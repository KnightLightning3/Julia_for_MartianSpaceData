# target_architecture_execution.md — 无旧兼容目标架构执行规格（基线门禁内可执行）

> 任务：t2 [decisions]（团队 `marsdata-flash-execution`）
> 执行：official-reviewer — attempt 1 / `e19427ea-89eb-4438-9913-40ee89c489b5`
> 日期：2026-10-14（Asia/Shanghai）
> **接续基线：`46db822425378d4ad99f8f0b7cfed07360118486`**（父 `fda2adae893f4367a4e86079e24d57bb6e545997`）
> 裁决依据：`.agent/审计结果.md`（HD-01…HD-15）及其执行解释 `.agent/execution_decisions.md`（t2 的另一份交付）。
> 与历史档案的关系：`.agent/target_architecture_final.md`（704 行）**保持原样，作为历史审定档案与细节来源**；**执行口径以本文件为准**，被 HD 裁决修订的条目清单见 `execution_decisions.md` §4。
> 写入范围：只写本文件。不改源码/测试/配置/依赖文件/`docs/`/`benchmark/`，不改任何历史文档。
> 状态：**规格待首批审批**。§1 之外的一切迁移动作均**未授权**。

---

## 1. 执行范围、批次与门禁

### 1.1 首批（本轮授权，不越过基线门禁）

| # | 内容 | 归属任务 | 产出 |
|---|---|---|---|
| 1 | 接续 Git 快照与远端增量核对 | t1（**已完成**） | `46db822`；`.agent/execution_snapshot.md` |
| 2 | 无旧兼容架构修订（裁决落地） | t2（本文件） | `execution_decisions.md`、本文件 |
| 3 | STATIC 科学契约审计（HD-10/HD-11，含 `sta_v_4d_new` 删除边界） | t3 | `.agent/static_mass_removal_audit.md` |
| 4 | 三个物理移动单元的全局路径审计（HD-14 前置） | t4 | `.agent/physical_path_audit.md` |
| 5 | 依赖收敛实施合同 | t6 | `.agent/dependency_convergence_requirements.md` |
| 6 | 根依赖恢复原 16 项（不改源码） | t7 | `Project.toml`、`Manifest.toml`、`.agent/dependency_convergence_result.md` |
| 7 | 依赖恢复的独立验证 | t8 | `.agent/dependency_convergence_verification.md` |
| 8 | 依赖收敛的独立审查 | t9 | `.agent/dependency_convergence_review.md` |
| 9 | 小粒度迁移 DAG 与任务分解 | t5 | `.agent/execution_task_breakdown.md` |
| 10 | 首批集成与待审批交付 | t10 | `.agent/execution_batch1_handoff.md` |

**首批禁止项（硬约束）**：不改任何 `.jl` 科研源码；不移动文件；不改注册表；不建 `validation/**` 工具；不执行任何函数级迁移；不 push/部署；不安装包；不改全局环境。

### 1.2 后续批次（**待二次审批**，本文件只定义骨架与验收）

| 批次 | 内容 | 门禁 |
|---|---|---|
| 波 B | AST/Call Table 工具（MIG-001/002/003/004）、审计表（MIG-005）、基线冻结（MIG-000） | 二次审批后启动 |
| GATE-B / HA-1 | 框架自检通过 + 基线冻结 + 审计表完成；确认 HD-07/08/09 的落地口径 | **人工确认**（无 Pro/Claude 审批） |
| 波 1 | 能力模块新建与权威实现就位（FunctionCoordinate、MarsCommon 扩充、MarsEnvironment、MAVEN_SWEA、MAVEN_plot 收编、注册表与策略 P） | GATE-B |
| 波 2 | 旧名删除 + 全仓调用点更新（按 R-2 原子性，按文件锁串行/并行） | 波 1 |
| GATE-2 / HA-2 | 无重复实现（不合并项除外）、无悬空引用、无兼容残留 | 人工确认 |
| 波 3 | 物理移动（IGRF→models、Extras→models/extras、Pickup→analysis）、脚本入口迁移、Pickup 函数化 | GATE-2 + t4 审计 |
| 波 4 | allow 保守补全、DataKeys/附录 A、文档同步、backlog 固化、死代码与孤儿 docstring 清理 | GATE-2 |

