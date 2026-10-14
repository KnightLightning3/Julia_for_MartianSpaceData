# current_state_recovery.md — Phase A：继承旧记录 + 当前真实状态恢复

> 任务：t1 [recovery]「继承旧记录并恢复当前真实状态」
> 执行：flash-recovery（DeepSeek Flash / Official）— attempt 1 / `8ae54848-5fa7-471c-9b20-87e898f01306`
> 日期：2026-10-14
> 方法：**先继承 `.agent/` 旧 P0–P6 记录与 `docs/reports/` 旧报告，再对当前代码与 git 状态做定向核实**；未从零重扫全仓，未重复上一轮分析。
> 本文件是本次 t1 的**唯一写入产物**；未改任何项目代码、测试、配置、`new_plan.md`，未创建任何子 Agent。

---

## 0. 结论速览（TL;DR）

| # | 结论 | 证据 |
|---|---|---|
| 1 | 仓库 HEAD = `94da314`（"文档：doc/ 并入 docs/ 统一文档根"），**上一轮 P6 实施全部尚未提交**，停在工作区 | `git log`；`git status --porcelain` 19 个 M 文件；`git diff --shortstat` = 19 files, +2493 / -221 |
| 2 | `.agent/` 旧记录 = 上一轮 P0–P6：`00…06` 有效可继承；`07/08/09` 仍是 PENDING 占位（8 行） | `.agent/06_IMPLEMENTATION_LOG.md` 638 行；`07/08/09` 各 205–218 B |
| 3 | 计划共 48 个 TASK；**已完成 TASK-001…025**（其中 008 因真实数据不可得判为"缺失不阻塞"、013/021 部分验证待补），**TASK-026…043 未开始**，**TASK-044…048（条件性）未触发** | `.agent/04_OPTIMIZATION_PLAN.md` 任务目录；逐任务符号核实（§3） |
| 4 | 测试框架**当前真实可跑**：`julia --project=. test/runtests.jl` → **141 passed / 1 broken / 0 failed，exit 0，19.6 s** | 本次实测（§6.1） |
| 5 | **旧记录未记载的两项已完成工作**：TASK-024（Cold_Plasma PlasmaState）、TASK-025（load_kp `kp_columns`）已在工作区实现，`.agent/06` 未记录 | `models/Cold_Plasma_Dispersion_Relation.jl:7`、`MAVEN_data/MAVEN_load.jl:454`、`test/runtests.jl:215-269` |
| 6 | **最需要人工裁定的差异**：工作区 `Project.toml [deps]` 由 16 个扩到 **45 个**、`Manifest.toml` +1743 行（mtime 10-14 11:29），与 `.agent/06` 自称的红线"`Project.toml [deps]` 未改动"**冲突** | `git diff Project.toml`；§5 D-1 |
| 7 | 本轮 `new_plan.md` 第 8/9 章要求的 **AST 验证框架与函数调用表尚不存在**；现有验证仅覆盖装载层 + 合成 golden 快照 + 少量科学函数 | §6.4；无 call table 文件 |
| 8 | 真实数据环境不可得（`E:/MAVEN`、`E:/MGS`、`E:/Tianwen-1`、`config/settings.toml`、`MAVEN_data/filename_lists.json` 均不存在）；**Python 测试不可运行（无 pytest）** | 本次实测（§2.4） |

**下游可以立即做的事**：以 `.agent/03`+`.agent/04` 为架构/迁移底稿，从 **TASK-026** 续做；先把 §5 的 D-1（依赖清单）与 D-4（孤儿 docstring）裁定清楚，并补建 AST/调用表（Phase B 前置）。

---

## 1. 继承来源清单（读了什么、是否仍有效）

