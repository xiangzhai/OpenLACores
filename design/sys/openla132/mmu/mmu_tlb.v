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

module mmu_tlb (
    input  wire           clk,
    input  wire           reset,

    input  wire           lookup0_vld,
    input  wire [ 31: 0]  lookup0_vaddr,
    input  wire [  9: 0]  lookup0_asid,

    input  wire           lookup1_vld,
    input  wire [ 31: 0]  lookup1_vaddr,
    input  wire [  9: 0]  lookup1_asid,

    input  wire           fill_vld,
    input  wire [ 31: 0]  fill_vaddr,
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
    input  wire [ 31: 0]  inv_vaddr,

    output wire           lookup0_hit,
    output wire [ 31: 0]  lookup0_paddr,
    output wire           lookup0_dirty,
    output wire [  1: 0]  lookup0_plv,
    output wire [  1: 0]  lookup0_mat,

    output wire           lookup1_hit,
    output wire [ 31: 0]  lookup1_paddr,
    output wire           lookup1_dirty,
    output wire [  1: 0]  lookup1_plv,
    output wire [  1: 0]  lookup1_mat
);

//============================================================//
//                     Regs Declarations
//============================================================//

reg [  2: 0] replace_r;

//============================================================//
//                     Wire Declarations
//============================================================//

wire [  7: 0] lookup0_hit_vec;
wire [  7: 0] lookup1_hit_vec;
wire [  7: 0] fill_sel;

wire [ 19: 0] lookup0_vpn;
wire [ 19: 0] lookup1_vpn;
wire [ 19: 0] fill_vpn;
wire [ 19: 0] inv_vpn;

wire         lookup0_hit0;
wire         lookup0_hit1;
wire         lookup0_hit2;
wire         lookup0_hit3;
wire         lookup0_hit4;
wire         lookup0_hit5;
wire         lookup0_hit6;
wire         lookup0_hit7;
wire         lookup1_hit0;
wire         lookup1_hit1;
wire         lookup1_hit2;
wire         lookup1_hit3;
wire         lookup1_hit4;
wire         lookup1_hit5;
wire         lookup1_hit6;
wire         lookup1_hit7;
wire         fill_vld0;
wire         fill_vld1;
wire         fill_vld2;
wire         fill_vld3;
wire         fill_vld4;
wire         fill_vld5;
wire         fill_vld6;
wire         fill_vld7;

wire [ 19: 0] entry0_ppn;
wire [ 19: 0] entry1_ppn;
wire [ 19: 0] entry2_ppn;
wire [ 19: 0] entry3_ppn;
wire [ 19: 0] entry4_ppn;
wire [ 19: 0] entry5_ppn;
wire [ 19: 0] entry6_ppn;
wire [ 19: 0] entry7_ppn;
wire [  5: 0] entry0_ps;
wire [  5: 0] entry1_ps;
wire [  5: 0] entry2_ps;
wire [  5: 0] entry3_ps;
wire [  5: 0] entry4_ps;
wire [  5: 0] entry5_ps;
wire [  5: 0] entry6_ps;
wire [  5: 0] entry7_ps;
wire          entry0_dirty;
wire          entry1_dirty;
wire          entry2_dirty;
wire          entry3_dirty;
wire          entry4_dirty;
wire          entry5_dirty;
wire          entry6_dirty;
wire          entry7_dirty;
wire [  1: 0] entry0_plv;
wire [  1: 0] entry1_plv;
wire [  1: 0] entry2_plv;
wire [  1: 0] entry3_plv;
wire [  1: 0] entry4_plv;
wire [  1: 0] entry5_plv;
wire [  1: 0] entry6_plv;
wire [  1: 0] entry7_plv;
wire [  1: 0] entry0_mat;
wire [  1: 0] entry1_mat;
wire [  1: 0] entry2_mat;
wire [  1: 0] entry3_mat;
wire [  1: 0] entry4_mat;
wire [  1: 0] entry5_mat;
wire [  1: 0] entry6_mat;
wire [  1: 0] entry7_mat;

