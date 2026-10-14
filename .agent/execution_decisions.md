# execution_decisions.md — 人工裁决（HD-01…HD-15）落地为「无旧兼容」架构执行规格

> 任务：t2 [decisions]「将人工裁决修订为无旧兼容架构执行规格」（团队 `marsdata-flash-execution`）
> 执行：official-reviewer（裁决落地、架构修订与独立代码审查）— attempt 1 / `e19427ea-89eb-4438-9913-40ee89c489b5`
> 日期：2026-10-14（Asia/Shanghai）
> **接续基线（唯一权威）：`46db822425378d4ad99f8f0b7cfed07360118486`**（父 `fda2adae893f4367a4e86079e24d57bb6e545997`）；来源与核验见 `.agent/execution_snapshot.md`（t1）。
> 输入（全部已读）：`.agent/审计结果.md`（19 行，用户裁决原文）、`.agent/target_architecture_final.md`（704 行，历史最终审定档案）、`.agent/execution_snapshot.md`（t1 接续快照）、`.agent/planning_archive_handoff.md`、团队任务合同 t3/t4/t5/t6/t7/t8/t9/t10。
> 写入范围：**只写本文件**。本任务不修改、不覆盖、不删除任何历史审定文档（`target_architecture_final.md`、`target_architecture_draft.md`、`*_recheck.md`、`审计结果.md`、`execution_snapshot.md` 一律保持原样），不改任何科研源码、`Project.toml`/`Manifest.toml`、测试、配置或 `docs/`。
> 状态：**文档层规格**。本文件不授权施工；本轮授权范围见 §0.3。

---

## 0. 使用说明、优先级与授权边界

### 0.1 引用与优先级（发生冲突时按此顺序）

| 级别 | 来源 | 效力 |
|---|---|---|
| P0 | `.agent/审计结果.md`（用户裁决原文，HD-01…HD-15 + 尾注） | **最高**。可直接推翻旧专家建议、旧草案与 `target_architecture_final.md` 的推荐项 |
| P1 | 团队合同与本规格 §2、§3（对 P0 的执行解释） | 执行口径；与 P0 冲突时以 P0 为准并上报 |
| P2 | `target_architecture_final.md`（历史最终审定档案） | **仅作为历史与细节来源**；凡被 P0/P1 修订者失效（覆盖清单见 §4） |
| P3 | `target_architecture_draft.md`、`*_expert_analysis.md`、`*_draft_review.md` | 只作背景，不作依据 |

**旧专家倾向、文档复核结论、Pro/Claude 意见一律不等于用户批准**（沿用 `target_architecture_final.md` §11.1 的立场）。

### 0.2 标记约定

| 标记 | 含义 |
|---|---|
| 【裁决】 | 用户原文直接给出的决定；本文件只做落地解释 |
| 【规格】 | 本文件对裁决的执行解释（由裁决派生，可被队长/用户改口径） |
| 【实测】 | 本次会话当场执行的只读测量结果，带文件与行号 |
| 【待确认】 | 需要队长或用户确认的解释点/边界问题，未确认前不得据以施工 |
| 【原样保留】 | 历史文档在本文中仅被引用，不被改写 |

### 0.3 本轮授权边界（重要，先读）

- 首次审批**不授权越过基线门禁进行全量函数迁移**。本轮（首批）只包含：
  1. 接续 Git 快照（t1，**已完成**：`46db822`）；
  2. 无旧兼容架构修订（本文件 + `target_architecture_execution.md`，t2）；
  3. 路径审计（HD-14 前置，t4）与 STATIC 科学契约审计（HD-10/HD-11，t3）；
  4. 依赖收敛到原 16 项（HD-01 A，t6 合同 → t7 实施 → t8 独立验证 → t9 独立审查）；
  5. 小粒度迁移 DAG（t5 产出 `.agent/execution_task_breakdown.md`；本文件只给骨架与约束）。
- **不在本轮内**：AST/Call Table 工具的构建与基线冻结、权威函数迁入/移除、注册表策略 P 落地、物理移动、文档终审、任何 `.jl` 科研源码修改。
- 报告驱动：成员只在完成、阻塞或需要决策时汇报，不轮询、不启用自动目标、无子 Agent、**不使用 Claude/Pro 作为审批方**（审查角色规则见 `target_architecture_execution.md` §8）。

### 0.4 三类状态（严格区分，不得混用）

| 类别 | 内容 | 当前状态 |
|---|---|---|
| ① 文档层已裁定/已修订 | HD-01…HD-15 全部有用户裁决；本规格已把裁决落到执行口径 | **本文件即交付** |
| ② 待实施 | 依赖收敛执行、审计、迁移、注册表、文档同步 | 未开始（t6–t10 排队中） |
| ③ 待实测 | 全部数值/副作用/装载/测试证据 | **零通过证据**；缺证据一律不算通过 |

---

## 1. 裁决登记表（`.agent/审计结果.md` 逐条引用与落地）

引用格式：`审计结果.md:L<行号>`。裁决原文以引号内文字为准。

