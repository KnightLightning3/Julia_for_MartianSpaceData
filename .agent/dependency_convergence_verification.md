# dependency_convergence_verification.md — 依赖收敛独立验证（t8）

> 任务：t8 [verification]「独立验证依赖恢复及源码未改」（团队 `marsdata-flash-execution`）
> 执行：official-reviewer — attempt 2 / attempt_id `4f1a1b61-9b6f-4aef-8ae1-787ab4ce76ed`
> 日期：2026-10-14（Asia/Shanghai）
> **接续基线：`46db822425378d4ad99f8f0b7cfed07360118486`**；目标参考提交：`94da314aba65c8a129c1883931872db6198044c6`
> 被验证对象：t7 实施（`.agent/dependency_convergence_result.md`）+ 根 `Project.toml`/`Manifest.toml` 当前字节
> 验证契约：`.agent/dependency_convergence_requirements.md`（t6）§3.2 与 §4 V1–V7
> 写入范围：**只写本文件**。本任务不修改实现、不修改环境、不安装任何包。
> 判定：**pass**（acceptance 三项全部满足；局限与缺证据面见 §6–§7）

---

## 0. 承接说明与独立性声明（必读）

| 项 | 事实 |
|---|---|
| 前任 | 本任务 attempt 1 由 `ustc-path-auditor` 执行，两次 300000ms 流空闲超时，**无正式完成证据**；接手时 `.agent/dependency_convergence_verification.md` **不存在**（`Test-Path` = False） |
| 前任残留 | 前任最后称"16 项可解析、准备清探针"。经核查：`.agent/` 下**无任何非 `.md` 文件、无子目录**，全仓近 3 小时无临时/探针类文件；t7 自述的两份一次性探针（`.agent/_probe_manifest.toml`、`.agent/_t7_runtests_out.txt`）也已不存在 ⇒ **无残留可清，本任务未删除任何文件** |
| 独立性 | 验证者 ≠ 实现者（t7 由 `official-engineer` 实施）⇒ 满足"实现者 ≠ 验证者"。**但验证者本人是 t6 契约作者**，因此**本验证不是第三人独立审查**，不得据此声称"已获独立第三方确认"；t9 审查须计入此关联 |
| 方法 | 全部为**现场重跑**：自行执行命令、自行解析文件、自行判读输出；**不复用 t7 的结论文本或数字**（仅在对照时引用其声称值） |

---

## 1. 前置核查：产物与残留

| 检查 | 命令/方式 | 结果 |
|---|---|---|
| 本任务产物是否存在 | `Test-Path .agent/dependency_convergence_verification.md` | **False**（前任未产出） |
| `.agent` 非 md 文件 | `Get-ChildItem .agent -Recurse -Force \| Where Name -notlike '*.md'` | **0 个** |
| `.agent` 子目录 | 同上 | **0 个** |
| 全仓近期临时/探针文件 | 近 3 小时 + 名称匹配 `probe|tmp|temp|scratch|.out|.log`（排除 `.git`） | 仅命中 `.agent-teams/…/team.json`（团队运行状态，**不属于本任务、未触碰**） |
| 清理动作 | — | **未执行任何删除**（无可确认由本任务生成且需清理的残留；不明文件一律保留） |

---

## 2. V1 — 字节一致（主判据：原始字节）

```text
git hash-object --no-filters Project.toml   → b9b0177feadcbd25a91f1b75b21770c94dbe6192
git hash-object --no-filters Manifest.toml  → a37ba5bfefd864dd9b4aa78e9e2381614a9d4233
git rev-parse 94da314:Project.toml          → b9b0177feadcbd25a91f1b75b21770c94dbe6192
git rev-parse 94da314:Manifest.toml         → a37ba5bfefd864dd9b4aa78e9e2381614a9d4233
git diff --exit-code 94da314 -- Project.toml Manifest.toml → exit 0
```

| 文件 | 工作区字节 | 行数（自测） | 行尾 | 94da314 blob 行数 |
|---|---|---|---|---|
| `Project.toml` | 1061 B | 31 | LF-only（CRLF=0） | 31 |
| `Manifest.toml` | 60944 B | 1782 | LF-only（CRLF=0） | 1782 |

**结论：两份文件与 94da314 的 Git blob 逐字节一致**（原始字节哈希相等 + `git diff` 退出码 0 + 行数/行尾独立计数一致）。t7 声称的"分 5 段写入、曾多 1 空行后修正"在终态**不可见**（无残留偏差）。

---

## 3. V2 — 依赖集合（独立解析，不复用 t7 输出）