> 详细的逐任务「路径 / 依赖 / 验收 / 可运行 verify 命令」由 **t5** 的 `.agent/execution_task_breakdown.md` 给出；本 §6 只提供骨架、约束与批次划分，避免与 t5 重复。

---

## 2. 能力层与依赖边（修订版）

### 2.1 能力层（保留；L6 缩减）

```text
L6 Analysis       Pickup_ion（pickup_ion_analysis）、Build_data、example、脚本入口
L5 Visualization  MAVEN_plot、src/plotting.jl
L4 Domain Model   IGRF_calculate、Cold_Plasma_Dispersion_Relation、Maxwellian_Distribution、
                  Single_Particle_Orbit、MarsEnvironment（HD-04 = E）
L3 Instrument     MAVEN_STATIC、MAVEN_SWIA、MAVEN_SWEA、TW_MINPA
L2 Data Access    MAVEN_load、TW_load、MGS_load、SP_load
L1 Foundation     constants、MarsCommon、FunctionCoordinate（新，包化）      L1n Native：Call_fortran_dll
L0 Core           MarsData：Paths、DataKeys、注册表/装载器、registry/index
X  Extras         Octree、Grahame…（CATALOG.toml 登记；任何层都不得依赖 X）
```

**修订**：L6 不再包含 `head.jl 兼容 shim` 与 `calculate_models 弃用门面`（HD-03/06/15；见 `execution_decisions.md` §3.3/§3.6/§3.15）。

### 2.2 允许的依赖边（`validation/architecture/layers.toml` 权威来源）

| 从 \ 到 | L0 | L1 | L1n | L2 | L3 | L4 | L5 | X |
|---|---|---|---|---|---|---|---|---|
| L1 | Paths/DataKeys | 见注 1 | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| L2 | ✓ | ✓ | ✗ | ✗ | **✗（修订）** | ✗ | ✗ | ✗ |
| L3 | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| L4 | ✓ | ✓ | ✓ | ✗ | ✗ | 一跳（注 3） | ✗ | ✗ |
| L5 | ✓ | ✓ | ✗ | ✗ | ✗ | 只限无状态纯函数模块 | 同层 | ✗ |
| L6 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | 显式 include |
| X | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | 同层 |

- **注 1**：L1 内部只允许 `FunctionCoordinate→MarsCommon` 与 `MarsCommon→constants` 两条边，反向禁止；**L1→L4 无例外**（`bowshock_zero` 从 FunctionCoordinate 删除且不转发）。
- **注 2（修订）**：原「L2→L3 只能作为兼容转发边、须用 `eager_dep`、登记移除期限」**作废**。HD-15 取消兼容 ⇒ **L2→L3 完全禁止**。因此 `MAVEN_load` 内的 SWEA shape/PAD 与 `static_c6_*` 旧副本必须删除而非转发，且必须确认 `MAVEN_load` 自身不再调用 `MAVEN_SWEA`/`MAVEN_STATIC`。
- **注 3**：L4 内部只允许一跳依赖，且必须登记在注册表 `deps`。
- 禁止一切循环；AST 校验强连通分量为空。

### 2.3 逻辑层与物理装载位置（策略 P 实施后）

