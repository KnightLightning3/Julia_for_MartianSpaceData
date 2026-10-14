# physical_path_audit.md — IGRF / Extras / Pickup 物理迁移路径审计（t4）

> 任务：t4 [work]「全局审计 IGRF Extras Pickup 物理迁移路径」（团队 `marsdata-flash-execution`）
> 执行：official-engineer，**接手** USTC 前任 attempt 1（前任因 `pi-ai stream idle timeout after 300000ms` 终止）
> attempt 2 / `e757dee4-84de-4ba2-9a29-52ba367e9a6e`；日期 2026-10-14（Asia/Shanghai）
> 基线：`46db822425378d4ad99f8f0b7cfed07360118486`（源码逐字节；工作区另有 t7 对 `Project.toml`/`Manifest.toml` 的已记录改动，与本审计对象无关）
> 纪律：**只读审计**——未移动/改名/删除任何文件，未修改任何源码；本报告是唯一产出。
>
> **前任产物交接核实**：接手时 `.agent/physical_path_audit.md` **不存在**（`Test-Path` = False，`.agent/` 近 3 小时内仅有 t2/t6/t7 的四份文档），故**无可复用分片文本**；本报告为全量重做。前任消息所称"证据已收集"未以任何落盘文件形式留下，本报告不假设其内容。

---

## 0. 方法与"未命中"的边界（先声明证据强度）

### 0.1 使用的检索口径

| 口径 | 命令/模式 | 用途 |
|---|---|---|
| 受跟踪路径 | `git ls-files` + 过滤 `IGRF\|Extras\|Pickup\|extras\|pickup` | 确定单元对象 |
| 全仓引用（含文档/配置） | `grep -rn "IGRF\|Magnetic_Model\|gh_gao\|Pickup_ion\|pickup_ion\|Graham\|Octree"` | 引用点定位 |
| 函数级调用点 | `grep -rn "build_octree\|get_min_bounding_box\|find_boundaries\|graham_scan!"`（`*.jl`） | 判断 Extras 是否被真实调用 |
| **include 与动态拼接** | `grep -rn "include(\|include\.(\|joinpath\|@__DIR__\|@__FILE__\|dirname("`（`*.jl`） | 定位相对/拼接路径 |
| **目录扫描型动态装载** | `grep -rn "readdir\|walkdir"`（`*.jl`） | 排查"扫描目录自动装载"的可能 |
| CWD 假设 | `grep -rn "pwd()\|cd(\|raw\"\|D:/"` 及人工阅读命中处 | 排查工作目录依赖 |
| 忽略与跟踪状态 | `git ls-files`、`git check-ignore -v` | 确认二进制/数据文件是否入库 |
| 装载解析语义 | 阅读 `src/modules.jl:230`、`common/paths.jl:11` | 确认路径相对谁解析 |

### 0.2 明确不能由"文本无命中"推出的结论

1. **未命中 ≠ 动态路径安全**。本次对三类"文本不可见"的路径逐项做了针对性排查，结论以 §0.3 的实测为准：
   - ① **运行时拼接**：`common/head.jl:28` 的 `Package_path = normpath(joinpath(@__DIR__,".."))*"/"` 后与子路径拼接；`Magnetic_Model/IGRF_calculate.jl:807-809` 的 `dirname(@__FILE__)*"/…"`；`models/Pickup_ion.jl:273-278` 的 `pkg_path*"…"`。**三者均已定位并逐行核对**（不是靠"没搜到"）。
   - ② **目录扫描/批量 include**：全仓 `readdir`/`walkdir` 仅 3 处（`benchmark/golden_snapshot.jl:251` 结果目录、`TW_data/TW_MINPA.jl:43` 数据目录、`MAVEN_data/Build_data/STATIC_vfd_3d.jl:212` 产物目录过滤），**均不扫描 `models/`、`Magnetic_Model/` 或任何源码目录**；仓内不存在"扫目录后 include"的装载器。故不存在"移动后自动被装载"的隐藏面。
   - ③ **注册表/配置文案**：`src/modules.jl` 是本仓唯一的路径→模块映射；`config/`（含 `settings.example.toml`）**零命中**（`grep -rn "IGRF|Magnetic|Pickup|Octree|Graham|dll|models" config/` → No matches）。
2. **本审计不判定 API/兼容策略**（属 t2/t5）；只判定"路径与位置依赖"。
3. **文档类命中已分类**：现行文档（需更新）与历史记录（`CHANGELOG.md`、`docs/reports/*`，**不改**）分别列出；后者引用的是历史事实。

### 0.3 装载与路径解析的三个事实（后续三个单元共用）

