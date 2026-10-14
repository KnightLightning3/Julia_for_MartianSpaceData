# planning_archive_handoff.md — 规划阶段 Git 归档交接说明

> 任务：t12「规划完成后 Git 归档规划与审查文档，保留既有代码原样」
> 执行：flash-recovery（DeepSeek Flash / Official）— attempt 1 / `0f3a1282-7a7e-4298-ae6e-ede243619296`
> 日期：2026-10-14
> 用户授权：**已完成规划后进行 git 归档**（授权归档、**不推送**；归档**不纳入**既有 19 个源码/依赖修改）。
> 本文件是本次 t12 的**唯一新增产物**，并与同批规划文档一起归档。

---

## 1. 归档性质与当前阶段（务必先读）

| 项 | 结论 |
|---|---|
| 规划阶段 | **已完成交付**：Phase A 恢复（t1）、架构分析（t3）、科研语义分析（t4）、目标架构草案（t5）、草案双审（t6/t7）、最终审定包（t8）、最终版双复核（t9/t10）、复核澄清并入（t11）、慢渠道补充（t2） |
| 架构审批 | **HA-0 未批准**。`target_architecture_final.md` 明确标注「待人工审查（HA-0）的最终方案，**不授权任何代码施工**」 |
| 施工授权 | **未授权**。HA-0 批准前不得开始任何 MIG；架构文件 §13 的 8 Agent 施工组织「只在 HA-0 之后启用」 |
| 归档内容性质 | **文档归档，不是代码迁移**。本次提交不包含任何 `.jl`/`Project.toml`/`Manifest.toml`/测试/数据文件 |
| 本次提交是否代表架构通过 | **不代表**。文档层面复核通过 ≠ 用户批准 ≠ 实施测试通过 |

---

## 2. 关键待人工决策项（HD-01…HD-15，全部未裁决）

来源：`target_architecture_final.md §10`。**专家倾向不视为用户批准。**

| 审批点 | 必须在此时机裁决 | 关键 HD |
|---|---|---|
| **HA-0**（审批本方案） | 批准前不施工 | **HD-01**（依赖清单 16→45：收敛/接纳/净化）、**HD-03**（head.jl 拆散与 shim 隐式 using）、**HD-04**（火星边界与环境函数方案 C 并入 MarsCommon / 方案 E 独立 MarsEnvironment）、**HD-05**（策略 P：MarsCommon 改 `:preloaded`）、**HD-06**（calculate_models 解体保留门面）；**HD-02**（工作区快照提交）建议同时裁决 |
| **HA-1 / GATE-B** | 验证框架、基线、审计表确认 | **HD-07**（cyclotron 三套体系处置与命名）、**HD-08**（`sta_v_4d` 证据处置 + `println` 是否改 `@warn`）、**HD-09**（`color_mapping` 改名） |
| **MIG-042 前** | DataKeys 增补 | **HD-10**（`:mass` 常量方案） |
| **MIG-020 前** | 兼容转发方式 | **HD-15**（eager_dep / 冻结双实现） |
| **HA-F 前** | 科学 backlog 与终审 | **HD-11**（C 类疑点 C6/C7/C10/C11/C12/C13 逐项裁决） |
| 不阻塞 | 范围控制 | HD-12（TASK-026/039/040 是否纳入）、HD-13（是否发 depwarn）、HD-14（物理迁移是否做） |

**与 HD-01 相关的现状提醒**：工作区 `Project.toml [deps]` 已由 HEAD 的 16 项扩到 45 项、`Manifest.toml` +1743 行（无日志记录，mtime 10-14 11:29）。该扩张**保持未提交、原样保留**，等待 HD-01 裁决后再处理。

---

## 3. 尚未执行的验证（不构成任何通过证据）

截至本归档，**下列全部未运行或未闭环**（`target_architecture_final.md §11.1 三类状态之③`）：

