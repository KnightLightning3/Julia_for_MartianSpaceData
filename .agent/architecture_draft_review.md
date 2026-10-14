# architecture_draft_review.md — 独立架构审查：目标架构草案的边界 / 依赖 / API / 扩展性 / 迁移可执行性

> 任务：t6 [architecture-review]「独立审查草案的架构边界和扩展性」
> 执行：pro-architecture（高级架构专家）— attempt 1 / `3011cf5d-7403-48bb-9cdb-b1639e52ce09`
> 日期：2026-10-14
> 审查对象：`.agent/target_architecture_draft.md`（t5，chief-architect 草案）
> 审查立场：**只评架构**（边界/依赖方向/API/namespace/扩展性/迁移可执行性），不评科学语义与数值正确性（pro-science 职责）；不替总架构师重写方案，只给证据化的必改项与建议。
> 本文件是本次 t6 的**唯一写入产物**；未改代码/测试/配置，未创建子 Agent，未轮询成员。

---

## 0. 审查结论速览

**总体评价**：草案的骨架是**成立且可执行**的——七能力层 + 允许依赖矩阵（`layers.toml`）+ compat 转发边（带移除期限）+ AST 门禁 + 四波「先建权威→再转发→脚本层→API 面」的迁移 DAG，与 `new_plan.md` §7/§8/§9、t3、t4 一致；「缺证据禁止合并」「不合并清单（§4.6）」「D-1 三支保持开放 + FA-7 两套文本」等关键判断都是正确的。

但存在 **6 个必改项**，其中 3 个是**真正的机制性缺陷**（不是措辞问题），必须在 HA-0 前解决，否则波 1/波 2 会在装载期翻车：

| # | 必改项 | 严重度 | 一句话 |
|---|---|---|---|
| M1 | 权威归属的实例一致性与「预装闭包内转发目标」解析机制未定义（§2.3 只覆盖 MarsEnvironment，漏了 plotting.jl→MarsCommon 与 MAVEN_plot→MarsCommon；且与 MIG-014 注册为普通载体模块自相矛盾） | **blocker** | 预装文件转发到载体模块会在 `using MarsData` 时 UndefVarError / 双实例 |
| M2 | L1→L4 依赖边违例：`FunctionCoordinate.bowshock_zero` 转发到 L4 `MarsEnvironment`，违反 §2.2 矩阵 | **high** | 层次方向自相矛盾 |
| M3 | `MarsEnvironment` 的 `deps` 声明不完整：`get_bowshock_normal` 依赖 `solve_func`（迁往 MarsCommon），deps 却只写 `constants` | high | 装载期解析缺失 |
| M4 | 波 2 全部 compat 转发的**目标模块装载解析**未定义（旧模块装载时如何引用新权威） | high | 转发函数在旧模块装载时 UndefVarError |
| M5 | DAG 与 §7 波次表不一致（MIG-040/041/042 的波次归属） | medium | 文件锁/并行调度歧义 |
| M6 | head.jl shim「保留原 using 列表」（RA-2）与「消除隐式依赖」目标冲突，且与 H-3 拆散方案未闭合 | medium | 需明确 shim 精确内容 |

另附 **8 条建议（S1…S8）** 与对 H-3/H-4/H-5 的架构意见（§5）。

---

## 1. 审查范围与方法

- **读取**：`.agent/target_architecture_draft.md`（543 行，全文）；依赖结果中的 t1/t3/t4 摘要。
- **定向复核的源码**（验证草案的关键事实声明，未重扫全仓）：

