# AI_HANDOFF.md —— 当前唯一接续入口（DeepSeek Flash 整理，2026-10-15 14:15 +08:00）

> 本文档是**当前唯一权威接续入口**。历史规划/审计稿全部**原地保留**，但除本文档「§9 文档效力索引」明示为现行者外，一律视为 **superseded（历史）**。
> **本整理只做记录整合，不代表对已审成果的额外审查**；未重跑整套科学测试（见 §4 的“最后运行时间”标注）。
> 整理者按用户要求**未使用子 agent**、**未改任何源码/测试/工具**、**未提交、未 push**。

---

## 1. 当前工作树基线（现场只读核对，2026-10-15 14:15 +08:00）

| 项 | 现场值 |
|---|---|
| HEAD | `5f225dba4c30d102682bb349460a3e05eee5d87f`（短号 `5f225db`，提交信息「暂存」，2026-10-14 22:48:11 +0800） |
| branch | `main` |
| remote | `origin` = `git@git.ustc.edu.cn:KnightLightning/Julia_for_MartianSpaceData.git` |
| 与远端关系 | `main...origin/main [ahead 2]`（`git rev-list --left-right --count HEAD...@{u}` = **2 / 0**） |
| 领先的 2 个提交（**均早于本批、均未 push**） | `5f225db 暂存`、`46db822 快照：纳入 HD-01…15 裁决文档与执行快照` |
| 本批改动状态 | **全部未提交**：`git status --porcelain` = M 20 / D 5 / ?? 18（含团队运行态与 1 个仅 CR 差异文件，见 §8） |
| 本批是否已提交/推送 | **否**：未 `git add`、未 `commit`、未 `push`；受限 `.git` 按既定口径不重试、不绕过 |

要点：`5f225db` 是**已提交的旧参考基线**（历史 oracle 来源，见 §7），而本批成果**完全在工作区未提交**（见 §4/§8）。

---

## 2. 用户最新裁决与协作/模型约束

- **阶段性停止施工**：用户明确要求暂停施工，先做记录整合，由后续 AI 接续。
- **模型/成员约束**：使用**本实例 Official Flash** 作为主力实施者；**禁止子 agent**；**无 Claude / Pro / Gemini**；团队规模**最多 8 人（含 captain）**；**报告驱动**（以任务书/报告为准）。
- **职责边界**：**captain 不写代码**（协调/裁决/派单）；**USTC 侧仅承担具体短任务**（如 IP 整理），不做长链实施。
- **本批已生效的工程裁决（现场可见的权威人工记录）**：用户 HD-01…HD-15 见 <.agent/审计结果.md>（含 HD-10 STATIC `:mass` 语义与常量等效、HD-08 移除 `sta_v_4d_new`、HD-06/HD-09/HD-15 取消兼容周期、HD-13 不改文档而是标注、HD-14 移动前先全局查依赖）。
- **Git 约束**：不 push；受限 `.git` 不重试不绕过；提交交用户**外部一次执行**（清单见 §8）。
- **文档约束**：除本文档外不新增 Markdown；历史 md 原地保留、不删除不移动；不读改 `.agent-teams/` 状态文件。

---

## 3. 科研契约（必须保持，不得“顺手改科学”）

1. **STATIC 质量基准精度提升（已实施/已审）**：9 处质量基准由数据包 `dat[:mass]`（`Float32`）改为常量 `constants.mp_eV_per_km_s2 = 0.010439684891821985`（`Float64`）。
   - 实测依据：同一确定性夹具 101 探针，`Float32` vs 同值 `Float64` 基准最大相对差 ≈ **7.07e-8**；同值路径与旧 `Float64` 基线**逐位一致**；键值 ×1.0001 的敏感度为 2.0e-4；缺 `:mass` 旧路径 `KeyError(:mass)`。
   - `mass_arr` / `m_int` **角色不变**：`mass_arr` 仍来自数据包质量轴、供质量掩膜与配平；`m_int` 仍是质荷比参数；本次只替换“质子静止质量常量”的取法，不改运算次序与公式。
2. **非等价函数各自保留**（不得合并、不得互相替代）：
   - `slice2d_cal_rot`（`FunctionCoordinate`，返回 `RotMatrix3`，共线抛 `ErrorException`）**vs** `slice2d_cal_rot_matrix`（`TW_MINPA`，返回 `SMatrix`，共线行为按输入类型不同）。
   - `Bpc2sphere`（`hypot` 稳健版）**vs** `Bpc2sphere_naive`（`sqrt` 版，`|坐标| ≳ 1.34e154` 上溢）。
   - `bowshock_plot_nan64` / `magnetopause_plot_nan64`（`MAVEN_plot` 内 NaN64/Float64 变体）**vs** 权威 `bowshock` / `magnetopause`（`MarsEnvironment`，NaN32/Float32）。