//============================================================//
//                   Module Implementation
//============================================================//

//------------------------------------------------------------//
//                          Entries
//------------------------------------------------------------//

mmu_tlb_entry x_mmu_tlb_entry_0 (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .lookup0_vld                  (lookup0_vld               ),
    .lookup0_vpn                  (lookup0_vpn               ),
    .lookup0_asid                 (lookup0_asid              ),
    .lookup0_hit                  (lookup0_hit0              ),
    .lookup1_vld                  (lookup1_vld               ),
    .lookup1_vpn                  (lookup1_vpn               ),
    .lookup1_asid                 (lookup1_asid              ),
    .lookup1_hit                  (lookup1_hit0              ),
    .fill_vld                     (fill_vld0                 ),
    .fill_vpn                     (fill_vpn                  ),
    .fill_ps                      (fill_ps                   ),
    .fill_ppn                     (fill_ppn                  ),
    .fill_asid                    (fill_asid                 ),
    .fill_global                  (fill_global               ),
    .fill_dirty                   (fill_dirty                ),
    .fill_plv                     (fill_plv                  ),
    .fill_mat                     (fill_mat                  ),
    .inv_vld                      (inv_vld                   ),
    .inv_op                       (inv_op                    ),
    .inv_asid                     (inv_asid                  ),
    .inv_vpn                      (inv_vpn                   ),
    .entry_ppn                    (entry0_ppn                ),
    .entry_ps                     (entry0_ps                 ),
    .entry_dirty                  (entry0_dirty              ),
    .entry_plv                    (entry0_plv                ),
    .entry_mat                    (entry0_mat                )
);

mmu_tlb_entry x_mmu_tlb_entry_1 (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .lookup0_vld                  (lookup0_vld               ),
    .lookup0_vpn                  (lookup0_vpn               ),
    .lookup0_asid                 (lookup0_asid              ),
    .lookup0_hit                  (lookup0_hit1              ),
    .lookup1_vld                  (lookup1_vld               ),
    .lookup1_vpn                  (lookup1_vpn               ),
    .lookup1_asid                 (lookup1_asid              ),
    .lookup1_hit                  (lookup1_hit1              ),
    .fill_vld                     (fill_vld1                 ),
    .fill_vpn                     (fill_vpn                  ),
    .fill_ps                      (fill_ps                   ),
    .fill_ppn                     (fill_ppn                  ),
    .fill_asid                    (fill_asid                 ),
    .fill_global                  (fill_global               ),
    .fill_dirty                   (fill_dirty                ),
    .fill_plv                     (fill_plv                  ),
    .fill_mat                     (fill_mat                  ),
    .inv_vld                      (inv_vld                   ),
    .inv_op                       (inv_op                    ),
    .inv_asid                     (inv_asid                  ),
    .inv_vpn                      (inv_vpn                   ),
    .entry_ppn                    (entry1_ppn                ),
    .entry_ps                     (entry1_ps                 ),
    .entry_dirty                  (entry1_dirty              ),
    .entry_plv                    (entry1_plv                ),
    .entry_mat                    (entry1_mat                )
);

mmu_tlb_entry x_mmu_tlb_entry_2 (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .lookup0_vld                  (lookup0_vld               ),
    .lookup0_vpn                  (lookup0_vpn               ),
    .lookup0_asid                 (lookup0_asid              ),
    .lookup0_hit                  (lookup0_hit2              ),
    .lookup1_vld                  (lookup1_vld               ),
    .lookup1_vpn                  (lookup1_vpn               ),
    .lookup1_asid                 (lookup1_asid              ),
    .lookup1_hit                  (lookup1_hit2              ),
    .fill_vld                     (fill_vld2                 ),
    .fill_vpn                     (fill_vpn                  ),
    .fill_ps                      (fill_ps                   ),
    .fill_ppn                     (fill_ppn                  ),
    .fill_asid                    (fill_asid                 ),
    .fill_global                  (fill_global               ),
    .fill_dirty                   (fill_dirty                ),
    .fill_plv                     (fill_plv                  ),
    .fill_mat                     (fill_mat                  ),
    .inv_vld                      (inv_vld                   ),
    .inv_op                       (inv_op                    ),
    .inv_asid                     (inv_asid                  ),
    .inv_vpn                      (inv_vpn                   ),
    .entry_ppn                    (entry2_ppn                ),
    .entry_ps                     (entry2_ps                 ),
    .entry_dirty                  (entry2_dirty              ),
    .entry_plv                    (entry2_plv                ),
    .entry_mat                    (entry2_mat                )
);