| 模块 | 逻辑层 | 物理装载位置 | 备注 |
|---|---|---|---|
| Paths、DataKeys | L0 | 预装 | Paths 被自包含产生嵌套副本（既有现状） |
| MarsCommon | L1 | **预装**（规范实例 = `MarsData.MAVEN_plot.MarsCommon`） | L2/L3/L4 自包含产生嵌套副本 |
| constants | L1 | 载体（豁免 I-4） | 理由：`runtests.jl:350` 的 `!isdefined(MarsData, :constants)` 隔离断言 |
| FunctionCoordinate | L1 | 载体（使用 Rotations，按 PL-1 不得预装） | G-include，不复制 MarsCommon |
| MarsEnvironment | L4 | **预装**（= `MarsData.MAVEN_plot.MarsEnvironment`） | HD-04 = E；无状态 |
| MAVEN_plot、plotting | L5 | 预装 | — |
| 其他注册模块 | L2–L4 | 载体 | — |

---

## 3. 装载机制红线与策略 P（保留部分）

1. **红线不变**：`_carrier`、`load_module`、`@load`、`:preloaded` 分支、`ModuleLoadError` 的代码一律不改；只允许增补/修改注册表数据（条目、`kind`、`deps`、`allow`、`note`）与 validate 校验。
2. **策略 P（HD-05 已批准）**：`:MarsCommon` 注册项改 `kind=:preloaded`；选 E 时新增 `:MarsEnvironment`（`:preloaded`）；`src/MarsData.jl` 增加 `const` 别名行。可观察变化：`using MarsData` 后 `MarsData.MarsCommon` 已定义，`parentmodule(MarsData.MarsCommon) === MarsData.MAVEN_plot`。
3. **实例规则 I-1…I-5 保留**（含嵌套副本只许无状态、预装闭包内不新增重复实例、既预装又注册者必须 `:preloaded`、转发目标在定义处可解析）。**唯一修订**：I-5 的"转发目标"不再指兼容转发，而是指新权威调用的可解析性（调用点写全限定名即可满足）。
4. **G-include 保留**（FunctionCoordinate / MarsEnvironment：父模块已有则复用，否则自包含）。
5. **PL-1 / PL-2 保留**：预装成员只能使用 16 项内的包；预装成员必须无状态。
6. **constants 豁免 I-4** 与其理由写入 `layers.toml` 注释。

---

## 4. 无兼容迁移规则（每条迁移单元的完成定义）

### 4.1 完成定义（缺一即未完成）

| # | 条件 | 证据 |
|---|---|---|
| C1 | **新权威实现就位**：目标模块顶层定义存在，定义数 = 1，参数个数/顺序/关键字与旧实现一致 | AST 报告（定义清单 diff） |
| C2 | **数值/行为等价**：`pure_move` 一律 exact；非 `pure_move` 按 `execution_decisions.md` §6 的 NaN/副作用规则 | Call Table 运行输出（含 exit code、报告文件） |
| C3 | **全仓调用点更新**：所有受跟踪 `.jl`/脚本/示例/`docs/src` 中的旧调用改为新权威 | 调用点清单 + AST 悬空引用断言 |
| C4 | **旧定义与旧名删除**：旧模块内定义数 = 0；无 alias、无同名转发、无换算包装、无 depwarn | AST 模块断言 + grep 证据 |
| C5 | **层规则与装载冒烟**：层矩阵通过、`using MarsData` 冒烟、受影响模块 `load_module` 冒烟、allow 逐名引入冒烟 | 命令输出 |
| C6 | **文档同步**：`CHANGELOG.md` 记「旧 → 新/删除 + 适配动作」；`docs/src/**` 相应条目更新 | diff |
| C7 | **独立性**：实现者 ≠ 审查者；`science_sensitive` 项经 flash 科学审查（§8） | 审查报告 |

### 4.2 原子性（R-2 的执行含义）

- 一个名字的迁移只能出现在**一个**迁移单元中；禁止"先建新权威、下一波再删旧名"的两段式（那会留下双实现，违反去重目标，并使 AST 断言无法通过）。
- 若确实需要两段式（例如共享文件锁冲突），必须在 DAG 中显式标注为**同一逻辑单元的连续两步**，且中间态不得进入任何 GATE。
- **共享文件串行**：`src/modules.jl`、`src/MarsData.jl` 等被多个单元触及的文件，严格按 §7 文件锁串行。

