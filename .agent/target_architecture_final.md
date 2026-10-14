# target_architecture_final.md — 人工架构审查包（目标架构 / Migration Plan / 功能添加规范 / 验证策略）

> 任务：t8 [final]「综合审定并交付人工架构审查包」
> 执行：chief-architect（总架构师）— attempt 1 / `702a2e79-d0ae-41f2-9b8c-bd0326b2a123`
> 模型：团队配置绑定 `anthropic/claude-opus-5.5`，本会话在该配置下运行，未静默换模型（provider 路由由队长在 DSH 层确认）。
> 日期：2026-10-14
> 输入：`new_plan.md`、`current_state_recovery.md`（t1）、`architecture_expert_analysis.md`（t3）、`science_expert_analysis.md`（t4）、`target_architecture_draft.md`（t5 草案）、`architecture_draft_review.md`（t6）、`science_draft_review.md`（t7）。另定向复核以下源码：`src/modules.jl:329-392`（load_module/preloaded 绑定）、`src/MarsData.jl`、`MAVEN_plot.jl:1-19,1442-1552`、`MAVEN_STATIC.jl:547-629`、`MAVEN_load.jl:1262-1302`、`test/runtests.jl:280-419`、`git show HEAD:Project.toml`，以及 §4 所需的同名函数定义计数。
> 状态：**待人工审查（HA-0）的最终方案。本文件不授权任何代码施工。**
> 修订记录：t11（chief-architect，attempt 2 / `cfa30293-dc82-4bb1-b41a-f64e23b5553f`）并入 t9（`architecture_final_recheck.md`）的 R-1…R-4，以及 t10（`science_final_recheck.md`）的 R-1、R-2。只做有限的文档澄清，未改动架构核心、HD 选项与建议、MIG 结构或范围。处置结果见 §11.1。
> 写入范围：只写了本文件。未改代码、测试、配置、`Project.toml`/`Manifest.toml`、草案或审查文件；未创建子 Agent，未轮询。

## 0. 使用说明与结论

### 0.1 本文件相对草案（t5）的变化

本文件取代 `target_architecture_draft.md`。草案中凡未在此改写的内容，以本文件的表述为准。两份审查共提出 22 项意见（M1–M6、S1–S8、F-1–F-8），全部逐项处置，见 §11。

**重要：t6、t7 审的是草案，不是本修订版。** §11 中每一项最初都写作「已修订·待独立复核」。修订点清单见 §12。

**复核结果（t9/t10）**：两名 Pro 已对本修订版做了**文档层面**的独立复核，结论为方案层闭合、可提交 HA-0，并提出 6 条非阻塞澄清，已由 t11 并入，见 §11.1。请注意三点：
- 「文档复核通过」**不等于**用户已批准；HD 项仍待裁决。
- 「文档复核通过」**不等于**实施测试已通过；所有 V-*/B-* 用例均尚未运行。
- t11 并入的澄清本身尚未经过第二轮复核，§11.1 中如实标注。

### 0.2 架构结论

| # | 结论 |
|---|---|
| 1 | **能力层**：保留七个能力层加 Extras 旁路，与草案一致。新增两条正交维度：逻辑层（能力归属）与物理装载位置（预装或载体）（§2.4，采纳 S3）。 |
| 2 | **实例语义（M1）**：引入「权威文件 / 规范实例 / 嵌套副本」三个概念和 I-1…I-5 五条规则（§3）。<br>推荐的预装策略 **P**：把 `MarsCommon`（以及选定独立方案时的 `MarsEnvironment`）的注册条目改为 `kind=:preloaded`，并绑定到 `MAVEN_plot` 内**已经存在**的那个实例。<br>效果：消除同名模块在预装闭包与载体中各有一份实例的现状；预装文件的转发目标在 `using MarsData` 时即可见。<br>代价与边界：装载机制代码零改动；不新增任何依赖；在 D-1 的三个分支下都成立。<br>该策略属人工决策（HD-05）。 |
| 3 | **转发解析（M4）**：只允许 `nested` 和 `eager_dep` 两种解析模式，禁止惰性 `load_module`（§3.4）。<br>每条兼容转发边都要在 `layers.toml` 登记 `resolve` 和 `adds_deps` 字段，并由 AST 校验。 |
| 4 | **M2**：任何方案下都不存在 L1→L4 边。`bowshock_zero` 从 FunctionCoordinate 中删除，不留转发；旧裸名由 L6 兼容层（head.jl shim / Pickup_ion）重新绑定。 |
| 5 | **H-4 仍由人工选择**（HD-04）。<br>方案 C：把火星边界几何并入 MarsCommon，这是 t6 倾向的做法。<br>方案 E：独立建 MarsEnvironment，这是草案原立场。<br>两套方案都给出完整的依赖、装载与迁移路径，本文件不替用户选择。 |
| 6 | **科学修正**：<br>F-1：cyclotron 三套实现参数体系不同，禁止裸 alias。<br>F-2/F-7：`sta_v_4d` 等价证据必须带前置条件；副作用（就地写入、println）单独建用例。<br>F-3：`color_mapping` 迁入后改用不同名字。<br>F-4：`:mass` 键禁止定义成「不同名同值」的常量。<br>F-5：NaN 按位置比较，新增 NaN 一律判失败。<br>F-6：建立科学验证 backlog。<br>F-8：AST oracle 改用精确计数。 |
| 7 | **待人工决策**：草案的 H 项与 t7 的 U 项合并去重为 **HD-01…HD-15**（§10）。 |
| 8 | **施工组织**：含队长 8 Agent，新增 `pro-code-official-1` 和 `flash-code-official-1` 两个名额。须经 HA-0 批准后才可施工。 |

---

## 1. 约束（继承，不再论证）

1. **装载机制红线**：`_carrier`、`load_module`、`@load`、`:preloaded` 分支、`ModuleLoadError` 的代码一律不改。只允许增补或修改注册表数据（条目、`kind`、`deps`、`allow`、`note`）和 validate 校验。修改既有条目的 `kind` 属于可观察行为变化，须经人工批准（HD-05）。
2. **科学契约保留**：以下差异是历史契约，不是 bug，本轮不统一：
   - `:mass` 键的含义随生产模块而异；
   - 角度约定：SWIA 用度，STATIC 存度、计算时转弧度，MINPA 用弧度，MarsCommon 用度；
   - MGS 返回 `Dict{String,Any}`，`"Vars"` 是位置列表；TW 同时输出 `:time` 和 `:epoch`；
   - 两套 PSD 并存；
   - 磁力线追踪默认 `:euler`；
   - `get_mag_line_s` 先读 `:B` 再回退 `"B"`；
   - `static_slip` 返回的视图与原数组共享内存；
   - 缺失值统一用 NaN 或 flag 表示，不引入 `missing`；
   - `constants` 中 μ0、e 的取值沿用现值；
   - 无操作参数（`STA_count2eflux` 的 `m_int`、SWEA `n1d` 的 `energy_range`）保持原样。
3. **C 类疑点不改值**：C6、C7、C10、C11、C12、C13 只原样搬运，由用户裁决（HD-11）。
4. **合成回归 ≠ 科学正确**（t4 §7）。
5. **工作区未提交代码保持原样**：P6 与 TASK-024/025 共 19 个文件，在 HD-02 裁决前不提交、不回滚。
6. **范围限制**：不做函数级性能优化，TASK-044…048 过滤。TASK-026、TASK-039/040 默认不纳入（HD-12）。
7. **依赖清单**：任何 MIG 都不修改 `Project.toml`/`Manifest.toml`。出现依赖缺失时，按阻塞上报。
8. **其他**：Python 侧零改动；数据与配置文件只读；不重命名既有模块。

---

## 2. 目标层次与依赖方向

### 2.1 能力层

```text
L6 Analysis       Pickup_ion（pickup_ion_analysis）、Build_data、example、head.jl 兼容 shim、calculate_models 弃用门面
L5 Visualization  MAVEN_plot、src/plotting.jl
L4 Domain Model   IGRF_calculate、Cold_Plasma_Dispersion_Relation、Maxwellian_Distribution、Single_Particle_Orbit、
                  MarsEnvironment（仅当 HD-04 选 E）
L3 Instrument     MAVEN_STATIC、MAVEN_SWIA、MAVEN_SWEA、TW_MINPA
L2 Data Access    MAVEN_load、TW_load、MGS_load、SP_load
L1 Foundation     constants、MarsCommon、FunctionCoordinate（新，包化）     L1n Native：Call_fortran_dll
L0 Core           MarsData：Paths、DataKeys、注册表/装载器、registry/index
X  Extras         Octree、Graham…（CATALOG.toml 登记；任何层都不得依赖 X）
```

calculate_models 门面与 head.jl shim 放在 **L6**。它们只做兼容绑定，按 L6 的规则可以指向任意下层，因此不再需要特例边。

### 2.2 允许的依赖边（`validation/architecture/layers.toml` 的权威来源）

| 从 \ 到 | L0 | L1 | L1n | L2 | L3 | L4 | L5 | X |
|---|---|---|---|---|---|---|---|---|
| L1 | Paths/DataKeys | 见注 1 | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| L2 | ✓ | ✓ | ✗ | ✗ | ✗（注 2） | ✗ | ✗ | ✗ |
| L3 | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| L4 | ✓ | ✓ | ✓ | ✗ | ✗ | 一跳（注 3） | ✗ | ✗ |
| L5 | ✓ | ✓ | ✗ | ✗ | ✗ | 只限无状态纯函数模块 | 同层 | ✗ |
| L6 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | 显式 include |
| X | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | 同层 |

- **注 1**：L1 内部只允许 FunctionCoordinate→MarsCommon 和 MarsCommon→constants 两条边，反向禁止。**L1→L4 无例外**（处置 M2）。
- **注 2**：L2→L3 只能作为兼容转发边存在，必须用 `eager_dep` 模式，登记移除期限（§3.4）。
- **注 3**：L4 内部只允许一跳依赖，且必须登记在注册表 `deps`。
- 禁止一切循环，AST 校验强连通分量为空。

### 2.3 L0 / 载体 / 白名单

- 装载机制原样保留。
- L1–L4 中凡**不在预装闭包内**的模块，都经载体装载。
- 预装闭包成员资格见 §3.3 的规则 PL-1 和 PL-2。