| HD | 原文（行号） | 落地解释 | 影响分类 |
|---|---|---|---|
| HD-01 | “HD-01：A”（L1） | 依赖清单从现状 45 项**收敛到原 16 项**（A 分支）；不改源码、不回滚 P6 成果 | 依赖/环境；不破坏科学行为 |
| HD-02 | “HD-02: 使用git快照”（L2） | 接续基线固定为 `46db822`；一切基线对照、哈希、diff 以该提交为锚 | 流程 |
| HD-03 | “HD-03：按能力拆分”（L3） | `common/head.jl` 按能力拆分（数学/几何→MarsCommon，绘图标签与色标→MAVEN_plot，其余按归属）；**取消旧 shim 兼容绑定** | 破坏性 API（脚本层裸名） |
| HD-04 | “HD-04：采纳E，”（L4） | 火星边界与环境函数独立为 `MarsEnvironment`（L4，预装），不并入 MarsCommon | 新增模块；科学行为保留 |
| HD-05 | “HD-05：采纳策略p”（L5） | 策略 P 采纳：`MarsCommon`（及 `MarsEnvironment`）注册项改 `kind=:preloaded` 并绑定到 `MAVEN_plot` 内既有实例；装载机制代码零改动 | 可观察行为变化（已获批准） |
| HD-06 | “HD-06：采纳，但是不需要考虑兼容周期”（L6） | calculate_models **解体**，且**不设兼容周期**：不保留以转发为目的的旧门面，旧名删除、调用点直接改到新权威 | 破坏性 API；科学行为须 exact 保留 |
| HD-07 | “HD-07：a”（L8） | cyclotron 取选项 (a)：在 MarsCommon 用**两个独立名字**逐字复制 kg 体系实现（暂定名 `cyclotron_frequency_kg(B; mass)`、`cyclotron_radius_velocity(v, B; mass)`，最终名待用户定） | 新增 API；跨体系不得混算 |
| HD-08 | “HD-08：sta_v_4d_new为早期性能测试代码，建议直接移除sta_v_4d_new”（L9） | **删除 `sta_v_4d_new`（含 docstring）**；这是本轮唯一被明确授权的「删实现」例外；`sta_v_4d` 的其他行为不得受影响 | 破坏性 API + 证据面收窄 |
| HD-09 | “HD-09：采纳，但是可以不考虑兼容”（L10） | `color_mapping` 改名 `color_mapping_lut`，**旧名不保留**（不转发、不 alias） | 破坏性 API；科学行为保留 |
| HD-10 | “HD-10：…建议在STATIC处直接使用constants.mp_eV_per_km_s2，并在STATIC计算等离子矩的地方备注标明：我们不使用数据包自带的dat[:mass]是因为这个和constants.mp_eV_per_km_s2完全等效”（L11） | STATIC 等离子矩代码改用 `constants.mp_eV_per_km_s2`，并在该处加等效性备注；`dat[:mass]` 的物理量解释（单位特定质子静止质量）为**授权契约**，但类型/数值变化仍必须实测 | 科学常量来源（须实测） |
| HD-11 | “HD-11：保留，但是可以加注释，说明这一点。MINPA涉及到数据处理仍然不规范，其他同理”（L13） | C 类疑点与 backlog **保留原值**并加注释；**MINPA 保持不规范状态**，不得把 STATIC 的 `:mass` 解释机械外推 | 科学边界（不修） |
| HD-12 | “HD-12：不加入。不需要面板化”（L14） | TASK-026、TASK-039/040 不纳入；不做面板化 | 范围 |
| HD-13 | “HD-13：不发，在文档中标注即可，由使用者自行适配”（L15） | **不发 depwarn**；破坏性变更只在文档/CHANGELOG 标注，由使用者适配 | 流程/文档 |
| HD-14 | “HD-14：可以移动，但是需要先全局查找是否有程序依赖它们的路径，以及它们对其他相对路径的调用，潜在问题可在测试里被纠正”（L16） | 物理移动**允许**，但必须先做全局路径审计（依赖这些路径的程序 + 它们自身的相对路径调用），问题在测试中纠正 | 路径/装载；科学行为保留 |
| HD-15 | “HD-15：取消兼容”（L17） | **取消兼容转发**：不做 `eager_dep`、不做冻结双实现、不做旧名 alias/wrapper；旧名删除、调用点更新 | 破坏性 API |
| 尾注 | “注：DSH的工具中预装了复制粘贴工具…如果可以直接移动特定行到特定位置，那就直接用，如果是整个文件，那么建议写一个简单的python脚本让agent调用，以此减轻token消耗”（L19） | 操作建议：优先用可见的精确文件工具做行级搬迁；整文件搬迁可写简单 Python 助手，但必须满足绝对路径核验、哈希前置、不覆盖目标、dry-run、失败回退（t5 描述）；**不得假定存在未经验证的行剪切接口** | 工具纪律 |

**总纲**：HD-01/02/04/05 保留目标架构主干；**HD-03/06/09/13/15 共同构成「无旧兼容」修订**（旧名、旧 shim、旧门面、旧转发、depwarn 全部取消）；HD-07/08/10/11 是四条明确的科学/实现例外；HD-12/14 是范围与路径纪律。

---

## 2. 无旧兼容修订总则（六条铁律）

| ID | 规则 | 依据 |
|---|---|---|
| **R-1** | **取消兼容 = 旧名消失**。禁止：同名转发、`const Old = New` 别名、换算包装、`depwarn` 兼容路径、旧 shim 绑定、旧门面转发、`eager_dep` 临时依赖边、冻结双实现 | HD-06/09/13/15 |
| **R-2** | **迁移原子性**：一个函数/一组函数的迁移必须在**同一个迁移单元**内完成「新权威就位 → 全仓调用点更新 → 旧定义与旧名删除 → 断言与测试」。禁止留下「新权威已存在但旧名仍是唯一入口」或「旧名已删但调用点未改」的中间态 | 【规格】由 R-1 + 装载冒烟要求派生 |
| **R-3** | **破坏性 API 变更显式登记**（§5），**科学行为必须保留**（§6）。二者的区分是本规格的核心交付：改名/移动/删除属于 API 面；数值、类型、单位、副作用（就地写入、stdout）、NaN 位置属于科学行为面 | 裁决 + 任务合同 |
| **R-4** | **删实现的例外唯一**：只授权删 `sta_v_4d_new`（HD-08）。其他任何「删函数体/删文件/删基准」都必须有单独的用户裁决或队长书面授权 | HD-08 |
| **R-5** | **禁止机械外推**：HD-10 的 `:mass` 解释只适用于 STATIC；MINPA 与 SWIA 的代码不得据此改动（MINPA 另按 HD-11 保持现状）。同一符号在不同生产者处含义不同时，必须先审计再决定 | HD-10/11 + 队长合同 |
| **R-6** | **未实测即未通过**。文档复核、专家意见、AI 推理均不构成通过证据。缺真实数据/DLL 的项只能记「开放/阻塞」，不得伪造或记为通过 | 全程纪律 |

