# 00_PROJECT_SCOPE.md — PHASE 0：项目范围与边界

> 状态：DONE（本文件为 PHASE 0 产物，后续阶段只读本文件与所需最小源码，不再重复全仓扫描）
> 阶段：PHASE 0 - Project Scope
> 负责：DeepSeek V4 Pro (Project Explorer / deepseek-explorer)
> 全量仓库扫描（目录树 + 源码职责映射）留给 PHASE 1（`01_PROJECT_MAP.md`）。

**本文件依据**（仅读根目录清单/说明文件与浅层目录列表，未做全仓扫描）：
`README.md`、`README_EN.md`、`CHANGELOG.md`、`Project.toml`、`Manifest.toml`、`requirement.jl`、
`requirements.txt`、`pyproject.toml`、`.gitignore`、`config/settings.example.toml`。

---

## 1. 范围界定

本次重构（PHASE 0–9）**只针对 Julia 数据处理与科学计算部分**。Python 下载与文件维护部分**完全 out of scope，任何阶段不得修改**。

### 1.1 In scope（Julia 侧，可读可改）

| 路径 | 内容 |
| --- | --- |
| `src/`（`MarsData.jl`、`modules.jl`、`plotting.jl`） | Julia 包 `MarsData`：轻量公共 API、模块注册表/装载机制、包化绘图 |
| `common/`（`constants.jl`、`head.jl`、`paths.jl`、`MarsCommon.jl`、`function_coordinate.jl`） | 通用常量、路径解析、坐标/物理标量函数 |
| `MAVEN_data/`（`MAVEN_load.jl`、`MAVEN_plot.jl`、`MAVEN_STATIC.jl`、`MAVEN_SWIA.jl`、`MAVEN_SWEA.jl` 等） | MAVEN 数据读取、仪器处理、绘图基元、数据格式定义 |
| `MGS_data/`（`MGS_load.jl`）、`TW_data/`（`TW_load.jl`、`TW_MINPA.jl`） | MGS 与天问一号读取和处理 |
| `models/`（`Cold_Plasma_Dispersion_Relation.jl`、`Maxwellian_distribution.jl`、`Single_Particle_Orbit.jl`、`Pickup_ion.jl`、`Octree.jl`、`Graham.jl`） | 等离子体、粒子轨道等物理模型 |
| `Magnetic_Model/`（`IGRF_calculate.jl`） | 火星磁场模型（依赖 Fortran DLL，见 §3） |
| `calculate/`（`calculate_models.jl`） | 模型计算流程与组合入口 |
| `support_data/`（`support_data_load.jl`） | 外部支持数据读取 |
| `config/settings.toml` 的**读取**（Julia 侧） | Julia 侧数据根路径等配置的读取；文件本体由 Python 迁移工具生成，改动需另行决策 |
| `test/`（`runtests.jl`）、`example/`（Julia 示例）、`docs/` 的 Julia 文档源与构建（`docs/make.jl`、`docs/src/*.md` 中的 Julia 相关内容） | Julia 测试、示例、文档 |

### 1.2 Out of scope（Python 侧与基础设施，一律只读、不得修改）

| 路径 | 内容 | 原因 |
| --- | --- | --- |
| `download_data/` | MAVEN 下载、完整性检查、压缩、清理脚本 | 任务硬性规定：Python 下载部分不改动 |
| `martian_pipeline/` | Python 包化 CLI（scan/check/clean） | Python 侧 |
| `config/`（`config.py`、`paths.py`、`utils.py`、`settings.example.toml`） | Python 配置层 | Python 侧；`settings.toml` 本身被 `.gitignore` 排除 |
| `tools/`（`migrate_config.py`、`scan_and_index.py`、`push_wiki.py` 等） | Python 工具脚本 | Python 侧 |
| `tests/`（`test_p0.py`–`test_p3.py`、`test_package.py`） | Python 回归测试 | Python 侧测试 |
| `requirements.txt`、`pyproject.toml` | Python 依赖清单 | 任务硬性规定 |
| `MAVEN_data/build_read_me.py`、`MAVEN_data/Build_data/` 的 Python 构建部分 | 派生 CDF 构建（依赖 spacepy/NASA CDF） | Python 侧 |
| `.agent-teams/` | AgentTeams 协调状态（team.json、inbox） | 运行时状态，只读诊断，禁止直接编辑 |
| `.git/`、`logo.jpg`、`LICENSE`、`.gitattributes`、`.gitignore` | 仓库元数据与素材 | 与重构目标无关 |

