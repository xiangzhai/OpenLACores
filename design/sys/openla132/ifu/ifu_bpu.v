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
module ifu_bpu
#(
    parameter BTB_NUM = 16,
    parameter RS_NUM  = 8
)
(
    input                              clk_g,
    input                              reset,
    input                              data_reset,
    input  [31                     :0] ifu_bpu_pc,
    input  [`OPEN132_DE2PRED_BUS_WD-1:0] idu_bpu_update_bus,
    input  [1                      :0] csr_bpu_ctrl_bus,
    output [`OPEN132_PRED2FT_BUS_WD-1:0] bpu_ifu_pred_bus
    );
localparam HIGH_WD = 20;

//------{csr_bpu_ctrl_bus}begin------//
wire enable_pred;
wire userdef_clr_pred;
assign {userdef_clr_pred,enable_pred} = csr_bpu_ctrl_bus;
//------{csr_bpu_ctrl_bus}end------//

//------{bpu_ifu_pred_bus}begin
genvar i,j;
localparam GHR_WD = `OPEN132_TAGE_GHR_WD;
wire            pred_valid;
wire            pred_brlo_hit;
wire            pred_jrlo_hit;
wire            pred_jr;
wire [31     :0] pred_npc;
wire [3      :0] pred_pos;
wire [2      :0] pred_cnt;
wire            pred_cond;
wire            pred_tage_taken;
wire [GHR_WD-1:0] pred_ghr;
assign bpu_ifu_pred_bus = {pred_valid,
                      pred_brlo_hit,
                      pred_jrlo_hit,
                      pred_jr,
                      pred_npc,
                      pred_pos,
                      pred_cnt,
                      pred_cond,
                      pred_tage_taken,
                      pred_ghr};
//------{bpu_ifu_pred_bus}end
//------{idu_bpu_update_bus}begin
wire [31:0] de_pred_pc;
wire [31:0] de_pred_npc;
wire        de_pred_jr;
wire        de_pred_jrlo_hit;
wire        de_pred_brlo_hit;
wire [3:0]  de_pred_pos;
wire [2:0]  de_pred_cnt;
wire        de_pred_correct;
wire        de_pred_valid_temp;
wire        de_pred_taken;
wire        de_pred_cond;
wire [GHR_WD-1:0] de_pred_ghr;
assign {de_pred_pc     ,
        de_pred_npc    ,
        de_pred_jr     ,
        de_pred_jrlo_hit,
        de_pred_brlo_hit,
        de_pred_pos    ,
        de_pred_cnt    ,
        de_pred_correct,
        de_pred_valid_temp,
        de_pred_taken  ,
        de_pred_cond   ,
        de_pred_ghr
       } = idu_bpu_update_bus;

wire de_pred_valid = de_pred_valid_temp && enable_pred;
//------{idu_bpu_update_bus}end
//------{BTB tag/target}begin------//
//tag high part
reg  [HIGH_WD/2   -1:0] tag_high  [1:0];
reg  [32-HIGH_WD-2-1:0] tag_br_lo [BTB_NUM-1:0];
reg  [13:0]             btb_npc   [BTB_NUM-1:0];
reg  [2:0]              btb_cnt   [BTB_NUM-1:0];
reg  [BTB_NUM-1:0]      br_which_high;
// per-BTB-entry marker: 1 = conditional branch (TAGE direction), 0 = unconditional
reg  [BTB_NUM-1:0]      br_cond;
reg  [32-HIGH_WD-2-1:0] tag_jr_lo [RS_NUM-1:0];
reg  [2             :0] jr_cnt    [RS_NUM-1:0];
reg  [RS_NUM-1:0]       jr_which_high;

//------{BTB tag/target}end------//
//------{SEL}begin---------------//
wire       btb_miss;
wire       jr_miss;
wire       high_miss;
wire       high_update_sel;
wire [1:0] high_update_miss;

wire                      br_update_rate_hit;
wire                      jr_update_rate_hit;
wire [BTB_NUM       -1:0] btb_update_valid;
wire                      jr_update;
wire [$clog2(RS_NUM)-1:0] jr_update_pos;
wire [$clog2(RS_NUM)-1:0] jr_sel_pos;
wire [RS_NUM        -1:0] jr_sel;
wire                      jr_update_hit;

//BTB rrip
wire [BTB_NUM-1:0] btb_cnt_eqz;
wire [BTB_NUM-1:0] btb_next_sel;
wire               btb_any_eqz;

generate for (i=0;i<BTB_NUM;i=i+1) begin
    assign btb_cnt_eqz[i] =  btb_cnt[i] == 3'b0;
end
endgenerate

ifu_first1_n #(.N(BTB_NUM))
first_one_btb(
    .first_one_input  (btb_cnt_eqz),
    .first_one_output (btb_next_sel),
    .first_one_has    (btb_any_eqz)
);
assign br_update_rate_hit = btb_any_eqz ;

//JR rrip
wire [RS_NUM-1:0] jr_cnt_eqz;
wire [RS_NUM-1:0] jr_next_sel;
wire              jr_any_eqz;

generate for (i=0;i<RS_NUM;i=i+1) begin
    assign jr_cnt_eqz[i] =  jr_cnt[i] == 3'b0;
end
endgenerate

ifu_first1_n #(.N(RS_NUM))
first_one_jr(
    .first_one_input  (jr_cnt_eqz),
    .first_one_output (jr_next_sel),
    .first_one_has    (jr_any_eqz)
);
assign jr_sel             = jr_next_sel;
assign jr_update_rate_hit = jr_any_eqz;

ifu_plru2 #(
    .LRU_DEPTH (1)
) btb_high_lru(
    .clk            (clk_g),
    .reset          (reset),
    .hit_update_lru (de_pred_valid),
    .hit_update_pos (high_update_miss[0]),
    .lru_next       (high_miss),
    .new_pos        (high_update_sel)
);
//------{SEL}end-----------------//
//------{BTB UPDATE}begin
//de pred pc seperate high/low
wire [32-HIGH_WD-2-1:0] de_pred_pc_low_part;
wire [HIGH_WD/2   -1:0] de_pred_pc_high_short;
wire [BTB_NUM     -1:0] update_sel;
assign de_pred_pc_low_part  = de_pred_pc[31-HIGH_WD  :           2];
assign de_pred_pc_high_short= de_pred_pc[31          :32-HIGH_WD/2]
                            ^ de_pred_pc[31-HIGH_WD/2:32-HIGH_WD  ];

//common update
wire [1             :0] tag_high_wen;
wire [32-HIGH_WD-2-1:0] tag_nxt;
wire                    tag_which_high_nxt;
assign high_update_miss[0] = !(de_pred_pc_high_short == tag_high[0]);
assign high_update_miss[1] = !(de_pred_pc_high_short == tag_high[1]);
assign high_miss           = de_pred_valid && (&high_update_miss);
assign tag_which_high_nxt  = high_miss ? high_update_sel
                                       : high_update_miss[0];
assign tag_nxt         = de_pred_pc_low_part;
assign tag_high_wen[0] =!high_update_sel && high_miss && br_update_rate_hit;
assign tag_high_wen[1] = high_update_sel && high_miss && br_update_rate_hit;

ifu_dec4_16 update_sel_decode(
    .decode_index  (de_pred_pos),
    .decode_onehot (update_sel)
);

//brlo update
wire [BTB_NUM-1:0] btb_new_hit;
wire               btb_cnt_decrease;
wire [13       :0] btb_npc_nxt;
wire [2        :0] btb_cnt_nxt;

assign btb_miss         = de_pred_valid && !de_pred_brlo_hit && !de_pred_jr;
assign btb_npc_nxt      = de_pred_npc[15:2];
assign btb_cnt_nxt      = de_pred_cnt;
assign btb_cnt_decrease = btb_miss &&!br_update_rate_hit;
generate for (i=0;i<BTB_NUM;i=i+1) begin
    assign btb_update_valid[i] = update_sel[i] && de_pred_valid
                              &&!de_pred_jr    && de_pred_brlo_hit;
    assign btb_new_hit[i]      = btb_miss && br_update_rate_hit && btb_next_sel[i];
end
endgenerate

//jr update
wire [RS_NUM -1:0] jr_new;
wire               jr_cnt_decrease;
wire [RS_NUM -1:0] jr_update_valid;
wire [2        :0] jr_valid_nxt;

assign jr_miss         = de_pred_valid && !de_pred_jrlo_hit && de_pred_jr;
assign jr_update       = de_pred_valid && de_pred_jr;
assign jr_update_pos   = de_pred_pos[$clog2(RS_NUM)-1:0];
assign jr_valid_nxt    = de_pred_cnt;
assign jr_cnt_decrease = jr_miss &&!jr_update_rate_hit;
generate for (i=0;i<RS_NUM;i=i+1) begin
    assign jr_update_valid[i] = de_pred_valid && update_sel[i]
                             && de_pred_jr    && de_pred_jrlo_hit;
    assign jr_new[i] = jr_miss && jr_sel[i] && jr_update_rate_hit;
end
endgenerate

//update regs
generate for (i=0;i<2;i=i+1) begin
always @(posedge clk_g)
begin
    if (reset)
    begin
        tag_high[i] <= {(HIGH_WD/2){1'b0}};
    end
    else if (tag_high_wen[i])
    begin
        tag_high[i] <= de_pred_pc_high_short;
    end
end
end
endgenerate
generate for (i=0;i<BTB_NUM;i=i+1) begin
always @(posedge clk_g)
begin
    if (reset||userdef_clr_pred)
    begin
        btb_cnt[i] <= 3'b0;
    end
    else if (btb_update_valid[i]||btb_new_hit[i])
    begin
        btb_cnt[i] <= btb_cnt_nxt;
    end
    else if (btb_cnt_decrease)
    begin
        btb_cnt[i] <= btb_cnt[i] - 3'b1;
    end
end
always @(posedge clk_g)
begin
    if (reset)
    begin
        tag_br_lo[i]    <= {32-HIGH_WD-2{1'b0}};
        br_which_high[i]<= 1'b0;
        btb_npc[i]      <= 14'b0;
        br_cond[i]      <= 1'b0;
    end
    else if (btb_new_hit[i])
    begin
        tag_br_lo[i]    <= tag_nxt;
        br_which_high[i]<= tag_which_high_nxt;
        btb_npc[i]      <= btb_npc_nxt;
        br_cond[i]      <= de_pred_cond;
    end
end
end
endgenerate
generate for (i=0;i<RS_NUM;i=i+1) begin
always @(posedge clk_g)
begin
    if (reset||userdef_clr_pred)
    begin
        tag_jr_lo[i]    <= {32-HIGH_WD-2{1'b0}};
        jr_which_high[i]<= 1'b0;
    end
    else if (jr_new[i])
    begin
        tag_jr_lo[i]    <= tag_nxt;
        jr_which_high[i]<= tag_which_high_nxt;
    end
end
always @(posedge clk_g)
begin
    if (reset||userdef_clr_pred)
    begin
        jr_cnt[i] <= 3'b0;
    end
    else if (jr_new[i]||jr_update_valid[i])
    begin
        jr_cnt[i] <= jr_valid_nxt;
    end
    else if (jr_cnt_decrease)
    begin
        jr_cnt[i] <= jr_cnt[i] - 3'b1;
    end
end
end
endgenerate
//------{BTB UPDATE}end
//-------{BTB READ}begin
//BTB HIGH READ
wire [31            :0] pred_pc;
wire [HIGH_WD/2   -1:0] pred_pc_high_short;
wire [32-HIGH_WD-2-1:0] pred_pc_low_part;
wire [1             :0] tag_high_read_hit;

assign pred_pc            = ifu_bpu_pc;
assign pred_pc_low_part   = pred_pc[31-HIGH_WD  :           2];
assign pred_pc_high_short = pred_pc[31          :32-HIGH_WD/2]
                          ^ pred_pc[31-HIGH_WD/2:32-HIGH_WD  ];
assign tag_high_read_hit[0] = pred_pc_high_short == tag_high[0];
assign tag_high_read_hit[1] = pred_pc_high_short == tag_high[1];

//BRLO READ HIT
wire [BTB_NUM-1:0]  br_lo_read_hit;
wire [BTB_NUM-1:0]  br_high_part_hit;
wire [BTB_NUM-1:0]  btb_read_hit;
wire                btb_any_read_hit;
wire                br_lo_any_read_hit;

assign btb_read_hit       =  br_lo_read_hit & br_high_part_hit;
assign br_lo_any_read_hit = |br_lo_read_hit;
assign btb_any_read_hit   = |btb_read_hit;
generate for (i=0;i<BTB_NUM;i=i+1) begin
    assign br_lo_read_hit[i]   = pred_pc_low_part == tag_br_lo[i]
                              && (|btb_cnt[i][2:1]);
    assign br_high_part_hit[i] = br_which_high[i] ? tag_high_read_hit[1]
                                                  : tag_high_read_hit[0];
end
endgenerate

//BTB READ INFO
wire [13               :0] btb_read_npc;
wire [$clog2(BTB_NUM)-1:0] btb_read_pos;
wire [2                :0] btb_read_cnt;

`GEN_2D_SEL_1D(BTB_NUM,14,btb_npc,btb_npc_T,btb_read_hit,btb_read_npc)
`GEN_2D_SEL_1D(BTB_NUM, 3,btb_cnt,btb_cnt_T,btb_read_hit,btb_read_cnt)

ifu_enc_n_m #(.N(16)) btb_read_pos_encode(
    .encode_onehot (br_lo_read_hit),
    .encode_value  (btb_read_pos)
);

//JR READ
wire                       jr_any_read_hit;
wire                       jrlo_any_read_hit;
wire [RS_NUM         -1:0] jr_lo_hit;
wire [RS_NUM         -1:0] jr_read_hit;
wire [RS_NUM         -1:0] jr_high_part_hit;
wire [$clog2(RS_NUM) -1:0] jr_read_pos;
wire [2                :0] jr_read_cnt;

generate for (i=0;i<RS_NUM;i=i+1) begin
    assign jr_lo_hit[i]      = pred_pc_low_part  == tag_jr_lo[i] && (|jr_cnt[i][2:1]);
    assign jr_high_part_hit[i] = jr_which_high[i] ? tag_high_read_hit[1]
                                                  : tag_high_read_hit[0];
end
endgenerate

assign jr_read_hit       =  jr_lo_hit & jr_high_part_hit;
assign jr_any_read_hit   = |jr_read_hit;
assign jrlo_any_read_hit = |jr_lo_hit;

`GEN_2D_SEL_1D(RS_NUM, 3,jr_cnt,jr_cnt_T,jr_read_hit,jr_read_cnt)