3. **NaN / 异常 / 副作用原则**：不改变任何几何或统计公式；无效输入保持原有 NaN 位置或异常类型（例：B 系列零坐标 `(NaN,NaN,2.0)`；FC 版共线抛 `ErrorException`；TW 版 `Vector` 共线抛 `ArgumentError`、`SVector` 共线返回 `SMatrix`）；就地修改（如 `mean_SWEA_pad_pa` 原地写回同一字典且保留原始键）保持不变。
4. **既有开放项不许伪造通过**：IGRF `:adaptive` 因 `IGRF_DLL.dll` 缺 `MAIN_mp_ADAPTIVE_STEP_TRACE` 当前抛错——测试以“抛错”这一可证伪断言固定，符号补齐后该断言会失败并提示更新。

---

## 4. 阶段性真实完成（按模块短表）

| 模块/文件（现行路径） | 完成内容 | 证据/回归 |
|---|---|---|
| `MAVEN_data/MAVEN_STATIC.jl` | 9 处质量基准 → `constants.mp_eV_per_km_s2`；删除 `sta_v_4d_new` | <.agent/06_IMPLEMENTATION_LOG.md> STATIC 节；<test/static_mass_regression.jl>（64/64） |
| <common/MarsCommon.jl> + <common/marscommon/>（statistics/geometry/numerics/cyclotron） | 通用能力子文件化（16 函数）；新增公开 `Bsphere2pc`/`Bpc2sphere`/`Bpc2sphere_naive` | <validation/migrations/common.toml>；<test/common_migration_test.jl>（280/280） |
| <models/Mars_Environment.jl> | 环境权威（模块名 `MarsEnvironment`，文件路径保留 `Mars_Environment.jl`）；`solve_func` 复用 MarsCommon | <validation/migrations/environment.toml>；<test/environment_migration_test.jl>（191/191） |
| <common/function_coordinate.jl> | 包化 `module FunctionCoordinate`；迁入 3 个旋转函数 | <validation/migrations/coordinate.toml>；<test/coordinate_migration_test.jl>（113/113） |
| <MAVEN_data/MAVEN_SWEA.jl> | shape 闭包 + `carclu_SWEA_pad` 迁入 | <validation/migrations/swea.toml>；<test/swea_migration_test.jl>（145/145） |
| <MAVEN_data/MAVEN_load.jl> | 旧副本/旧定义清理（`cyclone_*`、`static_c6_*`、`Bpc2sphere`），loader 链保留 | <test/callsite_migration_test.jl>（85/85） |
| IGRF（现 <models/IGRF_calculate.jl> + <models/gh_gao> + <models/IGRF_DLL.dll>） | 三文件同批移入 `models/`；注册 deps 补 `:MarsCommon`；两档复用规范实例 | <validation/migrations/igrf.toml>；<test/igrf_move_test.jl>（64/64） |
| 坐标变体去重 | `Bpc2sphere_naive`、`slice2d_cal_rot_matrix` 显式命名保留 | <validation/migrations/coordinate_variants.toml>；<test/coordinate_variants_test.jl>（81/81） |
| `call_fortran_dll.jl` | 字符串插值 `$p3；` → `$(p3)；`（1 行，整文件由不可解析转为可装载） | <test/fortran_parse_test.jl>（28/28） |
| 旧入口真删 | `common/head.jl`、`calculate/calculate_models.jl` 物理删除（清单补 `source_revision` 后由工具取证） | <validation/migrations/index.toml>；<validation/check_migrations.jl> |

**机器记录（现行权威）**：<validation/migrations/index.toml>
- 清单 **7** 份（`callsite_plan`、`common`、`coordinate`、`coordinate_variants`、`environment`、`igrf`、`swea`）；`units_total = 39`，`finalized_rows = 39`，`pending_rows = 0`，`retained_rows = **3**`，非法 `target_hash` = 0。
- 校验器 verdict：**ok 28 / fail 0 / pending 0 / unknown 11**；`unknown` 为**动态/无法静态解析点**，**不计通过**（**28 ≠ 39 科学通过**）；`overall_refactor_complete = false`。
- 3 条保留例外（`status=retained`，**无** `target_hash`）：`swea/mean_SWEA_pad_pa`、`coordinate_variants/slice2d_cal_rot`（FC 版 @<common/function_coordinate.jl>）、`coordinate_variants/slice2d_cal_rot`（MAVEN_plot 嵌套版 @<MAVEN_data/MAVEN_plot.jl>）。