### 2.4 逻辑层与物理装载位置两维表（采纳 S3）

| 模块 | 逻辑层 | 物理装载位置（策略 P 实施后） | 其他副本 |
|---|---|---|---|
| Paths、DataKeys | L0 | 预装（规范实例） | Paths 被 MAVEN_load、TW_MINPA 等自包含，形成嵌套副本，属既有现状 |
| MarsCommon | L1 | **预装**：规范实例 = `MarsData.MAVEN_plot.MarsCommon` | L2/L3/L4 自包含产生嵌套副本（I-2） |
| constants | L1 | 载体（保持不变；豁免 I-4，理由见 §3.2） | 多处嵌套副本 |
| FunctionCoordinate | L1 | 载体（使用 Rotations，按 PL-1 不得进入预装） | 采用 G-include（§3.5），不复制 MarsCommon |
| MarsEnvironment（选 E 时） | L4 | **预装**：规范实例 = `MarsData.MAVEN_plot.MarsEnvironment` | 无 |
| MAVEN_plot、plotting | L5 | 预装 | — |
| 其他注册模块 | L2–L4 | 载体 | — |

---

## 3. 实例语义、预装策略与转发解析（处置 M1 / M3 / M4）

### 3.1 现状事实（已复核）

1. `MAVEN_plot.jl:4-5` 在 MAVEN_plot 模块内部自包含 `constants.jl` 和 `MarsCommon.jl`。因此 `using MarsData` 之后，预装闭包里已经有一个 `MarsData.MAVEN_plot.MarsCommon`。
2. 注册表中 `:MarsCommon` 是 `kind=:module`（`modules.jl:61-64`）。`load_module(:MarsCommon)` 会在载体中**再**求值一次，得到第二个实例。**同名双实例在今天已经存在。**
3. `load_module` 处理 `:preloaded` 依赖时，若装入目标不是 MarsData 本身，会执行 `const X = <包内实例>`（`modules.jl:347-353`）。载体模块递归装入 `deps` 时（`:361-363`），依赖会以别名形式绑进载体。**这一点使策略 P 无需改动机制代码。**
4. `src/MarsData.jl` 只预装 Paths、DataKeys、MAVEN_plot、plotting。若在 plotting.jl 中直接写 `MarsCommon.f`，包加载时会 UndefVarError。
5. MarsCommon 的外部依赖**现状**只有 `using StaticArrays`，在 HEAD 的 16 项 `[deps]` 中，也在 45 项中。**拟改**：MIG-011 迁入函数后，将增加 Statistics、LinearAlgebra、Dates，受 §3.3 PL-1 约束。（t11 并入 RR-A R-2）
6. `test/runtests.jl:350` 断言 `!isdefined(MarsData, :constants)`。因此 constants 不能提升为预装。

### 3.2 实例规则

- **I-1 规范实例唯一**：每个注册模块在一个进程内只有一个规范实例，即 `MarsData.X`、`@load X`、`load_module(:X)` 三者返回的对象，且彼此 `===`。
- **I-2 嵌套副本只许无状态的权威文件**：自包含 include（ARCH-003）产生的嵌套副本，只允许出现在以下无状态模块：constants、MarsCommon、Paths（既有）、FunctionCoordinate、MarsEnvironment。
  - 「无状态」由 AST 判定：不存在非 `const` 的顶层赋值，不存在顶层 `Ref`/`Dict`/`Vector` 可变容器，不存在 `global` 写入。
  - 嵌套副本与规范实例之间只要求数值等价，不要求 `===`。
- **I-3 预装闭包内不新增重复实例**：从 MarsData 可达的子模块树中，MarsCommon、MarsEnvironment 各**恰好一个对象**。
  - constants 的既有重复（`MAVEN_plot.constants` 与 `MAVEN_plot.MarsCommon.constants`）在 MIG-000 记录基线，**只许不增**。
  - `src/MarsData.jl` 和 `src/plotting.jl` **不得**再次 include MarsCommon.jl 或 Mars_Environment.jl。
- **I-4 既预装又注册者，必须登记为 `:preloaded`**：凡在预装闭包中存在、又在注册表登记的模块，必须是 `kind=:preloaded`，并绑定到闭包内那个实例，不得另有载体孪生实例。
  - 适用：MarsCommon；HD-04 选 E 时还包括 MarsEnvironment。
  - **豁免 constants**：它只是常量容器；若提升为预装会破坏 `runtests.jl:350` 的隔离断言。豁免理由写入 `layers.toml`。
- **I-5 转发目标在定义处可解析**：转发函数所引用的目标模块，在转发模块的命名空间内必须可解析，具体方式见 §3.4。

### 3.3 策略 P（推荐，人工决策 HD-05）

**实施内容**：
1. 在 `src/MarsData.jl` 的 `using .MAVEN_plot` 之后，新增一行 `const MarsCommon = MAVEN_plot.MarsCommon`。若 HD-04 选 E，再加一行 `const MarsEnvironment = MAVEN_plot.MarsEnvironment`。
2. 注册表 `:MarsCommon` 的 `kind` 改为 `:preloaded`（`path`、`deps`、`allow` 不变）。若选 E，新增 `:MarsEnvironment` 条目，`kind=:preloaded`。

**与约束的关系**：

| 约束 | 关系 |
|---|---|
| 装载机制红线 | 机制代码零改动。只改注册表数据，并在 L0 加一行别名绑定。可观察变化是 `using MarsData` 之后 `MarsData.MarsCommon` 已定义，且 `parentmodule(MarsData.MarsCommon) === MarsData.MAVEN_plot`。因此须人工批准。 |
| L0 轻量性 | **不新增任何代码或依赖。** MarsCommon 本来就随 MAVEN_plot 预装，策略 P 只是把注册入口指向它。 |
| **PL-1** | 预装闭包成员只能 `using` HEAD 16 项 L0 依赖中的包。MarsCommon 在 MIG-011 之后（拟改状态）只用 StaticArrays/Statistics/LinearAlgebra/Dates；MarsEnvironment 只用 LinearAlgebra。MIG-011 迁入 MarsCommon 的函数受此约束，由 AST 校验。FunctionCoordinate（使用 Rotations）因此**不得**进入预装。 |
| **PL-2** | 预装成员必须无状态（I-2）。 |
| D-1 分支 A（收敛） | 成立。所用依赖全部在 16 项内。 |
| D-1 分支 B（接纳 45 项） | 成立。PL-1 依然有用：它让「无数据、无 DLL 也能 `using`」继续可测。 |
| D-1 分支 C（净化） | 成立。净化审计时必须保留 StaticArrays、LinearAlgebra、Statistics、Dates，可由 MIG-001 的 using 清单自动给出。 |
| 既有测试 | `runtests.jl:376-397` 中 MarsCommon 的 allow 与 `into` 用例逻辑仍成立（预装分支会做 `const` 绑定加 `_apply_allow!`）。`:350` 只涉及 constants，不受影响。`validate_registry` 的 errors 预期不变。MIG-014 须实测确认。 |

**若 HD-05 否决策略 P**：MarsCommon 保持载体模块。此时必须在文档和测试中声明「`MarsData.MarsCommon`（载体）与 `MAVEN_plot.MarsCommon` 是两个对象，只保证数值等价」，并接受 I-4 不成立。预装消费者一律转发到 `MAVEN_plot.MarsCommon`；MarsEnvironment（选 E 时）仍按 I-4 设为 `:preloaded`。

### 3.4 转发解析规则（处置 M4）

**允许的两种模式**：

| 模式 | 适用目标 | 机制 | 装载顺序保证 |
|---|---|---|---|
| `nested` | 只限 I-2 列出的无状态权威文件（MarsCommon、FunctionCoordinate、MarsEnvironment） | 转发模块自包含（或按 §3.5 G-include）该目标文件，转发体写 `MarsCommon.f(args...; kw...)` | 在定义时即存在（include 先于转发定义） |
| `eager_dep` | 有状态或重依赖的载体模块（L3：MAVEN_SWEA、MAVEN_STATIC） | 把目标加入转发模块的注册表 `deps`（临时，登记 `adds_deps`）。在**模块体顶层**写守卫常量（必须位于 `module MAVEN_load … end` 体内，使 `parentmodule(@__MODULE__) === 载体`；不得放在 `module` 声明之前的文件顶层，那里 `@__MODULE__` 是 include 的目标模块，例如 Main；t11 并入 RR-A R-1） `const _TARGET = isdefined(parentmodule(@__MODULE__), :MAVEN_SWEA) ? parentmodule(@__MODULE__).MAVEN_SWEA : nothing`。转发体在 `_TARGET === nothing` 时抛出带指引的 `ErrorException`（提示「请经 MarsData.@load 装载」），否则调用 `_TARGET.f` | `load_module` 先把 deps 递归装入载体，再 include 本文件（`modules.jl:361-363`） |

**禁止的模式**：在转发体内惰性调用 `MarsData.load_module`。理由：需要 `invokelatest` 处理 world age；会把 MarsData 引入载体模块；装载时机不可预测。

**预装文件的解析**：
- `src/plotting.jl` 的 `TimeFormat` 转发到 `MarsCommon.TimeFormat`。策略 P 下它就是 `MAVEN_plot.MarsCommon`；否决 P 时显式写 `MAVEN_plot.MarsCommon.TimeFormat`。两种情况下目标都在 plotting 被 include 之前已经存在（`MarsData.jl:66-70`）。
- MAVEN_plot 内部的转发全部用 `nested` 模式，指向其 `:5` 行已有的 MarsCommon。选 E 时 MAVEN_plot 增加 `include(models/Mars_Environment.jl)`，位置在 MarsCommon 之后。

**`layers.toml [compat_edges]` 字段**：`from`、`to`、`function`、`mig`、`resolve`（`nested:self_include`、`nested:dep_parent` 或 `eager_dep`）、`adds_deps`、`remove_by`（下一轮 MIG 编号）。

**AST 规则**：转发体引用了模块 X，但 X 既不是本模块的嵌套 include，也不在 `deps ∪ adds_deps` 中，即判失败。

