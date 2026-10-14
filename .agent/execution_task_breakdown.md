# execution_task_breakdown.md — 基线工具 + 小粒度「无旧兼容」迁移 DAG（t5）

> 任务：t5 [next-plan]，attempt 1 / `396e8d89-88c8-4b21-a141-ef505bea69ba`（official-reviewer）｜2026-10-14
> 基线：`46db822425378d4ad99f8f0b7cfed07360118486`；依赖参考提交 `94da314aba65c8a129c1883931872db6198044c6`
> 输入（引用其 hash，不重复其内容）：t2 `execution_decisions.md` + `target_architecture_execution.md`；t3 `static_mass_removal_audit.md`（**修订后字节为准**：blob `1ccd2771f9bfb2aa3417b5a7a0b924c65bb0aa38`，sha256 `3FB00312809CA699DA48701F7A18D9C1D61F23EB7ED5B4E755C6D296432D59FA`，18535 B/170 行）；t4 `physical_path_audit.md`（blob `3e0774a7e00cc0c30c4afd61cca0445602cdc85b`）；t6 `dependency_convergence_requirements.md`（blob `90fa4bde7659e3a8a3062758a7d8e43c2bb3fe41`）；t7 `dependency_convergence_result.md`；t8 `dependency_convergence_verification.md`（blob `694d9b0901fc843a5c92ff16a5151dd1ba68a545`）。
> **本文件只规划，不施工。** 唯一写入路径即本文件。首批（t1–t10）已由用户限定在基线门禁内；下方「波 B 及以后」全部**待二次审批**。

---

## 0. 编排原则（约束优先于任务内容）

1. **无旧兼容**：旧名删除、不转发、不 alias、不 shim、不旧门面、不发 depwarn（t2 R-1/R-11、HD-03/06/09/13/15）。
2. **原子单元**：每个函数组的迁移必须在同一单元内完成"新权威 → 全仓调用点更新 → 旧名删除 → 断言/测试"（t2 §4.1 C1–C7）；不许"先建后删"跨波留下双实现。
3. **角色可跨单元**：同一实例可兼工程与审查，**唯一硬约束 = 不审自己的实现**；规划者不参与自己设计对象的独立最终审定。不设"reviewer 永不实现"的人工串行。
4. **名额（建议，不现在建成员）**：现 5/8（captain + official-engineer / official-reviewer / ustc-glm-auditor / ustc-path-auditor）。并发建议 ≤2 实施线 + 1 独立审查线；新增槽位仅在二次审批后按需建。
5. **模型范围**：不使用 Claude / Pro / 嵌套 agent；**不使用 Gemini（用户新决定：免费额度不适合作 agent 工作）**，候选名单亦不列；**不保留"待启用机械迁移成员"占位**（本决定覆盖 t5 合同里"Gemini 可作未来候选"的旧措辞）。
6. **慢渠道（USTC）**：只派**单文件或单函数组**小单元，产物一页内；两次 300000ms 超时记录在先，不排关键路径。
7. **共享核心文件串行**：`src/modules.jl`、`src/MarsData.jl`、`common/MarsCommon.jl`、`test/runtests.jl` 一次只有一个所有者（t2 §7 文件锁）。
8. **工具纪律**：只用可见的精确文件工具；**不假装存在行剪切接口**。若确需整文件搬迁助手，必须满足：①绝对路径核验 ②源/目标哈希前置 ③不覆盖既有目标 ④`dry-run` 先出清单 ⑤失败回退明确；**先审后用**，且仅在纯搬迁单元使用。
9. **证据纪律**：verify 命令必须可现场重跑并记录 exit code；**纯函数迁移一律 exact**；STATIC 常量替换是**用户授权的 Float32→Float64 质量基准精度提升**（`dat[:mass]` 来自原始 CDF、Float32、值 ≈0.01；`constants.mp_eV_per_km_s2 = 0.010439684891821985` 为 Float64；二者表示**同一物理量** —— **用户提供的契约事实，非本团队读真实 CDF 实测**）⇒ Float32 旧 fixture 与新结果**可有预期舍入差异**：记录两侧 dtype 与误差，并**按实测证据设置容差**；**同一 Float64 基准或不受此影响的路径仍判 exact**，**不机械全局放宽**；公式、运算次序与 `mass_arr`/`m_int` 均不变（见 §6 勘误）。缺证据记开放/阻塞，不记通过（t2 R-6）。
10. **测试计数**：以 MIG-000 现场实测为唯一基线（t8 实测 `141 Pass / 1 Broken / 142 Total`，与 t7 一致；既有 broken = `test/runtests.jl:30`）；不得以历史值硬锁。

