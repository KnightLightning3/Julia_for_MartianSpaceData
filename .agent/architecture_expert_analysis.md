# architecture_expert_analysis.md — 高级架构分析（模块边界 / 依赖 / API / 扩展性）

> 任务：t3 [architecture-analysis]「分析模块边界、依赖与功能归属」
> 执行：pro-architecture（高级架构专家）— attempt 1 / `0bfdc3eb-caa1-451d-aa99-c1259d079f14`
> 日期：2026-10-14
> 方法：继承 `.agent/current_state_recovery.md`（t1）与 `.agent/01…04` 旧结论，**定向复核**功能→能力→模块、依赖方向、API/namespace、扩展性；**不重复科学语义全量分析**（单位/数值正确性留给 pro-science）。
> 本文件是本次 t3 的**唯一写入产物**；未改任何项目代码/测试/配置，未创建子 Agent，未轮询成员进度。

---

## 0. 结论速览（TL;DR）

| # | 结论 | 证据 |
|---|---|---|
| 1 | **D-1（依赖 16→45）是本轮唯一需要人类裁定的架构事件**，它动摇了目标架构 L0「轻量可加载 + 载体 LOAD_PATH 回退」这一地基；本文件只分析两种处置的架构影响，**不回滚、不提交、不视为已批准** | `Project.toml:7-51`（45 项 `[deps]`，含 GLMakie/IJulia/Revise/XLSX/MAT/MeshIO 等）；`.agent/03` §9.3/§9.9 红线 |
| 2 | AR-1…AR-30 重估：**已消除 8 项、部分消除/缓解 10 项、仍成立 11 项、需重写 1 项**（AR-24 因 D-1 前提反转）；旧计划的 S8 门禁 TASK-027 仍需先做 | §2 全表（逐条附当前代码位置） |
| 3 | **续做顺序必须插入「Phase B：AST + Call Table 最小可用版」这一门禁**（`new_plan.md` §8/§9 要求，当前不存在），置于 S7 收尾之后、S8 大规模去重之前；TASK-026 仅为旧计划续点，**不自动等于本轮实施项**，函数级性能优化（TASK-044…048）一律过滤 | `current_state_recovery.md` §6.4；`new_plan.md` §8/§9 |
| 4 | 目标分层（L0 轻量包 / L1 载体模块 / L2 脚本编排）在当前代码约束下**结构仍成立**，唯一前提是 D-1 的处置不能破坏 L0 轻量性；public API/namespace 与 `allow` 白名单的协同规则见 §5 | `src/modules.jl:59-121,204-218,477-489`；`src/MarsData.jl:22-56` |
| 5 | 未来功能添加规范（`new_plan.md` §4 落地版）已给出：进哪层、何时新建 Module、白名单如何维护、`Project.toml` 依赖边界规则 | §6 |

**给队长/人工的 4 个待裁决项**（§9）：D-1（依赖清单）、R-1（是否先固化提交未提交的 P6 成果）、AST/Call Table 的落点与最小范围、S8 的文件所有权串行划分。

---

## 1. 执行范围与证据来源

**读取并继承**：`.agent/new_plan.md`（817 行）、`.agent/current_state_recovery.md`（315 行）、`.agent/01_PROJECT_MAP.md`、`.agent/02_ARCHITECTURE_REVIEW.md`、`.agent/03_ARCHITECTURE_PLAN.md`（含附录 A）、`.agent/04_OPTIMIZATION_PLAN.md`。

**定向复核的源码**（未重扫全仓，按架构结论所需的最小集合）：