| 事实 | 证据 | 影响 |
|---|---|---|
| 注册表路径**相对项目根**解析，与 CWD 无关 | `src/modules.jl:230` `normpath(joinpath(project_root(), _spec_of(name).path))`；`common/paths.jl:11` `PROJECT_ROOT = normpath(joinpath(@__DIR__,".."))` | 移动文件后**只需**改注册表里那一行字符串 |
| 仓内 `include` 普遍用 `joinpath(@__DIR__,"..",…)` 或 `Package_path`（同样由 `@__DIR__` 推导） | `src/MarsData.jl:22,25,66,70,75`；`common/head.jl:28`；`calculate/calculate_models.jl:4-5` 等 | 相对 include 随文件位置变化，**必须逐个重算** |
| 仓内**已存在** Fortran DLL 的统一查找口径，但 IGRF **未使用**它 | `common/paths.jl:60-71` `fortran_dll_dir()`（config `paths.fortran_dll_dir` → 仓库根）；`call_fortran_dll.jl:14-27` 按该口径查找并 `@warn` 旧硬编码回退 | IGRF 的 DLL 定位是"另一套"，迁移时可选择统一；**本审计只记录不改** |

---

## 1. 单元 A：`Magnetic_Model/IGRF_calculate.jl` → `models/`

### 1.1 对象与目标

| 项 | 值 |
|---|---|
| 移动源 | `Magnetic_Model/IGRF_calculate.jl`（839 行，33978 B） |
| 目标 | `models/IGRF_calculate.jl`（目标目录已存在，含 6 个 `.jl`） |
| 同目录伴随物 | `Magnetic_Model/gh_gao`（197152 B，Fortran 无格式系数）、`Magnetic_Model/IGRF_DLL.dll`（27136 B）、`Magnetic_Model/gh_gao.txt`（443556 B） |
| 入库状态 | 四个文件**均受 Git 跟踪**（`git ls-files Magnetic_Model` 列出全部）；`git check-ignore -v` 对 `IGRF_DLL.dll`/`gh_gao`/`gh_gao.txt` 退出码 1 ⇒ **未被 `.gitignore` 排除**（与旧报告 `refactoring_diagnosis_report.md:448` 的"DLL 被 gitignore 排除"表述已不一致，以本次实测为准） |
| 前置约束 | 按 `.agent/target_architecture_execution.md:252` 文件锁：本单元排在 **`Bpc2sphere` 迁出之后**；波 2 的 `MAVEN_load` 旧副本删除亦须先完成 |

### 1.2 引用点清单（按载体分类）

**代码（必须更新）**

| 位置 | 内容 | 迁移后应变为 |
|---|---|---|
| `src/modules.jl:87-90` | `:IGRF_calculate => _spec(:IGRF_calculate, "Magnetic_Model/IGRF_calculate.jl", …)` | `"models/IGRF_calculate.jl"` |
| `example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl:15` | `include("../../Magnetic_Model/IGRF_calculate.jl");import .IGRF_calculate;` | `include("../../models/IGRF_calculate.jl")` |
| `example/MAVEN_plot_sample/MAVEN_overview_cases.jl:15` | 同上 | 同上 |
| `models/Pickup_ion.jl:278` | `include(pkg_path*"Magnetic_Model/IGRF_calculate.jl");import .IGRF_calculate;` | 见 §3（该行同时是 Pickup 单元的问题行） |

**代码（间接/无需改，但需回归确认）**

| 位置 | 说明 |
|---|---|
| `src/MarsData.jl:16` | `MarsData.@load MAVEN_STATIC IGRF_calculate` —— 按**符号名**装载，路径来自注册表 ⇒ 无需改 |
| `test/runtests.jl:173-174,192,277,379` | 全部按 `:IGRF_calculate` 符号/`MarsData.IGRF_calculate` 访问；`:379` 断言 `MODULE_REGISTRY[:IGRF_calculate].allow`；**仅 207 行注释提到 DLL 文件名** ⇒ 无需改路径字面量 |

**注释（可不动；若清理须单独单元）**

`models/Single_Particle_Orbit.jl:404-405`（`# include(EnvironmentPath*"Magnetic_Model/IGRF_calculate.jl")`）、`common/MarsCommon.jl:23`、`MAVEN_data/MAVEN_load.jl:960`、`MAVEN_data/MAVEN_SWEA.jl:137`、`MAVEN_data/MAVEN_load.jl:1541`、`common/function_coordinate.jl:261`、`TW_data/TW_MINPA.jl:289`、`Magnetic_Model/IGRF_calculate.jl:303-304,542-543`（旧硬编码 DLL 路径的注释）。

**现行文档（需更新）**