### 4.3 工具纪律（HD-14 尾注）

- 优先使用可见的精确文件工具做行级搬迁（`ops_replace`/`edit` 等），**不得假定存在未经验证的行剪切接口**（团队合同原文）。
- 整文件搬迁可写简单 Python 助手，但必须满足：绝对路径核验、源/目标哈希前置、不覆盖既有目标、`dry-run` 先跑、失败回退明确。助手本身也要经审查（实现者≠审查者）后才可批量使用。
- 移动函数/文件的每一步都要留下可复现命令与哈希，不依赖"记忆中的位置"。

---

## 5. 验证框架修订：兼容边 → 移动/移除断言

### 5.1 `layers.toml` 结构（修订）

| 节 | 状态 | 内容 |
|---|---|---|
| `[layers]` | 保留 | 层定义 |
| `[modules]` | 保留 | `name`、`path`、`layer`、`kind`、`deps`、`allow` |
| `[edges]` | 保留 | 允许边；`L2→L3` 一律不得出现 |
| `[compat_edges]`（`resolve`/`adds_deps`/`remove_by`） | **删除** | HD-15 取消兼容 |
| `[moves]`（**新**） | 新增 | 每条：`from_module`、`from_name`、`to_module`、`to_name`、`mig`、`evidence_case`、`old_removed = true` |
| `[removed_names]`（**新**） | 新增 | 每条：`name`、`module`、`mig`、`reason`（`move`/`authorized_deletion`）、`history_ref`（可回溯的提交/路径/行范围） |
| `[preinstall]` | 保留 | 预装闭包成员与豁免说明（含 `constants`） |

### 5.2 AST 断言（替换旧的"转发解析"规则）

| ID | 断言 | 失败含义 |
|---|---|---|
| A1 | 层规则：允许边、禁边（含 `L2→L3`、`L1→L4`）、强连通分量为空 | 架构违例 |
| A2 | **新入口存在**：每个 `[moves]` 项的 `to_module.to_name` 有顶层定义且唯一，参数形状与 `from_name` 一致 | 迁移未落地 |
| A3 | **悬空引用为空**：全仓受跟踪 `.jl` 中不存在 `FromModule.old_name` 形式的限定引用 | 调用点漏改 |
| A4 | **移除断言**：`old_name` 在 `from_module` 的顶层定义数 = 0；`[removed_names]` 全部命中 | 双实现/未删除 |
| A5 | **无兼容断言**：不存在 `const Old = New`、同名转发包装、`@deprecate`/`depwarn`、换算包装（HD-13/15） | 兼容残留 |
| A6 | **同名遮蔽检测**（保留）：顶层不出现与嵌套同名的新定义；`color_mapping_lut` 场景的嵌套调用点解析不变 | 遮蔽回归 |
| A7 | **孤儿 docstring 检测**（保留）：D-4 两处（`TW_load.jl:111-129`、`MGS_load.jl:96-113`） | 文档残留 |
| A8 | **PL-1/PL-2/I-2**：预装成员只用 16 项内包、无状态；嵌套副本仅限无状态权威文件 | 预装违例 |
| A9 | **自检 oracle 精确命中**（保留，按 `target_architecture_final.md` §4.1 的精确计数；复测不同须附证据更新，不得放宽为"至少"） | oracle 漂移 |

### 5.3 Call Table 修订

- 保留字段：`case_id`、`module`、`function`、`args`、`kwargs`、`setup`、`preconditions`、`expected_behavior`（`value`/`throws`/`mutates`/`prints`）、`comparison`、`atol`、`rtol`、`nan_policy`、`tolerance_justification`、`tags`、`evidence_level`、`migs`。
- 新增字段：`entry`（新权威全限定名）、`removed_old_entry`（旧名，用于 A4 对应）、`history_ref`（删除项的可回溯引用）。
- NaN/容差规则不变：`positional` 默认、新增 NaN 一律失败、`pure_move` exact、放宽容差须 `tolerance_justification` 且**只能由用户裁决**（不得由 Pro/Claude/flash 批准）。