---

## 3. 逐条落地细则

### 3.1 HD-01 = A：依赖收敛到原 16 项

**已定契约（队长已分派，t6–t10）**

| 项 | 内容 |
|---|---|
| 参考来源 | `94da314aba65c8a129c1883931872db6198044c6` 的 `Project.toml`/`Manifest.toml`（16 项：CairoMakie, ColorTypes, DataFrames, DataInterpolations, Dates, DelaunayTriangulation, IniFile, JSON, LaTeXStrings, LinearAlgebra, Makie, ProgressMeter, StaticArrays, Statistics, TOML, TimesDates）【实测：`execution_snapshot.md` §5.2 已录；本会话复核现状 `Project.toml` `[deps]` 共 45 项，行 7–51】 |
| 实施方式 | **只恢复根 `Project.toml` 与 `Manifest.toml` 到 94da314 的对应 blob**；**不改源码、不回滚 P6 成果**(t6/t7) |
| 验证 | `git diff --exit-code 94da314 -- Project.toml Manifest.toml` + `julia --project=. test/runtests.jl`（t7 实施自证，t8 独立重跑，t9 独立审查） |
| 禁止 | `Pkg.add`/`Pkg.develop` 救场、修改全局环境、修改 `benchmark` 环境、把缺依赖失败改写成「通过」 |

**【规格】收敛后的必查项（新增，供 t6/t7/t8 采用）**

1. **依赖来源必须逐包登记来源**：根 Project / 全局环境（`@v1.10` 等默认环境在 `LOAD_PATH` 中）/ 标准库。仅由全局环境满足的包必须显式记录为「不可复现风险」，不得写成「已声明依赖」。
2. **风险已知且必须实测**：现状源码中存在大量**不在 16 项内**的 `using`【实测，见 §7 R-1】，至少含 `CommonDataFormat`、`JLD2`、`FortranFiles`、`Rotations`、`DifferentialEquations`、`CSV`、`DSP`、`GeometryBasics`、`GLMakie`、`Interpolations`、`LsqFit`、`Optim`、`QuadGK`、`SparseArrays`、`SpecialFunctions`、`BenchmarkTools`。收敛后这些 `using` 是否仍可解析，必须由实测回答，**不得预设成功**。
3. **测试计数不得硬锁**（见 §7 R-7）：`runtests.jl` 的新计数由 t7/t8 现场实测；任何相对历史值的增减都必须逐条列出增/删/合并的用例。
4. **不做源码 `using` 清理**（t6 已定边界）：若收敛导致某文件无法装载，结论是**如实报告 + 请求合同修订**，不是改源码，也不是装包。
5. 收敛后本批不得推送（不 push、不部署）。

### 3.2 HD-02 = 使用 git 快照

- 基线提交：`46db822425378d4ad99f8f0b7cfed07360118486`（内容：`.agent/execution_snapshot.md` + `.agent/审计结果.md`，2 files / +202 / −0）。
- 【规格】所有「迁移前/迁移后」对照必须写明锚点提交（`46db822`）与工作区状态；工作区当前存在 1 处**预期内未提交修改**（`execution_snapshot.md` §7 回填），由 t10 补记提交，**其他成员不得代为提交或回退**。
- 【规格】`.agent/审计结果.md` 与 `execution_snapshot.md` 不得改写、删除或另存覆盖。

### 3.3 HD-03 = 按能力拆分（并取消旧 shim）

- 【裁决】`common/head.jl` 按能力拆分。
- 【规格】拆分的落点沿用 `target_architecture_final.md` §4.2 的权威表：数学/几何/统计工具与 `searchsortednearest*` → `MarsCommon`；绘图标签与色标（`label_data`、`print_f`、`norm2`、`get_log_ticks`、`color_mapping_lut`）→ `MAVEN_plot`；`Package_path` 之类路径量 → `Paths`/`paths.jl`；无归属者按最近能力层落位。
- 【规格】**取消旧 shim**：不实现 `target_architecture_final.md` §7.4 的 SH-1…SH-6 兼容 shim（旧裸名绑定集合、`head_legacy_usings.jl` opt-in 一并不做），不发 depwarn（HD-13）。
- 【实测】仓库内**只有一处** `.jl` 引用 head.jl：`models/Pickup_ion.jl:3` `include("../common/head.jl")`；其余引用都在文档/CHANGELOG 中。因此仓内断裂面很小，但**外部/笔记本使用者会断裂**——按 HD-13 只做文档标注。
- 【待确认】**`common/head.jl` 文件本身的去留**：(i) 删除文件（推荐，遵循 R-1），(ii) 保留一个不含任何旧名绑定、仅 `using MarsData` + `@load` 的装载入口。该选择改变一个公开入口点，须队长/用户定；未定前不得施工。

### 3.4 HD-04 = E：独立 `MarsEnvironment`