| 文件 | 复核目的 | 关键行 |
|---|---|---|
| `src/modules.jl` | 注册表 19 条目、allow 白名单、载体机制、validate_registry、@load | 59-121, 204-218, 294-302, 329-392, 407-457, 477-489 |
| `src/MarsData.jl` | L0 预装顺序（Paths→DataKeys）、load_index 惰性 | 22-26, 49-56, 66 |
| `common/paths.jl` | Paths 单一出处、fortran_dll_dir（ARCH-005） | 15-17, 48-53, 60-71 |
| `common/data_keys.jl` | DataKeys 契约常量（TASK-016） | 全文 130 行 |
| `MAVEN_data/MAVEN_load.jl` | 惰性 filename_list、日期索引、kp_columns、LOADER_FUNCS | 30, 40, 51-70, 454, 476, 1510-1536 |
| `MAVEN_data/MAVEN_plot.jl` | export 死名残留 | 18 |
| `common/head.jl` | 两套装载体系（AR-1）、A4 大小写 | 28-36 |
| `models/Pickup_ion.jl` | 裸 include（AR-1） | 3-4 |
| `Project.toml` | D-1 依赖清单 | 7-51 |

**未做**：科学语义/单位/数值正确性判断（pro-science 职责）；全仓重扫；任何代码/测试/配置修改；任何写操作命令（测试、golden 快照、bench 均未运行）。

---

## 2. AR-1…AR-30 重估表（已消除 / 仍成立 / 需重写）

> 判定依据：`.agent/current_state_recovery.md` §2.2/§3 + 本次定向复核的当前代码。图例：✅已消除 ｜ 🟡部分消除/缓解（剩余部分为既定保留或待后续任务） ｜ ⬜仍成立 ｜ 🔁需重写（前提反转）。

