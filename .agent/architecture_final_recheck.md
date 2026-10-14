# architecture_final_recheck.md — 独立复核最终修订版的架构问题闭合情况（RR-A）

> 任务：t9「独立复核最终修订版的架构问题闭合情况」
> 执行：pro-architecture（高级架构专家）— attempt 1 / `88f15018-8596-4a5c-bb1f-a59334f52112`
> 日期：2026-10-14
> 复核对象：`.agent/target_architecture_final.md`（t8）相对我自己的草案审查 `.agent/architecture_draft_review.md`（t6）的 M1…M6 / S1…S8。
> 立场：只复核**架构**闭合（实例语义/预装可见性/注册 kind-deps/L1→L4/解析规则/DAG/shim），不复核科学语义（pro-science 的 RR-S 职责）。
> 方法：逐项对照最终版 §11/§12，并对我能静态验证的机械声明做了定向代码复核（未运行任何测试——**未运行的断言一律不作为通过证据**）。
> 本文件是本次 t9 的**唯一写入产物**；未改最终方案/代码/测试/配置，未创建子 Agent，未轮询成员。

---

## 0. 复核结论速览

| 结论 | 内容 |
|---|---|
| **总评** | M1…M6 全部在**方案层面闭合**，S1…S8 全部采纳；**未发现阻塞级遗留**。最终版相对草案的修订是实质且自洽的，可以作为 HA-0 的架构底稿。 |
| **三类状态** | ① 方案层面已闭合（本节 M/S 表）；② 待用户批准（HD-01…15）；③ 待实施后测试（V-I/V-F/V-R/V-S、B-* 基线、§4.1 oracle 复测、MIG-020 装载开销）。③一律**不算通过**。 |
| **非阻塞修订建议** | 4 条措辞/边界精确化（§6，含精确位置与修复要求），不阻断 HA-0，但应在对应 MIG 实施前并入。 |

**判定口径**：我复核的是「方案是否把问题闭合」，而不是「断言是否跑过」。因此 V-I1…V-I5 / V-F1…V-F3 / V-R / V-S / B-* 全部归入「待实施后测试」，作为 MIG-014 / GATE-2 / GATE-B 的验收项，而非当前结论。

---

## 1. 复核范围与静态验证

- 读取：`.agent/target_architecture_final.md`（660 行，全文）、`.agent/architecture_draft_review.md`（我自己的 t6 审查）。
- 定向复核源码（用于验证最终版的机械声明，未重扫全仓）：

| 最终版声明 | 我复核的代码 | 结论 |
|---|---|---|
| 策略 P「装载机制代码零改动」 | `src/modules.jl:347-353`（preloaded 分支）、`:361-363`（deps 递归装入载体） | ✅ 成立（见 §5.1） |
| eager_dep 的 L2→L3 临时边不成环 | `src/modules.jl:75-82`（MAVEN_SWEA deps=[:constants]、MAVEN_STATIC deps=[:constants,:MarsCommon]，均不依赖 MAVEN_load） | ✅ 成立（见 §5.2） |
| `src/MarsData.jl` 别名行插入位置（`using .MAVEN_plot` 之后、`include plotting.jl` 之前） | `src/MarsData.jl:22-75` | ✅ 顺序可行（见 §5.3） |
| `MAVEN_plot` 内已存在规范实例来源 | `MAVEN_plot.jl:4-5`（自包含 constants+MarsCommon） | ✅ 成立 |
| 现有测试不阻断策略 P（仅 `:constants` 有 `!isdefined` 隔离断言，无 `:MarsCommon` 同类断言） | `test/runtests.jl:349-353`、`:374-404`、`:406-418` | ✅ 兼容（见 §5.4） |
| MarsCommon 现外部依赖只有 `StaticArrays` | `common/MarsCommon.jl:1-4` | ✅ 成立（§3.1 点 5 正确） |

---

## 2. M1…M6 逐项复核（我的原必改项）