| 文件 | 阶段 | 规模 | 继承判定 |
|---|---|---|---|
| `.agent/00_PROJECT_SCOPE.md` | P0 范围与红线 | 14.9 KB | **有效**：In/Out of scope、数据只读边界、R1–R7 硬约束仍适用 |
| `.agent/01_PROJECT_MAP.md` | P1 全量映射 | 31.0 KB | **基本有效**：19 个注册模块 + 5 个脚本文件、依赖地图、数据流；个别行号随 P6 改动漂移（§5 D-5） |
| `.agent/02_ARCHITECTURE_REVIEW.md` | P2 架构审查（AR-1…AR-30） | 33.2 KB | **有效**：抽样核实 AR-1/2/3/4/6/9/11/13/17/20/29 条目在当前代码仍成立 |
| `.agent/03_ARCHITECTURE_PLAN.md` | P3 目标架构（ARCH-001…017 + 附录 A 数据键契约） | 68.7 KB | **有效，可作 Phase C 底稿**；附录 A 已由 TASK-016 部分落地为 `DataKeys` |
| `.agent/04_OPTIMIZATION_PLAN.md` | P4 迁移计划（TASK-001…048、S0–S11） | 74.6 KB | **有效，可作 Migration Plan 底稿**；进度见 §3 |
| `.agent/05_TEST_STRATEGY.md` | P5 测试策略（五类测试、八项基准、验收门） | 42.0 KB | **有效**：TASK-001 建立的 golden/benchmark 口径正在被实际使用 |
| `.agent/06_IMPLEMENTATION_LOG.md` | P6 实施日志（唯一允许改源码的阶段） | 26.2 KB，mtime 10-14 02:21 | **部分有效**：TASK-001…023 记录；**遗漏 TASK-024/025**；TASK-002 的"无残留"表述不准确（§5 D-3/D-4） |
| `.agent/07_VERIFICATION.md` | P7 验证 | 208 B | **占位（PENDING），无内容** |
| `.agent/08_DOCUMENTATION_SYNC.md` | P8 文档同步 | 218 B | **占位（PENDING），无内容** |
| `.agent/09_FINAL_REVIEW.md` | P9 终审 | 205 B | **占位（PENDING），无内容** |
| `docs/reports/refactoring_audit_a42e14b.md` | 上上轮 AST 函数一致性审查（329 行） | — | **有效历史证据**：AST 对比方法可复用；BUG-1（IGRF 累加器清零）已修；μ0/e 常量的破坏性数值变化仍需知悉 |
| `docs/reports/refactoring_verification_report.md` | P0–P5 重构校验报告（123 行） | — | **有效历史证据**：Python 侧 + Julia 侧逐项校验结论；其中的 pytest 命令当前不可复现（无 pytest） |
| `docs/reports/refactoring_comparison_table.md` | P0–P5 功能/性能对照表（65 行） | — | **有效历史证据**：`git diff a09511a..HEAD` 口径（44 文件 / +2849 / −284） |
| `docs/reports/refactoring_diagnosis_report.md` | 上上轮诊断（70.6 KB） | — | 存在，未逐行复核；**P2 的 AR 清单已覆盖同类结论**，避免重复扫描（按需定向查阅） |

`new_plan.md`（817 行）本次已全文读取：本轮目标、边界（不做函数级性能优化）、22 项核心原则、8 Agent 上限、汇报驱动调度、"先架构后编码 + 人工审查后实施"均已确认。

---

## 2. 当前真实状态（定向核实）

### 2.1 Git 状态

```
HEAD           94da314  (origin/main)  "文档：doc/ 并入 docs/ 统一文档根，Wiki 改为从 docs/src 生成并推送"
分支           main（干净跟踪 origin/main，无本地分支）
工作区         19 个已修改文件，未提交；git diff --shortstat = 19 files changed, 2493 insertions(+), 221 deletions(-)
未跟踪         .agent/  .agent-teams/  benchmark/  common/data_keys.jl  tmp/
```

**HEAD 是 P6 之前的状态**（核实：`git show HEAD:models/Cold_Plasma_Dispersion_Relation.jl` 中 `PlasmaState`/`_state` 命中 0 次；`HEAD:MAVEN_data/MAVEN_load.jl` 仍是旧的模块级 `filename_list` 字典且含 `calculate_mag`）。
→ 因此 **P6 的全部成果目前只存在于工作区，一旦工作区被清理即丢失**，这是当前最大的单点风险（§7 风险 R-1）。

已修改文件与其最后写入时间（用于判定"哪一批工作"）：

| 文件 | mtime | 归属批次（与 `.agent/06` 对照） |
|---|---|---|
| `Manifest.toml` / `Project.toml` | **10-14 11:29** | **无日志记录**（06 写完后才出现，§5 D-1） |
| `MAVEN_data/MAVEN_load.jl` | 10-14 02:27 | TASK-005/006/007/012/013/022/025 |
| `test/runtests.jl`、`models/Cold_Plasma_Dispersion_Relation.jl` | 10-14 02:24 | TASK-015/016/017/024 |
| `MAVEN_data/MAVEN_SWIA.jl`、`TW_data/TW_MINPA.jl` | 10-14 02:19 | TASK-019/023 |
| `Magnetic_Model/IGRF_calculate.jl` | 10-14 02:14 | TASK-004/020/021 |
| `MAVEN_data/MAVEN_STATIC.jl`、`MAVEN_data/MAVEN_SWEA.jl`、`common/MarsCommon.jl`、`src/plotting.jl` | 10-14 02:05–02:07 | TASK-003/014/017/018 |
| `src/MarsData.jl`、`src/modules.jl` | 10-14 02:02 | TASK-015/016 |
| `MGS_data/MGS_load.jl`、`TW_data/TW_load.jl`、`call_fortran_dll.jl`、`common/paths.jl`、`support_data/support_data_load.jl` | 10-13 13:51–13:53 | TASK-009/010/011 |

**时间线判读**：P6 主体（TASK-001…025）在 10-14 02:00–02:30 完成；**随后 11:29 另有一次改动只动了 `Project.toml`/`Manifest.toml`（依赖清单扩张），没有随附日志**。这两点必须在续做前确认（§7 R-2）。

### 2.2 代码级关键路径证据（定向抽查，非重扫）

