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

`ifdef OPEN132_INTERFACE_AXI
module biu_axi_sysbus #(
    parameter PERF_CNT_NUM  = -1,
    parameter AXI_DATA_WD   = -1,  // 32/64/128
    // ICache
    parameter HAS_ICC       = -1,  // 0 or 1
    parameter ICC_SET_ASSOC = -1,  // 1/2/4 way set associative
    parameter ICC_WAYSIZE   = -1,  // 1/2/4/8/16 KB Size/way
    parameter ICC_ECC_BITS  = -1,  // 1/7/8/9 bits, for no ecc, 32+7, 64+8, 128+9
    // DCache
    parameter HAS_DCC       = -1,  // 0 or 1
    parameter DCC_SET_ASSOC = -1,  // 1/2/4 way set associative
    parameter DCC_WAYSIZE   = -1,  // 1/2/4/8/16 KB Size/way
    parameter DCC_ECC_BITS  = -1   // 1/7/8/9 bits, for no ecc, 32+7, 64+8, 128+9
) (
    // clk and reset
    input  wire                                              clk,
    input  wire                                              clk_ng,  // clk no-gating
    input  wire                                              reset,
    input  wire                                              data_reset,

    input  wire                                              ctrl_nowrap,  // axi no wrap

    input  wire                                              ex_cancel,

    // <->ifc
    input  wire                                              fetch_dbgm,
    input  wire [                                    31: 0]  fetch_vaddr,
    input  wire                                              memld_st_dbgm,
    input  wire [                                    31: 0]  de_mald_vaddr,
    input  wire [                                    31: 0]  memld_st_vaddr,  // load (in mem stage, maybe cache) or store address
    input  wire                                              memld_st_write,
    input  wire [                                     1: 0]  memld_st_size,
    input  wire [                                     3: 0]  memld_st_strb,
    input  wire [                                    31: 0]  st_wdata,  // set at same time with addr request! so need be registered for ahb.

    input  wire                                              de_load_req,  // for dcc_cd_hit_wr
    input  wire                                              memld_st_req,  // for dcc_md_hit_wr
    input  wire                                              memld_st_exc,  // for LL/SC
    input  wire                                              memld_st_dald,  // for device-load wait axi-b
    input  wire                                              sbus_sel_ft,  // predict
    input  wire                                              sbus_sel_mald,  // predict
    input  wire                                              sbus_real_sel_ft,  // real
    input  wire                                              sbus_real_sel_mald,  // real
    input  wire                                              sbus_sel_memld_st,  // real
    input  wire                                              ft_pre_s_ok,
    input  wire                                              mald_pre_s_ok,
    input  wire                                              ft_pre_s_err,
    input  wire                                              mald_pre_s_err,

    output wire                                              ft_in_sysbus,
    output wire                                              ld_in_sysbus,
    output wire                                              sysbus_mem_null,  // dcache no access is doing
    output wire                                              sysbus_ft_null,  // icache no access is doing

    output wire                                              fetch_req_s_ready,
    output wire                                              de_mald_req_s_ready,
    output wire                                              memld_st_req_s_ready,

    output wire                                              ft_data_s_ready,
    output wire                                              ld_data_s_ready,
    output wire                                              ld_data_s_exok,
    output wire [                                    31: 0]  ft_data_s_rdata,
    output wire [                                    31: 0]  ld_data_s_rdata,
    output wire                                              ft_data_s_err,
    output wire                                              ld_data_s_err,
`ifdef CONFIG_MMU
    output wire                                              ft_mmu_expt_vld,
    output wire [                                     5: 0]  ft_mmu_expt_code,
    output wire                                              ld_mmu_expt_vld,
    output wire [                                     5: 0]  ld_mmu_expt_code,
    output wire                                              ld_mmu_expt_write,
`endif
    // sys axi
    // ar
    input  wire                                              sys_arready,
    output wire [                                     3: 0]  sys_arid,
    output wire [                                    31: 0]  sys_araddr,
    output wire [                                     3: 0]  sys_arlen,
    output wire [                                     2: 0]  sys_arsize,
    output wire [                                     1: 0]  sys_arburst,
    output wire [                                     1: 0]  sys_arlock,
    output wire [                                     3: 0]  sys_arcache,
    output wire [                                     2: 0]  sys_arprot,
    output wire                                              sys_arvalid,
    // r
    input  wire [                                     3: 0]  sys_rid,
    input  wire [                         AXI_DATA_WD-1: 0]  sys_rdata,
    input  wire [                                     1: 0]  sys_rresp,
    input  wire                                              sys_rlast,
    input  wire                                              sys_rvalid,
    output wire                                              sys_rready,
    // aw
    input  wire                                              sys_awready,
    output wire [                                     3: 0]  sys_awid,
    output wire [                                    31: 0]  sys_awaddr,
    output wire [                                     3: 0]  sys_awlen,
    output wire [                                     2: 0]  sys_awsize,
    output wire [                                     1: 0]  sys_awburst,
    output wire [                                     1: 0]  sys_awlock,
    output wire [                                     3: 0]  sys_awcache,
    output wire [                                     2: 0]  sys_awprot,
    output wire                                              sys_awvalid,
    // w
    input  wire                                              sys_wready,
    output wire [                                     3: 0]  sys_wid,
    output wire [                         AXI_DATA_WD-1: 0]  sys_wdata,
    output wire [                       AXI_DATA_WD/8-1: 0]  sys_wstrb,
    output wire                                              sys_wlast,
    output wire                                              sys_wvalid,
    // b
    input  wire [                                     3: 0]  sys_bid,
    input  wire [                                     1: 0]  sys_bresp,
    input  wire                                              sys_bvalid,
    output wire                                              sys_bready,

    // cache/isync/pref inst
    input  wire                                              mem_cps_req,
    input  wire [                                    31: 0]  mem_sttag_data,
    input  wire                                              mem_cc_op_i,
    input  wire                                              mem_cc_op_d,
    input  wire [                                     5: 0]  mem_cc_op,
    input  wire                                              mem_cc_fill,
    input  wire                                              mem_cc_lock,
    input  wire                                              mem_cc_pref,
    output wire                                              mem_cps_req_ready,
    output wire                                              mem_cps_data_ready,
    output wire [                                    31: 0]  mem_cps_data_rdata,

    input  wire                                              resetn_in_d2,
    output wire                                              ram_init_cmplt,

    // mmu
    input  wire [     `OPEN132_CSR_CACHE_CTRL_BUS_WIDTH-1: 0]  csr_cache_ctrl_bus,
`ifdef CONFIG_MMU
    input  wire [       `OPEN132_CSR_MMU_CTRL_BUS_WIDTH-1: 0]  csr_mmu_ctrl_bus,
`endif
    // performance count
    output wire [   `OPEN132_CACHE_PERF_EVENT_BUS_WIDTH-1: 0]  cache_csr_perf_bus,

    // ecc fatal
    output wire [`OPEN132_CACHE_LSU_ECC_FATAL_BUS_WIDTH-1: 0]  cache_lsu_ecc_fatal_bus,
    // dcache ram
    output wire [    `OPEN132_DCC_RAM_TAGV_REQ_BUS_WD-1: 0]  dcc_ram_tagv_req_bus,
    output wire [    `OPEN132_DCC_RAM_DATA_REQ_BUS_WD-1: 0]  dcc_ram_data_req_bus,
    output wire [    `OPEN132_DCC_RAM_LRUD_REQ_BUS_WD-1: 0]  dcc_ram_lrud_req_bus,  // write by bit
    input  wire [   `OPEN132_DCC_RAM_TAGV_RESP_BUS_WD-1: 0]  dcc_ram_tagv_resp_bus,
    input  wire [   `OPEN132_DCC_RAM_DATA_RESP_BUS_WD-1: 0]  dcc_ram_data_resp_bus,
    input  wire [   `OPEN132_DCC_RAM_LRUD_RESP_BUS_WD-1: 0]  dcc_ram_lrud_resp_bus,
    // icache ram
    output wire [    `OPEN132_ICC_RAM_TAGV_REQ_BUS_WD-1: 0]  icc_ram_tagv_req_bus,
    output wire [    `OPEN132_ICC_RAM_DATA_REQ_BUS_WD-1: 0]  icc_ram_data_req_bus,
    output wire [    `OPEN132_ICC_RAM_LRUD_REQ_BUS_WD-1: 0]  icc_ram_lrud_req_bus,  // write by bit
    input  wire [   `OPEN132_ICC_RAM_TAGV_RESP_BUS_WD-1: 0]  icc_ram_tagv_resp_bus,
    input  wire [   `OPEN132_ICC_RAM_DATA_RESP_BUS_WD-1: 0]  icc_ram_data_resp_bus,
    input  wire [   `OPEN132_ICC_RAM_LRUD_RESP_BUS_WD-1: 0]  icc_ram_lrud_resp_bus

`ifdef OPEN132_HAS_LJTAG
    ,
    output wire [                                    55: 0]  biu_jtag_debug_req_bus,
    input  wire [                                    32: 0]  jtag_biu_debug_resp_bus
`endif
);

// dcache module
localparam DCC_CACHE_TAGV_RESP_WD = `OPEN132_DCC_RAM_TAGV_WD_ECC;
localparam DCC_CACHE_TAGV_REQ_WD  = `OPEN132_DCC_TAGV_EN_WD +
                                      `OPEN132_DCC_TAGV_WEN_WD +
                                      `OPEN132_DCC_INDEX_BITS + DCC_CACHE_TAGV_RESP_WD;
localparam DCC_CACHE_DATA_RESP_WD = 8*`OPEN132_DCC_RAM_BANK_WD_ECC;
localparam DCC_CACHE_DATA_REQ_WD  = 8*(`OPEN132_DCC_BANK_EN_WD +
                                      `OPEN132_DCC_BANK_WEN_WD +
                                      `OPEN132_DCC_INDEX_BITS +
                                      `OPEN132_DCC_RAM_BANK_WD_ECC);
localparam DCC_CACHE_LRUD_RESP_WD = `OPEN132_DCC_LRU_BITS + `OPEN132_DCC_SET_ASSOC;
localparam DCC_CACHE_LRUD_REQ_WD  = 1 + 2*DCC_CACHE_LRUD_RESP_WD +
                                      `OPEN132_DCC_INDEX_BITS;

// icache module
localparam ICC_CACHE_TAGV_RESP_WD = `OPEN132_ICC_RAM_TAGV_WD_ECC;
localparam ICC_CACHE_TAGV_REQ_WD  = `OPEN132_ICC_TAGV_EN_WD +
                                      `OPEN132_ICC_TAGV_WEN_WD +
                                      `OPEN132_ICC_INDEX_BITS + ICC_CACHE_TAGV_RESP_WD;
localparam ICC_CACHE_DATA_RESP_WD = 8*`OPEN132_ICC_RAM_BANK_WD_ECC;
localparam ICC_CACHE_DATA_REQ_WD  = 8*(`OPEN132_ICC_BANK_EN_WD +
                                      `OPEN132_ICC_BANK_WEN_WD +
                                      `OPEN132_ICC_INDEX_BITS +
                                      `OPEN132_ICC_RAM_BANK_WD_ECC);
localparam ICC_CACHE_LRUD_RESP_WD = `OPEN132_ICC_LRU_BITS + `OPEN132_ICC_SET_ASSOC;
localparam ICC_CACHE_LRUD_REQ_WD  = 1 + 2*ICC_CACHE_LRUD_RESP_WD +
                                      `OPEN132_ICC_INDEX_BITS;

localparam AXI_DATA_CACHE0             = AXI_DATA_WD;
localparam AXI_WID_N_CACHE0            = `OPEN132_N_AXI_WID;
localparam SET_ASSOC_CACHE0            = `OPEN132_DCC_SET_ASSOC;
localparam WAYSIZE_CACHE0              = `OPEN132_DCC_WAYSIZE;
localparam ECC_BITS_CACHE0             = `OPEN132_DCC_ECC_BITS;
localparam RAM_TAGV_REQ_BUS_WD_CACHE0  = DCC_CACHE_TAGV_REQ_WD;
localparam RAM_DATA_REQ_BUS_WD_CACHE0  = DCC_CACHE_DATA_REQ_WD;
localparam RAM_LRUD_REQ_BUS_WD_CACHE0  = DCC_CACHE_LRUD_REQ_WD;
localparam RAM_TAGV_RESP_BUS_WD_CACHE0 = DCC_CACHE_TAGV_RESP_WD;
localparam RAM_DATA_RESP_BUS_WD_CACHE0 = DCC_CACHE_DATA_RESP_WD;
localparam RAM_LRUD_RESP_BUS_WD_CACHE0 = DCC_CACHE_LRUD_RESP_WD;

localparam AXI_DATA_NC_CH0 = AXI_DATA_WD;

localparam AXI_DATA_CACHE1             = AXI_DATA_WD;
localparam AXI_WID_N_CACHE1            = 1;
localparam SET_ASSOC_CACHE1            = `OPEN132_ICC_SET_ASSOC;
localparam WAYSIZE_CACHE1              = `OPEN132_ICC_WAYSIZE;
localparam ECC_BITS_CACHE1             = `OPEN132_ICC_ECC_BITS;
localparam RAM_TAGV_REQ_BUS_WD_CACHE1  = ICC_CACHE_TAGV_REQ_WD;
localparam RAM_DATA_REQ_BUS_WD_CACHE1  = ICC_CACHE_DATA_REQ_WD;
localparam RAM_LRUD_REQ_BUS_WD_CACHE1  = ICC_CACHE_LRUD_REQ_WD;
localparam RAM_TAGV_RESP_BUS_WD_CACHE1 = ICC_CACHE_TAGV_RESP_WD;
localparam RAM_DATA_RESP_BUS_WD_CACHE1 = ICC_CACHE_DATA_RESP_WD;
localparam RAM_LRUD_RESP_BUS_WD_CACHE1 = ICC_CACHE_LRUD_RESP_WD;

localparam AXI_DATA_NC_CH1 = AXI_DATA_WD;

localparam MPU_NUM_VATTR    = 4;
localparam CFGSEG_NUM_VATTR = `OPEN132_CFGSEG_NUM;

//============================================================//
//                     Regs Declarations
//============================================================//

// performance count
reg          dcc_uc_req_ok_r;
reg          icc_c_req_ok_r;

// ar
reg          ar_valid_r;
reg          ar_fetch_r;
reg          ar_burst_r;
reg          ar_exc_r;
reg          ar_cache_r;
reg [  2: 0] ar_size_r;
reg [ 31: 0] ar_addr_r;

// r
reg                    rvalid_r;
reg                    rid0_r;
reg [AXI_DATA_WD-1: 0] rdata_r;
reg [            1: 0] rresp_r;

// wait flag
reg          ft_wait;  // fetch:after ar_ok and wait rdata
reg          ld_wait;  // load :
`ifdef OPEN132_HAS_LJTAG

// sel dcc or icc to dbgm
reg          dbgm_sel_icc;
`endif

//============================================================//
//                     Wire Declarations
//============================================================//

wire                                        is_icache_cache0;
wire                                        clk_cache0;
wire                                        clk_ng_cache0;
wire                                        reset_cache0;
wire                                        data_reset_cache0;
wire                                        ctrl_nowrap_cache0;
wire                                        ex_cancel_cache0;
wire                                        req_rd_wr_cache0;
wire                                        req_rd_cache0;
wire                                        req_exc_cache0;
wire [                                1: 0] size_cache0;
`ifdef CONFIG_MMU
wire [                               31: 0] vaddr_cache0;
`else
wire [                                2: 0] vaddr_h3_cache0;
`endif
wire [                               31: 0] paddr_cache0;
`ifdef CONFIG_MMU
wire                                        req_xlat_wait_cache0;
wire                                        req_attr_vld_cache0;
wire                                        req_sob_cache0;
wire                                        req_cached_cache0;
wire                                        req_alloc_cache0;
wire                                        xlat_vld_cache0;
wire                                        xlat_cancel_cache0;
wire [                               31: 0] xlat_paddr_cache0;
wire                                        xlat_sob_cache0;
wire                                        xlat_cached_cache0;
wire                                        xlat_alloc_cache0;
`endif
wire [                               31: 0] wdata_cache0;
wire [                               31: 0] rdata_cache0;
wire                                        rdata_valid_cache0;
wire                                        rdata_exok_cache0;
wire                                        rdata_err_cache0;
wire                                        rd_in_sysbus_cache0;
wire                                        axi_null_cache0;
wire [                               31: 0] go_mmu_vaddr_cache0;
wire                                        go_mmu_read_cache0;
wire                                        go_mmu_dbgm_cache0;
wire                                        mmu_sob_cache0;
wire                                        mmu_cached_cache0;
wire                                        mmu_alloc_cache0;
wire                                        req2dbgm_cache0;
wire                                        dbgm_req_valid_cache0;
wire                                        dbgm_req_wr_cache0;
wire [                               31: 0] dbgm_req_addr_cache0;
wire [                                1: 0] dbgm_req_size_cache0;
wire [                               31: 0] dbgm_req_wdata_cache0;
wire                                        dbgm_resp_valid_cache0;
wire [                               31: 0] dbgm_resp_data_cache0;
wire                                        dcc_ar_stall_icc_cache0;
wire                                        axi_arvalid_cache0;
wire                                        axi_arready_cache0;
wire                                        axi_arburst_cache0;
wire                                        axi_arexc_cache0;
wire                                        axi_arcache_cache0;
wire [                                2: 0] axi_arsize_cache0;
wire [                               31: 0] axi_araddr_cache0;
wire                                        axi_rvalid_cache0;
wire [                AXI_DATA_CACHE0-1: 0] axi_rdata_cache0;
wire [                                1: 0] axi_rresp_cache0;
wire [                                2: 0] axi_aw_wid_cache0;
wire                                        axi_awvalid_cache0;
wire                                        axi_awready_cache0;
wire                                        axi_awburst_cache0;
wire                                        axi_awexc_cache0;
wire                                        axi_awcache_cache0;
wire [                                2: 0] axi_awsize_cache0;
wire [                               31: 0] axi_awaddr_cache0;
wire                                        axi_wvalid_cache0;
wire                                        axi_wready_cache0;
wire [              AXI_DATA_CACHE0/8-1: 0] axi_wstrb_cache0;
wire [                AXI_DATA_CACHE0-1: 0] axi_wdata_cache0;
wire                                        axi_wlast_cache0;
wire                                        axi_bvalid_cache0;
wire [                                2: 0] axi_bid_cache0;
wire                                        all_addr_ok_cache0;
wire                                        req_pre_err_cache0;
wire [                                2: 0] req_bank_cache0;
wire [                                5: 0] cc_op_cache0;
wire                                        cc_isync_cache0;
wire [                               31: 0] cc_sttag_cache0;
wire                                        cc_pref_cache0;
wire                                        cc_lock_cache0;
wire                                        cc_op_stall_cache0;
wire                                        cps_req_ok_cache0;
wire                                        cps_data_ok_cache0;
wire [                               31: 0] cps_rdata_cache0;
wire                                        bypass_cache0;
wire                                        all_fatal_cache0;
wire                                        load_fatal_cache0;
wire                                        store_fatal_cache0;
wire                                        ccop_fatal_cache0;
wire                                        rf_impr_fatal_cache0;
wire                                        fatal_intagv_cache0;
wire [                                7: 0] fatal_indata_cache0;
wire [       $clog2(WAYSIZE_CACHE0)-5-1: 0] fatal_indx_cache0;
wire [               SET_ASSOC_CACHE0-1: 0] fatal_way_cache0;
wire                                        fatal_dirtywb_cache0;
wire [32-($clog2(WAYSIZE_CACHE0)-5)-5-1: 0] fatal_dirty_tag_cache0;
wire                                        all_ecc_err_add1_cache0;
wire                                        refill_add1_cache0;
wire                                        resetn_in_d2_cache0;
wire                                        ram_init_cmplt_cache0;
wire [     RAM_TAGV_REQ_BUS_WD_CACHE0-1: 0] ram_tagv_req_bus_cache0;
wire [     RAM_DATA_REQ_BUS_WD_CACHE0-1: 0] ram_data_req_bus_cache0;
wire [     RAM_LRUD_REQ_BUS_WD_CACHE0-1: 0] ram_lrud_req_bus_cache0;
wire [    RAM_TAGV_RESP_BUS_WD_CACHE0-1: 0] ram_tagv_resp_bus_cache0;
wire [    RAM_DATA_RESP_BUS_WD_CACHE0-1: 0] ram_data_resp_bus_cache0;
wire [    RAM_LRUD_RESP_BUS_WD_CACHE0-1: 0] ram_lrud_resp_bus_cache0;
wire                                        is_icache_nc_ch0;
wire                                        clk_nc_ch0;
wire                                        clk_ng_nc_ch0;
wire                                        reset_nc_ch0;
wire                                        data_reset_nc_ch0;
wire                                        ex_cancel_nc_ch0;
wire                                        req_rd_wr_nc_ch0;
wire                                        req_rd_nc_ch0;
wire                                        req_exc_nc_ch0;
wire [                                1: 0] size_nc_ch0;
wire [                               31: 0] paddr_nc_ch0;
wire [                               31: 0] wdata_nc_ch0;
wire [                               31: 0] rdata_nc_ch0;
wire                                        rdata_valid_nc_ch0;
wire                                        rdata_exok_nc_ch0;
wire                                        rdata_err_nc_ch0;
wire                                        rd_in_sysbus_nc_ch0;
wire                                        axi_null_nc_ch0;
wire                                        req2dbgm_nc_ch0;
wire                                        dbgm_req_valid_nc_ch0;
wire                                        dbgm_req_wr_nc_ch0;
wire [                               31: 0] dbgm_req_addr_nc_ch0;
wire [                                1: 0] dbgm_req_size_nc_ch0;
wire [                               31: 0] dbgm_req_wdata_nc_ch0;
wire                                        dbgm_resp_valid_nc_ch0;
wire [                               31: 0] dbgm_resp_data_nc_ch0;
wire                                        dcc_ar_stall_icc_nc_ch0;
wire                                        axi_arvalid_nc_ch0;
wire                                        axi_arready_nc_ch0;
wire                                        axi_arburst_nc_ch0;
wire                                        axi_arexc_nc_ch0;
wire                                        axi_arcache_nc_ch0;
wire [                                2: 0] axi_arsize_nc_ch0;
wire [                               31: 0] axi_araddr_nc_ch0;
wire                                        axi_rvalid_nc_ch0;
wire [                AXI_DATA_NC_CH0-1: 0] axi_rdata_nc_ch0;
wire [                                1: 0] axi_rresp_nc_ch0;
wire [                                2: 0] axi_aw_wid_nc_ch0;
wire                                        axi_awvalid_nc_ch0;
wire                                        axi_awready_nc_ch0;
wire                                        axi_awburst_nc_ch0;
wire                                        axi_awexc_nc_ch0;
wire                                        axi_awcache_nc_ch0;
wire [                                2: 0] axi_awsize_nc_ch0;
wire [                               31: 0] axi_awaddr_nc_ch0;
wire                                        axi_wvalid_nc_ch0;
wire                                        axi_wready_nc_ch0;
wire [              AXI_DATA_NC_CH0/8-1: 0] axi_wstrb_nc_ch0;
wire [                AXI_DATA_NC_CH0-1: 0] axi_wdata_nc_ch0;
wire                                        axi_wlast_nc_ch0;
wire                                        axi_bvalid_nc_ch0;
wire [                                2: 0] axi_bid_nc_ch0;
wire                                        cd_ar_addr_ok_nc_ch0;
wire                                        md_ar_addr_ok_nc_ch0;
wire                                        aw_addr_ok_nc_ch0;
wire                                        dbgm_addr_ok_nc_ch0;
wire                                        cd_hit_wr_nc_ch0;
wire                                        md_hit_wr_nc_ch0;
wire                                        is_icache_cache1;
wire                                        clk_cache1;
wire                                        clk_ng_cache1;
wire                                        reset_cache1;
wire                                        data_reset_cache1;
wire                                        ctrl_nowrap_cache1;
wire                                        ex_cancel_cache1;
wire                                        req_rd_wr_cache1;
wire                                        req_rd_cache1;
wire                                        req_exc_cache1;
wire [                                1: 0] size_cache1;
`ifdef CONFIG_MMU
wire [                               31: 0] vaddr_cache1;
`else
wire [                                2: 0] vaddr_h3_cache1;
`endif
wire [                               31: 0] paddr_cache1;
`ifdef CONFIG_MMU
wire                                        req_xlat_wait_cache1;
wire                                        req_attr_vld_cache1;
wire                                        req_sob_cache1;
wire                                        req_cached_cache1;
wire                                        req_alloc_cache1;
wire                                        xlat_vld_cache1;
wire                                        xlat_cancel_cache1;
wire [                               31: 0] xlat_paddr_cache1;
wire                                        xlat_sob_cache1;
wire                                        xlat_cached_cache1;
wire                                        xlat_alloc_cache1;
`endif
wire [                               31: 0] wdata_cache1;
wire [                               31: 0] rdata_cache1;
wire                                        rdata_valid_cache1;
wire                                        rdata_err_cache1;
wire                                        rd_in_sysbus_cache1;
wire                                        axi_null_cache1;
wire [                               31: 0] go_mmu_vaddr_cache1;
wire                                        go_mmu_dbgm_cache1;
wire                                        mmu_sob_cache1;
wire                                        mmu_cached_cache1;
wire                                        mmu_alloc_cache1;
wire                                        req2dbgm_cache1;
wire                                        dbgm_req_valid_cache1;
wire [                               31: 0] dbgm_req_addr_cache1;
wire [                                1: 0] dbgm_req_size_cache1;
wire                                        dbgm_resp_valid_cache1;
wire [                               31: 0] dbgm_resp_data_cache1;
wire                                        axi_arvalid_cache1;
wire                                        axi_arready_cache1;
wire                                        axi_arburst_cache1;
wire                                        axi_arcache_cache1;
wire [                                2: 0] axi_arsize_cache1;
wire [                               31: 0] axi_araddr_cache1;
wire                                        axi_rvalid_cache1;
wire [                AXI_DATA_CACHE1-1: 0] axi_rdata_cache1;
wire [                                1: 0] axi_rresp_cache1;
wire                                        axi_awready_cache1;
wire                                        axi_wready_cache1;
wire                                        axi_bvalid_cache1;
wire [                                2: 0] axi_bid_cache1;
wire                                        all_addr_ok_cache1;
wire                                        req_pre_err_cache1;
wire [                                2: 0] req_bank_cache1;
wire [                                5: 0] cc_op_cache1;
wire                                        cc_isync_cache1;
wire [                               31: 0] cc_sttag_cache1;
wire                                        cc_pref_cache1;
wire                                        cc_lock_cache1;
wire                                        cc_op_stall_cache1;
wire                                        cps_req_ok_cache1;
wire                                        cps_data_ok_cache1;
wire [                               31: 0] cps_rdata_cache1;
wire                                        bypass_cache1;
wire                                        all_fatal_cache1;
wire                                        load_fatal_cache1;
wire                                        ccop_fatal_cache1;
wire                                        rf_impr_fatal_cache1;
wire                                        fatal_intagv_cache1;
wire [                                7: 0] fatal_indata_cache1;
wire [       $clog2(WAYSIZE_CACHE1)-5-1: 0] fatal_indx_cache1;
wire [               SET_ASSOC_CACHE1-1: 0] fatal_way_cache1;
wire                                        all_ecc_err_add1_cache1;
wire                                        refill_add1_cache1;
wire                                        resetn_in_d2_cache1;
wire                                        ram_init_cmplt_cache1;
wire [     RAM_TAGV_REQ_BUS_WD_CACHE1-1: 0] ram_tagv_req_bus_cache1;
wire [     RAM_DATA_REQ_BUS_WD_CACHE1-1: 0] ram_data_req_bus_cache1;
wire [     RAM_LRUD_REQ_BUS_WD_CACHE1-1: 0] ram_lrud_req_bus_cache1;
wire [    RAM_TAGV_RESP_BUS_WD_CACHE1-1: 0] ram_tagv_resp_bus_cache1;
wire [    RAM_DATA_RESP_BUS_WD_CACHE1-1: 0] ram_data_resp_bus_cache1;
wire [    RAM_LRUD_RESP_BUS_WD_CACHE1-1: 0] ram_lrud_resp_bus_cache1;
wire                                        is_icache_nc_ch1;
wire                                        clk_nc_ch1;
wire                                        clk_ng_nc_ch1;
wire                                        reset_nc_ch1;
wire                                        data_reset_nc_ch1;
wire                                        ex_cancel_nc_ch1;
wire                                        req_rd_wr_nc_ch1;
wire                                        req_rd_nc_ch1;
wire                                        req_exc_nc_ch1;
wire [                                1: 0] size_nc_ch1;
wire [                               31: 0] paddr_nc_ch1;
wire [                               31: 0] wdata_nc_ch1;
wire [                               31: 0] rdata_nc_ch1;
wire                                        rdata_valid_nc_ch1;
wire                                        rdata_err_nc_ch1;
wire                                        rd_in_sysbus_nc_ch1;
wire                                        axi_null_nc_ch1;
wire                                        req2dbgm_nc_ch1;
wire                                        dbgm_req_valid_nc_ch1;
wire [                               31: 0] dbgm_req_addr_nc_ch1;
wire [                                1: 0] dbgm_req_size_nc_ch1;
wire                                        dbgm_resp_valid_nc_ch1;
wire [                               31: 0] dbgm_resp_data_nc_ch1;
wire                                        axi_arvalid_nc_ch1;
wire                                        axi_arready_nc_ch1;
wire                                        axi_arburst_nc_ch1;
wire                                        axi_arcache_nc_ch1;
wire [                                2: 0] axi_arsize_nc_ch1;
wire [                               31: 0] axi_araddr_nc_ch1;
wire                                        axi_rvalid_nc_ch1;
wire [                AXI_DATA_NC_CH1-1: 0] axi_rdata_nc_ch1;
wire [                                1: 0] axi_rresp_nc_ch1;
wire                                        axi_awready_nc_ch1;
wire                                        axi_wready_nc_ch1;
wire                                        axi_bvalid_nc_ch1;
wire [                                2: 0] axi_bid_nc_ch1;
wire                                        cd_ar_addr_ok_nc_ch1;
wire                                        dbgm_addr_ok_nc_ch1;
wire                                        cd_hit_wr_nc_ch1;
wire                                        md_hit_wr_nc_ch1;
wire                                        lisa_da_v2p0;
wire [                               23: 0] lisa_segpa_v2p0;
wire [                                2: 0] vaddr_h3_v2p0;
wire [                                2: 0] paddr_h3_v2p0;
wire                                        lisa_da_v2p1;
wire [                               23: 0] lisa_segpa_v2p1;
wire [                                2: 0] vaddr_h3_v2p1;
wire [                                2: 0] paddr_h3_v2p1;
wire                                        lisa_da_vattr;
wire [                                1: 0] lisa_dacf_vattr;
wire [                                1: 0] lisa_dacm_vattr;
wire [                                3: 0] mpu_valid_vattr;
wire [                               79: 0] mpu_base_vattr;
wire [                               79: 0] mpu_mask_vattr;
wire [                               15: 0] mpu_calg_vattr;
wire [                               31: 0] cfgseg_calg_vattr;
wire [                               31: 0] dcc_vaddr_vattr;
wire                                        dcc_read_vattr;
wire                                        dcc_dbgm_vattr;
wire                                        dcc_addr_sob_vattr;
wire                                        dcc_addr_cached_vattr;
wire                                        dcc_addr_alloc_vattr;
wire [                               31: 0] icc_vaddr_vattr;
wire                                        icc_dbgm_vattr;
wire                                        icc_addr_cached_vattr;

// no care
wire [  3: 0] memld_st_strb_nc;
wire [  3: 1] sys_rid_nc;
wire          sys_bid3_nc;
wire [  1: 0] sys_bresp_nc;

wire [4*`OPEN132_CFGSEG_NUM-1: 0] cfgseg_calg;
wire                              lisa_da;
wire [                      1: 0] lisa_dacf;
wire [                      1: 0] lisa_dacm;
wire [                     23: 0] lisa_segpa;
wire [                  1*4-1: 0] mpu_valid;    // 4 mpu
wire [                 20*4-1: 0] mpu_base;
wire [                 20*4-1: 0] mpu_mask;
wire [                  4*4-1: 0] mpu_calg;
wire                              dcc_bypass;
wire                              icc_bypass;