`README.md:93`（目录表）、`:188`（DLL 说明）、`:220-222`（`include("path/Magnetic_Model/IGRF_calculate.jl")` 示例）、`:292`（路径列表）；`README_EN.md:82,160,197-199`；`docs/src/api.md:18`（blob 链接）、`:213`（小节标题 `### Magnetic_Model/IGRF_calculate.jl`）；`docs/src/pipeline.md:193`；`docs/src/index.md:90`。

**历史记录（不改）**：`CHANGELOG.md:78,155,191,543,587,610,621`；`docs/reports/refactoring_audit_a42e14b.md:15,22,64,193,284`；`docs/reports/refactoring_diagnosis_report.md:156,348,448`。

### 1.3 内部路径与数据/DLL 依赖（本单元的核心风险）

```julia
806: const NIGRF = 110
807: root_dir = dirname(@__FILE__)
808: gh_filename = root_dir * "/gh_gao"
809: const IGRF_DLL_PATH = root_dir * "/IGRF_DLL.dll"
812: const GG, HH = read_gh()
```

| 依赖 | 解析方式 | 移动到 `models/` 后（若只移动 `.jl`） | 严重度 |
|---|---|---|---|
| 系数文件 `gh_gao` | `dirname(@__FILE__) * "/gh_gao"`，经 `read_gh()` → `FortranFile(gh_filename)` 在**模块加载时**执行（`:812`；docstring `:194` 明示"文件缺失会导致模块加载失败"） | 解析为 `models/gh_gao` → **不存在 ⇒ 模块装载直接失败**（`load_module(:IGRF_calculate)` 与 `@load` 全断） | **阻断级** |
| DLL `IGRF_DLL.dll` | `dirname(@__FILE__) * "/IGRF_DLL.dll"`，作为 `ccall((sym, IGRF_DLL_PATH), …)` 的**运行时路径**（`:229,262,306,545`） | 解析为 `models/IGRF_DLL.dll` → 首次调用即失败；`test/runtests.jl:197-205` 的 `:euler`/`:rk4` 分支会触发 | **高（测试可捕获）** |
| `gh_gao.txt` | **代码零引用**（全仓仅 `:179` docstring 与 `:808` 提到 `gh_gao`；无 `gh_gao.txt` 命中） | 若只移动 `.jl`，该文件留在 `Magnetic_Model/` 成为孤儿 | 低（真实性待 t5 判定） |

**结论**：单元 A **不是"单文件移动"**。要么把 `gh_gao`（+可选 `gh_gao.txt`）与 `IGRF_DLL.dll` **一并移动**，要么把 `:807-809` 改写为不依赖文件自身位置的定位（例如沿用 `Paths.fortran_dll_dir()` + `Paths.project_root()`，但 `common/paths.jl` 的 `PROJECT_ROOT` 与 `fortran_dll_dir()` 都指向**仓库根**，与"数据放在 `models/`"不一致——需 t5/t10 明确取舍）。两者都必须同时改 `:808/:809` 的表达式或移动文件，不存在"只移动 .jl 仍可用"的路径。

### 1.4 动态拼接与 CWD 假设

- `:807` 用 `@__FILE__` ⇒ 位置敏感但**不依赖 CWD**（从任意工作目录装载结果一致）。
- 无 `pwd()`/`cd()`/`raw"…"` 直接命中（`:304,543` 的 `raw"D:\CODE\..."` 与 `:303,542` 的 `"Megnetic_Model/IGRF_DLL.dll"`（原文拼写）均为**注释**，不参与运行）。
- `IGRF_DLL_PATH` 是 `const`，但 `gh_filename` 是**普通全局量**（非 const）⇒ 两者的解析时机不同（`const` 在 include 时求值一次；同样在 include 时）。无延迟解析。

### 1.5 风险清单（单元 A）

| ID | 风险 | 级别 | 依据 |
|---|---|---|---|
| A-R1 | 只移动 `.jl` ⇒ `gh_gao` 找不到，**模块加载失败** | 阻断 | §1.3 `:807-808,812` |
| A-R2 | DLL 不随迁 ⇒ `trace_mag_line`/`IGRF_pc` 等 `ccall` 失败；`runtests` 的 IGRF 用例转红 | 高 | §1.3 `:809`，`test/runtests.jl:197-205` |
| A-R3 | 二进制/数据进 `models/`（源码目录）造成"源码树含 DLL+197KB 系数+443KB 文本"的布局问题 | 中 | 目录用途；需 t5 决策 |
| A-R4 | 若改用 `Paths.fortran_dll_dir()`，会把 DLL 查找口径指向 `config/settings.toml`/仓库根，与 `gh_gao` 的 `models/` 位置不一致，形成"两个位置" | 中 | `common/paths.jl:60-71` |
| A-R5 | 文档/示例漏改（4 处现行文档 + 2 个示例）⇒ 用户按文档 `include("path/Magnetic_Model/IGRF_calculate.jl")` 断链 | 中 | §1.2 |
| A-R6 | `gh_gao.txt` 是否仍需要（无代码引用）未定 ⇒ 可能留下孤儿大文件 | 低 | §1.3 |