- 【裁决】采纳方案 E。
- 【规格】新建 `models/Mars_Environment.jl`（L4，纯函数、无状态，G-include 复用 MarsCommon）；注册表新增 `:MarsEnvironment`（`kind=:preloaded`，`deps=[:constants, :MarsCommon]`）；`src/MarsData.jl` 增加 `const MarsEnvironment = MAVEN_plot.MarsEnvironment`。
- 【规格】迁入集合：`bowshock`、`magnetopause`、`bowshock_km`、`bowshock_zero`、`get_bowshock_normal`、`mars_sun_dist_phys`、`escape_energy`。
- 【原样保留】`escape_energy` 在 `planet≠"Mars"` 时 `v` 未定义的既有缺陷**原样保留**、加注释、记 backlog（HD-11 精神），不修。
- 【规格】`bowshock_zero` 从 `FunctionCoordinate` **删除且不转发**（L1→L4 无例外保持不变）。
- 【规格】`bowshock`/`magnetopause` 两份副本（`MAVEN_plot` 与 head.jl 系）合并前必须逐点等价；不等价则以不同名字分别保留并上报，**不得强行合并**。

### 3.5 HD-05 = 策略 P

- 【裁决】采纳策略 P。
- 【规格】`src/modules.jl` 注册表：`:MarsCommon` 的 `kind` 改为 `:preloaded`（`path`/`deps`/`allow` 不变）；选 E 时新增 `:MarsEnvironment`（`:preloaded`）；`src/MarsData.jl` 在 `using .MAVEN_plot` 之后加 `const` 别名行。
- 【规格·红线】`_carrier`、`load_module`、`@load`、`:preloaded` 分支、`ModuleLoadError` 的**机制代码一律不改**；只允许改注册表数据与 validate 校验。此项是可观察行为变化，已由 HD-05 授权。
- 【规格】`constants` 豁免 I-4（保持非预装），理由是 `test/runtests.jl:350` 的 `@test !isdefined(MarsData, :constants)` 隔离断言【实测：行 350 存在；同文件 351/352 为 Main/ScratchBlank 对应断言】。

### 3.6 HD-06 = calculate_models 解体，无兼容周期

- 【裁决】采纳解体，且**不考虑兼容周期**。
- 【规格·R-1 应用】不保留以转发为目的的旧门面：`calculate_models` 迁出的每个函数，在旧模块的旧名**删除**，调用点直接改到新权威（如旋转函数 → `FunctionCoordinate`；`Linear_fit`、AMU/eV 体系 cyclotron → `MarsCommon`；边界与环境 → `MarsEnvironment`）。
- 【规格】`calculate_models` 残余内容（不属于任何更合适能力模块的函数）保留原位；注册表条目与 `deps` 按其实际内容更新（不得用 `adds_deps` 之类的临时兼容边）。
- 【待确认】旧 `calculate/calculate_models.jl` 中若存在仅被脚本使用的组合入口，是否保留同名顶层函数？本规格的立场：保留**实现**、不保留**转发**；具体清单由迁移批次的定义/调用点清点结果决定，不在本轮施工。
- 【实测背景】`calculate_models` 现为注册模块（`src/modules.jl:103-106`，`deps=[:constants, :MarsCommon]`），其调用点主要在 `MAVEN_data/Build_data/*.jl`、`example/**` 与文档中；这些调用点必须在迁移单元内一并更新。

### 3.7 HD-07 = a（两个独立名字）

- 【裁决】取选项 (a)；【规格】暂用既有建议的两个独立名字，**最终命名待用户确定**（本规格不把暂定名当作已批准 API 名）。
- 【规格】在 `MarsCommon` 中**逐字复制** kg 质量/速度体系实现（暂定 `cyclotron_frequency_kg(B; mass)`、`cyclotron_radius_velocity(v, B; mass)`），比较方式 **exact（同体系内逐位）**。
- 【规格·R-1 应用】`MAVEN_load.cyclone_frequency` / `cyclone_R` 旧名在调用点更新后删除；**禁止裸 alias**（`const cyclone_R = …cyclotron_radius`）与换算包装；选项 (c)（换算到 AMU/eV）**不做**（需要用户单独批准 + `tolerance_justification` + 科学审查）。
- 【规格】`Single_Particle_Orbit.cyclotron_radius`（SI 输入）保持不合并；三套体系的跨体系数值比较一律禁止，只做各自基线与「同体系 exact」。
- 【规格】审计表必须逐条给出四项结论：质量单位、默认粒子、输入是速度还是能量、离子情况下数值是否改变；`TimeFormat` 两版实现逐字采集。

### 3.8 HD-08 = 删除 `sta_v_4d_new`（唯一删实现例外）

【实测】`MAVEN_data/MAVEN_STATIC.jl`：`sta_v_4d` 定义在 547–596；`sta_v_4d_new` 的 docstring 在 597–616、函数体 617–688（模块结束于 1092）。

| 项 | 规格 |
|---|---|
| 删除范围 | `sta_v_4d_new` 的 docstring + 函数体（597–688），以及所有引用 |
| 仓内引用（实测） | `benchmark/bench_03_sta_v4d.jl`（L2/L36/L39/L81/L93/L95/L150/L151，等价性比较与性能对比段）、`docs/src/api.md:119`、`docs/reports/refactoring_audit_a42e14b.md`（历史报告 L171/L209 只作历史说明，不修改） |
| benchmark 处理 | bench_03 的**比较段重写或移除**（不保留兼容分支）；如需保留性能基线，改为对 `sta_v_4d` 单实现的基线，并注明对照实现已按用户裁决删除 |
| 证据面后果 | 跨实现等价用例（EQ-STA-1/EQ-STA-2）**不再可得**：删除后不得再以「两版一致」作为门槛；替代断言改为「删除断言 + `sta_v_4d` 自身回归基线 + 副作用断言」。被删实现仍可从 `46db822` 及其父提交的 git 历史取回，迁移单元必须登记其路径、行范围与 blob 哈希，作为日后科学比对的可回溯证据 |
| 禁止外溢 | 不得借删除之机改动 `sta_v_4d` 的任何其他行为：`dat[:valid] == 0` 时 `println("Invalid Data")` 并返回全 NaN（L548–551）、`STA_count2df` 对输入 Dict 的就地写入、返回 `(vel, flux, density)` 的 `SVector` 形状与单位，全部**保持** |
| backlog | `SB-STA` 状态由「只出证据（下一轮）」改为「实现已按 HD-08 删除；跨实现等价证据今后不可得（历史版本可回溯）」 |