| 主题 | 证据位置 | 结论 |
|---|---|---|
| 装载管理器 + 注册表 | `src/modules.jl:60-120`（19 条 `_spec`）、`src/MarsData.jl:26`（`using .DataKeys`） | 注册表 19 模块，`Paths`/`DataKeys` 为 `kind=:preloaded` |
| 白名单机制（AR-13 起点） | `src/modules.jl:63,69,89` | 仅 `MarsCommon`/`MAVEN_load`/`IGRF_calculate` 三条非空 `allow`；TASK-042 未做 |
| 注册表自检（TASK-015） | `src/modules.jl:405-457` | 返回 `(errors, warnings)`，docstring 已同步 |
| 惰性文件列表（TASK-007） | `MAVEN_data/MAVEN_load.jl:40` `filename_list()` | 模块加载期不再 `open` JSON |
| 日期索引（TASK-013） | `MAVEN_data/MAVEN_load.jl:51-70` `_FILE_INDEX_CACHE` / `_file_index` | 索引 + 线性回退双路径 |
| loader 白名单去 eval（TASK-012） | `MAVEN_data/MAVEN_load.jl:1514,1531-1535` | `LOADER_FUNCS::Dict{String,Function}`，缺名报清晰错误 |
| 读取错误可见化（TASK-006） | `MAVEN_data/MAVEN_load.jl:173,178,183,196` | `error_report::Vector{String}=String[]` |
| 表头稳健化（TASK-005） | `MAVEN_data/MAVEN_load.jl:387`；`MGS_data/MGS_load.jl:63` | 均改为 `findlast(…lines[1:min(N,nums)])` |
| 路径统一（TASK-009/010/011） | `MAVEN_data/MAVEN_load.jl:36`、`TW_data/TW_load.jl:9`、`TW_data/TW_MINPA.jl:12`、`MGS_data/MGS_load.jl:8`、`support_data/support_data_load.jl:14`、`call_fortran_dll.jl:13-15` | 全部经 `common/paths.jl` 的 `Paths.*` 解析，硬编码降为默认值兜底 |
| 自包含 include（TASK-014） | `common/MarsCommon.jl:2` | `include(joinpath(@__DIR__, "constants.jl"))`，消除装载顺序依赖 |
| 数据键契约（TASK-016） | `common/data_keys.jl`（新建）、`src/MarsData.jl:26` | `MarsData.DataKeys` 随包预装 |
| 就地修改约定（TASK-017） | `MAVEN_data/MAVEN_STATIC.jl:223,462-464`、`common/MarsCommon.jl:382`、`src/plotting.jl:41-46` | AR-9 docstring 已落地 |
| 科学修正（TASK-018…023） | `MAVEN_data/MAVEN_SWEA.jl:46`（`tiny` 已删）；`MAVEN_data/MAVEN_SWIA.jl:414-464`（C11 注释）；`TW_data/TW_MINPA.jl:113-454`（C6 注释）；`Magnetic_Model/IGRF_calculate.jl:701-705,717-720`（TASK-004 `:B`→`"B"` 回退）、`:751`（`method::Symbol=:euler` 等 kwargs）；`MAVEN_data/MAVEN_load.jl:1307,1412`（`SWEA_SHAPE_*` 具名常量） | 与 06 日志一致 |
| 状态显式化（TASK-024，**日志漏记**） | `models/Cold_Plasma_Dispersion_Relation.jl:7-27`（`const PlasmaState = NamedTuple{…}`、`const _state = Ref{Union{Nothing,PlasmaState}}(nothing)`、`make_particles`） | 旧签名未初始化时抛含 `set_particles` 指引的 `ErrorException` |
| KP 列映射（TASK-025，**日志漏记**） | `MAVEN_data/MAVEN_load.jl:30,234,252,454-466`（`_kp_dict = Ref{Dict}(Dict())`、`load_kp(…; kp_columns=_kp_dict[])`） | 默认=旧行为；`change_kp_read_data` 保留写 Ref |
| **未开始**的 S8–S11 证据（反向核实） | `MAVEN_load.jl:962` `Bpc2sphere`（未收敛 MarsCommon）、`MAVEN_load.jl:993` `mean_SWEA_pad_pa`（未迁 MAVEN_SWEA）、`MAVEN_plot.jl:1485` `polynomial_fit`、`MAVEN_plot.jl:1514,1541` `bowshock/magnetopause`、`common/head.jl:358,397` 同名副本、`models/Single_Particle_Orbit.jl:30` 第二份 `TimeFormat`、`src/plotting.jl:26` `TimeFormat(time1,time2)`（无 `format` kwarg）、`MAVEN_plot.jl:18` 仍 `export WaveSpactra_heatmap`、无 `module FunctionCoordinate`、无 `module MarsUtils`、无 `pickup_ion_analysis`、无 `panel_*!`/`_get_kp` | **TASK-026/027/028/029/030/032/033/034/035/036/039/040/041/042 均未开始** |
| 未做的 IGRF 并行安全（TASK-026 反向核实） | `Magnetic_Model/IGRF_calculate.jl:227,261,301` 仍 `Array{Float64}(B_compress)` 读模块全局；全仓无 `bcompress` kwarg | TASK-026 未做 |

### 2.3 验证/基准资产现状

