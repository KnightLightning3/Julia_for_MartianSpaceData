# dependency_convergence_review.md — 依赖收敛独立审查（t9）

> 任务：t9 [review]，attempt 1 / `3eb57403-96fb-4af9-a5e0-73013d8aac60`（official-reviewer）｜2026-10-14
> 被审对象：t7 实施（`.agent/dependency_convergence_result.md`，blob 见 §3）+ 根 `Project.toml`/`Manifest.toml` 当前字节
> 审查依据：t6 契约（`.agent/dependency_convergence_requirements.md`）§3.2/§4；用户 HD-01=A；接续基线 `46db822425378d4ad99f8f0b7cfed07360118486`；目标参考 `94da314aba65c8a129c1883931872db6198044c6`
> 写入范围：**只写本文件**。未改实现、未改环境、未安装任何包。
> **判定：pass**（三项 acceptance 全部满足；无阻塞性 findings）

---

## 0. 审查范围与独立性声明（先读）

| 项 | 事实 |
|---|---|
| 实现者 | t7 由 `official-engineer` 执行；本审查者为 `official-reviewer` ⇒ **实现者 ≠ 审查者**成立 |
| **关联声明（重要）** | 本审查者**同时是 t6 契约作者与 t8 验证者**。因此本审查**不是第三人独立审查**，而是"同一非实现者扮演契约/验证/审查三角色"的连续复核；不得据此声称已获独立第三方确认。若用户/captain 要求更高独立性，须另派未参与 t6/t8 的成员重做本审查 |
| 方法 | **现场重新取证**：本审查自行执行全部命令并自行解析，**不继承 t8 的 pass 结论**；与 t7/t8 的数值做逐项对照（三份独立执行的结果互证） |
| 范围之外 | t5 计划的 U-9 措辞与 t3 报告的常量量级错误**不属于本审查对象**，仅在 §6 作为"与依赖收敛无关的事实"单独记录，**不影响本判定**，也不要求刻意失败 |

---

## 1. 结论与 acceptance 对照

| acceptance（t9 合同） | 判定 | 依据 |
|---|---|---|
| 最新实现恢复了 94da314 的根 `Project`/`Manifest`，且原 45 项快照可追溯 | **通过** | §2 R1（字节一致）、R2（45 项可从 `46db822` blob 取回，deps=45、Manifest 3515 行）、R3（当前 16 项） |
| 范围仅限授权依赖文件及报告；源码/benchmark/global 环境未改变 | **通过** | §2 R4（改动面仅两份依赖文件 + t1 预期文档；源码目录 diff 为空）、R5（全局环境未写入）、R9（运行后无改写、无新增文件） |
| 实现与独立验证证据支持现有测试通过；科学未验证事项仍明确保留 | **通过** | §2 R8（本审查现场重跑 exit 0，141/1/142，Fail/Error/skip = 0/0/0）、§5（科学边界声明） |

**无阻塞性 findings。** 一处过程偏差的判定见 §4（结论：无需修复，只需记录）。

---

## 2. 现场证据（R1–R11）