---

## 1. 门禁与波次

```text
[首批·已完成/授权内] t1 快照 ─ t2 规格 ─ t3 STATIC 审计 ─ t4 路径审计 ─ t6 契约 ─ t7 恢复16项 ─ t8 独立验证 ─ t5 本计划
                                                    ▼
波 B：B-01 AST/层规则工具 ─ B-02 Call Table 框架 ─ B-03 用例与 fixtures ─ B-04 runtests 冒烟入口(默认跳过) ─ B-05 基线冻结(MIG-000)
                                                    ▼
                                   GATE-B / HA-1（人工确认：框架自检 + 基线冻结 + t3/t4 在位 + HD-07/08/09 口径）
                                                    ▼
波 1（权威就位，不动旧名）：W1-01 FunctionCoordinate ｜ W1-02 MarsCommon 扩充 ｜ W1-03 MarsEnvironment(E) ｜
                            W1-04 MAVEN_SWEA 收编 ｜ W1-05 MAVEN_plot 收编 ｜ W1-06 STATIC 常量替换+删 _new ｜ W1-07 注册表+策略P
                                                    ▼
波 2（原子迁移：调用点更新+旧名删除）… W2-01…W2-08（受文件锁约束并行） ──► GATE-2 / HA-2（人工确认）
                                                    ▼
波 3（物理移动，前置 t4）：W3-01 IGRF ｜ W3-02 Extras ｜ W3-03 Pickup   ──► 波 4（收尾）W4-01…W4-04 ──► HA-F
```

---

## 2. 任务表

每条 `verify` 均为可运行命令；`[sh]` = 共享文件，须排队。验收统一含 t2 §4.1 的 C1–C7（除纯工具任务）。

### 波 B — 工具与基线（不建成员；建议 official-engineer 实施、official-reviewer 独立审查）

| ID | 波 | Owned（精确路径） | 依赖 | 验收 | verify |
|---|---|---|---|---|---|
| **B-01** | B | `validation/ast/**`、`validation/architecture/layers.toml`（新） | GATE-首批后 | AST 抽取（定义/using/include/const/调用点）；层规则含 `[edges]`（**无 `[compat_edges]`**）、`[moves]`、`[removed_names]`、`[preinstall]`；断言 A1–A9（t2 §5.2）实现并自检 | `julia --project=validation validation/ast/selfcheck.jl`（建后运行，exit 0 且 oracle 精确命中 t2 §5.2 A9） |
| **B-02** | B | `validation/calltable/{schema.md,runner.jl,compare.jl,selftest.jl}`（新） | B-01 | schema 含 `entry`/`removed_old_entry`/`evidence_level`；比较器覆盖标量/Array/Tuple/Dict/struct/DataFrame、NaN positional、Inf、`missing` 报错、`mutates`/`prints` | `julia --project=validation validation/calltable/selftest.jl`（exit 0，含 NaN 位置报告用例） |
| **B-03** | B | `validation/calltable/cases/**`、`validation/fixtures/**`（新） | B-02 | 基线用例齐备：B-025/B-004/B-018/B-022/B-003/B-CYC/B-DUP/B-INST；**STATIC 最小合成回归 T1–T7**（t3 修订后 §3/§4 + 用户科学契约：**Float64 基准路径判 exact**；**Float32 旧 fixture 对新结果记录 dtype/误差并按证据设容差**（授权精度提升的预期舍入差异，不机械全局放宽）；异值、缺失 `:mass`、`valid==0` 的 SVector(NaN)+`println`、`df ≈ df_mass_mass .* mass_arr.^2` 关系保持）；无 `:new` 对照用例 | `julia --project=validation validation/calltable/runner.jl --all --baseline`（用例全部可运行） |
| **B-04** | B | `test/runtests.jl`（**只追加**）[sh] | B-02 | 追加验证冒烟入口，环境变量开关、**默认跳过**；默认运行计数不变 | `julia --project=. test/runtests.jl`（exit 0；默认与基线同计数） |
| **B-05** | B（末尾） | `validation/results/baseline/**`（新，单一写入者） | B-01,B-03 | 冻结 AST/Call Table 基线 + 现场实测计数 + 文件哈希清单；记录 `141/1/142` 与既有 broken 位置 | `julia --project=validation validation/freeze.jl`（产出哈希清单，可复现） |