- `benchmark/golden_snapshot.jl`（8.3 KB）+ `benchmark/common.jl`（14.4 KB）+ `benchmark/src/MarsDataBenchmark.jl`（dummy package）。
- `benchmark/results/`：`baseline_marscommon.json`、`baseline_static.json`、`baseline_swia_swea.json`、`baseline_coldplasma.json`、`baseline_igrf.json`（占位）、`baseline_loader.json`（占位）、`baseline_report.md`、`task018_verify.json`、`task018_verify_before.json`。
- 基准脚本：`bench_02_static.jl`、`bench_03_sta_v4d.jl`、`bench_05_findfile.jl`、`bench_06_plot.jl`、`verify_task018.jl`（缺 `bench_01`、`bench_04`、`bench_07`、`bench_08`，与 04 的八项基准清单有缺口）。
- `test/runtests.jl` 420 行（工作区版本比 HEAD 多 176 行）。
- `tests/*.py`（6 个文件，Python 侧 P0–P3 与包化测试）仍在，但**当前不可运行**。

### 2.4 运行环境实测

| 项 | 实测结果 |
|---|---|
| Julia | `C:\Users\Knight Lightning\AppData\Local\Programs\Julia-1.10.5\bin\julia.exe`，`julia version 1.10.5` |
| 全局环境 | `~\.julia\environments\v1.10\Project.toml` 存在（06 日志的 `requirement.jl` 安装路径） |
| Python | 3.15.0；**`python -m pytest` → No module named pytest**（`tests/` 全量不可跑） |
| 真实数据盘 | `E:\MAVEN`、`E:\MGS`、`E:\Tianwen-1` → 均 **False（不存在）** |
| 配置/索引 | `config/settings.toml` → False（且已被 `.gitignore`）；`MAVEN_data/filename_lists.json` → False（且已被 `.gitignore`） |

---

## 3. 任务完成度总表（TASK-001…048）

图例：✅完成（代码+证据）｜🟡完成但验证不完整｜⛔阻塞/环境缺失（按既有口径不阻塞）｜⬜未开始｜➖条件未触发

### S0–S6（TASK-001…025）

| TASK | 内容 | 状态 | 证据/说明 |
|---|---|---|---|
| 001 | benchmark 基建 + 合成 golden 快照 | ✅ | 6 份 baseline JSON 齐备；`golden_snapshot.jl` 可执行（本次未重跑，避免写入 `benchmark/results/`） |
| 002 | 删除三份坏死 `calculate_mag`/`caculate_mag` | 🟡 | 三个函数**定义**确已删除；但**孤儿 docstring 残留**（`TW_data/TW_load.jl:111-129`、`MGS_data/MGS_load.jl:96-113`），与 06 日志"无残留"表述不符（§5 D-4） |
| 003 | `STA_count2eflux`/`STA_eflux2df` 默认参数 | ✅ | `MAVEN_data/MAVEN_STATIC.jl:404,440` `m_int::Real=16` |
| 004 | `get_mag_line_s` 键不一致 | ✅ | `IGRF_calculate.jl:717-720`：先 `:B`、回退 `"B"`，docstring 已说明 |
| 005 | `load_mag_l2` 表头定位 | ✅ | `MAVEN_load.jl:387` `findlast(…min(300,nums))` |
| 006 | 读取错误可见化 | ✅ | `MAVEN_load.jl:173,178,183,196` |
| 007 | `filename_lists` 惰性化 | ✅ | `MAVEN_load.jl:40` `filename_list()` |
| 008 | 真实数据 golden + loader 基准 | ⛔ | 数据盘/配置/索引均不存在（本次实测复现）；06 已按"缺失、以合成基线为准"记录 |
| 009 | SP_load 路径化去副作用 | 🟡 | `support_data/support_data_load.jl:14` `root_path()` 就位；06 记录"运行时冒烟延后" |
| 010 | TW/MGS 根路径 Paths 化 | 🟡 | `TW_load.jl:9`、`TW_MINPA.jl:12`、`MGS_load.jl:8`；运行时 mock 测试延后 |
| 011 | Fortran DLL 路径解析 | 🟡 | `call_fortran_dll.jl:13-15`；无 DLL 环境断言延后 |
| 012 | 显式 `LOADER_FUNCS`（去 eval） | ✅ | `MAVEN_load.jl:1514,1531-1535` |
| 013 | 文件定位日期索引化 | 🟡 | `MAVEN_load.jl:51-70`；`bench_05` 需真实文件列表，未做 |
| 014 | MarsCommon 自包含 include | ✅ | `common/MarsCommon.jl:2` |
| 015 | `validate_registry` 扩展 | ✅ | `src/modules.jl:405-457`；测试断言 errors 为空、warnings 18 条 `@test_broken` |
| 016 | `DataKeys` 模块 | ✅ | `common/data_keys.jl` + `src/MarsData.jl:26` + `test/runtests.jl:54-73`（18 条契约断言） |
| 017 | AR-9 就地修改 docstring + 测试 | ✅ | `MAVEN_STATIC.jl:223,462`、`common/MarsCommon.jl:382`、`src/plotting.jl:41-46`；`test/runtests.jl:75-117` |
| 018 | SWEA 删除死变量 `tiny` | ✅ | `MAVEN_SWEA.jl:46` docstring 记录删除 |
| 019 | SWIA `v_3d` 维度分支 | ✅ | `test/runtests.jl:119-170`（coarse/fine/非法维度三路） |
| 020 | `combina_two_dir_trace` 自引用 | ✅ | `test/runtests.jl:172-189` |
| 021 | `trace_mag_line` `method` kwarg | 🟡 | `IGRF_calculate.jl:751`；`:adaptive` 因 DLL 缺 `MAIN_mp_ADAPTIVE_STEP_TRACE` 而 gated；`bench_07` 未做 |
| 022 | SWEA shape 常数具名化 | ✅ | `MAVEN_load.jl:1307,1412` |
| 023 | 常数出处注释（C6/C7/C11/C12/C13） | ✅ | `TW_MINPA.jl:113,452`、`MAVEN_SWIA.jl:414,462`、`MAVEN_load.jl`；06 建有《常数出处与 SPEDAS 对照表》 |
| **024** | **Cold_Plasma `PlasmaState` 重构** | ✅（**06 日志未记**） | `models/Cold_Plasma_Dispersion_Relation.jl:7-27,51,75`；`test/runtests.jl:215-269`（含 `Threads.@threads` 隔离）；本次测试通过 |
| **025** | **`load_kp` `kp_columns` kwarg** | 🟡（**06 日志未记**） | `MAVEN_load.jl:30,234,252,454-466`；**`test/runtests.jl` 无对应测试**（仅白名单处的 `load_kp` 名字断言），04 要求的"默认一致/自定义生效/兼容路径"三条测试缺失 |

