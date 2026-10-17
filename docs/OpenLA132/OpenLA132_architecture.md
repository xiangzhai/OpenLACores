# LA132S 核架构与特性说明

本文介绍本仓库中 LA132 核的 RTL 组织、可见接口和配置边界，面向需要集成、仿真、
调试或修改 RTL 的工程人员。

本文的实现依据是
[design/sys/openla132](../design/sys/openla132)、RTL 文件列表
[design/filelist/openla132.f](../design/filelist/openla132.f) 和公开顶层
[openla132_ip_top.v](../design/sys/openla132/top/openla132_ip_top.v)。

本文描述的是当前工程中的实现结构，不替代 LoongArch ISA 手册，也不承诺固定的主频、
PPA 或特定 FPGA 板卡的实现结果。

## 1. 核心定位

OpenLA132 处理器核是一款实现LoongArch32基本指令集兼容的32位高性能、低功耗RISC处理器核。

该处理器核面向低端微控制器（MCU）和终端类应用，采用完全可综合设计，可以方便地在不同工艺上实现，有助于设计开发人员专注于SoC芯片的设计研发，加速产品实现。

其主要结构特征为:

-  静态调度、单发射、四级流水线
-  采用指令访问接口和数据访问接口分离的哈佛结构
-  流水线内部包含普通定点运算、定点乘除法运算两条独立的执行流水线
-  定点乘除法部件可配置为速度优化乘除法、速度面积均衡乘除法、面积优化乘除法。
-  采用简洁的固定地址映射机制和基于段的地址空间访问控制

OpenLA132 处理器核 IP 结构如图所示。

![OpenLA132 处理器核 IP 结构图](OpenLA132_assets/OpenLA132_arch.png "OpenLA132_Arch")

其顶层对外接口主要总线接口通过地址空间区分为I-BUS、D-BUS和SYS-BUS三条总线。I-BUS、D-BUS封装为SRAM接口，支持可变延迟访问。对接的slave分别称为ISRAM、DSRAM，RAM的具体规格由客户自行决定。SYS-BUS封装为AXI3接口，数据宽度可选为32/64/128位。OPENLA132处理器核IP可选Cache部件，指令、数据分离式，可选ECC校验。ICache和DCache均是写回+写分配，可定制为：1/2/4路组相连，每路1/2/4/8/16KB，Cache行大小32字节。在支持Cache时，只有SYS-BUS访问才会经过Cache。

## 2. RTL 组成

| 目录/文件 | 主要职责 |
| --- | --- |
| [top/](../design/sys/openla132/top) | 核心实例化、复位、时钟门控封装、IP 顶层与 cache tie-off。 |
| [ifu/](../design/sys/openla132/ifu) | 取指状态机、PC 更新、分支预测接口、指令请求与响应。 |
| [dsu/](../design/sys/openla132/dsu) | 指令译码、寄存器堆与向后级发射控制。 |
| [exu/](../design/sys/openla132/exu) | 整数执行及乘除法单元选择、快速/串行乘除法实现。 |
| [lsu/](../design/sys/openla132/lsu) | Load/Store、地址属性、异常相关处理、store queue、cache 控制和写缓冲。 |
| [mmu/](../design/sys/openla132/mmu) | TLB、页表遍历、地址转换、MPU、访问属性与 DCache 仲裁。 |
| [csr/](../design/sys/openla132/csr) | CPUCFG、CSR 寄存器及相关停顿检查。 |
| [rtu/](../design/sys/openla132/rtu) | 退休/提交、重定向、异常与中断协作。 |
| [biu/](../design/sys/openla132/biu) | CPU 内部请求到 AXI 系统总线、cache 和非缓存通路的仲裁与适配。 |
| [ljtag/](../design/sys/openla132/ljtag) | JTAG/cJTAG、调试模块、内部硬件断点相关逻辑。 |
| [ram_arrays/](../design/sys/openla132/ram_arrays) | I/D Cache data/tag/LRU RAM 封装。 |
| [libwrapper/](../design/sys/openla132/libwrapper) | 通用 SRAM、时钟门控和复用器等技术边界模型。 |
| [include/](../design/sys/openla132/include) | 配置宏、内部总线宽度和 cache RAM 宽度定义。 |