### 3.9 HD-09 = `color_mapping_lut`，无兼容

- 【裁决】采纳改名，不考虑兼容。
- 【规格】head.jl 的 `color_mapping` 迁入 `MAVEN_plot` 后命名 `color_mapping_lut`；**旧名不保留**（无 shim 绑定、无 alias）；`MAVEN_plot` 内两处嵌套同名人（`STA_2d_slip`、`VDF_2d_slip` 内部）本轮**不删除**，仅作等价证据与遮蔽断言对象。
- 【规格】AST 断言保留并强化：顶层不出现与嵌套同名的新定义；两个嵌套调用点的解析结果不变；旧名 `color_mapping` 在全仓受跟踪 `.jl` 中的**定义数=0、限定引用数=0**。
- 【原样保留】`target_architecture_final.md` §4.5 的「备选：保留原名」分支作废（HD-09 已选改名）。

### 3.10 HD-10 = STATIC 使用 `constants.mp_eV_per_km_s2`

【实测】`common/constants.jl:3` `e = 1.602176634e-19`，`:5` `mp = 1.67262192e-27`，`:20` `const mp_eV_per_km_s2 = mp * 1e6 / e`。`MAVEN_data/MAVEN_SWIA.jl:89,197` 已用同一常量写入 `dat[:mass]`。

| 项 | 规格 |
|---|---|
| 契约来源 | 用户裁决：`dat[:mass]`（STATIC 数据包）意为**单位特定的质子静止质量**，与 `constants.mp_eV_per_km_s2` 完全等效；上述解释为**授权契约**，但类型/数值/运算次序变化仍必须实测（t3） |
| 修改内容 | 在 STATIC **等离子矩**计算路径把 `dat[:mass]` 读取改为 `constants.mp_eV_per_km_s2`，并在该处加注释，含义为「不使用数据包自带的 `dat[:mass]`，因为它与 `constants.mp_eV_per_km_s2` 完全等效」 |
| 精确范围（实测候选） | `MAVEN_STATIC.jl` 的读取点 237、301、321、332、442、575、633、732、949、990（412 为注释行，不动）。**必须由 t3 审计报告逐点确认**后再施工 |
| 明确的**不**改项 | ① `dat[:mass_arr]`（逐质量道数组，AMU）全部保留；② `static_c6_mass_mean`/`static_c6_energy_mean` **输出**的 `:mass => mass_out`（178、188）与 `MAVEN_load.jl:1146` 的同类输出——那是**质量数均值数组**，与质子质量常量不是同一物理量；③ `static_slip_2_V` 输出的 `:mass => m_int`（867）——那是质量数；④ `dat[:mass]` 作为**输入键**的数据契约在 `common/data_keys.jl`/文档中的登记状态另议（见下） |
| 输入契约影响 | 改动后这些函数不再需要调用方提供标量 `:mass`。这是**输入契约的破坏性变更**，必须登记（§5）并写入文档；`DataKeys` 是否新增/保留 `:mass` 条目由 t3 结论决定，不得在本轮擅改 |
| 值来源缺口（重要） | 仓库内**没有**任何受跟踪 `.jl` 把 STATIC 切片的标量 `:mass` 设为 `constants.mp_eV_per_km_s2`——其生产者是本仓库外的 c6 3D 产物（`load_c6_v3d` 读取 JLD2 的 `f["data"]`，`MAVEN_load.jl:820-847`）。因此「等效」在本轮只能得到**合成夹具层面**的实测结论；真实产物上的等价性属**开放证据**，不得写成通过 |
| 浮点纪律 | 若替换导致类型或运算次序变化（如 `Float32` 与 `Float64` 混合、常量折叠），必须显式报告，**不得伪称 exact**（t3 合同原文） |
| 禁止外推 | 不得改 MINPA、不得改 SWIA 代码；SWIA 的 `:mass` 赋值与用户对物理同一性的说明只作为文档事实记录 |

**MINPA 对照（禁止机械外推的事实依据）**：【实测】`TW_data/TW_MINPA.jl:101` `mass = [1,2,4,16,28,32,44,64]`（质量数数组），`:207` `:mass => mass`；`:366/413/501` 处 `reshape(dat[:mass], …)`。MINPA 的 `:mass` 是**逐道质量数数组**，与「单位特定质子静止质量」不是同一对象；按 R-5，HD-10 的解释**不得**扩展到此。

### 3.11 HD-11 = 科学疑点保留 + 注释

- 【裁决】保留，可加注释说明；MINPA 数据处理仍不规范，其他同理。
- 【规格】`C6/C7/C10/C11/C12/C13` 数值与算法**原样搬运**，只在现场加注释（注明疑点与 backlog 编号），不修改、不"顺手修正"。
- 【规格】`escape_energy`（`planet≠"Mars"` 时 `UndefVarError`）、`KeV_PER_AMU` 实为质子质量、无操作参数（`m_int`、`energy_range`）、`μ0`/`e` 取值影响等，全部按 backlog **记录不改值**。
- 【规格】MINPA 相关注释措辞必须避免"应与 STATIC 一致"这类外推结论；只陈述现状与待验证项。

### 3.12 HD-12 = 不加入、不面板化

- TASK-026、TASK-039/040 不纳入；`target_architecture_final.md` 的 MIG-047/048 作废。任何"顺手面板化"或引号修改都不在本轮范围内。

### 3.13 HD-13 = 不发 depwarn，文档标注