### 5.4 用例改写：V-F/B-STA → 新入口/悬空/移除断言

| 旧 ID（final 文件） | 处置 | 新 ID 与内容 |
|---|---|---|
| V-F1（`using MarsData` 后转发目标可用） | 改写 | **V-N1**：`using MarsData` 后新权威的入口可调用且基线一致（exact） |
| V-F2（`load_module(:MAVEN_load)` 后 SWEA 可用） | 改写 | **V-N2**：`load_module(:MAVEN_SWEA)` 后 `MAVEN_SWEA.<entry>` 可用；`MAVEN_load` 中旧名不存在（A4） |
| V-F3（eager_dep 转发错误语义） | **作废** | 由 **V-D1**（全仓悬空引用为空）与 **V-X1**（旧名未定义）取代 |
| V-S1…V-S5（head shim 验证） | **作废** | **V-S6**：脚本入口迁移后（`using MarsData` + `@load`）在 Main 与空 Module 两种目标下装载冒烟；旧裸名集合**不再存在**（负向断言） |
| V-I1…V-I5（实例一致性） | **保留** | 策略 P 相关断言不变 |
| V-R1（`runtests` 门槛） | **改写** | 见 §5.5 测试计数政策 |
| V-R2（`validate_registry` errors/warnings 增量） | **保留** | warnings 增量与迁移单元声明一致 |
| EQ-STA-1 / EQ-STA-2（`sta_v_4d` vs `_new` 等价） | **作废（HD-08）** | **V-X-STA1**：`sta_v_4d_new` 在 `MarsData.MAVEN_STATIC` 中未定义（移除断言）；**V-REG-STA1**：`sta_v_4d` 自身回归基线（合成夹具，exact 或按 t3 实测口径）；**V-SE-STA1/2**：`mutates`（写入 `:df`）与 `prints`（`Invalid Data`）副作用保留 |
| SE-STA-1 / SE-STA-2 / PRE-STA-1 | 保留（去掉与 `_new` 的对照语义） | 副作用与前置条件断言 |
| B-CYC | 保留并修订 | 三套体系各自基线 + HD-07 (a) 的**同体系** exact 用例；跨体系比较禁止 |
| B-DUP | 保留 | bowshock/magnetopause 两份副本互比（合并前门禁）、slice2d 共线、static_c6 旧输入、color_mapping 三版本 |

### 5.5 测试计数政策（不得硬锁历史值）

1. `runtests.jl` 的通过/损坏/跳过计数**必须现场实测**（记录 Julia 版本、命令、exit code、完整摘要行）。
2. 历史记录（t1：141 passed / 1 broken）**只是历史值**。本会话静态清点：420 行、plain `@test` 117、`@test_throws` 3、`@test_broken` 1、`@testset` 20（嵌套 19 + 外层容器 1）；静态上限 ≈ 120 + 19 = 139，与 141 差 2，须由循环/多次调用生成的用例解释，**尚未现场复现**。**任何成员不得把 141 当作通过门槛或失败判据。**
3. 每次计数变化必须给出逐条解释：新增用例、删除用例（含因 HD-08 删除比较段而移除的）、合并用例的名称或来源。未解释的减少判失败。
4. `broken` 不得增加（除本文件登记项）；`skipped` 必须标注原因（缺真实数据/DLL 等），且不计入通过。
5. 缺真实数据/DLL 的用例：如实保留为 `skipped`/开放，禁止伪造、禁止改成"通过"。

---

## 6. 迁移骨架 DAG（详细分解见 t5）

