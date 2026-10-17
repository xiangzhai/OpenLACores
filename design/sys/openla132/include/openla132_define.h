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

`include "openla132_config.h"

`ifndef OPEN132_DEFINE_H
`define OPEN132_DEFINE_H
//-------- bus length definition --------
//the width of buses
`define OPEN132_FETCH2DE_BUS_WD  101
`define OPEN132_FETCH2IFC_BUS_WD 34
`define OPEN132_IFC2FETCH_BUS_WD 37
`define OPEN132_DE2MEM_BUS_WD    117
`define OPEN132_DEC2MDU_BUS_WD   71
`define OPEN132_MEM2DE_BUS_WD    74
`define OPEN132_MEM2WB_BUS_WD    80
`define OPEN132_MEM2TOP_BUS_WD    6
`define OPEN132_CSR2DE_BUS_WD    24
`define OPEN132_CSR2FETCH_BUS_WD 10
`define OPEN132_WB2DE_BUS_WD     71
`define OPEN132_MEM2IFC_BUS_WD   149
`define OPEN132_IFC2MEM_BUS_WD   74
`define OPEN132_LISA_DECODE_BUS_WD 91
`define OPEN132_LISA_FPU_DECODE_BUS_WD 42
`define OPEN132_PRED2FT_BUS_WD   43
`define OPEN132_FT2DE_PRED_BUS_WD 11
`define OPEN132_DE2PRED_BUS_WD   76

// Refactored hierarchy bus names. The CONFIG_MMU=0 values remain aliases of
// the original CPU configuration macros above.
`ifdef CONFIG_MMU
`define OPEN132_IFU_IDU_INST_BUS_WIDTH  107
`else
`define OPEN132_IFU_IDU_INST_BUS_WIDTH  `OPEN132_FETCH2DE_BUS_WD
`endif
`define OPEN132_IFU_CACHE_REQ_BUS_WIDTH `OPEN132_FETCH2IFC_BUS_WD
`ifdef CONFIG_MMU
`define OPEN132_CACHE_IFU_RESP_BUS_WIDTH 44
`define OPEN132_IDU_LSU_INST_BUS_WIDTH    118
`else
`define OPEN132_CACHE_IFU_RESP_BUS_WIDTH `OPEN132_IFC2FETCH_BUS_WD
`define OPEN132_IDU_LSU_INST_BUS_WIDTH   `OPEN132_DE2MEM_BUS_WD
`endif
`define OPEN132_IDU_EXU_MDU_BUS_WIDTH       `OPEN132_DEC2MDU_BUS_WD
`define OPEN132_LSU_IDU_FORWARD_BUS_WIDTH   `OPEN132_MEM2DE_BUS_WD
`define OPEN132_LSU_RTU_INST_BUS_WIDTH      `OPEN132_MEM2WB_BUS_WD
`define OPEN132_LSU_CORE_CTRL_BUS_WIDTH     `OPEN132_MEM2TOP_BUS_WD
`define OPEN132_CSR_IDU_CTRL_BUS_WIDTH      `OPEN132_CSR2DE_BUS_WD
`define OPEN132_CSR_IFU_CTRL_BUS_WIDTH      `OPEN132_CSR2FETCH_BUS_WD
`define OPEN132_RTU_IDU_FORWARD_BUS_WIDTH   `OPEN132_WB2DE_BUS_WD
`define OPEN132_LSU_CACHE_REQ_BUS_WIDTH     `OPEN132_MEM2IFC_BUS_WD
`ifdef CONFIG_MMU
`define OPEN132_CACHE_LSU_RESP_BUS_WIDTH   82
`else
`define OPEN132_CACHE_LSU_RESP_BUS_WIDTH   `OPEN132_IFC2MEM_BUS_WD
`endif
`define OPEN132_IDU_DECODE_BUS_WIDTH        `OPEN132_LISA_DECODE_BUS_WD
`define OPEN132_IDU_FPU_DECODE_BUS_WIDTH    `OPEN132_LISA_FPU_DECODE_BUS_WD
`define OPEN132_BPU_IFU_PRED_BUS_WIDTH      `OPEN132_PRED2FT_BUS_WD
`define OPEN132_IFU_IDU_PRED_BUS_WIDTH      `OPEN132_FT2DE_PRED_BUS_WD
`define OPEN132_IDU_BPU_UPDATE_BUS_WIDTH    `OPEN132_DE2PRED_BUS_WD