- 【规格】代码中不得新增 `Base.depwarn`、`@deprecate`、`--depwarn` 兼容路径；`src/modules.jl` 与 `docs/` 中不得出现"deprecated → 转发"式条目。
- 【规格】**替代机制**：破坏性变更写入 `CHANGELOG.md` 的显式清单（旧名 → 新名/删除、影响面、使用者适配动作）与 `docs/src/**`（`api.md` 等）的改名/删除表；旧名在文档中只以"已删除"形式出现。
- 【规格】`docs/reports/**` 的历史报告不改写（保持其当时的表述），必要时在新文档中指向它并说明差异。

### 3.14 HD-14 = 允许物理移动，但全局路径审计先行

- 【裁决】可以移动；但必须先全局查找：① 有程序依赖这些路径；② 它们对其他相对路径的调用；潜在问题在测试里纠正。
- 【规格】审计对象为三个移动单元：`Magnetic_Model/IGRF_calculate.jl` → `models/`；Extras（`Octree`、`Grahame` 等）→ `models/extras/`；`models/Pickup_ion.jl` → `analysis/`（单元划分以 t4 的 `.agent/physical_path_audit.md` 为准）。
- 【规格】审计必须覆盖：源码/注册表 `path` 字段/脚本/示例/文档/配置/测试；`include` 相对路径；`joinpath(@__DIR__, …)`、`Package_path`、`Paths.*` 派生路径；数据与 DLL 路径；工作目录假设；动态拼接（不得以"grep 无命中"声称动态路径安全）。
- 【规格】审计输出必须给出**每个移动单元**的：引用位置清单、内部相对路径清单、风险、必须同步更新的清单、验证方式。审计未完成前**不得移动任何文件**。
- 【规格】移动后由测试纠正潜在问题：受影响模块的装载冒烟 + allow 逐名冒烟 + 相关 Call Table 用例；发现的问题记录在案，不得静默回退移动。

### 3.15 HD-15 = 取消兼容（撤销 `eager_dep`）

- 【裁决】取消兼容。【规格】撤销 `target_architecture_final.md` §3.4 的 `eager_dep` 模式与 §3.6 的 `adds_deps` 临时依赖；`layers.toml [compat_edges]` 整节作废（改写方案见 `target_architecture_execution.md` §5）。
- 【规格】依赖矩阵中 `L2→L3` 由"只允许兼容转发边"改为**完全禁止**；L1→L4 无例外不变。
- 【规格】`MAVEN_load` 中重复实现的 SWEA shape/PAD 与 `static_c6_*` 旧副本：迁出/权威化后，**旧定义删除**，仓内调用点改为 `MAVEN_SWEA.*` / `MAVEN_STATIC.*`。注意这要求确认这些函数在 `MAVEN_load` 内**不再被自身调用**（否则会形成 L2→L3 逆向边），该确认属迁移单元的必查项。
- 【规格】`eager_dep` 唯一的合理残留是"遗留直接 include 的报错语义"这一讨论，随该模式取消而一并作废。

---

## 4. 覆盖清单：被 HD 裁决修订/作废的旧条目

以下 `target_architecture_final.md` 条目**不再作为执行依据**（该文件本身保持原样，仅作历史档案）：

| 旧条目（final 文件位置） | 处置 | 依据 |
|---|---|---|
| §3.4 转发解析规则（`nested` / `eager_dep` 两种模式、`compat_edges` 字段、AST 转发规则） | **作废**，改为"移动 + 删除 + 调用点更新"（execution 规格 §4） | HD-06/09/15 |
| §3.6 `MAVEN_load adds_deps=[:MAVEN_SWEA,:MAVEN_STATIC]`（eager_dep 临时依赖） | **作废** | HD-15 |
| §2.2 注 2「L2→L3 只能作为兼容转发边」 | **改为完全禁止** | HD-15 |
| §5-2「迁出的函数在原模块保留同名转发（DEPRECATED）」；§5-3「转发名不加入 allow」 | **作废**（旧名删除，不保留转发） | HD-06/09/15 |
| §4.4 HD-07 选项 (b)/(c) 与"最终名称由用户定" | 取 (a)；**两个名字先按既有建议**，最终名待用户定 | HD-07 |
| §4.5 备选「保留顶层名 `color_mapping`」 | **作废** | HD-09 |
| §4.3「`sta_v_4d` 与 `_new`：只出证据，不合并」 | **改为：删除 `sta_v_4d_new`** | HD-08 |
| §6.3 B-STA 的 EQ-STA-1/EQ-STA-2（两实现等价） | **作废**，改写为删除断言 + `sta_v_4d` 回归基线 | HD-08 |
| §6.3 容差条款中的"经 Pro-science 批准" | **改口径**：科学例外只能由用户裁决；flash 科学审查只能拒收/要求证据 | 团队合同（无 Pro/Claude） |
| §7.1 MIG-020/021/022/023/024/025/026/027/028（DEPRECATE / 门面 / head shim / 转发） | **重排**为"创建权威 + 更新调用点 + 删除旧名"的原子单元（详细分解属 t5） | HD-03/06/09/15 |
| §7.1 MIG-047/048（面板化、bcompress） | **作废** | HD-12 |
| §7.1 MIG-044/045/046「默认不做」 | **改为：允许做，但以全局路径审计为前置** | HD-14 |
| §7.2 DAG 中波 2 的"全部转发完成后 → MIG-026 head shim" | **作废**（无 shim） | HD-03/15 |
| §7.4 SH-1…SH-6、V-S1…V-S5（兼容 shim 及其验证） | **作废**；改为"拆分后脚本入口的装载冒烟" | HD-03/13/15 |
| §9 SB-STA「只出证据（下一轮）」 | 改为"实现已删；跨实现证据不可得；历史可回溯" | HD-08 |
| §11-4「MIG-042 按 HD-10 增补 DataKeys (a)/(b)」 | 选项 (b) 作废；`(a)` 的"单一 `MASS=:mass`"须先由 t3 结论确认是否与"STATIC 改用常量"相容 | HD-10 |
| §11.1 / §12「由两名 Pro 做轻量确认」「复核 RR-A/RR-S」 | **不再作为门禁**；改由 flash 审查角色（execution 规格 §8）承担 | 团队合同 |
| §13 施工组织中 `pro-architecture-official`、`pro-science-official`、`pro-code-official-1` 的职责定义 | **改口径**：由 flash 角色按 §8 规则承担，审查独立性靠"实现者≠审查者"保证 | 团队合同 |
| §1-6「范围限制：不做函数级性能优化」 | 仍有效，但与 HD-08 不冲突（删除性能测试实现属授权例外） | HD-08/12 |