### 1.6 更新清单（单元 A，执行者须逐条勾选）

1. `git mv Magnetic_Model/IGRF_calculate.jl models/IGRF_calculate.jl`
2. **同批**移动 `gh_gao`（必需）与 `IGRF_DLL.dll`（必需或改路径表达式）；`gh_gao.txt` 处置由 t5 决策（移动/删除/保留原位）
3. `src/modules.jl:88` 路径串 → `"models/IGRF_calculate.jl"`
4. `example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl:15`、`MAVEN_overview_cases.jl:15` → `../../models/IGRF_calculate.jl`
5. `models/Pickup_ion.jl:278`（与单元 C 同批处理，见 §3）
6. 现行文档：`README.md`(4 处)、`README_EN.md`(3 处)、`docs/src/api.md`(2 处)、`docs/src/pipeline.md:193`、`docs/src/index.md:90`
7. 若采用"改 `:807-809` 表达式"方案：由该单元的负责人单独提交，且不得与文件移动混在同一 diff 语义之外
8. 不动 `CHANGELOG.md` 与 `docs/reports/*`

### 1.7 验证方式（单元 A）

| # | 验证 | 期望 |
|---|---|---|
| A-V1 | `julia --project=. -e 'using MarsData; MarsData.load_module(:IGRF_calculate)'` | 无异常（证明 `gh_gao` 在新位置被读到） |
| A-V2 | `julia --project=. test/runtests.jl` | IGRF 两个 `@testset`（`combina_two_dir_trace`、`trace_mag_line`）保持通过；总数不低于迁移前现场值 141 Pass / 1 Broken |
| A-V3 | `grep -rn "Magnetic_Model/IGRF_calculate" --include="*.jl" --include="*.md" .`（排除 `docs/reports`、`CHANGELOG`） | 无命中（除历史记录） |
| A-V4 | `julia --project=. -e 'using MarsData; I=MarsData.IGRF_calculate; I.IGRF_pc(3393.5,1.0,0.5)'`（DLL 真调用） | 无 `could not load library` 类错误 |
| A-V5 | `git status --porcelain` + `git diff --name-status` | 仅预期的移动/路径改动，无其他源码漂移 |

## 2. 单元 B：Extras（`models/Graham.jl`、`models/Octree.jl`）→ `models/extras/`

### 2.1 对象与目标

| 项 | 值 |
|---|---|
| 移动源 | `models/Graham.jl`（121 行，4310 B）、`models/Octree.jl`（9603 B）；二者均受 Git 跟踪 |
| 目标 | `models/extras/` —— **该目录当前不存在**（`Get-ChildItem -Recurse -Directory` 无 `extras` 命中），须新建 |
| 规格依据 | `.agent/target_architecture_execution.md:62`「X Extras：Octree、Grahame…（CATALOG.toml 登记；任何层都不得依赖 X）」；`:222` 波 3 |
| **命名核实** | 规格文档写作 `Grahame`，**实际文件名是 `Graham.jl`**（`git ls-files models` 实测）。本审计以实测文件名为准；后续不得据此造出 `Grahame.jl` |
| 登记现状 | `src/modules.jl` 注册表**无** `Octree`/`Graham` 条目（18 条列表见 `CHANGELOG.md:191`）⇒ 二者当前**不可经 `MarsData.load_module` 装载**；规格要求的 `CATALOG.toml` **仓库中不存在** |

### 2.2 文件形态（决定"移动是否安全"的关键事实）

| 文件 | 形态 | 证据 |
|---|---|---|
| `models/Graham.jl` | **无 `module` 包裹**（脚本式）；第 2 行即顶层 `struct Point` | `:1` 注释、`:2-5` `struct Point`、`:25` `graham_scan!`、`:98` `graham_scan_for_orbit` |
| `models/Octree.jl` | **无 `module` 包裹**；依赖 `using GLMakie`/`GeometryBasics`/`StaticArrays` | `:3-5` using、`:8` `OctreeNode`、`:63` `build_octree!`、`:126` `get_min_bounding_box`、`:150` 内层 `find_boundaries` |
| 内部相对 include | **两文件均无**（不含 `include`、无 `@__DIR__`/`open`/`readdir`/DLL 路径字符串） | §0.1 include 检索口径下无命中 |

