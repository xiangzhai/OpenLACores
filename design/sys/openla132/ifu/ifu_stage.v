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

`include "openla132_global.h"
module ifu_stage #(
    parameter HAS_BTB = -1  // 0 or 1
) (
    input  wire                                         clk_g,
    input  wire                                         reset,
    input  wire                                         data_reset,
    input  wire [                               31: 0]  boot_pc,

    input  wire                                         idu_ifu_allowin,
    input  wire [                               32: 0]  rtu_ifu_redirect_bus,
    input  wire [                               35: 0]  idu_ifu_branch_bus,
    input  wire [  `OPEN132_CSR_IFU_CTRL_BUS_WIDTH-1: 0]  csr_ifu_ctrl_bus,
    input  wire [`OPEN132_CACHE_IFU_RESP_BUS_WIDTH-1: 0]  cache_ifu_resp_bus,

    output wire [ `OPEN132_IFU_CACHE_REQ_BUS_WIDTH-1: 0]  ifu_cache_req_bus,
    output wire                                         ifu_idu_inst_valid,
    output wire [  `OPEN132_IFU_IDU_INST_BUS_WIDTH-1: 0]  ifu_idu_inst_bus,
    output wire [                               31: 0]  ifu_idu_seq_pc,
    output wire [                               31: 0]  ifu_jtag_pc,
    output wire [                               31: 0]  ifu_bpu_pc
    ,
    input  wire [  `OPEN132_BPU_IFU_PRED_BUS_WIDTH-1: 0]  bpu_ifu_pred_bus,
    output wire [  `OPEN132_IFU_IDU_PRED_BUS_WIDTH-1: 0]  ifu_idu_pred_bus,
    input  wire [                               32: 0]  idu_ifu_return_bus
`ifdef OPEN132_HAS_LJTAG
    ,
    input  wire                                         lsu_ifu_debug_map_valid
`endif
);

// fetch state
localparam FT_SEND_PC  = 2'b01;  // send pc
localparam FT_SEND_NPC = 2'b11;  // send next-pc
localparam FT_NO_SEND  = 2'b10;  // no send

//============================================================//
//                     Regs Declarations
//============================================================//

reg [ 31: 0] pc;
reg [  1: 0] stall_whichbus;
reg [ 31: 0] stall_inst;
reg          stall_inst_valid;
reg          stall_inst_err;
`ifdef CONFIG_MMU
reg          stall_mmu_expt;
reg [  5: 0] stall_mmu_code;
`endif
reg [  1: 0] stall2_whichbus;    // npc inst back
reg [ 31: 0] stall2_inst;
reg          stall2_inst_valid;
reg          stall2_inst_err;
`ifdef CONFIG_MMU
reg          stall2_mmu_expt;
reg [  5: 0] stall2_mmu_code;
`endif
reg          cancel_nextpc;

reg          no_rst;

// register jbr taken/target
reg          jbr_taken_r;
reg [ 31: 0] jbr_target_r;

reg [  1: 0] ft_st;
reg [  1: 0] ft_st_nxt;  // always @(*)

//============================================================//
//                     Wire Declarations
//============================================================//

wire          lisa_da_vaddr_chk;
wire [  1: 0] lisa_dacm_vaddr_chk;
wire [  7: 0] lisa_segplv_vaddr_chk;
wire [  7: 0] lisa_segca_dev_vaddr_chk;
wire [ 31: 0] vaddr_vaddr_chk;
wire          dbgm_vaddr_chk;
wire          user_mode_vaddr_chk;
wire          ade_priv_vaddr_chk;

wire [ 31: 0] ex_pc;
wire          ex_valid;

wire [ 31: 0] jbr_target;
wire          jbr_taken;
wire          de_stall_ft;
wire          de_stall_npc;
wire          de_jbr_last;   // inst jbr last clock

wire [  7: 0] lisa_segplv;
wire          lisa_da;
wire          user_mode;

wire          fetchreq_ready;
wire          fetchdata_ready;
wire          fetchdata_err;
`ifdef CONFIG_MMU
wire          fetch_mmu_expt_vld;
wire [  5: 0] fetch_mmu_expt_code;
`endif
wire [  1: 0] fetch_whichbus;
wire [ 31: 0] fetch_rdata;

wire          fetch_req;    // fetch requset to send address
wire          fetch_dbgm;
wire [ 31: 0] fetch_vaddr;

wire          fetch_validout;
wire [  1: 0] ifu_idu_whichbus;
wire          fetch_npc_jbr;     // next-pc is jbr taken.
wire [ 31: 0] fetch_inst;
wire [ 31: 0] fetch_pc;
wire [ 31: 0] fetch_follow_pc;
wire          fetch_ade;
wire          fetch_ex;
`ifdef CONFIG_MMU
wire [  5: 0] fetch_excode;
wire          fetch_resp_vld;
wire          fetch_mmu_expt;
`endif

wire          pred_valid;
wire          pred_brlo_hit;
wire          pred_jrlo_hit;
wire          pred_jrra;
wire [ 31: 0] pred_npc;
wire [  3: 0] pred_pos;
wire [  2: 0] pred_cnt;
wire          pred_cond;
wire          pred_tage_taken;
wire [`OPEN132_TAGE_GHR_WD-1: 0] pred_ghr;
wire          pred_taken_dir;   // final taken/not-taken direction of the prediction