**测试数值与运行状态（本次整理**未重跑**，沿用批内最后一次运行结果）**：

| 命令 | 结果 | 最后运行 |
|---|---|---|
| `test/runtests.jl` | 144 Pass / 1 Broken / 145 + STATIC 64 Pass | 2026-10-15 ≈13:2x（本批内） |
| `test/coordinate_variants_test.jl` | 81/81 | 同上 |
| `test/igrf_move_test.jl` | 64/64 | 同上 |
| `test/common_migration_test.jl` / `coordinate` / `environment` / `swea` / `callsite` | 280 / 113 / 191 / 145 / 85 | 同上 |
| `test/ast_migration_test.jl` / `fortran_parse_test.jl` | 204 / 28 | 同上 |
| `validation/check_migrations.jl` | exit 0（ok 28 / fail 0 / pending 0 / unknown 11） | 同上 |
| `git diff --check` | exit 0 | 同上 |

> 接续者若需在当前工作树上重新验证，请自行运行上表命令；**不要**把历史任务中的失败当作当前失败（见 §10）。

---

## 5. 尚未完成（**不得**称“全重构完工”）

- **Extras 与 Pickup 的物理移动**：尚未执行（本轮冻结）。
- **registry 的 `allow` 白名单与 DataKeys 相关项**：未完成。
- **最终文档同步**：<README.md>、<CHANGELOG.md>、<docs/> 仍提旧路径（例：`Magnetic_Model/IGRF_calculate.jl`），**未同步**（用户裁决 HD-13：仅在文档标注、由使用者自行适配）。
- **DLL 符号 / 真实数据验证**：IGRF `:adaptive` 缺 `MAIN_mp_ADAPTIVE_STEP_TRACE`；真实 CDF/科研数据端到端验证未做（本轮仅合成夹具与既有回归）。
- 其它见 <validation/migrations/index.toml> 的 `[index.overall].remaining_note`。

---

## 6. API 破坏 / 旧入口删除 / 新名称 / IGRF 资产新位置

- **旧入口删除（无兼容层）**：<common/head.jl>、<calculate/calculate_models.jl> 已**物理删除**；`:calculate_models` 注册条目已移除。
- **IGRF export 清理**：原 `export pc2sphere, sphere2pc, Bsphere2pc, Bpc2sphere` → `export pc2sphere, sphere2pc`（B 系列权威移至 `MarsCommon`，IGRF 仅 `using .MarsCommon: …` 绑定）。
- **新公开 API**：`MarsCommon` 新增 `Bsphere2pc`、`Bpc2sphere`、`Bpc2sphere_naive` 导出。
- **改名（旧名不再存在，无 alias）**：TW 本地 `slice2d_cal_rot` → **`slice2d_cal_rot_matrix`**；loader 的 sqrt `Bpc2sphere` → **`Bpc2sphere_naive`**；`models/Single_Particle_Orbit.jl` 本地 `TimeFormat` → **`TimeFormatMMSS`**（公共 `MarsData.TimeFormat` = `HH:MM:SS.mmm` 不变）；`head.jl` 迁入的 `color_mapping` → **`color_mapping_lut`**；`carclu_SWEA_pad` 由 `MAVEN_load` 迁至 **`MAVEN_SWEA`**（两示例已改 `MAVEN_SWEA.carclu_SWEA_pad`）。
- **模块名与路径**：`models/Mars_Environment.jl` 内模块名改为 **`MarsEnvironment`**（**文件路径不变**）；注册表新增 `:MarsEnvironment`（`kind=:preloaded`），`:IGRF_calculate` deps 补 `:MarsCommon`。
- **IGRF 资产新位置**：<models/IGRF_calculate.jl>、<models/gh_gao>、<models/IGRF_DLL.dll>（字节 `sha256` 与移动前一致）；资源仍以 `dirname(@__FILE__)` 同目录定位；**文本备份 <.agent…> 之外的 <Magnetic_Model/gh_gao.txt> 原位保留**（未移动、未改写）。

---

## 7. 已提交旧参考 vs 当前未提交成果（**必须区分**）