| 意见 | 处置落点 | 复核结论 | 剩余状态 |
|---|---|---|---|
| **M1** 实例一致性 + 预装闭包转发解析 | §3.1–3.3（I-1…I-5 + 策略 P + 否决分支）、§3.4、§3.7 | **已闭合（方案层）**。I-1…I-5 定义了「规范实例 / 嵌套副本」语义；策略 P 把 `MarsCommon`（选 E 时 +`MarsEnvironment`）改 `kind=:preloaded` 并绑定到 `MAVEN_plot` 内既有实例，消解双实例；`src/plotting.jl`/`MAVEN_plot` 的转发目标在包加载期即可见。我复核确认机制零改动（§5.1）。 | 待 HD-05 批准；V-I1…5/V-F1…3 待实施后测试 |
| **M2** L1→L4 违例 | §2.2 注 1（L1→L4 无例外）、§4.2、MIG-027 | **已闭合（方案层）**。`bowshock_zero` 从 FunctionCoordinate **删除且不转发**，旧裸名由 L6（head.jl shim / Pickup_ion）重新绑定到新权威；矩阵注明 L1→L4 无例外。两种 H-4 方案下均无 L1→L4 边（C：L5→L1；E：L5→L4，L4→L1）。 | 待 HD-04；MIG-027 + B-DUP 待实施 |
| **M3** MarsEnvironment deps 不完整 | §3.6 | **已闭合（方案层）**。deps 表补全：`MarsEnvironment [:constants, :MarsCommon]`（`get_bowshock_normal` 依赖 MarsCommon.solve_func）；门面、MAVEN_load、IGRF/SPO/TW_MINPA 全部给出。 | 无独立遗留 |
| **M4** compat 转发装载解析 | §3.4、§3.6 | **已闭合（方案层）**。限定 `nested`/`eager_dep` 两模式、禁惰性 `load_module`；`compat_edges` 增 `resolve`/`adds_deps`/`remove_by`；AST 规则补「引用未登记的模块即失败」；遗留直接 include 的错误语义（eager_dep 抛带指引 ErrorException）已定义。我复核 eager_dep 无环（§5.2）。 | 待 HD-15；V-F2/V-F3 待实施 |
| **M5** DAG 与波次不一致 | §7.1（单表加「波」列）、§7.2（DAG 重画） | **已闭合（方案层）**。041 归波 1，040/042 归波 4，043/052 归非关键轨，与 DAG 一致；文件锁补全（data_keys/附录 A/docs/test/validation 均已列）。 | 无独立遗留 |
| **M6** shim 隐式 using 冲突 | §7.4（SH-1…6、V-S1…5） | **已闭合（方案层）**。SH-1（零实现）、SH-2（唯一 `using MarsData`，不保留 20 个 using）、SH-3（@load + 守卫）、SH-4（旧名集合）、SH-5（不新增名）、SH-6（opt-in `head_legacy_usings.jl`）已把隐式依赖显式化并交 HD-03。 | 待 HD-03；V-S1…5 待实施 |

---

## 3. S1…S8 逐项复核（我的原建议项）

| 建议 | 最终版处置 | 采纳确认 |
|---|---|---|
| S1 子文件拆分 | MIG-011「由 `MarsCommon.jl` 统一 include」+ 自包含方装载冒烟 | ✅ 采纳 |
| S2 CATALOG `external_deps` | §8-2「装于全局/独立环境，永不进 `[deps]`」 | ✅ 采纳 |
| S3 逻辑层×物理位置两维 | §2.4 二维表 | ✅ 采纳 |
| S4 MIG-014 的 `note` | §5-3、MIG-014 | ✅ 采纳 |
| S5 孤儿 docstring oracle | §6.2 AST「孤儿 docstring 检测」 | ✅ 采纳 |
| S6 文件锁补全 | §7.3（data_keys/附录A/docs/test/validation） | ✅ 采纳 |
| S7 MIG-004 默认跳过 | MIG-004「环境变量开关，默认跳过」 | ✅ 采纳 |
| S8 MIG-000 编号/软依赖 | §6.1「编号仅标识，波 B 末尾冻结；HD-02 为软依赖」、§7.2 | ✅ 采纳 |

---

## 4. RR-A 八项专项复核（最终版 §12 要求）