```text
[首批·授权]
  t1 快照 ──► t2 本规格 ──┬─► t3 STATIC 科学契约审计 ─┐
                          ├─► t4 三个移动单元路径审计 ─┤
                          ├─► t6 依赖收敛合同 ─► t7 恢复原 16 项 ─► t8 独立验证 ─┐
                          │                                                      ├─► t5 小粒度迁移 DAG ─► t10 集成/待审批
                          └──────────────────────────────────────────────────────┘
[二次审批后]
  波 B：MIG-001 AST 工具 ─► MIG-002 Call Table ─┬─► MIG-003 用例 ─┐
                                                └─► MIG-004 runtests 冒烟入口（默认跳过）
        MIG-005 签名/单位审计表（含 TimeFormat 逐字采集、HD-07 四项结论）──► MIG-000 基线冻结（哈希清单）
                                   ▼
                            GATE-B / HA-1（人工确认）
  波 1（权威就位）：FunctionCoordinate 包化｜MarsCommon 扩充（含 HD-07 kg 体系两新名）｜MarsEnvironment（HD-04=E）｜
                    MAVEN_SWEA 收编 shape/PAD｜MAVEN_plot 收编绘图标签与 color_mapping_lut｜注册表 + 策略 P
                                   ▼
  波 2（原子迁移：新权威 + 调用点更新 + 旧名删除）：按文件锁串行/并行
                    MAVEN_load（Bpc2sphere、删除 SWEA/static_c6 旧副本、cyclone_* 旧名删除）｜
                    MAVEN_plot（数学函数迁出、边界函数指向 MarsEnvironment）｜IGRF｜SPO（TimeFormat）｜
                    TW_MINPA（slice2d_cal_rot）｜calculate_models（解体、删转发）｜src/plotting.jl｜
                    models/Pickup_ion.jl（入口更新）｜common/head.jl（拆分收尾，见 §10 Q-1）
                                   ▼
                            GATE-2 / HA-2（人工确认）
  波 3：物理移动（IGRF→models、Extras→models/extras、Pickup→analysis，均以 t4 审计为前置）｜
        Build_data/example 脚本改用 @load｜Pickup_ion 函数化
  波 4：allow 保守补全｜DataKeys 与附录 A（依 t3 结论）｜docs 同步（api.md/architecture.md/feature_addition.md）｜
        backlog 固化｜死代码与孤儿 docstring 清理（最后）
```

**DAG 约束**

1. 每个箭头都是**硬依赖**；同波内允许并行的前提是写入范围互斥（§7）。
2. 波 2 的每个单元必须同时满足 §4.1 的 C1–C7；禁止把"旧名删除"推迟到下一波。
3. 任何单元不得同时修改两个共享文件（`src/modules.jl`、`src/MarsData.jl`）之外的公共文件；共享文件锁见 §7。
4. 物理移动（波 3）必须晚于其路径审计（t4）与其文件的所有权转移；审计未完成时该单元保持阻塞。
5. 死代码清理（最后一步）只能删除注释与字符串表达式，且必须在该文件其他单元全部完成之后。

---

## 7. 文件锁与并行上限

| 文件 | 持有顺序（示例，最终以 t5 分解为准） |
|---|---|
| `common/MarsCommon.jl`、`common/marscommon/**` | MarsCommon 扩充单元（串行） |
| `common/function_coordinate.jl` | 包化 → `bowshock_zero` 删除 |
| `models/Pickup_ion.jl` | 第 3 行入口更新 → 移动 → 函数化 |
| `MAVEN_data/MAVEN_plot.jl` | 收编绘图函数 → 数学函数迁出 → 边界函数指向 |
| `MAVEN_data/MAVEN_load.jl` | 旧副本删除与 `Bpc2sphere` 迁出 → 死代码清理 |
| `MAVEN_data/MAVEN_STATIC.jl` | STATIC 常量替换 + `sta_v_4d_new` 删除（同一单元） |
| `MAVEN_data/MAVEN_SWEA.jl` | shape/PAD 收编 |
| `src/modules.jl` | 注册表单元（串行，任何含注册表变更的单元必须排队） |
| `src/MarsData.jl` | 策略 P 别名行 |
| `src/plotting.jl` | `TimeFormat` 迁出 |
| `Magnetic_Model/IGRF_calculate.jl` | `Bpc2sphere` 迁出 → 移动 |
| `TW_data/TW_MINPA.jl` | `slice2d_cal_rot` 迁出 |
| `models/Single_Particle_Orbit.jl` | `TimeFormat` 迁出 |
| `calculate/calculate_models.jl` | 解体与调用点更新 |
| `common/head.jl` | 拆分收尾（Q-1 决定后） |
| `common/data_keys.jl`、`.agent/03_ARCHITECTURE_PLAN.md` 附录 A | DataKeys 单元（依 t3 结论） |
| `docs/src/**` | 文档单元（串行） |
| `test/runtests.jl` | 追加式修改，串行 |
| `validation/**` | 分子目录并行（工具/用例/基线各自隔离） |