**直接 include 的遗留路径**：例如把 `MAVEN_load.jl` 直接 include 进 Main。此时各类转发的行为如下（t11 并入 RR-A R-3）：
- **nested · 自包含 / G-include 子模式**照常工作：转发模块在本文件内 include 目标文件，例如 MAVEN_load、MAVEN_plot、calculate_models 门面、FunctionCoordinate。
- **nested · 依赖 deps 与父模块解析子模式**只在经 `load_module` 装载时可用：转发模块不自包含目标，靠注册表 deps 把目标绑进载体，例如 IGRF_calculate、Single_Particle_Orbit、TW_MINPA 对 MarsCommon 的转发。直接 include 时会 UndefVarError。这三者是注册模块而非脚本，此限制可以接受。实施时每条 compat 边须在 `layers.toml` 的 `resolve` 中标明子模式，取值 `nested:self_include` 或 `nested:dep_parent`。
- **eager_dep 转发**在调用时给出清晰错误，不会是 UndefVarError。

CHANGELOG 中须注明上述三种行为。

### 3.5 新模块的 G-include（守卫复用）

FunctionCoordinate 和 MarsEnvironment 需要 constants 与 MarsCommon 时，采用「父模块已有就复用，否则自包含」的写法。示意如下，这里只是规范描述，不是交付代码：

```text
if isdefined(parentmodule(@__MODULE__), :MarsCommon)  → const MarsCommon = parentmodule(@__MODULE__).MarsCommon
else                                                  → include(…/MarsCommon.jl)
```

三种装载场景的效果：
- **在 MAVEN_plot 内部**：复用 `MAVEN_plot.MarsCommon`，满足 I-3。
- **在载体中**：deps 已经递归绑定了 MarsCommon（策略 P 下就是规范实例），复用它。
- **直接 include**：自包含，回到 I-2 的嵌套副本。

`validate_registry` 的规则 (b) 会因此增加「自包含加 deps 冗余」警告。该警告本来就在 `@test_broken` 中。MIG-014 须记录警告的精确增量，不得把它当成错误处理。

### 3.6 依赖声明（处置 M3）

| 模块 | 注册表 `deps` | 备注 |
|---|---|---|
| FunctionCoordinate | `[:constants, :MarsCommon]` | G-include |
| MarsEnvironment（E） | `[:constants, :MarsCommon]` | `get_bowshock_normal` 依赖 MarsCommon 的 `solve_func` |
| calculate_models（门面） | `[:constants, :MarsCommon, :FunctionCoordinate]`，选 E 时再加 `:MarsEnvironment` | 转发均为 nested 模式 |
| MAVEN_load（波 2 期间） | 原 deps 加 `adds_deps=[:MAVEN_SWEA, :MAVEN_STATIC]` | eager_dep，带移除期限；须先验证不成环（SWEA/STATIC 不依赖 MAVEN_load） |
| IGRF_calculate、Single_Particle_Orbit、TW_MINPA | 原 deps 加 `:MarsCommon`；TW_MINPA 另加 `:FunctionCoordinate` | nested 模式加文档化依赖 |

### 3.7 实施后可验证的同一实例断言与装载用例（写入 MIG-014 和 GATE-2 的验收）

| ID | 用例（新进程） | 期望 |
|---|---|---|
| V-I1 | `using MarsData`（选 P） | `MarsData.MarsCommon === MarsData.MAVEN_plot.MarsCommon` |
| V-I2 | `MarsData.load_module(:MarsCommon)` | `=== MarsData.MAVEN_plot.MarsCommon`，且载体中**不**新求值一份（`isdefined(_carrier(), :MarsCommon)` 只能是别名） |
| V-I3 | 顶层执行 `MarsData.@load MarsCommon` | `Main.MarsCommon === MarsData.MAVEN_plot.MarsCommon`；allow 中三个裸名可用 |
| V-I4 | `MarsData.load_module(:MAVEN_load)` | `MarsData._carrier().MarsCommon === MarsData.MarsCommon` |
| V-I5 | 遍历 MarsData 预装子模块树 | 名为 MarsCommon 的不同对象计数为 1；选 E 时 MarsEnvironment 也为 1，且 `MAVEN_plot.MarsEnvironment.MarsCommon === MAVEN_plot.MarsCommon`；constants 计数不高于 MIG-000 基线 |
| V-F1 | 只执行 `using MarsData`，不调用任何 load_module | `MarsData.TimeFormat(t1,t2)` 与基线字符串一致；`MarsData.MAVEN_plot.bowshock(x)`、`.polynomial_fit(...)` 与基线一致 |
| V-F2 | `load_module(:MAVEN_load)` 之后 | `isdefined(_carrier(), :MAVEN_SWEA)`；`MAVEN_load.SWEA_calc_shape_arr(fixture)` 与基线数值 exact 一致 |
| V-F3 | 把 `MAVEN_load.jl` 直接 include 进一个空 Module | eager_dep 转发抛 ErrorException，消息中含「MarsData.@load」；`nested:self_include` 转发照常可用（`nested:dep_parent` 不在此用例范围） |
| V-R1 | `test/runtests.jl` | pass 数不低于 141，broken 不增加；`:350` 的 constants 隔离断言仍然通过 |
| V-R2 | `validate_registry()` | errors 为空；warnings 增量与 MIG-014 记录一致 |

---

## 4. 功能归属与权威落点

### 4.1 同名定义精确计数（工作区实测；MIG-000 冻结时复测，作为 AST oracle，处置 F-8）

| 名称 | 顶层定义 | 嵌套（局部）定义 | 注释掉的定义 |
|---|---|---|---|
| `bowshock` | 2：`MAVEN_plot.jl:1514`、`head.jl:358` | 0 | 0 |
| `magnetopause` | 2：`MAVEN_plot.jl:1541`、`head.jl:397` | 0 | 0 |
| `bowshock_zero` | 1：`function_coordinate.jl:249` | 0 | 0 |
| `Bpc2sphere` | 2：`MAVEN_load.jl:962`、`IGRF_calculate.jl:121` | 0 | 0 |
| `TimeFormat` | 2：`src/plotting.jl:26`、`Single_Particle_Orbit.jl:30` | 0 | 0 |
| `color_mapping` | 1：`head.jl:169` | 2：`MAVEN_plot.jl:297,537` | 1：`TW_MINPA.jl:598`（不计入） |
| `slice2d_cal_rot` | 2：`function_coordinate.jl:28`、`TW_MINPA.jl:568` | 2：`MAVEN_plot.jl:321,561` | 0 |
| `static_c6_mass_mean` / `static_c6_energy_mean` | 各 2：`MAVEN_load.jl:1037/1105`、`MAVEN_STATIC.jl:69/142` | 0 | 0 |
| `cyclotron_radius` | 2：`calculate_models.jl:116`（AMU/eV）、`Single_Particle_Orbit.jl:355`（SI） | 0 | 0 |
| `cyclotron_frequency` / `cyclone_frequency` / `cyclone_R` | 各 1：`calculate_models.jl:149`、`MAVEN_load.jl:1277`、`MAVEN_load.jl:1298` | 0 | 0 |
| 死 export `WaveSpactra_heatmap` | 1：`MAVEN_plot.jl:18` | — | — |
| 孤儿 docstring（D-4） | 2：`TW_load.jl:111-129`、`MGS_load.jl:96-113` | — | — |

草案中「bowshock 至少 2 份」「至少 4 份副本」两种说法均作废。边界模型的准确描述是：3 个文件中共有 5 个定义（bowshock×2、magnetopause×2、bowshock_zero×1），外加依赖它们的 `get_bowshock_normal`。oracle 使用 `==` 精确计数。如复测结果不同，须附证据更新 oracle，**不得放宽为「至少」**。

### 4.2 权威落点

**两套方案共同的落点**：

| 函数 | 现位置 | 权威 | 转发与处理 |
|---|---|---|---|
| `Bpc2sphere` / `Bsphere2pc` | MAVEN_load、IGRF | MarsCommon | MAVEN_load 与 IGRF 改为 nested 转发（MIG-020/022） |
| `Vandermonde` / `polynomial_fit` / `vector_angle` | MAVEN_plot | MarsCommon | MAVEN_plot nested 转发（MIG-021） |
| `Linear_fit` | calculate_models | MarsCommon | 门面转发 |
| `safe_log_mean` / `skipnan` / `nozeros` / `geomean` / `find_range` / `get_normal_plane` / `get_angle` / `solve_func` | head.jl | MarsCommon | head.jl shim 绑定旧裸名 |
| `TimeFormat(t1,t2; format=:hms_ms)` | plotting、SPO | MarsCommon | plotting 与 SPO 转发；SPO 显式传原格式；输出须逐字一致 |
| `rotation_matrix` / `Quaternion_Rot` / `Quaternion_Rot_reverse` | calculate_models | FunctionCoordinate | 门面转发 |
| `slice2d_cal_rot` | function_coordinate、TW_MINPA | FunctionCoordinate | TW_MINPA 转发前，须证明共线输入的行为也一致；否则保留副本并上报 |
| SWEA shape / PAD（`SWEA_calc_shape_arr*`、`mean_SWEA_pad_pa`、`carclu_SWEA_pad`） | MAVEN_load | MAVEN_SWEA | MAVEN_load 用 eager_dep 转发 |
| `static_c6_*` | MAVEN_load、MAVEN_STATIC | MAVEN_STATIC（新版） | MAVEN_load 用 eager_dep 转发。前置条件：旧输入在新版上逐点等价 |
| `cyclotron_frequency` / `cyclotron_radius`（AMU/eV 体系） | calculate_models | MarsCommon（代码逐字复制，同名同签名） | 门面 nested 转发，exact 比较 |
| `MAVEN_load.cyclone_*`（kg 质量加速度 v 体系） | MAVEN_load | 见 §4.4，待 HD-07 | **禁止裸 alias** |
| 绘图标签与色标（`label_data`、`print_f`、`norm2`、`get_log_ticks`，以及 `color_mapping`→`color_mapping_lut`，见 §4.5） | head.jl | MAVEN_plot | shim 绑定旧名 |

**火星边界与环境函数**（HD-04 二选一）：