### 2.3 引用点清单

**代码引用：零。** `grep -rn "build_octree\|get_min_bounding_box\|find_boundaries\|graham_scan!"`（`*.jl`）仅命中 `models/Octree.jl` 与 `models/Graham.jl` **自身**；`include(...Graham/Octree...)` 全仓无命中。

| 载体 | 位置 | 处置 |
|---|---|---|
| 文档（现行） | `docs/src/api.md:301`（小节标题 `### models/Graham.jl、models/Octree.jl`）、`:303-307`（函数说明） | 路径改为 `models/extras/…` |
| 历史记录 | `docs/reports/refactoring_audit_a42e14b.md:170,205`、`docs/reports/refactoring_diagnosis_report.md:249` | **不改** |
| 易混淆项（非引用） | `MAVEN_data/MAVEN_plot.jl:719-729` 内部定义了**另一个嵌套函数** `graham_scan(points)`（与 `Graham.jl` 的 `graham_scan!` 同名不同实现、不同作用域，`MAVEN_plot.jl:899` 的调用被注释） | 不随本单元变化；属"重复实现"，交 t5 评估，本审计不改 |

### 2.4 动态拼接与 CWD 假设

无。两文件不含任何路径表达式，也不含 `pwd()`/`cd()`/`dirname(@__FILE__)`。

### 2.5 风险清单（单元 B）

| ID | 风险 | 级别 | 依据 |
|---|---|---|---|
| B-R1 | `models/extras/` 需新建；规格要求"任何层都不得依赖 X"，但**仓内无任何机制强制**（无 `CATALOG.toml`、无注册表条目、无 lint） | 中 | `target_architecture_execution.md:62` |
| B-R2 | 两文件无 `module` 包裹且 `Graham.jl` 顶层定义 `struct Point` ⇒ 若未来以 `include` 进入共享命名空间，易与 `GeometryBasics.Point`/Base 名称冲突 | 中 | `Graham.jl:2`、`Octree.jl:3-4` |
| B-R3 | 无目录扫描型装载器（§0.2-②）⇒ 移动后**不会**被自动装载；反之若要"可装载"必须显式登记 | 中 | `readdir` 三处均与源码目录无关 |
| B-R4 | `Octree.jl` 依赖 `GLMakie`（GUI 重依赖）；若登记进注册表会引入图形栈 | 低 | `Octree.jl:3` |
| B-R5 | 无调用点 ⇒ **无行为回归面**；风险集中在可发现性/文档与将来登记 | 低 | §2.3 |
| B-R6 | 文档名 `Grahame` vs 实际 `Graham.jl` 的命名漂移，迁移脚本若按文档名操作会失效 | 低但易错 | §2.1 |

### 2.6 更新清单（单元 B）

1. 新建 `models/extras/`；`git mv models/Graham.jl models/extras/Graham.jl`、`git mv models/Octree.jl models/extras/Octree.jl`
2. `docs/src/api.md:301` 标题与相邻链接改为 `models/extras/…`
3. 若 t5 决定登记（`CATALOG.toml` / 注册表条目）→ 属 t5/t10 设计批次，**不在本单元**执行
4. 不动 `CHANGELOG.md`、`docs/reports/*`
5. 不做"顺手重构"（不加 `module` 包裹、不改 `struct Point`）；否则破坏 R-2 原子性与文件锁

### 2.7 验证方式（单元 B）

| # | 验证 | 期望 |
|---|---|---|
| B-V1 | `grep -rn "models/Graham.jl\|models/Octree.jl" --include="*.jl" .` | 无命中（证明确无代码断链） |
| B-V2 | `julia --project=. -e 'include("models/extras/Graham.jl")'` 后调用 `graham_scan!`（自造 3–4 点冒烟） | 可装载、函数可调用（人工冒烟，非门禁） |
| B-V3 | `julia --project=. -e 'include("models/extras/Octree.jl")'` | 可装载（`using GLMakie` 需依赖可用） |
| B-V4 | `julia --project=. test/runtests.jl` | 计数与迁移前一致（141 Pass / 1 Broken），证明移动无副作用 |
| B-V5 | `git status --porcelain` | 仅两文件重命名 + 文档改动 |

## 3. 单元 C：`models/Pickup_ion.jl` → `analysis/`

### 3.1 对象与目标