### S7–S11 与条件任务（TASK-026…048）

| TASK | 内容 | 状态 | 反向核实证据 |
|---|---|---|---|
| 026 | IGRF `bcompress` 显式变体 | ⬜ | 全仓无 `bcompress` kwarg；`IGRF_calculate.jl:227,261,301` 仍读模块全局 |
| 027 | 签名/单位审计表（门禁） | ⬜ | `.agent/06` 无审计节；`03 §15` 之外的逐对审计未产出 |
| 028–034 | 去重/权威实现（Bpc2sphere、bowshock、SWEA shape、static_c6、数学工具、FunctionCoordinate、TimeFormat） | ⬜ | §2.2 反向核实：同名副本全部仍并存 |
| 035–038 | 脚本层迁移（MarsUtils、Pickup_ion、Build_data、example） | ⬜ | 无 `module MarsUtils`、无 `pickup_ion_analysis` |
| 039–042 | 绘图面板化、KP 归一、别名收尾、白名单补全 | ⬜ | 无 `panel_*!`/`_get_kp`；`WaveSpactra_heatmap` 仍在 export；仅 3 个模块有非空 `allow` |
| 043 | 死代码清理 | ⬜ | 注释测试块与孤儿 docstring 仍在 |
| 044–048 | 条件性性能任务 | ➖ | 门（bench_03/04 等）未达成，且 `bench_04` 等脚本不存在 |

**当前进度刻度**：48 个 TASK 完成 20 个（✅）、4 个部分完成（🟡：002/009-011/013/021/025 归类见上）、1 个环境阻塞（008）、23 个未开始/未触发 + 1 个门禁任务（027）。**S0–S6 已过，S7 刚开（024/025 完成、026 未做），S8–S11 完全未动。**

---

## 4. 可继承结论（无需重做，直接采用）

1. **架构诊断（AR-1…AR-30）与目标架构（ARCH-001…017）可继承**。定向核实确认下列条目在当前代码仍成立：AR-1（两套装载体系）、AR-3（相对父模块引用）、AR-4（`B_compress` 全局，TASK-026 未做）、AR-6（同名多份实现，S8 未做）、AR-9（视图别名，已文档化但语义未变）、AR-11（同义函数多版本，如 `sta_v_4d/_new`）、AR-13（白名单覆盖不足，仅 3 模块）、AR-17（仪器函数仍在 `MAVEN_load`）、AR-20（磁力线默认 Euler，仍为默认）、AR-29（死代码/孤儿 docstring）。
2. **装载管理器 + 载体机制 + 注册表 = 重构红线，必须保留**（`src/modules.jl`、`src/MarsData.jl`；测试 `test/runtests.jl` 覆盖幂等、`into` 隔离、`@load` 宏、拓扑序、白名单生效）。
3. **数据键契约**：`03 附录 A` 已由 `DataKeys` 落地并测试；后续迁移（S8–S10）应把它作为键名唯一出处。
4. **P6 已消除的旧风险**：A1（模块加载期 IO）→ TASK-007；JSON→`eval` 代码执行入口 → TASK-012；AR-3 的装载顺序依赖（`MarsCommon`）→ TASK-014；AR-12 默认参数引用未定义全局（`m_int=m_int`）→ TASK-003；AR-28（三份坏死 `calculate_mag`）→ TASK-002（函数已删，见 D-4 残留）。
5. **历史数值结论（来自 `docs/reports/`，仍有效）**：`IGRF()` 累加器清零回归已修（BUG-1，附回归证据）；`μ0` 由 `4π×10⁷` 改 `4π×10⁻⁷`、`e` 精度 `1.6e-19→1.602176634e-19`（+0.136%）属**破坏性数值变化**，下游派生量口径需知悉；`Quaternion_Rot` 由 `QuaternionF64` 改 `QuatRotation`（数值等价 <1e-12）。
6. **C 类科学疑点仍待人类复核**（不得由 AI 自行裁定）：C6/C7（`TW_MINPA` 差分与符号）、C10（SWEA 13:64 能量通道）、C11（`7.224566339926571e-7`、`8.8`）、C12（SWEA PAD NaN 互填）、C13（CDF RV `flags & 1`）。这些已在代码中以"疑点+出处+待验证"注释固化。
7. **测试策略口径可继承**：合成 golden 快照是当前唯一可用基线；真实数据基准缺失不阻塞后续任务（06 TASK-008 结论），但**任何"科学正确性"声明在真实数据/SPEDAS 对照前都不成立**（`new_plan.md` §17）。