- **验证框架尚不存在**：`new_plan.md §8` 要求的 AST 工具与 `§9` 要求的函数调用表（Call Table）**均未建立**（属 MIG-001/002/003，波 B）。
- **实施期用例全部未运行**：V-I1…V-I5、V-F1…V-F3、V-R1/V-R2、V-S1…V-S5。
- **行为基线未采集**：B-025 / B-004 / B-018 / B-022 / B-003 / B-STA / B-CYC / B-DUP / B-INST，以及 §4.1 oracle 复测。
- **MIG-005 审计表未产出**（含两版 `TimeFormat` 逐字采集）；MIG-020 装载开销未测量；AST 自检未运行。
- **科学 backlog 全部开放/阻塞**：SB-C6…SB-C13（需 SPEDAS/IDL 源码或真实文件）、SB-D08（真实数据 golden）、SB-D13（真实 `filename_lists.json`）、SB-D21（DLL 缺 `MAIN_mp_ADAPTIVE_STEP_TRACE`）、SB-ESC（`escape_energy` 潜在 bug，按 HD 记录不修）。
- **本轮唯一实测**：t1 记录的装载层测试 `julia --project=. test/runtests.jl` = 141 passed / 1 broken / 0 failed（exit 0，19.6 s）。该结果只覆盖现有装载与少量合成科学用例，**不代表重构后行为**（重构尚未开始）。
- **科学正确性边界**：合成回归 ≠ 科学正确；最终科研正确性由使用者确认（`new_plan.md §17`）。

---

## 4. 后续验证门禁（施工前必须满足）

| 门 | 时机 | 内容 |
|---|---|---|
| **HA-0** | 人工审批 | 批准 `target_architecture_final.md` + HD-01/03/04/05/06（HD-02 建议同时） |
| **Phase B / 波 B** | HA-0 之后、任何迁移之前 | 交付并自检 AST 工具（MIG-001）、Call Table 框架与用例（MIG-002/003）、`runtests.jl` 验证冒烟入口（MIG-004，默认跳过）、TASK-027 审计表（MIG-005）、冻结 AST/Call Table 基线（MIG-000） |
| **GATE-B / HA-1** | 波 1 之前 | 框架自检通过 + 基线冻结 + 审计表完成 + HD-07/08/09 已裁决（人工确认） |
| **GATE-2 / HA-2** | 波 2 之后 | 所有转发用例通过；AST 不再检出重复实现（兼容转发与「明确不合并」项除外） |
| **HA-F** | 收尾 | 最终架构审查；确认「合成回归 ≠ 科学正确」边界与 backlog |
| 每 MIG | 合并前 | 文件锁互斥 + 该 MIG 的验收用例 + 实现者与审查者分离（缺一项不得合并） |

---

## 5. 归档范围（本次提交包含 / 不包含）

### 5.1 包含：`.agent/` 下 22 个 Markdown（21 个既有 + 本文件）

- 规划/日志链：`00_PROJECT_SCOPE.md`、`01_PROJECT_MAP.md`、`02_ARCHITECTURE_REVIEW.md`、`03_ARCHITECTURE_PLAN.md`、`04_OPTIMIZATION_PLAN.md`、`05_TEST_STRATEGY.md`、`06_IMPLEMENTATION_LOG.md`、`07_VERIFICATION.md`、`08_DOCUMENTATION_SYNC.md`、`09_FINAL_REVIEW.md`（07/08/09 为 PENDING 占位，按 `00 §4.2 R1` 不得删除）、`new_plan.md`
- 本轮交付：`current_state_recovery.md`(t1)、`architecture_expert_analysis.md`(t3)、`science_expert_analysis.md`(t4)、`target_architecture_draft.md`(t5)、`architecture_draft_review.md`(t6)、`science_draft_review.md`(t7)、`target_architecture_final.md`(t8/t11)、`architecture_final_recheck.md`(t9)、`science_final_recheck.md`(t10)、`ustc_supplement.md`(t2)
- 本文件：`planning_archive_handoff.md`(t12)

### 5.2 明确不包含

- `.agent-teams/`（团队运行状态、inbox/team.json）
- `tmp/`（临时目录）
- 任何源码（`.jl`）、测试（`test/`、`tests/`）、配置（`config/`）、`Project.toml`、`Manifest.toml`
- `benchmark/`（含 `benchmark/results/*.json` 基线与脚本）
- 任何数据/二进制/图片文件
- `docs/`（文档同步属 PHASE 8/MIG-050/053，尚未实施）