| 函数 | 方案 C（并入 MarsCommon，`common/marscommon/environment.jl` 子文件） | 方案 E（独立 MarsEnvironment，`models/Mars_Environment.jl`，L4，预装） |
|---|---|---|
| `bowshock` / `magnetopause` / `bowshock_km` | MarsCommon | MarsEnvironment |
| `bowshock_zero` / `get_bowshock_normal` | MarsCommon | MarsEnvironment |
| `mars_sun_dist_phys` / `escape_energy` | MarsCommon | MarsEnvironment |
| `escape_energy` 已知潜在 bug（两方案相同；t11 并入 RR-S R-1） | 原行为：`planet≠"Mars"` 时 `v` 未赋值，调用抛 `UndefVarError`（`calculate_models.jl:87-96`，docstring 自述）。**原样保留并记录，本轮不修**。迁移按 pure_move exact 比较；B-DUP 增加一条 `expected_behavior = throws` 用例（`planet="Earth"` 时抛 `UndefVarError`）；登记 §9 SB-ESC | 同左 |
| MAVEN_plot 的转发目标 | `MarsCommon.bowshock`（nested，已存在） | `MarsEnvironment.bowshock`（MAVEN_plot 内 include，G-include 复用 MarsCommon） |
| FunctionCoordinate | **删除** `bowshock_zero`，不转发；旧裸名由 L6 绑定（MIG-027） | 同左 |
| 依赖边 | L1 内部；L5→L1 | L5→L4（纯函数）；L4→L1；无 L1→L4 |
| 代价 | MarsCommon 体积变大（以子文件拆分缓解）；能力域语义稍弱 | 多一个模块；须走策略 P/I-4 的预装绑定 |

**同名副本合并前的门禁**：bowshock、magnetopause 各自的两份副本（MAVEN_plot 与 head.jl）须先证明逐点等价。若不等价，以不同名字分别保留，并交给 Pro-science 判断。

### 4.3 明确不合并

- `load_quat`：读取层返回 Dict，SWEA 返回 Matrix。
- `MINPA_sphere2xyz`：FunctionCoordinate 版与 TW_MINPA 版接口不同。
- 两套 PSD。
- `Single_Particle_Orbit.cyclotron_radius`：SI 输入。
- `sta_v_4d` 与 `sta_v_4d_new`：只出证据，不合并（HD-08）。
- MAVEN_plot 内部嵌套的 `slice2d_cal_rot`、`remove_repeat_points`、`color_mapping`：本轮不动。
- `logticks` / `interpolate_x_ticks` / `time_ticks` / `time2x`：属于绘图刻度，留在 MAVEN_plot。

### 4.4 cyclotron（处置 F-1，待 HD-07）

已复核的三套参数体系：

| 实现 | 质量与电荷 | 输入 | 输出 |
|---|---|---|---|
| `MAVEN_load.cyclone_frequency(B; mass=me)` | kg 质量；默认电子，不随离子切换 | B（nT） | Hz，公式 `e·B·1e-9/(2π·m)` |
| `MAVEN_load.cyclone_R(v, B; mass=me)` | kg 质量 | v（m/s）、B（nT） | m |
| `calculate_models.cyclotron_frequency/radius(B[, ek]; nM, nQ)` | AMU 质量数加电荷数；电子与离子分支 | B（nT）、ek（eV） | Hz / (f, rc, v)，公式 `1/(cc·2π)` |
| `Single_Particle_Orbit.cyclotron_radius(B_in, v; nM, nQ)` | SI | — | 不合并 |

kg 体系与 AMU 体系即使在电子情况下代数等价，浮点运算顺序也不同，**不能**按逐位一致处理。

**HD-07 选项**（禁止项对所有选项都适用）：

| 选项 | 内容 | 比较方式 |
|---|---|---|
| **(a) 推荐** | 在 MarsCommon 中以**独立名字**逐字复制 kg 体系实现，暂定名 `cyclotron_frequency_kg(B; mass)`、`cyclotron_radius_velocity(v, B; mass)`，最终名称由用户定。`cyclone_*` 用 nested 转发到同体系的新名字 | exact |
| (b) | `cyclone_*` 留在 MAVEN_load 作为冻结的遗留函数，不转发，与 SPO 的处理一致 | — |
| (c) | 用换算包装把 kg/v 输入转到 AMU/eV 体系 | 必须由用户明确批准；须写 `tolerance_justification`，rtol 不宽于 1e-12，并经 Pro-science 批准 |

- **禁止**：`const cyclone_R = MarsCommon.cyclotron_radius` 这类跨体系裸 alias。
- MIG-005 审计表必须逐条写出：质量单位、默认粒子、输入是速度还是能量、离子情况下数值是否改变，四项结论齐全。
- **TimeFormat 格式逐字采集**（t11 并入 RR-S R-2）：MIG-005 审计表须逐字照录 `src/plotting.jl:26` 与 `Single_Particle_Orbit.jl:30` 两版 `TimeFormat` 的实际格式化实现，包括字符串拼接或 `Dates.format` 字面量、补零位数与分隔符，不得凭记忆填写。MarsCommon `TimeFormat` 的 `format` 选项值，以及 MIG-024 中 SPO 显式传入的格式，都以该采集为唯一依据。

### 4.5 color_mapping（处置 F-3，待 HD-09）

- `MAVEN_plot.jl:297,537` 两处是 `STA_2d_slip` 和 `VDF_2d_slip` **内部**的局部函数，局部定义会遮蔽同名全局函数。
- **默认方案**：head.jl 的 `color_mapping` 迁入 MAVEN_plot 时改名为 `color_mapping_lut`（顶层不再出现同名）。head.jl shim 把旧裸名 `color_mapping` 绑定到 `MAVEN_plot.color_mapping_lut`。
- 三个版本（head 顶层版与两个嵌套版）之间的等价比较**只作为证据**。本轮不删除嵌套版。
- **AST 断言**：MAVEN_plot 顶层不出现与嵌套函数同名的新定义；`STA_2d_slip`、`VDF_2d_slip` 内部的调用点解析结果不变；shim 绑定的目标精确为 `color_mapping_lut`。
- **备选**：保留顶层名 `color_mapping`。前提是三个版本已证明等价，且用户接受局部遮蔽的语义。

---

## 5. Public API 与 namespace

1. **三层 API 面**：全限定名为默认形式；allow 白名单裸名只放 api.md 认定的入口；`export` 不作为裸名引入依据。
2. **旧名保留**：迁出的函数在原模块保留同名转发，docstring 首行写 `DEPRECATED → X.f (MIG-xxx)`。默认不发 depwarn（HD-13）。转发名**不加入** allow。
3. **新入口进新模块的 allow**；旧模块 allow 中已有的名字（例如 IGRF 的 `pc2sphere`）保持不变。MIG-014 把这三条规则写进注册表 `note`（采纳 S4）。
4. **数据契约属于 API 的一部分**：新增或改动 Dict 键必须先登记 DataKeys 与附录 A。`:mass` 的处理见 HD-10。**禁止**定义多个无前缀、值相同、只靠 docstring 区分语义的常量（处置 F-4）。
5. **`MarsData` 顶层 namespace 只增加三类绑定**：策略 P 带来的 `MarsCommon`（以及选 E 时的 `MarsEnvironment`）模块别名，以及 L0 基础设施。不新增顶层函数。

---

## 6. 验证策略（Phase B 先行）

### 6.1 位置、环境与基线

- 验证工具放在 `validation/`，使用独立环境或只用标准库（`Meta.parseall`、`TOML`），不改主 `Project.toml`。
- **基线冻结**（MIG-000）：在任何迁移之前，从当前工作区采集。HD-02 批准快照提交时，以该提交为基线；否则以只读副本为基线，并记录文件哈希清单。MIG-000 的编号只是标识，它是波 B 末尾的冻结动作；HD-02 是它的软依赖（采纳 S8）。

### 6.2 AST 工具（MIG-001）

**抽取与分析**：
- module 与 function 定义（顶层和嵌套分开标注）、`using`/`import`/`include`（包括 G-include 模式）、`export`、`const` 别名；
- 调用点与跨模块调用图；
- `layers.toml` 层规则校验，包括 compat_edges 的 `resolve` 与 `adds_deps`、预装成员的 PL-1/PL-2、I-2 无状态判定、强连通分量检测；
- 迁移前后结构 diff：定义的增、删、移位，export 与 allow 集合差，悬空调用；
- 把每个 MIG 的「预期移动清单」（`validation/migrations/MIG-xxx.toml`）与实际 diff 比对，非预期变化即失败；
- 同名遮蔽检测（F-3 通用化）；
- 孤儿 docstring 检测（采纳 S5，作为 MIG-051 的前置）。

**自检 oracle**（必须精确命中）：
- §4.1 的全部计数；
- `head.jl` 存在裸 include（AR-1）；
- 死 export 一处；
- D-4 两处孤儿 docstring；
- MarsCommon 到 L2 无边；
- 当前 MarsCommon 同时存在于预装闭包和载体注册中（即策略 P 要修正的现状）。

### 6.3 Call Table（MIG-002 框架，MIG-003 用例）

**用例字段**：`case_id`、`module`、`function`、`args`、`kwargs`、`setup`、`preconditions`、`expected_behavior`（取值：`value`、`throws`、`mutates`、`prints`）、`comparison`、`atol`、`rtol`、`nan_policy`、`tolerance_justification`、`tags`、`evidence_level`（A/B/C/D）、`migs`。

**比较器**：
- 递归比较标量、Array、Tuple、NamedTuple、Dict（键集合必须相等）、struct（逐字段）、DataFrame（列名和列值）。
- `Inf` 须同位置、同符号；出现 `missing` 直接报错。
- exact 模式按 `isequal` 逐元素比较，带符号零的差异也判失败。

**NaN 规则（处置 F-5）**：
- 默认 `nan_policy = positional`：新旧结果的 NaN 位置集合必须完全相同。
- 报告必须包含：旧 NaN 数量、新 NaN 数量、新增位置、消失位置。
- **任何新增 NaN 位置都判失败，与容差无关**。
- `nan_policy = ignore` 只能在附理由并经 Pro-science 批准后使用，且对 `science_sensitive` 用例一律禁止。

**容差**：
- `pure_move` 一律 exact。exact 失败本身就是红色警报，不得改用 rtol 蒙混。
- 重排或参数化的转发，默认 `rtol = 1e-12`。
- 放宽容差须写 `tolerance_justification` 并经 Pro-science 批准。
- 结果不一致时，按 new_plan §10 的五类原因归因，不得静默修改用例。

**行为基线用例（GATE-B 门禁内容；缺证据不得标记为通过）**：