---

## 5. 破坏性 API 变更清单（已授权，需登记与文档化）

| ID | 变更 | 类型 | 授权 | 使用者适配动作（写入 CHANGELOG/docs） |
|---|---|---|---|---|
| B-01 | 旧名不再转发：迁出函数在旧模块的旧名被删除 | 破坏性 | HD-06/15 | 改用新权威全限定名 |
| B-02 | `head.jl` 旧裸名集合消失（含 `searchsortednearest*`、`Package_path`、绘图标签函数等） | 破坏性 | HD-03/13/15 | 脚本改用 `using MarsData` + `MarsData.@load` + 全限定名 |
| B-03 | `color_mapping` → `color_mapping_lut`（旧名删除） | 破坏性 | HD-09 | 改名 |
| B-04 | `MAVEN_load.cyclone_frequency/cyclone_R` 旧名删除，kg 体系迁至 `MarsCommon` 的两个新名（暂定 `cyclotron_frequency_kg`/`cyclotron_radius_velocity`） | 破坏性 | HD-07/15 | 改名；注意质量单位仍是 kg、B 单位 nT |
| B-05 | `sta_v_4d_new` 删除（含 docstring） | 破坏性 | HD-08 | 改用 `sta_v_4d`；benchmark 比较段同步调整 |
| B-06 | `calculate_models` 旧门面不再提供转发 | 破坏性 | HD-06/15 | 直接调用能力模块 |
| B-07 | STATIC 等离子矩函数不再要求输入 `dat[:mass]`（改用 `constants.mp_eV_per_km_s2`） | 破坏性（输入契约） | HD-10 | 调用方可不再提供 `:mass`；不做"兼容读取" |
| B-08 | `MarsData.MarsCommon` / `MarsData.MarsEnvironment` 顶层别名出现（可观察新增） | 新增（非破坏） | HD-05 | 可用全限定名直接调用 |
| B-09 | SWEA shape/PAD 与 `static_c6_*` 旧副本从 `MAVEN_load` 删除 | 破坏性 | HD-15 | 改用 `MAVEN_SWEA.*`/`MAVEN_STATIC.*` |
| B-10 | 物理移动导致 `include`/路径变化（IGRF→models、Extras→models/extras、Pickup→analysis） | 破坏性（路径） | HD-14（须先审计） | 更新路径引用；按审计清单执行 |
| B-11 | 根依赖从 45 项收敛到 16 项 | 环境面 | HD-01 | 依赖 16 项之外的包不再由项目声明 |

**纪律**：以上每一项都必须在 `CHANGELOG.md` 留下"旧 → 新/删除 + 适配动作"的行；不得用 depwarn 代替文档（HD-13）。

---

## 6. 科学行为保留清单（不得因取消兼容而改变）

| ID | 保留项 | 约束/证据 |
|---|---|---|
| K-01 | 迁移实现的数值结果 | `pure_move` 一律 **exact**（`isequal` 逐元素，含带符号零）；exact 失败本身就是红色警报，禁止改用 rtol 蒙混 |
| K-02 | NaN 语义 | 默认 `nan_policy = positional`：新旧 NaN 位置集合必须完全相同，**新增 NaN 位置一律判失败**；`science_sensitive` 禁用 `ignore` |
| K-03 | 副作用 | 就地写入（`STA_count2df` 写 `:df`/`:df_mass_mass`、`static_slip` 视图共享内存）与 stdout（`sta_v_4d` 的 `println("Invalid Data")`）必须逐项建 `mutates`/`prints` 用例，不得因"清理 API"顺手删除 |
| K-04 | 单位与类型契约 | 角度：SWIA 度、STATIC 存度算时转弧度、MINPA 弧度、MarsCommon 度；MGS `Dict{String,Any}`；TW 同时输出 `:time`/`:epoch`；缺失值用 NaN/flag，不引入 `missing`；`SVector` 返回形状 |
| K-05 | 历史科学差异不统一 | 两套 PSD、`load_quat` 两种返回、`MINPA_sphere2xyz` 两接口、`Single_Particle_Orbit.cyclotron_radius`（SI）、`logticks`/`time_ticks` 等**不合并** |
| K-06 | 已知缺陷保留 | `escape_energy`（`UndefVarError`）、无操作参数、C 类疑点、`μ0`/`e` 现值——按 HD-11 保留并注释 |
| K-07 | 预装/实例结构 | 策略 P 的实例绑定、G-include 的三种装载场景、`constants` 豁免——机制与语义按 final §3 保留（仅删掉其中的"兼容转发"部分） |
| K-08 | 科学正确性边界 | 合成回归 ≠ 科学正确；最终科研正确性由使用者确认 |

---

## 7. 风险与阻塞登记

