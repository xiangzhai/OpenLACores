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

module mmu_core (
    input  wire           clk,
    input  wire           reset,

    input  wire           ifu_kill,
    input  wire           ifu_req_vld,
    input  wire [ 31: 0]  ifu_req_vaddr,
    input  wire           ifu_cache_req_rdy,

    input  wire           lsu_kill,
    input  wire           lsu_req_vld,
    input  wire           lsu_req_write,
    input  wire [ 31: 0]  lsu_req_vaddr,
    input  wire           lsu_cache_req_rdy,

    input  wire [  1: 0]  csr_plv,
    input  wire           csr_da,
    input  wire           csr_pg,
    input  wire [  1: 0]  csr_datf,
    input  wire [  1: 0]  csr_datm,
    input  wire [  9: 0]  csr_asid,
    input  wire [ 31: 0]  csr_pgdl,
    input  wire [ 31: 0]  csr_pgdh,
    input  wire [ 31: 0]  csr_dmw0,
    input  wire [ 31: 0]  csr_dmw1,
    input  wire [ 31: 0]  csr_pwcl,
    input  wire [ 31: 0]  csr_pwch,
    input  wire           csr_ptw_en,

    input  wire           csr_inv_vld,
    input  wire [  4: 0]  csr_inv_op,
    input  wire [  9: 0]  csr_inv_asid,
    input  wire [ 31: 0]  csr_inv_vaddr,

    input  wire           dcache_ptw_req_rdy,
    input  wire           dcache_ptw_resp_vld,
    input  wire [ 31: 0]  dcache_ptw_resp_data,
    input  wire           dcache_ptw_resp_err,

    output wire           ifu_req_rdy,
    output wire           ifu_expt_vld,
    output wire [  5: 0]  ifu_expt_code,
    output wire           ifu_cache_req_vld,
    output wire           ifu_cache_req_wait,
    output wire [ 31: 0]  ifu_cache_req_vaddr,
    output wire [ 31: 0]  ifu_cache_req_paddr,
    output wire [  1: 0]  ifu_cache_req_mat,
    output wire           ifu_cache_xlat_vld,
    output wire           ifu_cache_xlat_cancel,
    output wire [ 31: 0]  ifu_cache_xlat_paddr,
    output wire [  1: 0]  ifu_cache_xlat_mat,

    output wire           lsu_req_rdy,
    output wire           lsu_expt_vld,
    output wire [  5: 0]  lsu_expt_code,
    output wire           lsu_expt_write,
    output wire           lsu_cache_req_vld,
    output wire           lsu_cache_req_wait,
    output wire [ 31: 0]  lsu_cache_req_vaddr,
    output wire [ 31: 0]  lsu_cache_req_paddr,
    output wire [  1: 0]  lsu_cache_req_mat,
    output wire           lsu_cache_xlat_vld,
    output wire           lsu_cache_xlat_cancel,
    output wire [ 31: 0]  lsu_cache_xlat_paddr,
    output wire [  1: 0]  lsu_cache_xlat_mat,

    output wire           ptw_dcache_req_vld,
    output wire [ 31: 0]  ptw_dcache_req_paddr
);

//============================================================//
//                Local Parameter Declarations
//============================================================//

localparam IFU_IS_FETCH = 1;
localparam LSU_IS_FETCH = 0;

//============================================================//
//                     Wire Declarations
//============================================================//

wire         ifu_req_write;

wire          ifu_tlb_lookup_vld;
wire [ 31: 0] ifu_tlb_lookup_vaddr;
wire [  9: 0] ifu_tlb_lookup_asid;
wire          ifu_tlb_lookup_hit;
wire [ 31: 0] ifu_tlb_lookup_paddr;
wire          ifu_tlb_lookup_dirty;
wire [  1: 0] ifu_tlb_lookup_plv;
wire [  1: 0] ifu_tlb_lookup_mat;

wire          lsu_tlb_lookup_vld;
wire [ 31: 0] lsu_tlb_lookup_vaddr;
wire [  9: 0] lsu_tlb_lookup_asid;
wire          lsu_tlb_lookup_hit;
wire [ 31: 0] lsu_tlb_lookup_paddr;
wire          lsu_tlb_lookup_dirty;
wire [  1: 0] lsu_tlb_lookup_plv;
wire [  1: 0] lsu_tlb_lookup_mat;