| 组 | 内容 | 可行性 | 放行对象 |
|---|---|---|---|
| B-025 | `load_kp`：默认 `kp_columns`、自定义 `kp_columns`、`change_kp_read_data` 兼容路径（合成 fixture） | 可合成 | 所有触及 MAVEN_load 的 MIG |
| B-004 | `get_mag_line_s`：读 `:B`、回退 `"B"` | 可合成 | MIG-022 |
| B-018 | SWEA `n1d`（含 clamp） | 可合成 | MIG-013 |
| B-022 | `SWEA_calc_shape_arr`（含 C10 常数与 NaN 处置） | 可合成 | MIG-013、MIG-020 |
| B-003 | `STA_count2eflux` / `STA_eflux2df` 默认 `m_int`，以及 `m_int` 不参与计算的无操作语义 | 可合成 | STATIC 相关迁移 |
| **B-STA**（处置 F-2/F-7） | 见下表 | 可合成 | **只出证据**（HD-08） |
| B-CYC | cyclotron 三套体系各自的基线，以及 HD-07 选项 (a) 的 exact 用例 | 可合成 | MIG-011、MIG-020、MIG-025 |
| B-DUP | §4.2 每一对「旧副本 vs 新权威」的逐点用例（bowshock/magnetopause 两份副本互比、slice2d 共线输入、static_c6 旧输入、color_mapping 三版本） | 可合成 | 对应的转发 MIG |
| B-INST | §3.7 中 V-I/V-F 系列 | 可运行 | MIG-014、GATE-2 |
| 既有测试 | `runtests.jl` 141 pass / 1 broken | 已可运行 | 全程不得回退 |
| skipped | `needs_dll`（`:adaptive`）、`needs_real_data`（C 类） | 不可运行 | 不伪造 DLL；不计入通过 |

**B-STA 用例**：

| 用例 | 前置条件 | 断言 |
|---|---|---|
| EQ-STA-1 | 合成 `static_slip` 切片满足 `sta_v_4d_new` 的类型断言（`:energy` 等为 `Float32` 三维数组，df 为 `Float64`）。先对 `deepcopy(dat)` 执行 `STA_count2df`，得到**已含 `:df`** 的 `dat_df` | `sta_v_4d(deepcopy(dat); unit_cover=true)` 与 `sta_v_4d_new(deepcopy(dat_df); unit_cover=true)` 相对误差 ≤ 1e-9 |
| EQ-STA-2 | 输入已含 `:df_mass_mass` | 两个实现在 `unit_cover=false` 下比较，相对误差 ≤ 1e-9 |
| SE-STA-1 | — | `sta_v_4d(unit_cover=true)` 对输入 Dict 的写入，**以实测为准**记录前后键集与值（t7 指出它会写 `:df`/`:df_mass_mass`）；`sta_v_4d_new` 对输入无修改（`mutates = none`） |
| SE-STA-2 | `dat[:valid] == 0` | `sta_v_4d` 向 stdout 输出 `Invalid Data`（用 `redirect_stdout` 捕获，`prints`）；`sta_v_4d_new` 不输出；两者都返回 NaN。迁移须保持；改成 `@warn` 须经人工批准 |
| PRE-STA-1 | 输入不含 `:df` | `sta_v_4d_new` 抛 `KeyError`，归类为前置条件差异，**不计为数值不等价** |

结果分三类报告：数值差异、前置条件差异、副作用差异。

### 6.4 每个 MIG 的标准验收（缺一项即不得合并）

1. AST diff 与预期移动清单一致；层规则、compat 字段、PL 与 I 规则全部通过。
2. 关联的 Call Table 用例全部通过（NaN 按位置比较）；`pure_move` 结果 exact 一致。
3. `runtests` 通过，pass 数不低于 141，broken 不增加。
4. `validate_registry` 不新增 errors；warnings 增量与 MIG 声明一致；受影响模块 `load_module` 冒烟成功，allow 逐名引入冒烟成功。
5. git diff 的文件清单不超出该 MIG 的 Owned 范围。
6. 实现者与审查者分离；`science_sensitive` 的 MIG（011 中 cyclotron 部分、013、020、023、030）须经 Pro-science 审查通过。

---

## 7. Migration Plan（波次表与 DAG 一致，处置 M5）

每一行的「波」列与 §7.2 的 DAG 严格对应。所有 MIG 都在 **HA-0 之后**才可启动。

### 7.1 迁移单元

| ID | 波 | 类型 | 原 → 目标 | Owned（互斥写） | API 影响 | 依赖 | 验证 |
|---|---|---|---|---|---|---|---|
| MIG-001 | B | CREATE | AST 工具、`layers.toml`、迁移清单格式 | `validation/ast/**`、`validation/architecture/**`、`validation/migrations/README.md` | 无 | HA-0 | §6.2 自检 oracle |
| MIG-002 | B | CREATE | Call Table schema、runner、比较器及其自测 | `validation/calltable/{schema.md,runner.jl,compare.jl,selftest.jl}` | 无 | HA-0 | 比较器自测覆盖 NaN 位置报告、Inf、missing、Dict、NamedTuple、struct、DataFrame、mutates、prints |
| MIG-003 | B | CREATE | §6.3 全部基线用例与 fixture | `validation/calltable/cases/**`、`validation/fixtures/**` | 无 | 002 | 用例在基线上全部可运行 |
| MIG-004 | B | CREATE | `runtests.jl` 末尾追加验证冒烟入口，用环境变量开关，**默认跳过**（采纳 S7） | `test/runtests.jl`（只追加） | 无 | 002 | 默认运行仍为 141/1 |
| MIG-005 | B | AUDIT | TASK-027 签名与单位审计表，含 F-1 四项结论和两版 TimeFormat 格式逐字采集（§4.4 末） | `.agent/audit_signature_units.md` | 无 | 001 | Pro-science 审查 |
| MIG-000 | B（末尾） | 冻结 | 采集 AST 基线与 Call Table 旧结果；复测 §4.1 计数 | `validation/results/baseline/**` | 无 | 001、003；HD-02（软依赖） | 哈希清单；结果可复现 |
| **GATE-B / HA-1** | — | 门禁 | 框架自检通过、基线冻结、审计表完成，且 HD-07/08/09 已有裁决 | — | — | 000–005 | **人工确认** |
| MIG-010 | 1 | CREATE | 把 `function_coordinate.jl` 包成 `module FunctionCoordinate`（G-include），并复制 calculate_models 中的三个旋转函数；**同时**把 `models/Pickup_ion.jl:4` 改为「include 后 `using .FunctionCoordinate:` 精确旧名列表」的兼容行 | `common/function_coordinate.jl`、`models/Pickup_ion.jl`（只改第 4 行） | 新模块；Pickup_ion 旧裸名保持可用 | GATE-B | pure_move exact；AST 断言 Pickup_ion 可见名集合不变 |
| MIG-011 | 1 | MERGE | 把 §4.2 中落到 MarsCommon 的函数复制进来（按 S1 拆子文件 `common/marscommon/*.jl`，由 `MarsCommon.jl` 统一 include）；包括 TimeFormat；HD-07 选 (a) 时加入 kg 体系独立命名函数；HD-04 选 C 时加入边界与环境函数 | `common/MarsCommon.jl`、`common/marscommon/**` | 新增 MarsCommon API | GATE-B、MIG-005 | 与旧副本 exact 一致；PL-1/PL-2；所有自包含 MarsCommon 的模块装载冒烟（S1） |
| MIG-012 | 1 | CREATE | **仅 HD-04 选 E**：新建 `models/Mars_Environment.jl`（G-include，无状态） | `models/Mars_Environment.jl` | 新模块 | GATE-B | 两份副本互比；PL-1/PL-2 |
| MIG-013 | 1 | MERGE | 把 SWEA shape 与 PAD 函数复制进 MAVEN_SWEA | `MAVEN_data/MAVEN_SWEA.jl` | 新增 SWEA API | GATE-B（B-018、B-022） | exact；`science_sensitive` |
| MIG-015 | 1 | MERGE | MAVEN_plot 收入 head.jl 的可视化函数（`color_mapping_lut`、`label_data`、`print_f`、`norm2`、`get_log_ticks`）；选 E 时增加 `include(Mars_Environment.jl)` | `MAVEN_data/MAVEN_plot.jl` | 新增绘图 API | GATE-B；选 E 时还依赖 012 | 等价用例；同名遮蔽断言（F-3） |
| MIG-041 | 1 | RENAME（别名） | Cold_Plasma 与 Maxwellian 的正确拼写别名（TASK-041） | `models/Cold_Plasma_Dispersion_Relation.jl`、`models/Maxwellian_distribution.jl` | 新别名，旧名保留 | GATE-B | 别名与旧名 exact 一致 |
| MIG-014 | 1（末尾） | CREATE | 注册表新增 `:FunctionCoordinate`；策略 P 下 `:MarsCommon` 改为 `kind=:preloaded`，选 E 时新增 `:MarsEnvironment` 条目（`:preloaded`）；`src/MarsData.jl` 增加别名行；按 S4 写 `note` | `src/modules.jl`（只改注册表区）、`src/MarsData.jl` | 新可装载模块；`MarsData.MarsCommon` 已定义（HD-05） | 010、011、015（选 E 时还有 012） | **V-I1…V-I5、V-R1、V-R2** |
| MIG-020 | 2 | DEPRECATE | MAVEN_load：`Bpc2sphere` 用 nested 转发；SWEA shape/PAD 与 `static_c6_*` 用 eager_dep 转发；`cyclone_*` 按 HD-07 处理 | `MAVEN_data/MAVEN_load.jl`；注册表 `adds_deps` 由 MIG-014 预先登记，或本 MIG 申请注册表锁 | 旧名保留 | 011、013、014；B-025 | V-F2、V-F3；`science_sensitive` |
| MIG-021 | 2 | DEPRECATE | MAVEN_plot：数学函数转发到 MarsCommon；边界函数按 HD-04 转发；删除死 export | `MAVEN_data/MAVEN_plot.jl` | 绘图 API 不变 | 011、015、014 | V-F1；`using MarsData` 冒烟；bench_06 |
| MIG-022 | 2 | DEPRECATE | IGRF：`Bpc2sphere` / `Bsphere2pc` 用 nested 转发到 MarsCommon | `Magnetic_Model/IGRF_calculate.jl` | 不变 | 011；B-004 | 用例；`:euler` 与 `:rk4` 回归 |
| MIG-023 | 2 | MERGE | TW_MINPA 的私有 `slice2d_cal_rot` 转发到 FunctionCoordinate（G-include） | `TW_data/TW_MINPA.jl` | 不变 | 010、014 | 共线输入一致性；`science_sensitive` |
| MIG-024 | 2 | DEPRECATE | SPO 的 `TimeFormat` 用 nested 转发，并显式传原格式 | `models/Single_Particle_Orbit.jl` | 不变 | 011 | 输出逐字一致 |
| MIG-025 | 2 | DEPRECATE | calculate_models 改为纯门面，按 §3.6 声明 deps | `calculate/calculate_models.jl` | 旧名保留 | 010、011（选 E 时还有 012）、014 | 门面用例 exact |
| MIG-028 | 2 | DEPRECATE | `src/plotting.jl` 的 `TimeFormat` 转发（§3.4） | `src/plotting.jl` | 不变 | 011、014 | V-F1 |
| MIG-026 | 2（末尾） | SPLIT | head.jl 改为精确兼容 shim（§7.4） | `common/head.jl` | 脚本侧旧裸名保留 | 010–015、014、020–028 | V-S1…V-S5 |
| **GATE-2 / HA-2** | — | 门禁 | 所有转发用例通过；AST 不再检出 §4.1 中的重复实现（compat 转发和 §4.3 的不合并项除外） | — | — | 020–028 | **人工确认** |
| MIG-027 | 3 | DEPRECATE | 删除 FunctionCoordinate 中的 `bowshock_zero`（不转发）；把 Pickup_ion 第 4 行兼容列表中的 `bowshock_zero` 改为由 L6 绑定到新权威 | `common/function_coordinate.jl`、`models/Pickup_ion.jl`（第 4 行） | FC 的 API 少一个名字；Pickup 行为不变 | GATE-2 | 无 L1→L4 边；B-DUP |
| MIG-030 | 3 | SPLIT | Pickup_ion 函数化：新增 `pickup_ion_analysis`、改用 `@load`、加全局 shim、去掉 `D:/` 路径 | `models/Pickup_ion.jl` | 新入口 | 027 | 合成事件下新旧入口一致；证据等级 C；`science_sensitive` |
| MIG-031 | 3 | MOVE（装载） | `Build_data/*.jl` 改用 `@load` | `MAVEN_data/Build_data/*.jl` | — | GATE-2 | AST：无相对 include |
| MIG-032 | 3 | MOVE（装载） | `example/**/*.jl` 改用 `@load` | `example/**/*.jl` | — | GATE-2 | 同上 |
| MIG-040 | 4 | CREATE | allow 白名单保守补全 | `src/modules.jl` | 新增裸名 | GATE-2 | 逐名引入冒烟 |
| MIG-042 | 4 | CREATE | 按 HD-10 增补 DataKeys 与附录 A | `common/data_keys.jl`、`.agent/03_ARCHITECTURE_PLAN.md`（只改附录 A） | 新契约常量 | GATE-2、HD-10 | 契约测试；不得出现同值无前缀常量 |
| MIG-050 | 4 | 文档 | 新增 `docs/src/architecture.md`、`feature_addition.md`；同步 api.md | `docs/src/**` | — | GATE-2 | 文档审查 |
| MIG-053 | 4 | 文档 | 把 §9 科学验证 backlog 固化为 `docs/src/science_validation_backlog.md` | 该文件 | — | GATE-2 | Pro-science 审查 |
| MIG-051 | 4（最后） | 删除 | 死代码与孤儿 docstring（D-4、D-7） | 逐文件；须在该文件其他 MIG 全部完成之后 | — | 全部 | AST 确认只删注释与字符串表达式 |
| MIG-043 | N（非关键轨） | CREATE | `models/CATALOG.toml` | `models/CATALOG.toml` | — | HA-0 | 字段齐全 |
| MIG-052 | N（非关键轨） | 文档 | `.agent/06` 补记 TASK-024/025 | `.agent/06_IMPLEMENTATION_LOG.md` | — | HA-0 | — |
| MIG-044/045/046 | 可选 | MOVE | 物理迁移：IGRF→models、Extras→models/extras、Pickup→analysis | 各自文件、注册表、docs | 路径变化 | HD-14 逐项批准 | 默认**不做** |
| MIG-047/048 | 可选 | — | TASK-039/040（面板化）、TASK-026（bcompress） | `src/plotting.jl`、IGRF 文件 | — | HD-12 | 默认不做 |