// ra_bus
wire          de_ra_change;
wire [ 31: 0] de_ra_value;

wire          pc_allowin;
wire [ 31: 0] nextpc;

wire          cancel_nextpc_now;
wire [ 31: 0] vaddr;

wire          ade_priv;
wire          nalign;

wire          pred_taken;
wire          pred_jrra_taken;

wire          ft_send_pc;
wire          ft_send_npc;
wire          ft_no_send;

wire          npc_data_back;

wire          dbgm;  // debug memory

wire          fetch_ibe;
`ifdef CONFIG_MMU

`endif

//============================================================//
//                    Module Implementation
//============================================================//

//------------------------------------------------------------//
//                      Bus Connections
//------------------------------------------------------------//
//------------------------------------------------------------//
//                    rtu_ifu_redirect_bus
//------------------------------------------------------------//
// Instance Boundary Alias Mapping
// x_mmu_vaddr_check

assign lisa_da_vaddr_chk         =  lisa_da;
assign lisa_dacm_vaddr_chk       =  2'd0;
assign lisa_segplv_vaddr_chk     =  lisa_segplv;
assign lisa_segca_dev_vaddr_chk  =  8'd0;
assign vaddr_vaddr_chk           =  pc;
assign dbgm_vaddr_chk            =  dbgm;
assign user_mode_vaddr_chk       =  user_mode;
assign ade_priv                  =  ade_priv_vaddr_chk;

assign { ex_pc,
         ex_valid }  =  rtu_ifu_redirect_bus;
// End rtu_ifu_redirect_bus

//------------------------------------------------------------//
//                     idu_ifu_branch_bus
//------------------------------------------------------------//
assign { jbr_target,
         jbr_taken,
         de_stall_ft,
         de_stall_npc,
         de_jbr_last   }  =  idu_ifu_branch_bus;
// End idu_ifu_branch_bus

//------------------------------------------------------------//
//                      csr_ifu_ctrl_bus
//------------------------------------------------------------//
assign { lisa_segplv,  // 9:2
         lisa_da    ,  // 1
         user_mode  // 0
       }  =  csr_ifu_ctrl_bus;
// End csr_ifu_ctrl_bus

//------------------------------------------------------------//
//                     cache_ifu_resp_bus
//------------------------------------------------------------//

`ifdef CONFIG_MMU
assign { fetch_mmu_expt_vld,
         fetch_mmu_expt_code,
         fetchreq_ready,
`else
assign { fetchreq_ready,
`endif
         fetchdata_ready,
         fetchdata_err,
         fetch_whichbus,
         fetch_rdata    }  =  cache_ifu_resp_bus;
// End cache_ifu_resp_bus

//------------------------------------------------------------//
//                     ifu_cache_req_bus
//------------------------------------------------------------//
assign ifu_cache_req_bus  =  { fetch_req   ,
                               fetch_dbgm  ,
                               fetch_vaddr };
// End ifu_cache_req_bus

//------------------------------------------------------------//
//                      ifu_idu_inst_bus
//------------------------------------------------------------//

assign ifu_idu_inst_valid  =  fetch_validout;
assign ifu_idu_inst_bus    =  {
                                ifu_idu_whichbus,
                                fetch_npc_jbr,
                                fetch_inst,
                                fetch_pc,
                                fetch_follow_pc,
`ifdef CONFIG_MMU
                                fetch_excode,
`endif
                                fetch_ade,
                                fetch_ex   };
// End ifu_idu_inst_bus
//------------------------------------------------------------//
//                        bpu_ifu_bus
//------------------------------------------------------------//

assign {pred_valid,
        pred_brlo_hit,
        pred_jrlo_hit,
        pred_jrra,
        pred_npc,
        pred_pos,
        pred_cnt,
        pred_cond,
        pred_tage_taken,
        pred_ghr}  =  bpu_ifu_pred_bus&{`OPEN132_BPU_IFU_PRED_BUS_WIDTH{HAS_BTB}};