| 项 | 值 |
|---|---|
| 移动源 | `models/Pickup_ion.jl`（475 行，22935 B，受 Git 跟踪） |
| 目标 | `analysis/` —— **当前不存在**（`Test-Path analysis` = False），须新建 |
| 规格依据 | `.agent/target_architecture_execution.md:222`（波 3）、`:244` 文件锁「第 3 行入口更新 → 移动 → 函数化」 |
| 文件形态 | **脚本式入口**，无 `module` 包裹；`:1` 注释明示"建议使用 include 执行"；大量代码位于顶层 `if` 块内（`docs/reports/refactoring_audit_a42e14b.md:42` 亦记录该结构） |
| 与 `head.jl` 的关系 | 本文件 `include` `common/head.jl`（仓内**唯一**处，见 `execution_decisions.md:129`）；反向无引用 |
| 注册表现状 | 注册表**无** `:Pickup_ion` 条目 ⇒ 当前不可经 `load_module` 装载 |

### 3.2 内部相对 include（本单元"是否安全"的决定性一节）

```julia
3: include("../common/head.jl")
4: include("../common/function_coordinate.jl")
5: if !isdefined(@__MODULE__, :constants)
6:     include(joinpath(@__DIR__, "..", "common", "constants.jl"))
7: end
8: if !isdefined(@__MODULE__, :MarsCommon)
9:     include(joinpath(@__DIR__, "..", "common", "MarsCommon.jl"))
10: end
```

| 形式 | 现位置 `models/` 下的解析 | 迁到 `<repo>/analysis/` 后的解析 | 是否需改 |
|---|---|---|---|
| `"../common/head.jl"`（:3） | `<repo>/common/head.jl` | `<repo>/common/head.jl`（`analysis/..` = 仓库根） | **不需要**（前提：`analysis/` 直接位于仓库根） |
| `"../common/function_coordinate.jl"`（:4） | 同上 | 同上 | **不需要**（同前提） |
| `joinpath(@__DIR__,"..","common","constants.jl")`（:6） | 同上 | 同上 | **不需要**（同前提） |
| `joinpath(@__DIR__,"..","common","MarsCommon.jl")`（:9） | 同上 | 同上 | **不需要**（同前提） |

- **结论**：只要目标目录是 `<repo>/analysis/`（与 `common/` 同级、深度相同），上述 4 处相对 include **保持有效**，这正是与单元 A 的关键差别（A 的解析依赖 `dirname(@__FILE__)`+同目录数据文件，C 只依赖"上一级"）。
- `common/head.jl` 自身不受影响：其 `:28` `Package_path = normpath(joinpath(@__DIR__,".."))*"/"` 由 **head.jl 自己的位置**推导 → 仍指向仓库根；其后 `:30-35` 的 include 目标（`MAVEN_data/*`、`support_data/*`、`models/Maxwellian_Distribution.jl`）均不属本审计三单元。
- ⚠ 该结论**强依赖**"`analysis/` 在仓库根"这一前提（见 C-R1）。若 t5 改为 `models/analysis/` 或更深位置，:3/:4/:5-10 将全部断裂，需改 4 行并重跑 C-V1。

### 3.3 硬编码/动态拼接路径（本单元最危险处）

```julia
271:    catch
272:        if !isdefined(Main, :MAVEN_load)
273:            pkg_path = "D:/CODE/Package_for_Julia/"
274:            include(pkg_path*"MAVEN_data/MAVEN_load.jl");import .MAVEN_load;
275:            include(pkg_path*"MAVEN_data/MAVEN_plot.jl");import .MAVEN_plot;
276:            include(pkg_path*"MAVEN_data/MAVEN_STATIC.jl");import .MAVEN_STATIC;
277:            include(pkg_path*"MAVEN_data/MAVEN_SWIA.jl");import .MAVEN_SWIA;
278:            include(pkg_path*"Magnetic_Model/IGRF_calculate.jl");import .IGRF_calculate;
279:        end
```

| 项 | 分析 |
|---|---|
| 触发条件 | 顶层 `try` 读取 MAVEN 数据抛异常 **且** `Main` 中尚无 `MAVEN_load`（`:271-272`） |
| 性质 | **绝对路径硬编码**（`D:/CODE/Package_for_Julia/`，原作者机器路径）→ 在非该布局的机器上必然失败；**迁移前后皆坏**（既有缺陷，非迁移引入） |
| 与单元 A 的耦合 | `:278` 指向 `Magnetic_Model/IGRF_calculate.jl` ⇒ 单元 A 完成后此行必然失效 |
| 处置选项（交 t5/t10 决定，本审计不实施） | (a) 删除该分支，改为明确报错/要求先 `using MarsData`（符合 R-1/R-4 精神）；(b) 改为 `@__DIR__`/`Paths.project_root()` 推导的相对路径。**不建议**只把 `D:/…` 换成另一个硬编码根 |