| 声明（草案） | 复核结果 | 证据 |
|---|---|---|
| MAVEN_plot 自包含 include constants/MarsCommon | ✅ 成立，且是**嵌套子模块**（非注册表实例） | `MAVEN_plot.jl:4-5` |
| calculate_models 自包含 include constants/MarsCommon | ✅ 成立 | `calculate_models.jl:4-5` |
| `escape_energy` 用 `constants.mp`/`constants.eV`，`planet≠"Mars"` 时 `v` 未定义 | ✅ 成立（草案 §4.2 记录正确） | `calculate_models.jl:87-96` |
| function_coordinate.jl 目前是脚本（无 `module`） | ✅ 成立，顶层 `using LinearAlgebra/StaticArrays/Rotations` | `function_coordinate.jl:1-5` |
| MAVEN_plot export 死名 `WaveSpactra_heatmap` | ✅ 成立 | `MAVEN_plot.jl:18` |
| 注册表 19 条目、DataKeys/Paths 为 preloaded | ✅ 成立 | `src/modules.jl:59-121` |
| `src/MarsData.jl` 预装顺序：paths → data_keys → MAVEN_plot → plotting → modules | ✅ 成立 | `src/MarsData.jl:22-75` |
| TimeFormat 现存于 `src/plotting.jl`（L0 包内）与 `Single_Particle_Orbit.jl`（L4）两份 | ✅ 成立 | t1 §2.2 + `src/plotting.jl:26` |

---

## 2. 必改项（Must-fix）

### M1【blocker】权威归属的「实例一致性」与「预装闭包内转发目标解析」未定义

**问题**：草案把 `bowshock/magnetopause` 权威放 L4 `MarsEnvironment`、把 `TimeFormat/Vandermonde/polynomial_fit/vector_angle` 权威放 L1 `MarsCommon`，并让 **L0 预装文件**（`src/plotting.jl`、`MAVEN_plot.jl`）转发到这些权威（MIG-021/028）。但 `MarsCommon`/`MarsEnvironment` 都是**载体装载模块**（`kind=:module`），在包加载期（`using MarsData`）并不存在于 `MarsData` 命名空间——`src/MarsData.jl` 只预装了 `Paths`/`DataKeys`/`MAVEN_plot`/`plotting`。

具体三处矛盾：

1. **§2.3 vs §3.1/MIG-014 自相矛盾**：§2.3 说 `MarsEnvironment`「随 MAVEN_plot 自包含 include 进入预装闭包」；但 §3.1（MarsData 迁入列）与 MIG-014 又把 `:MarsEnvironment` 注册为**普通载体模块**。两者并存 = 同一代码在「MAVEN_plot 嵌套副本」与「载体模块」里**双实例**——这正是 AR-1（同代码双实例）在包内部的复现，且全局状态/身份一致性从此失去保证。
2. **`src/plotting.jl`（L0 包内）MIG-028 转发 `TimeFormat → MarsCommon.TimeFormat`**：`MarsCommon` 是载体模块，包加载期 `MarsData.MarsCommon` 未定义 → `UndefVarError`。若让 plotting.jl 自包含 include MarsCommon 来兜底，则会在 `MarsData` 命名空间造出一个嵌套 `MarsCommon`，与后续 `load_module(:MarsCommon)` 的 `const MarsCommon = 载体模块` 绑定**冲突**（`modules.jl:382-384`）。
3. **`MAVEN_plot`（预装）MIG-021 转发到 `MarsCommon`/`MarsEnvironment`**：MAVEN_plot 自包含的 `MarsCommon` 是其**嵌套副本**（`MAVEN_plot.MarsCommon`，见 `MAVEN_plot.jl:5`），与载体 `:MarsCommon` 不是同一实例。转发指向哪一个？若指向嵌套副本，则「权威 = common/MarsCommon.jl 文件」实际上是「文件级单一真相 + 多实例」，需在文档明确这一语义；若指向载体副本，则装载期解析失败。

**必改方案（二选一，草案必须择一并全篇一致）**：

- **方案 α（预装统一，推荐）**：把需要被 L0 预装文件引用的权威模块（`MarsCommon`、`MarsEnvironment`、`constants`）一律改为 `kind=:preloaded`，在 `src/MarsData.jl` 中**各 include 一次**并绑定为 `MarsData.X`；消费者（MAVEN_plot/plotting/FunctionCoordinate/L3/L4）用 `using ..MarsCommon`（父模块相对引用）而非自包含 include。代价：触及 ARCH-003 的「自包含」决定，需把各模块的 `include(MarsCommon.jl)` 改为 `using ..MarsCommon`——这是大范围但方向明确的一次性改动，且**不碰装载机制红线**（只增补 `kind=:preloaded` 条目与注册表 note）。
- **方案 β（保持自包含多实例，明确语义）**：维持 ARCH-003 自包含；明确「权威 = **文件**，非模块实例；所有副本因 include 同一文件而数值同步」。转发一律指向「本模块的嵌套副本」（MAVEN_plot 转发到 `MAVEN_plot.MarsCommon.*`，plotting 自包含 MarsCommon 后转发到本地副本）。代价：`MarsData.MarsCommon` 与 `MAVEN_plot.MarsCommon` 是不同实例，`===` 恒假，需在文档与测试中断言「数值等价而非身份等价」；且 `src/plotting.jl` 自包含 MarsCommon 与注册表绑定的冲突问题仍未解决（需让 `load_module` 对已存在嵌套绑定的情况做兼容，或让 plotting 不转发、保留本地实现）。