assign { de_ra_change,
         de_ra_value }  =  idu_ifu_return_bus;
// End bpu_ifu_bus

// End ifu_idu_pred_bus
assign ifu_idu_pred_bus  =  {pred_valid,
                              pred_brlo_hit,
                              pred_jrlo_hit,
                              pred_jrra,
                              pred_pos,
                              pred_cnt,
                              pred_cond,
                              pred_tage_taken,
                              pred_ghr
                            };
// End ifu_idu_pred_bus
// End Bus Connections

always @ ( posedge clk_g )
begin
    if(reset) begin
        no_rst <= 1'b0;
    end
    else if(!no_rst) begin
        no_rst <= 1'b1;
    end
end
always @ ( posedge clk_g )
begin
    if(reset) begin
        jbr_taken_r <= 1'b0;
    end
    else if(ex_valid) begin
        jbr_taken_r <= 1'b0;
    end
    else if(pc_allowin) begin
        jbr_taken_r <= 1'b0;
    end  // de_jbr last clock, must regiter jbr_taken, otherwise jbr_taken will be clear.
    else if(jbr_taken && de_jbr_last && !pc_allowin) begin
        jbr_taken_r <= 1'b1;
    end
end
always @ ( posedge clk_g )
begin
    if(data_reset) begin
        jbr_target_r <= 32'd0;
    end
    else if(jbr_taken && de_jbr_last && !pc_allowin) begin
        jbr_target_r <= jbr_target;
    end
end

// pc_stage control
assign pc_allowin            =  idu_ifu_allowin & fetch_validout;
assign ifu_idu_seq_pc[31:2]  =  pc[31:2] + 1'b1;
assign ifu_idu_seq_pc[1   ]  =  1'b0;
assign ifu_idu_seq_pc[0   ]  =  pc[0];
assign pred_taken_dir        =  pred_cond ? pred_tage_taken : (|pred_cnt[2:1]);
assign pred_taken            =  pred_valid && pred_taken_dir;
assign pred_jrra_taken       =  pred_valid && pred_taken_dir && pred_jrra;
assign nextpc                =  jbr_taken_r ? jbr_target_r :
                                  jbr_taken   ? jbr_target   :
                                  pred_taken  ? (pred_jrra ? de_ra_value : pred_npc) :
                                  ifu_idu_seq_pc;