> 注意：`MAVEN_data/`、`MGS_data/`、`TW_data/`、`support_data/` 目录内**同时存在** `.jl`（in scope）与个别 `.py`/`.json`/`.png` 文件；判定粒度是**文件**：`.jl` 文件属于 Julia 重构范围，其余文件默认只读，确需改动须在对应阶段文档中单独说明理由。

### 1.3 根目录文件边界

| 文件 | 边界 |
| --- | --- |
| `Project.toml` / `Manifest.toml` | Julia 包 `MarsData`（uuid `9e0bb210-…-9c1467dafac6`，`[compat] julia = "1.10"`，Manifest 记录 `julia_version = "1.10.0"`）。仅在 Julia 侧重构明确需要时修改依赖，且修改必须能在 `julia 1.10` 下 instantiate。 |
| `requirement.jl` | Julia 环境初始化清单（历史脚本），与 `Project.toml` 的 `[deps]` 不同步是已知现状；重构如需增删依赖须同步评估此文件。 |
| `README.md` / `README_EN.md` / `CHANGELOG.md` | 说明与变更日志。**Markdown 一律不得删除**；文档同步在 PHASE 8 集中处理。 |
| `call_fortran_dll.jl`、`color_117_modified.txt` | 根目录遗留脚本/数据文件；PHASE 1 扫描时确认职责后再决定是否纳入范围，当前默认只读。 |

---

## 2. 仓库结构概览

```
Julia_for_MartianSpaceData/
├── .agent/                  # 重构阶段交付物（00–09，Markdown，本文件所在目录）
├── .agent-teams/            # AgentTeams 运行时状态（只读诊断，禁止直接编辑）
├── src/                     # [Julia] 包 MarsData：MarsData.jl / modules.jl / plotting.jl
├── common/                  # [Julia] constants / head / paths / MarsCommon / function_coordinate
├── MAVEN_data/              # [Julia] MAVEN 读取、仪器处理、绘图、格式定义（Build_data/ 为 Python 派生构建）
├── MGS_data/                # [Julia] MGS 读取（MGS_load.jl）
├── TW_data/                 # [Julia] 天问一号读取（TW_load.jl / TW_MINPA.jl）
├── models/                  # [Julia] 物理模型（色散关系/麦克斯韦拟合/粒子轨道/Pickup/Octree/Graham）
├── Magnetic_Model/          # [Julia+Fortran] IGRF 磁场模型（IGRF_calculate.jl + IGRF_DLL.dll + gh_gao 系数）
├── calculate/               # [Julia] 模型计算流程组合入口（calculate_models.jl）
├── support_data/            # [Julia] 外部支持数据读取（support_data_load.jl）
├── test/                    # [Julia] runtests.jl
├── example/                 # [Julia] 绘图与数据分析示例（MAVEN_plot_sample/）
├── docs/                    # 文档唯一根目录：src/（Documenter 源）、wiki/、references/、reports/、make.jl
├── download_data/           # [Python] 下载/检查/压缩/清理 —— OUT OF SCOPE
├── config/                  # [Python] 配置层（settings.example.toml + config.py/paths.py/utils.py）—— 只读
├── martian_pipeline/        # [Python] 包化 CLI —— OUT OF SCOPE
├── tools/                   # [Python] 迁移/扫描/推送脚本 —— OUT OF SCOPE
├── tests/                   # [Python] P0–P3 回归测试 —— OUT OF SCOPE
├── Project.toml / Manifest.toml / requirement.jl      # Julia 包与依赖清单
├── pyproject.toml / requirements.txt                  # Python 依赖清单 —— OUT OF SCOPE
└── README.md / README_EN.md / CHANGELOG.md / LICENSE / .gitignore / .gitattributes
```

### 2.1 Julia 侧要点（来自 README/CHANGELOG，详情留待 PHASE 1）