mmu_tlb_entry x_mmu_tlb_entry_3 (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .lookup0_vld                  (lookup0_vld               ),
    .lookup0_vpn                  (lookup0_vpn               ),
    .lookup0_asid                 (lookup0_asid              ),
    .lookup0_hit                  (lookup0_hit3              ),
    .lookup1_vld                  (lookup1_vld               ),
    .lookup1_vpn                  (lookup1_vpn               ),
    .lookup1_asid                 (lookup1_asid              ),
    .lookup1_hit                  (lookup1_hit3              ),
    .fill_vld                     (fill_vld3                 ),
    .fill_vpn                     (fill_vpn                  ),
    .fill_ps                      (fill_ps                   ),
    .fill_ppn                     (fill_ppn                  ),
    .fill_asid                    (fill_asid                 ),
    .fill_global                  (fill_global               ),
    .fill_dirty                   (fill_dirty                ),
    .fill_plv                     (fill_plv                  ),
    .fill_mat                     (fill_mat                  ),
    .inv_vld                      (inv_vld                   ),
    .inv_op                       (inv_op                    ),
    .inv_asid                     (inv_asid                  ),
    .inv_vpn                      (inv_vpn                   ),
    .entry_ppn                    (entry3_ppn                ),
    .entry_ps                     (entry3_ps                 ),
    .entry_dirty                  (entry3_dirty              ),
    .entry_plv                    (entry3_plv                ),
    .entry_mat                    (entry3_mat                )
);

mmu_tlb_entry x_mmu_tlb_entry_4 (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .lookup0_vld                  (lookup0_vld               ),
    .lookup0_vpn                  (lookup0_vpn               ),
    .lookup0_asid                 (lookup0_asid              ),
    .lookup0_hit                  (lookup0_hit4              ),
    .lookup1_vld                  (lookup1_vld               ),
    .lookup1_vpn                  (lookup1_vpn               ),
    .lookup1_asid                 (lookup1_asid              ),
    .lookup1_hit                  (lookup1_hit4              ),
    .fill_vld                     (fill_vld4                 ),
    .fill_vpn                     (fill_vpn                  ),
    .fill_ps                      (fill_ps                   ),
    .fill_ppn                     (fill_ppn                  ),
    .fill_asid                    (fill_asid                 ),
    .fill_global                  (fill_global               ),
    .fill_dirty                   (fill_dirty                ),
    .fill_plv                     (fill_plv                  ),
    .fill_mat                     (fill_mat                  ),
    .inv_vld                      (inv_vld                   ),
    .inv_op                       (inv_op                    ),
    .inv_asid                     (inv_asid                  ),
    .inv_vpn                      (inv_vpn                   ),
    .entry_ppn                    (entry4_ppn                ),
    .entry_ps                     (entry4_ps                 ),
    .entry_dirty                  (entry4_dirty              ),
    .entry_plv                    (entry4_plv                ),
    .entry_mat                    (entry4_mat                )
);