always @ ( posedge clk_g )
begin
    if(reset) begin
        pc <= boot_pc;
    end
    else if(ex_valid) begin
        pc <= ex_pc;
    end
    else if(pc_allowin) begin
        pc <= nextpc | {31'b0,cancel_nextpc&&!(jbr_taken||jbr_taken_r)};
    end
end
always @ ( posedge clk_g )
begin
    if(reset) begin
        cancel_nextpc <= 1'b0;
    end
    else if(ex_valid) begin
        cancel_nextpc <= 1'b0;
    end
    else if(pc_allowin) begin
        cancel_nextpc <= 1'b0;
    end
    else if(cancel_nextpc_now) begin
        cancel_nextpc <= 1'b1;
    end
end

assign ft_send_pc   =  ft_st==FT_SEND_PC ;
assign ft_send_npc  =  ft_st==FT_SEND_NPC;
assign ft_no_send   =  ft_st==FT_NO_SEND ;

always @ ( posedge clk_g )
begin
    if(reset) begin
        ft_st <= FT_SEND_PC;
    end
    else if(ex_valid) begin
        ft_st <= FT_SEND_PC;
    end
    else begin
        ft_st <= ft_st_nxt;
    end
end

`ifdef CONFIG_MMU
assign npc_data_back  =  fetch_resp_vld && stall_inst_valid && ft_no_send;
`else
assign npc_data_back  =  fetchdata_ready&&stall_inst_valid&&ft_no_send;
`endif

always @ ( ft_st
           or fetchreq_ready
           or pc_allowin
         )
begin
    case(ft_st)
        FT_SEND_PC: begin
            if(fetchreq_ready) begin
                ft_st_nxt = FT_SEND_NPC;
            end
            else begin
                ft_st_nxt = FT_SEND_PC;
            end
        end
        FT_SEND_NPC: begin
            if(fetchreq_ready && pc_allowin) begin
                ft_st_nxt = FT_SEND_NPC;
            end
            else if(fetchreq_ready) begin
                ft_st_nxt = FT_NO_SEND;
            end
            else if(pc_allowin) begin
                ft_st_nxt = FT_SEND_PC;
            end
            else begin
                ft_st_nxt = FT_SEND_NPC;
            end
        end
        FT_NO_SEND: begin
            if(pc_allowin) begin
                ft_st_nxt = FT_SEND_NPC;
            end
            else begin
                ft_st_nxt = FT_NO_SEND;
            end
        end
        default: begin
            ft_st_nxt = FT_SEND_PC;
        end
    endcase
end

// vaddr
assign vaddr  =  ft_send_pc ? pc : nextpc;

mmu_vaddr_check x_mmu_vaddr_check (
    .lisa_da        (lisa_da_vaddr_chk       ),
    .lisa_dacm      (lisa_dacm_vaddr_chk     ),  // no cacre for fetch
    .lisa_segplv    (lisa_segplv_vaddr_chk   ),  // 1: can access by PLV3; 0: only access by PLV0
    .lisa_segca_dev (lisa_segca_dev_vaddr_chk),  // no care for fetch

    .vaddr          (vaddr_vaddr_chk         ),
    .dbgm           (dbgm_vaddr_chk          ),
    .user_mode      (user_mode_vaddr_chk     ),
    .addr_mem       (                        ),
    .ade_priv       (ade_priv_vaddr_chk      )
);
// fetch2ifc bus
assign fetch_req    =  no_rst && (ft_send_pc||ft_send_npc&&!de_stall_npc) &&
                         !de_stall_ft && !ex_valid;
assign fetch_dbgm   =  dbgm;
assign fetch_vaddr  =  {vaddr[31:2],2'd0};

// exception,use pc to generate addr error!
assign nalign     =  pc[1:0]==2'b10 || pc[0];
assign fetch_ade  =  ade_priv || nalign;

// stall instruction
always @ ( posedge clk_g )
begin
    if(reset || ex_valid) begin
        stall_inst_valid <= 1'b0;
    end
    else if(idu_ifu_allowin) begin
        stall_inst_valid <= npc_data_back || stall2_inst_valid;
    end
`ifdef CONFIG_MMU
    else if(fetch_resp_vld && (!ft_send_pc || fetch_mmu_expt_vld)) begin
`else
    else if(fetchdata_ready&&!ft_send_pc) begin
`endif
        stall_inst_valid <= 1'b1;
    end

    if(data_reset) begin
        stall_inst     <= 32'd0;
        stall_whichbus <= 2'd0;
        stall_inst_err <= 1'd0;
`ifdef CONFIG_MMU
        stall_mmu_expt <= 1'b0;
        stall_mmu_code <= 6'd0;
`endif
    end
`ifdef CONFIG_MMU
    else if(!idu_ifu_allowin && fetch_resp_vld && !stall_inst_valid
            || idu_ifu_allowin && npc_data_back) begin
        stall_inst     <= fetch_mmu_expt_vld ? 32'd0 : fetch_rdata;
        stall_whichbus <= fetch_mmu_expt_vld ? 2'd0 : fetch_whichbus;
`else
    else if(!idu_ifu_allowin&&fetchdata_ready&&!stall_inst_valid || idu_ifu_allowin&&npc_data_back) begin
        stall_inst     <= fetch_rdata;
        stall_whichbus <= fetch_whichbus;
`endif
        stall_inst_err <= fetchdata_err;
`ifdef CONFIG_MMU
        stall_mmu_expt <= fetch_mmu_expt_vld;
        stall_mmu_code <= fetch_mmu_expt_code;
`endif
    end
    else if(idu_ifu_allowin&&stall2_inst_valid) begin
        stall_inst     <= stall2_inst;
        stall_whichbus <= stall2_whichbus;
        stall_inst_err <= stall2_inst_err;
`ifdef CONFIG_MMU
        stall_mmu_expt <= stall2_mmu_expt;
        stall_mmu_code <= stall2_mmu_code;
`endif
    end
end
// stall instruction 2
always @ ( posedge clk_g )
begin
    if(reset || ex_valid) begin
        stall2_inst_valid <= 1'b0;
    end
    else if(idu_ifu_allowin) begin
        stall2_inst_valid <= 1'b0;
    end
    else if(npc_data_back) begin
        stall2_inst_valid <= 1'b1;
    end

    if(data_reset) begin
        stall2_inst     <= 32'd0;
        stall2_whichbus <= 2'd0;
        stall2_inst_err <= 1'd0;
`ifdef CONFIG_MMU
        stall2_mmu_expt <= 1'b0;
        stall2_mmu_code <= 6'd0;
`endif
    end
    else if(!idu_ifu_allowin&&npc_data_back) begin
`ifdef CONFIG_MMU
        stall2_inst     <= fetch_mmu_expt_vld ? 32'd0 : fetch_rdata;
        stall2_whichbus <= fetch_mmu_expt_vld ? 2'd0 : fetch_whichbus;
`else
        stall2_inst     <= fetch_rdata;
        stall2_whichbus <= fetch_whichbus;
`endif
        stall2_inst_err <= fetchdata_err;
`ifdef CONFIG_MMU
        stall2_mmu_expt <= fetch_mmu_expt_vld;
        stall2_mmu_code <= fetch_mmu_expt_code;
`endif
    end
end

// ifu_idu_inst_bus signals
`ifdef CONFIG_MMU
assign fetch_resp_vld    =  fetchdata_ready || fetch_mmu_expt_vld;
assign fetch_validout    =  stall_inst_valid
                            || fetch_resp_vld && (!ft_send_pc || fetch_mmu_expt_vld);
`else
assign fetch_validout    =  stall_inst_valid | (fetchdata_ready & ~ft_send_pc);
`endif
assign fetch_follow_pc   =  jbr_taken_r ? jbr_target_r : pc;
assign fetch_pc          =  pc;
`ifdef CONFIG_MMU
assign fetch_inst        =  stall_inst_valid ? stall_inst :
                              fetch_mmu_expt_vld ? 32'd0 : fetch_rdata;
`else
assign fetch_inst        =  stall_inst_valid ? stall_inst     : fetch_rdata;
`endif
assign fetch_npc_jbr     =  jbr_taken_r || jbr_taken;
assign ifu_idu_whichbus  =  stall_inst_valid ? stall_whichbus : fetch_whichbus;

assign fetch_ibe  =  stall_inst_valid ? stall_inst_err : fetchdata_err;
`ifdef CONFIG_MMU
assign fetch_mmu_expt  =  stall_inst_valid ? stall_mmu_expt
                                            : fetch_mmu_expt_vld;
assign fetch_excode    =  fetch_ade      ? 6'd8  :
                           fetch_mmu_expt ? (stall_inst_valid
                                             ? stall_mmu_code
                                             : fetch_mmu_expt_code) : 6'h1a;
assign fetch_ex        =  fetch_ade || fetch_ibe || fetch_mmu_expt;
`else
assign fetch_ex   =  fetch_ade || fetch_ibe;
`endif

// Debug and branch-predictor PC fanout
assign ifu_jtag_pc  =  pc;
assign ifu_bpu_pc   =  pc;

//------------------------------------------------------------//
//                           LJTAG
//------------------------------------------------------------//
`ifdef OPEN132_HAS_LJTAG
assign dbgm  =  (vaddr[31:20]==12'hdb0) && lsu_ifu_debug_map_valid;
`else
assign dbgm  =  1'b0;
`endif
// End LJTAG

// BTB return-address correction. HAS_BTB is a static configuration parameter.
generate
    if (HAS_BTB) begin: gen_has_btb
        assign cancel_nextpc_now = de_ra_change && pred_jrra_taken && !ft_send_pc;
    end else begin: gen_no_btb
        assign cancel_nextpc_now = 1'b0;
    end
endgenerate

endmodule