### 3.4 引用点清单

| 载体 | 位置 | 处置 |
|---|---|---|
| 代码引用（include/调用） | **全仓零命中**：`grep -rn "Pickup_ion\|pickup_ion"` 的 `*.jl` 命中仅为该文件自身 | 无需改调用点 |
| 注册表 | `src/modules.jl` 无 `:Pickup_ion` | 无需改；若 t5 要登记则另批处理 |
| 现行文档 | `docs/src/api.md:295`（小节标题 `### models/Pickup_ion.jl`） | 改路径 |
| 历史记录 | `CHANGELOG.md:26,139,165,309` | **不改** |
| 无关同名词 | `MAVEN_data/Build_data/KP重构为cdf.py:146-150,360`（CDF 变量名 `static_dominant_pickup_ion_*`） | 不涉及本文件 |
| 外部使用者 | 按 HD-13「不发布，仅在文档中标注，由使用者自行适配」 | 仅文档标注 |

### 3.5 动态拼接与 CWD 假设

- 无 `pwd()`/`cd()`；数据根由 `common/paths.jl`（`@__DIR__` 推导）决定 ⇒ **与 CWD 无关**。
- 唯一绝对路径是 §3.3 的 `pkg_path`（`:273`）。
- 顶层存在大量立即执行的副作用代码（读数据/计算），移动**不改变**该行为，但"函数化"单元必须覆盖（属波 3 后半，见 `:223`）。

### 3.6 风险清单（单元 C）

| ID | 风险 | 级别 | 依据 |
|---|---|---|---|
| C-R1 | **目标位置未定**：若 `analysis/` 不在仓库根，4 处相对 include 全部断裂 | 高 | §3.2 |
| C-R2 | `:273-278` 硬编码 `D:/CODE/Package_for_Julia/` 且 `:278` 指向旧 IGRF 位置 | 高（既有） | §3.3 |
| C-R3 | 无 `module` 包裹 + `if !isdefined` 保护式 include ⇒ 多次 include 会重复执行顶层副作用 | 中 | `:5-10` 模式仅保护 constants/MarsCommon，不保护本文件整体 |
| C-R4 | 迁到 `analysis/` 后语义从"模型文件"变为"分析入口"，但函数化尚未做 ⇒ 单元边界须由 t5 明确 | 中 | `:244` 文件锁顺序 |
| C-R5 | 与单元 A 的耦合（`C:278` ↔ `A` 路径） | 中 | §3.3 |
| C-R6 | `common/head.jl` 的 Q-1 决策（删除 or 保留）会反作用到 `:3` | 中 | `execution_decisions.md:319` Q-1 |
| C-R7 | 文档遗漏（api.md）致外部使用者按旧路径 include | 低 | §3.4 |

### 3.7 更新清单（单元 C）

1. 新建 `<repo>/analysis/`；`git mv models/Pickup_ion.jl analysis/Pickup_ion.jl`
2. 复核 `:3/:4/:6/:9` 相对 include 在 `analysis/` 下仍成立（成立则**不改**，仅记录复核结论）
3. 处置 `:273-278`（删除硬编码分支 或 改为 `@__DIR__`/`project_root()` 推导；若保留对 IGRF 的 include，须与单元 A 的**新**路径一致）
4. `docs/src/api.md:295` 路径更新
5. 与 Q-1 联动：若 `common/head.jl` 被删除，`:3` 同批更新（Q-1 未决 ⇒ 本单元须以 Q-1 决策为前提或与之同批）
6. 不做函数化（属后续单元），不在本单元改 `module` 包裹

### 3.8 验证方式（单元 C）

| # | 验证 | 期望 |
|---|---|---|
| C-V1 | 路径可解析性检查（不触发重活）：`julia --project=. -e 'for p in ["analysis/../common/head.jl","analysis/../common/function_coordinate.jl","analysis/../common/constants.jl","analysis/../common/MarsCommon.jl"]; println(isfile(p), " ", p); end'` | 四行均 `true` |
| C-V2 | `grep -n "D:/CODE/Package_for_Julia" analysis/Pickup_ion.jl` | 无命中（若采纳 §3.3 处置） |
| C-V3 | `grep -rn "models/Pickup_ion" --include="*.jl" .` | 无命中 |
| C-V4 | `julia --project=. test/runtests.jl` | 计数与迁移前一致（141 Pass / 1 Broken）；本文件不在测试覆盖内 ⇒ 计数变化即为异常信号 |
| C-V5 | 人工冒烟（可选，需真实数据）：按 `:1` 注释准备 `time_event`/`instrument_mode` 后 include 运行 | 依赖外部数据，**不作为门禁** |