- **已提交参考**：HEAD `5f225db`（以及 `46db822`）——团队全部「旧 oracle / 旧行为」对照均来自 `git show 5f225db:<路径>`（例如旧的 `Magnetic_Model/IGRF_calculate.jl`、旧 `MAVEN_data/MAVEN_load.jl`、旧 `TW_data/TW_MINPA.jl`）。
- **当前未提交成果**：§4 的模块表、§8 的 59 条路径全部只是**工作区改动**；任何“已迁移/已删除”结论都**尚未进入历史**。
- 因此：`git show HEAD:<path>` 看到的是**旧实现**；比对时请用工作区文件，或用 `git show 5f225db:<path>` 取旧行为。

---

## 8. 单次提交清单（精确、逐文件；供用户外部执行）

**基线（本批此前核对过的 57 条）**：58 条 = MODIFIED 18 + DELETED 5 + NEW 34（逐文件数组见下），**其后本整理新增 2 条**（`<.agent/AI_HANDOFF.md>`、`<.agent/new_plan.md>`）⇒ 当前应为 **59 条**。请以**写后现场**核对，勿假定 57 仍然完整。

```powershell
cd H:\code\Julia_for_MartianSpaceData
$paths = @(
  '.agent/06_IMPLEMENTATION_LOG.md'
  '.agent/AI_HANDOFF.md'
  '.agent/new_plan.md'
  'benchmark/bench_03_sta_v4d.jl'
  'calculate/calculate_models.jl'
  'call_fortran_dll.jl'
  'common/function_coordinate.jl'
  'common/head.jl'
  'common/MarsCommon.jl'
  'common/marscommon/cyclotron.jl'
  'common/marscommon/geometry.jl'
  'common/marscommon/numerics.jl'
  'common/marscommon/statistics.jl'
  'docs/src/api.md'
  'example/MAVEN_plot_sample/MAVEN_overview_cases.jl'
  'example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl'
  'Magnetic_Model/gh_gao'
  'Magnetic_Model/IGRF_calculate.jl'
  'Magnetic_Model/IGRF_DLL.dll'
  'MAVEN_data/MAVEN_load.jl'
  'MAVEN_data/MAVEN_plot.jl'
  'MAVEN_data/MAVEN_STATIC.jl'
  'MAVEN_data/MAVEN_SWEA.jl'
  'models/gh_gao'
  'models/IGRF_calculate.jl'
  'models/IGRF_DLL.dll'
  'models/Mars_Environment.jl'
  'models/Pickup_ion.jl'
  'models/Single_Particle_Orbit.jl'
  'src/MarsData.jl'
  'src/modules.jl'
  'test/ast_migration_test.jl'
  'test/callsite_migration_test.jl'
  'test/common_migration_test.jl'
  'test/coordinate_migration_test.jl'
  'test/coordinate_variants_test.jl'
  'test/environment_migration_test.jl'
  'test/fortran_parse_test.jl'
  'test/igrf_move_test.jl'
  'test/runtests.jl'
  'test/static_mass_regression.jl'
  'test/swea_migration_test.jl'
  'TW_data/TW_MINPA.jl'
  'validation/ast/ASTMigrate.jl'
  'validation/ast/Checks.jl'
  'validation/ast/ExprWalk.jl'
  'validation/ast/Index.jl'
  'validation/ast/Records.jl'
  'validation/ast/Report.jl'
  'validation/ast/Scanner.jl'
  'validation/check_migrations.jl'
  'validation/migrations/callsite_plan.toml'
  'validation/migrations/common.toml'
  'validation/migrations/coordinate_variants.toml'
  'validation/migrations/coordinate.toml'
  'validation/migrations/environment.toml'
  'validation/migrations/igrf.toml'
  'validation/migrations/index.toml'
  'validation/migrations/swea.toml'
)
git add -A -- $paths

# 安全核对：暂存区不得含团队运行态 / 仅 CR 差异文件（两条命令期望均无输出）
git diff --cached --name-only
git diff --cached --name-only | Select-String '^\.agent-teams/|审计结果'

git commit -m "迁移批次：STATIC 质量基准常量 + common/MarsEnvironment/FunctionCoordinate/SWEA/IGRF 权威收束 + AST 校验器 + AI 交接"
```

**排除项（必须不进入提交）**：
- `.agent-teams/**`（团队运行态：`static-small-change/`、`archive/marsdata-flash-execution/`、已跟踪但仅状态变化的 `retired-members.json`）。
- `<.agent/审计结果.md>`：相对 HEAD **仅有 CR 行尾差异**（`git diff --ignore-cr-at-eol` 无输出），虽为权威人工裁决记录，但其**内容未变**，按既定口径不纳入本批提交。
- 临时文件/探针目录（当前 `_tmpprobe*` 残留数 = 0）；仓外 `%TEMP%` 的生成脚本与校验脚本（如索引生成脚本）**不在仓库内**，不参与提交。
- 注意：**不要**使用 `test/{a,b}.jl` 这类 brace 展开，也**不要**使用无范围 `git add -A`。