以 `TOML.parsefile` 由本验证自行解析当前工作区文件：

| 项 | 实测值 |
|---|---|
| `[deps]` 条目数 | **16** |
| 集合内容 | `CairoMakie, ColorTypes, DataFrames, DataInterpolations, Dates, DelaunayTriangulation, IniFile, JSON, LaTeXStrings, LinearAlgebra, Makie, ProgressMeter, StaticArrays, Statistics, TOML, TimesDates` |
| 与参考清单集合相等 | **true**（对称差 = `[]`） |
| `[compat] julia` | `1.10` |
| `[extras]` / `[targets].test` | `Test` / `["Test"]` |
| Manifest `manifest_format` / `julia_version` | `2.0` / `1.10.0` |
| Manifest `project_hash` | `040c540bcab7dc28246654e048c8e0d52a9d64b8`（与 94da314 配对一致） |
| Manifest 条目数 | 264 |

**结论**：根环境依赖集合 = 原 16 项，且与 `Project.toml` 配对的 `project_hash` 未被改写 ⇒ 无需 `Pkg.resolve`、无重解析迹象。

---

## 4. V3 — 源码与范围核对（以接续快照 `46db822` 为锚）

```text
git diff --name-only 46db822                        → .agent/execution_snapshot.md, Manifest.toml, Project.toml
git diff --name-only 46db822 -- . ':!.agent'        → Manifest.toml, Project.toml        （仅这两份）
git diff --stat 46db822 -- <全部源码/测试/配置/benchmark/docs 目录> → 空（exit 0）
```

- 除 `.agent` 文档外，改动面**只有两份依赖文件**。
- 源码目录级检查（`MAVEN_data`、`MGS_data`、`TW_data`、`Magnetic_Model`、`common`、`src`、`models`、`calculate`、`support_data`、`test`、`benchmark`、`docs`、`config`、`tools`、`example`、`download_data`、`martian_pipeline`、`tests`、`tmp` 及根级脚本/清单）**全部为空** ⇒ **P6 源码零回滚**。
- `.agent/execution_snapshot.md` 的修改是 t1 已登记的预期项（§7 回填，待 t10 补记），**不属于 t7 改动**。

**结论**：源码/测试/配置/benchmark/docs 相对接续快照未被改动。

---

## 5. V4–V6 — 环境未被污染、无隐式安装、无文件重写

| 检查 | 实测 | 判读 |
|---|---|---|
| 全局环境 `~/.julia/environments/v1.10/Project.toml` | 2158 B / 43 行 / `[deps]` **42 项** | 与 t6 时点（收敛前）**一致** |
| 全局环境 `Manifest.toml` | 134770 B / 3515 行 / 443 条目 / format 2.0 / julia_version 1.10.5 / `project_hash 42a780cf…` | 与 t6 时点一致（其 `project_hash` 与 46db822 工作区版本的 `399bf066…` 不同 ⇒ **未被替换成工作区版本**） |
| 全局环境两文件 mtime | `2026-10-14 01:49:43` | **早于** t7 执行（约 20:23）与本次验证 ⇒ 未被本批任务写入 |
| depot 包目录是否新增 | `~/.julia/packages` 下 20:00 之后**无**目录 mtime 更新（顶层 425 个目录） | 无安装/升级/降级 |
| 本次验证执行过的命令 | 仅 `git`（只读）+ `julia --project=. test/runtests.jl` + `julia -e`（只读解析/探测） | **无任何 `Pkg.*` 变更操作** |
| 运行后依赖文件是否被改写 | 运行后重取 `git hash-object --no-filters` = `b9b0177f…` / `a37ba5bf…`（不变） | 运行测试未触发 Manifest 重写 |
| 运行后是否新增/残留文件 | `git status --porcelain=v1` 与运行前一致；`.agent` 无非 md 文件 | 无残留 |

**结论**：全局 Julia 环境、depot、根工作区均未被污染；无隐式安装；测试运行未改写依赖文件。

---

## 6. V5/V7 — 现场测试结果与缺证据面

### 6.1 现场重跑（独立执行，输出仅捕获到进程变量，未落盘任何文件）

```text
julia --project=. test/runtests.jl
exit_code = 0        elapsed = 33.2 s（其中 Test Summary Time = 18.1 s）
Test Summary:            | Pass  Broken  Total   Time
MarsData 模块装载管理器  |  141       1    142  18.1s
Fail 行 = 0 ; Error 行 = 0 ; skip 行 = 0
```