> 无论选哪个，**必须**把 `layers.toml` 的「模块→实例来源（preloaded/carrier）」这一列补上，并在 MIG-001 的自检 oracle 中加「同一模块不得既 preloaded 又 carrier」。

---

### M2【high】L1→L4 依赖边违例：`FunctionCoordinate.bowshock_zero`

**问题**：§2.2 矩阵明确禁止 L1→L4（`L1 Foundation` 行 L4 列 = ✗）。但 §3.1（FunctionCoordinate 迁出列）与 MIG-027 让 **L1 的 `FunctionCoordinate`** 把 `bowshock_zero` 转发到 **L4 的 `MarsEnvironment`**，形成一条矩阵未允许、且方向向上的边。

**证据**：`bowshock_zero` 现位于 `common/function_coordinate.jl:249`；草案 §4.3 把 `bowshock_zero` 权威迁入 MarsEnvironment；FunctionCoordinate 是 L1（§3.2）。

**必改方案**（任选）：
1. 把 `bowshock`/`magnetopause`/`bowshock_zero`/`get_bowshock_normal` 的权威落点从 L4 降到 **L1 MarsCommon**（回归 03 ARCH-006 原案，见 §5 H-4 意见）；或
2. `bowshock_zero` 留在 FunctionCoordinate 本地实现（不复用 MarsEnvironment，接受 L1 内一处「钳 0」小包装）；或
3. 修订矩阵，显式允许 L1→L4 的「纯函数环境模型」边（不推荐：破坏「L4 依赖 L1、反向禁止」的单向原则）。

---

### M3【high】`MarsEnvironment` 的 `deps` 声明不完整

**问题**：§3.2 写 `MarsEnvironment` 依赖「constants（只依赖 L1）」。但 §4.3 明确 `get_bowshock_normal`「依赖 bowshock/solve_func」，而 `solve_func` 迁往 **MarsCommon**（§4.1）。因此 `MarsEnvironment` 实际依赖 `MarsCommon`，`deps` 至少应写 `[constants, MarsCommon]`。

**必改**：在 §3.2 / MIG-012 中把 MarsEnvironment 的 `deps` 修正为 `[:constants, :MarsCommon]`（若 M1 选方案 α，则相应写 `using ..constants, ..MarsCommon` 或自包含 include）。

---

### M4【high】波 2 全部 compat 转发的「目标模块装载解析」未定义

**问题**：波 2 的 MIG-020/021/022/023/024/025/027/028 把旧模块内的实现改为转发到新权威（如 `MAVEN_load.mean_SWEA_pad_pa → MAVEN_SWEA.mean_SWEA_pad_pa`、`IGRF_calculate.Bpc2sphere → MarsCommon.Bpc2sphere`、`Single_Particle_Orbit.TimeFormat → MarsCommon.TimeFormat`）。但草案**未规定**：旧模块装载时，如何解析这些新权威模块？

- `MAVEN_load` 是 L2 载体模块，`MAVEN_SWEA` 是 L3 载体模块，二者都经 `load_module` 装载。`MAVEN_load` 文件内的转发函数若直接写 `MAVEN_SWEA.mean_SWEA_pad_pa(...)`，则在 `MAVEN_load` 装载期（MAVEN_SWEA 未装入载体）会 `UndefVarError`。
- 唯一可工作的方式是：把转发的目标模块加入转发模块的注册表 `deps`（临时依赖），使 `load_module` 先装目标；或转发函数内部惰性 `MarsData.load_module(:MAVEN_SWEA)`。