**GATE-B / HA-1（人工确认，不由 AI 自评）**：B-01 自检通过 + B-05 基线冻结 + t3/t4 审计在位 + HD-07/08/09 落地口径确认。未过门禁不得启动波 1。

### 波 1 — 权威就位（新增实现，旧名暂留原位，禁止在第 1 波删除旧名）

| ID | Owned | 依赖 | 验收 | verify |
|---|---|---|---|---|
| **W1-01** | `common/function_coordinate.jl`、`models/Pickup_ion.jl`（仅 include/using 行） | GATE-B | 包成 `module FunctionCoordinate`（G-include）；迁入 `rotation_matrix`/`Quaternion_Rot`/`Quaternion_Rot_reverse`；Pickup 的 `include`+精确 `using` 行同批更新（装载必需，非兼容 shim） | `julia --project=. -e 'using MarsData; MarsData.load_module(:FunctionCoordinate); println(names(MarsData.FunctionCoordinate))'` |
| **W1-02** | `common/MarsCommon.jl`、`common/marscommon/*.jl`（新子文件） | GATE-B、B-03 | 迁入数学/几何/统计函数与 `TimeFormat`；**HD-07 (a)** 加入 kg 体系两个独立名（暂定 `cyclotron_frequency_kg`、`cyclotron_radius_velocity`，最终名待用户）；PL-1/PL-2 通过 | `julia --project=. -e 'using MarsData; using MarsData.MarsCommon; println(MarsCommon.TimeFormat(1,2))'` + `validation` 中 B-* 用例 exact |
| **W1-03** | `models/Mars_Environment.jl`（新） | GATE-B、W1-02 | HD-04=E：边界/环境函数独立成模块（L4、无状态、G-include）；`escape_energy` 缺陷**原样保留并加注释**（不改值） | `julia --project=. -e 'using MarsData; MarsData.load_module(:MarsEnvironment)'`（建注册表后）；本波先 `julia -e 'include("models/Mars_Environment.jl")'` 无错 |
| **W1-04** | `MAVEN_data/MAVEN_SWEA.jl` | GATE-B、B-03 | 收编 SWEA shape/PAD（`SWEA_calc_shape_arr*`、`mean_SWEA_pad_pa`、`carclu_SWEA_pad`）；B-018/B-022 exact | `julia --project=. -e 'using MarsData; MarsData.load_module(:MAVEN_SWEA)'` + B-022 用例 |
| **W1-05** | `MAVEN_data/MAVEN_plot.jl` | GATE-B、W1-02（选 E 再加 W1-03） | 收编 head.jl 绘图函数（`color_mapping_lut`、`label_data`、`print_f`、`norm2`、`get_log_ticks`）；同名遮蔽断言 A6 通过 | `julia --project=. -e 'using MarsData; println(isdefined(MarsData.MAVEN_plot, :color_mapping_lut))'` + bench_06 冒烟 |
| **W1-06** | `MAVEN_data/MAVEN_STATIC.jl` | GATE-B、B-03 | **① 常量替换**：`dat[:mass]` 9 个读取点（237/301/321/332/442/575/732/949/990）→ `constants.mp_eV_per_km_s2`（**用户授权的 Float32→Float64 质量基准精度提升**），并在等离子矩处加"与 `dat[:mass]` 完全等效"备注；**不动** `:mass_arr`/`m_int`/`:577`/`:589`/`:243` 的算式形式；**三角色独立（用户说明）**：`dat[:mass]`=质量基准（本单元**唯一**被精度升级者）；`mass_arr`（数组，对应探测到的不同离子）与 `m_int`（选定离子的标量）均表示 **NASA 约定的原子质量数（AMU 口径）**，二者与 `mass` 相乘得到对应离子静止质量 ⇒ **保留 `mass_arr`/`m_int` 及其乘法，不替换为质子常量，不引入新的 AMU↔质子质量换算，不改数据键**；**② 删除** `sta_v_4d_new`（区间 **597–688**，含 docstring）；**③ 同批**改 `benchmark/bench_03_sta_v4d.jl` 比较段（去 `isdefined` 兼容分支）、`docs/src/api.md:119` 只列 `sta_v_4d`；历史 `docs/reports/**`、`benchmark/results/baseline_report.md` 不动 | `julia --project=validation validation/calltable/runner.jl --tag STATIC`（T1–T7 通过：**Float64 基准路径 exact**；**Float32 旧 fixture 的预期舍入差异**按其记录的 dtype/误差与容差依据判定） + `Select-String -Path MAVEN_data\MAVEN_STATIC.jl -Pattern 'sta_v_4d_new'` 零命中 + `julia --project=. test/runtests.jl` exit 0 |
| **W1-07** | `src/modules.jl`（注册表区）、`src/MarsData.jl` [sh] | W1-01/02/05（选 E 加 W1-03） | HD-05 策略 P：`:MarsCommon`（及 `:MarsEnvironment`）`kind=:preloaded` + 别名行；**机制代码零改动**；`constants` 豁免 I-4；V-I1…V-I5 | `julia --project=. -e 'using MarsData; println(MarsData.MarsCommon === MarsData.MAVEN_plot.MarsCommon)'`（期望 true）+ `julia --project=. test/runtests.jl` exit 0 |

