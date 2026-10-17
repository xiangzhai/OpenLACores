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

module mmu_port #(
    parameter IS_FETCH = 0
)(
    input  wire           clk,
    input  wire           reset,
    input  wire           kill,

    input  wire           cpu_req_vld,
    input  wire           cpu_req_write,
    input  wire [ 31: 0]  cpu_req_vaddr,

    input  wire           cache_req_rdy,

    input  wire [  1: 0]  csr_plv,
    input  wire           csr_da,
    input  wire           csr_pg,
    input  wire [  1: 0]  csr_datf,
    input  wire [  1: 0]  csr_datm,
    input  wire [  9: 0]  csr_asid,
    input  wire [ 31: 0]  csr_dmw0,
    input  wire [ 31: 0]  csr_dmw1,
    input  wire           csr_ptw_en,

    input  wire           tlb_lookup_hit,
    input  wire [ 31: 0]  tlb_lookup_paddr,
    input  wire           tlb_lookup_dirty,
    input  wire [  1: 0]  tlb_lookup_plv,
    input  wire [  1: 0]  tlb_lookup_mat,

    input  wire           port_ptw_req_rdy,

    input  wire           port_ptw_resp_vld,
    input  wire [ 31: 0]  port_ptw_resp_vaddr,
    input  wire [  9: 0]  port_ptw_resp_asid,
    input  wire [ 19: 0]  port_ptw_resp_ppn,
    input  wire [  5: 0]  port_ptw_resp_ps,
    input  wire           port_ptw_resp_global,
    input  wire           port_ptw_resp_dirty,
    input  wire [  1: 0]  port_ptw_resp_plv,
    input  wire [  1: 0]  port_ptw_resp_mat,
    input  wire           port_ptw_resp_page_vld,
    input  wire           port_ptw_resp_bus_err,

    output wire           cpu_req_rdy,
    output wire           cpu_expt_vld,
    output wire [  5: 0]  cpu_expt_code,
    output wire           cpu_expt_write,

    output wire           cache_req_vld,
    output wire           cache_req_wait,
    output wire [ 31: 0]  cache_req_vaddr,
    output wire [ 31: 0]  cache_req_paddr,
    output wire [  1: 0]  cache_req_mat,
    output wire           cache_xlat_vld,
    output wire           cache_xlat_cancel,
    output wire [ 31: 0]  cache_xlat_paddr,
    output wire [  1: 0]  cache_xlat_mat,

    output wire           tlb_lookup_vld,
    output wire [ 31: 0]  tlb_lookup_vaddr,
    output wire [  9: 0]  tlb_lookup_asid,

    output wire           port_ptw_req_vld,
    output wire           port_ptw_req_write,
    output wire [ 31: 0]  port_ptw_req_vaddr,
    output wire [  9: 0]  port_ptw_req_asid,

    output wire           port_fill_vld,
    output wire [ 31: 0]  port_fill_vaddr,
    output wire [ 19: 0]  port_fill_ppn,
    output wire [  5: 0]  port_fill_ps,
    output wire [  9: 0]  port_fill_asid,
    output wire           port_fill_global,
    output wire           port_fill_dirty,
    output wire [  1: 0]  port_fill_plv,
    output wire [  1: 0]  port_fill_mat,

    output wire           port_auto_inv_vld,
    output wire [ 31: 0]  port_auto_inv_vaddr,
    output wire [  9: 0]  port_auto_inv_asid
);

//============================================================//
//                Local Parameter Declarations
//============================================================//

localparam PORT_IDLE    = 2'd0;
localparam PORT_LOOKUP  = 2'd1;
localparam PORT_PTW     = 2'd2;
localparam PORT_REPLAY  = 2'd3;

localparam EXCODE_PIL   = 6'd1;
localparam EXCODE_PIS   = 6'd2;
localparam EXCODE_PIF   = 6'd3;
localparam EXCODE_PME   = 6'd4;
localparam EXCODE_PPI   = 6'd7;
localparam EXCODE_BERR  = 6'h1a;
localparam EXCODE_TLBR  = 6'h3f;

//============================================================//
//                     Regs Declarations
//============================================================//

reg [  1: 0] state_r;
reg [  1: 0] state_nxt;
reg          write_r;
reg [ 31: 0] vaddr_r;
reg [  1: 0] plv_r;
reg [  9: 0] asid_r;
reg [ 31: 0] replay_paddr_r;
reg [  1: 0] replay_mat_r;
reg          drop_r;