| 分类 | 数量 | 说明 |
|---|---|---|
| Pass | **141** | 与 t7 现场值一致（独立重跑复现） |
| Broken | **1** | **既有** `@test_broken`：`test/runtests.jl:30 @test_broken isempty(result.warnings)`（同文件 :29 注释"警告不阻塞测试，但本阶段应无冗余 include"）⇒ 属先于本批的既有声明，**不计为通过，也不属本轮回归** |
| Fail / Error | **0 / 0** | 无失败、无异常 |
| Skip | **0** | 本次运行未出现因缺真实数据/DLL 而跳过的用例 |
| Total | 142 | — |

运行的尾部日志为 `validate_registry` 的 **Info 级**注册表警告（`MAVEN_load` 自包含 `MarsCommon.jl` 同时 deps 含 `MarsCommon`；`MAVEN_STATIC` 同类两处）——即上表 Broken 所指的既有警告面，**非错误**。

### 6.2 明确不作为通过证据的事项（科学边界，不得外推）

1. 本测试套件为**装载管理器 + 少量合成用例**；**不是科学验证**。真实数据、DLL、SPEDAS/IDL 对照、C 类科学疑点均**未覆盖**。
2. 依赖解析来源：`load_path` = 根项目 → 全局环境 `v1.10` → stdlib；本次**只验证了装载层通过**，未逐包登记"16 项外依赖"的解析来源（t6 §2.4 的既有现状：`SpecialFunctions`（仅 head.jl）为间接条目按名不可解析，`BenchmarkTools`（仅 benchmark）、`Documenter`（仅 docs）不在环境）——这三项**不被本次运行覆盖**，其状态保持 t6 记录，既不因本次通过而改变，也未因本次运行而恶化。
3. 未做：路径审计（t4 职责）、AST 级引用分析、科学数值等价性验证。

---

## 7. 判定与遗留

| acceptance（t8 合同） | 判定 | 证据 |
|---|---|---|
| 独立运行 `git diff --exit-code 94da314 -- Project.toml Manifest.toml` 及 `julia --project=. test/runtests.jl` 并记录退出码与测试结果 | **通过** | §2（exit 0）、§6.1（exit 0，141/1/142 原文摘要） |
| 以接续快照核对源码无改动、根环境仍只有原 16 项 | **通过** | §4（改动面仅两份依赖文件 + t1 预期文档；源码目录全空）、§3（16 项、与参考集合相等、`project_hash` 配对） |
| 失败、缺依赖、跳过与已知 broken 分别呈现，不伪称科学验证通过 | **通过** | §6.1 分类呈现（Fail 0 / Error 0 / Skip 0 / Broken 1 且定位到既有行）、§6.2 明确科学未验证面 |

**范围偏差记录（供 t9 判定，本验证不下结论）**

- t7 自述曾生成两份一次性探针文件（`.agent/_probe_manifest.toml`、`.agent/_t7_runtests_out.txt`）并在核验路径后删除。本验证确认**当前无残留、追踪面未受污染**（§1、§5）。
- 该事项属"过程证据未按预期落盘即删"的流程偏差；**是否需要修复动作**由 t9 依其合同判定。从本次独立证据看：**无字节/范围/环境层面的实际危害**（所有主判据均通过，且探针不含科学数据）。

**交接给 t9 的要点**

1. 本验证由 t6 契约作者执行，**不是第三人审查**；t9 需据此评估审查独立性链。
2. t6 存在平台的"内容绑定再评审"门禁警告：请以本报告 §2 的字节哈希与 t6 文档实际 blob 绑定为起点，独立复核 `dependency_convergence_requirements.md` 的当前字节与合同一致性。
3. 独立复现命令（可直接引用）：§2 的三条 `git` 命令 + `julia --project=. test/runtests.jl`；预期 exit 0 与 `141 / 1 / 142`。

---

## 8. 合规声明

- 本任务**只写** `.agent/dependency_convergence_verification.md`；未修改 `Project.toml`/`Manifest.toml`、未修改任何源码/测试/配置/文档、未修改全局 Julia 环境。
- 未执行任何 `Pkg` 变更或安装操作，未联网；未执行 `git add/commit/checkout/restore/reset/push`（仅只读 `git` 命令）。
- 未删除任何文件（无残留可清；不明文件一律保留）。
- 未创建子 Agent、未轮询、未启用自动目标；`.agent-teams/**` 未读写（仅在只读诊断时列出文件名）。
- 本报告不写入自身哈希（避免自引用改变字节）；其字节绑定由 t8 任务终态证据与 t10 交接记录承载。