### 波 2 — 原子迁移（每个单元：新权威调用 + 旧名删除 + 调用点同批；受文件锁串行/并行）

| ID | Owned | 依赖 | 验收 | verify |
|---|---|---|---|---|
| **W2-01** | `MAVEN_data/MAVEN_load.jl` [sh] | 波 1 全 | `Bpc2sphere` 迁出后旧名删除；**删除** SWEA shape/PAD 与 `static_c6_*` 旧副本（不得留转发，L2→L3 禁边）；`cyclone_*` 旧名删除并指向 W1-02 新名 | `Select-String` 三个旧名零命中 + `julia --project=. -e 'using MarsData; MarsData.load_module(:MAVEN_load)'` |
| **W2-02** | `MAVEN_data/MAVEN_plot.jl` [sh] | W1-05 | 数学函数改直接调用新权威（无转发）；删死 export `WaveSpactra_heatmap` | `julia --project=. -e 'using MarsData'` 冒烟 + A5 无兼容断言通过 |
| **W2-03** | `Magnetic_Model/IGRF_calculate.jl` | W1-02 | `Bpc2sphere`/`Bsphere2pc` 迁出、旧名删除、调用点更新 | `julia --project=. -e 'using MarsData; MarsData.load_module(:IGRF_calculate)'` + B-004 用例 |
| **W2-04** | `TW_data/TW_MINPA.jl` | W1-01 | 私有 `slice2d_cal_rot` 迁出并删旧名；共线输入一致性证据 | `julia --project=. -e 'using MarsData; MarsData.load_module(:TW_MINPA)'` + B-DUP 共线用例 |
| **W2-05** | `models/Single_Particle_Orbit.jl` | W1-02 | `TimeFormat` 迁出、旧名删除、显式传原格式；输出逐字一致（依 t2 §4.4 逐字采集口径） | 用例 exact + `julia --project=. -e 'using MarsData; MarsData.load_module(:Single_Particle_Orbit)'` |
| **W2-06** | `calculate/calculate_models.jl` | W1-01/02（选 E 加 W1-03） | 解体：旧门面转发取消，`Linear_fit`/旋转/边界/cyclotron 各自改调新权威；残余实现保留 | `julia --project=. -e 'using MarsData; MarsData.load_module(:calculate_models)'` + 门面用例 exact |
| **W2-07** | `src/plotting.jl` | W1-02、W1-07 | `TimeFormat` 迁出、旧名删除 | `julia --project=. test/runtests.jl` exit 0（V-N1 类断言） |
| **W2-08** | `common/head.jl`、`models/Pickup_ion.jl`、`example/**`、`MAVEN_data/Build_data/*.jl` | W2-01…07、**U-5 裁决** | head.jl 按能力拆分收尾、**不保留任何旧名绑定**；脚本改 `using MarsData` + `@load`；A3 悬空引用为零 | `Get-ChildItem -Recurse -Include *.jl \| Select-String 'head\.jl'` 零命中（除裁决保留项）+ `julia --project=. -e 'using MarsData'` |