wire          ifu_port_ptw_req_vld;
wire          ifu_port_ptw_req_rdy;
wire          ifu_port_ptw_req_write;
wire [ 31: 0] ifu_port_ptw_req_vaddr;
wire [  9: 0] ifu_port_ptw_req_asid;
wire          lsu_port_ptw_req_vld;
wire          lsu_port_ptw_req_rdy;
wire          lsu_port_ptw_req_write;
wire [ 31: 0] lsu_port_ptw_req_vaddr;
wire [  9: 0] lsu_port_ptw_req_asid;

wire          ptw_req_vld;
wire          ptw_req_rdy;
wire          ptw_req_port;
wire          ptw_req_write;
wire [ 31: 0] ptw_req_vaddr;
wire [  9: 0] ptw_req_asid;

wire          ptw_resp_vld;
wire          ptw_resp_rdy;
wire          ptw_resp_port;
wire [ 31: 0] ptw_resp_vaddr;
wire [  9: 0] ptw_resp_asid;
wire [ 19: 0] ptw_resp_ppn;
wire [  5: 0] ptw_resp_ps;
wire          ptw_resp_global;
wire          ptw_resp_dirty;
wire [  1: 0] ptw_resp_plv;
wire [  1: 0] ptw_resp_mat;
wire          ptw_resp_page_vld;
wire          ptw_resp_bus_err;

wire         ifu_port_ptw_resp_vld;
wire         lsu_port_ptw_resp_vld;

wire          ifu_port_fill_vld;
wire [ 31: 0] ifu_port_fill_vaddr;
wire [ 19: 0] ifu_port_fill_ppn;
wire [  5: 0] ifu_port_fill_ps;
wire [  9: 0] ifu_port_fill_asid;
wire          ifu_port_fill_global;
wire          ifu_port_fill_dirty;
wire [  1: 0] ifu_port_fill_plv;
wire [  1: 0] ifu_port_fill_mat;
wire          lsu_port_fill_vld;
wire [ 31: 0] lsu_port_fill_vaddr;
wire [ 19: 0] lsu_port_fill_ppn;
wire [  5: 0] lsu_port_fill_ps;
wire [  9: 0] lsu_port_fill_asid;
wire          lsu_port_fill_global;
wire          lsu_port_fill_dirty;
wire [  1: 0] lsu_port_fill_plv;
wire [  1: 0] lsu_port_fill_mat;

wire          tlb_fill_vld;
wire [ 31: 0] tlb_fill_vaddr;
wire [ 19: 0] tlb_fill_ppn;
wire [  5: 0] tlb_fill_ps;
wire [  9: 0] tlb_fill_asid;
wire          tlb_fill_global;
wire          tlb_fill_dirty;
wire [  1: 0] tlb_fill_plv;
wire [  1: 0] tlb_fill_mat;

wire          ifu_auto_inv_vld;
wire [ 31: 0] ifu_auto_inv_vaddr;
wire [  9: 0] ifu_auto_inv_asid;
wire          lsu_auto_inv_vld;
wire [ 31: 0] lsu_auto_inv_vaddr;
wire [  9: 0] lsu_auto_inv_asid;
wire          tlb_inv_vld;
wire [  4: 0] tlb_inv_op;
wire [  9: 0] tlb_inv_asid;
wire [ 31: 0] tlb_inv_vaddr;


//============================================================//
//                   Module Implementation
//============================================================//

assign ifu_req_write          =  1'b0;


//------------------------------------------------------------//
//                   Shared PTW Arbitration
//------------------------------------------------------------//

assign ptw_req_vld            =  lsu_port_ptw_req_vld || ifu_port_ptw_req_vld;
assign ptw_req_port           =  lsu_port_ptw_req_vld;
assign ptw_req_write          =  lsu_port_ptw_req_vld ? lsu_port_ptw_req_write
                                 : ifu_port_ptw_req_write;
assign ptw_req_vaddr          =  lsu_port_ptw_req_vld ? lsu_port_ptw_req_vaddr
                                 : ifu_port_ptw_req_vaddr;