| ID | 检查 | 实测 |
|---|---|---|
| R1 | 字节一致（主判据，原始字节） | `git hash-object --no-filters`：Project `b9b0177feadcbd25a91f1b75b21770c94dbe6192`、Manifest `a37ba5bfefd864dd9b4aa78e9e2381614a9d4233`，与 `git rev-parse 94da314:{Project,Manifest}.toml` **逐字节相同**；`git diff --exit-code 94da314 -- Project.toml Manifest.toml` → **exit 0** |
| R2 | 45 项可追溯（从 Git blob 直接解析，非引用他人结论） | `46db822:Project.toml` = `f6def9eb85dafd8c45c9d2f247f5334d6649f555`，**`[deps]` = 45 项**；`46db822:Manifest.toml` = `a92fb4d74e70d4dc2a7b08726e8c2ee86c57e712`，3515 行 ⇒ 收敛前的状态可由 `git show` 完整取回 |
| R3 | 当前依赖集合（自测解析） | `[deps]` = **16 项**；与参考集合 **集合相等**（`Compare-Object` 输出为空） |
| R4 | 范围红线 | `git diff --name-only 46db822` = `.agent/execution_snapshot.md`（t1 已登记的预期回填）+ `Manifest.toml` + `Project.toml`；**排除 `.agent` 后只剩两份依赖文件**；对全部源码/测试/配置/benchmark/docs 目录 `git diff --stat 46db822` = **空**（exit 0） |
| R5 | 全局环境未被污染 | `~/.julia/environments/v1.10/Project.toml` 2158 B/43 行、`Manifest.toml` 134770 B/3515 行，两者 mtime **2026-10-14 01:49:43**（早于 t7 与本次审查）⇒ 未被本批任务写入 |
| R6 | t6 契约内容绑定（见 §3） | requirements 现字节 blob `90fa4bde7659e3a8a3062758a7d8e43c2bb3fe41`，sha256 `54B7B18017943DBFFFAC0BB2CE5792E43E5E33E1C86D91B3D27654B1CC05743E`，19194 B / 248 行；文档内引用的 4 个 blob 哈希**均与 git 实物一致** |
| R7 | 残留/偏差 | t7 声明的两份一次性探针（`.agent/_probe_manifest.toml`、`.agent/_t7_runtests_out.txt`）**当前均不存在**；`.agent` 下非 `.md` 文件 **0 个** |
| R8 | 现场测试（本审查独立重跑） | `julia --project=. test/runtests.jl` → **exit 0**，29.4 s；摘要 `MarsData 模块装载管理器 \| 141 Pass \| 1 Broken \| 142 Total`；**Fail 0 / Error 0 / skip 0**（Broken=1 = 既有 `test/runtests.jl:30 @test_broken isempty(result.warnings)`） |
| R9 | 运行后未改写/无副作用 | 运行后哈希仍为 `b9b0177f…`/`a37ba5bf…`（测试运行未重写 Manifest）；全局 Manifest mtime 不变；`git status` 12 行（与运行前同一集合） |
| R10 | Manifest 元数据（自测） | `entries=264`、`manifest_format=2.0`、`julia_version=1.10.0`、`project_hash=040c540bcab7dc28246654e048c8e0d52a9d64b8`（与 94da314 的 Project 配对） |
| R11 | 与 t7/t8 的互证 | t7 报告声称（16 项、exit 0、141/1/142、两 blob 哈希）与本次实测**逐项一致**；t8 记录的计数（141/1/142）与本次一致 ⇒ **三次独立执行**（t7/t8/t9）结果相同 |

---

## 3. t6 契约的内容绑定与合同一致性（应 captain 要求）

**绑定（本次实测，写入本审查终态证据）**

| 项 | 值 |
|---|---|
| `.agent/dependency_convergence_requirements.md` blob | `90fa4bde7659e3a8a3062758a7d8e43c2bb3fe41` |
| sha256 | `54B7B18017943DBFFFAC0BB2CE5792E43E5E33E1C86D91B3D27654B1CC05743E` |
| 大小 / 行数 / 行尾 | 19194 B / 248 行 / LF-only（CRLF=0）、无 BOM |

**合同一致性核对（文档声称 vs git 实物 vs 本次实测）**

| 文档引用 | 出现在文档 | git 实物 | 本次实测一致 |
|---|---|---|---|
| `b9b0177f…`（94da314 Project） | 是 | 存在 | 是（R1 主判据命中值） |
| `a37ba5bf…`（94da314 Manifest） | 是 | 存在 | 是（R1） |
| `f6def9eb…`（46db822 Project，45 项） | 是 | 存在 | 是（R2：deps=45） |
| `a92fb4d7…`（46db822 Manifest） | 是 | 存在 | 是（R2：3515 行） |

- 契约 §3.2 的三条主/辅判据（hash-object、`git diff --exit-code 94da314`、LF-only）与 §4 V1–V7 的预期**全部被实现结果满足**（§2）。
- 契约 §3.3 的禁止项（`Pkg.*`、联网、改全局环境、改源码、`git checkout/restore/reset`、提交推送）**均有反向证据**：R4（范围）、R5（全局环境 mtime）、R9（运行后无改写）、R7（无残留）+ t7 报告逐条 exit code。
- 结论：**t6 契约与当前字节/实现结果一致，无陈旧声明**；本次绑定即为平台门禁所要求的"内容绑定"，已记录于 t9 终态证据（是否清除门禁由平台判定，非本审查可自证）。

---

## 4. t7 过程偏差判定（临时探针生成后删除）

| 维度 | 判定 |
|---|---|
| 事实 | t7 为取得目标 blob 精确文本与测试输出，临时在 `.agent/` 下生成 `_probe_manifest.toml`、`_t7_runtests_out.txt`，核验路径后删除 |
| 残留 | **无**：两份文件不存在；`.agent` 下非 `.md` 文件 0 个；`git status` 未出现它们（R7/R9） |
| 实际危害 | 字节（R1）、范围（R4）、环境（R5/R9）、测试（R8）四项主判据均通过 ⇒ **未发现实际危害** |
| 是否需修复 | **否**（无须返工，无须回滚）。属"过程证据未按预期落盘即删"的流程偏差，按流程记录即可 |
| 是否构成 needs_revision 理由 | **否**（不以流程瑕疵替代实质判定，也不为制造失败而失败） |
| 移交 t10 | 在首批交接中记一条过程说明：临时产物须登记"路径 + 生成时点 + 删除时点 + 是否留存哈希"；建议后续同类取证直接把输出留在报告中而非临时文件 |