顶层 [openla132_core.v](../design/sys/openla132/top/openla132_core.v) 实例化 IFU、IDU、MDU 选择、
LSU、RTU、AXI 接口、分支预测器和调试模块；[openla132_ip_top.v](../design/sys/openla132/top/openla132_ip_top.v)
将该核心作为可集成的 IP 边界导出。

## 3. 前端、执行与退休

### 3.1 取指与分支预测

IFU 维护 PC、取指状态和取指请求。它向 cache/MMU 路径发送取指虚拟地址，并从返回数据
形成指令及预测信息。分支预测逻辑位于 [ifu_bpu.v](../design/sys/openla132/ifu/ifu_bpu.v)，
其预测结果经 IFU 传递给后级；跳转、异常或退休侧重定向会改变后续取指地址。

### 3.2 译码与整数执行

IDU 负责将取回的 LoongArch 指令转换为内部控制总线，并提供通用寄存器读写路径。
EXU 包含算术逻辑、掩码/移位相关组合逻辑，以及多种乘除法实现。
[exu_mdu_sel.v](../design/sys/openla132/exu/exu_mdu_sel.v) 在快速、串行 smart 和串行
area 等 MDU 实现之间选择；乘除法的具体延迟、资源与时序取决于所选实现和综合结果。

### 3.3 访存、异常与退休

LSU 负责 load/store 地址、数据访问、转发、访存异常、cache 操作和 CSR/控制相关的
停顿条件。RTU 对完成的指令进行提交，并与异常、中断和流水冲刷协作。Verilator 顶层将
RTU 的提交信号导出为 commit 探针，供提交日志和 DiffTest 使用；该探针是验证接口，
不是公开 SoC 总线。

## 4. 地址转换与 Cache 配置

### 4.1 CONFIG_MMU 的作用

CONFIG_MMU 是 RTL 的编译期配置宏，而不是 openla132_config.h 中默认定义的宏。它必须由
仿真或综合文件列表、命令行宏定义或上层工程一致地提供。该宏影响 MMU、CPUCFG、cache
参数、内部总线宽度和技术单元的条件编译。

| 配置 | CPUCFG 可见能力 | MMU/Cache RTL 行为 |
| --- | --- | --- |
| 未定义 CONFIG_MMU | CPUCFG 报告无分页 MMU、无硬件页表遍历；la132_core 的默认 I/D Cache 参数为关闭。 | MMU 相关逻辑不作为有效地址转换路径使用，cache 走 no-cache/tie-off 配置。 |
| 定义 CONFIG_MMU | CPUCFG 报告分页 MMU、硬件页表遍历和稳定计时器能力。 | openla132_ip_top 将 ICache 与 DCache 设为启用；二者均为 1 路、每路 1 KiB、32 字节 cache line。 |

Cache 的容量、相联度和 ECC 参数在核心参数与配置宏中定义。当前公开 IP 顶层在 MMU 配置下
使用上述固定参数；若直接实例化 la132_core，则应由集成方同时传入 HAS_ICC、HAS_DCC、
相联度、每路容量和 ECC 参数，且保证 RAM 封装与这些参数一致。

分页支持的基本页大小为 4 KiB、16 KiB 和 64 KiB，并由 `PRCFG2` 上报。硬件页表遍历器
从 `PWCL`（CSR 0x1c）和 `PWCH`（CSR 0x1d）读取 `PTBASE/PTWIDTH` 以及各级目录的
`DIRnBASE/DIRnWIDTH`，因此遍历层数和每级索引宽度是运行时可配置的；`PTBASE` 同时作为
叶级页大小（架构 PS 编码：12/14/16）。L1TLB 每项保存自己的 PS，查表、物理地址拼接和
`INVTLB` 地址匹配都按该项的页大小处理。当前不支持目录项 `H=1` 的大页。