**并行上限**：波 1 最多 2 条实施线 + 1 条验证线；波 2 受文件锁约束；任何时刻同一文件只能有一个所有者。

---

## 8. 审查角色规则（不需要 Pro/Claude 批准）

### 8.1 角色与职责（全部由 flash/official 模型承担）

| 角色 | 职责 | 不得做 |
|---|---|---|
| **captain** | 调度、门禁、证据汇总、冲突裁决、上报用户 | 不编码、不审查自己的产物、不用"Pro 已批准"作为门禁理由 |
| **flash-arch-review**（独立架构审查） | 审查 AST diff、层规则、A2–A9 断言、注册表变更、装载冒烟、文件锁合规 | 不改实现文件；不为自己实现的单元出 pass |
| **flash-science-review**（独立科学证据审查） | 审查数值证据（exact/NaN 位置）、副作用证据、单位与类型契约、容差 `tolerance_justification`、常量语义落地 | 不修改数值或实现；**不得**自行批准放宽容差或改变科学约定（只能拒收并上报用户） |
| **flash-validation**（独立验证执行） | 在冻结基线上重跑指定命令、记录 exit code/输出/哈希、复现证据 | 不重复研究、不扩大范围、不安装包 |
| **implementers**（实现者） | 按 Owned 范围实现、提供自证命令与输出 | 不审查自己的单元；不越范围写文件 |

### 8.2 硬规则

1. **独立性**：实现者 ≠ 审查者；验证者 ≠ 实现者；captain 不批准自己经手的产物。
2. **证据要求**：任何 `pass` 必须附「可复现命令 + exit code + 关键输出 + 受影响文件哈希」；缺证据只能是 `blocked/open`，**不得**写"通过"。
3. **裁决词汇**：`pass` / `needs_revision` / `reject`；`needs_revision` 与 `reject` 必须给出结构化 findings（`id`、`severity`、`problem`、`requiredFix`、`file`、`line`）。
4. **无 Pro/Claude 门禁**：不得出现"待 Pro/Claude 批准"、"需 pro-science 复核"作为完成条件；原 `target_architecture_final.md` 中此类条款一律由 `flash-science-review` 或**用户裁决**替代。
5. **升级路径（只有两类事升级给用户）**：① 科学判断（常量语义、容差、C 类疑点、`sta_v_4d` 行为是否需要改变）；② 边界变更（范围、红线、破坏性策略、命名）。其余由机械证据决定。
6. **邮件/口头意见不是正式审查**：`agent_teams_send_message` 的讨论不构成 verdict；正式结论必须落在任务终态（`verdict` + findings/acceptanceResults）。
7. **不得伪造环境结论**：缺真实数据/DLL 时保留开放或阻塞状态；不得以合成回归代替科学正确性。
8. **不得越范围**：审查者不顺手修代码；实现者不顺带改评论许可之外的共享文件。

### 8.3 审查报告最小模板