| # | RR-A 项 | 复核结论 |
|---|---|---|
| 1 | §3 实例语义 I-1…I-5 与策略 P 是否真零改动 | ✅ 真零改动（§5.1：`modules.jl:347-353` preloaded 分支 + `:361-363` deps 递归 + `MarsData` 顶层一行 `const` 别名 + 注册表 `kind` 改动）；可观察变化（`MarsData.MarsCommon` 在 `using MarsData` 后即已定义、`parentmodule` 变为 `MAVEN_plot`）已正确登记为 HD-05。 |
| 2 | G-include 三场景正确性 + validate warning 影响 | ✅ 三场景（MAVEN_plot 内/载体/直接 include）均正确，前提是守卫位于**模块体内**使 `parentmodule(@__MODULE__)` = 父模块；warning 增量（validate 规则 (b)）已预判并归入既有 `@test_broken`，要求 MIG-014 记录精确增量。见 §6-2 措辞建议。 |
| 3 | nested/eager_dep + 遗留路径错误语义 | ✅ 闭合。遗留路径：nested 照常、eager_dep 抛 ErrorException；错误语义清晰。见 §6-3 一条边界限定建议。 |
| 4 | eager_dep 的 L2→L3 临时边成环/开销 | ✅ 不成环（§5.2）；开销是「MAVEN_load 装载闭包扩大为 +SWEA+STATIC」的有界、带 `remove_by` 期限的临时成本，需 MIG-020 实测记录，不构成方案层否决。 |
| 5 | HD-04 两方案依赖闭合 | ✅ C 与 E 都闭合（§4.2 表 + §2.2 矩阵 + §3.3 否决分支均自洽）；E 下 `MarsEnvironment` 预装 + G-include 复用 `MAVEN_plot.MarsCommon`，V-I5 断言 `===` 成立。 |
| 6 | DAG/文件锁/Pickup_ion 三次持锁 | ✅ Pickup_ion.jl 锁序 `010(第4行)→027(第4行)→030` 与波次/DAG（MIG-027→030）一致；三处持有互斥、按序转移。 |
| 7 | SH-1…SH-6 | ✅ 闭合且可 AST 断言（SH-1/SH-3/SH-5 机器可查；SH-2 单 using 可查）。见 §6-4 一条守卫目标措辞建议。 |
| 8 | PL-1 与 D-1 三分支 | ✅ A 成立（MarsCommon 迁入后仅需 StaticArrays/Statistics/LinearAlgebra/Dates，均在 HEAD 16 项内，§5.5）；B/C 的表述自洽。 |

---

## 5. 我的定向机械验证（补充证据）

### 5.1 策略 P 确实零改动装载机制

- `load_module` 的 `:preloaded` 分支（`modules.jl:347-353`）：`mod = getfield(@__MODULE__, sym)` 取 `MarsData.MarsCommon`（策略 P 已绑定的别名）；`into !== MarsData` 时 `Core.eval(into, :(const MarsCommon = $mod))` 把**同一实例**绑进载体/调用者。
- deps 递归（`modules.jl:361-363`）：`load_module(:MarsCommon; into=carrier)` 走上述 preloaded 分支，把规范实例以别名绑进载体。
- 结论：**只需** `src/MarsData.jl` 加一行 `const MarsCommon = MAVEN_plot.MarsCommon` + 注册表 `:MarsCommon.kind = :preloaded`，无需改 `_carrier`/`load_module`/`@load` 任何机制代码。最终版 §3.3 的「零改动」声明成立。

### 5.2 eager_dep 不成环

- `MAVEN_load` 拟加 `adds_deps=[:MAVEN_SWEA, :MAVEN_STATIC]`；`MAVEN_SWEA.deps=[:constants]`、`MAVEN_STATIC.deps=[:constants, :MarsCommon]`（`modules.jl:75-82`），两者均不依赖 `MAVEN_load`。`_topo_order` 的 SCC/环检测不会触发。成立。

### 5.3 `src/MarsData.jl` 别名行插入位置可行

- 现顺序：`paths`(:22) → `data_keys`(:25) → `MAVEN_plot`(:66) → `using .MAVEN_plot`(:67) → `plotting`(:70) → `modules`(:75)。最终版 §3.3 把别名行插在 :67 之后、:70 之前，`plotting.jl` 的 `MarsCommon.TimeFormat` 在 include 时即可解析。成立。

### 5.4 现有测试不阻断策略 P

- `runtests.jl:350` 只断言 `!isdefined(MarsData, :constants)`（constants 保持载体，不受影响）；全测试无「`MarsCommon` 非预装」断言；`runtests.jl:388-397` 的 MarsCommon `into`/allow 用例在 preloaded 分支下仍返回 `isa Module` 且 allow 逐名生效；`:406-418` 的 `parentmodule(m)===_carrier()` 只针对 MAVEN_load（不受影响）。成立。**但**这是静态推演，V-R1 才是最终证据（待实施后测试）。

### 5.5 PL-1 的依赖面