---

## 4. 跨单元耦合与执行顺序（审计结论）

| 耦合 | 内容 | 约束 |
|---|---|---|
| A ↔ C | `models/Pickup_ion.jl:278` include 了 IGRF 的旧路径 | 两单元必须**同批**或在 A 完成后同步更新；否则留下断链 |
| A ↔ 波 2 | `target_architecture_execution.md:252`：`Magnetic_Model/IGRF_calculate.jl` 的 `Bpc2sphere` 先迁出，再移动 | A 不得早于该迁出单元 |
| C ↔ Q-1 | `execution_decisions.md:319`：`common/head.jl` 去留未决；`:3` 依赖它 | C 须与 Q-1 决策同批或以其为前置 |
| B ↔ 其他 | 无代码耦合（零调用点、无注册表条目） | B 可在任一时点独立执行 |
| 共享文件 | `src/modules.jl` 仅 **A** 需要改（B/C 无注册表条目）；若 B 要登记 `CATALOG.toml`，该文件为新文件、无锁竞争 | 按 §7 文件锁排队 |

**建议执行次序（仅供参考，最终以 t5 的 DAG 为准）**：A（含伴随数据/DLL 决策）→ C（同批修 `:278`）→ B（独立）。

---

## 5. 未决项与交接

| ID | 未决项 | 影响单元 | 归属 |
|---|---|---|---|
| U-1 | `gh_gao`/`gh_gao.txt`/`IGRF_DLL.dll` 是"随迁"还是"改表达式" | A | t5/t10 |
| U-2 | IGRF 的 DLL 是否统一到 `Paths.fortran_dll_dir()`（该口径指向 `config/settings.toml`/仓库根，与 `models/` 不一致） | A | t5/t10 |
| U-3 | `analysis/` 是否确为仓库根目录（§3.2 结论的前提） | C | t5 |
| U-4 | Extras 是否登记（`CATALOG.toml` 当前不存在） | B | t5/t10 |
| U-5 | `gh_gao.txt` 是否为死文件（代码零引用） | A | t5 |
| U-6 | `MAVEN_data/MAVEN_plot.jl:719-729` 的重复 `graham_scan` 是否并入 extras | 超出本审计 | t5 |
| U-7 | 文档命名 `Grahame` → `Graham.jl` 的更正 | B | t5/t10 |

**本审计未做（如实声明）**：未移动/改名任何文件；未做 AST 级全仓引用分析（采用文本检索 + 关键行人工阅读）；未覆盖仓库之外的用户笔记本/外部脚本（HD-13 已决定仅文档标注）；未判定 API 兼容策略（属 t2/t5）；三个单元的"验证方式"均为**建议**，未在本任务中执行。

### 附录：本次审计实际执行的只读命令（可复现）

```
git ls-files | Select-String "IGRF|Extras|Pickup|extras|pickup"
git ls-files Magnetic_Model ; git ls-files models
git check-ignore -v Magnetic_Model/IGRF_DLL.dll Magnetic_Model/gh_gao Magnetic_Model/gh_gao.txt
grep -rn "IGRF_calculate|IGRF_DLL|gh_gao|Magnetic_Model" .
grep -rn "Pickup_ion|pickup_ion" .
grep -rn "graham|octree|Graham|Octree" --glob "*.jl"
grep -rn "build_octree|get_min_bounding_box|find_boundaries|graham_scan!" --glob "*.jl"
grep -rn "readdir|walkdir|include\(|joinpath|@__DIR__|@__FILE__|dirname\(" --glob "*.jl"
grep -rn "IGRF|Magnetic|Pickup|Octree|Graham|dll|models" config/
Get-ChildItem -Recurse -Directory | Where-Object { $_.Name -match "extras" }
Test-Path ".agent/physical_path_audit.md" ; Test-Path "analysis" ; Test-Path "config/settings.toml"
（人工阅读）Magnetic_Model/IGRF_calculate.jl:182-217,795-830 ; models/Pickup_ion.jl:1-12,262-301 ;
          models/Graham.jl:1-8 ; models/Octree.jl:3-5 ; common/head.jl:28-35 ; common/paths.jl:1-73 ;
          src/modules.jl:75-134,230 ; src/MarsData.jl:15-35,66-75 ; call_fortran_dll.jl:1-30 ;
          test/runtests.jl:168-212
```

> 报告结束。本文件为 t4 唯一产出；三个单元的引用点、内部路径、风险、更新清单与验证方式均已分单元列出。执行者不得据"文本无命中"跳过 A-V1/A-V4 与 C-V2 的现场验证。
