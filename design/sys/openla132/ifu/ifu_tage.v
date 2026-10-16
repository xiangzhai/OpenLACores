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

// Compact TAgged GEometric history length (TAGE) direction predictor.
// - A bimodal base table provides the default prediction.
// - NTAGE tagged tables hold geometric history lengths (4 / 8 / 12).
// - A committed global history register (GHR) is updated when a conditional
//   branch resolves; the same snapshot is fed back through the pipeline so a
//   prediction read and its later update always touch the same table entry.
// Only conditional-branch direction is learned here; targets stay in the BTB.

`include "openla132_global.h"

module ifu_tage #(
    parameter GH = 12
) (
    input  wire            clk_g,
    input  wire            reset,
    input  wire            clear,        // e.g. CSR user-defined predictor clear
    // prediction
    input  wire [31     :0] pred_pc,
    output wire             pred_taken,
    output wire [GH    -1:0] pred_ghr,
    // update (conditional branch resolution)
    input  wire             upd_valid,
    input  wire [31     :0] upd_pc,
    input  wire             upd_taken,
    input  wire [GH    -1:0] upd_ghr
);

//----------------------------------------------------------------------------//
//                        Configuration / helpers
//----------------------------------------------------------------------------//
localparam BASE_ENTRIES = 512;
localparam BASE_IDX_W   = 9;
localparam TAGE_ENTRIES = 128;
localparam TAGE_IDX_W   = 7;
localparam TAG_W        = 8;

// History masks: table 0 = 4 bits, table 1 = 8 bits, table 2 = 12 bits (=GH).
localparam [GH-1:0] H0_MASK = {{(GH-4){1'b0}}, 4'hf};
localparam [GH-1:0] H1_MASK = {{(GH-8){1'b0}}, 8'hff};
localparam [GH-1:0] H2_MASK = {GH{1'b1}};

function [TAGE_IDX_W-1:0] tage_idx;
    input [31       :0] pc;
    input [GH     -1:0] h;
    input [GH     -1:0] hm;
    reg   [GH     -1:0] hh;
    begin
        hh       = h & hm;
        tage_idx = pc[TAGE_IDX_W+1:2]
                 ^ hh[TAGE_IDX_W-1:0]
                 ^ {{(TAGE_IDX_W-(GH-TAGE_IDX_W)){1'b0}}, hh[GH-1:TAGE_IDX_W]};
    end
endfunction

function [TAG_W-1:0] tage_tag;
    input [31    :0] pc;
    input [GH  -1:0] h;
    input [GH  -1:0] hm;
    reg   [GH  -1:0] hh;
    begin
        hh       = h & hm;
        tage_tag = pc[16:9]
                 ^ {1'b0, hh[TAGE_IDX_W-1:0]}
                 ^ {{(TAG_W-1){1'b0}}, hh[GH-1]};
    end
endfunction

function [2:0] ctr_up; input [2:0] c; begin ctr_up = (c==3'b111) ? 3'b111 : c + 3'b1; end endfunction
function [2:0] ctr_dn; input [2:0] c; begin ctr_dn = (c==3'b000) ? 3'b000 : c - 3'b1; end endfunction
function [1:0] base_up; input [1:0] c; begin base_up = (c==2'b11) ? 2'b11 : c + 2'b1; end endfunction
function [1:0] base_dn; input [1:0] c; begin base_dn = (c==2'b00) ? 2'b00 : c - 2'b1; end endfunction

//----------------------------------------------------------------------------//
//                              Storage
//----------------------------------------------------------------------------//
reg  [1:0]       base_ctr [BASE_ENTRIES-1:0];
reg  [TAG_W-1:0] t0_tag   [TAGE_ENTRIES-1:0];
reg  [2:0]       t0_ctr   [TAGE_ENTRIES-1:0];
reg              t0_u     [TAGE_ENTRIES-1:0];
reg              t0_v     [TAGE_ENTRIES-1:0];
reg  [TAG_W-1:0] t1_tag   [TAGE_ENTRIES-1:0];
reg  [2:0]       t1_ctr   [TAGE_ENTRIES-1:0];
reg              t1_u     [TAGE_ENTRIES-1:0];
reg              t1_v     [TAGE_ENTRIES-1:0];
reg  [TAG_W-1:0] t2_tag   [TAGE_ENTRIES-1:0];
reg  [2:0]       t2_ctr   [TAGE_ENTRIES-1:0];
reg              t2_u     [TAGE_ENTRIES-1:0];
reg              t2_v     [TAGE_ENTRIES-1:0];
reg  [GH-1:0]    ghr;

//----------------------------------------------------------------------------//
//                          Prediction (combinational)
//----------------------------------------------------------------------------//
wire [BASE_IDX_W-1:0] p_base_i;
wire [TAGE_IDX_W-1:0] p_i0;
wire [TAGE_IDX_W-1:0] p_i1;
wire [TAGE_IDX_W-1:0] p_i2;
wire [TAG_W-1:0]      p_t0;
wire [TAG_W-1:0]      p_t1;
wire [TAG_W-1:0]      p_t2;
wire                  p_m0;
wire                  p_m1;
wire                  p_m2;

assign p_base_i = pred_pc[BASE_IDX_W+1:2];
assign p_i0     = tage_idx(pred_pc, ghr, H0_MASK);
assign p_i1     = tage_idx(pred_pc, ghr, H1_MASK);
assign p_i2     = tage_idx(pred_pc, ghr, H2_MASK);
assign p_t0     = tage_tag(pred_pc, ghr, H0_MASK);
assign p_t1     = tage_tag(pred_pc, ghr, H1_MASK);
assign p_t2     = tage_tag(pred_pc, ghr, H2_MASK);
assign p_m0     = t0_v[p_i0] && (t0_tag[p_i0] == p_t0);
assign p_m1     = t1_v[p_i1] && (t1_tag[p_i1] == p_t1);
assign p_m2     = t2_v[p_i2] && (t2_tag[p_i2] == p_t2);

assign pred_taken = p_m2 ? t2_ctr[p_i2][2] :
                    p_m1 ? t1_ctr[p_i1][2] :
                    p_m0 ? t0_ctr[p_i0][2] :
                           base_ctr[p_base_i][1];
assign pred_ghr   = ghr;

//----------------------------------------------------------------------------//
//                          Update (combinational view)
//----------------------------------------------------------------------------//
wire [BASE_IDX_W-1:0] u_base_i;
wire [TAGE_IDX_W-1:0] u_i0;
wire [TAGE_IDX_W-1:0] u_i1;
wire [TAGE_IDX_W-1:0] u_i2;
wire [TAG_W-1:0]      u_t0;
wire [TAG_W-1:0]      u_t1;
wire [TAG_W-1:0]      u_t2;
wire                  u_m0;
wire                  u_m1;
wire                  u_m2;
wire                  u_hit;
wire                  prov0;
wire                  prov1;
wire                  prov2;
wire                  upd_pred;
wire                  upd_miss;
wire                  alloc_t0;
wire                  alloc_t1;
wire                  alloc_t2;

assign u_base_i = upd_pc[BASE_IDX_W+1:2];
assign u_i0     = tage_idx(upd_pc, upd_ghr, H0_MASK);
assign u_i1     = tage_idx(upd_pc, upd_ghr, H1_MASK);
assign u_i2     = tage_idx(upd_pc, upd_ghr, H2_MASK);
assign u_t0     = tage_tag(upd_pc, upd_ghr, H0_MASK);
assign u_t1     = tage_tag(upd_pc, upd_ghr, H1_MASK);
assign u_t2     = tage_tag(upd_pc, upd_ghr, H2_MASK);
assign u_m0     = t0_v[u_i0] && (t0_tag[u_i0] == u_t0);
assign u_m1     = t1_v[u_i1] && (t1_tag[u_i1] == u_t1);
assign u_m2     = t2_v[u_i2] && (t2_tag[u_i2] == u_t2);
assign u_hit    = u_m0 | u_m1 | u_m2;
// provider = longest matching table
assign prov0    =  u_m0 & ~u_m1 & ~u_m2;
assign prov1    =  u_m1 & ~u_m2;
assign prov2    =  u_m2;

assign upd_pred = prov2 ? t2_ctr[u_i2][2] :
                  prov1 ? t1_ctr[u_i1][2] :
                  prov0 ? t0_ctr[u_i0][2] :
                          base_ctr[u_base_i][1];
assign upd_miss = upd_valid && (upd_pred != upd_taken);

// TAGE allocation: on a misprediction, install the branch in a table with a
// longer history than the provider (or the longest free table on a cold miss).
assign alloc_t2 = upd_miss && (prov0 | prov1 | ~u_hit) && ~t2_u[u_i2];
assign alloc_t1 = upd_miss && (prov0 | ~u_hit) && ~alloc_t2 && ~t1_u[u_i1];
assign alloc_t0 = upd_miss && (~u_hit) && ~alloc_t2 && ~alloc_t1;

//----------------------------------------------------------------------------//
//                          Storage update
//----------------------------------------------------------------------------//
integer k;
always @ (posedge clk_g) begin
    if (reset || clear) begin
        for (k=0; k<BASE_ENTRIES; k=k+1) begin
            base_ctr[k] <= 2'b0;
        end
        for (k=0; k<TAGE_ENTRIES; k=k+1) begin
            t0_v[k]   <= 1'b0;
            t0_tag[k] <= {TAG_W{1'b0}};
            t0_ctr[k] <= 3'b0;
            t0_u[k]   <= 1'b0;
            t1_v[k]   <= 1'b0;
            t1_tag[k] <= {TAG_W{1'b0}};
            t1_ctr[k] <= 3'b0;
            t1_u[k]   <= 1'b0;
            t2_v[k]   <= 1'b0;
            t2_tag[k] <= {TAG_W{1'b0}};
            t2_ctr[k] <= 3'b0;
            t2_u[k]   <= 1'b0;
        end
        ghr <= {GH{1'b0}};
    end
    else if (upd_valid) begin
        ghr <= {ghr[GH-2:0], upd_taken};

        // base bimodal counter (only when no tagged table matched)
        if (!u_hit) begin
            base_ctr[u_base_i] <= upd_taken ? base_up(base_ctr[u_base_i])
                                            : base_dn(base_ctr[u_base_i]);
        end

        // provider counter
        if (prov0) t0_ctr[u_i0] <= upd_taken ? ctr_up(t0_ctr[u_i0]) : ctr_dn(t0_ctr[u_i0]);
        if (prov1) t1_ctr[u_i1] <= upd_taken ? ctr_up(t1_ctr[u_i1]) : ctr_dn(t1_ctr[u_i1]);
        if (prov2) t2_ctr[u_i2] <= upd_taken ? ctr_up(t2_ctr[u_i2]) : ctr_dn(t2_ctr[u_i2]);

        // usefulness bits
        if (upd_pred == upd_taken) begin
            if (prov0) t0_u[u_i0] <= 1'b1;
            if (prov1) t1_u[u_i1] <= 1'b1;
            if (prov2) t2_u[u_i2] <= 1'b1;
        end
        else begin
            if (prov1) t1_u[u_i1] <= 1'b0;
            if (prov2) t2_u[u_i2] <= 1'b0;
        end

        // allocation of the mispredicted branch
        if (alloc_t0) begin
            t0_v[u_i0]   <= 1'b1;
            t0_tag[u_i0] <= u_t0;
            t0_ctr[u_i0] <= upd_taken ? 3'b100 : 3'b011;
            t0_u[u_i0]   <= 1'b0;
        end
        if (alloc_t1) begin
            t1_v[u_i1]   <= 1'b1;
            t1_tag[u_i1] <= u_t1;
            t1_ctr[u_i1] <= upd_taken ? 3'b100 : 3'b011;
            t1_u[u_i1]   <= 1'b0;
        end
        if (alloc_t2) begin
            t2_v[u_i2]   <= 1'b1;
            t2_tag[u_i2] <= u_t2;
            t2_ctr[u_i2] <= upd_taken ? 3'b100 : 3'b011;
            t2_u[u_i2]   <= 1'b0;
        end
    end
end

endmodule