```text
verdict: pass | needs_revision | reject
source_task_id / source_attempt_id:
scope（被审对象与提交/工作区哈希）:
acceptanceResults: [{criterion, status, evidence}]
commandsRun: [{command, status, exitCode, evidence}]
findings（needs_revision/reject 必填）: [{id, severity, problem, requiredFix, file, line}]
evidence_note（补救/追记，append-only）:
```

---

## 9. 每个迁移单元的验收标准（修正版）

1. AST diff 与预期移动清单一致；A1–A9 全部通过。
2. 关联 Call Table 用例全部通过；`pure_move` 结果 exact；NaN 按位置比较；副作用（`mutates`/`prints`）逐项有证据。
3. `runtests.jl` 现场实测：无失败；通过/损坏/跳过计数及变化按 §5.5 逐条解释；`:350` 的 constants 隔离断言仍通过。
4. `validate_registry` 不新增 errors；warnings 增量与单元声明一致；受影响模块 `load_module` 冒烟成功；allow 逐名引入冒烟成功。
5. `git diff` 文件清单不超出该单元的 Owned 范围；共享文件锁未被违反。
6. 文档同步完成：`CHANGELOG.md` 有「旧 → 新/删除 + 适配动作」行；`docs/src/**` 相关条目更新（HD-13）。
7. 实现者与审查者分离；`science_sensitive` 单元（STATIC 常量替换、SWEA shape/PAD、static_c6、cyclotron、TW_MINPA slice2d、Pickup 函数化）必须经 `flash-science-review`。
8. 交付物落盘为受跟踪文件（报告路径预先声明），不以聊天内容代替产物。

---

## 10. 未决项、缺口与阻塞

| ID | 项 | 状态 | 归属 |
|---|---|---|---|
| Q-1 | `common/head.jl` 删除还是保留为无旧名绑定的装载入口 | **待队长/用户确认** | 详见 `execution_decisions.md` §8 Q-1 |
| Q-2 | HD-07 两个新函数的最终命名 | 待用户定（暂用既有建议） | 波 1 |
| Q-3 | `calculate_models` 残余函数与注册表条目去留 | 待确认 | 波 2 |
| Q-4 | `DataKeys` 中 `:mass` 的登记状态（STATIC 不再消费标量 `:mass`） | 待 t3 结论 | 波 4 |
| Q-5 | 依赖收敛后 16 项外包的解析来源（根 Project / 全局环境 / 标准库） | **待 t7/t8 实测** | 首批 |
| Q-6 | STATIC 真实 c6 产物上的 `:mass` 等价性 | **开放证据**（缺真实数据即不通过） | t3 / backlog |
| Q-7 | `escape_energy` 缺陷（`planet≠"Mars"` 抛 `UndefVarError`）是否修复 | 不修（HD-11 精神），文档标注 | 波 4 |
| Q-8 | C 类疑点 C6/C7/C10–C13 的真实数据/SPEDAS 对照 | 开放/阻塞 | backlog |
| Q-9 | `bench_03` 重写后的性能基线形态 | 待 t5 分解 | 波 2 |
| Q-10 | 物理移动后的 `include` 兼容面（外部脚本） | 以 t4 审计为准 | 波 3 |

**缺口声明**：本轮**没有任何**数值、装载或测试层面的通过证据；`validation/` 目录尚不存在；所有 V-*/B-* 用例均未运行；科学 backlog 全部开放或阻塞。合成回归 ≠ 科学正确。

---

## 11. 合规声明

- 本任务只写入 `.agent/execution_decisions.md` 与 `.agent/target_architecture_execution.md`；未修改、未覆盖任何历史文档与科研源码、测试、配置、依赖文件、文档目录。
- 未执行写操作类 git 命令，未触碰 `.agent-teams/**` 运行状态文件，未创建子 Agent，未轮询成员。
- 本文件所有结构、ID 与断言均以 `46db822` 为锚点；未能实测的事项已明确标为未测/开放/待确认。
- **本文件不授权施工**：§1.1 之外的一切动作需二次审批；GATE-B/GATE-2/HA-F 的人工确认不得由 AI 审查替代。