**GATE-2 / HA-2（人工确认）**：A1–A9 全通过、无重复实现（不合并项除外）、无悬空引用、无兼容残留、`runtests` 与基线计数一致（差异逐条解释）。

### 波 3 — 物理移动（**前置 t4 审计；IGRF 伴随资产需 U-1 裁决后方可动手**）

| ID | Owned | 依赖 | 验收/关键约束 | verify |
|---|---|---|---|---|
| **W3-01** | `Magnetic_Model/IGRF_calculate.jl` → `models/`、`src/modules.jl:88`、`example/MAVEN_plot_sample/*.jl:15`、`models/Pickup_ion.jl:278`、IGRF 伴随资产（按 U-1） | GATE-2、U-1 裁决 | **只移 .jl 必致装载失败**（`:807-809`+`:812`）；方案 A（资产同移）或 B（源码移动 + `:807-809` 显式路径）；**不改 IGRF 自身 `root_dir` 语义**；不把 `PROJECT_ROOT`/`fortran_dll_dir()` 与 `root_dir` 说成"必须统一"（未证实）；`gh_gao.txt` 受"数据只读"约束，**不得删除** | `julia --project=. -e 'using MarsData; MarsData.load_module(:IGRF_calculate)'` + `julia --project=. test/runtests.jl` 中 IGRF 分支（`:197-205`）通过 |
| **W3-02** | `models/Graham.jl`、`models/Octree.jl` → `models/extras/`（新建目录）、`docs/src/api.md:301` | GATE-2 | 零代码引用；**命名纠正为 `Graham.jl`**（文档误写 `Grahame`）；**无 `module` 包装 ≠ 纯物理移动授权** → 是否加 module 包装属 U-6 裁决，未定则不包化 | `julia --project=. -e 'include("models/extras/Graham.jl"); println(isdefined(Main, :graham_scan_for_orbit))'` |
| **W3-03** | `models/Pickup_ion.jl` → `analysis/`（新建目录）、`models/Pickup_ion.jl:273-278` | GATE-2、**与 W3-01 同批** | 目录须在**仓库根**（`analysis/`）以保持 4 处相对 include 解析不变；`:273-278` 硬编码 `D:/CODE/…` 处置（明确报错或 `@__DIR__`/`project_root()` 推导，**不换另一个硬编码根**）；`:278` 的 IGRF 路径须与 W3-01 一致 | `julia --project=. -e 'include("analysis/Pickup_ion.jl")'`（无 include 解析错误） |

### 波 4 — 收尾

| ID | Owned | 依赖 | 验收 | verify |
|---|---|---|---|---|
| **W4-01** | `src/modules.jl`（allow 区）[sh] | GATE-2 | allow 保守补全；逐名引入冒烟 | `julia --project=. test/runtests.jl` exit 0 + 逐名冒烟脚本 |
| **W4-02** | `common/data_keys.jl`、`.agent/03_ARCHITECTURE_PLAN.md`（仅附录 A） | W1-06、U-8 | 依 t3 结论登记 `:mass` 语义；**禁止**同值无前缀双常量 | 契约测试 + A 表一致性检查 |
| **W4-03** | `docs/src/architecture.md`、`docs/src/feature_addition.md`、`docs/src/api.md`、`CHANGELOG.md` | GATE-2 | 破坏性变更（B-01…B-11）逐条"旧→新/删除+适配动作"；科学 backlog 固化 | 文档审查（人） |
| **W4-04** | 逐文件（该文件其他单元全部完成后） | 全部 | 只删注释与孤儿 docstring（D-4 两处）；AST 确认无代码语义变化 | A7 断言 + `git diff` 仅注释/字符串变化 |