assign ptw_req_asid           =  lsu_port_ptw_req_vld ? lsu_port_ptw_req_asid
                                 : ifu_port_ptw_req_asid;

assign lsu_port_ptw_req_rdy   =  ptw_req_rdy && lsu_port_ptw_req_vld;
assign ifu_port_ptw_req_rdy   =  ptw_req_rdy && !lsu_port_ptw_req_vld
                                 && ifu_port_ptw_req_vld;
assign ptw_resp_rdy           =  1'b1;
assign ifu_port_ptw_resp_vld  =  ptw_resp_vld && !ptw_resp_port;
assign lsu_port_ptw_resp_vld  =  ptw_resp_vld && ptw_resp_port;

//------------------------------------------------------------//
//                   Refill and Invalidate
//------------------------------------------------------------//

assign tlb_inv_vld            =  csr_inv_vld || lsu_auto_inv_vld || ifu_auto_inv_vld;
assign tlb_inv_op             =  csr_inv_vld ? csr_inv_op : 5'd6;
assign tlb_inv_asid           =  csr_inv_vld      ? csr_inv_asid  :
                                 lsu_auto_inv_vld ? lsu_auto_inv_asid :
                                                    ifu_auto_inv_asid;
assign tlb_inv_vaddr          =  csr_inv_vld      ? csr_inv_vaddr :
                                 lsu_auto_inv_vld ? lsu_auto_inv_vaddr :
                                                    ifu_auto_inv_vaddr;

assign tlb_fill_vld           =  (lsu_port_fill_vld || ifu_port_fill_vld) && !tlb_inv_vld;
assign tlb_fill_vaddr         =  lsu_port_fill_vld ? lsu_port_fill_vaddr
                                 : ifu_port_fill_vaddr;
assign tlb_fill_ppn           =  lsu_port_fill_vld ? lsu_port_fill_ppn
                                 : ifu_port_fill_ppn;
assign tlb_fill_ps            =  lsu_port_fill_vld ? lsu_port_fill_ps
                                 : ifu_port_fill_ps;
assign tlb_fill_asid          =  lsu_port_fill_vld ? lsu_port_fill_asid
                                 : ifu_port_fill_asid;
assign tlb_fill_global        =  lsu_port_fill_vld ? lsu_port_fill_global
                                 : ifu_port_fill_global;
assign tlb_fill_dirty         =  lsu_port_fill_vld ? lsu_port_fill_dirty
                                 : ifu_port_fill_dirty;
assign tlb_fill_plv           =  lsu_port_fill_vld ? lsu_port_fill_plv
                                 : ifu_port_fill_plv;
assign tlb_fill_mat           =  lsu_port_fill_vld ? lsu_port_fill_mat
                                 : ifu_port_fill_mat;

//------------------------------------------------------------//
//                    Instruction MMU Port
//------------------------------------------------------------//