| AR | 主题 | 判定 | 当前证据与说明 |
|---|---|---|---|
| AR-1 | 两套装载体系并存 | ⬜仍成立 | `common/head.jl:28-36` 仍裸 include 6 个重模块；`models/Pickup_ion.jl:3-4` 仍 include head.jl + function_coordinate.jl。TASK-035/036 未开始 |
| AR-2 | 模块加载期 IO | 🟡部分消除 | `filename_list()` 已惰性化（`MAVEN_load.jl:40`，TASK-007）；SP_load INI 已去（TASK-009）；IGRF `const GG,HH` 与 Schmidt 预计算**保留加载期**（ARCH-001.3 既定，负收益不惰性化） |
| AR-3 | 相对父模块引用依赖装载顺序 | ✅已消除 | `common/MarsCommon.jl:2` 已自包含 include（TASK-014）；`validate_registry` 已扩展校验 `using ..X`/冗余 include（`src/modules.jl:407-457`，TASK-015） |
| AR-4 | 全局可变状态 | 🟡部分消除 | Cold_Plasma `PlasmaState`（TASK-024 已完成）；`_kp_dict` Ref + `kp_columns` kwarg（`MAVEN_load.jl:30,454,476`，TASK-025）；**`B_compress` 仍模块全局**（TASK-026 未做） |
| AR-5 | Pickup_ion 隐式全局契约 | ⬜仍成立 | `Pickup_ion.jl` 未函数化（TASK-036 未开始） |
| AR-6 | 横向耦合 / 同物理量多份实现 | ⬜仍成立 | Bpc2sphere/cyclotron/bowshock/slice2d/static_c6/TimeFormat 副本均仍并存（TASK-028…034 未开始） |
| AR-7 | `Dict{Symbol,Any}` 无 schema | 🟡缓解 | `DataKeys` 已落地（TASK-016），但全仓类型化按 03 §3.4.1 明确不做 |
| AR-8 | 数据键不一致清单 | 🟡部分消除 | C3（`:B` vs `"B"`）已修（TASK-004）；`:time`/`:epoch`、KP_l3/KP、MGS 字符串键**登记不强制改**（附录 A 契约表） |
| AR-9 | 就地修改 / 视图别名 | 🟡缓解 | TASK-017 docstring 已落地；语义未变（机制防御推迟到 PHASE 4） |
| AR-10 | 拼写错误固化 | ⬜仍成立 | `MAVEN_plot.jl:18` 仍 `export WaveSpactra_heatmap`（死名）；别名层 TASK-041 未开始 |
| AR-11 | 同义函数多版本并存 | ⬜仍成立 | `sta_v_4d`/`sta_v_4d_new` 仍并存（TASK-044 条件性，未触发） |
| AR-12 | 默认参数引用未定义全局 | ✅已消除 | TASK-003 `m_int::Real=16` |
| AR-13 | 白名单覆盖面不足 | ⬜仍成立 | 仅 3 模块非空 allow（`src/modules.jl:62,68,89`）；TASK-042 未开始 |
| AR-14 | 反射注册 + 线性文件匹配 | ✅已消除 | `LOADER_FUNCS` 显式函数表（`MAVEN_load.jl:1514-1536`，TASK-012）；`_FILE_INDEX_CACHE`/`_file_index` 日期索引（`MAVEN_load.jl:51-70`，TASK-013） |
| AR-15 | 静默失败路径 | ✅已消除 | `@warn` + `error_report` 聚合（TASK-006） |
| AR-16 | 绘图管线硬绑定 data_dict | ⬜仍成立 | `src/plotting.jl` 未面板化（TASK-039 未开始） |
| AR-17 | 科学核心与读取混层 | ⬜仍成立 | SWEA shape 函数仍在 `MAVEN_load`（TASK-030 未开始） |
| AR-18 | 硬编码常数无出处 | 🟡缓解 | C6/C7/C11/C12/C13 已注释记录、C10 已具名常量（TASK-022/023）；数值未改（既定） |
| AR-19 | 单位约定混杂 | 🟡缓解 | 附录 A 已登记单位约定；未改名（既定） |
| AR-20 | 磁力线默认一阶 Euler | 🟡部分消除 | `method` kwarg 已暴露（TASK-021），默认仍 `:euler`（人类批准前不改，R5） |
| AR-21 | 零 benchmark 基线 | 🟡部分消除 | `benchmark/` + 合成 golden 已建（TASK-001）；八项基准缺 4 项（D-6） |
| AR-22 | 类型不稳定热路径 | ⬜仍成立 | TASK-045/046 条件性，未触发（**本轮过滤**） |
| AR-23 | ccall 边界与逐点调用 | ⬜仍成立 | TASK-048 条件性评估，未触发（**本轮过滤**） |
| AR-24 | 包加载与编译成本 | 🔁**需重写** | 原「轻量 deps 既定设计」的前提被 D-1 推翻：`Project.toml` 现 45 项 `[deps]`，`using MarsData` 将加载 GLMakie/IJulia/Revise 等，冷启动成本与「轻量可加载」承诺冲突（见 §4.1） |
| AR-25 | 模块不可无数据环境加载 | ✅已消除 | filename_lists 惰性（TASK-007）+ SP/TW/MGS Paths 化（TASK-009/010）；剩余 IGRF/Call_fortran_dll 依赖 DLL 属既定环境依赖 |
| AR-26 | 科学计算零自动化测试 | 🟡缓解 | `test/runtests.jl` 现 141 passed/1 broken（覆盖装载管理器、DataKeys、v_3d、PlasmaState 等）；仍远未覆盖全科学面 |
| AR-27 | 全局状态阻隔测试隔离 | 🟡缓解 | PlasmaState（TASK-024）、kp_columns（TASK-025）已可隔离；`B_compress` 仍全局 |
| AR-28 | 三份坏死 calculate_mag | 🟡部分消除 | 函数定义已删（TASK-002）；**孤儿 docstring 残留**（`TW_load.jl:111-129`、`MGS_load.jl:96-113`，D-4），归 TASK-043 |
| AR-29 | 死代码与演进痕迹 | ⬜仍成立 | 注释测试块/注释旧版仍在（TASK-043 未开始） |
| AR-30 | 文档两级分化 | ⬜仍成立 | PHASE 8 文档同步未开始 |

**重估要点（相对旧 02 结论的变化）**：
1. AR-24 是唯一「需重写」项——它从「既定设计，仅记录」升级为「D-1 造成的架构回归」，必须在 D-1 处置后重新定性。
2. AR-28 由「已消除」改为「部分消除」——函数删除完成，但 06 日志「无残留」表述不准确（D-4 孤儿 docstring），清理归入 TASK-043。
3. 其余 AR 的「仍成立」项全部对应 TASK-026…043 未开始，与恢复报告 §3 的进度刻度一致，无需改写旧结论。