// dcc/icc uncached/cached for sysbus access
wire          dcc_uncached_sbus;  // dcc_cached_sbus is not precise, so we don't count it.
wire          icc_cached_sbus;    // icc_cached_sbus is precise as icc_uncached_sbus

// ecc performance count
wire                                          dcc_all_ecc_err_add1;
wire                                          dcc_refill_add1;       // cache refill
wire                                          icc_all_ecc_err_add1;
wire                                          icc_refill_add1;       // cache refill
wire [`OPEN132_CACHE_PERF_EVENT_BUS_WIDTH-1: 0] cache_perf_events;

// sysbus sel fetch/load/store
// sell{HAS CACHE}/{NO CACHE}
// they have different values in HAS CACHE or NO CACHE
wire          req_ft;
wire          req_mald;
wire          req_memld_st;

// wire req_mem = req_mald   || req_memld_st;
wire          req_ft_pre_ok;
wire          req_mald_pre_ok;
wire          icc_stall_cps;
wire          dcc_stall_cps;

wire          dcc_ram_init_cmplt;

// ifc
wire          dcc_req_rd_wr;
wire          dcc_req_rd;
wire          dcc_req_exc;        // exclusive
wire [  1: 0] dcc_size;
wire [ 31: 0] dcc_vaddr;
wire [ 31: 0] dcc_paddr;          // no-cache: combination with vaddr; cache: register vaddr.
wire [  2: 0] dcc_req_bank;
wire [ 31: 0] dcc_wdata;
wire          dcc_cd_ar_addr_ok;  // for cacheld
wire          dcc_md_ar_addr_ok;  // for memld
wire          dcc_aw_addr_ok;
wire          dcc_dbgm_addr_ok;
wire          dcc_ar_stall_icc;
wire [ 31: 0] dcc_rdata;
wire          dcc_rdata_valid;    // rdata back
wire          dcc_rdata_exok;     // rdata back exokay
wire          dcc_rdata_err;      // valid if dcc_rdata_valid==1
wire          dcc_rd_in_sysbus;

// wire       dcc_wr_in_sysbus;
wire          dcc_axi_null;

// mmu
wire [ 31: 0] dcc_cc_vaddr;         // from tagcmp, for HAS_CACHE
wire          dcc_cc_read;
wire          dcc_cc_dbgm;
wire          dcc_sob;              // strong-order-back
wire          dcc_cached;
wire          dcc_cc_alloc;         // alloc if miss, for HAS_CACHE
wire          dcc_req2dbgm;
wire          dcc_dbgm_req_valid;
wire          dcc_dbgm_req_wr;
wire [ 31: 0] dcc_dbgm_req_addr;
wire [  1: 0] dcc_dbgm_req_size;
wire [ 31: 0] dcc_dbgm_req_wdata;
wire          dcc_dbgm_resp_valid;
wire [ 31: 0] dcc_dbgm_resp_data;

// axi
wire                    dcc_axi_arvalid;  // read request
wire                    dcc_axi_arready;  // read request received
wire                    dcc_axi_arburst;  // read burst
wire                    dcc_axi_arexc;    // read exclusive
wire                    dcc_axi_arcache;  // read cached
wire [            2: 0] dcc_axi_arsize;   // read size
wire [           31: 0] dcc_axi_araddr;   // read addr
wire                    dcc_axi_rvalid;   // read response valid
wire [AXI_DATA_WD-1: 0] dcc_axi_rdata;    // read data
wire [            1: 0] dcc_axi_rresp;    // read response

wire [              2: 0] dcc_axi_aw_wid;   // write id for awid/wid
wire                      dcc_axi_awvalid;  // write request
wire                      dcc_axi_awready;  // write request received
wire                      dcc_axi_awburst;  // write burst
wire                      dcc_axi_awexc;    // write exclusive
wire                      dcc_axi_awcache;  // write cached
wire [              2: 0] dcc_axi_awsize;   // write size
wire [             31: 0] dcc_axi_awaddr;   // write addr
wire                      dcc_axi_wvalid;   // write data request
wire                      dcc_axi_wready;   // write data received
wire [AXI_DATA_WD/8-1: 0] dcc_axi_wstrb;    // write strobe
wire [  AXI_DATA_WD-1: 0] dcc_axi_wdata;    // write data
wire                      dcc_axi_wlast;    // write last data
wire                      dcc_axi_bvalid;   // write response valid
wire [              2: 0] dcc_axi_bid;      // write bid[2:0]

wire [  5: 0] dcc_cc_op;
wire [ 31: 0] dcc_cc_sttag;
wire          dcc_cc_pref;
wire          dcc_cc_lock;
wire          dcc_cc_op_stall;

// for dcc
wire          dcc_cps_req_ok;
wire          dcc_cps_data_ok;
wire [ 31: 0] dcc_cps_rdata;

// ecc fatal
wire          dcc_all_fatal;
wire          dcc_rd_fatal;
wire          dcc_wr_fatal;
wire          dcc_ccop_fatal;
wire          dcc_rf_impr_fatal;      // refill
wire          dcc_fatal_intagv;
wire [  7: 0] dcc_fatal_indata;
wire          dcc_fatal_dirtywb;      // err data writeback
wire [  9: 0] dcc_fatal_indx10;
wire [  4: 0] dcc_fatal_way5;
wire [ 22: 0] dcc_fatal_dirty_tag23;

wire          mem_cps_req_dcc;

wire                                dcc_cache_all_addr_ok;
wire [                       31: 0] dcc_cache_rdata;
wire                                dcc_cache_rdata_valid;
wire                                dcc_cache_rdata_exok;
wire                                dcc_cache_rdata_err;
wire                                dcc_cache_rd_in_sysbus;
wire                                dcc_cache_axi_null;
wire [                       31: 0] dcc_cache_cc_vaddr;
wire                                dcc_cache_cc_read;
wire                                dcc_cache_cc_dbgm;
wire                                dcc_cache_dbgm_req_valid;
wire                                dcc_cache_dbgm_req_wr;
wire [                       31: 0] dcc_cache_dbgm_req_addr;
wire [                        1: 0] dcc_cache_dbgm_req_size;
wire [                       31: 0] dcc_cache_dbgm_req_wdata;
wire                                dcc_cache_axi_ar_stall_icc;
wire                                dcc_cache_axi_arvalid;
wire                                dcc_cache_axi_arburst;
wire                                dcc_cache_axi_arexc;
wire                                dcc_cache_axi_arcache;
wire [                        2: 0] dcc_cache_axi_arsize;
wire [                       31: 0] dcc_cache_axi_araddr;
wire [                        2: 0] dcc_cache_axi_aw_wid;
wire                                dcc_cache_axi_awvalid;
wire                                dcc_cache_axi_awburst;
wire                                dcc_cache_axi_awexc;
wire                                dcc_cache_axi_awcache;
wire [                        2: 0] dcc_cache_axi_awsize;
wire [                       31: 0] dcc_cache_axi_awaddr;
wire                                dcc_cache_axi_wvalid;
wire [          AXI_DATA_WD/8-1: 0] dcc_cache_axi_wstrb;
wire [            AXI_DATA_WD-1: 0] dcc_cache_axi_wdata;
wire                                dcc_cache_axi_wlast;
wire                                dcc_cache_cps_req_ok;
wire                                dcc_cache_cps_data_ok;
wire [                       31: 0] dcc_cache_cps_rdata;
wire                                dcc_cache_all_fatal;
wire                                dcc_cache_rd_fatal;
wire                                dcc_cache_wr_fatal;
wire                                dcc_cache_ccop_fatal;
wire                                dcc_cache_rf_impr_fatal;
wire                                dcc_cache_fatal_intagv;
wire [                        7: 0] dcc_cache_fatal_indata;
wire [`OPEN132_DCC_INDEX_BITS-1: 0] dcc_cache_fatal_indx;
wire [ `OPEN132_DCC_SET_ASSOC-1: 0] dcc_cache_fatal_way;
wire                                dcc_cache_fatal_dirtywb;
wire [  `OPEN132_DCC_TAG_BITS-1: 0] dcc_cache_fatal_dirty_tag;
wire                                dcc_cache_all_ecc_err_add1;
wire                                dcc_cache_refill_add1;
wire                                dcc_cache_ram_init_cmplt;
wire [  DCC_CACHE_TAGV_REQ_WD-1: 0] dcc_cache_ram_tagv_req_bus;
wire [  DCC_CACHE_DATA_REQ_WD-1: 0] dcc_cache_ram_data_req_bus;
wire [  DCC_CACHE_LRUD_REQ_WD-1: 0] dcc_cache_ram_lrud_req_bus;
wire [ DCC_CACHE_TAGV_RESP_WD-1: 0] dcc_cache_ram_tagv_resp_bus;
wire [ DCC_CACHE_DATA_RESP_WD-1: 0] dcc_cache_ram_data_resp_bus;
wire [ DCC_CACHE_LRUD_RESP_WD-1: 0] dcc_cache_ram_lrud_resp_bus;