mmu_port #(
  .IS_FETCH(IFU_IS_FETCH)
) x_mmu_port_ifu (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .kill                         (ifu_kill                  ),
    .cpu_req_vld                  (ifu_req_vld               ),
    .cpu_req_rdy                  (ifu_req_rdy               ),
    .cpu_req_write                (ifu_req_write             ),
    .cpu_req_vaddr                (ifu_req_vaddr             ),
    .cpu_expt_vld                 (ifu_expt_vld              ),
    .cpu_expt_code                (ifu_expt_code             ),
    .cpu_expt_write               (                           ),
    .cache_req_vld                (ifu_cache_req_vld         ),
    .cache_req_rdy                (ifu_cache_req_rdy         ),
    .cache_req_wait               (ifu_cache_req_wait        ),
    .cache_req_vaddr              (ifu_cache_req_vaddr       ),
    .cache_req_paddr              (ifu_cache_req_paddr       ),
    .cache_req_mat                (ifu_cache_req_mat         ),
    .cache_xlat_vld               (ifu_cache_xlat_vld        ),
    .cache_xlat_cancel            (ifu_cache_xlat_cancel     ),
    .cache_xlat_paddr             (ifu_cache_xlat_paddr      ),
    .cache_xlat_mat               (ifu_cache_xlat_mat        ),
    .csr_plv                      (csr_plv                   ),
    .csr_da                       (csr_da                    ),
    .csr_pg                       (csr_pg                    ),
    .csr_datf                     (csr_datf                  ),
    .csr_datm                     (csr_datm                  ),
    .csr_asid                     (csr_asid                  ),
    .csr_dmw0                     (csr_dmw0                  ),
    .csr_dmw1                     (csr_dmw1                  ),
    .csr_ptw_en                   (csr_ptw_en                ),
    .tlb_lookup_vld               (ifu_tlb_lookup_vld        ),
    .tlb_lookup_vaddr             (ifu_tlb_lookup_vaddr      ),
    .tlb_lookup_asid              (ifu_tlb_lookup_asid       ),
    .tlb_lookup_hit               (ifu_tlb_lookup_hit        ),
    .tlb_lookup_paddr             (ifu_tlb_lookup_paddr      ),
    .tlb_lookup_dirty             (ifu_tlb_lookup_dirty      ),
    .tlb_lookup_plv               (ifu_tlb_lookup_plv        ),
    .tlb_lookup_mat               (ifu_tlb_lookup_mat        ),
    .port_ptw_req_vld             (ifu_port_ptw_req_vld      ),
    .port_ptw_req_rdy             (ifu_port_ptw_req_rdy      ),
    .port_ptw_req_write           (ifu_port_ptw_req_write    ),
    .port_ptw_req_vaddr           (ifu_port_ptw_req_vaddr    ),
    .port_ptw_req_asid            (ifu_port_ptw_req_asid     ),
    .port_ptw_resp_vld            (ifu_port_ptw_resp_vld     ),
    .port_ptw_resp_vaddr          (ptw_resp_vaddr            ),
    .port_ptw_resp_asid           (ptw_resp_asid             ),
    .port_ptw_resp_ppn            (ptw_resp_ppn              ),
    .port_ptw_resp_ps             (ptw_resp_ps               ),
    .port_ptw_resp_global         (ptw_resp_global           ),
    .port_ptw_resp_dirty          (ptw_resp_dirty            ),
    .port_ptw_resp_plv            (ptw_resp_plv              ),
    .port_ptw_resp_mat            (ptw_resp_mat              ),
    .port_ptw_resp_page_vld       (ptw_resp_page_vld         ),
    .port_ptw_resp_bus_err        (ptw_resp_bus_err          ),
    .port_fill_vld                (ifu_port_fill_vld         ),
    .port_fill_vaddr              (ifu_port_fill_vaddr       ),
    .port_fill_ppn                (ifu_port_fill_ppn         ),
    .port_fill_ps                 (ifu_port_fill_ps          ),
    .port_fill_asid               (ifu_port_fill_asid        ),
    .port_fill_global             (ifu_port_fill_global      ),
    .port_fill_dirty              (ifu_port_fill_dirty       ),
    .port_fill_plv                (ifu_port_fill_plv         ),
    .port_fill_mat                (ifu_port_fill_mat         ),
    .port_auto_inv_vld            (ifu_auto_inv_vld          ),
    .port_auto_inv_vaddr          (ifu_auto_inv_vaddr        ),
    .port_auto_inv_asid           (ifu_auto_inv_asid         )
);

//------------------------------------------------------------//
//                       Data MMU Port
//------------------------------------------------------------//