---

## 3. ARCH-001…017 → TASK 映射在当前进度下的重排

### 3.1 进度基线

- 已完成：S0a（001）、S1（002-007）、S0b 部分（008 环境缺失不阻塞）、S2（009-011）、S3（012-013）、S4（014-015）、S5（016-017）、S6（018-023）、S7 半程（024/025 完成，026 未做）。
- 未开始：S7 尾（026）、S8（027-034）、S9（035-038）、S10（039-042）、S11（043）、条件任务（044-048）。

### 3.2 必须插入的新门禁：Phase B（AST + Call Table）

`new_plan.md` §8/§9 要求「先建立 AST 验证框架与函数调用表，确认其可运行，再开始大规模迁移」。当前两者**均不存在**（`current_state_recovery.md` §6.4）。旧 03/04 计划（P0-P6 时代）没有这一条，因此续做顺序**必须插入**：

```
当前进度（S7 半程）
   ↓
【新门禁】Phase B：AST 框架 + Call Table 最小可用版（提取 function/module/using/export/call、
           跨模块调用、API 影响、重构前后结构对比 + case_id/module/function/arguments/
           comparison_method/tolerance/tags 的 TOML/JSON 结构），并自检可运行
   ↓
S7 收尾（TASK-026，若本轮需要；见 §3.3 过滤说明）
   ↓
S8 门禁（TASK-027 签名/单位审计表）→ S8 去重（028-034）
   ↓
S9 → S10 → S11
```

**理由**：S8 去重（028-034）是大规模 MOVE/MERGE/转发，`new_plan.md` 原则 3「先建立验证能力，再大规模迁移」要求迁移前后结构对比能力先行；否则「迁移完整性」无法机器判定，只能靠手工 grep（违反 `new_plan.md` §8 与 §14「能自动化不手工」）。

### 3.3 TASK 续做点过滤（响应队长指示）

- **TASK-026（IGRF bcompress 显式变体）仅作旧计划续点**，不自动等于本轮应实施项。它是「状态显式化」类（非性能优化），是否纳入本轮由 Phase B/C 目标架构审定后决定；若本轮范围收缩为「先交付架构 + AST/Call Table 门禁」，则 TASK-026 可与 S8 一并排期。
- **TASK-044…048 一律过滤**：它们是函数级/条件性性能优化（sta_v_4d 收编、热点 struct、向量化、绘图微优化、ccall 评估），落在 `new_plan.md` §2.2「暂时不做」与队长「过滤函数性能优化」指令之内，本轮不实施、不排期，仅保留在 04 文档作为后续参考。
- **TASK-008（真实数据基线）保持「环境缺失不阻塞」口径**；不因本轮进入实施而改变。

### 3.4 S8 门禁 TASK-027 是否必须先做

**必须先做**。TASK-027（签名/单位审计表）是 TASK-028…034（去重/转发）的权威依据；其核心风险是「转发破坏调用点」（单位不一致，如 `Single_Particle_Orbit.cyclotron_radius` 为 SI 输入 vs `calculate_models.cyclotron_radius` 为 nT/eV 输入）。审计表已预判「保留私有 helper 而非强行转发」的例外，证明它在防科学分叉上不可省略。同时它本身是**只读审计**（无代码改动、无科学数值风险），适合在 Phase B 门禁通过后立即并行推进。

---

## 4. 目标架构分层与依赖方向在当前约束下的复核

### 4.1 D-1（依赖 16→45）的架构影响分析（两种处置，不预判裁决）

**事实**：`Project.toml [deps]` 现 45 项（`Project.toml:7-51`），含 `GLMakie`、`IJulia`、`Revise`、`XLSX`、`MAT`、`MeshIO`、`Meshes`、`NFFT`、`LegendrePolynomials`、`GridInterpolations`、`CommonDataFormat`、`JLD2`、`DifferentialEquations` 等。mtime 10-14 11:29，无日志（D-1）。

**架构影响（与 03 §9.3/§9.9、01 §3.2 红线冲突）**：