wire                      dcc_nocache_cd_ar_addr_ok;
wire                      dcc_nocache_md_ar_addr_ok;
wire                      dcc_nocache_aw_addr_ok;
wire                      dcc_nocache_dbgm_addr_ok;
wire [             31: 0] dcc_nocache_rdata;
wire                      dcc_nocache_rdata_valid;
wire                      dcc_nocache_rdata_exok;
wire                      dcc_nocache_rdata_err;
wire                      dcc_nocache_rd_in_sysbus;
wire                      dcc_nocache_axi_null;
wire                      dcc_nocache_dbgm_req_valid;
wire                      dcc_nocache_dbgm_req_wr;
wire [             31: 0] dcc_nocache_dbgm_req_addr;
wire [              1: 0] dcc_nocache_dbgm_req_size;
wire [             31: 0] dcc_nocache_dbgm_req_wdata;
wire                      dcc_nocache_axi_ar_stall_icc;
wire                      dcc_nocache_axi_arvalid;
wire                      dcc_nocache_axi_arburst;
wire                      dcc_nocache_axi_arexc;
wire                      dcc_nocache_axi_arcache;
wire [              2: 0] dcc_nocache_axi_arsize;
wire [             31: 0] dcc_nocache_axi_araddr;
wire [              2: 0] dcc_nocache_axi_aw_wid;
wire                      dcc_nocache_axi_awvalid;
wire                      dcc_nocache_axi_awburst;
wire                      dcc_nocache_axi_awexc;
wire                      dcc_nocache_axi_awcache;
wire [              2: 0] dcc_nocache_axi_awsize;
wire [             31: 0] dcc_nocache_axi_awaddr;
wire                      dcc_nocache_axi_wvalid;
wire [AXI_DATA_WD/8-1: 0] dcc_nocache_axi_wstrb;
wire [  AXI_DATA_WD-1: 0] dcc_nocache_axi_wdata;
wire                      dcc_nocache_axi_wlast;
wire                      cached_biu_nocache_0;

wire          dcc_cd_hit_wr;          // kept separate for timing
wire          dcc_md_hit_wr;
wire          nc_sbus_real_sel_mald;
wire          nc_de_load_req;
wire          nc_memld_st_req;
wire          nc_memld_st_dald;
wire          nc_sbus_sel_mald;
wire          nc_mald_pre_s_ok;
wire          nc_mald_pre_s_err;
wire          nc_dcc_bypass;

wire          icc_ram_init_cmplt;

// ifc
wire          icc_req_rd_wr;
wire          icc_req_rd;
wire [ 31: 0] icc_vaddr;
wire [ 31: 0] icc_paddr;         // no-cache: combination with vaddr;
wire [  2: 0] icc_req_bank;
wire          icc_ar_addr_ok;
wire          icc_dbgm_addr_ok;
wire [ 31: 0] icc_rdata;
wire          icc_rdata_valid;   // rdata back
wire          icc_rdata_err;     // valid if icc_rdata_valid==1
wire          icc_rd_in_sysbus;
wire          icc_axi_null;

// mmu
wire [ 31: 0] icc_cc_vaddr;  // from tagcmp, for HAS_CACHE

// wire       icc_cc_read ;
wire          icc_cc_dbgm;
wire          icc_cached;
wire          icc_req2dbgm;
wire          icc_dbgm_req_valid;
wire [ 31: 0] icc_dbgm_req_addr;
wire [  1: 0] icc_dbgm_req_size;
wire          icc_dbgm_resp_valid;
wire [ 31: 0] icc_dbgm_resp_data;

// axi
wire                    icc_axi_arvalid;  // read request
wire                    icc_axi_arready;  // read request received
wire                    icc_axi_arburst;  // read burst
wire                    icc_axi_arcache;  // read cached
wire [            2: 0] icc_axi_arsize;   // read size
wire [           31: 0] icc_axi_araddr;   // read addr
wire                    icc_axi_rvalid;   // read response valid
wire [AXI_DATA_WD-1: 0] icc_axi_rdata;    // read data
wire [            1: 0] icc_axi_rresp;    // read response

wire [  5: 0] icc_cc_op;
wire [ 31: 0] icc_cc_sttag;
wire          icc_cc_fill;
wire          icc_cc_lock;
wire          icc_cc_op_stall;

// for icc
wire          icc_cps_req_ok;
wire          icc_cps_data_ok;
wire [ 31: 0] icc_cps_rdata;

// ecc fatal
wire          icc_all_fatal;      // icc
wire          icc_rd_fatal;
wire          icc_ccop_fatal;
wire          icc_rf_impr_fatal;
wire          icc_fatal_intagv;
wire [  7: 0] icc_fatal_indata;
wire [  9: 0] icc_fatal_indx10;
wire [  4: 0] icc_fatal_way5;

wire          mem_cps_req_icc;

wire                                icc_cache_all_addr_ok;
wire [                       31: 0] icc_cache_rdata;
wire                                icc_cache_rdata_valid;
wire                                icc_cache_rdata_err;
wire                                icc_cache_rd_in_sysbus;
wire                                icc_cache_axi_null;
wire [                       31: 0] icc_cache_cc_vaddr;
wire                                icc_cache_cc_dbgm;
wire                                icc_cache_dbgm_req_valid;
wire [                       31: 0] icc_cache_dbgm_req_addr;
wire [                        1: 0] icc_cache_dbgm_req_size;
wire                                icc_cache_axi_arvalid;
wire                                icc_cache_axi_arburst;
wire                                icc_cache_axi_arcache;
wire [                        2: 0] icc_cache_axi_arsize;
wire [                       31: 0] icc_cache_axi_araddr;
wire                                icc_cache_cps_req_ok;
wire                                icc_cache_cps_data_ok;
wire [                       31: 0] icc_cache_cps_rdata;
wire                                icc_cache_all_fatal;
wire                                icc_cache_rd_fatal;
wire                                icc_cache_ccop_fatal;
wire                                icc_cache_rf_impr_fatal;
wire                                icc_cache_fatal_intagv;
wire [                        7: 0] icc_cache_fatal_indata;
wire [`OPEN132_ICC_INDEX_BITS-1: 0] icc_cache_fatal_indx;
wire [ `OPEN132_ICC_SET_ASSOC-1: 0] icc_cache_fatal_way;
wire                                icc_cache_all_ecc_err_add1;
wire                                icc_cache_refill_add1;
wire                                icc_cache_ram_init_cmplt;
wire [  ICC_CACHE_TAGV_REQ_WD-1: 0] icc_cache_ram_tagv_req_bus;
wire [  ICC_CACHE_DATA_REQ_WD-1: 0] icc_cache_ram_data_req_bus;
wire [  ICC_CACHE_LRUD_REQ_WD-1: 0] icc_cache_ram_lrud_req_bus;
wire [ ICC_CACHE_TAGV_RESP_WD-1: 0] icc_cache_ram_tagv_resp_bus;
wire [ ICC_CACHE_DATA_RESP_WD-1: 0] icc_cache_ram_data_resp_bus;
wire [ ICC_CACHE_LRUD_RESP_WD-1: 0] icc_cache_ram_lrud_resp_bus;

wire          icc_nocache_ar_addr_ok;
wire          icc_nocache_dbgm_addr_ok;
wire [ 31: 0] icc_nocache_rdata;
wire          icc_nocache_rdata_valid;
wire          icc_nocache_rdata_err;
wire          icc_nocache_rd_in_sysbus;
wire          icc_nocache_axi_null;
wire          icc_nocache_dbgm_req_valid;
wire [ 31: 0] icc_nocache_dbgm_req_addr;
wire [  1: 0] icc_nocache_dbgm_req_size;
wire          icc_nocache_axi_arvalid;
wire          icc_nocache_axi_arburst;
wire          icc_nocache_axi_arcache;
wire [  2: 0] icc_nocache_axi_arsize;
wire [ 31: 0] icc_nocache_axi_araddr;
wire          cached_biu_nocache_1;

wire          nc_sbus_real_sel_ft;
wire          nc_sbus_sel_ft;
wire          nc_ft_pre_s_ok;
wire          nc_ft_pre_s_err;
wire          nc_icc_bypass;

// dcc attribute check
wire [ 31: 0] dcc_mmu_vaddr;
wire          dcc_mmu_read;
wire          dcc_mmu_dbgm;

// icc attribute ch
wire [ 31: 0] icc_mmu_vaddr;
wire          icc_mmu_dbgm;

// axi burst size
wire [  3: 0] axi_burst_len;

// read from: dcache and icache
wire          sys_ar_ok;
wire          sys_r_ok;

wire          ft_allowin;  // if ld_allowin and ld_req, ft can't allowin
wire          ld_allowin;

// fetch/load go ok
wire          ft_go_ok;
wire          ld_go_ok;
wire          nx_go_ok;

wire          ft_rlast_ok;
wire          ld_rlast_ok;

// control
wire          ar_buf_empty;

// fatal_bus
wire          dcc_fatal;
wire          icc_fatal;
wire          fatal_rd;
wire          impr_fatal_wr;
wire          impr_fatal_ccop;
wire          impr_fatal_rf;
wire          fatal_intagv;
wire [  7: 0] fatal_indata;
wire [  3: 0] fatal_way;
wire [  8: 0] fatal_indx;
wire          fatal_dirtywb;
wire [ 21: 0] fatal_dirty_tag;