### 4.2 复位与 Cache 初始化

核心复位由 hard_resetn 经同步后生成。Cache/写缓冲初始化完成信号参与复位释放；
因此集成方需要确保 cache RAM 与相关初始化逻辑均被正确包含。若配置、RAM 模型或时钟
门控模型不完整，现象可能是复位已释放但前端不发起取指。

当前 [libwrapper/](../design/sys/openla132/libwrapper) 中的时钟与 SRAM 技术边界
已提供可仿真、可综合实现。Verilator 对 `CONFIG_MMU=0` 使用
`scripts/formal/openla132_tech_models.v` 中的确定性时钟模型，两种 MMU 配置使用独立构建目录。

## 5. IP 顶层接口

openla132_ip_top 是 FPGA 与 Verilator 直接实例化的结构化顶层。它不包含 DDR 控制器、
UART、PLIC/中断控制器、片上 RAM 或时钟发生器；这些设备由 SoC/Block Design 或仿真
testbench 在核外提供。

### 5.1 时钟、复位和控制

| 信号 | 方向 | 说明 |
| --- | --- | --- |
| clk | 输入 | 核心主时钟。 |
| hard_resetn | 输入 | 低有效硬复位输入。 |
| boot_pc[31:0] | 输入 | 复位后 IFU 使用的启动 PC。 |
| cpunum[9:0] | 输入 | CPU 编号，供 CSR/软件可见的处理器标识使用。 |
| ext_int[7:0] | 输入 | 外部中断输入。 |
| sleeping | 输出 | 核心声明可安全切断时钟/电源的休眠指示。 |
| test_mode | 输入 | 测试/时钟门控相关控制。 |

### 5.2 系统 AXI 主接口

系统 AXI 接口具有 32 位地址、32 位读写数据和 4 位事务 ID；支持 AR/R、AW/W/B 五个
独立通道，暴露 burst 长度、size、burst、lock、cache、prot 和响应字段。核是 AXI
master，SoC 必须作为 slave 正确响应读写事务及 burst 的 RLAST/B 通道。

该接口定义了访问方式，并不定义外设地址。地址映射属于 SoC 层：例如本仓库的
Verilator 与 FPGA 平台把 16550 UART 映射到 0x1fe00000，但这不是 LA132 核本身
硬编码的地址。

### 5.3 SRAM 和地址窗口接口

IP 顶层另导出 inst_sram 与 data_sram 接口，以及各四组 ibus/dbus 的
valid/base/mask 窗口配置。它们用于将特定指令/数据地址路由至集成方提供的 SRAM 或
特定总线窗口。若不使用这些端口，集成顶层应明确 tie-off，并保证 AXI 路径仍可获得
取指和数据访问响应。Verilator 的 `CONFIG_SRAM=0` 使用 AXI 路径，
`CONFIG_SRAM=1` 则把 CoreMark 地址窗口路由到 `inst_sram_*`/`data_sram_*`。

### 5.4 调试接口

顶层同时提供标准 JTAG 与 cJTAG 信号。配置文件默认启用 OPEN132_HAS_LJTAG，因此
JTAG 子模块会被纳入 RTL；实际调试器、引脚复用、时钟和复位时序由 SoC/FPGA 顶层负责。
GODSON_DEBUG 宏启用时会额外导出执行、寄存器和若干 CSR 观察信号。

## 6. ISA 与可见特性

下表仅列出可由当前 CPUCFG/RTL 直接确认的能力，不是完整指令清单。