1. **L0 轻量性丧失**：`using MarsData` 现在把 45 个包拉进依赖闭包。其中 `IJulia`、`Revise` 是**开发工具**，本不应出现在库包 `[deps]`；`GLMakie`/`MeshIO`/`Meshes` 等仅被 `models/Octree.jl`（本轮不动的独立脚本）使用。这与 03 §9.3「包轻量可加载」与 §9.9「依赖清单不动」直接冲突。
2. **载体机制理由被架空一半**：`_carrier()`（`src/modules.jl:294-302`）的存在理由是「绕开包模块对 `[deps]` 外依赖的严格校验」。若这些重依赖全部进 `[deps]`，载体机制对它们的回退解析意义消失（机制仍可用，只是不再必要）。这是目标架构「L0 轻量 + L1 载体 LOAD_PATH 回退」的一体两面被拆散。
3. **冷启动与预编译成本**：AR-24 由「既定设计」反转为「架构回归」。

**处置选项（只分析影响，不执行、不视为批准）**：

| 选项 | 动作 | 架构影响 | 代价 |
|---|---|---|---|
| **收敛（回滚到 16 项）** | 把 `Project.toml`/`Manifest.toml` 恢复为 HEAD（`94da314`）状态 | 恢复 L0 轻量 + 载体回退理由 + 红线一致性；与 03 目标架构完全对齐 | 测试/运行依赖回到「全局 `v1.10` 环境已装重依赖」这一旧前提；需确认全局环境确实具备（恢复报告 §2.4 显示全局环境存在） |
| **保留（接纳 45 项）** | 维持现状，修订红线 | 载体机制退化为遗留 shim；L0/L1 分层塌缩；「轻量可加载」承诺正式废弃 | 需重写 03 §9.3/§9.9、01 §3.2、AR-24；`using MarsData` 冷启动显著变慢；`IJulia`/`Revise` 等工具依赖污染库包 |
| **部分保留（净化）** | 只保留「注册模块真正 import 的运行期重依赖」，剔除工具/GUI 依赖 | 折中；但需要一个明确的「哪些依赖进 `[deps]`、哪些走载体」边界规则（即 §6 的依赖边界规则） | 需逐项审计 45 个包的实际 import 归属，工作量大且边界易再漂移 |

**本文件的架构建议**（供人工参考，不自行执行）：优先「收敛（回滚）」——因为目标架构的整条 L0/L1/L2 依赖方向与「未来功能添加规范」（§6）都以「L0 轻量、重依赖走载体」为前提；保留 45 项等于在未审定的情况下改写架构地基。但**具体裁决归人工**，且裁决前不应基于当前 45 项继续改 `Project.toml`（与恢复报告 D-1 处置建议一致）。

### 4.2 L0/L1/L2 分层在当前代码下的成立性（D-1 之外的部分）

- **L0（`src/MarsData.jl`）**：Paths → DataKeys → load_registry/data_model/load_index → MAVEN_plot → plotting → modules 的预装顺序成立且已复核（`MarsData.jl:22-75`）。`DataKeys` 已作为 `kind=:preloaded` 注册（`modules.jl:66`），符合 03 §3.1 目标。
- **L1（载体模块层）**：注册表 19 条目（含 DataKeys/Paths 两 preloaded），统一自包含 include 已落地（TASK-014），显式 LOADER_FUNCS + 日期索引已落地（TASK-012/013）。剩余 03 §3.1 目标中的 `FunctionCoordinate`/`MarsUtils` 两新模块**尚未注册**（grep 确认无 `module FunctionCoordinate`/`module MarsUtils`，TASK-033/035 未开始）。
- **L2（脚本层）**：仍是「装载体系」而非「编排」——head.jl/Pickup_ion 裸 include 未迁移（AR-1），依赖方向问题依旧。

**结论**：除 D-1 外，目标分层结构本身在当前代码下仍成立，无需推翻重来；03 目标架构可继续作为 Phase C 底稿。

### 4.3 依赖方向红线（迁移中必须保持）