- **包化现状**：`src/MarsData.jl` 提供路径解析、产品注册表、索引读取等公共 API，并承诺**在无本地数据、无 Fortran DLL 的环境下可加载**（不加载任何科学数据 loader）。
- **重模块装载**：`MAVEN_load`、`MAVEN_STATIC`、`MAVEN_SWIA`、`MAVEN_SWEA`、`IGRF_calculate`、`Cold_Plasma_Dispersion_Relation` 等重模块仍以 include 为主，经 `MarsData.load_module` / `MarsData.@load` 包化入口装载；白名单逐名引入（`ModuleSpec.allow`），依赖自动装载、幂等。
- **环境依赖**：Julia ≥ 1.10；`Magnetic_Model/IGRF_calculate.jl` 依赖 C++/Fortran DLL（`IGRF_DLL.dll`，不入库于无 DLL 环境的加载路径）；`MAVEN_data/Build_data/` 派生构建依赖 NASA CDF 库（Python 侧）。

### 2.2 Python 侧要点（只读参考，不改动）

- `download_data/MAVEN_download.py` 下载；`martian_pipeline` CLI（scan/check/clean）维护文件树；`tools/migrate_config.py` 负责 INI→TOML 配置迁移；配置唯一写端为 TOML（`config/settings.toml`，gitignored，本地文件）。
- Python ≥ 3.11；运行依赖见 `pyproject.toml`（requests/beautifulsoup4/tqdm/numpy/pandas/cdflib），可选 build 依赖 spacepy。

---

## 3. 数据目录清单与只读数据边界

### 3.1 原始科学数据（仓库外，绝对只读）

原始 CDF 数据**不在仓库内**，存放在本机配置的根目录（`config/settings.example.toml` 的示例值）：

| 任务 | 配置键 | 示例根路径 |
| --- | --- | --- |
| MAVEN | `paths.maven_data_root` | `E:/MAVEN/` |
| 天问一号 | `paths.tw_data_root` | `E:/Tianwen-1/` |
| MGS | `paths.mgs_data_root` | `E:/MGS/` |

- 本地实际值在 gitignored 的 `config/settings.toml`（不在仓库内），**任何阶段不得读取/写入/搬动这些数据文件**，Julia 侧只通过配置键定位并只读打开。
- 时间轴约定（既有文档约定，重构必须保持）：所有被读取数据的时间轴为排序时序数据；最近邻查找统一用 `MarsCommon.searchsortednearest`（二分 `O(log N)`），**禁止**用 `findmin(abs.(x .- x0))` 线性扫描。

### 3.2 仓库内随代码目录的数据/参考文件（只读，默认不改）

| 路径 | 内容 | 边界 |
| --- | --- | --- |
| `Magnetic_Model/gh_gao`、`gh_gao.txt` | IGRF/火星磁场球谐系数 | 只读输入数据；修改系数=科学算法变更，需人类批准（§4 约束 R5） |
| `Magnetic_Model/IGRF_DLL.dll` | Fortran 导出的磁场计算动态库 | 二进制只读；与 C++/Fortran 环境配套 |
| `MAVEN_data/MAVEN_data_format.json`、`KP_vars.json` | 数据格式/变量定义（`build_read_me.py` 生成物） | 只读参考；其生成端在 Python 侧，Julia 重构不得改写 |
| `MAVEN_data/*.png`、`color_117_modified.txt` | 产物图/色标文件 | 只读 |
| `docs/references/`（含 12 份仪器 SIS PDF、HTML） | 参考资料 | 只读 |
| `example/MAVEN_plot_sample/*.png` | 示例输出图（gitignored） | 不提交、不改动 |

### 3.3 目录命名澄清

`MAVEN_data/`、`MGS_data/`、`TW_data/`、`support_data/` 四个目录按数据源命名，但仓库内实际存放的是**Julia 读取/处理源码**（`.jl`）与格式定义，**不含原始 CDF 数据**。原始数据一律在 §3.1 的外部根目录。PHASE 1 全量扫描时按此边界归类文件。

---

## 4. 重构目标与硬性约束

### 4.1 目标

分阶段（PHASE 0–9）提升 Julia 数据处理与科学计算部分的**结构清晰度、性能与可维护性**，同时保证科学结果不变、文档体系完好、Python 侧零改动。

### 4.2 硬性约束（所有阶段必须遵守）