### 7.2 DAG

```text
HA-0 ─┬─ MIG-001 ─┬─ MIG-005 ─────────────────────┐
      │           └───────────────┐               │
      ├─ MIG-002 ─┬─ MIG-003 ─────┴─ MIG-000 ─────┤（HD-02 为软依赖）
      │           └─ MIG-004 ─────────────────────┤
      └─ [N] MIG-043, MIG-052                     ▼
                                   GATE-B / HA-1（同时需要 HD-07/08/09 已裁决）
   波1：MIG-010   MIG-011   MIG-012(仅E)   MIG-013   MIG-041
                     │          │
                     └──── MIG-015（选E时依赖012）
        MIG-010 + MIG-011 + MIG-015 (+012) ──► MIG-014（波1末尾）
   波2：MIG-014 之后：MIG-020、MIG-021、MIG-022、MIG-023、MIG-024、MIG-025、MIG-028（受文件锁约束，可并行）
        全部完成 ──► MIG-026（head shim）
                                   ▼
                          GATE-2 / HA-2
   波3：MIG-027 ──► MIG-030；   MIG-031；   MIG-032
   波4：MIG-040；  MIG-042(HD-10)；  MIG-050；  MIG-053 ──► MIG-051（最后） ──► HA-F
   可选：MIG-044/045/046（HD-14）、MIG-047/048（HD-12），插入时须遵守 §7.3 文件锁
```

### 7.3 文件锁（同一时刻只允许一个 MIG 持有；按序转移）

| 文件 | 持有顺序 |
|---|---|
| `common/MarsCommon.jl`、`common/marscommon/**` | 011 |
| `common/function_coordinate.jl` | 010 → 027 |
| `models/Pickup_ion.jl` | 010（第 4 行）→ 027（第 4 行）→ 030 |
| `MAVEN_data/MAVEN_plot.jl` | 015 → 021 |
| `MAVEN_data/MAVEN_load.jl` | 020 → 051 |
| `MAVEN_data/MAVEN_SWEA.jl` | 013 → 051 |
| `src/modules.jl` | 014（→ 020 如需登记 `adds_deps`）→ 040（→ 044） |
| `src/MarsData.jl` | 014 |
| `src/plotting.jl` | 028（→ 047） |
| `Magnetic_Model/IGRF_calculate.jl` | 022（→ 048 / 044） |
| `TW_data/TW_MINPA.jl` | 023 |
| `models/Single_Particle_Orbit.jl` | 024 |
| `calculate/calculate_models.jl` | 025 |
| `common/head.jl` | 026 |
| `common/data_keys.jl`、`.agent/03` 附录 A | 042 |
| `docs/src/**` | 050 → 053 |
| `test/runtests.jl` | 004；其后的追加须串行 |
| `validation/**` | 001 / 002 / 003 分属不同子目录；000 只写 `results/baseline` |

### 7.4 head.jl 兼容 shim 的精确约束（处置 M6）

| ID | 约束 |
|---|---|
| SH-1 | **不包含任何实现**：AST 统计 function 定义数为 0。 |
| SH-2 | **唯一的 `using` 是 `using MarsData`**。原 `head.jl:3-26` 的 20 余个 `using` **不保留**（是否保留由 HD-03 的子项决定，默认不保留）。 |
| SH-3 | 不包含任何 `include`；装载一律用 `MarsData.@load`，并保留原 `head.jl:29` 的守卫语义（只装尚未定义的名字）。**守卫检查的目标是 `@__MODULE__`**，即执行 include 的那个模块，不再是原文的 `Main`；include 目标就是 Main 时两者等价。（t11 并入 RR-A R-4）装载对象为 MAVEN_load、MAVEN_STATIC、MAVEN_SWIA、SP_load、Maxwellian_Distribution；另把 `MAVEN_plot` 绑定到 `MarsData.MAVEN_plot`。 |
| SH-4 | 旧裸名绑定集合包含迁移前 head.jl 的全部顶层名：函数、`label_data`、`print_f`、`norm2`、`searchsortednearest*`、`Package_path`。以 MIG-000 AST 基线为准；每个绑定写成 `const name = Mod.name`；`color_mapping` 绑定到 `MAVEN_plot.color_mapping_lut`。 |
| SH-5 | 不定义 SH-4 清单之外的任何名字。 |
| SH-6 | 若用户在 HD-03 中选择保留隐式 `using`，改为提供 `common/head_legacy_usings.jl` 作为**单独的 opt-in 文件**，shim 本身仍满足 SH-2。 |

**V-S 验证**：

| ID | 验证内容 |
|---|---|
| V-S1 | 分别在 **Main** 和**空 Module** 两种 include 目标中执行 `include("common/head.jl")`，旧名集合都须包含基线集合（AST 加运行时 `names` 双重核对）；两种目标下守卫都只检查 `@__MODULE__`。 |
| V-S2 | 抽样旧名的调用结果与基线 exact 一致。 |
| V-S3 | SH-1、SH-2 由 AST 断言。 |
| V-S4 | 重复 include 幂等。 |
| V-S5 | CHANGELOG 列出「不再隐式 `using`」的包清单。 |

---

## 8. Extras（杂项模型）规范

1. **两级分类**：
   - Registered Model（L4）：进注册表，自包含，只依赖 L1/L1n，有 Call Table 用例，入口进 allow。
   - Extra（X）：不进注册表，在 `models/CATALOG.toml` 登记。