---

## 5. 差异清单（旧记录 vs 当前真实状态）

| ID | 差异 | 详情 | 处置建议 |
|---|---|---|---|
| **D-1** | **依赖清单扩张且无日志** | 工作区 `Project.toml [deps]` 由 **16 → 45** 个；`Manifest.toml` +1743 行；mtime **10-14 11:29**（06 日志最后写入 02:21）。`.agent/06` 明确自称"`Project.toml [deps]` 未改动（依赖清单不动红线）"，`docs/reports` 亦称"`[deps]` 15 个，轻量" | **需人工/队长裁定**：保留（则红线需修订，载体 `LOAD_PATH` 回退机制的意义改变）或回滚（则测试须依赖全局 `v1.10` 环境）。**在裁定前不要基于该 diff 继续改 `Project.toml`** |
| **D-2** | 06 日志漏记 TASK-024/025 | 两项已在工作区实现（含 024 的 55 行测试），`.agent/06` 无对应小节 | 续做时补记到 06（文档补录，不改代码） |
| **D-3** | 测试数量口径不一致 | 06 记录"84/84"，后又"106 passed / 1 broken"；**本次实测 141 passed / 1 broken**（差值来自 TASK-024 测试集） | 以本次实测数为准（§6.1） |
| **D-4** | TASK-002 "无残留"表述不准确 | `calculate_mag`/`caculate_mag` 的**函数定义**确已删除，但**孤儿 docstring** 仍在：`TW_data/TW_load.jl:111-129`、`MGS_data/MGS_load.jl:96-113`（后接下一个函数的 docstring，成为无用字符串表达式，不报错但污染阅读，且其文本自述"引用了未定义的全局 `data`"） | 归入 TASK-043 清理范围；**不影响运行**（已完成测试全绿） |
| **D-5** | 01 映射的行号锚点漂移 | P6 改动后，`01_PROJECT_MAP.md` 中若干函数行号（如 `MAVEN_load` 各函数）与当前文件不一致 | Phase B 引用时以**符号名**定位，不按旧行号 |
| **D-6** | 八项基准缺 4 项 | 04 §2.3 列 bench_01…08，工作区只有 02/03/05/06 + `verify_task018.jl` | Phase B/D 补 `bench_01/04/07/08` 或明确降级说明 |
| **D-7** | benchmark/tmp 与仓库 tmp 重复 | `tmp/instantiate_benchmark.jl` 与 `benchmark/tmp/instantiate_benchmark.jl` 内容相同（51 B） | 归入 TASK-043 清理候选 |
| **D-8** | Python 测试链断裂 | `docs/reports/refactoring_verification_report.md` 的结论依赖 `tests/test_p0…p3.py`，当前无 pytest | 本轮只做 Julia 架构时可不处理；若需回归 Python 侧须先装 pytest（属环境动作，需队长批准） |

---

## 6. 已有验证框架与真实命令

### 6.1 本次实际执行的命令（可作为后续成员复现入口）

| 命令 | 结果 |
|---|---|
| `julia --project=. test/runtests.jl` | **exit 0**；`Test Summary: MarsData 模块装载管理器 | 141 Pass 1 Broken 142 Total 19.6s`；1 broken = `@test_broken isempty(result.warnings)`（注册表 18 条"自包含 include 与 deps 冗余"警告，预期） |
| `git log --date=iso --pretty=format:"%h %ad %s" -18` | HEAD=`94da314`；P0–P5 提交链 `7e081b8…88a221a` 完整，其后为 martian_pipeline/绘图/加载管理器等包化提交 |
| `git status --porcelain` / `git diff --shortstat` | 19 M 文件；+2493 / −221；未跟踪 `.agent/`、`.agent-teams/`、`benchmark/`、`common/data_keys.jl`、`tmp/` |
| 定向 `grep`（见 §2.2 表格） | 逐任务符号核实，产出 §3 完成度表 |
| `julia --version` / `python --version` / `python -m pytest --version` / `Test-Path`（数据盘等） | §2.4 环境表 |

### 6.2 已存在但本次未执行的验证命令（有写入副作用或环境缺失，留给 Phase B/D）