### 5.3 内容安全检查（归档前已执行）

| 检查 | 结果 |
|---|---|
| 凭据/密钥扫描（`api_key`/`token`/`password`/`secret`/`credential`/`Bearer`/`sk-*`/`ghp_`/`AKIA`/`PRIVATE KEY`/URL 内嵌账号/jwt 前缀等，大小写不敏感） | **无命中** |
| 中文凭据词（凭据/密码/密钥） | **无命中** |
| `.agent/` 下非 Markdown 文件 | **0 个**（21 个文件全为 `.md`） |
| 临时输出引用 | 仅 1 处描述性提及（`current_state_recovery.md` 说明旧 AST 脚本位于 `%TEMP%`、已不可复现），**非**归档内容中的临时产物 |
| 本地绝对路径 | 文档中存在本机路径（如 Julia 安装路径、仓库路径），属环境说明，非凭据 |

---

## 6. 既有工作区修改的状态（归档**不**触碰）

- 归档提交**不包含**、也**不改变**以下 19 个已修改文件，它们保持**未提交（unstaged）**、内容原样：
  `MAVEN_data/MAVEN_STATIC.jl`、`MAVEN_data/MAVEN_SWEA.jl`、`MAVEN_data/MAVEN_SWIA.jl`、`MAVEN_data/MAVEN_load.jl`、`MGS_data/MGS_load.jl`、`Magnetic_Model/IGRF_calculate.jl`、`Manifest.toml`、`Project.toml`、`TW_data/TW_MINPA.jl`、`TW_data/TW_load.jl`、`call_fortran_dll.jl`、`common/MarsCommon.jl`、`common/paths.jl`、`models/Cold_Plasma_Dispersion_Relation.jl`、`src/MarsData.jl`、`src/modules.jl`、`src/plotting.jl`、`support_data/support_data_load.jl`、`test/runtests.jl`
  （`git diff --shortstat` = 19 files changed, 2493 insertions(+), 221 deletions(-)；即上一轮 P6 + TASK-024/025 的成果，仍未提交 → 风险项 R-1 依旧存在，见 HD-02）
- 其他未跟踪目录/文件：`.agent-teams/`、`tmp/`、`benchmark/`、`common/data_keys.jl` —— 本次**均不归档、不修改**。
- 归档后 `git status` 应只减少 `.agent/`（从 `?? .agent/` 变为已跟踪且干净），其余状态逐项不变。

---

## 7. 归档后的下一步建议

1. **人工 HA-0 审查**：批准 `target_architecture_final.md` 并裁决 HD-01、HD-03、HD-04、HD-05、HD-06（+HD-02）。
2. **HD-02 决定后**：对既有 19 个源码/依赖修改做一次工作区快照提交（本归档刻意未包含，避免把"规划归档"与"P6 成果提交"混为一次提交）。
3. **HA-0 通过后**：按 `target_architecture_final.md §7.2` DAG 启动波 B（MIG-001/002/003/004/005 → MIG-000 → GATE-B）。
4. **慢渠道（ustc）任务**：按 `ustc_supplement.md §3.1`（SUP-01…SUP-04 = MIG-043/052、MIG-050/053 草稿）与 §3.2（需队长批准）路由；其首次尝试失败证据见该文件 §0。
5. 归档**不推送**；如需推送或改分支，须另行授权。

---

## 8. 合规声明

- 本次只新增本文件，并按显式路径 `git add` 归档 `.agent/` 下规划/日志/审查 Markdown；未 `push`、未 `reset`/`clean`/`stash`、未切换或重写分支、未 amend 既有提交。
- 归档前已确认**无他人暂存内容**（`git diff --cached` 为空），不存在与他人暂存冲突的提交风险。
- 未修改任何源码/测试/配置/`Project.toml`/`Manifest.toml`/`benchmark`/数据文件；未创建子 Agent；未轮询成员进度。
- 归档提交信息明确标注为**规划归档，非代码迁移**。
