# OpenLACores 前端分支预测 TAGE 化改造报告

## 1. 背景与目标

OpenLA132 原有前端分支预测基于：

- 16 项 BTB（`ifu_bpu.v`）+ 每项 3-bit 饱和计数器做方向判断；
- 8 项 jalr 目标表（jr 表）；
- 2 项压缩高位 tag + 14-bit 目标，仅记录“已跳转”的直接分支。

本次将其**基础方向预测**替换为 **TAGE（TAgged GEometric history length）** 方向预测器，保留 BTB 提供目标地址与命中判定。目标是在不改动体系结构语义的前提下，用几何历史长度的 tagged 表提升条件分支方向预测精度。

## 2. 改造范围

| 文件 | 变更 |
| --- | --- |
| `design/sys/openla132/ifu/ifu_tage.v` | **新增**：紧凑 TAGE 方向预测器 |
| `design/sys/openla132/ifu/ifu_bpu.v` | 方向改由 TAGE 决定；新增 `br_cond` 标记；例化 `ifu_tage` |
| `design/sys/openla132/ifu/ifu_stage.v` | 透传 `pred_ghr` / `pred_cond` / `pred_tage_taken`，`pred_taken` 采用 TAGE 方向 |
| `design/sys/openla132/dsu/dsu_stage.v` | 寄存器化 GHR 快照；产生 `de_pred_taken/de_pred_cond/de_pred_ghr`；扩展更新总线 |
| `design/sys/openla132/include/openla132_define.h` | 新增 `OPEN132_TAGE_GHR_WD`；加宽三条预测/更新总线 |
| `design/filelist/openla132.f` | 登记 `ifu_tage.v` |

## 3. TAGE 微架构

### 3.1 结构

- **Base（双模）表**：512 项 × 2-bit 计数器，索引 `pc[10:2]`，作为默认预测。
- **3 个 tagged 表**：每表 128 项，8-bit tag + 3-bit 计数器 + 1-bit useful + 1-bit valid，几何历史长度 **4 / 8 / 12**。
- **GHR**：12-bit 提交制全局历史寄存器（`OPEN132_TAGE_GHR_WD`）。

### 3.2 索引与 tag

```
idx_t = pc[8:2] ^ (h & mask_t)[6:0] ^ {0, (h & mask_t)[11:7]}
tag_t = pc[16:9] ^ {1'b0,(h & mask_t)[6:0]} ^ {7'b0,(h & mask_t)[11]}
```

### 3.3 预测选择

最长历史且 tag 命中的表作为 provider；无命中则用 base：

```
pred_taken = m2 ? ctr2[2] : m1 ? ctr1[2] : m0 ? ctr0[2] : base[1]
```

### 3.4 更新策略

- provider 计数器向实际方向饱和调整；无命中则更新 base。
- 预测正确：置 provider 的 useful 位。
- 预测错误：在历史更长的表中分配（优先满足 TAGE 分配规则，`u==0` 可替换）。
- 条件分支解析后 GHR 左移并入实际方向。

### 3.5 历史快照的一致性

预测读取以“当前提交制 GHR”为索引；更新时若直接用解析时刻的 GHR，会因在飞分支导致索引不一致、训练到错误表项。因此：

- 预测时把所用 GHR 作为 `pred_ghr` 输出；
- 经 IFU → IDU 随指令流水（在 IDU 打拍）回送到 BPU；
- 更新时使用该**取指时刻快照** `de_pred_ghr`，保证读/写命中同一表项。

因采用**提交制 GHR（仅在解析时更新）**，无需投机状态回滚，逻辑显著简化且功能安全。

## 4. 接口/总线变更

| 总线 | 原宽 | 新宽 | 新增字段 |
| --- | --- | --- | --- |
| `OPEN132_PRED2FT_BUS_WD` | 43 | 57 | `cond`、`tage_taken`、`ghr[11:0]` |
| `OPEN132_FT2DE_PRED_BUS_WD` | 11 | 25 | `cond`、`tage_taken`、`ghr[11:0]` |
| `OPEN132_DE2PRED_BUS_WD` | 76 | 90 | `taken`、`cond`、`ghr[11:0]` |