mmu_port #(
  .IS_FETCH(LSU_IS_FETCH)
) x_mmu_port_lsu (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .kill                         (lsu_kill                  ),
    .cpu_req_vld                  (lsu_req_vld               ),
    .cpu_req_rdy                  (lsu_req_rdy               ),
    .cpu_req_write                (lsu_req_write             ),
    .cpu_req_vaddr                (lsu_req_vaddr             ),
    .cpu_expt_vld                 (lsu_expt_vld              ),
    .cpu_expt_code                (lsu_expt_code             ),
    .cpu_expt_write               (lsu_expt_write            ),
    .cache_req_vld                (lsu_cache_req_vld         ),
    .cache_req_rdy                (lsu_cache_req_rdy         ),
    .cache_req_wait               (lsu_cache_req_wait        ),
    .cache_req_vaddr              (lsu_cache_req_vaddr       ),
    .cache_req_paddr              (lsu_cache_req_paddr       ),
    .cache_req_mat                (lsu_cache_req_mat         ),
    .cache_xlat_vld               (lsu_cache_xlat_vld        ),
    .cache_xlat_cancel            (lsu_cache_xlat_cancel     ),
    .cache_xlat_paddr             (lsu_cache_xlat_paddr      ),
    .cache_xlat_mat               (lsu_cache_xlat_mat        ),
    .csr_plv                      (csr_plv                   ),
    .csr_da                       (csr_da                    ),
    .csr_pg                       (csr_pg                    ),
    .csr_datf                     (csr_datf                  ),
    .csr_datm                     (csr_datm                  ),
    .csr_asid                     (csr_asid                  ),
    .csr_dmw0                     (csr_dmw0                  ),
    .csr_dmw1                     (csr_dmw1                  ),
    .csr_ptw_en                   (csr_ptw_en                ),
    .tlb_lookup_vld               (lsu_tlb_lookup_vld        ),
    .tlb_lookup_vaddr             (lsu_tlb_lookup_vaddr      ),
    .tlb_lookup_asid              (lsu_tlb_lookup_asid       ),
    .tlb_lookup_hit               (lsu_tlb_lookup_hit        ),
    .tlb_lookup_paddr             (lsu_tlb_lookup_paddr      ),
    .tlb_lookup_dirty             (lsu_tlb_lookup_dirty      ),
    .tlb_lookup_plv               (lsu_tlb_lookup_plv        ),
    .tlb_lookup_mat               (lsu_tlb_lookup_mat        ),
    .port_ptw_req_vld             (lsu_port_ptw_req_vld      ),
    .port_ptw_req_rdy             (lsu_port_ptw_req_rdy      ),
    .port_ptw_req_write           (lsu_port_ptw_req_write    ),
    .port_ptw_req_vaddr           (lsu_port_ptw_req_vaddr    ),
    .port_ptw_req_asid            (lsu_port_ptw_req_asid     ),
    .port_ptw_resp_vld            (lsu_port_ptw_resp_vld     ),
    .port_ptw_resp_vaddr          (ptw_resp_vaddr            ),
    .port_ptw_resp_asid           (ptw_resp_asid             ),
    .port_ptw_resp_ppn            (ptw_resp_ppn              ),
    .port_ptw_resp_ps             (ptw_resp_ps               ),
    .port_ptw_resp_global         (ptw_resp_global           ),
    .port_ptw_resp_dirty          (ptw_resp_dirty            ),
    .port_ptw_resp_plv            (ptw_resp_plv              ),
    .port_ptw_resp_mat            (ptw_resp_mat              ),
    .port_ptw_resp_page_vld       (ptw_resp_page_vld         ),
    .port_ptw_resp_bus_err        (ptw_resp_bus_err          ),
    .port_fill_vld                (lsu_port_fill_vld         ),
    .port_fill_vaddr              (lsu_port_fill_vaddr       ),
    .port_fill_ppn                (lsu_port_fill_ppn         ),
    .port_fill_ps                 (lsu_port_fill_ps          ),
    .port_fill_asid               (lsu_port_fill_asid        ),
    .port_fill_global             (lsu_port_fill_global      ),
    .port_fill_dirty              (lsu_port_fill_dirty       ),
    .port_fill_plv                (lsu_port_fill_plv         ),
    .port_fill_mat                (lsu_port_fill_mat         ),
    .port_auto_inv_vld            (lsu_auto_inv_vld          ),
    .port_auto_inv_vaddr          (lsu_auto_inv_vaddr        ),
    .port_auto_inv_asid           (lsu_auto_inv_asid         )
);

//------------------------------------------------------------//
//                        Shared L1TLB
//------------------------------------------------------------//

