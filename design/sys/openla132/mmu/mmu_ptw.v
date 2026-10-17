// ------------------------------------------------------------------------------------//
//  Copyright (c) 2026 Loongson Technology Corporation Limited.
//
//  OpenLACores is licensed under Mulan PSL v2.
// 
//  You can use this software according to the terms and conditions of the Mulan PSL v2.
//
//  You may obtain a copy of Mulan PSL v2 at:
//           http://license.coscl.org.cn/MulanPSL2
// 
//  THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY
//  KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
//  NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// 
//  See the Mulan PSL v2 for more details.
// ------------------------------------------------------------------------------------//

`ifdef CONFIG_MMU
`include "openla132_global.h"

module mmu_ptw (
    input  wire           clk,
    input  wire           reset,

    input  wire           ptw_req_vld,
    input  wire           ptw_req_port,
    input  wire           ptw_req_write,
    input  wire [ 31: 0]  ptw_req_vaddr,
    input  wire [  9: 0]  ptw_req_asid,

    input  wire           ptw_resp_rdy,

    input  wire [ 31: 0]  csr_pgdl,
    input  wire [ 31: 0]  csr_pgdh,
    input  wire [ 31: 0]  csr_dmw0,
    input  wire [ 31: 0]  csr_dmw1,
    input  wire [ 31: 0]  csr_pwcl,
    input  wire [ 31: 0]  csr_pwch,

    input  wire           ptw_mem_req_rdy,
    input  wire           ptw_mem_resp_vld,
    input  wire [ 31: 0]  ptw_mem_resp_data,
    input  wire           ptw_mem_resp_err,

    output wire           ptw_req_rdy,

    output wire           ptw_resp_vld,
    output wire           ptw_resp_port,
    output wire [ 31: 0]  ptw_resp_vaddr,
    output wire [  9: 0]  ptw_resp_asid,
    output wire [ 19: 0]  ptw_resp_ppn,
    output wire [  5: 0]  ptw_resp_ps,
    output wire           ptw_resp_global,
    output wire           ptw_resp_dirty,
    output wire [  1: 0]  ptw_resp_plv,
    output wire [  1: 0]  ptw_resp_mat,
    output wire           ptw_resp_page_vld,
    output wire           ptw_resp_bus_err,

    output wire           ptw_mem_req_vld,
    output wire [ 31: 0]  ptw_mem_req_paddr
);

//============================================================//
//                Local Parameter Declarations
//============================================================//

localparam PTW_IDLE      = 3'd0;
localparam PTW_DIR_REQ   = 3'd1;
localparam PTW_DIR_WAIT  = 3'd2;
localparam PTW_PTE_REQ   = 3'd3;
localparam PTW_PTE_WAIT  = 3'd4;
localparam PTW_RESP      = 3'd5;

//============================================================//
//                     Regs Declarations
//============================================================//

reg [  2: 0] state_r;
reg [  2: 0] state_nxt;
reg          port_r;
reg          write_r;
reg [ 31: 0] vaddr_r;
reg [  9: 0] asid_r;
reg [ 31: 0] pwcl_r;
reg [ 31: 0] pwch_r;
reg [  2: 0] level_r;
reg [ 31: 0] dir_addr_r;
reg [ 31: 0] pte_addr_r;
reg [ 31: 0] pte_r;
reg          bus_err_r;

//============================================================//
//                     Wire Declarations
//============================================================//

wire          req_fire;
wire          mem_req_fire;
wire [ 31: 0] selected_pgd;
wire [ 31: 0] selected_pgd_phys;
wire [  5: 0] req_ptbase;
wire [  5: 0] req_ptwidth;
wire [ 31: 0] pgd_base_aligned;
wire [  2: 0] req_first_level;

wire [  5: 0] ptbase_r;
wire [  5: 0] ptwidth_r;
wire [ 31: 0] dir_resp_phys;
wire [ 31: 0] dir_resp_base;
wire [  2: 0] dir_next_level;
wire          dir_entry_empty;
wire          dir_entry_huge;
wire          ps_supported;