2. **CATALOG 字段**：`name`、`file`、`purpose`、`status`（experimental / maintained / frozen）、`external_deps`（必须注明「装于全局环境或独立环境，永不进 `[deps]`」，采纳 S2）、`entry`、`owner_note`、`promotion_candidate`。
3. **调用方式**：显式 `include(joinpath(MarsData.project_root(), file))`。L0–L6 的任何注册模块都不得依赖 Extra。
4. **最低要求**：文件头一行说明；加载时不读写外部路径；不与注册模块重名。
5. **晋升条件**（满足任一即应晋升）：被 ≥2 处非脚本代码调用；被 Analysis 层正式入口依赖；用户要求对其结果做回归保护。晋升动作：包成 module、写注册表条目、补用例、登记 allow 与 `layers.toml`。
6. **冻结**：长期不用的注册模型标为 frozen，但不删除。
7. **磁场模型**：IGRF 逻辑上归 L4。物理迁移由 HD-14 决定。

---

## 9. 科学验证 backlog（长期交付物，处置 F-6；MIG-053 落为文档）

| ID | 事项 | 出处与方法（引用 t4 §3） | 容差 | 负责人 | 触发条件 | 状态 |
|---|---|---|---|---|---|---|
| SB-C6 | TW_MINPA `v3d` 密度归一化 `0.2/2`，未使用 `denergy` | 与 TW 官方 L2 矩逐点对比；比较两种口径 | 量级一致 | 裁决：用户；准备：pro-science | 获得 MINPA 官方矩或 IDL 源码 | 开放 |
| SB-C7 | MINPA 速度符号 | 转到 MSO 系后与官方及磁场横流方向一致性比对 | 符号一致 | 同上 | 同上 | 开放 |
| SB-C10 | SWEA shape 的 `13:64` 通道与模板 | `mvn_swe_calc_shape_arr.pro` 逐元素核对 | rel < 1e-12 | 同上 | 获得 SPEDAS 源码 | 开放 |
| SB-C11a / SB-C11b | SWIA 密度系数 `7.2245…e-7`、`8.8` | 量纲推导，并与 SPEDAS 常数比对 | rel < 1e-6 | 同上 | 同上 | 开放 |
| SB-C12 | SWEA PAD 的 NaN 互填 | `mvn_swe_pad_180.pro`，三种策略对比 | 策略一致 | 同上 | 获得 SPEDAS 源码与 PAD 文件 | 开放 |
| SB-C13 | CDF RV 判定 `flags & 1` | CDF 规范；在实际文件上统计 flags 分布 | 规则一致 | 同上 | 获得真实 CDF 文件 | 开放 |
| SB-D08 | TASK-008 真实数据 golden 基线 | 一日 `load_MAVEN_data` | exact | 执行：flash-validation | 数据盘可用 | 开放（不阻塞） |
| SB-D21 | `:adaptive` 追踪方法 | DLL 符号可用后补用例 | rtol 由用户定 | pro-science | DLL 提供 `MAIN_mp_ADAPTIVE_STEP_TRACE` | 阻塞 |
| SB-D13 | `bench_05` 真实文件列表 | 索引命中与旧回退路径一致 | exact | flash-validation | 获得 `filename_lists.json` | 开放 |
| SB-STA | `sta_v_4d` 与 `_new` 是否收编 | §6.3 B-STA 证据 | rel ≤ 1e-9 | 用户 | TASK-044 立项（下一轮） | 只出证据 |
| SB-K | `KeV_PER_AMU` 实为质子质量；SWIA 假定全为质子 | 文档标注 | — | 用户 | 文档同步时 | 记录 |
| SB-NOOP | 无操作参数（`m_int`、`energy_range`） | API 文档显著标注 | — | MIG-050 | 文档同步时 | 记录 |
| SB-CONST | μ0 / e 新值影响派生量口径 | 文档标注 | — | 用户 | 文档同步时 | 记录 |
| SB-ESC | `escape_energy` 在 `planet≠"Mars"` 时 `v` 未定义，抛 `UndefVarError`（已知潜在 bug；t11 并入 RR-S R-1） | 原样保留；API 文档显著标注；是否修复由用户决定，修复属于行为变更，须单独批准 | — | 用户 | 文档同步时，或任何 MIG 触及该函数时 | 记录（不修） |

---

## 10. 待人工决策项（H 项与 U 项合并去重为 HD-01…HD-15）

| HD | 事项 | 来源 | 选项 | 本文件建议 | 阻塞的环节 |
|---|---|---|---|---|---|
| HD-01 | 依赖清单 16→45 | H-1 / D-1 | A 收敛 / B 接纳 / C 净化 | 倾向 A；策略 P 在三个分支下都成立 | 不阻塞 MIG；影响 FA-7 的文本 |
| HD-02 | 工作区快照提交 | H-2 / R-1 | 提交 / 只读副本 | 建议先提交 | MIG-000（软依赖） |
| HD-03 | head.jl 按能力拆散；shim 是否保留隐式 `using` | H-3 / M6 | 拆散加 SH-1…5 / MarsUtils 整体包化；隐式 using：不保留（默认）/ opt-in 文件 | 拆散，不保留 | HA-0 |
| HD-04 | 火星边界与环境函数 | H-4 / M1 / M2 | **C** 并入 MarsCommon / **E** 独立 MarsEnvironment（预装） | 两套方案都已闭合，不替用户选择（t6 倾向 C，草案原立场 E） | HA-0 |
| HD-05 | 策略 P：MarsCommon（及选 E 时的 MarsEnvironment）改为 `:preloaded` | M1（新） | 采纳 / 否决（接受双实例并声明数值等价） | 采纳 | MIG-014 |
| HD-06 | calculate_models 解体并保留一个周期的门面 | H-5 | 执行 / 保留原状 | 执行（deps 按 §3.6） | HA-0 |
| HD-07 | cyclotron 三套体系的处置 | U-1 / F-1 | (a) 独立命名 / (b) 冻结不转发 / (c) 换算包装 | (a)，名称由用户定 | GATE-B |
| HD-08 | `sta_v_4d` 与 `_new` 的证据处置；`println` 是否改 `@warn` | H-12 / U-2 / F-2 / F-7 | 只出证据 / 收编（下一轮）；println 保持 / 改 | 只出证据，保持 println | GATE-B |
| HD-09 | `color_mapping` 命名 | U-4 / F-3 | 改名 `color_mapping_lut` / 等价前提下保留原名 | 改名 | GATE-B |
| HD-10 | `:mass` 等 DataKeys 增补 | H-10 / U-3 / F-4 | (a) 单一 `MASS=:mass`，附录 A 按生产模块注释语义 / (b) 带生产者前缀的名字；**禁止**同值无前缀的双常量 | (a) | MIG-042 |
| HD-11 | C 类疑点与 backlog | H-11 / U-5 / F-6 | 用户逐项裁决 | 只原样搬运，backlog 见 §9 | HA-F |
| HD-12 | 范围扩展（TASK-026、TASK-039/040） | H-9 | 纳入 / 不纳入 | 不纳入 | 无 |
| HD-13 | 弃用转发是否发 depwarn | H-13 | 发 / 不发 | 不发 | 无 |
| HD-14 | 物理迁移与「不移动文件」红线 | H-6 / H-7 / H-8 / H-14 | 逐项批准 MIG-044/045/046 | 都不做 | 无 |
| HD-15 | L2→L3 兼容转发的方式 | M4（新） | eager_dep（临时 deps）/ 冻结双实现直到移除 | eager_dep | MIG-020 |

**审批点**：

| 审批点 | 时机与内容 |
|---|---|
| **HA-0** | 审批本文件，以及 HD-01、03、04、05、06（HD-02 建议同时裁决）。**批准前不施工。** |
| **HA-1** | GATE-B 时确认验证框架、基线、审计表，以及 HD-07/08/09 的裁决。 |
| **HA-2** | GATE-2 时确认去重转发的等价证据。 |
| **HA-F** | 最终架构审查；确认「合成回归 ≠ 科学正确」的边界声明与 backlog。 |

---

## 11. 审查意见处置表

本节第一张表的「处置」列来自 t8 的修订。t9/t10 已对这些处置做了**文档层面**的独立复核，结论是 M1–M6、S1–S8、F-1–F-8 全部在方案层面闭合（见 §11.1）。文档复核通过**不等于**用户批准，也**不等于**实施测试通过。

| 意见 | 严重度 | 处置 | 落点 |
|---|---|---|---|
| M1 实例一致性与预装转发解析 | blocker | 引入 I-1…I-5；策略 P（HD-05）及其否决分支；说明与装载机制红线、L0 轻量、D-1 三分支的关系；给出 V-I1…5、V-F1…3 | §3.1–3.3、§3.7 |
| M2 L1→L4 违例 | high | 删除 FC 的 `bowshock_zero` 且不转发；旧名由 L6 绑定；矩阵注明 L1→L4 无例外 | §2.2、§4.2、MIG-027 |
| M3 MarsEnvironment 的 deps | high | 改为 `[:constants, :MarsCommon]`；门面及其他模块的 deps 一并补全 | §3.6 |
| M4 compat 转发的装载解析 | high | 限定 nested / eager_dep 两种模式，禁止惰性装载；`compat_edges` 增加 `resolve`、`adds_deps` 字段；补 AST 规则；定义遗留路径的错误语义 | §3.4、§3.6 |
| M5 DAG 与波次不一致 | medium | 单表加波次列；DAG 重画；041 归波 1，040/042 归波 4，043/052 归非关键轨 | §7.1、§7.2 |
| M6 shim 的 using 冲突 | medium | 精确约束 SH-1…SH-6、V-S1…5；隐式 using 交给 HD-03 | §7.4 |
| S1 子文件拆分 | 建议 | 采纳：由 `MarsCommon.jl` 统一 include；所有自包含方装载冒烟 | MIG-011 |
| S2 CATALOG 的 `external_deps` | 建议 | 采纳 | §8-2 |
| S3 逻辑层与物理位置两维 | 建议 | 采纳 | §2.4 |
| S4 MIG-014 的 `note` | 建议 | 采纳 | §5-3、MIG-014 |
| S5 孤儿 docstring oracle | 建议 | 采纳 | §6.2 |
| S6 文件锁补全 | 建议 | 采纳 | §7.3 |
| S7 MIG-004 默认跳过 | 建议 | 采纳 | MIG-004 |
| S8 MIG-000 编号与软依赖 | 建议 | 采纳 | §6.1、§7.2 |
| F-1 cyclotron 参数体系 | 高 | 禁止裸 alias；三个选项交 HD-07；MIG-005 须给出四项结论 | §4.4 |
| F-2 `sta_v_4d` 前置条件 | 中 | EQ-STA-1/2 写明「已含 `:df`」及类型前置条件；PRE-STA-1 归入前置条件差异 | §6.3 |
| F-3 `color_mapping` 遮蔽 | 中 | 改名 `color_mapping_lut`，加 AST 遮蔽断言；HD-09 | §4.5 |
| F-4 `:mass` 同值常量 | 低-中 | 禁止同值无前缀双常量；HD-10 的选项 (a)/(b) | §5-4、HD-10 |
| F-5 NaN 位置敏感 | 中 | 默认 `positional`；报告数量与位置；新增 NaN 一律失败；`science_sensitive` 禁用 `ignore` | §6.3 |
| F-6 科学验证 backlog | 低 | §9 表格，含负责人与触发条件；MIG-053 | §9 |
| F-7 println 副作用 | 低 | SE-STA-2 `prints` 用例；改 `@warn` 须经 HD-08 | §6.3 |
| F-8 oracle 副本数 | 低 | 改为精确计数表，复测时不得放宽 | §4.1 |