// fatal bus
wire [`OPEN132_CACHE_LSU_ECC_FATAL_BUS_WIDTH-1: 0] cache_ecc_fatal_events;

wire          nc_resetn_in_d2;
`ifdef CONFIG_MMU

// Hardware page-table walker and shared L1TLB
wire [  1: 0] mmu_plv;
wire          mmu_da;
wire          mmu_pg;
wire [  1: 0] mmu_datf;
wire [  1: 0] mmu_datm;
wire [  9: 0] mmu_asid;
wire [ 31: 0] mmu_pgdl;
wire [ 31: 0] mmu_pgdh;
wire [ 31: 0] mmu_dmw0;
wire [ 31: 0] mmu_dmw1;
wire [ 31: 0] mmu_pwcl;
wire [ 31: 0] mmu_pwch;
wire          mmu_ptw_en;
wire          mmu_inv_vld;
wire [  4: 0] mmu_inv_op;
wire [  9: 0] mmu_inv_asid;
wire [ 31: 0] mmu_inv_vaddr;
wire          mmu_page_mode;

wire          ifu_mmu_req_vld;
wire          ifu_mmu_req_rdy;
wire          ifu_mmu_expt_vld;
wire [  5: 0] ifu_mmu_expt_code;
wire          ifu_mmu_cache_vld;
wire          ifu_mmu_cache_rdy;
wire          ifu_mmu_cache_wait;
wire [ 31: 0] ifu_mmu_cache_va;
wire [ 31: 0] ifu_mmu_cache_pa;
wire [  1: 0] ifu_mmu_cache_mat;
wire          ifu_mmu_xlat_vld;
wire          ifu_mmu_xlat_cancel;
wire [ 31: 0] ifu_mmu_xlat_pa;
wire [  1: 0] ifu_mmu_xlat_mat;

wire          lsu_mmu_req_vld;
wire          lsu_mmu_req_rdy;
wire          lsu_mmu_expt_vld;
wire [  5: 0] lsu_mmu_expt_code;
wire          lsu_mmu_expt_write;
wire          lsu_mmu_cache_vld;
wire          lsu_mmu_cache_rdy;
wire          lsu_mmu_cache_wait;
wire [ 31: 0] lsu_mmu_cache_va;
wire [ 31: 0] lsu_mmu_cache_pa;
wire [  1: 0] lsu_mmu_cache_mat;
wire          lsu_mmu_xlat_vld;
wire          lsu_mmu_xlat_cancel;
wire [ 31: 0] lsu_mmu_xlat_pa;
wire [  1: 0] lsu_mmu_xlat_mat;
wire          lsu_mmu_store_done;


wire          ptw_dc_req_vld;
wire          ptw_dc_req_rdy;
wire [ 31: 0] ptw_dc_req_pa;
wire          ptw_dc_busy;
wire          ptw_dc_resp_vld;
wire [ 31: 0] ptw_dc_resp_data;
wire          ptw_dc_resp_err;

wire          dcpu_req_vld;
wire          dcpu_req_rdy;
wire          dcpu_req_wait;
wire          dcpu_req_replay;
wire          dcpu_req_rd;
wire          dcpu_req_exc;
wire          dcpu_req_pre_err;
wire          dcpu_req_dbgm;
wire [  1: 0] dcpu_req_size;
wire [ 31: 0] dcpu_req_va;
wire [ 31: 0] dcpu_req_pa;
wire [  1: 0] dcpu_req_mat;
wire [  2: 0] dcpu_req_bank;
wire [ 31: 0] dcpu_req_wdata;
wire          dcpu_resp_vld;
wire [ 31: 0] dcpu_resp_data;
wire          dcpu_resp_exok;
wire          dcpu_resp_err;

wire          darb_cache_req_vld;
wire          darb_cache_req_rdy;
wire          darb_cache_req_wait;
wire          darb_cache_req_rd;
wire          darb_cache_req_exc;
wire          darb_cache_req_pre_err;
wire          darb_cache_req_dbgm;
wire [  1: 0] darb_cache_req_size;
wire [ 31: 0] darb_cache_req_va;
wire [ 31: 0] darb_cache_req_pa;
wire [  1: 0] darb_cache_req_mat;
wire [  2: 0] darb_cache_req_bank;
wire [ 31: 0] darb_cache_req_wdata;
`endif
`ifdef OPEN132_HAS_LJTAG

// biu_jtag_debug_req_bus
wire          dbmemcbus_valid;
wire          dbmemcbus_write;
wire [  1: 0] dbmemcbus_size;
wire [ 19: 0] dbmemcbus_paddr;
wire [ 31: 0] dbmemcbus_data;

// jtag_biu_debug_resp_bus
wire          dbmemrbus_valid;
wire [ 31: 0] dbmemrbus_data;

wire          dbgm_req_valid;
wire [ 31: 0] dbgm_req_addr;
wire          dbgm_req_wr;
wire [  1: 0] dbgm_req_size;
wire [ 31: 0] dbgm_req_wdata;

// dbgm bus
wire          dbgmrbus_valid;
wire [ 31: 0] dbgmrbus_data;
`endif

//============================================================//
//                    Module Implementation
//============================================================//

// Instance Parameter Aliases
// x_lsu_cache_0
// x_biu_nocache_0
// x_lsu_cache_1
// x_biu_nocache_1
// x_mmu_vaddr_attribute

assign memld_st_strb_nc  =  memld_st_strb;
// Instance Boundary Alias Mapping
// x_lsu_cache_0

assign is_icache_cache0            =  1'b0;
assign clk_cache0                  =  clk;
assign clk_ng_cache0               =  clk_ng;
assign reset_cache0                =  reset;
assign data_reset_cache0           =  data_reset;
assign ctrl_nowrap_cache0          =  ctrl_nowrap;
`ifdef CONFIG_MMU
assign ex_cancel_cache0            =  ex_cancel && !ptw_dc_busy;
assign req_rd_wr_cache0            =  darb_cache_req_vld;
assign req_rd_cache0               =  darb_cache_req_rd;
assign req_exc_cache0              =  darb_cache_req_exc;
assign size_cache0                 =  darb_cache_req_size;
assign vaddr_cache0                =  mem_cps_req_dcc ? dcc_vaddr : darb_cache_req_va;
assign paddr_cache0                =  mem_cps_req_dcc ? dcc_paddr : darb_cache_req_pa;
assign req_xlat_wait_cache0        =  mmu_page_mode && darb_cache_req_vld
                                      && !mem_cps_req_dcc && !dcc_cc_pref
                                      && darb_cache_req_wait;
assign req_attr_vld_cache0         =  mmu_page_mode && darb_cache_req_vld
                                      && !mem_cps_req_dcc && !dcc_cc_pref
                                      && !darb_cache_req_wait;
assign req_sob_cache0              =  darb_cache_req_mat == 2'b00;
assign req_cached_cache0           =  darb_cache_req_mat == 2'b01;
assign req_alloc_cache0            =  darb_cache_req_mat == 2'b01;
assign xlat_vld_cache0             =  lsu_mmu_xlat_vld;
assign xlat_cancel_cache0          =  lsu_mmu_xlat_cancel && !ptw_dc_busy;
assign xlat_paddr_cache0           =  lsu_mmu_xlat_pa;
assign xlat_sob_cache0             =  lsu_mmu_xlat_mat == 2'b00;
assign xlat_cached_cache0          =  lsu_mmu_xlat_mat == 2'b01;
assign xlat_alloc_cache0           =  lsu_mmu_xlat_mat == 2'b01;
assign wdata_cache0                =  darb_cache_req_wdata;
assign dcc_cache_rdata             =  dcpu_resp_data;
assign dcc_cache_rdata_valid       =  dcpu_resp_vld;
assign dcc_cache_rdata_exok        =  dcpu_resp_exok;
assign dcc_cache_rdata_err         =  dcpu_resp_err;
`else
assign ex_cancel_cache0            =  ex_cancel;
assign req_rd_wr_cache0            =  dcc_req_rd_wr;
assign req_rd_cache0               =  dcc_req_rd;
assign req_exc_cache0              =  dcc_req_exc;
assign size_cache0                 =  dcc_size;
assign vaddr_h3_cache0             =  dcc_vaddr[31:29];
assign paddr_cache0                =  dcc_paddr;
assign wdata_cache0                =  dcc_wdata;
assign dcc_cache_rdata             =  rdata_cache0;
assign dcc_cache_rdata_valid       =  rdata_valid_cache0;
assign dcc_cache_rdata_exok        =  rdata_exok_cache0;
assign dcc_cache_rdata_err         =  rdata_err_cache0;
`endif
assign dcc_cache_rd_in_sysbus      =  rd_in_sysbus_cache0;
assign dcc_cache_axi_null          =  axi_null_cache0;
assign dcc_cache_cc_vaddr          =  go_mmu_vaddr_cache0;
assign dcc_cache_cc_read           =  go_mmu_read_cache0;
assign dcc_cache_cc_dbgm           =  go_mmu_dbgm_cache0;
assign mmu_sob_cache0              =  dcc_sob;
assign mmu_cached_cache0           =  dcc_cached;
assign mmu_alloc_cache0            =  dcc_cc_alloc;
assign req2dbgm_cache0             =  dcc_req2dbgm;
assign dcc_cache_dbgm_req_valid    =  dbgm_req_valid_cache0;
assign dcc_cache_dbgm_req_wr       =  dbgm_req_wr_cache0;
assign dcc_cache_dbgm_req_addr     =  dbgm_req_addr_cache0;
assign dcc_cache_dbgm_req_size     =  dbgm_req_size_cache0;
assign dcc_cache_dbgm_req_wdata    =  dbgm_req_wdata_cache0;
assign dbgm_resp_valid_cache0      =  dcc_dbgm_resp_valid;
assign dbgm_resp_data_cache0       =  dcc_dbgm_resp_data;
assign dcc_cache_axi_ar_stall_icc  =  dcc_ar_stall_icc_cache0;
assign dcc_cache_axi_arvalid       =  axi_arvalid_cache0;
assign axi_arready_cache0          =  dcc_axi_arready;
assign dcc_cache_axi_arburst       =  axi_arburst_cache0;
assign dcc_cache_axi_arexc         =  axi_arexc_cache0;
assign dcc_cache_axi_arcache       =  axi_arcache_cache0;
assign dcc_cache_axi_arsize        =  axi_arsize_cache0;
assign dcc_cache_axi_araddr        =  axi_araddr_cache0;
assign axi_rvalid_cache0           =  dcc_axi_rvalid;
assign axi_rdata_cache0            =  dcc_axi_rdata;
assign axi_rresp_cache0            =  dcc_axi_rresp;
assign dcc_cache_axi_aw_wid        =  axi_aw_wid_cache0;
assign dcc_cache_axi_awvalid       =  axi_awvalid_cache0;
assign axi_awready_cache0          =  dcc_axi_awready;
assign dcc_cache_axi_awburst       =  axi_awburst_cache0;
assign dcc_cache_axi_awexc         =  axi_awexc_cache0;
assign dcc_cache_axi_awcache       =  axi_awcache_cache0;
assign dcc_cache_axi_awsize        =  axi_awsize_cache0;
assign dcc_cache_axi_awaddr        =  axi_awaddr_cache0;
assign dcc_cache_axi_wvalid        =  axi_wvalid_cache0;
assign axi_wready_cache0           =  dcc_axi_wready;
assign dcc_cache_axi_wstrb         =  axi_wstrb_cache0;
assign dcc_cache_axi_wdata         =  axi_wdata_cache0;
assign dcc_cache_axi_wlast         =  axi_wlast_cache0;
assign axi_bvalid_cache0           =  dcc_axi_bvalid;
assign axi_bid_cache0              =  dcc_axi_bid;
assign dcc_cache_all_addr_ok       =  all_addr_ok_cache0;
`ifdef CONFIG_MMU
assign req_pre_err_cache0          =  darb_cache_req_pre_err;
assign req_bank_cache0             =  darb_cache_req_bank;
`else
assign req_pre_err_cache0          =  mald_pre_s_err;
assign req_bank_cache0             =  dcc_req_bank;
`endif
assign cc_op_cache0                =  dcc_cc_op;
assign cc_isync_cache0             =  mem_cc_op_i;
assign cc_sttag_cache0             =  dcc_cc_sttag;
assign cc_pref_cache0              =  dcc_cc_pref;
assign cc_lock_cache0              =  dcc_cc_lock;
assign cc_op_stall_cache0          =  dcc_cc_op_stall;
assign dcc_cache_cps_req_ok        =  cps_req_ok_cache0;
assign dcc_cache_cps_data_ok       =  cps_data_ok_cache0;
assign dcc_cache_cps_rdata         =  cps_rdata_cache0;
assign bypass_cache0               =  dcc_bypass;
assign dcc_cache_all_fatal         =  all_fatal_cache0;
assign dcc_cache_rd_fatal          =  load_fatal_cache0;
assign dcc_cache_wr_fatal          =  store_fatal_cache0;
assign dcc_cache_ccop_fatal        =  ccop_fatal_cache0;
assign dcc_cache_rf_impr_fatal     =  rf_impr_fatal_cache0;
assign dcc_cache_fatal_intagv      =  fatal_intagv_cache0;
assign dcc_cache_fatal_indata      =  fatal_indata_cache0;
assign dcc_cache_fatal_indx        =  fatal_indx_cache0;
assign dcc_cache_fatal_way         =  fatal_way_cache0;
assign dcc_cache_fatal_dirtywb     =  fatal_dirtywb_cache0;
assign dcc_cache_fatal_dirty_tag   =  fatal_dirty_tag_cache0;
assign dcc_cache_all_ecc_err_add1  =  all_ecc_err_add1_cache0;
assign dcc_cache_refill_add1       =  refill_add1_cache0;
assign resetn_in_d2_cache0         =  resetn_in_d2;
assign dcc_cache_ram_init_cmplt    =  ram_init_cmplt_cache0;
assign dcc_cache_ram_tagv_req_bus  =  ram_tagv_req_bus_cache0;
assign dcc_cache_ram_data_req_bus  =  ram_data_req_bus_cache0;
assign dcc_cache_ram_lrud_req_bus  =  ram_lrud_req_bus_cache0;
assign ram_tagv_resp_bus_cache0    =  dcc_cache_ram_tagv_resp_bus;
assign ram_data_resp_bus_cache0    =  dcc_cache_ram_data_resp_bus;
assign ram_lrud_resp_bus_cache0    =  dcc_cache_ram_lrud_resp_bus;
// x_biu_nocache_0
assign is_icache_nc_ch0              =  1'b0;
assign clk_nc_ch0                    =  clk;
assign clk_ng_nc_ch0                 =  clk_ng;
assign reset_nc_ch0                  =  reset;
assign data_reset_nc_ch0             =  data_reset;
assign ex_cancel_nc_ch0              =  ex_cancel;
assign req_rd_wr_nc_ch0              =  dcc_req_rd_wr;
assign req_rd_nc_ch0                 =  dcc_req_rd;
assign req_exc_nc_ch0                =  dcc_req_exc;
assign size_nc_ch0                   =  dcc_size;
assign paddr_nc_ch0                  =  dcc_paddr;
assign wdata_nc_ch0                  =  dcc_wdata;
assign dcc_nocache_rdata             =  rdata_nc_ch0;
assign dcc_nocache_rdata_valid       =  rdata_valid_nc_ch0;
assign dcc_nocache_rdata_exok        =  rdata_exok_nc_ch0;
assign dcc_nocache_rdata_err         =  rdata_err_nc_ch0;
assign dcc_nocache_rd_in_sysbus      =  rd_in_sysbus_nc_ch0;
assign dcc_nocache_axi_null          =  axi_null_nc_ch0;
assign req2dbgm_nc_ch0               =  dcc_req2dbgm;
assign dcc_nocache_dbgm_req_valid    =  dbgm_req_valid_nc_ch0;
assign dcc_nocache_dbgm_req_wr       =  dbgm_req_wr_nc_ch0;
assign dcc_nocache_dbgm_req_addr     =  dbgm_req_addr_nc_ch0;
assign dcc_nocache_dbgm_req_size     =  dbgm_req_size_nc_ch0;
assign dcc_nocache_dbgm_req_wdata    =  dbgm_req_wdata_nc_ch0;
assign dbgm_resp_valid_nc_ch0        =  dcc_dbgm_resp_valid;
assign dbgm_resp_data_nc_ch0         =  dcc_dbgm_resp_data;
assign dcc_nocache_axi_ar_stall_icc  =  dcc_ar_stall_icc_nc_ch0;
assign dcc_nocache_axi_arvalid       =  axi_arvalid_nc_ch0;
assign axi_arready_nc_ch0            =  dcc_axi_arready;
assign dcc_nocache_axi_arburst       =  axi_arburst_nc_ch0;
assign dcc_nocache_axi_arexc         =  axi_arexc_nc_ch0;
assign dcc_nocache_axi_arcache       =  axi_arcache_nc_ch0;
assign dcc_nocache_axi_arsize        =  axi_arsize_nc_ch0;
assign dcc_nocache_axi_araddr        =  axi_araddr_nc_ch0;
assign axi_rvalid_nc_ch0             =  dcc_axi_rvalid;
assign axi_rdata_nc_ch0              =  dcc_axi_rdata;
assign axi_rresp_nc_ch0              =  dcc_axi_rresp;
assign dcc_nocache_axi_aw_wid        =  axi_aw_wid_nc_ch0;
assign dcc_nocache_axi_awvalid       =  axi_awvalid_nc_ch0;
assign axi_awready_nc_ch0            =  dcc_axi_awready;
assign dcc_nocache_axi_awburst       =  axi_awburst_nc_ch0;
assign dcc_nocache_axi_awexc         =  axi_awexc_nc_ch0;
assign dcc_nocache_axi_awcache       =  axi_awcache_nc_ch0;
assign dcc_nocache_axi_awsize        =  axi_awsize_nc_ch0;
assign dcc_nocache_axi_awaddr        =  axi_awaddr_nc_ch0;
assign dcc_nocache_axi_wvalid        =  axi_wvalid_nc_ch0;
assign axi_wready_nc_ch0             =  dcc_axi_wready;
assign dcc_nocache_axi_wstrb         =  axi_wstrb_nc_ch0;
assign dcc_nocache_axi_wdata         =  axi_wdata_nc_ch0;
assign dcc_nocache_axi_wlast         =  axi_wlast_nc_ch0;
assign axi_bvalid_nc_ch0             =  dcc_axi_bvalid;
assign axi_bid_nc_ch0                =  dcc_axi_bid;
assign dcc_nocache_cd_ar_addr_ok     =  cd_ar_addr_ok_nc_ch0;
assign dcc_nocache_md_ar_addr_ok     =  md_ar_addr_ok_nc_ch0;
assign dcc_nocache_aw_addr_ok        =  aw_addr_ok_nc_ch0;
assign dcc_nocache_dbgm_addr_ok      =  dbgm_addr_ok_nc_ch0;
assign cd_hit_wr_nc_ch0              =  dcc_cd_hit_wr;
assign md_hit_wr_nc_ch0              =  dcc_md_hit_wr;
// x_lsu_cache_1
assign is_icache_cache1            =  1'b1;
assign clk_cache1                  =  clk;
assign clk_ng_cache1               =  clk_ng;
assign reset_cache1                =  reset;
assign data_reset_cache1           =  data_reset;
assign ctrl_nowrap_cache1          =  ctrl_nowrap;
assign ex_cancel_cache1            =  ex_cancel;
`ifdef CONFIG_MMU
assign req_rd_wr_cache1            =  mmu_page_mode ? ifu_mmu_cache_vld
                                                    : icc_req_rd_wr;
assign req_rd_cache1               =  mmu_page_mode ? ifu_mmu_cache_vld
                                                    : icc_req_rd;
`else
assign req_rd_wr_cache1            =  icc_req_rd_wr;
assign req_rd_cache1               =  icc_req_rd;
`endif
assign req_exc_cache1              =  1'b0;
assign size_cache1                 =  2'b10;
`ifdef CONFIG_MMU
assign vaddr_cache1                =  mem_cps_req_icc ? icc_vaddr
                                                      : mmu_page_mode
                                                        ? ifu_mmu_cache_va : icc_vaddr;
assign paddr_cache1                =  mem_cps_req_icc ? icc_paddr
                                                      : mmu_page_mode
                                                        ? ifu_mmu_cache_pa : icc_paddr;
assign req_xlat_wait_cache1        =  mmu_page_mode && ifu_mmu_cache_vld
                                      && !mem_cps_req_icc && !icc_cc_fill
                                      && ifu_mmu_cache_wait;
assign req_attr_vld_cache1         =  mmu_page_mode && ifu_mmu_cache_vld
                                      && !mem_cps_req_icc && !icc_cc_fill
                                      && !ifu_mmu_cache_wait;
assign req_sob_cache1              =  ifu_mmu_cache_mat == 2'b00;
assign req_cached_cache1           =  ifu_mmu_cache_mat == 2'b01;
assign req_alloc_cache1            =  ifu_mmu_cache_mat == 2'b01;
assign xlat_vld_cache1             =  ifu_mmu_xlat_vld;
assign xlat_cancel_cache1          =  ifu_mmu_xlat_cancel;
assign xlat_paddr_cache1           =  ifu_mmu_xlat_pa;
assign xlat_sob_cache1             =  ifu_mmu_xlat_mat == 2'b00;
assign xlat_cached_cache1          =  ifu_mmu_xlat_mat == 2'b01;
assign xlat_alloc_cache1           =  ifu_mmu_xlat_mat == 2'b01;
`else
assign vaddr_h3_cache1             =  icc_vaddr[31:29];
assign paddr_cache1                =  icc_paddr;
`endif
assign wdata_cache1                =  32'd0;
assign icc_cache_rdata             =  rdata_cache1;
assign icc_cache_rdata_valid       =  rdata_valid_cache1;
assign icc_cache_rdata_err         =  rdata_err_cache1;
assign icc_cache_rd_in_sysbus      =  rd_in_sysbus_cache1;
assign icc_cache_axi_null          =  axi_null_cache1;
assign icc_cache_cc_vaddr          =  go_mmu_vaddr_cache1;
assign icc_cache_cc_dbgm           =  go_mmu_dbgm_cache1;
assign mmu_sob_cache1              =  1'b0;
assign mmu_cached_cache1           =  icc_cached;
assign mmu_alloc_cache1            =  1'b1;
assign req2dbgm_cache1             =  icc_req2dbgm;
assign icc_cache_dbgm_req_valid    =  dbgm_req_valid_cache1;
assign icc_cache_dbgm_req_addr     =  dbgm_req_addr_cache1;
assign icc_cache_dbgm_req_size     =  dbgm_req_size_cache1;
assign dbgm_resp_valid_cache1      =  icc_dbgm_resp_valid;
assign dbgm_resp_data_cache1       =  icc_dbgm_resp_data;
assign icc_cache_axi_arvalid       =  axi_arvalid_cache1;
assign axi_arready_cache1          =  icc_axi_arready;
assign icc_cache_axi_arburst       =  axi_arburst_cache1;
assign icc_cache_axi_arcache       =  axi_arcache_cache1;
assign icc_cache_axi_arsize        =  axi_arsize_cache1;
assign icc_cache_axi_araddr        =  axi_araddr_cache1;
assign axi_rvalid_cache1           =  icc_axi_rvalid;
assign axi_rdata_cache1            =  icc_axi_rdata;
assign axi_rresp_cache1            =  icc_axi_rresp;
assign axi_awready_cache1          =  1'b0;
assign axi_wready_cache1           =  1'b0;
assign axi_bvalid_cache1           =  1'b0;
assign axi_bid_cache1              =  3'd0;
assign icc_cache_all_addr_ok       =  all_addr_ok_cache1;
`ifdef CONFIG_MMU
assign req_pre_err_cache1          =  mmu_page_mode ? 1'b0 : ft_pre_s_err;
assign req_bank_cache1             =  mmu_page_mode ? ifu_mmu_cache_va[4:2]
                                                    : icc_req_bank;
`else
assign req_pre_err_cache1          =  ft_pre_s_err;
assign req_bank_cache1             =  icc_req_bank;
`endif
assign cc_op_cache1                =  icc_cc_op;
assign cc_isync_cache1             =  mem_cc_op_d;
assign cc_sttag_cache1             =  icc_cc_sttag;
assign cc_pref_cache1              =  icc_cc_fill;
assign cc_lock_cache1              =  icc_cc_lock;
assign cc_op_stall_cache1          =  icc_cc_op_stall;
assign icc_cache_cps_req_ok        =  cps_req_ok_cache1;
assign icc_cache_cps_data_ok       =  cps_data_ok_cache1;
assign icc_cache_cps_rdata         =  cps_rdata_cache1;
assign bypass_cache1               =  icc_bypass;
assign icc_cache_all_fatal         =  all_fatal_cache1;
assign icc_cache_rd_fatal          =  load_fatal_cache1;
assign icc_cache_ccop_fatal        =  ccop_fatal_cache1;
assign icc_cache_rf_impr_fatal     =  rf_impr_fatal_cache1;
assign icc_cache_fatal_intagv      =  fatal_intagv_cache1;
assign icc_cache_fatal_indata      =  fatal_indata_cache1;
assign icc_cache_fatal_indx        =  fatal_indx_cache1;
assign icc_cache_fatal_way         =  fatal_way_cache1;
assign icc_cache_all_ecc_err_add1  =  all_ecc_err_add1_cache1;
assign icc_cache_refill_add1       =  refill_add1_cache1;
assign resetn_in_d2_cache1         =  resetn_in_d2;
assign icc_cache_ram_init_cmplt    =  ram_init_cmplt_cache1;
assign icc_cache_ram_tagv_req_bus  =  ram_tagv_req_bus_cache1;
assign icc_cache_ram_data_req_bus  =  ram_data_req_bus_cache1;
assign icc_cache_ram_lrud_req_bus  =  ram_lrud_req_bus_cache1;
assign ram_tagv_resp_bus_cache1    =  icc_cache_ram_tagv_resp_bus;
assign ram_data_resp_bus_cache1    =  icc_cache_ram_data_resp_bus;
assign ram_lrud_resp_bus_cache1    =  icc_cache_ram_lrud_resp_bus;
// x_biu_nocache_1
assign is_icache_nc_ch1            =  1'b1;
assign clk_nc_ch1                  =  clk;
assign clk_ng_nc_ch1               =  clk_ng;
assign reset_nc_ch1                =  reset;
assign data_reset_nc_ch1           =  data_reset;
assign ex_cancel_nc_ch1            =  ex_cancel;
assign req_rd_wr_nc_ch1            =  icc_req_rd_wr;
assign req_rd_nc_ch1               =  icc_req_rd;
assign req_exc_nc_ch1              =  1'b0;
assign size_nc_ch1                 =  2'b10;
assign paddr_nc_ch1                =  icc_paddr;
assign wdata_nc_ch1                =  32'd0;
assign icc_nocache_rdata           =  rdata_nc_ch1;
assign icc_nocache_rdata_valid     =  rdata_valid_nc_ch1;
assign icc_nocache_rdata_err       =  rdata_err_nc_ch1;
assign icc_nocache_rd_in_sysbus    =  rd_in_sysbus_nc_ch1;
assign icc_nocache_axi_null        =  axi_null_nc_ch1;
assign req2dbgm_nc_ch1             =  icc_req2dbgm;
assign icc_nocache_dbgm_req_valid  =  dbgm_req_valid_nc_ch1;
assign icc_nocache_dbgm_req_addr   =  dbgm_req_addr_nc_ch1;
assign icc_nocache_dbgm_req_size   =  dbgm_req_size_nc_ch1;
assign dbgm_resp_valid_nc_ch1      =  icc_dbgm_resp_valid;
assign dbgm_resp_data_nc_ch1       =  icc_dbgm_resp_data;
assign icc_nocache_axi_arvalid     =  axi_arvalid_nc_ch1;
assign axi_arready_nc_ch1          =  icc_axi_arready;
assign icc_nocache_axi_arburst     =  axi_arburst_nc_ch1;
assign icc_nocache_axi_arcache     =  axi_arcache_nc_ch1;
assign icc_nocache_axi_arsize      =  axi_arsize_nc_ch1;
assign icc_nocache_axi_araddr      =  axi_araddr_nc_ch1;
assign axi_rvalid_nc_ch1           =  icc_axi_rvalid;
assign axi_rdata_nc_ch1            =  icc_axi_rdata;
assign axi_rresp_nc_ch1            =  icc_axi_rresp;
assign axi_awready_nc_ch1          =  1'b0;
assign axi_wready_nc_ch1           =  1'b0;
assign axi_bvalid_nc_ch1           =  1'b0;
assign axi_bid_nc_ch1              =  3'd0;
assign icc_nocache_ar_addr_ok      =  cd_ar_addr_ok_nc_ch1;
assign icc_nocache_dbgm_addr_ok    =  dbgm_addr_ok_nc_ch1;
assign cd_hit_wr_nc_ch1            =  1'b0;
assign md_hit_wr_nc_ch1            =  1'b0;
// x_mmu_vaddr_to_paddr_0
assign lisa_da_v2p0      =  lisa_da;
assign lisa_segpa_v2p0   =  lisa_segpa;
assign vaddr_h3_v2p0     =  dcc_vaddr[31:29];
assign dcc_paddr[31:29]  =  paddr_h3_v2p0;
// x_mmu_vaddr_to_paddr_1
assign lisa_da_v2p1      =  lisa_da;
assign lisa_segpa_v2p1   =  lisa_segpa;
assign vaddr_h3_v2p1     =  icc_vaddr[31:29];
assign icc_paddr[31:29]  =  paddr_h3_v2p1;
// x_mmu_vaddr_attribute
assign lisa_da_vattr      =  lisa_da;
assign lisa_dacf_vattr    =  lisa_dacf;
assign lisa_dacm_vattr    =  lisa_dacm;
assign mpu_valid_vattr    =  mpu_valid;
assign mpu_base_vattr     =  mpu_base;
assign mpu_mask_vattr     =  mpu_mask;
assign mpu_calg_vattr     =  mpu_calg;
assign cfgseg_calg_vattr  =  cfgseg_calg;
assign dcc_vaddr_vattr    =  dcc_mmu_vaddr;
assign dcc_read_vattr     =  dcc_mmu_read;
assign dcc_dbgm_vattr     =  dcc_mmu_dbgm;
assign dcc_sob            =  dcc_addr_sob_vattr;
assign dcc_cached         =  dcc_addr_cached_vattr;
assign dcc_cc_alloc       =  dcc_addr_alloc_vattr;
assign icc_vaddr_vattr    =  icc_mmu_vaddr;
assign icc_dbgm_vattr     =  icc_mmu_dbgm;
assign icc_cached         =  icc_addr_cached_vattr;

assign sys_rid_nc    =  sys_rid[3:1];
assign sys_bid3_nc   =  sys_bid[3];
assign sys_bresp_nc  =  sys_bresp;

//------------------------------------------------------------//
//                          csr2ifc
//------------------------------------------------------------//
assign {cfgseg_calg ,
        lisa_da     ,
        lisa_dacf   ,
        lisa_dacm   ,
        lisa_segpa  ,
        mpu_valid   ,
        mpu_base    ,
        mpu_mask    ,
        mpu_calg    ,
        dcc_bypass  ,
        icc_bypass
       }  =  csr_cache_ctrl_bus;
// End csr2ifc

//------------------------------------------------------------//
`ifdef CONFIG_MMU
//                    Hardware Address Translation
//------------------------------------------------------------//

assign {mmu_pwcl      ,
        mmu_pwch      ,
        mmu_plv       ,
        mmu_da        ,
        mmu_pg        ,
        mmu_datf      ,
        mmu_datm      ,
        mmu_asid      ,
        mmu_pgdl      ,
        mmu_pgdh      ,
        mmu_dmw0      ,
        mmu_dmw1      ,
        mmu_ptw_en    ,
        mmu_inv_vld   ,
        mmu_inv_op    ,
        mmu_inv_asid  ,
        mmu_inv_vaddr }  =  csr_mmu_ctrl_bus;

assign mmu_page_mode       =  !mmu_da && mmu_pg;
assign ifu_mmu_req_vld     =  mmu_page_mode && req_ft && !mem_cps_req_icc;
assign lsu_mmu_req_vld     =  mmu_page_mode && req_memld_st && !mem_cps_req_dcc;
assign ifu_mmu_cache_rdy   =  icc_cache_all_addr_ok;
assign lsu_mmu_cache_rdy   =  dcpu_req_rdy;
assign lsu_mmu_store_done  =  lsu_mmu_xlat_vld
                              || (lsu_mmu_cache_vld && !lsu_mmu_cache_wait
                                  && lsu_mmu_cache_rdy)
                              || (lsu_mmu_expt_vld && lsu_mmu_expt_write);

assign ft_mmu_expt_vld     =  ifu_mmu_expt_vld;
assign ft_mmu_expt_code    =  ifu_mmu_expt_code;
assign ld_mmu_expt_vld     =  lsu_mmu_expt_vld;
assign ld_mmu_expt_code    =  lsu_mmu_expt_code;
assign ld_mmu_expt_write   =  lsu_mmu_expt_write;

mmu_core x_mmu_core (
    .clk                   (clk                  ),
    .reset                 (reset                ),
    .ifu_kill              (ex_cancel            ),
    .ifu_req_vld           (ifu_mmu_req_vld      ),
    .ifu_req_rdy           (ifu_mmu_req_rdy      ),
    .ifu_req_vaddr         (fetch_vaddr          ),
    .ifu_expt_vld          (ifu_mmu_expt_vld     ),
    .ifu_expt_code         (ifu_mmu_expt_code    ),
    .ifu_cache_req_vld     (ifu_mmu_cache_vld    ),
    .ifu_cache_req_rdy     (ifu_mmu_cache_rdy    ),
    .ifu_cache_req_wait    (ifu_mmu_cache_wait   ),
    .ifu_cache_req_vaddr   (ifu_mmu_cache_va     ),
    .ifu_cache_req_paddr   (ifu_mmu_cache_pa     ),
    .ifu_cache_req_mat     (ifu_mmu_cache_mat    ),
    .ifu_cache_xlat_vld    (ifu_mmu_xlat_vld     ),
    .ifu_cache_xlat_cancel (ifu_mmu_xlat_cancel  ),
    .ifu_cache_xlat_paddr  (ifu_mmu_xlat_pa      ),
    .ifu_cache_xlat_mat    (ifu_mmu_xlat_mat     ),
    .lsu_kill              (ex_cancel            ),
    .lsu_req_vld           (lsu_mmu_req_vld      ),
    .lsu_req_rdy           (lsu_mmu_req_rdy      ),
    .lsu_req_write         (memld_st_write       ),
    .lsu_req_vaddr         (memld_st_vaddr       ),
    .lsu_expt_vld          (lsu_mmu_expt_vld     ),
    .lsu_expt_code         (lsu_mmu_expt_code    ),
    .lsu_expt_write        (lsu_mmu_expt_write   ),
    .lsu_cache_req_vld     (lsu_mmu_cache_vld    ),
    .lsu_cache_req_rdy     (lsu_mmu_cache_rdy    ),
    .lsu_cache_req_wait    (lsu_mmu_cache_wait   ),
    .lsu_cache_req_vaddr   (lsu_mmu_cache_va     ),
    .lsu_cache_req_paddr   (lsu_mmu_cache_pa     ),
    .lsu_cache_req_mat     (lsu_mmu_cache_mat    ),
    .lsu_cache_xlat_vld    (lsu_mmu_xlat_vld     ),
    .lsu_cache_xlat_cancel (lsu_mmu_xlat_cancel  ),
    .lsu_cache_xlat_paddr  (lsu_mmu_xlat_pa      ),
    .lsu_cache_xlat_mat    (lsu_mmu_xlat_mat     ),
    .csr_plv               (mmu_plv              ),
    .csr_da                (mmu_da               ),
    .csr_pg                (mmu_pg               ),
    .csr_datf              (mmu_datf             ),
    .csr_datm              (mmu_datm             ),
    .csr_asid              (mmu_asid             ),
    .csr_pgdl              (mmu_pgdl             ),
    .csr_pgdh              (mmu_pgdh             ),
    .csr_dmw0              (mmu_dmw0             ),
    .csr_dmw1              (mmu_dmw1             ),
    .csr_pwcl              (mmu_pwcl             ),
    .csr_pwch              (mmu_pwch             ),
    .csr_ptw_en            (mmu_ptw_en           ),
    .csr_inv_vld           (mmu_inv_vld          ),
    .csr_inv_op            (mmu_inv_op           ),
    .csr_inv_asid          (mmu_inv_asid         ),
    .csr_inv_vaddr         (mmu_inv_vaddr        ),
    .ptw_dcache_req_vld    (ptw_dc_req_vld       ),
    .dcache_ptw_req_rdy    (ptw_dc_req_rdy       ),
    .ptw_dcache_req_paddr  (ptw_dc_req_pa        ),
    .dcache_ptw_resp_vld   (ptw_dc_resp_vld      ),
    .dcache_ptw_resp_data  (ptw_dc_resp_data     ),
    .dcache_ptw_resp_err   (ptw_dc_resp_err      )
);

//------------------------------------------------------------//
//                       PTW DCache Access
//------------------------------------------------------------//

assign dcpu_req_vld      =  mmu_page_mode ? lsu_mmu_cache_vld : dcc_req_rd_wr;
assign dcpu_req_wait     =  mmu_page_mode && lsu_mmu_cache_wait;
assign dcpu_req_replay   =  mmu_page_mode && lsu_mmu_cache_vld
                            && !lsu_mmu_cache_wait;
assign dcpu_req_rd       =  mmu_page_mode ? !memld_st_write : dcc_req_rd;
assign dcpu_req_exc      =  mmu_page_mode ? memld_st_exc : dcc_req_exc;
assign dcpu_req_pre_err  =  mmu_page_mode ? 1'b0 : mald_pre_s_err;
assign dcpu_req_dbgm     =  mmu_page_mode ? memld_st_dbgm : dcc_req2dbgm;
assign dcpu_req_size     =  mmu_page_mode ? memld_st_size : dcc_size;
assign dcpu_req_va       =  mmu_page_mode ? lsu_mmu_cache_va : dcc_vaddr;
assign dcpu_req_pa       =  mmu_page_mode ? lsu_mmu_cache_pa : dcc_paddr;
assign dcpu_req_mat      =  mmu_page_mode ? lsu_mmu_cache_mat : 2'b00;
assign dcpu_req_bank     =  dcpu_req_va[4:2];
assign dcpu_req_wdata    =  dcc_wdata;
assign darb_cache_req_rdy =  all_addr_ok_cache0;

mmu_dcache_arb x_mmu_dcache_arb (
    .clk               (clk                    ),
    .reset             (reset                  ),
    .cpu_req_vld       (dcpu_req_vld           ),
    .cpu_req_rdy       (dcpu_req_rdy           ),
    .cpu_req_wait      (dcpu_req_wait          ),
    .cpu_req_replay    (dcpu_req_replay        ),
    .cpu_req_rd        (dcpu_req_rd            ),
    .cpu_req_exc       (dcpu_req_exc           ),
    .cpu_req_pre_err   (dcpu_req_pre_err       ),
    .cpu_req_dbgm      (dcpu_req_dbgm          ),
    .cpu_req_size      (dcpu_req_size          ),
    .cpu_req_vaddr     (dcpu_req_va            ),
    .cpu_req_paddr     (dcpu_req_pa            ),
    .cpu_req_mat       (dcpu_req_mat           ),
    .cpu_req_bank      (dcpu_req_bank          ),
    .cpu_req_wdata     (dcpu_req_wdata         ),
    .cpu_resp_vld      (dcpu_resp_vld          ),
    .cpu_resp_data     (dcpu_resp_data         ),
    .cpu_resp_exok     (dcpu_resp_exok         ),
    .cpu_resp_err      (dcpu_resp_err          ),
    .ptw_req_vld       (ptw_dc_req_vld         ),
    .ptw_req_rdy       (ptw_dc_req_rdy         ),
    .ptw_req_paddr     (ptw_dc_req_pa          ),
    .ptw_busy          (ptw_dc_busy            ),
    .ptw_resp_vld      (ptw_dc_resp_vld        ),
    .ptw_resp_data     (ptw_dc_resp_data       ),
    .ptw_resp_err      (ptw_dc_resp_err        ),
    .cache_req_vld     (darb_cache_req_vld     ),
    .cache_req_rdy     (darb_cache_req_rdy     ),
    .cache_req_wait    (darb_cache_req_wait    ),
    .cache_req_rd      (darb_cache_req_rd      ),
    .cache_req_exc     (darb_cache_req_exc     ),
    .cache_req_pre_err (darb_cache_req_pre_err ),
    .cache_req_dbgm    (darb_cache_req_dbgm    ),
    .cache_req_size    (darb_cache_req_size    ),
    .cache_req_vaddr   (darb_cache_req_va      ),
    .cache_req_paddr   (darb_cache_req_pa      ),
    .cache_req_mat     (darb_cache_req_mat     ),
    .cache_req_bank    (darb_cache_req_bank    ),
    .cache_req_wdata   (darb_cache_req_wdata   ),
    .cache_resp_vld    (rdata_valid_cache0     ),
    .cache_resp_data   (rdata_cache0           ),
    .cache_resp_exok   (rdata_exok_cache0      ),
    .cache_resp_err    (rdata_err_cache0       ),
    .cache_idle        (dcc_cache_axi_null     )
);
// End Hardware Address Translation

//------------------------------------------------------------//
`endif
//                          ifc2perf
//------------------------------------------------------------//
assign cache_perf_events   =  {dcc_uncached_sbus   ,
                                icc_cached_sbus      ,
                                dcc_all_ecc_err_add1 ,
                                dcc_refill_add1      ,
                                icc_all_ecc_err_add1 ,
                                icc_refill_add1      };
generate
    if (PERF_CNT_NUM > 0) begin: gen_cache_perf_bus
        assign cache_csr_perf_bus = cache_perf_events;
    end else begin: gen_no_cache_perf_bus
        assign cache_csr_perf_bus = {`OPEN132_CACHE_PERF_EVENT_BUS_WIDTH{1'b0}};
    end
endgenerate
// End ifc2perf

//------------------------------------------------------------//
//                      request< >dcache
//------------------------------------------------------------//
assign dcc_req_rd_wr  =  req_mald||req_memld_st;
assign dcc_req_rd     =  req_mald||req_memld_st&&!memld_st_write;
assign dcc_req_exc    =  req_memld_st&&memld_st_exc;  // |-> !req_mald
assign dcc_size       =  req_mald ? 2'b10 : memld_st_size;
assign dcc_vaddr      =  req_mald ? de_mald_vaddr : memld_st_vaddr;
assign dcc_req_bank   =  dcc_vaddr[4:2];
assign dcc_wdata      =  st_wdata;

`ifdef CONFIG_MMU
assign de_mald_req_s_ready   =  mmu_page_mode ? 1'b0 :
                                  dcc_cd_ar_addr_ok && req_mald_pre_ok;
assign memld_st_req_s_ready  =  mmu_page_mode
                                  ? (memld_st_write ? lsu_mmu_store_done
                                                     : lsu_mmu_req_rdy) :
                                  !req_mald&&req_memld_st&&
`else
assign de_mald_req_s_ready   =  dcc_cd_ar_addr_ok && req_mald_pre_ok;
assign memld_st_req_s_ready  =  !req_mald&&req_memld_st&&
`endif
                                  (dcc_md_ar_addr_ok&&!memld_st_write&&!dcc_req2dbgm||
                                  dcc_aw_addr_ok   && memld_st_write&&!dcc_req2dbgm||
                                  dcc_dbgm_addr_ok &&                  dcc_req2dbgm);
assign ld_data_s_ready       =  dcc_rdata_valid;
assign ld_data_s_exok        =  dcc_rdata_exok;
assign ld_data_s_err         =  dcc_rdata_err;
assign ld_data_s_rdata       =  {32{ld_data_s_ready}} & dcc_rdata;
// End request< >dcace

`ifdef OPEN132_CHIP_NO_SLC
assign cached_biu_nocache_0  =  1'b0;
`else
assign cached_biu_nocache_0  =  dcc_cached;
`endif

// Cache-load and memory-load requests are mutually exclusive. Virtual and
// physical address bits [28:2] are equivalent for this conflict comparison.
assign dcc_cd_hit_wr          =  de_load_req &&
                                   de_mald_vaddr[28:2] == dcc_axi_awaddr[28:2];
assign dcc_md_hit_wr          =  memld_st_req&&!memld_st_write &&
                                   (memld_st_vaddr[28:2] == dcc_axi_awaddr[28:2] ||
                                   memld_st_dald);
assign nc_sbus_real_sel_mald  =  sbus_real_sel_mald;
assign nc_de_load_req         =  de_load_req;
assign nc_memld_st_req        =  memld_st_req;
assign nc_memld_st_dald       =  memld_st_dald;
assign nc_sbus_sel_mald       =  sbus_sel_mald;
assign nc_mald_pre_s_ok       =  mald_pre_s_ok;
assign nc_mald_pre_s_err      =  mald_pre_s_err;
assign nc_dcc_bypass          =  dcc_bypass;

`ifdef CONFIG_MMU
assign req_mald                     =  mmu_page_mode ? 1'b0 :
                                        HAS_DCC ? sbus_sel_mald : sbus_real_sel_mald;
`else
assign req_mald                     =  HAS_DCC ? sbus_sel_mald : sbus_real_sel_mald;
`endif
assign req_memld_st                 =  sbus_sel_memld_st;
assign req_mald_pre_ok              =  HAS_DCC ? mald_pre_s_ok : sbus_real_sel_mald;
assign dcc_stall_cps                =  HAS_DCC ? !dcc_cps_req_ok : 1'b0;
assign mem_cps_req_dcc              =  HAS_DCC ? mem_cc_op_d&&mem_cps_req : 1'b0;
assign dcc_cache_ram_tagv_resp_bus  =  {{(DCC_CACHE_TAGV_RESP_WD-`OPEN132_DCC_RAM_TAGV_RESP_BUS_WD){1'b0}},
                                         dcc_ram_tagv_resp_bus};
assign dcc_cache_ram_data_resp_bus  =  {{(DCC_CACHE_DATA_RESP_WD-`OPEN132_DCC_RAM_DATA_RESP_BUS_WD){1'b0}},
                                         dcc_ram_data_resp_bus};
assign dcc_cache_ram_lrud_resp_bus  =  {{(DCC_CACHE_LRUD_RESP_WD-`OPEN132_DCC_RAM_LRUD_RESP_BUS_WD){1'b0}},
                                         dcc_ram_lrud_resp_bus};

generate
if (HAS_DCC) begin: gen_has_dcc
lsu_cache #(
    .AXI_DATA             (AXI_DATA_CACHE0            ),  // 32/64/128
    .AXI_WID_N            (AXI_WID_N_CACHE0           ),  // 1/2/4/8
    .SET_ASSOC            (SET_ASSOC_CACHE0           ),  // 1/2/4 way set associative
    .WAYSIZE              (WAYSIZE_CACHE0             ),  // 1/2/4/8/16 KB Size/way
    .ECC_BITS             (ECC_BITS_CACHE0            ),
    .RAM_TAGV_REQ_BUS_WD  (RAM_TAGV_REQ_BUS_WD_CACHE0 ),
    .RAM_DATA_REQ_BUS_WD  (RAM_DATA_REQ_BUS_WD_CACHE0 ),
    .RAM_LRUD_REQ_BUS_WD  (RAM_LRUD_REQ_BUS_WD_CACHE0 ),
    .RAM_TAGV_RESP_BUS_WD (RAM_TAGV_RESP_BUS_WD_CACHE0),
    .RAM_DATA_RESP_BUS_WD (RAM_DATA_RESP_BUS_WD_CACHE0),
    .RAM_LRUD_RESP_BUS_WD (RAM_LRUD_RESP_BUS_WD_CACHE0)
) x_lsu_cache_0 (
    .is_icache         (is_icache_cache0        ),
    // clk and reset
    .clk               (clk_cache0              ),
    .clk_ng            (clk_ng_cache0           ),
    .reset             (reset_cache0            ),
    .data_reset        (data_reset_cache0       ),
    .ctrl_nowrap       (ctrl_nowrap_cache0      ),
    .ex_cancel         (ex_cancel_cache0        ),

    // ifc <--> cache
    .req_rd_wr         (req_rd_wr_cache0        ),  // request read or write
    .req_rd            (req_rd_cache0           ),  // request read
    .req_exc           (req_exc_cache0          ),  // request exclusive access
    .size              (size_cache0             ),  // request size
`ifdef CONFIG_MMU
    .vaddr             (vaddr_cache0            ),  // request virtual address
`else
    .vaddr_h3          (vaddr_h3_cache0         ),  // request vaddr[31:29]
`endif
    .paddr             (paddr_cache0            ),  // request paddr
`ifdef CONFIG_MMU
    .req_xlat_wait     (req_xlat_wait_cache0    ),
    .req_attr_vld      (req_attr_vld_cache0     ),
    .req_sob           (req_sob_cache0          ),
    .req_cached        (req_cached_cache0       ),
    .req_alloc         (req_alloc_cache0        ),
    .xlat_vld          (xlat_vld_cache0         ),
    .xlat_cancel       (xlat_cancel_cache0      ),
    .xlat_paddr        (xlat_paddr_cache0       ),
    .xlat_sob          (xlat_sob_cache0         ),
    .xlat_cached       (xlat_cached_cache0      ),
    .xlat_alloc        (xlat_alloc_cache0       ),
`endif
    .wdata             (wdata_cache0            ),  // request write data
    .rdata             (rdata_cache0            ),  // read data
    .rdata_valid       (rdata_valid_cache0      ),  // rdata is valid
    .rdata_exok        (rdata_exok_cache0       ),  // rdata is exokay
    .rdata_err         (rdata_err_cache0        ),  // rdata is error

    .rd_in_sysbus      (rd_in_sysbus_cache0     ),
    .wr_in_sysbus      (                        ),
    .axi_null          (axi_null_cache0         ),
    .go_mmu_vaddr      (go_mmu_vaddr_cache0     ),  // from tagcmp
    .go_mmu_read       (go_mmu_read_cache0      ),
    .go_mmu_dbgm       (go_mmu_dbgm_cache0      ),
    .mmu_sob           (mmu_sob_cache0          ),  // strong-order-back
    .mmu_cached        (mmu_cached_cache0       ),  // cached
    .mmu_alloc         (mmu_alloc_cache0        ),  // alloc if miss
    // LJTAG
    .req2dbgm          (req2dbgm_cache0         ),
    .dbgm_req_valid    (dbgm_req_valid_cache0   ),
    .dbgm_req_wr       (dbgm_req_wr_cache0      ),
    .dbgm_req_addr     (dbgm_req_addr_cache0    ),
    .dbgm_req_size     (dbgm_req_size_cache0    ),
    .dbgm_req_wdata    (dbgm_req_wdata_cache0   ),
    .dbgm_resp_valid   (dbgm_resp_valid_cache0  ),
    .dbgm_resp_data    (dbgm_resp_data_cache0   ),

    // cache <--> axi
    .dcc_ar_stall_icc  (dcc_ar_stall_icc_cache0 ),  // dcc-ar stall icc-ar
    .axi_arvalid       (axi_arvalid_cache0      ),  // read request
    .axi_arready       (axi_arready_cache0      ),  // read request received
    .axi_arburst       (axi_arburst_cache0      ),  // read burst
    .axi_arexc         (axi_arexc_cache0        ),  // read exclusive
    .axi_arcache       (axi_arcache_cache0      ),  // read cached
    .axi_arsize        (axi_arsize_cache0       ),  // read size
    .axi_araddr        (axi_araddr_cache0       ),  // read addr
    .axi_rvalid        (axi_rvalid_cache0       ),  // read response valid
    .axi_rdata         (axi_rdata_cache0        ),  // read data
    .axi_rresp         (axi_rresp_cache0        ),  // read response

    .axi_aw_wid        (axi_aw_wid_cache0       ),  // write id
    .axi_awvalid       (axi_awvalid_cache0      ),  // write request
    .axi_awready       (axi_awready_cache0      ),  // write request received
    .axi_awburst       (axi_awburst_cache0      ),  // write burst
    .axi_awexc         (axi_awexc_cache0        ),  // write exclusive
    .axi_awcache       (axi_awcache_cache0      ),  // write cached
    .axi_awsize        (axi_awsize_cache0       ),  // write size
    .axi_awaddr        (axi_awaddr_cache0       ),  // write addr
    .axi_wvalid        (axi_wvalid_cache0       ),  // write data request
    .axi_wready        (axi_wready_cache0       ),  // write data received
    .axi_wstrb         (axi_wstrb_cache0        ),  // write strobe
    .axi_wdata         (axi_wdata_cache0        ),  // write data
    .axi_wlast         (axi_wlast_cache0        ),  // write last data
    .axi_bvalid        (axi_bvalid_cache0       ),  // write response valid
    .axi_bid           (axi_bid_cache0          ),  // write bid[2:0]

    .all_addr_ok       (all_addr_ok_cache0      ),  // request to ar, aw, dbgm
    .req_pre_err       (req_pre_err_cache0      ),  // request prediction is fail
    .req_bank          (req_bank_cache0         ),  // request bank
    // cache operation, address is in addr
    .cc_op             (cc_op_cache0            ),  // cache/isync op
    .cc_isync          (cc_isync_cache0         ),  // if op_d and op_i, means isync
    .cc_sttag          (cc_sttag_cache0         ),
    .cc_pref           (cc_pref_cache0          ),  // pref
    .cc_lock           (cc_lock_cache0          ),  // lock
    .cc_op_stall       (cc_op_stall_cache0      ),  // for isync
    .cps_req_ok        (cps_req_ok_cache0       ),
    .cps_data_ok       (cps_data_ok_cache0      ),
    .cps_rdata         (cps_rdata_cache0        ),
    .bypass            (bypass_cache0           ),  // has cache, but no access
    // ecc fatal
    .all_fatal         (all_fatal_cache0        ),  // ecc fatal in dcache
    .load_fatal        (load_fatal_cache0       ),  // load ecc fatal, precise
    .store_fatal       (store_fatal_cache0      ),  // store ecc fatal,imprecise
    .ccop_fatal        (ccop_fatal_cache0       ),  // ccop ecc fatal,imprecise
    .rf_impr_fatal     (rf_impr_fatal_cache0    ),  // refill
    .fatal_intagv      (fatal_intagv_cache0     ),
    .fatal_indata      (fatal_indata_cache0     ),
    .fatal_indx        (fatal_indx_cache0       ),
    .fatal_way         (fatal_way_cache0        ),
    .fatal_dirtywb     (fatal_dirtywb_cache0    ),  // 2bit err data writeback.
    .fatal_dirty_tag   (fatal_dirty_tag_cache0  ),
    // ecc 1bit error count
    .all_ecc_err_add1  (all_ecc_err_add1_cache0 ),
    .refill_add1       (refill_add1_cache0      ),
    .resetn_in_d2      (resetn_in_d2_cache0     ),
    .ram_init_cmplt    (ram_init_cmplt_cache0   ),
    // ram interface
    .ram_tagv_req_bus  (ram_tagv_req_bus_cache0 ),
    .ram_data_req_bus  (ram_data_req_bus_cache0 ),
    .ram_lrud_req_bus  (ram_lrud_req_bus_cache0 ),  // write by bit
    .ram_tagv_resp_bus (ram_tagv_resp_bus_cache0),
    .ram_data_resp_bus (ram_data_resp_bus_cache0),
    .ram_lrud_resp_bus (ram_lrud_resp_bus_cache0)
);

end else begin: gen_no_dcc
// axi-read address hit wr, for cacheld/memld
// NOTE: de_load_req and a read memld_st_req are mutually exclusive.

biu_nocache #(
    .AXI_DATA (AXI_DATA_NC_CH0)  // 32/64/128
) x_biu_nocache_0 (
    .is_icache        (is_icache_nc_ch0       ),
    // clk and reset
    .clk              (clk_nc_ch0             ),
    .clk_ng           (clk_ng_nc_ch0          ),
    .reset            (reset_nc_ch0           ),
    .data_reset       (data_reset_nc_ch0      ),
    .ex_cancel        (ex_cancel_nc_ch0       ),

    // ifc <--> cache
    .req_rd_wr        (req_rd_wr_nc_ch0       ),  // request read or write
    .req_rd           (req_rd_nc_ch0          ),  // request read
    .req_exc          (req_exc_nc_ch0         ),  // request exclusive access
    .cached           (cached_biu_nocache_0   ),  // request is cached
    .size             (size_nc_ch0            ),  // request size
    .paddr            (paddr_nc_ch0           ),  // request paddr
    .wdata            (wdata_nc_ch0           ),  // request write data
    .rdata            (rdata_nc_ch0           ),  // read data
    .rdata_valid      (rdata_valid_nc_ch0     ),  // rdata is valid
    .rdata_exok       (rdata_exok_nc_ch0      ),  // rdata is exokay
    .rdata_err        (rdata_err_nc_ch0       ),  // rdata is error

    .rd_in_sysbus     (rd_in_sysbus_nc_ch0    ),
    .wr_in_sysbus     (                       ),
    .axi_null         (axi_null_nc_ch0        ),
    // LJTAG
    .req2dbgm         (req2dbgm_nc_ch0        ),
    .dbgm_req_valid   (dbgm_req_valid_nc_ch0  ),
    .dbgm_req_wr      (dbgm_req_wr_nc_ch0     ),
    .dbgm_req_addr    (dbgm_req_addr_nc_ch0   ),
    .dbgm_req_size    (dbgm_req_size_nc_ch0   ),
    .dbgm_req_wdata   (dbgm_req_wdata_nc_ch0  ),
    .dbgm_resp_valid  (dbgm_resp_valid_nc_ch0 ),
    .dbgm_resp_data   (dbgm_resp_data_nc_ch0  ),

    // cache <--> axi
    .dcc_ar_stall_icc (dcc_ar_stall_icc_nc_ch0),  // dcc-ar stall icc-ar
    .axi_arvalid      (axi_arvalid_nc_ch0     ),  // read request
    .axi_arready      (axi_arready_nc_ch0     ),  // read request received
    .axi_arburst      (axi_arburst_nc_ch0     ),  // read burst
    .axi_arexc        (axi_arexc_nc_ch0       ),  // read exclusive
    .axi_arcache      (axi_arcache_nc_ch0     ),  // read cached
    .axi_arsize       (axi_arsize_nc_ch0      ),  // read size
    .axi_araddr       (axi_araddr_nc_ch0      ),  // read addr
    .axi_rvalid       (axi_rvalid_nc_ch0      ),  // read response valid
    .axi_rdata        (axi_rdata_nc_ch0       ),  // read data
    .axi_rresp        (axi_rresp_nc_ch0       ),  // read response

    .axi_aw_wid       (axi_aw_wid_nc_ch0      ),  // write id
    .axi_awvalid      (axi_awvalid_nc_ch0     ),  // write request
    .axi_awready      (axi_awready_nc_ch0     ),  // write request received
    .axi_awburst      (axi_awburst_nc_ch0     ),  // write burst
    .axi_awexc        (axi_awexc_nc_ch0       ),  // write exclusive
    .axi_awcache      (axi_awcache_nc_ch0     ),  // write cached
    .axi_awsize       (axi_awsize_nc_ch0      ),  // write size
    .axi_awaddr       (axi_awaddr_nc_ch0      ),  // write addr
    .axi_wvalid       (axi_wvalid_nc_ch0      ),  // write data request
    .axi_wready       (axi_wready_nc_ch0      ),  // write data received
    .axi_wstrb        (axi_wstrb_nc_ch0       ),  // write strobe
    .axi_wdata        (axi_wdata_nc_ch0       ),  // write data
    .axi_wlast        (axi_wlast_nc_ch0       ),  // write last data
    .axi_bvalid       (axi_bvalid_nc_ch0      ),  // write response
    .axi_bid          (axi_bid_nc_ch0         ),  // write bid[2:0]

    .cd_ar_addr_ok    (cd_ar_addr_ok_nc_ch0   ),  // request to ar, for cacheld
    .md_ar_addr_ok    (md_ar_addr_ok_nc_ch0   ),  // request to ar, for memld
    .aw_addr_ok       (aw_addr_ok_nc_ch0      ),  // request to aw
    .dbgm_addr_ok     (dbgm_addr_ok_nc_ch0    ),  // request to dbgm
    .cd_hit_wr        (cd_hit_wr_nc_ch0       ),  // axi-read address hit wr, for cahceld
    .md_hit_wr        (md_hit_wr_nc_ch0       )   // axi-read address hit wr, for memld
);
end
endgenerate

assign dcc_cd_ar_addr_ok  =  HAS_DCC ? dcc_cache_all_addr_ok :
                               dcc_nocache_cd_ar_addr_ok;
assign dcc_md_ar_addr_ok  =  HAS_DCC ? dcc_cache_all_addr_ok :
                               dcc_nocache_md_ar_addr_ok;
assign dcc_aw_addr_ok     =  HAS_DCC ? dcc_cache_all_addr_ok : dcc_nocache_aw_addr_ok;
assign dcc_dbgm_addr_ok   =  HAS_DCC ? dcc_cache_all_addr_ok : dcc_nocache_dbgm_addr_ok;
assign dcc_rdata          =  HAS_DCC ? dcc_cache_rdata : dcc_nocache_rdata;
assign dcc_rdata_valid    =  HAS_DCC ? dcc_cache_rdata_valid : dcc_nocache_rdata_valid;
assign dcc_rdata_exok     =  HAS_DCC ? dcc_cache_rdata_exok : dcc_nocache_rdata_exok;
assign dcc_rdata_err      =  HAS_DCC ? dcc_cache_rdata_err : dcc_nocache_rdata_err;
assign dcc_rd_in_sysbus   =  HAS_DCC ? dcc_cache_rd_in_sysbus : dcc_nocache_rd_in_sysbus;
assign dcc_axi_null       =  HAS_DCC ? dcc_cache_axi_null : dcc_nocache_axi_null;

assign dcc_cc_vaddr        =  HAS_DCC ? dcc_cache_cc_vaddr : 32'd0;
assign dcc_cc_read         =  HAS_DCC ? dcc_cache_cc_read : 1'b0;
assign dcc_cc_dbgm         =  HAS_DCC ? dcc_cache_cc_dbgm : 1'b0;
assign dcc_dbgm_req_valid  =  HAS_DCC ? dcc_cache_dbgm_req_valid : dcc_nocache_dbgm_req_valid;
assign dcc_dbgm_req_wr     =  HAS_DCC ? dcc_cache_dbgm_req_wr : dcc_nocache_dbgm_req_wr;
assign dcc_dbgm_req_addr   =  HAS_DCC ? dcc_cache_dbgm_req_addr : dcc_nocache_dbgm_req_addr;
assign dcc_dbgm_req_size   =  HAS_DCC ? dcc_cache_dbgm_req_size : dcc_nocache_dbgm_req_size;
assign dcc_dbgm_req_wdata  =  HAS_DCC ? dcc_cache_dbgm_req_wdata : dcc_nocache_dbgm_req_wdata;

assign dcc_ar_stall_icc  =  HAS_DCC ? dcc_cache_axi_ar_stall_icc : dcc_nocache_axi_ar_stall_icc;
assign dcc_axi_arvalid   =  HAS_DCC ? dcc_cache_axi_arvalid : dcc_nocache_axi_arvalid;
assign dcc_axi_arburst   =  HAS_DCC ? dcc_cache_axi_arburst : dcc_nocache_axi_arburst;
assign dcc_axi_arexc     =  HAS_DCC ? dcc_cache_axi_arexc : dcc_nocache_axi_arexc;
assign dcc_axi_arcache   =  HAS_DCC ? dcc_cache_axi_arcache : dcc_nocache_axi_arcache;
assign dcc_axi_arsize    =  HAS_DCC ? dcc_cache_axi_arsize : dcc_nocache_axi_arsize;
assign dcc_axi_araddr    =  HAS_DCC ? dcc_cache_axi_araddr : dcc_nocache_axi_araddr;
assign dcc_axi_aw_wid    =  HAS_DCC ? dcc_cache_axi_aw_wid : dcc_nocache_axi_aw_wid;
assign dcc_axi_awvalid   =  HAS_DCC ? dcc_cache_axi_awvalid : dcc_nocache_axi_awvalid;
assign dcc_axi_awburst   =  HAS_DCC ? dcc_cache_axi_awburst : dcc_nocache_axi_awburst;
assign dcc_axi_awexc     =  HAS_DCC ? dcc_cache_axi_awexc : dcc_nocache_axi_awexc;
assign dcc_axi_awcache   =  HAS_DCC ? dcc_cache_axi_awcache : dcc_nocache_axi_awcache;
assign dcc_axi_awsize    =  HAS_DCC ? dcc_cache_axi_awsize : dcc_nocache_axi_awsize;
assign dcc_axi_awaddr    =  HAS_DCC ? dcc_cache_axi_awaddr : dcc_nocache_axi_awaddr;
assign dcc_axi_wvalid    =  HAS_DCC ? dcc_cache_axi_wvalid : dcc_nocache_axi_wvalid;
assign dcc_axi_wstrb     =  HAS_DCC ? dcc_cache_axi_wstrb : dcc_nocache_axi_wstrb;
assign dcc_axi_wdata     =  HAS_DCC ? dcc_cache_axi_wdata : dcc_nocache_axi_wdata;
assign dcc_axi_wlast     =  HAS_DCC ? dcc_cache_axi_wlast : dcc_nocache_axi_wlast;

assign dcc_cps_req_ok         =  HAS_DCC ? dcc_cache_cps_req_ok : 1'b0;
assign dcc_cps_data_ok        =  HAS_DCC ? dcc_cache_cps_data_ok : 1'b0;
assign dcc_cps_rdata          =  HAS_DCC ? dcc_cache_cps_rdata : 32'd0;
assign dcc_all_fatal          =  HAS_DCC ? dcc_cache_all_fatal : 1'b0;
assign dcc_rd_fatal           =  HAS_DCC ? dcc_cache_rd_fatal : 1'b0;
assign dcc_wr_fatal           =  HAS_DCC ? dcc_cache_wr_fatal : 1'b0;
assign dcc_ccop_fatal         =  HAS_DCC ? dcc_cache_ccop_fatal : 1'b0;
assign dcc_rf_impr_fatal      =  HAS_DCC ? dcc_cache_rf_impr_fatal : 1'b0;
assign dcc_fatal_intagv       =  HAS_DCC ? dcc_cache_fatal_intagv : 1'b0;
assign dcc_fatal_indata       =  HAS_DCC ? dcc_cache_fatal_indata : 8'd0;
assign dcc_fatal_dirtywb      =  HAS_DCC ? dcc_cache_fatal_dirtywb : 1'b0;
assign dcc_fatal_indx10       =  HAS_DCC ?
                                   {{(10-`OPEN132_DCC_INDEX_BITS){1'b0}},dcc_cache_fatal_indx} : 10'd0;
assign dcc_fatal_way5         =  HAS_DCC ?
                                   {{(5-`OPEN132_DCC_SET_ASSOC){1'b0}},dcc_cache_fatal_way} : 5'd0;
assign dcc_fatal_dirty_tag23  =  HAS_DCC ?
                                   {{(23-`OPEN132_DCC_TAG_BITS){1'b0}},dcc_cache_fatal_dirty_tag} : 23'd0;
assign dcc_ram_init_cmplt     =  HAS_DCC ? dcc_cache_ram_init_cmplt : 1'b1;
assign dcc_all_ecc_err_add1   =  HAS_DCC ? dcc_cache_all_ecc_err_add1 : 1'b0;
assign dcc_refill_add1        =  HAS_DCC ? dcc_cache_refill_add1 : 1'b0;

assign dcc_ram_tagv_req_bus  =  HAS_DCC ?
                                  dcc_cache_ram_tagv_req_bus[`OPEN132_DCC_RAM_TAGV_REQ_BUS_WD-1:0] :
                                  {`OPEN132_DCC_RAM_TAGV_REQ_BUS_WD{1'b0}};
assign dcc_ram_data_req_bus  =  HAS_DCC ?
                                  dcc_cache_ram_data_req_bus[`OPEN132_DCC_RAM_DATA_REQ_BUS_WD-1:0] :
                                  {`OPEN132_DCC_RAM_DATA_REQ_BUS_WD{1'b0}};
assign dcc_ram_lrud_req_bus  =  HAS_DCC ?
                                  dcc_cache_ram_lrud_req_bus[`OPEN132_DCC_RAM_LRUD_REQ_BUS_WD-1:0] :
                                  {`OPEN132_DCC_RAM_LRUD_REQ_BUS_WD{1'b0}};
// End Dcache

//------------------------------------------------------------//
//                      request< >icache
//------------------------------------------------------------//
assign icc_req_rd_wr  =  icc_req_rd;
assign icc_req_rd     =  req_ft && !mem_cps_req_icc;
assign icc_vaddr      =  mem_cps_req_icc ? memld_st_vaddr : fetch_vaddr;
assign icc_req_bank   =  icc_vaddr[4:2];

`ifdef CONFIG_MMU
assign fetch_req_s_ready  =  mmu_page_mode ? ifu_mmu_req_rdy :
                               req_ft_pre_ok &&(icc_ar_addr_ok  &&!icc_req2dbgm ||
`else
assign fetch_req_s_ready  =  req_ft_pre_ok &&(icc_ar_addr_ok  &&!icc_req2dbgm ||
`endif
                               icc_dbgm_addr_ok&& icc_req2dbgm );
assign ft_data_s_ready    =  icc_rdata_valid;
assign ft_data_s_err      =  icc_rdata_err;
assign ft_data_s_rdata    =  {32{ft_data_s_ready}} & icc_rdata;
// End request< >dcace

`ifdef OPEN132_CHIP_NO_SLC
assign cached_biu_nocache_1  =  1'b0;
`else
assign cached_biu_nocache_1  =  icc_cached;
`endif

assign nc_sbus_real_sel_ft  =  sbus_real_sel_ft;
assign nc_sbus_sel_ft       =  sbus_sel_ft;
assign nc_ft_pre_s_ok       =  ft_pre_s_ok;
assign nc_ft_pre_s_err      =  ft_pre_s_err;
assign nc_icc_bypass        =  icc_bypass;

assign req_ft                       =  HAS_ICC ? sbus_sel_ft : sbus_real_sel_ft;
assign req_ft_pre_ok                =  HAS_ICC ? ft_pre_s_ok : sbus_real_sel_ft;
assign icc_stall_cps                =  HAS_ICC ? !icc_cps_req_ok : 1'b0;
assign mem_cps_req_icc              =  HAS_ICC ? mem_cc_op_i&&mem_cps_req : 1'b0;
assign icc_cache_ram_tagv_resp_bus  =  {{(ICC_CACHE_TAGV_RESP_WD-`OPEN132_ICC_RAM_TAGV_RESP_BUS_WD){1'b0}},
                                         icc_ram_tagv_resp_bus};
assign icc_cache_ram_data_resp_bus  =  {{(ICC_CACHE_DATA_RESP_WD-`OPEN132_ICC_RAM_DATA_RESP_BUS_WD){1'b0}},
                                         icc_ram_data_resp_bus};
assign icc_cache_ram_lrud_resp_bus  =  {{(ICC_CACHE_LRUD_RESP_WD-`OPEN132_ICC_RAM_LRUD_RESP_BUS_WD){1'b0}},
                                         icc_ram_lrud_resp_bus};

generate
if (HAS_ICC) begin: gen_has_icc
lsu_cache #(
    .AXI_DATA             (AXI_DATA_CACHE1            ),  // 32/64/128
    .AXI_WID_N            (AXI_WID_N_CACHE1           ),  // 1 for icache.
    .SET_ASSOC            (SET_ASSOC_CACHE1           ),  // 1/2/4 way set associative
    .WAYSIZE              (WAYSIZE_CACHE1             ),  // 1/2/4/8/16 KB Size/way
    .ECC_BITS             (ECC_BITS_CACHE1            ),
    .RAM_TAGV_REQ_BUS_WD  (RAM_TAGV_REQ_BUS_WD_CACHE1 ),
    .RAM_DATA_REQ_BUS_WD  (RAM_DATA_REQ_BUS_WD_CACHE1 ),
    .RAM_LRUD_REQ_BUS_WD  (RAM_LRUD_REQ_BUS_WD_CACHE1 ),
    .RAM_TAGV_RESP_BUS_WD (RAM_TAGV_RESP_BUS_WD_CACHE1),
    .RAM_DATA_RESP_BUS_WD (RAM_DATA_RESP_BUS_WD_CACHE1),
    .RAM_LRUD_RESP_BUS_WD (RAM_LRUD_RESP_BUS_WD_CACHE1)
) x_lsu_cache_1 (
    .is_icache         (is_icache_cache1        ),
    // clk and reset
    .clk               (clk_cache1              ),
    .clk_ng            (clk_ng_cache1           ),
    .reset             (reset_cache1            ),
    .data_reset        (data_reset_cache1       ),
    .ctrl_nowrap       (ctrl_nowrap_cache1      ),
    .ex_cancel         (ex_cancel_cache1        ),

    // ifc <--> cache
    .req_rd_wr         (req_rd_wr_cache1        ),  // request read or write
    .req_rd            (req_rd_cache1           ),  // request read
    .req_exc           (req_exc_cache1          ),  // request exclusive access
    .size              (size_cache1             ),  // request size
`ifdef CONFIG_MMU
    .vaddr             (vaddr_cache1            ),  // request virtual address
`else
    .vaddr_h3          (vaddr_h3_cache1         ),  // request vaddr
`endif
    .paddr             (paddr_cache1            ),  // register vaddr
`ifdef CONFIG_MMU
    .req_xlat_wait     (req_xlat_wait_cache1    ),
    .req_attr_vld      (req_attr_vld_cache1     ),
    .req_sob           (req_sob_cache1          ),
    .req_cached        (req_cached_cache1       ),
    .req_alloc         (req_alloc_cache1        ),
    .xlat_vld          (xlat_vld_cache1         ),
    .xlat_cancel       (xlat_cancel_cache1      ),
    .xlat_paddr        (xlat_paddr_cache1       ),
    .xlat_sob          (xlat_sob_cache1         ),
    .xlat_cached       (xlat_cached_cache1      ),
    .xlat_alloc        (xlat_alloc_cache1       ),
`endif
    .wdata             (wdata_cache1            ),  // request write data
    .rdata             (rdata_cache1            ),  // read data
    .rdata_valid       (rdata_valid_cache1      ),  // rdata is valid
    .rdata_exok        (                        ),  // rdata is exokay
    .rdata_err         (rdata_err_cache1        ),  // rdata is error

    .rd_in_sysbus      (rd_in_sysbus_cache1     ),
    .wr_in_sysbus      (                        ),
    .axi_null          (axi_null_cache1         ),
    .go_mmu_vaddr      (go_mmu_vaddr_cache1     ),  // from tagcmp
    .go_mmu_read       (                        ),
    .go_mmu_dbgm       (go_mmu_dbgm_cache1      ),
    .mmu_sob           (mmu_sob_cache1          ),  // 0 for icc
    .mmu_cached        (mmu_cached_cache1       ),  // cached
    .mmu_alloc         (mmu_alloc_cache1        ),  // 1 for icc, alloc if miss

    // LJTAG
    .req2dbgm          (req2dbgm_cache1         ),
    .dbgm_req_valid    (dbgm_req_valid_cache1   ),
    .dbgm_req_wr       (                        ),
    .dbgm_req_addr     (dbgm_req_addr_cache1    ),
    .dbgm_req_size     (dbgm_req_size_cache1    ),
    .dbgm_req_wdata    (                        ),
    .dbgm_resp_valid   (dbgm_resp_valid_cache1  ),
    .dbgm_resp_data    (dbgm_resp_data_cache1   ),

    // cache <--> axi
    .dcc_ar_stall_icc  (                        ),  // dcc-ar stall icc-ar, icc no it
    .axi_arvalid       (axi_arvalid_cache1      ),  // read request
    .axi_arready       (axi_arready_cache1      ),  // read request received
    .axi_arburst       (axi_arburst_cache1      ),  // read burst
    .axi_arexc         (                        ),  // read exclusive
    .axi_arcache       (axi_arcache_cache1      ),  // read cached
    .axi_arsize        (axi_arsize_cache1       ),  // read size
    .axi_araddr        (axi_araddr_cache1       ),  // read addr
    .axi_rvalid        (axi_rvalid_cache1       ),  // read response valid
    .axi_rdata         (axi_rdata_cache1        ),  // read data
    .axi_rresp         (axi_rresp_cache1        ),  // read response

    .axi_aw_wid        (                        ),  // write id
    .axi_awvalid       (                        ),  // write request
    .axi_awready       (axi_awready_cache1      ),  // write request received
    .axi_awburst       (                        ),  // write burst
    .axi_awexc         (                        ),  // write exclusive
    .axi_awcache       (                        ),  // write cached
    .axi_awsize        (                        ),  // write size
    .axi_awaddr        (                        ),  // write addr
    .axi_wvalid        (                        ),  // write data request
    .axi_wready        (axi_wready_cache1       ),  // write data received
    .axi_wstrb         (                        ),  // write strobe
    .axi_wdata         (                        ),  // write data
    .axi_wlast         (                        ),  // write last data
    .axi_bvalid        (axi_bvalid_cache1       ),  // write response valid
    .axi_bid           (axi_bid_cache1          ),  // write bid[2:0]

    .all_addr_ok       (all_addr_ok_cache1      ),  // request to ar, aw, dbgm
    .req_pre_err       (req_pre_err_cache1      ),  // request prediction is fail
    .req_bank          (req_bank_cache1         ),  // request bank
    // cache operation, address is in addr
    .cc_op             (cc_op_cache1            ),  // cache/isync op
    .cc_isync          (cc_isync_cache1         ),  // if op_d and op_i, means isync
    .cc_sttag          (cc_sttag_cache1         ),
    .cc_pref           (cc_pref_cache1          ),  // fill
    .cc_lock           (cc_lock_cache1          ),  // lock
    .cc_op_stall       (cc_op_stall_cache1      ),  // for isync
    .cps_req_ok        (cps_req_ok_cache1       ),
    .cps_data_ok       (cps_data_ok_cache1      ),
    .cps_rdata         (cps_rdata_cache1        ),
    .bypass            (bypass_cache1           ),  // has cache, but no access
    // ecc fatal
    .all_fatal         (all_fatal_cache1        ),  // ecc fatal in icache
    .load_fatal        (load_fatal_cache1       ),  // fetch ecc fatal, precise
    .store_fatal       (                        ),
    .ccop_fatal        (ccop_fatal_cache1       ),  // ccop ecc fatal,imprecise
    .rf_impr_fatal     (rf_impr_fatal_cache1    ),  // refill
    .fatal_intagv      (fatal_intagv_cache1     ),
    .fatal_indata      (fatal_indata_cache1     ),
    .fatal_indx        (fatal_indx_cache1       ),
    .fatal_way         (fatal_way_cache1        ),
    .fatal_dirtywb     (                        ),  // 2bit err data  writeback.
    .fatal_dirty_tag   (                        ),
    // ecc 1bit error count
    .all_ecc_err_add1  (all_ecc_err_add1_cache1 ),
    .refill_add1       (refill_add1_cache1      ),
    .resetn_in_d2      (resetn_in_d2_cache1     ),
    .ram_init_cmplt    (ram_init_cmplt_cache1   ),
    // ram interface
    .ram_tagv_req_bus  (ram_tagv_req_bus_cache1 ),
    .ram_data_req_bus  (ram_data_req_bus_cache1 ),
    .ram_lrud_req_bus  (ram_lrud_req_bus_cache1 ),  // write by bit
    .ram_tagv_resp_bus (ram_tagv_resp_bus_cache1),
    .ram_data_resp_bus (ram_data_resp_bus_cache1),
    .ram_lrud_resp_bus (ram_lrud_resp_bus_cache1)
);

end else begin: gen_no_icc
biu_nocache #(
    .AXI_DATA (AXI_DATA_NC_CH1)  // 32/64/128
) x_biu_nocache_1 (
    .is_icache        (is_icache_nc_ch1      ),
    // clk and reset
    .clk              (clk_nc_ch1            ),
    .clk_ng           (clk_ng_nc_ch1         ),
    .reset            (reset_nc_ch1          ),
    .data_reset       (data_reset_nc_ch1     ),
    .ex_cancel        (ex_cancel_nc_ch1      ),

    // ifc <--> cache
    .req_rd_wr        (req_rd_wr_nc_ch1      ),  // request read or write
    .req_rd           (req_rd_nc_ch1         ),  // request read
    .req_exc          (req_exc_nc_ch1        ),  // request exclusive access
    .cached           (cached_biu_nocache_1  ),  // request is cached
    .size             (size_nc_ch1           ),  // request size
    .paddr            (paddr_nc_ch1          ),  // request paddr
    .wdata            (wdata_nc_ch1          ),  // request write data
    .rdata            (rdata_nc_ch1          ),  // read data
    .rdata_valid      (rdata_valid_nc_ch1    ),  // rdata is valid
    .rdata_exok       (                      ),  // rdata is exokay
    .rdata_err        (rdata_err_nc_ch1      ),  // rdata is error

    .rd_in_sysbus     (rd_in_sysbus_nc_ch1   ),
    .wr_in_sysbus     (                      ),
    .axi_null         (axi_null_nc_ch1       ),
    // LJTAG
    .req2dbgm         (req2dbgm_nc_ch1       ),
    .dbgm_req_valid   (dbgm_req_valid_nc_ch1 ),
    .dbgm_req_wr      (                      ),
    .dbgm_req_addr    (dbgm_req_addr_nc_ch1  ),
    .dbgm_req_size    (dbgm_req_size_nc_ch1  ),
    .dbgm_req_wdata   (                      ),
    .dbgm_resp_valid  (dbgm_resp_valid_nc_ch1),
    .dbgm_resp_data   (dbgm_resp_data_nc_ch1 ),

    // cache <--> axi
    .dcc_ar_stall_icc (                      ),  // dcc-ar stall icc-ar, icc no it
    .axi_arvalid      (axi_arvalid_nc_ch1    ),  // read request
    .axi_arready      (axi_arready_nc_ch1    ),  // read request received
    .axi_arburst      (axi_arburst_nc_ch1    ),  // read burst
    .axi_arexc        (                      ),  // read exclusive
    .axi_arcache      (axi_arcache_nc_ch1    ),  // read cached
    .axi_arsize       (axi_arsize_nc_ch1     ),  // read size
    .axi_araddr       (axi_araddr_nc_ch1     ),  // read addr
    .axi_rvalid       (axi_rvalid_nc_ch1     ),  // read response valid
    .axi_rdata        (axi_rdata_nc_ch1      ),  // read data
    .axi_rresp        (axi_rresp_nc_ch1      ),  // read response

    .axi_aw_wid       (                      ),  // write id
    .axi_awvalid      (                      ),  // write request
    .axi_awready      (axi_awready_nc_ch1    ),  // write request received
    .axi_awburst      (                      ),  // write burst
    .axi_awexc        (                      ),  // write exclusive
    .axi_awcache      (                      ),  // write cached
    .axi_awsize       (                      ),  // write size
    .axi_awaddr       (                      ),  // write addr
    .axi_wvalid       (                      ),  // write data request
    .axi_wready       (axi_wready_nc_ch1     ),  // write data received
    .axi_wstrb        (                      ),  // write strobe
    .axi_wdata        (                      ),  // write data
    .axi_wlast        (                      ),  // write last data
    .axi_bvalid       (axi_bvalid_nc_ch1     ),  // write response
    .axi_bid          (axi_bid_nc_ch1        ),  // write bid[2:0]

    .cd_ar_addr_ok    (cd_ar_addr_ok_nc_ch1  ),  // request to ar
    .md_ar_addr_ok    (                      ),  // same as cd_ar_addr_ok for fetch
    .aw_addr_ok       (                      ),  // request to aw
    .dbgm_addr_ok     (dbgm_addr_ok_nc_ch1   ),  // request to dbgm
    .cd_hit_wr        (cd_hit_wr_nc_ch1      ),  // 1'b0 for fetch
    .md_hit_wr        (md_hit_wr_nc_ch1      )   // 1'b0 for fetch
);
end
endgenerate

assign icc_ar_addr_ok      =  HAS_ICC ? icc_cache_all_addr_ok : icc_nocache_ar_addr_ok;
assign icc_dbgm_addr_ok    =  HAS_ICC ? icc_cache_all_addr_ok : icc_nocache_dbgm_addr_ok;
assign icc_rdata           =  HAS_ICC ? icc_cache_rdata : icc_nocache_rdata;
assign icc_rdata_valid     =  HAS_ICC ? icc_cache_rdata_valid : icc_nocache_rdata_valid;
assign icc_rdata_err       =  HAS_ICC ? icc_cache_rdata_err : icc_nocache_rdata_err;
assign icc_rd_in_sysbus    =  HAS_ICC ? icc_cache_rd_in_sysbus : icc_nocache_rd_in_sysbus;
assign icc_axi_null        =  HAS_ICC ? icc_cache_axi_null : icc_nocache_axi_null;
assign icc_cc_vaddr        =  HAS_ICC ? icc_cache_cc_vaddr : 32'd0;
assign icc_cc_dbgm         =  HAS_ICC ? icc_cache_cc_dbgm : 1'b0;
assign icc_dbgm_req_valid  =  HAS_ICC ? icc_cache_dbgm_req_valid :
                                icc_nocache_dbgm_req_valid;
assign icc_dbgm_req_addr   =  HAS_ICC ? icc_cache_dbgm_req_addr :
                                icc_nocache_dbgm_req_addr;
assign icc_dbgm_req_size   =  HAS_ICC ? icc_cache_dbgm_req_size :
                                icc_nocache_dbgm_req_size;
assign icc_axi_arvalid     =  HAS_ICC ? icc_cache_axi_arvalid : icc_nocache_axi_arvalid;
assign icc_axi_arburst     =  HAS_ICC ? icc_cache_axi_arburst : icc_nocache_axi_arburst;
assign icc_axi_arcache     =  HAS_ICC ? icc_cache_axi_arcache : icc_nocache_axi_arcache;
assign icc_axi_arsize      =  HAS_ICC ? icc_cache_axi_arsize : icc_nocache_axi_arsize;
assign icc_axi_araddr      =  HAS_ICC ? icc_cache_axi_araddr : icc_nocache_axi_araddr;

assign icc_cps_req_ok        =  HAS_ICC ? icc_cache_cps_req_ok : 1'b0;
assign icc_cps_data_ok       =  HAS_ICC ? icc_cache_cps_data_ok : 1'b0;
assign icc_cps_rdata         =  HAS_ICC ? icc_cache_cps_rdata : 32'd0;
assign icc_all_fatal         =  HAS_ICC ? icc_cache_all_fatal : 1'b0;
assign icc_rd_fatal          =  HAS_ICC ? icc_cache_rd_fatal : 1'b0;
assign icc_ccop_fatal        =  HAS_ICC ? icc_cache_ccop_fatal : 1'b0;
assign icc_rf_impr_fatal     =  HAS_ICC ? icc_cache_rf_impr_fatal : 1'b0;
assign icc_fatal_intagv      =  HAS_ICC ? icc_cache_fatal_intagv : 1'b0;
assign icc_fatal_indata      =  HAS_ICC ? icc_cache_fatal_indata : 8'd0;
assign icc_fatal_indx10      =  HAS_ICC ?
                                  {{(10-`OPEN132_ICC_INDEX_BITS){1'b0}},icc_cache_fatal_indx} : 10'd0;
assign icc_fatal_way5        =  HAS_ICC ?
                                  {{(5-`OPEN132_ICC_SET_ASSOC){1'b0}},icc_cache_fatal_way} : 5'd0;
assign icc_ram_init_cmplt    =  HAS_ICC ? icc_cache_ram_init_cmplt : 1'b1;
assign icc_all_ecc_err_add1  =  HAS_ICC ? icc_cache_all_ecc_err_add1 : 1'b0;
assign icc_refill_add1       =  HAS_ICC ? icc_cache_refill_add1 : 1'b0;

assign icc_ram_tagv_req_bus  =  HAS_ICC ?
                                  icc_cache_ram_tagv_req_bus[`OPEN132_ICC_RAM_TAGV_REQ_BUS_WD-1:0] :
                                  {`OPEN132_ICC_RAM_TAGV_REQ_BUS_WD{1'b0}};
assign icc_ram_data_req_bus  =  HAS_ICC ?
                                  icc_cache_ram_data_req_bus[`OPEN132_ICC_RAM_DATA_REQ_BUS_WD-1:0] :
                                  {`OPEN132_ICC_RAM_DATA_REQ_BUS_WD{1'b0}};
assign icc_ram_lrud_req_bus  =  HAS_ICC ?
                                  icc_cache_ram_lrud_req_bus[`OPEN132_ICC_RAM_LRUD_REQ_BUS_WD-1:0] :
                                  {`OPEN132_ICC_RAM_LRUD_REQ_BUS_WD{1'b0}};
// End Icache

//------------------------------------------------------------//
//                    Address Translation
//------------------------------------------------------------//
//------------------------------------------------------------//
//                            Dcc
//------------------------------------------------------------//
mmu_vaddr_to_paddr x_mmu_vaddr_to_paddr_0 (
    .lisa_da    (lisa_da_v2p0   ),  // da-mode
    .lisa_segpa (lisa_segpa_v2p0),
    .vaddr_h3   (vaddr_h3_v2p0  ),
    .paddr_h3   (paddr_h3_v2p0  )
);
assign dcc_paddr[28:0]  =  dcc_vaddr[28:0];
assign dcc_mmu_vaddr    =  HAS_DCC ? dcc_cc_vaddr : dcc_vaddr   ;
assign dcc_mmu_read     =  HAS_DCC ? dcc_cc_read  : 1'b0        ;
assign dcc_mmu_dbgm     =  HAS_DCC ? dcc_cc_dbgm  : dcc_req2dbgm;
// End Dcc

//------------------------------------------------------------//
//                            Icc
//------------------------------------------------------------//
mmu_vaddr_to_paddr x_mmu_vaddr_to_paddr_1 (
    .lisa_da    (lisa_da_v2p1   ),  // da-mode
    .lisa_segpa (lisa_segpa_v2p1),
    .vaddr_h3   (vaddr_h3_v2p1  ),
    .paddr_h3   (paddr_h3_v2p1  )
);
assign icc_paddr[28:0]  =  icc_vaddr[28:0];
assign icc_mmu_vaddr    =  HAS_ICC ? icc_cc_vaddr : icc_vaddr   ;
assign icc_mmu_dbgm     =  HAS_ICC ? icc_cc_dbgm  : icc_req2dbgm;
// End Icc

// if no cache, only need cached
mmu_vaddr_attribute #(
    .MPU_NUM    (MPU_NUM_VATTR   ),
    .CFGSEG_NUM (CFGSEG_NUM_VATTR)
) x_mmu_vaddr_attribute (
    .lisa_da         (lisa_da_vattr        ),
    .lisa_dacf       (lisa_dacf_vattr      ),
    .lisa_dacm       (lisa_dacm_vattr      ),
    .mpu_valid       (mpu_valid_vattr      ),
    .mpu_base        (mpu_base_vattr       ),
    .mpu_mask        (mpu_mask_vattr       ),
    .mpu_calg        (mpu_calg_vattr       ),
    .cfgseg_calg     (cfgseg_calg_vattr    ),

    // dcc
    .dcc_vaddr       (dcc_vaddr_vattr      ),
    .dcc_read        (dcc_read_vattr       ),
    .dcc_dbgm        (dcc_dbgm_vattr       ),
    .dcc_addr_sob    (dcc_addr_sob_vattr   ),
    .dcc_addr_cached (dcc_addr_cached_vattr),
    .dcc_addr_alloc  (dcc_addr_alloc_vattr ),

    // icc
    .icc_vaddr       (icc_vaddr_vattr      ),
    .icc_dbgm        (icc_dbgm_vattr       ),
    .icc_addr_cached (icc_addr_cached_vattr)
);

always @ ( posedge clk )
begin
    dcc_uc_req_ok_r <= memld_st_req_s_ready &&( !dcc_cached || HAS_DCC );
    icc_c_req_ok_r  <= fetch_req_s_ready    &&(  icc_cached || HAS_ICC );
end
// if no DCC , dcc_cached is in dcc_uc_req_ok_r
// if HAS_DCC, need && dcc_cached.
assign dcc_uncached_sbus  =  dcc_uc_req_ok_r && ( !dcc_cached || !HAS_DCC);
assign icc_cached_sbus    =  icc_c_req_ok_r  && (  icc_cached || !HAS_ICC);
// End Address Translation

//------------------------------------------------------------//
//                        sysbus< >AXI
//------------------------------------------------------------//
generate
    case (AXI_DATA_WD)
        32: begin: gen_axi_burst_32
            assign axi_burst_len = 4'b0111;
        end
        64: begin: gen_axi_burst_64
            assign axi_burst_len = 4'b0011;
        end
        128: begin: gen_axi_burst_128
            assign axi_burst_len = 4'b0001;
        end
    endcase
endgenerate
// write:from dcache
// aw
assign sys_awid         =  {1'b0,dcc_axi_aw_wid};
assign sys_awaddr       =  dcc_axi_awaddr;
assign sys_awlen        =  axi_burst_len&{4{dcc_axi_awburst}};
assign sys_awsize       =  dcc_axi_awsize;
assign sys_awburst      =  2'b01;  // normal sequential memory
assign sys_awlock       =  {1'b0,dcc_axi_awexc};  // normal access or exclusive
assign sys_awcache      =  {4{dcc_axi_awcache}};  // nonbufferable, all cache-access is burst
assign sys_awprot[0]    =  1'b0;  // normal access
assign sys_awprot[1]    =  1'b1;  // non-secure access
assign sys_awprot[2]    =  1'b0;  // 0:data access,1:fetch
assign sys_awvalid      =  dcc_axi_awvalid;
assign dcc_axi_awready  =  sys_awready;
// w
assign sys_wid         =  {1'b0,dcc_axi_aw_wid};
assign sys_wstrb       =  dcc_axi_wstrb;
assign sys_wdata       =  dcc_axi_wdata;
assign sys_wlast       =  dcc_axi_wlast;
assign sys_wvalid      =  dcc_axi_wvalid;
assign dcc_axi_wready  =  sys_wready;
// b
assign dcc_axi_bvalid  =  sys_bvalid;
assign dcc_axi_bid     =  sys_bid[2:0];
assign sys_bready      =  1'b1;

assign sys_ar_ok  =  sys_arvalid&&sys_arready;
assign sys_r_ok   =  sys_rvalid &&sys_rready;

assign ft_go_ok  =  icc_axi_arvalid&&ft_allowin;
assign ld_go_ok  =  dcc_axi_arvalid&&ld_allowin;
assign nx_go_ok  =  ft_go_ok || ld_go_ok;

assign ft_rlast_ok  =  sys_rlast&&sys_r_ok && sys_rid[0];
assign ld_rlast_ok  =  sys_rlast&&sys_r_ok &&!sys_rid[0];
always @ ( posedge clk )
begin
    // ar
    ar_valid_r <= reset       ? 1'b0                :
    sys_ar_ok   ? 1'b0                :
    nx_go_ok    ? 1'b1                : ar_valid_r;
    ar_fetch_r <= reset       ? 1'b0                :
    nx_go_ok    ? !ld_go_ok           : ar_fetch_r;
    ar_burst_r <= reset       ? 1'b0                :
    ld_go_ok    ? dcc_axi_arburst     :
    ft_go_ok    ? icc_axi_arburst     : ar_burst_r;
    ar_exc_r   <= reset       ? 1'b0                :
    ld_go_ok    ? dcc_axi_arexc       :
    ft_go_ok    ? 1'b0                : ar_exc_r;
    ar_cache_r <= reset       ? 1'b0                :
    ld_go_ok    ? dcc_axi_arcache     :
    ft_go_ok    ? icc_axi_arcache     : ar_cache_r;
    ar_size_r  <= reset       ? 3'd0 :
    ld_go_ok    ? dcc_axi_arsize      :
    ft_go_ok    ? icc_axi_arsize      : ar_size_r ;
    ar_addr_r  <= reset       ? 32'd0 :
    ld_go_ok    ? dcc_axi_araddr      :
    ft_go_ok    ? icc_axi_araddr      : ar_addr_r ;
    // r
    rvalid_r   <= reset       ? 1'b0                :
    sys_r_ok    ? 1'b1                : 1'b0      ;
    rid0_r  <= sys_r_ok    ? sys_rid[0]          : rid0_r    ;
    rdata_r <= sys_r_ok    ? sys_rdata           : rdata_r   ;
    rresp_r <= sys_r_ok    ? sys_rresp           : rresp_r   ;
    // wait flag
    ft_wait    <= reset       ? 1'b0                :
    ft_rlast_ok ? 1'b0                :
    ft_go_ok    ? 1'b1                : ft_wait   ;
    ld_wait    <= reset       ? 1'b0                :
    ld_rlast_ok ? 1'b0                :
    ld_go_ok    ? 1'b1                : ld_wait   ;
end
assign ar_buf_empty  =  !ar_valid_r;

// if ld_allowin and ld_req, ft can't allowin
// if dcc_axi_arvalid==1, must dcc_ar_stall_icc==1.
assign ld_allowin  =  ar_buf_empty && !ld_wait;
assign ft_allowin  =  ar_buf_empty && !ft_wait && (!dcc_ar_stall_icc||ld_wait);

// to fetch/load request
assign dcc_axi_arready  =  ld_allowin;
assign icc_axi_arready  =  ft_allowin;
assign dcc_axi_rvalid   =  rvalid_r && !rid0_r;  // id==0
assign dcc_axi_rdata    =  rdata_r;
assign dcc_axi_rresp    =  rresp_r;
assign icc_axi_rvalid   =  rvalid_r &&  rid0_r;  // id==1
assign icc_axi_rdata    =  rdata_r;
assign icc_axi_rresp    =  rresp_r;

// sys read
assign sys_arid       =  {3'b000,ar_fetch_r};
assign sys_araddr     =  ar_addr_r;
assign sys_arlen      =  axi_burst_len & {4{ar_burst_r}};
assign sys_arsize     =  ar_size_r;
assign sys_arburst    =  ctrl_nowrap ? 2'b01  // 10: wrap ; 01:incr
                         : {ar_burst_r,~ar_burst_r};  // 10: wrap ; 01:incr
assign sys_arlock     =  {1'b0      , ar_exc_r  };  // 00: normal ; 01:exclusive
assign sys_arcache    =  {4{ar_cache_r}};  // nonbufferable, all cache access is burst
assign sys_arprot[0]  =  1'b0;  // normal access
assign sys_arprot[1]  =  1'b1;  // non-secure access
assign sys_arprot[2]  =  ar_fetch_r;  // 0:data access,1:fetch
assign sys_arvalid    =  ar_valid_r;
assign sys_rready     =  1'b1;
// End sysbus< >AXI

//------------------------------------------------------------//
//                       >cpu Interface
//------------------------------------------------------------//
assign ft_in_sysbus  =  icc_rd_in_sysbus;
assign ld_in_sysbus  =  dcc_rd_in_sysbus;
// assign st_in_sysbus     = dcc_wr_in_sysbus;
`ifdef CONFIG_MMU
assign sysbus_mem_null  =  dcc_axi_null && !lsu_mmu_req_vld
                            && !ptw_dc_req_vld && !ptw_dc_busy;
assign sysbus_ft_null   =  icc_axi_null && !ifu_mmu_req_vld;
`else
assign sysbus_mem_null  =  dcc_axi_null;
assign sysbus_ft_null   =  icc_axi_null;
`endif
// End >cpu Interface

//------------------------------------------------------------//
//                       OPEN132 CACHE
//------------------------------------------------------------//
// ram init for cache
assign ram_init_cmplt  =  dcc_ram_init_cmplt && icc_ram_init_cmplt;

//------------------------------------------------------------//
//                      Cache Isync Pref
//------------------------------------------------------------//
assign mem_cps_req_ready   =  mem_cps_req && ( !mem_cc_op_i||icc_cps_req_ok)
                              &&(!(mem_cc_op_d||mem_cc_pref)||dcc_cps_req_ok);
assign mem_cps_data_ready  =  mem_cc_op_i&&icc_cps_data_ok || mem_cc_op_d&&dcc_cps_data_ok;
assign mem_cps_data_rdata  =  mem_cc_op_i ? icc_cps_rdata : dcc_cps_rdata;
// End Cache Isync Pref

//------------------------------------------------------------//
//                 Cache Isync Pref To DCache
//------------------------------------------------------------//
// cc_op[5:0]
//   [5]       [4]       [3]      [2]     [1]   [0]
// StoreTag  LoadTag  Writeback  invalid  Index  hit
assign dcc_cc_op        =  {6{mem_cps_req_dcc}}&mem_cc_op;
assign dcc_cc_sttag     =  mem_sttag_data;
assign dcc_cc_pref      =  mem_cc_pref&&mem_cps_req;
assign dcc_cc_lock      =  mem_cc_lock&&mem_cps_req_dcc;
assign dcc_cc_op_stall  =  mem_cc_op_i&&icc_stall_cps;
// End Cache Isync Pref To DCache

//------------------------------------------------------------//
//                 Cache Isync Pref To ICache
//------------------------------------------------------------//
// cc_op[5:0]
//   [5]       [4]       [3]      [2]     [1]   [0]
// StoreTag  LoadTag  Writeback  invalid  Index  hit
assign icc_cc_op        =  {6{mem_cps_req_icc}}&{mem_cc_op[5:4],1'b0, mem_cc_op[2:0]};
assign icc_cc_sttag     =  mem_sttag_data;
assign icc_cc_fill      =  mem_cc_fill&&mem_cps_req;
assign icc_cc_lock      =  mem_cc_lock&&mem_cps_req_icc;
assign icc_cc_op_stall  =  mem_cc_op_d&&dcc_stall_cps;
// End Cache Isync Pref To ICache

//------------------------------------------------------------//
//                    ECC Fatal Exception
//------------------------------------------------------------//

assign dcc_fatal                =  dcc_all_fatal;
assign icc_fatal                =  !dcc_all_fatal && icc_all_fatal;
assign fatal_rd                 =  dcc_all_fatal ? dcc_rd_fatal : icc_rd_fatal;
assign impr_fatal_wr            =  dcc_all_fatal ? dcc_wr_fatal : 1'b0;
assign impr_fatal_ccop          =  dcc_all_fatal ? dcc_ccop_fatal    : icc_ccop_fatal;
assign impr_fatal_rf            =  dcc_all_fatal ? dcc_rf_impr_fatal : icc_rf_impr_fatal;
assign fatal_intagv             =  dcc_all_fatal ? dcc_fatal_intagv  : icc_fatal_intagv;
assign fatal_indata             =  dcc_all_fatal ? dcc_fatal_indata  : icc_fatal_indata;
assign fatal_way                =  dcc_all_fatal ? dcc_fatal_way5  [3:0]:
                                     icc_fatal_way5  [3:0];
assign fatal_indx               =  dcc_all_fatal ? dcc_fatal_indx10[8:0]:
                                     icc_fatal_indx10[8:0];
assign fatal_dirtywb            =  dcc_all_fatal ? dcc_fatal_dirtywb           : 1'b0 ;
assign fatal_dirty_tag          =  dcc_all_fatal ? dcc_fatal_dirty_tag23[21:0] : 22'd0;
assign cache_ecc_fatal_events   =  {dcc_fatal       ,  // 1, total 52
                                     icc_fatal       ,  // 1,
                                     fatal_rd        ,  // 1, total 50
                                     impr_fatal_wr   ,  // 1
                                     impr_fatal_ccop ,  // 1
                                     impr_fatal_rf   ,  // 1
                                     1'b0            ,  // 1
                                     fatal_intagv    ,  // 1, total 45
                                     fatal_indata    ,  // 8
                                     fatal_way       ,  // 4, total 36
                                     fatal_indx      ,  // 9, total 32
                                     fatal_dirtywb   ,  // 1
                                     fatal_dirty_tag  // 22
                                   };
generate
    if (HAS_DCC && (DCC_ECC_BITS >= 7) || HAS_ICC && (ICC_ECC_BITS >= 7)) begin: gen_ecc_fatal_bus_has_ecc
        assign cache_lsu_ecc_fatal_bus = cache_ecc_fatal_events;
    end else begin: gen_ecc_fatal_bus_no_ecc
        assign cache_lsu_ecc_fatal_bus = {`OPEN132_CACHE_LSU_ECC_FATAL_BUS_WIDTH{1'b0}};
    end
endgenerate
// End ECC Fatal Exception
generate
    if (HAS_DCC == 0 && HAS_ICC == 0) begin: gen_no_cache
        assign nc_resetn_in_d2 = resetn_in_d2;
    end
endgenerate
// End OPEN132 CACHE

//------------------------------------------------------------//
//                           LJTAG
//------------------------------------------------------------//
`ifdef OPEN132_HAS_LJTAG
//------------------------------------------------------------//
//                Input And Output Connections
//------------------------------------------------------------//
assign biu_jtag_debug_req_bus  =  {dbmemcbus_valid,
                                    dbmemcbus_write,
                                    dbmemcbus_size,
                                    dbmemcbus_paddr,
                                    dbmemcbus_data };

assign {dbmemrbus_valid,dbmemrbus_data}  =  jtag_biu_debug_resp_bus;
// End Input And Output Connections

//------------------------------------------------------------//
//                     Fetch Mem Req Dbgm
//------------------------------------------------------------//
assign icc_req2dbgm  =  fetch_dbgm    && !mem_cps_req_icc;  // must not cache_op
assign dcc_req2dbgm  =  memld_st_dbgm && !req_mald&& !mem_cps_req_dcc;  // cached load/op won't go dbgm

always @ ( posedge clk )
begin
    if(reset) begin
        dbgm_sel_icc <= 1'b0;
    end
    else if(icc_dbgm_resp_valid) begin
        dbgm_sel_icc <= 1'b0;
    end
    else if(icc_dbgm_req_valid && !dcc_dbgm_req_valid) begin
        dbgm_sel_icc <= 1'b1;
    end
end

assign dbgm_req_valid  =  !dbgm_sel_icc ? dcc_dbgm_req_valid : icc_dbgm_req_valid;
assign dbgm_req_addr   =  !dbgm_sel_icc ? dcc_dbgm_req_addr : icc_dbgm_req_addr;
assign dbgm_req_wr     =  !dbgm_sel_icc&&dcc_dbgm_req_wr;
assign dbgm_req_size   =  !dbgm_sel_icc ? dcc_dbgm_req_size : icc_dbgm_req_size;
assign dbgm_req_wdata  =  dcc_dbgm_req_wdata;
// dbmem req
assign dbmemcbus_valid  =  dbgm_req_valid && !dbgm_req_addr[20];
assign dbmemcbus_write  =  dbgm_req_wr;
assign dbmemcbus_size   =  dbgm_req_size;
assign dbmemcbus_paddr  =  dbgm_req_addr[19:0];
assign dbmemcbus_data   =  dbgm_req_wdata;
// End Fetch Mem Req Dbgm

//------------------------------------------------------------//
//             Fetch Mem Req Dbgm Ready And Data
//------------------------------------------------------------//
assign dbgmrbus_valid  =  dbmemcbus_valid&&dbmemrbus_valid;
assign dbgmrbus_data   =  dbmemrbus_data;

assign dcc_dbgm_resp_valid  =  dbgmrbus_valid&&!dbgm_sel_icc;
assign dcc_dbgm_resp_data   =  dbgmrbus_data;
assign icc_dbgm_resp_valid  =  dbgmrbus_valid&& dbgm_sel_icc;
assign icc_dbgm_resp_data   =  dbgmrbus_data;
// End Fetch Mem Req Dbgm Ready And Data
`else
assign icc_req2dbgm         =  1'b0;
assign dcc_req2dbgm         =  1'b0;
assign dcc_dbgm_resp_valid  =  1'd0;
assign dcc_dbgm_resp_data   =  32'd0;
assign icc_dbgm_resp_valid  =  1'd0;
assign icc_dbgm_resp_data   =  32'd0;
`endif
// End LJTAG

//------------------------------------------------------------//
//                           Assert
//------------------------------------------------------------//
`ifdef OPEN132_ASSERT
assert property (
    @(posedge clk)
    (mem_cps_req_dcc || dcc_cc_pref)
    |-> !dcc_req_rd_wr
)
else begin $display("Assert Error!!!"); #2 $finish; end

assert property (
    @(posedge clk)
    (de_load_req && (memld_st_req&&!memld_st_write)) |-> 1'b0
    )
else begin $display("de_load_req Assert Error!!!"); #2 $finish; end

assert property (
    @(posedge clk)
    (req_memld_st&&memld_st_exc) |-> !req_mald
        )
else begin $display("axi sysbus ll/sc Assert Error!!!"); #2 $finish; end
`endif
// End Assert

endmodule
`endif