mmu_tlb_entry x_mmu_tlb_entry_5 (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .lookup0_vld                  (lookup0_vld               ),
    .lookup0_vpn                  (lookup0_vpn               ),
    .lookup0_asid                 (lookup0_asid              ),
    .lookup0_hit                  (lookup0_hit5              ),
    .lookup1_vld                  (lookup1_vld               ),
    .lookup1_vpn                  (lookup1_vpn               ),
    .lookup1_asid                 (lookup1_asid              ),
    .lookup1_hit                  (lookup1_hit5              ),
    .fill_vld                     (fill_vld5                 ),
    .fill_vpn                     (fill_vpn                  ),
    .fill_ps                      (fill_ps                   ),
    .fill_ppn                     (fill_ppn                  ),
    .fill_asid                    (fill_asid                 ),
    .fill_global                  (fill_global               ),
    .fill_dirty                   (fill_dirty                ),
    .fill_plv                     (fill_plv                  ),
    .fill_mat                     (fill_mat                  ),
    .inv_vld                      (inv_vld                   ),
    .inv_op                       (inv_op                    ),
    .inv_asid                     (inv_asid                  ),
    .inv_vpn                      (inv_vpn                   ),
    .entry_ppn                    (entry5_ppn                ),
    .entry_ps                     (entry5_ps                 ),
    .entry_dirty                  (entry5_dirty              ),
    .entry_plv                    (entry5_plv                ),
    .entry_mat                    (entry5_mat                )
);

mmu_tlb_entry x_mmu_tlb_entry_6 (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .lookup0_vld                  (lookup0_vld               ),
    .lookup0_vpn                  (lookup0_vpn               ),
    .lookup0_asid                 (lookup0_asid              ),
    .lookup0_hit                  (lookup0_hit6              ),
    .lookup1_vld                  (lookup1_vld               ),
    .lookup1_vpn                  (lookup1_vpn               ),
    .lookup1_asid                 (lookup1_asid              ),
    .lookup1_hit                  (lookup1_hit6              ),
    .fill_vld                     (fill_vld6                 ),
    .fill_vpn                     (fill_vpn                  ),
    .fill_ps                      (fill_ps                   ),
    .fill_ppn                     (fill_ppn                  ),
    .fill_asid                    (fill_asid                 ),
    .fill_global                  (fill_global               ),
    .fill_dirty                   (fill_dirty                ),
    .fill_plv                     (fill_plv                  ),
    .fill_mat                     (fill_mat                  ),
    .inv_vld                      (inv_vld                   ),
    .inv_op                       (inv_op                    ),
    .inv_asid                     (inv_asid                  ),
    .inv_vpn                      (inv_vpn                   ),
    .entry_ppn                    (entry6_ppn                ),
    .entry_ps                     (entry6_ps                 ),
    .entry_dirty                  (entry6_dirty              ),
    .entry_plv                    (entry6_plv                ),
    .entry_mat                    (entry6_mat                )
);

mmu_tlb_entry x_mmu_tlb_entry_7 (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .lookup0_vld                  (lookup0_vld               ),
    .lookup0_vpn                  (lookup0_vpn               ),
    .lookup0_asid                 (lookup0_asid              ),
    .lookup0_hit                  (lookup0_hit7              ),
    .lookup1_vld                  (lookup1_vld               ),
    .lookup1_vpn                  (lookup1_vpn               ),
    .lookup1_asid                 (lookup1_asid              ),
    .lookup1_hit                  (lookup1_hit7              ),
    .fill_vld                     (fill_vld7                 ),
    .fill_vpn                     (fill_vpn                  ),
    .fill_ps                      (fill_ps                   ),
    .fill_ppn                     (fill_ppn                  ),
    .fill_asid                    (fill_asid                 ),
    .fill_global                  (fill_global               ),
    .fill_dirty                   (fill_dirty                ),
    .fill_plv                     (fill_plv                  ),
    .fill_mat                     (fill_mat                  ),
    .inv_vld                      (inv_vld                   ),
    .inv_op                       (inv_op                    ),
    .inv_asid                     (inv_asid                  ),
    .inv_vpn                      (inv_vpn                   ),
    .entry_ppn                    (entry7_ppn                ),
    .entry_ps                     (entry7_ps                 ),
    .entry_dirty                  (entry7_dirty              ),
    .entry_plv                    (entry7_plv                ),
    .entry_mat                    (entry7_mat                )
);