---

## 3. 需用户裁决项（不裁决则相关单元保持阻塞）

| ID | 事项 | 选项 | 建议与理由 |
|---|---|---|---|
| **U-1** | IGRF 移动时 `gh_gao`/`IGRF_DLL.dll`/`gh_gao.txt` 如何处置 | **A** 伴随资产随单元同移；**B** 源码移动 + `:807-809` 改为显式路径 | 建议 **B**：数据/二进制留原位，符合既有"数据与配置只读"约束；不移动 640 KB 受跟踪二进制；无需触碰零引用的 `gh_gao.txt`。代价是 `models/IGRF_calculate.jl` 需引用既有数据目录（经 `Paths.project_root()` 派生，非新硬编码根） |
| **U-2** | `gh_gao.txt` 去留 | 保留原位 /（删除需单独批准） | 保留：`03_ARCHITECTURE_PLAN.md:577` 已把它列为只读受保护资产 |
| **U-3** | 是否把 IGRF 的 DLL 口径统一到 `Paths.fortran_dll_dir()` | 统一 / 不统一 | 建议**不统一**：两者机制不同（目录 vs 完整路径）且统一属行为变更，未证实"必须统一" |
| **U-4** | HD-07 两新名最终命名 | 用户定 | 暂用 `cyclotron_frequency_kg` / `cyclotron_radius_velocity` |
| **U-5** | `common/head.jl` 去留 | 删除 / 保留为无旧名入口 | 建议删除（仓内仅 `models/Pickup_ion.jl:3` 引用）；保留则须零旧名绑定 |
| **U-6** | Extras 是否加 `module` 包装 | 是 / 否 | 建议**本轮否**：移动 ≠ 包化授权；包化单列后续任务 |
| **U-7** | `analysis/` 与 `models/extras/` 的确切位置 | 仓库根 `analysis/` / `models/analysis/` | 建议仓库根（t4：同级前提下 Pickup 的 4 处相对 include 才不变） |
| **U-8** | `DataKeys` 中 `:mass` 登记（STATIC 不再消费标量 `:mass`） | 依 t3 结论 | 不得新增同值无前缀常量 |
| **U-9** | STATIC 替换验收口径（**已由用户明确，不再待裁决**） | 授权 Float32→Float64 精度提升 | 用户契约：`dat[:mass]` 来自原始 CDF、**Float32**、值 ≈0.01，与 Float64 `constants.mp_eV_per_km_s2 = 0.010439684891821985` 表示**同一物理量**；替换意图 = **提高数值精度**（**用户提供事实，非团队读真实 CDF 实测**）。验收：Float64 基准或不受此影响的路径判 **exact**；**Float32 旧 fixture 对新结果记录 dtype/误差并按证据设容差**（预期舍入差异），**不机械全局放宽**；公式、运算次序与 `mass_arr`/`m_int` 不变 |

---

## 4. 不做清单（本轮 + 未获二次审批前）

- 不施工：本文件之外不创建/修改任何文件；波 B 及以后全部待二次审批。
- 不建成员、不建 Gemini 槽位、不派 GLM 空闲任务、不启用自动目标/子 agent；不使用 Claude/Pro。
- 不安装/升级包、不改 `~/.julia/environments/**`、不改 `Project.toml`/`Manifest.toml`（已完成，勿再动）。
- 不做函数级性能优化；不纳入 TASK-026/039/040（HD-12）；不发 depwarn（HD-13）；不把 STATIC `:mass` 解释外推到 MINPA/SWIA（HD-10/11）。
- 不改写历史文档（`docs/reports/**`、`benchmark/results/**`、`.agent/*_final.md`、`*_recheck.md`）。
- 未获复核前不实现"整文件搬迁 Python 助手"（须先满足 §0.8 五项安全设计并经独立审查）。

---

## 5. 合规声明