```
common（constants → MarsCommon / DataKeys / Paths）  ←  仪器/读取（MAVEN_*/TW/MGS/SP/IGRF）  ←  脚本/绘图
```

- 禁止跨目录横向 include（如 TW_MINPA 私有 slice2d 副本，TASK-033 清除）；禁止读取器兼任科学处理（TASK-030 迁移）。
- 重依赖经载体 LOAD_PATH 回退（在 D-1「收敛」处置下）；任何新外部依赖**不并入 `[deps]`**（见 §6 规则 5）。

---

## 5. public API / namespace / 白名单协同规则

当前机制（已复核）：`@load` 展开为 `const 模块名 = load_module(...)`（`modules.jl:477-489`），裸名引入面完全由 `ModuleSpec.allow` 决定（`_apply_allow!` 用 `using .Mod: a, b` 逐名引入，与模块自身 `export` 无关，`modules.jl:204-218`）。

由此推导出三层 API 面，需在迁移与规范中一致使用：

| 层 | 形式 | 适用 | 维护规则 |
|---|---|---|---|
| **全限定名** | `MarsData.MAVEN_STATIC.sta_v_4d(...)` | 一切稳定调用 | 默认首选；不依赖 allow/export，最不易冲突 |
| **白名单裸名** | `@load MAVEN_STATIC` 后直接 `sta_v_4d(...)` | 少量「文档明确的公开入口」 | 只放 `docs/src/api.md` 认定的公开入口；新增裸名须先跑「逐名引入冒烟」（`_apply_allow!` 对不存在的名字会抛 ArgumentError，机制已保护） |
| **模块 export** | `export sta_v_4d, ...` | 历史遗留 | **不作为裸名引入依据**；`WaveSpactra_heatmap` 这类死名由 TASK-041 清理 |

**协同规则**：
1. 白名单补全（TASK-042）**必须保守**：16 个空白名单模块只填「文档明确公开入口」，避免裸名污染与冲突（03 §11 风险 #7）。
2. 每模块 `@load` 冒烟 + 逐名引入测试是白名单变更的强制验收（`new_plan.md` §14 自动化精神）。
3. 被删坏死函数（ARCH-007）与旧拼写别名**不进白名单**；别名层（ARCH-010）用转发函数而非白名单裸名。

---

## 6. 未来功能添加规范（Feature Addition Convention，草案）

> 落地 `new_plan.md` §4「低摩擦 Feature Addition Convention」，原则是「新功能可快速增加，但不能继续无规则增加」。

### 规则 1 — 功能归属判据（新函数进哪一层）

| 新功能类别 | 归属 | 判据 |
|---|---|---|
| 纯物理/数学常数 | `common/constants.jl` | 与现有常量同类 |
| 纯数学工具 / 坐标变换 / 能量换算 | `common/MarsCommon.jl` | 无仪器/数据依赖、纯函数、标量约定 |
| 跨模块数据键 | `common/data_keys.jl` + `.agent/03` 附录 A | 新键名必须先登记契约，禁止裸字面量 |
| 数据读取 / 格式解析 | 对应数据目录新/现有模块（`MAVEN_data/`、`TW_data/`、`MGS_data/`、`support_data/`） | 只做读取与解析，不含科学处理 |
| 仪器矩/换算 | 对应仪器模块（`MAVEN_STATIC/SWIA/SWEA/TW_MINPA`） | 只做矩/换算 |
| 物理模型 | `models/` | 领域物理 |
| 绘图基元 | `MAVEN_data/MAVEN_plot.jl` | 绘图专用；纯数学工具移 `MarsCommon` |

### 规则 2 — 何时新建 Module

满足**任一**即新建模块（否则加入既有模块）：
1. 新功能引入一个**既有模块未使用的全新外部依赖**（该依赖仍走载体 LOAD_PATH，不进 `[deps]`）；
2. 新数据源/仪器（reader）；
3. 新物理领域（与现有 models/ 职责不重叠）。

**何时拆模块**：一个模块职责横跨 ≥2 个「能力域」（如读取+科学处理，见 AR-17 God module）时拆分，拆分后保留原模块转发别名。