mmu_tlb x_mmu_tlb (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .lookup0_vld                  (ifu_tlb_lookup_vld        ),
    .lookup0_vaddr                (ifu_tlb_lookup_vaddr      ),
    .lookup0_asid                 (ifu_tlb_lookup_asid       ),
    .lookup0_hit                  (ifu_tlb_lookup_hit        ),
    .lookup0_paddr                (ifu_tlb_lookup_paddr      ),
    .lookup0_dirty                (ifu_tlb_lookup_dirty      ),
    .lookup0_plv                  (ifu_tlb_lookup_plv        ),
    .lookup0_mat                  (ifu_tlb_lookup_mat        ),
    .lookup1_vld                  (lsu_tlb_lookup_vld        ),
    .lookup1_vaddr                (lsu_tlb_lookup_vaddr      ),
    .lookup1_asid                 (lsu_tlb_lookup_asid       ),
    .lookup1_hit                  (lsu_tlb_lookup_hit        ),
    .lookup1_paddr                (lsu_tlb_lookup_paddr      ),
    .lookup1_dirty                (lsu_tlb_lookup_dirty      ),
    .lookup1_plv                  (lsu_tlb_lookup_plv        ),
    .lookup1_mat                  (lsu_tlb_lookup_mat        ),
    .fill_vld                     (tlb_fill_vld              ),
    .fill_vaddr                   (tlb_fill_vaddr            ),
    .fill_ps                      (tlb_fill_ps               ),
    .fill_ppn                     (tlb_fill_ppn              ),
    .fill_asid                    (tlb_fill_asid             ),
    .fill_global                  (tlb_fill_global           ),
    .fill_dirty                   (tlb_fill_dirty            ),
    .fill_plv                     (tlb_fill_plv              ),
    .fill_mat                     (tlb_fill_mat              ),
    .inv_vld                      (tlb_inv_vld               ),
    .inv_op                       (tlb_inv_op                ),
    .inv_asid                     (tlb_inv_asid              ),
    .inv_vaddr                    (tlb_inv_vaddr             )
);

//------------------------------------------------------------//
//                  Shared Page-Table Walker
//------------------------------------------------------------//

mmu_ptw x_mmu_ptw (
    .clk                          (clk                       ),
    .reset                        (reset                     ),
    .ptw_req_vld                  (ptw_req_vld               ),
    .ptw_req_rdy                  (ptw_req_rdy               ),
    .ptw_req_port                 (ptw_req_port              ),
    .ptw_req_write                (ptw_req_write             ),
    .ptw_req_vaddr                (ptw_req_vaddr             ),
    .ptw_req_asid                 (ptw_req_asid              ),
    .csr_pgdl                     (csr_pgdl                  ),
    .csr_pgdh                     (csr_pgdh                  ),
    .csr_dmw0                     (csr_dmw0                  ),
    .csr_dmw1                     (csr_dmw1                  ),
    .csr_pwcl                     (csr_pwcl                  ),
    .csr_pwch                     (csr_pwch                  ),
    .ptw_resp_vld                 (ptw_resp_vld              ),
    .ptw_resp_rdy                 (ptw_resp_rdy              ),
    .ptw_resp_port                (ptw_resp_port             ),
    .ptw_resp_vaddr               (ptw_resp_vaddr            ),
    .ptw_resp_asid                (ptw_resp_asid             ),
    .ptw_resp_ppn                 (ptw_resp_ppn              ),
    .ptw_resp_ps                  (ptw_resp_ps               ),
    .ptw_resp_global              (ptw_resp_global           ),
    .ptw_resp_dirty               (ptw_resp_dirty            ),
    .ptw_resp_plv                 (ptw_resp_plv              ),
    .ptw_resp_mat                 (ptw_resp_mat              ),
    .ptw_resp_page_vld            (ptw_resp_page_vld         ),
    .ptw_resp_bus_err             (ptw_resp_bus_err          ),
    .ptw_mem_req_vld              (ptw_dcache_req_vld        ),
    .ptw_mem_req_rdy              (dcache_ptw_req_rdy        ),
    .ptw_mem_req_paddr            (ptw_dcache_req_paddr      ),
    .ptw_mem_resp_vld             (dcache_ptw_resp_vld       ),
    .ptw_mem_resp_data            (dcache_ptw_resp_data      ),
    .ptw_mem_resp_err             (dcache_ptw_resp_err       )
);

endmodule
`endif