| 编号 | 约束 | 落实方式 |
| --- | --- | --- |
| R1 | **不删除任何 Markdown** | 所有 `.md` 文件（含 `.agent/`、`docs/src/`、`docs/wiki/`、`docs/reports/` 历史快照）只允许修改或新增，不允许删除；`docs/reports/` 中的历史报告为快照，内容不动 |
| R2 | **性能优化必须 benchmark** | 任何以性能为理由的改动，须记录改动前后基准（同机同数据、多次取中位），结果写入对应阶段交付物；无 benchmark 数据的"优化"不得合入 |
| R3 | **重要代码修改必须有测试** | 公共 API、读取入口、被多处引用的计算函数等的修改/重构，须同步新增或更新 `test/runtests.jl` 测试并运行通过；测试命令与结果记入交付物 |
| R4 | **科学计算修改必须做科学结果验证** | 涉及物理计算（坐标变换、能量-速度、PSD、磁场、模型拟合等）的改动，必须与改动前数值做回归对比（逐位一致或差异在可论证的容差内），并在交付物中给出对比方法、样本与结论；仅"测试通过"不等于科学验证 |
| R5 | **不允许实现 Agent 自行决定重大科学算法** | 新算法、模型替换、系数更换、数值方法更改等属于领域决策，必须由人类（项目作者/领域专家）批准后才可实施；Agent 只能按已批准的规格实现。未经批准发现的问题只记录、不改算法 |
| R6 | **不做无价值的风格性大规模重构** | 纯改名、纯格式化的批量改动禁止；每一项改动必须有功能性、性能或可维护性理由，且理由写入阶段文档。既有破坏性改名（如 `data_get_from_date` → `load_MAVEN_data`）已完成，重构**不得再制造新的破坏性 API 变更**，确有必要时须在阶段文档中单列并同步 README/CHANGELOG |
| R7 | **Python 侧零改动** | §1.2 所列文件在任何阶段不得修改（含文档中描述 Python 流程的内容） |
| R8 | **阶段隔离与最小读取** | 每阶段只读前一阶段交付物 + 完成当前任务所需的最小源码，不做重复全仓扫描（全量扫描只在 PHASE 1） |

### 4.3 阶段交付物链（`.agent/`）

| 文件 | 阶段 | 产出 |
| --- | --- | --- |
| `00_PROJECT_SCOPE.md` | PHASE 0 | 本文件：范围、边界、数据清单、硬性约束 |
| `01_PROJECT_MAP.md` | PHASE 1 | 全量仓库扫描：目录树、源码职责、依赖映射 |
| `02_ARCHITECTURE_REVIEW.md` | PHASE 2 | 架构评审与问题清单 |
| `03_ARCHITECTURE_PLAN.md` | PHASE 3 | 重构方案与分阶段计划 |
| `04_OPTIMIZATION_PLAN.md` | PHASE 4 | 性能优化计划（含 benchmark 方案） |
| `05_TEST_STRATEGY.md` | PHASE 5 | 测试策略 |
| `06_IMPLEMENTATION_LOG.md` | PHASE 6 | 实施日志 |
| `07_VERIFICATION.md` | PHASE 7 | 验证报告（测试 + 科学结果回归） |
| `08_DOCUMENTATION_SYNC.md` | PHASE 8 | 文档同步 |
| `09_FINAL_REVIEW.md` | PHASE 9 | 独立最终评审（独立 DeepSeek V4 Pro 成员） |

每个阶段完成后写入对应文件；下一阶段以其为唯一状态来源。`01–09` 目前为占位文件，由对应阶段任务覆盖。

---

## 5. 已确认的关键事实（供后续阶段引用）

1. Julia 包名 `MarsData`，版本 `0.1.0`，`[compat] julia = "1.10"`；Manifest 记录 `julia_version = "1.10.0"`。
2. `Project.toml` 的 `[deps]` 为轻量集合（Makie/CairoMakie/DataFrames/JSON/TOML 等 15 项）；重依赖（CommonDataFormat、JLD2、FortranFiles、Rotations、CSV、DifferentialEquations、LsqFit 等）在 `requirement.jl` 清单中、经运行时载体机制加载，**不声明进包依赖**——这是 README 明确记载的架构决策，重构不得破坏（否则"无数据、无 DLL 环境可加载"承诺失效）。
3. 配置唯一写端为 TOML（Python 工具生成）；Julia 侧只读。
4. 文档唯一根目录 `docs/`，`docs/src/*.md` 为权威源，Wiki 由 `tools/push_wiki.py`（Python，out of scope）生成。
5. 本地 gitignored 文件：`config/settings.toml`、`docs/build/`、`download_data/MAVEN_download_config.ini`、各类 `*.jld2`/`*.png` 产物。