**必改**：为每条 compat 边显式规定解析方式，并同步到 `layers.toml [compat_edges]`（草案已要求登记边，但未登记**临时的 deps 增补**）。建议：compat 边登记字段增加 `adds_deps=[...]` 与 `resolve=:eager_dep | :lazy_load`，并纳入 MIG-001 的层规则校验（「转发引用了 X 但 X 不在本模块 deps 且不在 layers.toml compat_edges.adds_deps」→ 报错）。

---

### M5【medium】DAG 与 §7 波次表不一致

**问题**：MIG-040（allow 补全）、MIG-041（拼写别名）、MIG-042（DataKeys 增补）在 DAG 中被放在**波 1**（MIG-041）与**波 3**（MIG-040/042），但 §7 波次表把它们全部放在**波 4**。这会造成文件锁（`src/modules.jl` 被 MIG-014 与 MIG-040 分属不同波）与并行调度歧义。

**必改**：统一三者的波次归属（建议：MIG-041 拼写别名确可在波 1 做，因为它只碰 `models/Cold_Plasma_*` 与 `Maxwellian_distribution.jl`，与波 1 权威建立无冲突；MIG-040/042 留在波 4 或 GATE-2 后，但 DAG 与表必须一致）。并同步修正 DAG 文本。

---

### M6【medium】head.jl shim「保留原 using 列表」与消隐式依赖目标冲突

**问题**：§11 RA-2 的缓解是「shim 保留原 `using` 列表」；但 H-3 拆散 head.jl 的**动机**正是消除「裸 include 6 重模块 + 20 个隐式 `using`」这一 AR-1/A10 债务。若 shim 仍保留 20 个 `using`，则 `include("common/head.jl")` 依旧要求 20 个包在 LOAD_PATH 可见、依旧把隐式依赖注入调用者 Main，收益减半。

**证据**：`head.jl:3-26` 有 `using TimesDates/Dates/ColorTypes/…/QuadGK` 共 20 个。

**必改**：明确 shim 的精确内容——只保留「工具函数旧裸名绑定」而**不保留** `using` 列表（旧脚本若依赖 head.jl 的隐式 `using`，属历史契约，需在 CHANGELOG 明示并建议脚本自行 `using`）。若确需兼容隐式 `using`，应单列为 H-item（建议 H-15），而不是默认藏在 RA-2。

---

## 3. 建议项（Suggestions）

- **S1**：MarsCommon 按 FA-4 拆子文件（`common/marscommon/*.jl`）时，所有自包含 include MarsCommon 的模块（MAVEN_STATIC/SWIA/SWEA/calculate_models/MAVEN_plot/TW_*/MGS_*）的 `include(…MarsCommon.jl)` 语义须在 MIG-011 验证「顶层入口不变、子文件自动带出」，避免隐性装载失败。
- **S2**：Extras 的显式 `include`（§8.3）依赖 `using GLMakie` 等经全局环境解析；建议在 `CATALOG.toml` 的 `external_deps` 字段明确「须装于全局环境 / 独立环境，永不进 `[deps]`」，与 FA-7 对齐，避免与 D-1 再混淆。
- **S3**：L5 目前是「单成员层」（只有 MAVEN_plot），且 MAVEN_plot 又是 L0 预装。建议在文档把「物理装载位置」与「逻辑能力层」显式做成两个正交维度（§2.3 已有雏形，可画成一张二维表），避免未来新增 L5 成员时再次混淆。
- **S4**：MIG-014（注册 FunctionCoordinate/MarsEnvironment）应同时把「新权威入口进新模块 allow、转发名不进 allow、旧模块 allow 中已存在名不变」写进 `note`，防止 MIG-040（白名单补全）时漏项或误删。
- **S5**：MIG-051（死代码/孤儿 docstring 清理）的「AST：只删注释与字符串表达式」需要 MIG-001 的 AST 工具**能区分 docstring 字符串与实现**；建议在 AST 自检 oracle 中增加「孤儿 docstring 检测（D-4 两处）」作为 MIG-051 前置。
- **S6**：§7.2 文件锁表未覆盖 `common/data_keys.jl`（MIG-042）、`.agent/03` 附录 A（MIG-042）、`docs/src/**`（MIG-050）；建议补全，尤其 MIG-042 与 MIG-050 都触契约文档。
- **S7**：MIG-004 追加 `test/runtests.jl` 的可选验证入口，建议用环境变量 gate 且默认跳过，并显式断言「默认运行仍为 141 pass/1 broken、broken 不增」；该文件已是高冲突文件，须严格串行（草案 §7.2 已列，此处强调 gate 语义）。
- **S8**：MIG-000 的编号（000）先于其依赖（002/003），且 GATE-B 依赖 R-1 裁定；建议在表头加注「MIG-000 为波 B 末尾的冻结动作，编号仅作标识」并强调 R-1 未裁定时以只读副本冻结（草案 §6.1 已备，仅需在 DAG 上显式标注 R-1 为软依赖）。