| ID | 风险/缺口 | 证据 | 处置 |
|---|---|---|---|
| R-1 | 依赖收敛到 16 项后，源码仍 `using` 大量 16 项外的包（CommonDataFormat、JLD2、FortranFiles、Rotations、DifferentialEquations、CSV、DSP、GeometryBasics、GLMakie、Interpolations、LsqFit、Optim、QuadGK、SparseArrays、SpecialFunctions、BenchmarkTools 等） | 【实测】本会话全仓 `using/import` 清单（`.jl`，排除 `.git`/`tmp`） | t6 合同 + t7/t8 实测：逐包登记解析来源；缺包即如实报告为阻塞，禁止 `Pkg.add` 救场 |
| R-2 | `Manifest.toml` 恢复旧版本可能与当前 Julia 版本/全局环境不匹配 | 未测 | t7 记录 `julia --version` 与解析结果；失败如实报告 |
| R-3 | 无兼容 + 不发 depwarn 会让**仓外**使用者的笔记本/脚本直接断裂 | HD-13 明示"由使用者自行适配" | 文档标注（CHANGELOG + docs）；记录为已接受的破坏 |
| R-4 | 删除 `sta_v_4d_new` 使跨实现等价证据不可再得 | HD-08 | 登记历史 blob/行范围；`sta_v_4d` 自身回归基线；SB-STA 状态更新 |
| R-5 | STATIC `dat[:mass]` 标量生产者在本仓库外（c6 3D JLD2），仓内无法证明"完全等效" | 【实测】`MAVEN_load.jl:820-847` 只读取 JLD2；仓内无标量 `:mass` 赋值 | t3 审计 + 合成夹具实测；真实产物等价性记开放证据，不伪装通过 |
| R-6 | 物理移动可能破坏相对 include/工作目录假设 | HD-14 原文 | t4 路径审计为前置门禁；审计未完成不得移动 |
| R-7 | **测试计数不得硬锁**：t1 记录 `runtests.jl` 为 141 passed / 1 broken，但**本会话静态清点对不上**：420 行、plain `@test` 117、`@test_throws` 3、`@test_broken` 1、`@testset` 20（其中嵌套 19、外层容器 1）。静态可解释的上限 ≈ 120 个叶用例 + 19 个嵌套 testset 计 1 次 = **139**，与 141 相差 2，只能由「循环内生成的 `@test`（实测 1 处位于循环内）/ 循环内生成的 testset / 被多次调用的辅助断言」解释——**尚未现场复现** | 【实测】`test/runtests.jl`（`46db822`）：行数、`@test`/`@test_throws`/`@test_broken`/`@testset` 计数 | MIG-000 与 t7/t8 必须**现场实测**并逐条解释与历史值的差异（增/删/合并用例清单 + 差异归因）；`141` 只是历史值，**不得**作为通过门槛或失败判据 |
| R-8 | `benchmark/bench_03_sta_v4d.jl` 的合成输入缺 `:mass`/`:theta`/`:dphi`/`:sc_pot` 等键，两个实现实际都只会走到 `catch` 分支，不具备等价性证据能力 | 【实测】`bench_03_sta_v4d.jl:66-97` | 不把它当作基准证据；按 HD-08 重写/移除比较段，另立基线用例 |
| R-9 | `head.jl` 去留未定（§3.3 待确认项） | — | 队长/用户确认后再动 |
| R-10 | 依赖收敛与「不改源码」的边界可能相互冲突（若某包缺失导致装载失败） | R-1 | t6 合同已声明：实现开始前发现验证命令不可满足时**报告 captain 修订合同**，不要求刻意失败、不自作主张改源码 |

---

## 8. 需队长/用户确认的解释点（未确认前不得施工）

| ID | 问题 | 本规格建议 | 影响 |
|---|---|---|---|
| Q-1 | `common/head.jl` 文件本身删除还是保留为"无旧名绑定的装载入口"？ | 删除（R-1 最干净）；仓内唯一引用 `models/Pickup_ion.jl:3` 一并更新 | 公开入口点、外部脚本 |
| Q-2 | HD-07 两个新名的最终命名 | 暂用 `cyclotron_frequency_kg` / `cyclotron_radius_velocity` | 公开 API |
| Q-3 | `calculate_models` 残余函数（无更合适归属者）是否留在原文件、注册表条目是否保留 | 保留实现、保留注册表条目、删除转发 | 注册表与调用点 |
| Q-4 | `DataKeys` 中 `:mass` 的登记状态（STATIC 不再消费标量 `:mass` 后） | 依 t3 结论决定；本轮不改 | 数据契约文档 |
| Q-5 | `docs/reports/**` 历史报告中提及已删除实现（如 `sta_v_4d_new`）是否加注 | 不改写历史，仅在 `CHANGELOG`/`api.md` 指向说明 | 文档一致性 |
| Q-6 | 是否给 `MarsEnvironment` 既有的 `escape_energy` 缺陷加"已知问题"文档段 | 是（HD-11 精神，不改值） | 文档 |

---

## 9. 合规声明

- 本任务只写入 `.agent/execution_decisions.md` 与 `.agent/target_architecture_execution.md` 两个文件；未修改、未覆盖、未删除任何历史文档（`审计结果.md`、`execution_snapshot.md`、`target_architecture_final.md`、草案与审查文件全部原样）。
- 未修改任何 `.jl`、测试、配置、`Project.toml`/`Manifest.toml`、`docs/`、`benchmark/`；未执行写操作类 git 命令（无 `add`/`commit`/`reset`/`clean`/`stash`/`push`），未触碰 `.agent-teams/**` 运行状态文件。
- 本文件所有【实测】均来自只读读取/`grep`/只读统计命令，锚点为基线 `46db822`；无法实测者明确标为未测/开放，不伪称通过。
- **本文件不授权施工**：任何迁移需在基线门禁（本规格 + t3/t4 审计 + 依赖收敛独立验证 + GATE-B）之后，由队长二次审批后分派。
