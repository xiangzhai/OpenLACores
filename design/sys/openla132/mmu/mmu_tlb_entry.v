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

module mmu_tlb_entry (
    input  wire           clk,
    input  wire           reset,

    input  wire           lookup0_vld,
    input  wire [ 19: 0]  lookup0_vpn,
    input  wire [  9: 0]  lookup0_asid,

    input  wire           lookup1_vld,
    input  wire [ 19: 0]  lookup1_vpn,
    input  wire [  9: 0]  lookup1_asid,

    input  wire           fill_vld,
    input  wire [ 19: 0]  fill_vpn,
    input  wire [  5: 0]  fill_ps,
    input  wire [ 19: 0]  fill_ppn,
    input  wire [  9: 0]  fill_asid,
    input  wire           fill_global,
    input  wire           fill_dirty,
    input  wire [  1: 0]  fill_plv,
    input  wire [  1: 0]  fill_mat,

    input  wire           inv_vld,
    input  wire [  4: 0]  inv_op,
    input  wire [  9: 0]  inv_asid,
    input  wire [ 19: 0]  inv_vpn,

    output wire           lookup0_hit,
    output wire           lookup1_hit,
    output wire [ 19: 0]  entry_ppn,
    output wire [  5: 0]  entry_ps,
    output wire           entry_dirty,
    output wire [  1: 0]  entry_plv,
    output wire [  1: 0]  entry_mat
);

//============================================================//
//                     Regs Declarations
//============================================================//

reg          vld_r;
reg [ 19: 0] vpn_r;
reg [  5: 0] ps_r;
reg [ 19: 0] ppn_r;
reg [  9: 0] asid_r;
reg          global_r;
reg          dirty_r;
reg [  1: 0] plv_r;
reg [  1: 0] mat_r;

//============================================================//
//                     Wire Declarations
//============================================================//

wire         lookup0_asid_match;
wire         lookup1_asid_match;
wire         inv_asid_match;
wire         inv_vpn_match;
wire         inv_match;

//============================================================//
//                   Module Implementation
//============================================================//

//------------------------------------------------------------//
//                       Page Size Helpers
//------------------------------------------------------------//

// PS is the architectural page shift (12 = 4 KiB, 14 = 16 KiB, ...).
// VPN/PPN are held in 4 KiB units, so bits [PS-1:12] are the in-page
// part of a larger translation and must be ignored for tag matching.
function [19: 0] vpn_mask;
    input [5: 0] ps;
    begin
        if (ps <= 6'd12) begin
            vpn_mask = 20'hF_FFFF;
        end
        else if (ps >= 6'd32) begin
            vpn_mask = 20'd0;
        end
        else begin
            vpn_mask = 20'hF_FFFF << (ps - 6'd12);
        end
    end
endfunction

// LA32 INVTLB still addresses a paired VPPN. Ignore VPN bit 0 for
// sub-8 KiB pages, and ignore the whole in-page VPN field for larger pages.
function [19: 0] inv_vpn_mask;
    input [5: 0] ps;
    begin
        if (ps <= 6'd13) begin
            inv_vpn_mask = 20'hF_FFFE;
        end
        else if (ps >= 6'd32) begin
            inv_vpn_mask = 20'd0;
        end
        else begin
            inv_vpn_mask = 20'hF_FFFF << (ps - 6'd12);
        end
    end
endfunction

//------------------------------------------------------------//
//                           Lookup
//------------------------------------------------------------//

assign lookup0_asid_match     =  global_r || (asid_r == lookup0_asid);
assign lookup1_asid_match     =  global_r || (asid_r == lookup1_asid);

assign lookup0_hit            =  lookup0_vld && vld_r && lookup0_asid_match
                                 && (((vpn_r ^ lookup0_vpn) & vpn_mask(ps_r)) == 20'd0);
assign lookup1_hit            =  lookup1_vld && vld_r && lookup1_asid_match
                                 && (((vpn_r ^ lookup1_vpn) & vpn_mask(ps_r)) == 20'd0);

//------------------------------------------------------------//
//                        Maintenance
//------------------------------------------------------------//

assign inv_asid_match         =  asid_r == inv_asid;
assign inv_vpn_match          =  (((vpn_r ^ inv_vpn) & inv_vpn_mask(ps_r)) == 20'd0);

assign inv_match              =  (inv_op == 5'd0)
                                 || (inv_op == 5'd1)
                                 || ((inv_op == 5'd2) && global_r)
                                 || ((inv_op == 5'd3) && !global_r)
                                 || ((inv_op == 5'd4) && !global_r && inv_asid_match)
                                 || ((inv_op == 5'd5) && !global_r && inv_asid_match
                                     && inv_vpn_match)
                                 || ((inv_op == 5'd6) && inv_vpn_match
                                     && (global_r || inv_asid_match));

//------------------------------------------------------------//
//                        Entry State
//------------------------------------------------------------//

always @ ( posedge clk )
begin
    if(reset) begin
        vld_r <= 1'b0;
    end
    else if(inv_vld && inv_match) begin
        vld_r <= 1'b0;
    end
    else if(fill_vld) begin
        vld_r <= 1'b1;
    end
end

//------------------------------------------------------------//
//                       Entry Payload
//------------------------------------------------------------//
always @ ( posedge clk )
begin
    if(reset) begin
        ps_r <= 6'd12;
    end
    else if(fill_vld) begin
        vpn_r    <= fill_vpn & vpn_mask(fill_ps);
        ppn_r    <= fill_ppn & vpn_mask(fill_ps);
        ps_r     <= fill_ps;
        asid_r   <= fill_asid;
        global_r <= fill_global;
        dirty_r  <= fill_dirty;
        plv_r    <= fill_plv;
        mat_r    <= fill_mat;
    end
end

//------------------------------------------------------------//
//                      Entry Projection
//------------------------------------------------------------//

assign entry_ppn              =  ppn_r;
assign entry_ps               =  ps_r;
assign entry_dirty            =  dirty_r;
assign entry_plv              =  plv_r;
assign entry_mat              =  mat_r;

endmodule
`endif