- `MarsCommon` 现只 `using StaticArrays`（`common/MarsCommon.jl:4`）。MIG-011 迁入 `Vandermonde/polynomial_fit/vector_angle`（LinearAlgebra）、统计函数（Statistics）、`TimeFormat`（Dates）后，需 StaticArrays+Statistics+LinearAlgebra+Dates 四项，**均在 HEAD 16 项内**（对照 01 §3.1 与 `Project.toml`）。PL-1 在 D-1 分支 A 下成立。

---

## 6. 仍需修订 / 待明确（**非阻塞**，含精确位置与修复要求）

| # | 位置 | 问题 | 修复要求（建议措辞） |
|---|---|---|---|
| R-1 | §3.4「eager_dep」表格行「文件顶层写守卫常量 `const _TARGET = …`」 | 「文件顶层」有歧义：若字面放到 `module MAVEN_load` 之前的文件顶层，`parentmodule(@__MODULE__)` = Main，守卫会误判。 | 改为「**模块体顶层**写守卫常量」，并注明「守卫必须位于 `module MAVEN_load` 体内，使 `parentmodule(@__MODULE__) === 载体`」。 |
| R-2 | §3.1 点 5「外部依赖只有 `using StaticArrays`」 vs §3.3 PL-1「StaticArrays/Statistics/LinearAlgebra/Dates」 | 两者时态不一致，易误读。 | §3.1 点 5 改为「**当前**只有 `using StaticArrays`；MIG-011 迁入后将增加 Statistics/LinearAlgebra/Dates（受 PL-1 约束）」。 |
| R-3 | §3.4「直接 include 的遗留路径：… nested 转发照常工作」 | 该保证只对「自包含/G-include」的 nested 成立；对「deps+父模块解析」的 nested（IGRF/SPO/TW_MINPA）直接 include 会 UndefVarError。 | 加一句限定：「nested 的**自包含 / G-include** 子模式在直接 include 下照常；依赖 deps 父模块解析的 nested 仅经 `load_module` 可用（IGRF/SPO/TW_MINPA 为注册模块，非脚本，可接受）。」 |
| R-4 | §7.4 SH-3「保留原 `head.jl:29` 守卫语义（只装尚未定义的名字）」 | 未明确守卫检查目标是 `Main` 还是 `@__MODULE__`（原文查 `Main`；V-S1 在空 Module 中 include 时 `@__MODULE__` 更正确）。 | 明确「守卫检查 `@__MODULE__` 中是否已定义目标名」，并让 V-S1 同时覆盖 Main 与空 Module 两种 include 目标。 |

> 这 4 条**不阻断 HA-0**；建议在 HA-0 批准后、对应 MIG（020/012/015/026）实施前并入最终版。

---

## 7. 状态分类汇总（不把未运行断言当作通过）

**待用户批准（HD，决定方案分支）**：HD-01（D-1）、HD-02（提交）、HD-03（shim/隐式 using）、HD-04（C/E）、HD-05（策略 P 采纳/否决）、HD-06（calculate_models 门面）、HD-07（cyclotron）、HD-08（sta_v_4d）、HD-09（color_mapping）、HD-10（:mass）、HD-11（C 类）、HD-12（范围）、HD-13（depwarn）、HD-14（物理迁移）、HD-15（eager_dep）。

**待实施后测试（断言未运行，仅作验收项）**：
- 实例/转发：V-I1…V-I5、V-F1…V-F3（MIG-014 / GATE-2）；
- 回归/注册表：V-R1、V-R2；
- shim：V-S1…V-S5；
- 行为基线：B-025/004/018/022/003、B-STA（EQ-STA-1/2、SE-STA-1/2、PRE-STA-1）、B-CYC、B-DUP、B-INST；
- §4.1 oracle 精确计数（MIG-000 复测）；
- eager_dep 装载开销（MIG-020 实测记录）。

以上全部**未运行**，不得视为已通过；它们是把「方案层闭合」变成「事实闭合」的后续步骤。

---

## 8. 合规声明

- **只写了一个文件**：`.agent/architecture_final_recheck.md`（本文件）。未改最终方案、代码、测试、配置、其他成员交付物。
- 未创建子 Agent、未轮询成员、未运行任何测试或写操作命令（所有 V-*/B-* 断言仅列为待办，未执行）。
- 分工边界：只复核架构闭合；科学语义闭合由 pro-science 的 RR-S 承担；对同一证据只给本专业结论。
- 本次定向复核仅读取 5 个源码文件（`src/modules.jl`、`src/MarsData.jl`、`MAVEN_plot.jl`、`common/MarsCommon.jl`、`test/runtests.jl`），未重扫全仓。