```bash
# 合成 golden 快照（写 benchmark/results/*.json → 本次刻意未跑，避免越界写入）
julia --project=benchmark benchmark/golden_snapshot.jl

# 现有基准脚本
julia --project=benchmark benchmark/bench_02_static.jl
julia --project=benchmark benchmark/bench_03_sta_v4d.jl
julia --project=benchmark benchmark/bench_05_findfile.jl     # 需真实 filename_lists.json，当前不可跑
julia --project=benchmark benchmark/bench_06_plot.jl
julia --project=benchmark benchmark/verify_task018.jl

# 装载冒烟（主测试套件已覆盖同类路径）
julia --project=. -e 'using MarsData; MarsData.load_module(:MAVEN_load)'

# 注册表自检
julia --project=. -e 'using MarsData; r=MarsData.validate_registry(); println(length(r.errors)," / ",length(r.warnings))'
```

### 6.3 验证资产清单

- **单元/集成**：`test/runtests.jl`（装载管理器、注册表、DataKeys、AR-9、`v_3d`、`combina_two_dir_trace`、`trace_mag_line`、PlasmaState）。
- **回归基线**：`benchmark/results/baseline_*.json`（4 份合成 + 2 份占位）+ `baseline_report.md` + `task018_verify{,_before}.json`。
- **历史报告**：`docs/reports/refactoring_audit_a42e14b.md`（AST 级函数对比方法）、`refactoring_verification_report.md`、`refactoring_comparison_table.md`、`refactoring_diagnosis_report.md`。
- **文档面（Phase 8 目标）**：`docs/src/{api,data_reading,data_format,pipeline,index,swia_electron}.md`、`docs/wiki/*`、`README.md` / `README_EN.md` / `CHANGELOG.md`、`docs/reports/`。

### 6.4 验证能力缺口（Phase B 必须先补）

1. **无 AST 框架**：`new_plan.md` §8 要求 function/module/using/export/call/跨模块调用/API 影响/前后对比能力 —— 当前仅靠 `docs/reports` 里一次性脚本（位于 `%TEMP%`，已不可复现）。
2. **无函数调用表（Call Table）**：`new_plan.md` §9 的 `case_id/module/function/arguments/expected_behavior/comparison_method/tolerance/tags` 结构尚未建立，无 TOML/JSON 文件。
3. **无真实数据/SPEDAS 对照**：C 类疑点无法闭环；比较容差也尚未定义（`new_plan.md` §10 的 abs/rel tolerance、NaN/Inf/missing 语义未落到代码）。
4. **无迁移前后结构对比工具**：S8–S11 大量 MOVE/MERGE 需要它来判断"迁移完整性"。

---

## 7. 风险与待裁定项（提交队长/人工）

| ID | 风险 | 影响 | 建议动作 |
|---|---|---|---|
| R-1 | **P6+TASK-024/025 成果全部未提交**（HEAD 仍在 P6 之前） | 一次误清理/误 checkout 即丢 2493 行成果 | 由队长决定是否先做一次"工作区快照提交"（属写操作，需人工批准） |
| R-2 | D-1 依赖清单扩张无日志、无批准 | 与"依赖清单不动"红线和载体机制设计冲突；影响后续所有 `Project.toml` 相关任务 | 人工裁定：保留/回滚/部分保留 |
| R-3 | 验证框架缺口（6.4） | 若直接进入 S8–S11 大批迁移，将违反"先建立验证能力再大规模迁移"（`new_plan.md` §8、原则 3） | Phase B 先交付 AST + Call Table 最小可用版并通过自检 |
| R-4 | 无真实数据 | 科学类改动只有合成基线，"行为一致"证据强度有限 | 所有科学结论标注"合成证据"，最终由使用者确认科研正确性 |
| R-5 | 002 孤儿 docstring 与实际函数的错配 | 阅读误导（非运行缺陷） | 并入 TASK-043 |
| R-6 | 未提交状态下多 Agent 并行 | 违反"不同实例写入范围互斥"极易产生冲突 | 实施阶段（Phase D 之后）必须先为每个 TASK 划定 Owned Files，且建议先固化基线提交 |

---

## 8. 两名 Pro 专家分工建议（不重复扫描，各按证据清单定向核实）

依据 `new_plan.md` §15 的定位（`pro-architecture-official` / `pro-science-official`），建议如下**互不重叠**的分工：

### 8.1 `pro-architecture-official`（高级架构：模块边界 / 依赖方向 / API / 扩展性）

**输入证据（只读，勿重扫全仓）**：`.agent/01`、`.agent/02`（AR-1…AR-30）、`.agent/03`（ARCH-001…017）、`.agent/04`（TASK-001…048）、本文件 §2.2/§3、`src/modules.jl`、`src/MarsData.jl`。