拼接顺序（MSB→LSB）：

```
pred:      valid,brlo_hit,jrlo_hit,jr,npc,pos,cnt,cond,tage_taken,ghr
ft2de:     valid,brlo_hit,jrlo_hit,jrra,pos,cnt,cond,tage_taken,ghr
update:    pc,npc,jrra,jrlo_hit,brlo_hit,pos,cnt,correct,valid,taken,cond,ghr
```

## 5. 关键设计决策：方向与 BTB 计数器解耦

最初的实现直接把 TAGE 结果写入 `pred_cnt`。这是**错误**的：DSU 用 `pred_cnt` 派生 `de_pred_cnt` 回写 BTB 计数器（`btb_read_hit` 要求 `|cnt[2:1]`）。

循环分支每轮退出被 TAGE 正确预测为 not-taken 时，会把 BTB 表项计数直接清零，导致：

1. 表项“消失”，下一轮无法命中 → 无法使用 TAGE；
2. 每轮循环多一次误预测，性能反而不如改造前。

**修正**：`pred_cnt` 保持为 legacy BTB/jr 计数器（用于表项寿命与替换），TAGE 决策另走 `pred_cond` / `pred_tage_taken` 两位，最终方向：

```
pred_taken_dir = pred_cond ? pred_tage_taken : |pred_cnt[2:1]
```

仅 **条件直接分支**（`br_cond=1`）使用 TAGE；无条件直接跳转与 jalr 仍走 legacy（始终 taken / jr 计数器）。

## 6. 训练通路（DSU 侧）

```
de_pred_taken = jbr_taken                                  // 实际方向
de_pred_cond  = !de_ex && valid && de2nxt_inst_cmplt
                && !jbr_stall && lisa_br                    // 仅条件分支
de_pred_ghr   = pred_ghr                                    // 取指时刻 GHR 快照
```

TAGE 仅对 `lisa_br` 训练与推进 GHR；无条件跳转 / jalr 不进入 TAGE。

## 7. 正确性论证

分支预测是**投机**的，误预测由 DSU/RTU 冲刷纠正。本次改动：

- `pred_valid` / `pred_npc` / `pred_jr` / BTB 命中逻辑完全不变，重定向目标只可能来自真实 BTB 表项；
- TAGE 仅改变“taken/not-taken”判断，不产生新的目标地址；
- 即使 TAGE 哈希/计数器/分配存在缺陷，也只影响**预测精度**，不影响**体系结构正确性**。

## 8. 验证

已做：

- `iverilog -g2012 -Wall` 全核 elaborate 通过，无新增告警（仅原有 cache RAM 数组越界告警）；
- `ifu_tage` 动态冒烟测试：同一循环分支训练后预测收敛为 taken；5000 次随机激励无 X、无越界、无崩溃。

未做（**必须补做**）：

- **Verilator + loong-emu DiffTest**：确认提交 PC/寄存器状态与参考模型一致（本环境无 Verilator）；
- **Vivado 综合**：确认时序与资源（TAGE 表容量、组合索引路径）；
- CoreMark / Dhrystone 前后对比，量化 TAGE 相对原 BTB 的 IPC 增益。

## 9. 后续可选改进

- 提高 GHR 宽度与历史长度（如 8/16/32），增大表容量；
- 增加循环预测器 / ITTAGE（间接跳转）与 TAGE-SC 统计纠错；
- 采用投机式 GHR + 冲刷修复以提升历史精度；
- 将 TAGE 表放到 SRAM / 寄存器阵列并按目标频率重新划分流水级。

## 10. 结论

在保持 OpenLA132 流水线与体系结构语义不变的前提下，前端基础方向预测已替换为可综合的 TAGE 实现，并通过与 BTB 计数器解耦避免了表项寿命被破坏的问题。功能安全依赖既有的误预测纠正通路；**上线前需以 DiffTest 与综合结果为准完成最终验证**。