### 11.1 最终独立复核（t9 RR-A / t10 RR-S）意见处置与三类状态

**A. 复核新提出的澄清项（t11 并入）**

| 意见 | 来源 | 严重度 | t11 处置 | 落点 | 状态 |
|---|---|---|---|---|---|
| R-1 eager_dep 守卫位置写作「文件顶层」，有歧义 | t9 | 非阻塞 | 改为「**模块体顶层**」，并注明不得放在 `module` 声明之前，原因是那里的 `@__MODULE__` 是 include 目标模块 | §3.4 eager_dep 行 | 已并入 · 待第二轮复核确认措辞 |
| R-2 §3.1 与 §3.3 依赖描述时态不一致 | t9 | 非阻塞 | §3.1 第 5 点改为「现状只有 StaticArrays；拟改（MIG-011 后）增加 Statistics/LinearAlgebra/Dates」；§3.3 PL-1 行标明「拟改状态」 | §3.1-5、§3.3 PL-1 | 已并入 · 待第二轮复核确认措辞 |
| R-3 nested 在直接 include 下照常工作的保证需按子模式限定 | t9 | 非阻塞 | 拆为 `nested:self_include`（直接 include 照常）与 `nested:dep_parent`（只经 `load_module` 可用：IGRF/SPO/TW_MINPA）；`resolve` 字段增加这两个取值；V-F3 限定适用范围 | §3.4 遗留路径段、compat_edges 字段、§3.7 V-F3 | 已并入 · 待第二轮复核确认措辞 |
| R-4 SH-3 守卫检查的目标未明确 | t9 | 非阻塞 | 明确检查 `@__MODULE__`（include 目标是 Main 时与原文等价）；V-S1 同时覆盖 Main 与空 Module 两种目标 | §7.4 SH-3、V-S1 | 已并入 · 待第二轮复核确认措辞 |
| R-1 `escape_energy` 已知潜在 bug 的注记丢失 | t10 | 低 | 在 §4.2 补注「planet≠Mars 时 v 未定义，原样保留并记录，不修」；B-DUP 增加 throws 用例；§9 新增 SB-ESC | §4.2 环境函数表、§9 SB-ESC | 已并入 · 待第二轮复核确认措辞 |
| R-2 TimeFormat 两版格式字面量需逐字采集（可选） | t10 | 可选 | 采纳：MIG-005 审计表逐字照录两版实现，作为 `format` 选项与 MIG-024 的唯一依据 | §4.4 末、MIG-005 行 | 已并入 · 待第二轮复核确认措辞 |

t11 判断：以上 6 项都是澄清，没有改变架构核心、依赖矩阵、HD 选项与建议、MIG 拆分或范围。未发现需要实质变更的问题。

**B. 三类状态（严格区分，不得混用）**

| 类别 | 内容 | 当前状态 |
|---|---|---|
| ① 文档复核通过（方案层） | M1–M6、S1–S8（t9 RR-A 复核）；F-1–F-8（t10 RR-S 复核）；RR-A 机械核对（策略 P 不需要改动机制、eager_dep 不成环、别名行插入位置可行、PL-1 在 D-1 分支 A 下成立）；RR-S 七点源码核实 | **通过（文档层面）**。上表 A 中 t11 并入的 6 项措辞尚待第二轮确认 |
| ② 人工待决 | HD-01…HD-15，其中 HA-0 必须裁决 HD-01、03、04、05、06（HD-02 建议同时裁决）；HA-1 前须裁决 HD-07、08、09；HD-10 在 MIG-042 前；HD-11 在 HA-F 前；HD-15 在 MIG-020 前 | **全部未裁决**。专家倾向不视为用户批准 |
| ③ 尚未运行的实施测试 | V-I1…5、V-F1…3、V-R1/2、V-S1…5、B-025/004/018/022/003/STA/CYC/DUP/INST、MIG-005 审计（含 TimeFormat 逐字采集）、§4.1 oracle 复测、MIG-020 装载开销测量、AST 自检 | **全部未运行，不构成任何通过证据**。在 HA-0 批准、Phase B 交付之后才能执行 |

**科学正确性边界不变**：合成回归不等于科学正确；SB-C6…C13、SB-D08/D21/D13、SB-ESC 均为开放、阻塞或仅记录状态，由用户裁决。

---

## 12. 尚需独立复核的修订点（t6、t7 的结论不能作为本修订版的通过证明）

| 复核方 | 必须复核的修订点 |
|---|---|
| **pro-architecture**（复核 RR-A） | 1. §3 的实例语义 I-1…I-5，以及策略 P 是否真的无需改动装载机制（对照 `modules.jl:347-363`）。<br>2. G-include 在三种装载场景下的正确性，以及它对 `validate_registry` warning 的影响。<br>3. nested / eager_dep 两种转发模式与遗留直接 include 路径的错误语义。<br>4. eager_dep 带来的 L2→L3 临时边是否成环、是否带来不可接受的装载开销。<br>5. HD-04 两套方案的依赖闭合。<br>6. §7 的 DAG、文件锁，以及 Pickup_ion 三次持锁的安排。<br>7. SH-1…SH-6。<br>8. PL-1 与 D-1 三个分支的关系。 |
| **pro-science**（复核 RR-S） | 1. §4.4 中 cyclotron 的选项及「浮点运算顺序不同、不能逐位一致」的判断。<br>2. B-STA 五个用例的前置条件与副作用断言；其中 `STA_count2df` 是否写入输入，须以实测为准。<br>3. NaN 的 positional 策略与报告字段。<br>4. HD-10 的 (a)/(b) 选项。<br>5. §9 backlog 的完整性。<br>6. §4.1 计数作为 oracle 是否足够。<br>7. 方案 C/E 下 bowshock/magnetopause 两份副本的等价门禁。 |
| **双方共同** | 确认 §11 每一项的处置充分。**未经复核前，§11 的状态保持「待独立复核」，不得改写为「通过」。** |

复核可以与人工 HA-0 审查并行进行。复核提出的必改项，须在 HA-0 批准前并入本文件。

**进展**：RR-A（t9）与 RR-S（t10）已完成，结论为文档层面通过，并提出 6 条澄清，已由 t11 并入（§11.1）。**仍需复核的只剩一项**：§11.1 表 A 中 6 处措辞是否准确落实了复核意图。可由两名 Pro 做轻量确认，也可由人工在 HA-0 时一并审阅；这项确认不阻断 HA-0。

---

## 13. 施工组织建议（含队长最多 8 Agent；只在 HA-0 之后启用）

| 槽位 | 角色 | 现状 | 实施期职责 | 写入范围 |
|---|---|---|---|---|
| 1 | captain | 在岗 | 调度、文件锁、证据汇总；不编码 | `.agent/` 状态文档 |
| 2 | chief-architect | 在岗 | 审定 GATE-B、GATE-2、HA-F 的架构部分；审查 `layers.toml` 与 MIG 清单的变更；不编码 | 架构文档 |
| 3 | pro-architecture-official | 在岗 | RR-A 复核；审查每个 MIG 的 AST diff 与实例断言 | 只写审查文档 |
| 4 | pro-science-official | 在岗 | RR-S 复核；审查 MIG-005 与所有 `science_sensitive` 的 MIG；批准容差或 NaN 策略的例外 | 只写审查文档 |
| 5 | flash-recovery → 转为 flash-validation | 在岗 | 波 B：MIG-001、002、003、004、000 | `validation/**`、`test/runtests.jl`（004） |
| 6 | deepseek-code-ustc-1 | 在岗 | 非关键轨：MIG-043、052；MIG-050、053 的文档草稿 | 各自 Owned |
| 7 | **pro-code-official-1**（新增名额） | 待加 | 复杂迁移：MIG-011、014、020、023、026、027、030 | 按文件锁 |
| 8 | **flash-code-official-1**（新增名额） | 待加 | 常规迁移：MIG-010、012、013、015、021、022、024、025、028、031、032、040、041、042、051 | 按文件锁 |

- **实现与审查分离**：代码实例不审查自己的 MIG；Pro 审查实例不写代码。
- **并行上限**：波 1 最多 2 条实施线加 1 条验证线；波 2 受文件锁约束；不同实例的写入范围必须互斥。
- **汇报驱动**：完成、阻塞或需要决策时主动汇报，不轮询。
- **慢渠道**：ustc 实例不放在关键路径上；转交前先撤销原所有权。
- **名额调剂**：GATE-2 之后，验证工作可以并入 flash-code，把释放出的名额给第二个 pro-code。

---

## 14. 合规声明

- 只写了 `.agent/target_architecture_final.md` 这一个文件。未改动代码、测试、配置、`Project.toml`/`Manifest.toml`、`new_plan.md`、草案、审查文件，或其他成员的交付物。
- 只执行了只读命令（`git show HEAD:Project.toml`）和定向读取或 grep。未运行测试，未写仓库，未创建子 Agent，未轮询成员。
- **本文件不授权施工**：须经 HA-0 人工批准和 RR-A、RR-S 复核之后，才由队长分派。
- t11 修订：只修改了本文件中 §3.1、§3.3、§3.4、§3.7、§4.2、§4.4、§7.1（MIG-005 行）、§7.4、§9、§0.1、§11、§11.1（新增）、§12，以及文件头。未改源码、测试、配置，未创建子 Agent，未轮询。