//------------------------------------------------------------//
//                    Replacement Pointer
//------------------------------------------------------------//

always @ ( posedge clk )
begin
    if(reset) begin
        replace_r <= 3'd0;
    end
    else if(fill_vld && !inv_vld) begin
        replace_r <= replace_r + 3'd1;
    end
end

assign fill_sel[0]            =  fill_vld && (replace_r == 3'd0);
assign fill_sel[1]            =  fill_vld && (replace_r == 3'd1);
assign fill_sel[2]            =  fill_vld && (replace_r == 3'd2);
assign fill_sel[3]            =  fill_vld && (replace_r == 3'd3);
assign fill_sel[4]            =  fill_vld && (replace_r == 3'd4);
assign fill_sel[5]            =  fill_vld && (replace_r == 3'd5);
assign fill_sel[6]            =  fill_vld && (replace_r == 3'd6);
assign fill_sel[7]            =  fill_vld && (replace_r == 3'd7);

assign lookup0_vpn            =  lookup0_vaddr[31:12];
assign lookup1_vpn            =  lookup1_vaddr[31:12];
assign fill_vpn               =  fill_vaddr[31:12];
assign inv_vpn                =  inv_vaddr[31:12];
assign lookup0_hit_vec        =  {lookup0_hit7, lookup0_hit6, lookup0_hit5, lookup0_hit4,
                            lookup0_hit3, lookup0_hit2, lookup0_hit1, lookup0_hit0};
assign lookup1_hit_vec        =  {lookup1_hit7, lookup1_hit6, lookup1_hit5, lookup1_hit4,
                            lookup1_hit3, lookup1_hit2, lookup1_hit1, lookup1_hit0};
assign fill_vld0              =  fill_sel[0];
assign fill_vld1              =  fill_sel[1];
assign fill_vld2              =  fill_sel[2];
assign fill_vld3              =  fill_sel[3];
assign fill_vld4              =  fill_sel[4];
assign fill_vld5              =  fill_sel[5];
assign fill_vld6              =  fill_sel[6];
assign fill_vld7              =  fill_sel[7];

//------------------------------------------------------------//
//                       Lookup Result
//------------------------------------------------------------//

// PPN is expressed in 4 KiB units. For a larger page, the low
// (PS-12) PPN bits are the in-page part and come from the VA.
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

assign lookup0_hit            =  |lookup0_hit_vec;
assign lookup1_hit            =  |lookup1_hit_vec;

assign lookup0_paddr          =  lookup0_hit_vec[0] ? make_paddr(entry0_ppn, lookup0_vaddr, entry0_ps) :
                         lookup0_hit_vec[1] ? make_paddr(entry1_ppn, lookup0_vaddr, entry1_ps) :
                         lookup0_hit_vec[2] ? make_paddr(entry2_ppn, lookup0_vaddr, entry2_ps) :
                         lookup0_hit_vec[3] ? make_paddr(entry3_ppn, lookup0_vaddr, entry3_ps) :
                         lookup0_hit_vec[4] ? make_paddr(entry4_ppn, lookup0_vaddr, entry4_ps) :
                         lookup0_hit_vec[5] ? make_paddr(entry5_ppn, lookup0_vaddr, entry5_ps) :
                         lookup0_hit_vec[6] ? make_paddr(entry6_ppn, lookup0_vaddr, entry6_ps) :
                         lookup0_hit_vec[7] ? make_paddr(entry7_ppn, lookup0_vaddr, entry7_ps) : 32'd0;
assign lookup0_dirty          =  lookup0_hit_vec[0] ? entry0_dirty :
                         lookup0_hit_vec[1] ? entry1_dirty :
                         lookup0_hit_vec[2] ? entry2_dirty :
                         lookup0_hit_vec[3] ? entry3_dirty :
                         lookup0_hit_vec[4] ? entry4_dirty :
                         lookup0_hit_vec[5] ? entry5_dirty :
                         lookup0_hit_vec[6] ? entry6_dirty :
                         lookup0_hit_vec[7] ? entry7_dirty : 1'b0;
assign lookup0_plv            =  lookup0_hit_vec[0] ? entry0_plv :
                         lookup0_hit_vec[1] ? entry1_plv :
                         lookup0_hit_vec[2] ? entry2_plv :
                         lookup0_hit_vec[3] ? entry3_plv :
                         lookup0_hit_vec[4] ? entry4_plv :
                         lookup0_hit_vec[5] ? entry5_plv :
                         lookup0_hit_vec[6] ? entry6_plv :
                         lookup0_hit_vec[7] ? entry7_plv : 2'b0;
assign lookup0_mat            =  lookup0_hit_vec[0] ? entry0_mat :
                         lookup0_hit_vec[1] ? entry1_mat :
                         lookup0_hit_vec[2] ? entry2_mat :
                         lookup0_hit_vec[3] ? entry3_mat :
                         lookup0_hit_vec[4] ? entry4_mat :
                         lookup0_hit_vec[5] ? entry5_mat :
                         lookup0_hit_vec[6] ? entry6_mat :
                         lookup0_hit_vec[7] ? entry7_mat : 2'b0;

assign lookup1_paddr          =  lookup1_hit_vec[0] ? make_paddr(entry0_ppn, lookup1_vaddr, entry0_ps) :
                         lookup1_hit_vec[1] ? make_paddr(entry1_ppn, lookup1_vaddr, entry1_ps) :
                         lookup1_hit_vec[2] ? make_paddr(entry2_ppn, lookup1_vaddr, entry2_ps) :
                         lookup1_hit_vec[3] ? make_paddr(entry3_ppn, lookup1_vaddr, entry3_ps) :
                         lookup1_hit_vec[4] ? make_paddr(entry4_ppn, lookup1_vaddr, entry4_ps) :
                         lookup1_hit_vec[5] ? make_paddr(entry5_ppn, lookup1_vaddr, entry5_ps) :
                         lookup1_hit_vec[6] ? make_paddr(entry6_ppn, lookup1_vaddr, entry6_ps) :
                         lookup1_hit_vec[7] ? make_paddr(entry7_ppn, lookup1_vaddr, entry7_ps) : 32'd0;
assign lookup1_dirty          =  lookup1_hit_vec[0] ? entry0_dirty :
                         lookup1_hit_vec[1] ? entry1_dirty :
                         lookup1_hit_vec[2] ? entry2_dirty :
                         lookup1_hit_vec[3] ? entry3_dirty :
                         lookup1_hit_vec[4] ? entry4_dirty :
                         lookup1_hit_vec[5] ? entry5_dirty :
                         lookup1_hit_vec[6] ? entry6_dirty :
                         lookup1_hit_vec[7] ? entry7_dirty : 1'b0;
assign lookup1_plv            =  lookup1_hit_vec[0] ? entry0_plv :
                         lookup1_hit_vec[1] ? entry1_plv :
                         lookup1_hit_vec[2] ? entry2_plv :
                         lookup1_hit_vec[3] ? entry3_plv :
                         lookup1_hit_vec[4] ? entry4_plv :
                         lookup1_hit_vec[5] ? entry5_plv :
                         lookup1_hit_vec[6] ? entry6_plv :
                         lookup1_hit_vec[7] ? entry7_plv : 2'b0;
assign lookup1_mat            =  lookup1_hit_vec[0] ? entry0_mat :
                         lookup1_hit_vec[1] ? entry1_mat :
                         lookup1_hit_vec[2] ? entry2_mat :
                         lookup1_hit_vec[3] ? entry3_mat :
                         lookup1_hit_vec[4] ? entry4_mat :
                         lookup1_hit_vec[5] ? entry5_mat :
                         lookup1_hit_vec[6] ? entry6_mat :
                         lookup1_hit_vec[7] ? entry7_mat : 2'b0;

endmodule
`endif