| 项目 | 当前 RTL 结论 |
| --- | --- |
| 通用寄存器宽度 | 32 位；CPUCFG 的 GR32 位置位，GR64 不置位。 |
| 地址宽度 | CPUCFG 报告 VABITS=32、PABITS=32；顶层 AXI 地址为 32 位。 |
| 整数乘除 | 具有快速/串行 MDU RTL，可通过 MDU 选择逻辑切换实现。 |
| CSR/异常/中断 | 存在 CSR、异常入口、ERTN 和外部中断处理相关 RTL。 |
| CPUCFG | 实现 CPUCFG 0、1、2、3、6、10、11、12；MMU 配置时额外实现 4、5。 |
| LLSYNC | CPUCFG3 将 LLSYNC 能力位置位。 |
| 浮点 | CPUCFG2 报告无单精度、双精度和 FPU。 |
| 向量 | CPUCFG2 报告无 LSX 与 LASX。 |
| 分页 MMU/HPTW | 仅在 CONFIG_MMU 配置下报告并启用。 |
| I/D Cache | 可配置；公开 IP 顶层在 CONFIG_MMU 下启用 1 KiB 直映 ICache 与 DCache。 |

软件的 ISA 选项、Linux 配置和随机指令生成器必须与上述可见能力匹配。尤其不能因为
源代码目录中存在 MMU 或 cache 文件，就假定当前某个仿真/综合配置已经启用了它们。

## 7. 集成与验证建议

1. 使用 [design/filelist/openla132.f](../design/filelist/openla132.f) 作为直接 RTL 仿真的基础，
   并添加 include 目录作为 Verilog include 路径。
2. 明确记录 CONFIG_MMU、GODSON_DEBUG、SYNTHESIS 等宏；仿真与 FPGA 综合必须使用
   相同的功能配置。
3. 复位期间保持 boot_pc、AXI 返回信号和 SRAM 响应处于确定状态；等待 cache 初始化
   完成后再判断取指是否异常。
4. AXI slave 必须支持核发出的 burst 与多个事务 ID；简化模型至少要正确处理 AR/R 与
   AW/W/B 握手、RID/BID 和 RLAST。
5. 先用无差分 Verilator 检查复位、取指、UART 和 GOOD TRAP，再构建 loong-emu
   reference 启用 DiffTest。详见 [Verilator 说明](../verify/verilator/README.md)。
6. FPGA 集成时使用 impl/ 的板卡配置和 Block Design；UART、DDR、JTAG 和 loader
   地址映射属于该层，详见 [FPGA 实现说明](../impl/README.md)。
7. 若用户既有开发流程是在RTL代码中插入BIST逻辑，需要自行修改 openla132/lib_wrapper/目录下 spram 模块相关 verilog 文件，
   完成各个SRAM BIST控制逻辑的连接

## 8. 相关文件速查

| 需求 | 首选文件 |
| --- | --- |
| 查看 IP 端口 | [openla132_ip_top.v](../design/sys/openla132/top/openla132_ip_top.v) |
| 查看核心层次 | [openla132_core.v](../design/sys/openla132/top/openla132_core.v) |
| 查看默认宏与内部总线定义 | [openla132_config.h](../design/sys/openla132/include/openla132_config.h)、[openla132_define.h](../design/sys/openla132/include/openla132_define.h) |
| 查看 CPUCFG 报告内容 | [csr_cpucfg.v](../design/sys/openla132/csr/csr_cpucfg.v) |
| 查看 AXI/cache 仲裁 | [biu_axi_if.v](../design/sys/openla132/biu/biu_axi_if.v)、[biu_axi_sysbus.v](../design/sys/openla132/biu/biu_axi_sysbus.v) |
| 查看 MMU/HPTW | [mmu_core.v](../design/sys/openla132/mmu/mmu_core.v)、[mmu_ptw.v](../design/sys/openla132/mmu/mmu_ptw.v) |
| 查看仿真顶层与模型 | [verify/verilator](../verify/verilator) |
| 查看 FPGA SoC 集成 | [impl](../impl) |