### 规则 3 — 依赖方向与跨模块依赖

- 严格单向：`common ← 仪器/读取 ← 脚本/绘图`；禁止横向复制实现（AR-6 的教训）。
- 新函数同时依赖两个模块时：**放入更高层消费者，或新建组合模块，禁止复制**。
- 注册表新增条目必须同步写 `deps`（语义文档化）与 `note`。

### 规则 4 — allow 白名单维护

- 新增裸名 = 新增到 `docs/src/api.md` 的公开入口 + 写入 `allow` + `@load` 冒烟测试三者同步。
- 白名单只增公开入口，不放内部/别名/坏死名。

### 规则 5 — `Project.toml` 依赖边界（直接回应 D-1）

- **只有 L0 包自身（`src/MarsData.jl`/`plotting.jl`/`modules.jl`/`MAVEN_plot.jl`）使用的依赖才允许进 `[deps]`**。
- **仅被 L1 载体模块使用的依赖一律不进 `[deps]`**，经载体 LOAD_PATH 回退解析（01 §3.2、03 §9.9）。
- **开发/工具类依赖（`IJulia`/`Revise`/`BenchmarkTools` 等）永不进库包 `[deps]`**（放全局环境或 `benchmark/` 独立环境）。
- 任何 `[deps]` 变更需在 06 日志记录并附理由；无日志的 `Pkg.add` 视为架构事件（D-1 教训）。

### 规则 6 — 状态与数据键

- 禁止新增模块级可变全局；状态用显式参数或不可变配置（`PlasmaState` 模式）；遗留可变状态仅 `Ref` + 弃用标注。
- 新键名复用 `DataKeys` 常量，不写裸 Symbol/字符串字面量。

---

## 7. 备选架构（Alternative Architectures）

> 供人工在 D-1 裁决时参考；本文件不替人工选择。

| 方案 | 描述 | 优点 | 缺点 / 风险 | 与本轮边界的关系 |
|---|---|---|---|---|
| **A. 现状目标（03 定稿，轻量包 + 载体 + 白名单）** | 保持 16 项 `[deps]` + 载体 LOAD_PATH 回退 + L0/L1/L2 | 轻量可加载、依赖隔离、与既有红线一致、迁移面小 | 依赖「全局环境装齐重依赖」；precompilation 弱 | **本文件推荐**，前提是 D-1「收敛」 |
| **B. 全包化（heavy package）** | 45 项全进 `[deps]`，模块改静态子模块，去载体回退理由 | 编译期依赖校验、可预编译、不依赖全局环境 | `using MarsData` 变重；「轻量可加载」/「无数据无 DLL 可 using」承诺废弃；载体机制变遗留 | 与 D-1「保留」等价；需重写红线 |
| **C. 双包拆分（core + extensions）** | 轻量 core（paths/registry/DataKeys）+ 每域 extension 包，用 Julia Extensions 表达可选重依赖 | 最干净的依赖隔离、可预编译 | 大重组，触及 03 §3.4.2「不重命名/不重排」红线；超出本轮范围 | **仅登记为远期选项**，本轮不做 |

**结论**：本轮架构工作应继续沿 **方案 A** 推进（即 D-1 处置取「收敛」）；方案 B 视为 D-1「保留」的架构后果，需人工明确接受才成立；方案 C 记录备查，不在本轮启动。

---

## 8. 迁移风险与并行互斥建议

### 8.1 风险（继承恢复报告 §7 + 架构增量）