- 本任务**只写** `.agent/execution_task_breakdown.md`；未修改源码/测试/配置/依赖文件/文档目录/审计报告。
- 全程只读引用已有产物（t2/t3/t4/t6/t7/t8）；未重跑其研究、未安装包、未移动或删除任何文件。
- 未创建子 agent、未轮询、未启用自动目标；`.agent-teams/**` 未读写。
- 本计划不含"已通过"的科学结论：所有迁移验收均为**待执行**；科学正确性边界与开放证据（t3 §5 U-A…U-D）原样保留。

---

## 6. 勘误记录（append-only；不改本计划既有结论）

> 记录人：official-reviewer｜时间：2026-10-14（captain 授权精确勘误）｜**本块为追加内容，未删除或重写任何原有句子**。

| 项 | 内容 |
|---|---|
| 触发 | ① t3 报告原记 `constants.mp_eV_per_km_s2 ≈ 9.6485e8` 属**未实测数值错误**（正确值由本计划作者独立自算为 **`0.010439684891821985`**，`1/值 = 95.78833177075664`，`Float32(值) = 0.010439685` 且与 Float64 值位不一致）；② 原 U-9/§0.9/W1-06/B-03 由该错误值推出"只能容差验收"，属**过度结论** |
| 勘误后口径 | STATIC 常量替换**先判 exact**（同值、逐位/`isequal`）；**仅当** fixture 实测证实舍入差异，才使用容差并附 rtol 依据与两侧 dtype 记录；**不得先行放宽**，也不得把未观测的 dtype 假定当作全仓事实 |
| 被修改的句子（仅此 5 处） | 头部输入行（t3 改为按修订后字节引用）；§0.9 证据纪律；§2 B-03 验收；§2 W1-06 verify；§3 U-9 行 |
| t3 依据（修订后字节） | `.agent/static_mass_removal_audit.md` blob `1ccd2771f9bfb2aa3417b5a7a0b924c65bb0aa38`，sha256 `3FB00312809CA699DA48701F7A18D9C1D61F23EB7ED5B4E755C6D296432D59FA`，18535 B/170 行（修订前 15804 B/165 行，**修订前未先取哈希**） |
| 本计划字节 | 勘误前 blob `2dc171aa7d5a38ed335f7ef33868b5721d287e6d`（138 行/18951 B）；勘误后哈希见 t5 终态的 append-only 证据（本文件不写自身哈希，避免自引用再次改变字节） |
| 未受影响 | §1 波次、§2 其余 26 个任务、§3 U-1…U-8、§4 不做清单、§5 合规声明；本计划的"待二次审批、不施工"性质与 t5 终态 verdict 均不变 |
| **二次勘误（用户科学契约，2026-10-14）** | 用户明确：`dat[:mass]` **来自原始 CDF、Float32、值 ≈0.01**，与 Float64 `constants.mp_eV_per_km_s2 = 0.010439684891821985` 表示**同一物理量**；替换意图 = **提高数值精度**（**用户提供事实，非团队读真实 CDF 实测**）。据此：来源/dtype **不再列为"待用户确认/未观测"项**；**Float32 旧 fixture 与新结果的预期舍入差异**须记录 dtype/误差并按证据设容差；**同一 Float64 基准或不受此影响的路径仍判 exact**；纯函数迁移继续 exact；公式、运算次序、`mass_arr`/`m_int` 不变 |
| 二次被修改的句子 | §0.9 证据纪律；§2 B-03 验收；§2 W1-06 验收（① 标注"授权精度提升"）与 verify；§3 U-9 行（改为"已由用户明确，不再待裁决"） |
| **三次勘误（用户说明，2026-10-14）** | 用户明确：`mass_arr`（数组，对应探测到的不同离子）与 `m_int`（选定离子的标量）均表示 **NASA 约定的原子质量数（AMU 口径）**，**不是** `mass` 质量基准的同义量；关系为 `mass` × 质量数 = 对应离子静止质量。⇒ 保留 `mass_arr`/`m_int` 及其乘法，**不替换为质子常量**，**不引入新的 AMU↔质子质量换算、不改数据键**；STATIC 现行近似/单位约定照用户要求保留，**精度升级仅限 `mass` 基准 Float32→Float64**。无需追溯 NASA 文献或额外推导 |
| 三次被修改的句子 | §2 W1-06 验收（"不动"子句扩写为三角色独立说明）；§6 追加本两行 |