**必须回答**：
1. AR-1…AR-30 中，哪些已被 P6（TASK-001…025）实际消除、哪些仍成立、哪些判断需要修订？（按条给"已消除/仍成立/需重写"结论，附当前代码位置）
2. ARCH-001…017 → TASK-001…048 的映射在当前进度（S6 完成、S7 半程）下是否需要重排？特别是 S8 的顺序门禁（TASK-027 审计表）是否必须先做。
3. 目标架构的模块分层与依赖方向（`03 §3.1`）在 `DataKeys`/`Paths` 预装、载体机制、白名单机制的现实约束下是否仍成立？public API 与 namespace 规则如何与白名单（`allow`）机制协同？
4. "未来功能添加规范"（`new_plan.md` §4）落到本仓库的具体判据：新函数进哪一层、何时新建 Module、`allow` 白名单如何维护、`Project.toml` 依赖边界规则（回应 D-1）。
5. 明确列出**不应在本轮触碰**的架构红线（`03 §9`）与并行写入互斥建议。

**交付物**：Architecture Rebase 报告 + 修订后的迁移顺序 + 新功能添加规范草案（文档，不写代码）。

### 8.2 `pro-science-official`（科研语义：数据契约 / 单位坐标 / 行为兼容）

**输入证据（只读）**：`.agent/03 §15`（C 类决策）与附录 A（数据键契约）、`.agent/06`（含《常数出处与 SPEDAS 对照表》）、本文件 §2.2/§4.6、`docs/reports/refactoring_audit_a42e14b.md`、相关源码文件（按需定向，不整仓扫描）。

**必须回答**：
1. 附录 A 数据键契约 + `common/data_keys.jl` 是否覆盖当前代码实际使用的键？有无遗漏/冲突（尤其 `MAVEN_load` 的字符串键 `"B"`、`"data staute"` 一类历史键）？
2. C6/C7/C10/C11/C12/C13 六项疑点：在不改数值的前提下，给出"可验证的 SPEDAS/IDL 出处清单 + 建议的验证方法（含容差）"；明确哪些必须由使用者裁定。
3. P6 已完成科学改动的等价性复核：TASK-003/004/018/019/020/021/022/023/024/025 的"行为不变"声明中，哪些有测试证据（列出测试名）、哪些只有合成推理、哪些完全无证据 → 产出"证据强度分级表"。
4. TASK-025（`kp_columns`）缺测试、TASK-009/010/011/013/021 的运行时验证延后项：给出可执行的最小验证清单（含所需数据/环境与降级方案）。
5. 单位与坐标约定（AR-19）、默认磁力线方法（AR-20，`:euler` vs `:rk4`/`:adaptive`）、AR-9 就地修改/视图别名语义：给出"必须在迁移中保持"的语义红线清单。
6. 明确"合成基线 ≠ 科学正确性"的边界表述（`new_plan.md` §17），供最终交付使用。

**交付物**：Scientific Semantics Review + C 类疑点验证方案 + 证据强度分级表（文档，不写代码）。

### 8.3 分工边界（防止重复）

- 架构 Pro **不谈**数值/单位正确性判断，只谈归属、边界、依赖与扩展性；科学 Pro **不谈**模块划分，只谈语义、契约、单位与行为兼容。
- 两者都要**引用本文件的证据位置**而不是重新扫描；对同一证据（如 `MAVEN_load.jl:717-720`）各自只给本专业结论。
- 二者均产出文档；任何代码修改仍由 Flash/Pro 编码实例在审定后的 Migration Plan 下执行。

---

## 9. 合规声明（本次 t1）

- **只写了一个文件**：`.agent/current_state_recovery.md`（本文件）。未修改任何项目代码/测试/配置/`new_plan.md`，未改动 `.agent/00…06`，未触碰 `Project.toml`/`Manifest.toml`（§5 D-1 的扩张是**继承自工作区现状**，非本次产生）。
- 未创建任何子 Agent（符合"含队长最多 8 Agent"与"队员不得创建子 Agent"）；未查询其他成员进度邮箱；未自行更换模型（本条报告本身即"官方 Flash 路由连通"的实证）。
- 未从零重扫全仓：先继承 `.agent/` 旧记录，再对 48 个 TASK 的**特征符号**做定向 grep/定点读取，与旧记录不一致处以当前代码为准并登记在 §5。
- 唯一副作用：为捕获测试输出曾短暂生成 `tmp/recovery_runtests.log`，任务结束前已删除（该目录本身是上一轮遗留的临时目录，非本任务产物）。
- 未运行会写入仓库的验证命令（`golden_snapshot.jl`、`bench_*`），因此 §6.2 均为"已存在、待 Phase B 执行"，不是本次结论。

---

## 10. 交接建议（下一步）

1. **队长裁定 §7 R-2（依赖清单）与 R-1（是否先固化提交）**——这两项决定后续所有编码任务的起点状态。
2. 以 §8 分工派出两名 Pro 的**文档型**审查（不写代码），并行、互斥、不重扫。
3. 架构审定后，Phase B 先补 **AST + Call Table 最小可用版**（`new_plan.md` §8/§9），再进 Phase C/D。
4. 代码续做从 **TASK-026** 起（S7 收尾），S8 起始必须先完成 **TASK-027 审计表（门禁）**。
5. 所有实施任务开始前：为每个 TASK 明确 `Owned Files`（建议把 `MAVEN_load.jl`、`MAVEN_STATIC.jl`、`src/plotting.jl`、`models/Cold_Plasma_Dispersion_Relation.jl` 设为高冲突文件，串行安排）。