//============================================================//
//                     Wire Declarations
//============================================================//

wire          cache_req_fire;
wire          pending_kill;
wire          paging_mode;
wire          dmw0_plv_en;
wire          dmw1_plv_en;
wire          dmw0_hit;
wire          dmw1_hit;
wire          dmw_hit;
wire [ 31: 0] dmw_paddr;
wire [  1: 0] dmw_mat;
wire          mapped_lookup;
wire          tlb_plv_fault;
wire          tlb_dirty_fault;
wire          tlb_fault;
wire          tlb_miss;
wire          fast_success;
wire [ 31: 0] fast_paddr;
wire [  1: 0] fast_mat;
wire          lookup_terminal_fault;
wire [  5: 0] lookup_expt_code;

wire          ptw_plv_fault;
wire          ptw_dirty_fault;
wire          ptw_success;
wire          ptw_fault;
wire [  5: 0] ptw_expt_code;
wire [ 31: 0] ptw_paddr;

function [31: 0] make_paddr;
    input [19: 0] ppn;
    input [31: 0] vaddr;
    input [ 5: 0] ps;
    reg   [31: 0] mask;
    begin
        if (ps <= 6'd12) begin
            mask = 32'h0000_0FFF;
        end
        else if (ps >= 6'd32) begin
            mask = 32'hFFFF_FFFF;
        end
        else begin
            mask = (32'h1 << ps) - 32'h1;
        end
        make_paddr = ({ppn, 12'd0} & ~mask) | (vaddr & mask);
    end
endfunction


//------------------------------------------------------------//
//                     Request Ownership
//------------------------------------------------------------//

// A kill blocks a request that has not crossed the address handshake. Once an
// LSU request is accepted, it is older than a later pipeline flush and remains
// owned by this port until translation/replay completes. IFU requests remain
// cancelable because a redirect can invalidate an accepted speculative fetch.
assign pending_kill           =  IS_FETCH && kill;
assign cache_req_vld          =  (state_r == PORT_IDLE) ? cpu_req_vld && !kill :
                                 (state_r == PORT_REPLAY) ? !pending_kill && !drop_r :
                                 1'b0;
assign cache_req_fire         =  cache_req_vld && cache_req_rdy;
assign cache_req_wait         =  state_r == PORT_IDLE;
assign cache_req_vaddr        =  state_r == PORT_REPLAY ? vaddr_r : cpu_req_vaddr;
assign cache_req_paddr        =  state_r == PORT_REPLAY ? replay_paddr_r : cpu_req_vaddr;
assign cache_req_mat          =  state_r == PORT_REPLAY ? replay_mat_r : 2'b0;

//------------------------------------------------------------//
//                 Direct and DMW Translation
//------------------------------------------------------------//

assign paging_mode            =  !csr_da && csr_pg;

assign dmw0_plv_en            =  ((plv_r == 2'd0) && csr_dmw0[0])
                                 || ((plv_r == 2'd1) && csr_dmw0[1])
                                 || ((plv_r == 2'd2) && csr_dmw0[2])
                                 || ((plv_r == 2'd3) && csr_dmw0[3]);
assign dmw1_plv_en            =  ((plv_r == 2'd0) && csr_dmw1[0])
                                 || ((plv_r == 2'd1) && csr_dmw1[1])
                                 || ((plv_r == 2'd2) && csr_dmw1[2])
                                 || ((plv_r == 2'd3) && csr_dmw1[3]);
assign dmw0_hit               =  paging_mode && dmw0_plv_en
                                 && (vaddr_r[31:29] == csr_dmw0[31:29]);
assign dmw1_hit               =  paging_mode && dmw1_plv_en
                                 && (vaddr_r[31:29] == csr_dmw1[31:29]);
assign dmw_hit                =  dmw0_hit || dmw1_hit;
assign dmw_paddr              =  dmw0_hit ? {csr_dmw0[27:25], vaddr_r[28:0]}
                                 : {csr_dmw1[27:25], vaddr_r[28:0]};
assign dmw_mat                =  dmw0_hit ? csr_dmw0[5:4] : csr_dmw1[5:4];

//------------------------------------------------------------//
//                        L1TLB Lookup
//------------------------------------------------------------//

assign mapped_lookup          =  paging_mode && !dmw_hit;
assign tlb_lookup_vld         =  (state_r == PORT_LOOKUP) && mapped_lookup
                                 && !pending_kill;
assign tlb_lookup_vaddr       =  vaddr_r;
assign tlb_lookup_asid        =  asid_r;

assign tlb_plv_fault          =  tlb_lookup_hit && (plv_r > tlb_lookup_plv);
assign tlb_dirty_fault        =  tlb_lookup_hit && write_r && !tlb_lookup_dirty;
assign tlb_fault              =  mapped_lookup && (tlb_plv_fault || tlb_dirty_fault);
assign tlb_miss               =  mapped_lookup && !tlb_lookup_hit;

assign fast_success           =  !paging_mode || dmw_hit
                                 || (mapped_lookup && tlb_lookup_hit && !tlb_fault);
assign fast_paddr             =  !paging_mode ? vaddr_r :
                                 dmw_hit       ? dmw_paddr :
                                                 tlb_lookup_paddr;
assign fast_mat               =  !paging_mode ? (IS_FETCH ? csr_datf : csr_datm) :
                                 dmw_hit       ? dmw_mat :
                                                 tlb_lookup_mat;

assign lookup_terminal_fault  =  tlb_fault || (tlb_miss && !csr_ptw_en);
assign lookup_expt_code       =  tlb_plv_fault   ? EXCODE_PPI :
                                 tlb_dirty_fault ? EXCODE_PME : EXCODE_TLBR;

//------------------------------------------------------------//
//                     Speculation Result
//------------------------------------------------------------//

assign cache_xlat_vld         =  (state_r == PORT_LOOKUP) && fast_success
                                 && !pending_kill;
assign cache_xlat_cancel      =  (state_r == PORT_LOOKUP)
                                 && (!fast_success || pending_kill);
assign cache_xlat_paddr       =  fast_paddr;
assign cache_xlat_mat         =  fast_mat;

//------------------------------------------------------------//
//                        PTW Request
//------------------------------------------------------------//

assign port_ptw_req_vld       =  (state_r == PORT_LOOKUP) && tlb_miss
                                 && csr_ptw_en && !pending_kill;
assign port_ptw_req_write     =  write_r;
assign port_ptw_req_vaddr     =  vaddr_r;
assign port_ptw_req_asid      =  asid_r;

//------------------------------------------------------------//
//                        PTW Response
//------------------------------------------------------------//

assign ptw_plv_fault          =  port_ptw_resp_page_vld
                                 && (plv_r > port_ptw_resp_plv);
assign ptw_dirty_fault        =  port_ptw_resp_page_vld && write_r
                                 && !port_ptw_resp_dirty;
assign ptw_success            =  port_ptw_resp_page_vld && !port_ptw_resp_bus_err
                                 && !ptw_plv_fault && !ptw_dirty_fault;
assign ptw_fault              =  port_ptw_resp_bus_err || !port_ptw_resp_page_vld
                                 || ptw_plv_fault || ptw_dirty_fault;
assign ptw_expt_code          =  port_ptw_resp_bus_err ? EXCODE_BERR :
                                 ptw_plv_fault          ? EXCODE_PPI  :
                                 ptw_dirty_fault        ? EXCODE_PME  :
                                 IS_FETCH               ? EXCODE_PIF  :
                                 write_r                ? EXCODE_PIS  :
                                                          EXCODE_PIL;
assign ptw_paddr              =  make_paddr(port_ptw_resp_ppn, port_ptw_resp_vaddr,
                                             port_ptw_resp_ps);

//------------------------------------------------------------//
//                    Upstream Completion
//------------------------------------------------------------//

// The upstream ready is an address-accept handshake. Translation completion
// is carried independently by cache_xlat_* or cpu_expt_vld. A PTW replay is
// owned by this port and must not acknowledge the next upstream request.
assign cpu_req_rdy            =  (state_r == PORT_IDLE) && cache_req_fire;

assign cpu_expt_vld           =  ((state_r == PORT_LOOKUP) && !pending_kill
                                 && lookup_terminal_fault)
                                || ((state_r == PORT_PTW) && port_ptw_resp_vld
                                    && !drop_r && !pending_kill && ptw_fault);
assign cpu_expt_code          =  (state_r == PORT_LOOKUP) ? lookup_expt_code
                                 : ptw_expt_code;
assign cpu_expt_write         =  write_r;

//------------------------------------------------------------//
//                    Refill and Recovery
//------------------------------------------------------------//

assign port_fill_vld          =  (state_r == PORT_PTW) && port_ptw_resp_vld
                                 && !drop_r && !pending_kill && ptw_success;
assign port_fill_vaddr        =  port_ptw_resp_vaddr;
assign port_fill_ppn          =  port_ptw_resp_ppn;
assign port_fill_ps           =  port_ptw_resp_ps;
assign port_fill_asid         =  port_ptw_resp_asid;
assign port_fill_global       =  port_ptw_resp_global;
assign port_fill_dirty        =  port_ptw_resp_dirty;
assign port_fill_plv          =  port_ptw_resp_plv;
assign port_fill_mat          =  port_ptw_resp_mat;

assign port_auto_inv_vld      =  (state_r == PORT_LOOKUP) && mapped_lookup
                                 && tlb_dirty_fault && !pending_kill;
assign port_auto_inv_vaddr    =  vaddr_r;
assign port_auto_inv_asid     =  asid_r;

//------------------------------------------------------------//
//                       State Machine
//------------------------------------------------------------//

always @ ( state_r
           or cache_req_fire
           or pending_kill
           or fast_success
           or lookup_terminal_fault
           or tlb_miss
           or csr_ptw_en
           or port_ptw_req_rdy
           or port_ptw_resp_vld
           or drop_r
           or ptw_success
         )
begin
    state_nxt = PORT_IDLE;

    case(state_r)
        PORT_IDLE: begin
            if(cache_req_fire) begin
                state_nxt = PORT_LOOKUP;
            end
            else begin
                state_nxt = PORT_IDLE;
            end
        end
        PORT_LOOKUP: begin
            if(pending_kill || fast_success || lookup_terminal_fault) begin
                state_nxt = PORT_IDLE;
            end
            else if(tlb_miss && csr_ptw_en && port_ptw_req_rdy) begin
                state_nxt = PORT_PTW;
            end
            else begin
                state_nxt = PORT_LOOKUP;
            end
        end
        PORT_PTW: begin
            if(port_ptw_resp_vld) begin
                if(drop_r || pending_kill || !ptw_success) begin
                    state_nxt = PORT_IDLE;
                end
                else begin
                    state_nxt = PORT_REPLAY;
                end
            end
            else begin
                state_nxt = PORT_PTW;
            end
        end
        PORT_REPLAY: begin
            if(pending_kill || cache_req_fire) begin
                state_nxt = PORT_IDLE;
            end
            else begin
                state_nxt = PORT_REPLAY;
            end
        end
        default: begin
            state_nxt = PORT_IDLE;
        end
    endcase
end

//------------------------------------------------------------//
//                  Sequential State Update
//------------------------------------------------------------//
always @ ( posedge clk )
begin
    if(reset) begin
        state_r <= PORT_IDLE;
    end
    else begin
        state_r        <= state_nxt;
    end
end

//------------------------------------------------------------//
//                       Payload State
//------------------------------------------------------------//

always @ ( posedge clk )
begin
    if((state_r == PORT_IDLE) && cache_req_fire) begin
        write_r <= cpu_req_write;
        vaddr_r <= cpu_req_vaddr;
        plv_r   <= csr_plv;
        asid_r  <= csr_asid;
    end

    if((state_r == PORT_PTW) && port_ptw_resp_vld && ptw_success
       && !drop_r && !pending_kill) begin
        replay_paddr_r <= ptw_paddr;
        replay_mat_r   <= port_ptw_resp_mat;
    end
end

//------------------------------------------------------------//
//                         Drop State
//------------------------------------------------------------//
always @ ( posedge clk )
begin
    if(reset) begin
        drop_r <= 1'b0;
    end
    else if((state_r == PORT_IDLE) && cache_req_fire) begin
        drop_r         <= 1'b0;
    end
    else if((state_r == PORT_PTW) && pending_kill) begin
        drop_r         <= 1'b1;
    end
    else if((state_r == PORT_PTW) && port_ptw_resp_vld) begin
        drop_r         <= 1'b0;
    end
end

endmodule
`endif