ifu_enc_n_m #(.N(8)) jr_read_pos_encode(
    .encode_onehot (jr_read_hit),
    .encode_value  (jr_read_pos)
);

//-------{BTB READ}end
//-----bpu_ifu_pred_bus signasl
// TAGE provides the direction for conditional direct branches. pred_cnt keeps
// carrying the legacy BTB/jr confidence counter (used for BTB replacement and
// updates); the TAGE decision rides on pred_cond / pred_tage_taken so that the
// final taken/not-taken choice does not corrupt the BTB entry lifetime.
wire btb_read_cond;
assign btb_read_cond= |(br_cond & btb_read_hit);
assign pred_valid   = (btb_any_read_hit || jr_any_read_hit)&&enable_pred;
assign pred_brlo_hit= br_lo_any_read_hit;
assign pred_jrlo_hit= jrlo_any_read_hit;
assign pred_jr      = jr_any_read_hit;
assign pred_npc     = {pred_pc[31:16],btb_read_npc,2'b0};
assign pred_pos     = jr_any_read_hit ? jr_read_pos : btb_read_pos;
assign pred_cnt     = jr_any_read_hit ? jr_read_cnt
                                      : btb_read_cnt;
// conditional direct-branch BTB hit -> direction comes from TAGE
assign pred_cond      = btb_read_cond && !jr_any_read_hit;
`ifdef OPEN132_DEBUG
wire [3:0] btb_sel_pos;
ifu_enc_n_m #(.N(16)) lru_sel_pos_encode(
    .encode_onehot (btb_next_sel),
    .encode_value  (btb_sel_pos)
);
`endif

`ifdef OPEN132_ASSERT
assert property (
    @(posedge clk_g)
    pred_valid
    |-> $onehot0(br_lo_read_hit[15:0])
    )
else begin $display("Brlo multi hit Assert Error!!!"); #2 $finish; end

assert property (
    @(posedge clk_g)
    pred_valid
    |-> $onehot0(jr_lo_hit[7:0])
    )
else begin $display("jrlo multi hit Assert Error!!!"); #2 $finish; end
`endif

//------------------------------------------------------------//
//                       TAGE predictor
//------------------------------------------------------------//
ifu_tage #(
    .GH        (GHR_WD)
) x_ifu_tage (
    .clk_g     (clk_g                ),
    .reset     (reset                ),
    .clear     (userdef_clr_pred     ),
    .pred_pc   (ifu_bpu_pc           ),
    .pred_taken(pred_tage_taken      ),
    .pred_ghr  (pred_ghr             ),
    .upd_valid (de_pred_cond && enable_pred),
    .upd_pc    (de_pred_pc           ),
    .upd_taken (de_pred_taken        ),
    .upd_ghr   (de_pred_ghr          )
);
endmodule