---

## 5. 未验证事项与科学边界（原样保留，未升级为通过）

1. 测试套件仅覆盖**装载管理器 + 少量合成用例**；`runtests` 通过**不等于**科学正确性验证。
2. 未被本次运行覆盖：`SpecialFunctions`（仅 `common/head.jl`，在全局 Manifest 中为间接条目、按名不可解析）、`BenchmarkTools`（仅 `benchmark/*.jl`）、`Documenter`（仅 `docs/make.jl`）——该三项状态与 t6 §2.4 记录一致，**既未改善也未恶化**。
3. 未做：路径审计、AST 级引用分析、数值/科学等价性验证、真实数据/DLL 相关用例（本次运行无 skip、无 fail，但也不代表这些路径已被覆盖）。
4. 依赖来源口径仍为"根项目 + 全局 `v1.10` + stdlib"混用（t6 §2.2–2.4）；本次未逐包登记解析来源，故 `execution_decisions.md` §3.1 的"逐包登记来源"仍是**开放项**（非本审查可关闭）。

---

## 6. 与依赖收敛无关的事实记录（**不影响本判定**）

> 应 captain 要求（t9 仅依赖收敛），以下仅为事实登记，供 t5 勘误与后续科学任务使用；**未进入本审查的 acceptance 判定**。

1. **t3 的常量量级错误与已完成的勘误（本审查独立核实）**：`common/constants.jl:3,5,20`（`e=1.602176634e-19`、`mp=1.67262192e-27`、`mp_eV_per_km_s2 = mp*1e6/e`）⇒ 本审查自行计算（不引用任何他人数字）：**`0.010439684891821985`**（Float64；`1/值 = 95.78833177075664`；`Float32(值) = 0.010439685`，且 `Float32(值) == 值` 为 **false**）。t3 原报告的"≈9.6485e8"与实测相差约 11 个数量级。
   该数值错误**已由 t3 就地修订**：修订后 `.agent/static_mass_removal_audit.md` blob = `1ccd2771f9bfb2aa3417b5a7a0b924c65bb0aa38`、sha256 = `3FB00312809CA699DA48701F7A18D9C1D61F23EB7ED5B4E755C6D296432D59FA`、18535 B / 170 行，顶部第 10–11 行含「勘误」块。本审查对修订后字节**逐项复核通过**：blob/sha256/大小/行数与 t3 通知一致；`9.6485e8` 仅命中 1 处（勘误块内）、`1836` 零命中、`0.010439684891821985` 命中 6 处；且其更正值与本审查自算值**完全一致**。
   因该报告为终态、`output` 原文不可改（append-only），错误的"≈9.6485e8"仍留存在 t3 任务 `output` 文本中 ⇒ 后续引用**必须以修订后工件字节为准**，不得引用 `output` 原文。
2. **t5 的 U-9 措辞需收窄**（与上述错误相关）：待删 `sta_v_4d_new` 内的局部 `::Float32` 断言**不能推广**为"其余生产数据是 Float32"；若数据包 `:mass` 本身就是 Float64 且与常量同值，纯替换可 **exact**；若为 Float32，则 `Float32(常量) ≠ 常量`（本审查自算可证：`0.010439685` 与 `0.010439684891821985` 位不一致）⇒ 是否需容差、容差多大，须由**小 fixture 实测后决定并附依据**，不得先行放宽。修订后的 t3 报告已改为同一条件式口径（exact 或容差由 fixture 实测决定），与本条一致。
3. **过程缺口（如实记录，非本审查对象）**：t3 修订前**未先取哈希**，故修订前的 blob/sha256 无法提供（仅能给出 15804 B/165 行 → 18535 B/170 行的规模变化）。建议后续任务在修改任何已落盘工件前先记录其哈希，以便事后可验证"改了什么"。
4. 上述三项的处置属 t5/t3 范围；本审查不修改其终态结果，也不据以变更本 verdict。

---

## 7. 合规声明

- 本任务**只写** `.agent/dependency_convergence_review.md`；未修改 `Project.toml`/`Manifest.toml`、未修改任何源码/测试/配置/文档、未修改 t7/t8/t6/t3/t5 的既有产物。
- 未执行任何 `Pkg` 变更或安装、未联网；`git` 命令全部只读（无 `add/commit/checkout/restore/reset/push`）。
- 未删除任何文件；未创建临时文件（本次审查的输出全部在会话内捕获，不落盘）。
- 未创建子 Agent、未轮询、未启用自动目标；`.agent-teams/**` 未读写。
- 本报告不写入自身哈希（避免自引用改变字节）；其字节绑定由 t9 任务终态证据与 t10 交接承载。