wire          pte_present;
wire          pte_write_ok;

//============================================================//
//                       Page Size Helpers
//============================================================//

function [31: 0] bit_mask;
    input [5: 0] width;
    begin
        if (width >= 6'd32) begin
            bit_mask = 32'hFFFF_FFFF;
        end
        else if (width == 6'd0) begin
            bit_mask = 32'd0;
        end
        else begin
            bit_mask = (32'h1 << width) - 32'h1;
        end
    end
endfunction

function [31: 0] align_base;
    input [31: 0] base;
    input [ 5: 0] ps;
    begin
        align_base = base & ~bit_mask(ps);
    end
endfunction

function [31: 0] dir_index;
    input [31: 0] vaddr;
    input [ 5: 0] base;
    input [ 5: 0] width;
    begin
        if (base >= 6'd32) begin
            dir_index = 32'd0;
        end
        else begin
            dir_index = (vaddr >> base) & bit_mask(width);
        end
    end
endfunction

// LA32 page tables hold 4-byte entries, while PWCL/PWCH widths are
// programmed using the architectural 8-byte slot convention. Expose the
// additional index bit for 32-bit entries, matching loong-emu.
function [5: 0] eff_width;
    input [5: 0] width;
    begin
        if (width == 6'd0) begin
            eff_width = 6'd0;
        end
        else begin
            eff_width = width + 6'd1;
        end
    end
endfunction

function [5: 0] level_base;
    input [31: 0] pwcl;
    input [31: 0] pwch;
    input [ 2: 0] level;
    begin
        case (level)
            3'd1:    level_base = {1'b0, pwcl[14:10]};
            3'd2:    level_base = {1'b0, pwcl[24:20]};
            3'd3:    level_base = pwch[5:0];
            3'd4:    level_base = pwch[17:12];
            default: level_base = 6'd0;
        endcase
    end
endfunction

function [5: 0] level_width;
    input [31: 0] pwcl;
    input [31: 0] pwch;
    input [ 2: 0] level;
    reg   [ 5: 0] raw_width;
    begin
        case (level)
            3'd1:    raw_width = {1'b0, pwcl[19:15]};
            3'd2:    raw_width = {1'b0, pwcl[29:25]};
            3'd3:    raw_width = pwch[11:6];
            3'd4:    raw_width = pwch[23:18];
            default: raw_width = 6'd0;
        endcase
        level_width = eff_width(raw_width);
    end
endfunction

function [2: 0] first_level;
    input [31: 0] pwcl;
    input [31: 0] pwch;
    integer i;
    begin
        first_level = 3'd0;
        for (i = 1; i <= 4; i = i + 1) begin
            if (level_width(pwcl, pwch, i) != 6'd0) begin
                first_level = i;
            end
        end
    end
endfunction

function [2: 0] next_level;
    input [31: 0] pwcl;
    input [31: 0] pwch;
    input [ 2: 0] level;
    integer i;
    begin
        next_level = 3'd0;
        for (i = 1; i < level; i = i + 1) begin
            if (level_width(pwcl, pwch, i) != 6'd0) begin
                next_level = i;
            end
        end
    end
endfunction

// LA32S stores DMW virtual pointers in PGD CSRs and directory entries.
function [31: 0] dmw_translate;
    input [31: 0] addr;
    input [31: 0] dmw0;
    input [31: 0] dmw1;
    reg   [ 2: 0] vseg;
    begin
        vseg = addr[31:29];
        if (dmw0[0] && (vseg == dmw0[31:29])) begin
            dmw_translate = {dmw0[27:25], addr[28:0]};
        end
        else if (dmw1[0] && (vseg == dmw1[31:29])) begin
            dmw_translate = {dmw1[27:25], addr[28:0]};
        end
        else begin
            dmw_translate = addr;
        end
    end
endfunction

//------------------------------------------------------------//
//                 Request Address Formation
//------------------------------------------------------------//

assign selected_pgd           =  ptw_req_vaddr[31] ? csr_pgdh : csr_pgdl;
assign selected_pgd_phys      =  dmw_translate(selected_pgd, csr_dmw0, csr_dmw1);
assign req_ptbase             =  {1'b0, csr_pwcl[4:0]};
assign req_ptwidth            =  eff_width({1'b0, csr_pwcl[9:5]});
assign pgd_base_aligned       =  align_base(selected_pgd_phys, req_ptbase);
assign req_first_level        =  first_level(csr_pwcl, csr_pwch);

assign ptbase_r               =  {1'b0, pwcl_r[4:0]};
assign ptwidth_r              =  eff_width({1'b0, pwcl_r[9:5]});
assign dir_resp_phys          =  dmw_translate(ptw_mem_resp_data, csr_dmw0, csr_dmw1);
assign dir_resp_base          =  align_base(dir_resp_phys, ptbase_r);
assign dir_next_level         =  next_level(pwcl_r, pwch_r, level_r);
assign dir_entry_empty        =  ((ptw_mem_resp_data & ~bit_mask(ptbase_r)) == 32'd0);
assign dir_entry_huge         =  ptw_mem_resp_data[6];

// Only the base page sizes advertised in PRCFG2 are accepted.
assign ps_supported           =  (ptbase_r == 6'd12)
                              || (ptbase_r == 6'd14)
                              || (ptbase_r == 6'd16);

assign pte_present            =  pte_r[7] || pte_r[0];
assign pte_write_ok           =  pte_r[29];

//------------------------------------------------------------//
//                         Handshakes
//------------------------------------------------------------//

assign ptw_req_rdy            =  state_r == PTW_IDLE;
assign req_fire               =  ptw_req_vld && ptw_req_rdy;
assign ptw_mem_req_vld        =  (state_r == PTW_DIR_REQ)
                              || (state_r == PTW_PTE_REQ);
assign ptw_mem_req_paddr      =  state_r == PTW_DIR_REQ ? dir_addr_r : pte_addr_r;
assign mem_req_fire           =  ptw_mem_req_vld && ptw_mem_req_rdy;

//------------------------------------------------------------//
//                    Response Projection
//------------------------------------------------------------//

assign ptw_resp_vld           =  state_r == PTW_RESP;
assign ptw_resp_port          =  port_r;
assign ptw_resp_vaddr         =  vaddr_r;
assign ptw_resp_asid          =  asid_r;
assign ptw_resp_ppn           =  pte_r[27:8];
assign ptw_resp_ps            =  ptbase_r;
assign ptw_resp_global        =  pte_r[6];
assign ptw_resp_dirty         =  pte_r[1]
                              || (write_r && pte_present && pte_write_ok);
assign ptw_resp_plv           =  pte_r[3:2];
assign ptw_resp_mat           =  pte_r[5:4];
assign ptw_resp_page_vld      =  pte_present && ps_supported;
assign ptw_resp_bus_err       =  bus_err_r;

//------------------------------------------------------------//
//                       State Machine
//------------------------------------------------------------//

always @ ( state_r
           or req_fire
           or req_first_level
           or mem_req_fire
           or ptw_mem_resp_vld
           or ptw_mem_resp_err
           or dir_entry_empty
           or dir_entry_huge
           or dir_next_level
           or ptw_resp_rdy
         )
begin
    state_nxt = PTW_IDLE;

    case(state_r)
        PTW_IDLE: begin
            if(req_fire) begin
                if(req_first_level != 3'd0) begin
                    state_nxt = PTW_DIR_REQ;
                end
                else begin
                    state_nxt = PTW_PTE_REQ;
                end
            end
            else begin
                state_nxt = PTW_IDLE;
            end
        end
        PTW_DIR_REQ: begin
            if(mem_req_fire) begin
                state_nxt = PTW_DIR_WAIT;
            end
            else begin
                state_nxt = PTW_DIR_REQ;
            end
        end
        PTW_DIR_WAIT: begin
            if(ptw_mem_resp_vld) begin
                if(ptw_mem_resp_err || dir_entry_empty || dir_entry_huge) begin
                    state_nxt = PTW_RESP;
                end
                else if(dir_next_level != 3'd0) begin
                    state_nxt = PTW_DIR_REQ;
                end
                else begin
                    state_nxt = PTW_PTE_REQ;
                end
            end
            else begin
                state_nxt = PTW_DIR_WAIT;
            end
        end
        PTW_PTE_REQ: begin
            if(mem_req_fire) begin
                state_nxt = PTW_PTE_WAIT;
            end
            else begin
                state_nxt = PTW_PTE_REQ;
            end
        end
        PTW_PTE_WAIT: begin
            if(ptw_mem_resp_vld) begin
                state_nxt = PTW_RESP;
            end
            else begin
                state_nxt = PTW_PTE_WAIT;
            end
        end
        PTW_RESP: begin
            if(ptw_resp_rdy) begin
                state_nxt = PTW_IDLE;
            end
            else begin
                state_nxt = PTW_RESP;
            end
        end
        default: begin
            state_nxt = PTW_IDLE;
        end
    endcase
end

//------------------------------------------------------------//
//                  Sequential State Update
//------------------------------------------------------------//
always @ ( posedge clk )
begin
    if(reset) begin
        state_r <= PTW_IDLE;
    end
    else begin
        state_r   <= state_nxt;
    end
end

//------------------------------------------------------------//
//                       Payload State
//------------------------------------------------------------//

always @ ( posedge clk )
begin
    if(reset) begin
        port_r     <= 1'b0;
        write_r    <= 1'b0;
        vaddr_r    <= 32'd0;
        asid_r     <= 10'd0;
        pwcl_r     <= 32'd0;
        pwch_r     <= 32'd0;
        level_r    <= 3'd0;
        dir_addr_r <= 32'd0;
        pte_addr_r <= 32'd0;
        pte_r      <= 32'd0;
        bus_err_r  <= 1'b0;
    end
    else begin
        if(req_fire) begin
            port_r     <= ptw_req_port;
            write_r    <= ptw_req_write;
            vaddr_r    <= ptw_req_vaddr;
            asid_r     <= ptw_req_asid;
            pwcl_r     <= csr_pwcl;
            pwch_r     <= csr_pwch;
            level_r    <= req_first_level;
            bus_err_r  <= 1'b0;

            if(req_first_level != 3'd0) begin
                dir_addr_r <= pgd_base_aligned
                            | (dir_index(ptw_req_vaddr,
                                         level_base(csr_pwcl, csr_pwch, req_first_level),
                                         level_width(csr_pwcl, csr_pwch, req_first_level)) << 2);
            end
            else begin
                pte_addr_r <= pgd_base_aligned
                            | (dir_index(ptw_req_vaddr, req_ptbase, req_ptwidth) << 2);
            end
        end

        if((state_r == PTW_DIR_WAIT) && ptw_mem_resp_vld) begin
            if(ptw_mem_resp_err || dir_entry_empty || dir_entry_huge) begin
                pte_r      <= 32'd0;
                bus_err_r  <= ptw_mem_resp_err;
            end
            else if(dir_next_level != 3'd0) begin
                level_r    <= dir_next_level;
                dir_addr_r <= dir_resp_base
                            | (dir_index(vaddr_r,
                                         level_base(pwcl_r, pwch_r, dir_next_level),
                                         level_width(pwcl_r, pwch_r, dir_next_level)) << 2);
            end
            else begin
                level_r    <= 3'd0;
                pte_addr_r <= dir_resp_base
                            | (dir_index(vaddr_r, ptbase_r, ptwidth_r) << 2);
            end
        end

        if((state_r == PTW_PTE_WAIT) && ptw_mem_resp_vld) begin
            pte_r      <= ptw_mem_resp_err ? 32'd0 : ptw_mem_resp_data;
            bus_err_r  <= ptw_mem_resp_err;
        end
    end
end

endmodule
`endif