| ID | 风险 | 架构定性 | 缓解 |
|---|---|---|---|
| R-1 | P6 + TASK-024/025 共 19 文件 +2493/−221 全部未提交 | 最高单点风险 | 人工决定是否先固化提交（属写操作，需批准） |
| R-2/D-1 | 依赖清单扩张无日志、无批准 | 架构地基事件 | 人工裁定（§4.1）；裁定前不改 `Project.toml` |
| R-3 | AST/Call Table 缺口 | 违反 `new_plan.md` §8/§9「先验证后迁移」 | Phase B 门禁前置（§3.2） |
| R-4 | 无真实数据 | 科学证据强度受限 | 合成证据标注；最终科研正确性归使用者 |
| R-5 | 孤儿 docstring（D-4） | 阅读误导，非运行缺陷 | 归 TASK-043 |
| R-6 | 未提交状态下多 Agent 并行 | 写入互斥风险 | §8.2 文件所有权 |
| R-7（新增） | S8 去重跨文件交叉（MarsCommon/MAVEN_load/MAVEN_plot 同被 028/029/031/032 触及） | 若并行会冲突 | §8.2 高冲突文件串行 |
| R-8（新增） | A4 大小写隐患仍在（`head.jl:35` 引用 `Maxwellian_Distribution.jl`，实际文件 `Maxwellian_distribution.jl`） | Linux/CI 必失败 | TASK-035（head.jl→MarsUtils）随装载块删除一并消除 |

### 8.2 高冲突文件与串行划分（并行互斥建议）

> 实施阶段（Phase D 之后）每个 TASK 必须先声明 Owned Files；下列文件设串行锁。

| 文件 | 被哪些待办 TASK 触及 | 建议 |
|---|---|---|
| `MAVEN_data/MAVEN_load.jl` | 026/028/030/031/043 | **串行**，且 S8 去重前先完成 S7 尾 |
| `MAVEN_data/MAVEN_STATIC.jl` | 043/044-046（本轮过滤后仅 043） | 串行 |
| `src/plotting.jl` | 034/039/040/047（本轮过滤 047 后仅 034/039/040） | 串行 |
| `src/modules.jl` | 033/035/042（+仅增补注册表/allow，机制红线） | 串行；只增注册表条目/allow，不改机制 |
| `common/MarsCommon.jl` | 028/029/032 | 串行 |
| `Magnetic_Model/IGRF_calculate.jl` | 026（+已完成的 020/021） | 串行 |
| `models/Cold_Plasma_Dispersion_Relation.jl` | 041（若别名未随 024 补全） | 串行 |

---

## 9. 待裁决项（提交队长/人工）

| ID | 事项 | 本文件立场 | 决策主体 |
|---|---|---|---|
| P-1 | **D-1 依赖清单（16→45）**：保留 / 收敛 / 部分保留净化 | 建议「收敛（回滚到 16 项）」以保住目标架构地基；但明确**不回滚、不提交、不视为已批准**，仅分析影响 | 人工 |
| P-2 | **R-1 未提交的 P6 成果**是否先固化提交 | 建议先固化基线（降低 19 文件丢失风险 + 为并行互斥提供干净起点） | 队长（写操作，需批准） |
| P-3 | **Phase B（AST + Call Table）的落点与最小范围**：由哪个 Flash 实例、产出到哪个目录、最小验收（提取/调用表/自检） | 建议：最小可用版 = 函数/模块/using/export/call 提取 + 跨模块调用表 + 前后结构对比 + 一个 TOML call-table 样例，通过自检即放行 S8 | 队长（调度） |
| P-4 | **S8 文件所有权串行划分**是否按 §8.2 采纳 | 建议采纳 | 队长 |
| P-5 | 本轮范围是否含 TASK-026（IGRF bcompress） | 仅作旧计划续点，**不自动实施**；随 Phase C 目标架构审定后再定 | 队长/总架构师 |

---

## 10. 合规声明

- **只写了一个文件**：`.agent/architecture_expert_analysis.md`（本文件）。未修改任何项目代码/测试/配置/`new_plan.md`/`.agent/00…06`，未触碰 `Project.toml`/`Manifest.toml`。
- 未创建任何子 Agent；未查询其他成员进度邮箱；未轮询。
- 未运行任何写操作命令（测试、golden 快照、bench 均未执行）；所有行号锚点为本次定向读取 + 继承恢复报告的证据。
- 分工边界：本文件只谈**归属、边界、依赖方向、API/namespace、扩展性、迁移顺序**；不谈数值/单位/科学正确性判断（交 pro-science）；两 Pro 对同一证据（如 `MAVEN_load.jl:454`）各自只给本专业结论。