---

## 9. 文档效力索引（谁现行、谁 superseded）

**现行（权威）**
1. **本文档** <.agent/AI_HANDOFF.md> —— 当前唯一接续入口（整合记录，非额外审查）。
2. **权威人工裁决** <.agent/审计结果.md> —— 用户 HD-01…HD-15（含 HD-08/HD-10/HD-13/HD-14 等直接约束）。
3. **机器记录** <validation/migrations/index.toml> + 7 份清单 <validation/migrations/>（`common`/`environment`/`coordinate`/`coordinate_variants`/`swea`/`igrf` + `callsite_plan`）。
4. **实施证据** <validation/check_migrations.jl>、<validation/ast/>（AST 校验器与自检）、<test/> 下各回归、<.agent/06_IMPLEMENTATION_LOG.md>（实施日志；STATIC 节 + 迁移批次冻结节）。

**历史 / superseded（原地保留，不再作为当前依据）**
- 规划与架构稿：<.agent/new_plan.md>（团队总纲 V2，**已在头部加指引**）、<.agent/00_PROJECT_SCOPE.md>、<.agent/01_PROJECT_MAP.md>、<.agent/02_ARCHITECTURE_REVIEW.md>、<.agent/03_ARCHITECTURE_PLAN.md>、<.agent/04_OPTIMIZATION_PLAN.md>、<.agent/05_TEST_STRATEGY.md>、<.agent/07_VERIFICATION.md>、<.agent/08_DOCUMENTATION_SYNC.md>、<.agent/09_FINAL_REVIEW.md>。
- 目标架构系列：<.agent/target_architecture_draft.md>、<.agent/target_architecture_execution.md>、<.agent/target_architecture_final.md>、<.agent/architecture_draft_review.md>、<.agent/architecture_expert_analysis.md>、<.agent/architecture_final_recheck.md>。
- 执行/依赖收敛系列：<.agent/execution_decisions.md>、<.agent/execution_snapshot.md>、<.agent/execution_task_breakdown.md>、<.agent/execution_batch1_handoff.md>、<.agent/current_state_recovery.md>、<.agent/physical_path_audit.md>（历史路径审计：现以清单/测试为准）、<.agent/dependency_convergence_*>.md（4 份）、<.agent/planning_archive_handoff.md>、<.agent/ustc_supplement.md>。
- 科学/STATIC 审计系列：<.agent/science_expert_analysis.md>、<.agent/science_draft_review.md>、<.agent/science_final_recheck.md>、<.agent/static_mass_removal_audit.md>（其结论**已实施**，故作为历史证据而非待办）。
- 说明：上述历史稿中的旧数字/旧哈希**可能已过期**，本文档**不复制**它们；需要旧值时请查原文或 `git show 5f225db:<路径>`。

---

## 10. 后续 AI 的第一步（建议顺序）

1. **先只读核对**：`git rev-parse HEAD`、`git status -sb`、`git log origin/main..HEAD --oneline`，确认 §1 的基线是否仍成立（尤其“本批仍未提交”）。
2. **读本文档 + 机器记录**：本文件 §3/§4/§5、<.agent/审计结果.md>、<validation/migrations/index.toml>、<.agent/06_IMPLEMENTATION_LOG.md>。
3. **核对未提交差异**：`git status --porcelain` 与 `git diff --stat`（需要时按文件 `git diff -- <path>`）；**不要** `git reset` / `git clean` / 自动回滚或 `git checkout --` 覆盖工作区。
4. **区分历史与当前**：不要因历史任务报告中的“失败/阻塞/被驳回”就假定当前失败；以现场文件与当前回归为准（必要时自行运行 §4 命令）。
5. **无用户授权不部署、不 push**；需要提交时，用 §8 的显式清单**一次性**提交（受限 `.git` 不重试不绕过）。
6. 若继续施工：以 §5 的未完成清单为准（Extras/Pickup 物理移动 → allow/DataKeys → 文档同步 → DLL 符号与真实数据验证），并沿用 §3 的科学契约（不改公式/不合并非等价函数/不伪造通过）。

---

*整理者说明：本文档由本实例 Official Flash 依据现场只读核对与既有任务记录整理；只新增本文件并精确编辑 <.agent/new_plan.md> 头部指引，未改源码/测试/工具，未提交未 push；历史 Markdown 均原地保留。*