---

## 4. 逐维度评估

| 维度 | 评价 | 关键点 |
|---|---|---|
| **边界** | 良，两处需修 | 七层 + Extras 旁路边界清晰；M2（bowshock_zero L1→L4）与 M1（MarsEnvironment 双归属）是唯一边界裂缝 |
| **依赖方向** | 良，一处违例 | 矩阵 + compat 边 + SCC 校验设计正确；M2 违例、M4（compat 解析）未闭合 |
| **API / namespace** | 良 | 三层 API 面、转发不破坏旧调用、depwarn 默认不发（H-13）、`MarsData` 顶层不扩张——均正确且与 t3 一致 |
| **扩展性** | 优 | FA-1…FA-8 归属判定 + 新建/拆分/子层条件 + Extras 晋升规则，是草案最强部分；唯一待补是 M1 的「实例来源」作为 FA 新增判断维度 |
| **迁移可执行性** | 良，M4/M5 是关键缺口 | 四波 DAG + 文件锁 + 每 MIG 验收门设计合理；M4（compat 装载解析）、M5（波次不一致）须先修 |

---

## 5. 对关键 H 项的架构意见（供 HA-0 参考）

| H | 草案立场 | 本审查意见（仅架构角度） |
|---|---|---|
| H-3 head.jl 拆散 vs MarsUtils | 建议拆散 | **同意拆散**。整体包成 MarsUtils 会造出第二个 God module（统计/几何/绘图标签/边界模型混装），与 AR-17 教训相反；但需按 M6 明确 shim 不保留隐式 `using`。 |
| H-4 MarsEnvironment 独立 vs 并入 MarsCommon | 建议独立 | **倾向「并入 MarsCommon」**（草案备选）。理由：bowshock/magnetopause/bowshock_zero/get_bowshock_normal 是纯函数且被 L1（FunctionCoordinate）与 L5（预装 MAVEN_plot）双向引用；独立成 L4 会同时触发 M1（预装双实例）与 M2（L1→L4）。若坚持要「火星专用能力域」的语义区分，可保留 MarsEnvironment，但须满足 M1/M2/M3（即：仅放 escape_energy/mars_sun_dist_phys 这类不进入预装闭包、不被 L1 引用的函数；边界几何公式留在 MarsCommon）。 |
| H-5 calculate_models 解体 + 门面 | 建议执行 | **同意**，但门面的 `deps` 须写 `[:constants, :MarsCommon, :FunctionCoordinate, :MarsEnvironment]`（按 M4 登记临时依赖），否则门面装载期解析失败。 |
| H-13 depwarn 默认不发 | 建议不发 | **同意**（科研脚本输出不被刷屏，符合 new_plan §17「适合科研」）。 |

---

## 6. 合规声明

- **只写了一个文件**：`.agent/architecture_draft_review.md`（本文件）。未修改任何代码/测试/配置/草案/其他成员交付物。
- 未创建子 Agent、未轮询成员、未运行任何写操作命令。
- 分工边界：本审查只评架构（边界/依赖/API/扩展性/迁移可执行性），不评科学语义与数值正确性（pro-science 职责）；对草案同一证据只给本专业结论。
- 本次定向复核仅读取 5 个源码文件（MAVEN_plot.jl、calculate_models.jl、function_coordinate.jl、src/modules.jl、src/MarsData.jl）以验证草案关键事实，未重扫全仓。