//---{MMU}begin

`define OPEN132_CFGSEG_NUM     8
//---{MMU}end
`define OPEN132_CSR2IFC_BUS_WD (4*`OPEN132_CFGSEG_NUM + 28 + 45*4 + 3)
`define OPEN132_CSR_CACHE_CTRL_BUS_WIDTH (4*`OPEN132_CFGSEG_NUM + 28 + 45*4 + 3)
`ifdef CONFIG_MMU
`define OPEN132_CSR_MMU_CTRL_BUS_WIDTH   259
`endif

//---{low power}begin
`ifdef OPEN132_LOW_POWER
    `define OPEN132_NOT_LOWP 1'b0
`else
    `define OPEN132_NOT_LOWP 1'b1
`endif
//---{low power}end

//---{cache}begin
    //-----DCACHE
    `define OPEN132_DCC_SET_ASSOC   DCC_SET_ASSOC
    `define OPEN132_DCC_WAYSIZE     DCC_WAYSIZE
    `define OPEN132_DCC_ECC_BITS    DCC_ECC_BITS
    //DCC
    `define OPEN132_DCC_INDEX_BITS ($clog2(`OPEN132_DCC_WAYSIZE) - 5)
    `define OPEN132_DCC_TAG_BITS   (32 - `OPEN132_DCC_INDEX_BITS - 5)
    //for 2/4 ways, has 1 bit lock in TGAV, for 1 ways, no lock bit
    `define OPEN132_DCC_TAGV_BITS  (`OPEN132_DCC_TAG_BITS + 1 + (`OPEN132_DCC_SET_ASSOC+2)/4)
    `define OPEN132_DCC_LRU_BITS   ((`OPEN132_DCC_SET_ASSOC-1)*`OPEN132_DCC_SET_ASSOC/2)
    //for ecc
    `define OPEN132_DCC_ECC_WAY       ((`OPEN132_DCC_ECC_BITS<7) ? 1 : 2**(`OPEN132_DCC_ECC_BITS-7))
    `define OPEN132_DCC_ECC_SET       (`OPEN132_DCC_SET_ASSOC/`OPEN132_DCC_ECC_WAY) //if noe ecc, ==SET_ASSOC
    `define OPEN132_DCC_ECC_BANK_BITS (`OPEN132_DCC_ECC_SET*`OPEN132_DCC_ECC_BITS)

    `define OPEN132_DCC_TAGV_EN_WD      `OPEN132_DCC_SET_ASSOC
    `define OPEN132_DCC_TAGV_WEN_WD     `OPEN132_DCC_ECC_SET
    `define OPEN132_DCC_BANK_EN_WD      `OPEN132_DCC_SET_ASSOC
    `define OPEN132_DCC_BANK_WEN_WD     ((`OPEN132_DCC_ECC_BITS<7) ? `OPEN132_DCC_ECC_SET*4 : `OPEN132_DCC_ECC_SET)
    `define OPEN132_DCC_RAM_TAGV_WD_ECC ((`OPEN132_DCC_ECC_BITS<7) ? `OPEN132_DCC_TAGV_BITS*`OPEN132_DCC_SET_ASSOC : `OPEN132_DCC_TAGV_BITS*`OPEN132_DCC_SET_ASSOC + `OPEN132_DCC_ECC_BANK_BITS)
    `define OPEN132_DCC_RAM_BANK_WD_ECC ((`OPEN132_DCC_ECC_BITS<7) ? 32*`OPEN132_DCC_SET_ASSOC : 32*`OPEN132_DCC_SET_ASSOC + `OPEN132_DCC_ECC_BANK_BITS)

    `define OPEN132_DCC_RAM_TAGV_RESP_BUS_WD (HAS_DCC ? `OPEN132_DCC_RAM_TAGV_WD_ECC \
                                                    : 1 )
    `define OPEN132_DCC_RAM_TAGV_REQ_BUS_WD  (HAS_DCC ? (`OPEN132_DCC_TAGV_EN_WD + `OPEN132_DCC_TAGV_WEN_WD + `OPEN132_DCC_INDEX_BITS + `OPEN132_DCC_RAM_TAGV_RESP_BUS_WD) \
                                                    : 1 )
    `define OPEN132_DCC_RAM_DATA_RESP_BUS_WD (HAS_DCC ? (8*(`OPEN132_DCC_RAM_BANK_WD_ECC)) \
                                                    : 1 )
    `define OPEN132_DCC_RAM_DATA_REQ_BUS_WD  (HAS_DCC ? (8*(`OPEN132_DCC_BANK_EN_WD+`OPEN132_DCC_BANK_WEN_WD+`OPEN132_DCC_INDEX_BITS+`OPEN132_DCC_RAM_BANK_WD_ECC)) \
                                                    : 1 )
    `define OPEN132_DCC_RAM_LRUD_RESP_BUS_WD (HAS_DCC ? (`OPEN132_DCC_LRU_BITS+`OPEN132_DCC_SET_ASSOC) \
                                                    : 1 )
    `define OPEN132_DCC_RAM_LRUD_REQ_BUS_WD  (HAS_DCC ? (1+`OPEN132_DCC_RAM_LRUD_RESP_BUS_WD*2+`OPEN132_DCC_INDEX_BITS) \
                                                    : 1 )

    //-----ICACHE
    `define OPEN132_ICC_SET_ASSOC   ICC_SET_ASSOC
    `define OPEN132_ICC_WAYSIZE     ICC_WAYSIZE
    `define OPEN132_ICC_ECC_BITS    ICC_ECC_BITS
    //ICC
    `define OPEN132_ICC_INDEX_BITS  ($clog2(`OPEN132_ICC_WAYSIZE) - 5)
    `define OPEN132_ICC_TAG_BITS    (32 - `OPEN132_ICC_INDEX_BITS- 5)
    //for 2/4 ways, has 1 bit lock in TGAV, for 1 ways, no lock bit
    `define OPEN132_ICC_TAGV_BITS   (`OPEN132_ICC_TAG_BITS + 1 + (`OPEN132_ICC_SET_ASSOC+2)/4)
    `define OPEN132_ICC_LRU_BITS    ((`OPEN132_ICC_SET_ASSOC-1)*`OPEN132_ICC_SET_ASSOC/2)
    //for ecc
    `define OPEN132_ICC_ECC_WAY       ((`OPEN132_ICC_ECC_BITS<7) ? 1 : 2**(`OPEN132_ICC_ECC_BITS-7))
    `define OPEN132_ICC_ECC_SET       (`OPEN132_ICC_SET_ASSOC/`OPEN132_ICC_ECC_WAY) //if noe ecc, ==SET_ASSOC
    `define OPEN132_ICC_ECC_BANK_BITS (`OPEN132_ICC_ECC_SET*`OPEN132_ICC_ECC_BITS)

    `define OPEN132_ICC_TAGV_EN_WD      `OPEN132_ICC_SET_ASSOC
    `define OPEN132_ICC_TAGV_WEN_WD     `OPEN132_ICC_ECC_SET
    `define OPEN132_ICC_BANK_EN_WD      `OPEN132_ICC_SET_ASSOC
    `define OPEN132_ICC_BANK_WEN_WD     ((`OPEN132_ICC_ECC_BITS<7) ? `OPEN132_ICC_ECC_SET*4 : `OPEN132_ICC_ECC_SET)
    `define OPEN132_ICC_RAM_TAGV_WD_ECC ((`OPEN132_ICC_ECC_BITS<7) ? `OPEN132_ICC_TAGV_BITS*`OPEN132_ICC_SET_ASSOC : `OPEN132_ICC_TAGV_BITS*`OPEN132_ICC_SET_ASSOC + `OPEN132_ICC_ECC_BANK_BITS)
    `define OPEN132_ICC_RAM_BANK_WD_ECC ((`OPEN132_ICC_ECC_BITS<7) ? 32*`OPEN132_ICC_SET_ASSOC : 32*`OPEN132_ICC_SET_ASSOC + `OPEN132_ICC_ECC_BANK_BITS)


    `define OPEN132_ICC_RAM_TAGV_RESP_BUS_WD (HAS_ICC ? `OPEN132_ICC_RAM_TAGV_WD_ECC \
                                                    : 1 )
    `define OPEN132_ICC_RAM_TAGV_REQ_BUS_WD  (HAS_ICC ? (`OPEN132_ICC_TAGV_EN_WD + `OPEN132_ICC_TAGV_WEN_WD +`OPEN132_ICC_INDEX_BITS+`OPEN132_ICC_RAM_TAGV_RESP_BUS_WD) \
                                                    : 1 )
    `define OPEN132_ICC_RAM_DATA_RESP_BUS_WD (HAS_ICC ? (8*(`OPEN132_ICC_RAM_BANK_WD_ECC)) \
                                                    : 1 )
    `define OPEN132_ICC_RAM_DATA_REQ_BUS_WD  (HAS_ICC ? (8*(`OPEN132_ICC_BANK_EN_WD+`OPEN132_ICC_BANK_WEN_WD+`OPEN132_ICC_INDEX_BITS+`OPEN132_ICC_RAM_BANK_WD_ECC)) \
                                                    : 1 )
    `define OPEN132_ICC_RAM_LRUD_RESP_BUS_WD (HAS_ICC ? (`OPEN132_ICC_LRU_BITS+`OPEN132_ICC_SET_ASSOC) \
                                                    : 1 )
    `define OPEN132_ICC_RAM_LRUD_REQ_BUS_WD  (HAS_ICC ? (1+`OPEN132_ICC_RAM_LRUD_RESP_BUS_WD*2+`OPEN132_ICC_INDEX_BITS) \
                                                    : 1 )
//---{cache}end

//application-specific
`ifndef OPEN132_APP_SPEC
    `define OPEN132_DE2MEM_APP_BUS 1
    `define OPEN132_MEM2WB_APP_BUS 1
    `define OPEN132_WB2MDU_APP_BUS 1
    `define OPEN132_IDU_LSU_APP_BUS_WIDTH 1
    `define OPEN132_LSU_RTU_APP_BUS_WIDTH 1
    `define OPEN132_RTU_EXU_APP_BUS_WIDTH 1
`endif

//fpu
`define OPEN132_DEC2FPU_BUS_WD   146
`define OPEN132_FPU2DEC_BUS_WD   127
`define OPEN132_FPU2MEM_BUS_WD   35
`define OPEN132_MEM2FPU_BUS_WD   36
`define OPEN132_WB2FPU_BUS_WD    4
`define OPEN132_IDU_FPU_INST_BUS_WIDTH     `OPEN132_DEC2FPU_BUS_WD
`define OPEN132_FPU_IDU_RESULT_BUS_WIDTH   `OPEN132_FPU2DEC_BUS_WD
`define OPEN132_FPU_LSU_BUS_WIDTH          `OPEN132_FPU2MEM_BUS_WD
`define OPEN132_LSU_FPU_BUS_WIDTH          `OPEN132_MEM2FPU_BUS_WD
`define OPEN132_RTU_FPU_BUS_WIDTH          `OPEN132_WB2FPU_BUS_WD

//ecc, needn't change these even if no ecc.
`define OPEN132_ECC2MEM_FATAL_BUS  52
`define OPEN132_CACHE_LSU_ECC_FATAL_BUS_WIDTH `OPEN132_ECC2MEM_FATAL_BUS

//performance events bus
`define OPEN132_DE2PERF_BUS_WD     5
`define OPEN132_CC2PERF_BUS_WD     6
`define OPEN132_IFC2PERF_BUS_WD    (`OPEN132_CC2PERF_BUS_WD)
`define OPEN132_IDU_CSR_PERF_BUS_WIDTH      `OPEN132_DE2PERF_BUS_WD
`define OPEN132_CACHE_PERF_EVENT_BUS_WIDTH  `OPEN132_CC2PERF_BUS_WD
`define OPEN132_CACHE_CSR_PERF_BUS_WIDTH    `OPEN132_IFC2PERF_BUS_WD


//---------------------{generate define}begin-------------------//
//GEN_COMPRESS: [ResWidth*OrWidth] --OR--> [ResWidth]
//input :wire [ResWidth*OrWidth -1:0] Src
//output:wire [ResWidth         -1:0] Res
`define GEN_COMPRESS_OR(ResWidth,OrWidth,Src,Res) \
    generate for(i=0; i<ResWidth;i=i+1) \
    begin \
        assign Res[i] = |Src[(i+1)*OrWidth -1: i*OrWidth]; \
    end \
    endgenerate

//GEN_EXTEND: [SrcWidth] --EXTEND--> [SrcWidth*ExtWidth]
//input :wire [SrcWidth          -1:0] Src
//output:wire [SrcWidth*ExtWidth -1:0] Res
`define GEN_EXTEND(SrcWidth,ExtWidth,Src,Res) \
    generate for(i=0; i<SrcWidth;i=i+1) \
    begin \
        assign Res[(i+1)*ExtWidth -1: i*ExtWidth] = {ExtWidth{Src[i]}}; \
    end \
    endgenerate

//GEN_2D_TO_1D: [Depth][Width] --> [Depth*Width]
//input :wire [Width       -1:0] Src [Depth -1:0]
//output:wire [Depth*Width -1:0] Res
`define GEN_2D_TO_1D(Depth,Width,Src,Res) \
    generate for(i=0; i<Depth;i=i+1) \
    begin \
        assign Res[Width*(i+1) -1: Width*i] = Src[i]; \
    end \
    endgenerate

//GEN_1D_TO_2D: [Depth*Width]  --> [Depth][Width]
//input :wire [Depth*Width -1:0] Src
//output:wire [Width       -1:0] Res [Depth -1:0]
`define GEN_1D_TO_2D(Depth,Width,Src,Res) \
    generate for(i=0; i<Depth;i=i+1) \
    begin \
        assign Res[i] = Src[Width*(i+1) -1: Width*i]; \
    end \
    endgenerate

//GEN_2D_TO_3D: [Depth1][Depth2*Width]  --> [Depth1][Depth2][Width]
//input :wire [Depth2*Width -1:0] Src [Depth1 -1:0]
//output:wire [Width        -1:0] Res [Depth1 -1:0][Depth2 -1:0]
`define GEN_2D_TO_3D(Depth1,Depth2,Width,Src,Res) \
    generate for(i=0; i<Depth1;i=i+1) \
    begin \
        for (j=0; j<Depth2;j=j+1) \
        begin \
            assign Res[i][j] = Src[i][Width*(j+1) -1: Width*j]; \
        end \
    end \
    endgenerate

//GEN_3D_TO_2D: [Depth1][Depth2][Width]  --> [Depth1][Depth2*Width]
//input :wire [Width        -1:0] Src [Depth1 -1:0][Depth2 -1:0]
//output:wire [Depth2*Width -1:0] Res [Depth1 -1:0]
`define GEN_3D_TO_2D(Depth1,Depth2,Width,Src,Res) \
    generate for(i=0; i<Depth1;i=i+1) \
    begin \
        for (j=0; j<Depth2;j=j+1) \
        begin \
            assign Res[i][Width*(j+1) -1: Width*j] = Src[i][j]; \
        end \
    end \
    endgenerate

//GEN_2D_T: [Depth][Width]  --> [Width][Depth]
//input :wire [Width -1:0] Src [Depth -1:0]
//output:wire [Depth -1:0] Res [Width -1:0]
`define GEN_2D_T(Depth,Width,Src,Res) \
    generate for(i=0; i<Depth;i=i+1) \
    begin \
        for(j=0; j<Width; j=j+1) \
        begin \
            assign Res[j][i] = Src[i][j]; \
        end \
    end \
    endgenerate

//GEN_2D_SEL_1D: [Depth][Width] X [Depth]--> [Width]
//input :wire [Width -1:0] Src [Depth -1:0]
//       wire [Depth -1:0] Sel
//output:wire [Width -1:0] Res
`define GEN_2D_SEL_1D(Depth,Width,Src,Src_T,Sel,Res) \
    wire [Depth -1:0] Src_T[Width-1 :0]; \
    `GEN_2D_T(Depth,Width,Src,Src_T) \
    generate for(i=0; i<Width;i=i+1) \
    begin \
        assign Res[i] = | (Src_T[i] & Sel); \
    end \
    endgenerate

//GEN_3D_T: [Depth1][Depth2][Width]  --> [Depth1][Width][Depth2]
//input :wire [Width  -1:0] Src [Depth1 -1:0][Depth2 -1:0]
//output:wire [Depth2 -1:0] Res [Depth1 -1:0][Width  -1:0]
`define GEN_3D_T(Depth1,Depth2,Width,Src,Res) \
    generate for(i=0; i<Depth1;i=i+1) \
    begin \
        for(j=0; j<Depth2;j=j+1) \
        begin \
            for(k=0; k<Width; k=k+1) \
            begin \
                assign Res[i][k][j] = Src[i][j][k]; \
            end \
        end \
    end \
    endgenerate

//GEN_3D_SEL_2D: [Depth1][Dep2th][Width] X [Depth2]--> [Depth1][Width]
//input :wire [Width  -1:0] Src [Depth1 -1:0] [Depth2 -1:0]
//       wire [Depth2 -1:0] Sel
//output:wire [Width  -1:0] Res [Depth1 -1:0]
`define GEN_3D_SEL_2D(Depth1,Depth2,Width,Src,Src_T,Sel,Res) \
    wire [Depth2-1:0] Src_T[Depth1-1:0][Width-1 :0]; \
    `GEN_3D_T(Depth1,Depth2,Width,Src,Src_T) \
    generate for(i=0; i<Depth1;i=i+1) \
    begin \
        for(j=0; j<Width;j=j+1) \
        begin \
            assign Res[i][j] = | (Src_T[i][j] & Sel); \
        end \
    end \
    endgenerate

//GEN_ECC_COMPRESS_X: [SET_ASSOC][9] --> [ECC_SET][9]
//input :wire [8 :0] Src [SET_ASSOC -1:0]
//output:wire [8 :0] Res [ECC_SET   -1:0]
`define GEN_ECC_COMPRESS_X(SET_ASSOC,ECC_SET,ECC_WAY,Src,Src_T,Res) \
    wire [SET_ASSOC -1:0] Src_T[8:0]; \
    `GEN_2D_T(SET_ASSOC, 9, Src, Src_T) \
    generate for(i=0; i<ECC_SET; i=i+1) \
    begin \
        for(j=0; j<9; j=j+1) \
        begin \
            assign Res[i][j] = ^Src_T[j][i*ECC_WAY +: ECC_WAY]; \
        end \
    end \
    endgenerate

//GEN_ECC_COMPRESS_Y: [ECC_SET][9] --> [ECC_SET][ECC_BITS]
//input :wire [8          :0] Src [ECC_SET -1:0]
//output:wire [ECC_BITS -1:0] Res [ECC_SET -1:0]
`define GEN_ECC_COMPRESS_Y(ECC_SET,ECC_BITS,Src,Res) \
    generate for(i=0; i<ECC_SET; i=i+1) \
    begin \
        for(j=1; j<ECC_BITS; j=j+1) \
        begin \
            assign Res[i][j] = Src[i][j]; \
        end \
        if(ECC_BITS==7) \
        begin \
            assign Res[i][0] = Src[i][0] ^ Src[i][7] ^ Src[i][8];\
        end \
        else if(ECC_BITS==8) \
        begin \
            assign Res[i][0] = Src[i][0] ^ Src[i][8];\
        end \
        else if(ECC_BITS==9) \
        begin \
            assign Res[i][0] = Src[i][0];\
        end \
        else \
        begin \
            assign Res[i][0] = 1'b0;\
        end \
    end \
    endgenerate
//---------------------{generate define}-end---------------------//
`endif // OPEN132_DEFINE_H
