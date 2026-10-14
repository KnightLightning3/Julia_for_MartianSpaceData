# 04_OPTIMIZATION_PLAN.md — PHASE 4：性能优化计划与 PHASE 6 可执行任务分解

> 状态：DONE
> 阶段：PHASE 4 - Optimization Planning
> 负责：DeepSeek V4 Pro (Scientific Architect / Performance Architect)
> 依赖：`.agent/01_PROJECT_MAP.md`、`.agent/02_ARCHITECTURE_REVIEW.md`、`.agent/03_ARCHITECTURE_PLAN.md`（三者均为正式输入，本文件只引用、未改动；01/02 禁止覆盖）
> 性质：**只读规划**。本阶段不修改任何源码，仅在 `.agent/` 下覆盖本文件。
> 用途：把 03 的架构方案（ARCH-001…017）分解为**可独立实施、独立测试、按依赖排序**的 Coding Task（TASK-001…048），供 PHASE 6 依次执行；性能类任务附带硬性 benchmark 口径（R2），科学类任务附带科学结果验证口径（R4），重大科学算法以 03 §15 与本文件任务条款为唯一执行依据（R5）。

---

## 1. 执行协议

### 1.1 任务字段（每个 TASK 必须包含全部 15 项）

| 字段 | 含义 |
| --- | --- |
| Task ID | TASK-001…048（唯一、顺序即执行顺序） |
| 对应 ARCH ID | 03 中的架构变更编号（可多个） |
| Objective | 一句话目标 |
| 修改文件 | 精确到文件（新增/修改） |
| 修改函数 | 精确到函数名/行区间 |
| 当前行为 | 改动前行为（含已知 bug/债务） |
| 目标行为 | 改动后行为（本文件定稿，实现 Agent 照做） |
| 依赖任务 | 前置 TASK 编号（含"同文件顺序"软依赖） |
| 风险 | 等级 + 内容 |
| 预期收益 | 量化或可论证收益 |
| 涉及科学计算 | 是/否 |
| 涉及数值结果 | 是/否（是 = 必须做改动前后数值对比，R4） |
| 测试要求 | 具体测试与验收标准（R3） |
| Benchmark 要求 | 具体基准或"无（非性能任务）"（R2） |
| 文档要求 | 06/07/08 记录要求 |

### 1.2 硬性执行规则

1. **顺序执行**：任务按编号顺序执行；依赖未完成不得开始；同文件任务必须串行。
2. **绿灯门禁**：每个任务的"测试要求"全绿才允许标记完成并进入下一任务；失败即修，不得带病前进。
3. **证据入库**：所有数值对比/基准结果写入 `benchmark/results/`（golden JSON 入库），摘要写入 `06_IMPLEMENTATION_LOG.md`；PHASE 7 汇总进 `07_VERIFICATION.md`。
4. **R2**：任何以性能为理由的改动必须携带本文件指定 benchmark 的前后对比；无数据不得合入。
5. **R3**：任何重要修改必须同步更新 `test/runtests.jl` 并运行通过（`julia --project=. test/runtests.jl`）。
6. **R4**：标"涉及数值结果=是"的任务，必须产出改动前后对比（合成数据 rel ≤ 1e-9，或逐位一致；真实数据 opt-in），方法与结论写入 06。
7. **R5**：重大科学算法只在 03 §15 与本文件定义范围内实施；表中"记录不改值"项严禁改值；超出范围立即停手上报。
8. **CONDITIONAL 任务**（TASK-045…049）：执行前必须满足其"门"条件并先在 06 记录触发证据；门未满足 = 跳过该任务，不得硬做。
9. 建议执行人仅供参考（GLM-5=复杂实施 / Qwen=批量 / V4 Flash=测试·基准·文档），由船长调度。

### 1.3 与 03 迁移步骤（S0–S11）的映射

| 03 步骤 | 任务 | 内容 |
| --- | --- | --- |
| S0a | TASK-001 | benchmark 基建 + 合成数据基线 + 纯函数 golden 快照 |
| S1 | TASK-002…007 | P0 修正包（ARCH-007/001） |
| S0b | TASK-008 | 真实数据 golden 快照与 loader 基准（依赖 A1 修复） |
| S2 | TASK-009…011 | 路径统一（ARCH-005） |
| S3 | TASK-012…013 | 显式函数表 + 日期索引（ARCH-004） |
| S4 | TASK-014…015 | include 统一 + validate 扩展（ARCH-003） |
| S5 | TASK-016…017 | DataKeys + 契约（ARCH-011） |
| S6 | TASK-018…023 | 科学修正与出处注释（ARCH-008） |
| S7 | TASK-024…026 | 状态显式化（ARCH-009） |
| S8 | TASK-027…034 | 签名审计 + 去重（ARCH-006） |
| S9 | TASK-035…038 | 脚本层迁移（ARCH-002/013） |
| S10 | TASK-039…042 | 绘图面板化 + API 面（ARCH-012/010） |
| S11 | TASK-043 | 死代码清理（ARCH-016） |
| 条件 | TASK-044…048 | 性能优化（ARCH-014，全部带门） |

### 1.4 依赖关系总览（简化）

```
TASK-001
TASK-002 → 003 → 004 → 005 → 006 → 007 → 008（S0b 快照）
  009/010/011（互不依赖，可与 012 并行批次）
TASK-012 → 013
TASK-014 → 015 → 016 → 017
TASK-018/019/020/021/022/023（均依赖 008 或 001 的基线；021 依赖 001 的基准项7）
TASK-024（独立）→ 025（依赖 013 同文件）→ 026（依赖 021 同文件）
TASK-027（审计，门禁 028–034）→ 028 → 029 → 030 → 031 → 032 → 033 → 034
   （029 依赖 028+014；030 依赖 022+018；031 依赖 025；034 依赖 029）
TASK-035（依赖 027/029）→ 036（依赖 035/033/013/007）→ 037（依赖 012）→ 038（依赖 040）
TASK-039（依赖 034）→ 040 → 041（依赖 024/030）→ 042（依赖 016/033）
TASK-043（依赖 030/031 同文件顺序）
TASK-044（门：001 项3 等价）→ 045（门：044+001）→ 046（门：001 项2）→ 047（门：001 项6+040）→ 048（门：001 项7+026）
```

---

## 2. Benchmark 方案（ARCH-014 执行口径）

### 2.1 目录与依赖

```
benchmark/
├── Project.toml        # [deps] BenchmarkTools, JSON, Dates, LinearAlgebra, Statistics, StaticArrays,
│                       #        MarsData（path=".."）；载体重依赖经 LOAD_PATH 回退（与包一致）
├── common.jl           # 合成数据生成器（STATIC 切片/c6/SWEA/SWIA 网格/文件名列表/绘图 data_dict）
│                       # + 装载辅助（MarsData.load_module/@load）
├── bench_01_loader.jl … bench_08_fullday.jl   # 8 项基准脚本
├── golden_snapshot.jl  # 纯函数/合成数据数值快照 → results/baseline_*.json
└── results/            # baseline_*.json（入库，作为全项目数值回归基准）+ 报告 md（06/07 引用）
```

- **不修改包级 `Project.toml`**（红线 §9.9）；benchmark 环境独立。
- `benchmark/results/*.json` 是**版本化回归基准**，任何数值漂移必须在 PHASE 7 说明原因。

### 2.2 方法口径（R2）

- 同机同数据、同 Julia 会话配置；每项 `@benchmark` 采样 `minimum` 与 `median` 双记录，注明 `samples/evals`。
- 合成数据优先（可复现）；真实数据基准 opt-in：跑前记录数据文件路径、大小与哈希（SHA-256）于 06。
- CI 不跑 benchmark（时长原因）；`golden_snapshot.jl` 的一致性对比（快照 vs 当前）设计为**秒级**，可进 CI。
- 任何性能改动前后必须成对出结果（同脚本、同输入）。

### 2.3 八项基准清单

| # | 脚本 | 项目 | 输入 | 判据/用途 |
| --- | --- | --- | --- | --- |
| 1 | bench_01_loader.jl | load_mag_l2 / MGS load_mag / load_kp 文本读取 | 真实单文件（opt-in） | 基线；TASK-005/006/012 前后对比 |
| 2 | bench_02_static.jl | STA_count2df_all / STA_count3df / STA_count2eflux_all | 合成 c6/d1 字典 | 基线；TASK-047 门证据 |
| 3 | bench_03_sta_v4d.jl | **sta_v_4d vs sta_v_4d_new**：等价网格对比 + 计时 | 合成切片 + 真实切片（opt-in） | 等价 rel ≤ 1e-9 = TASK-045 门；不等价 → 保留双版并上报 |
| 4 | bench_04_c6.jl | static_c6_mass_mean / static_c6_energy_mean | 合成一日 c6 | 基线；TASK-031 前后对比 |
| 5 | bench_05_findfile.jl | find_file_of_data 索引化前后 | 1000 文件名合成列表 | 命中一致 + 计时；TASK-013 证据 |
| 6 | bench_06_plot.jl | plot_module 合成 | 合成 data_dict（固定 12 面板） | 基线；TASK-040/041/048 前后对比，**不得慢于基线 110%** |
| 7 | bench_07_trace.jl | **磁力线追踪 Euler vs RK4 vs adaptive** | gh_gao 模型、固定起点、step=0.5、max_trace=30000 | 终点偏差 + 耗时表 = C1 决策数据（交人类，TASK-021 只加 kwarg 不改默认） |
| 8 | bench_08_fullday.jl | load_MAVEN_data 一日全产品 | 真实数据（opt-in） | 基线；TASK-013 索引化前后对比 |

### 2.4 Golden 快照清单（S0a/S0b，入库 JSON）

| 快照 | 内容 | 环境要求 |
| --- | --- | --- |
| baseline_marscommon.json | 球↔笛卡尔往返、能量↔速度、eflux→PSD（两版）、bowshock/magnetopause 网格、Bpc2sphere、Vandermonde/polynomial_fit | 无 |
| baseline_static.json | 合成切片：STA_count2eflux/STA_eflux2df/sta_v_4d/sta_v_4d_new/STA_count3df/sta_v_1d | 无 |
| baseline_swia_swea.json | 合成网格：n1d、n_3d、j_3d（v_3d 当前有 C5 bug，只快照其异常行为并注明，TASK-019 修复后以 n_3d 一致性为准） | 无 |
| baseline_coldplasma.json | set_particles + Dispersion_Relation/DR_wave_vector/carculate_minimum_energy 参数网格 | 无 |
| baseline_igrf.json | IGRF_pc 网格、trace_mag_line（Euler）终点、get_mag_line_s 输出 | Windows + DLL（仓库内） |
| baseline_loader.json | load_mag_l2/load_kp/load_cdf（单文件）输出摘要（键集 + 形状 + 抽样值） | 真实数据 opt-in（TASK-008） |

**快照时机**：`baseline_*`（合成类）在 TASK-001 一次性生成；`baseline_loader/igrf`（真实数据/DLL 类）在 TASK-008 生成——两者均早于任何科学改动（TASK-018+），故可作为 R4 的"改动前"基准。

---

## 3. Task 目录

### S0a：基线基建

#### TASK-001 — benchmark 基建 + 合成基线 + 纯函数 golden 快照
- **对应 ARCH ID**：ARCH-014
- **Objective**：建立 benchmark 目录、8 项基准脚本骨架与合成数据生成器；生成全部合成类 golden 快照。
- **修改文件**：`benchmark/Project.toml`、`benchmark/common.jl`、`benchmark/bench_01…08.jl`、`benchmark/golden_snapshot.jl`（全部新增）。
- **修改函数**：新增（`gen_static_slice`、`gen_c6_day`、`gen_swea_spec`、`gen_swia_coarse`、`gen_filename_list`、`gen_plot_datadict` 等生成器）。
- **当前行为**：全仓无 benchmark、无 golden 数据（AR-21）。
- **目标行为**：`julia --project=benchmark benchmark/golden_snapshot.jl` 生成 §2.4 合成类快照；8 项脚本中 2/3/4/5/6/7 可直接运行（1/8 为 opt-in，标注"待 TASK-008 后运行"）。
- **依赖任务**：无。
- **风险**：低。benchmark 独立环境不动包；合成数据形状必须与真实契约一致（以 03 附录 A 为准），否则快照失去回归意义。
- **预期收益**：R2/R4 的基准底座；后续每个任务的验证成本大幅下降。
- **涉及科学计算**：是（快照生成调用既有科学函数，不新增算法）。
- **涉及数值结果**：是（快照本身即基线）。
- **测试要求**：快照 JSON 可重复生成（两次运行逐位一致）；形状断言测试（生成器输出与附录 A 契约一致）。
- **Benchmark 要求**：本任务即基准基建；产出 §2.3 表内可运行项的首份结果并写入 `benchmark/results/baseline_report.md`。
- **文档要求**：06 记录目录结构与快照清单。
- **建议执行人**：DeepSeek V4 Flash。

### S1：P0 修正包（ARCH-007/ARCH-001）

#### TASK-002 — 删除三份坏死 calculate_mag/caculate_mag
- **对应 ARCH ID**：ARCH-007（AR-28/B1）
- **Objective**：删除调用必崩的坏死函数。
- **修改文件**：`MAVEN_data/MAVEN_load.jl`（923-932）、`TW_data/TW_load.jl`（128-137）、`MGS_data/MGS_load.jl`（112-121）。
- **修改函数**：删除 `calculate_mag` ×2、`caculate_mag` ×1（含 docstring）。
- **当前行为**：三份函数均引用未初始化全局 `data`，调用必 `UndefVarError`；docstring 已自曝。
- **目标行为**：函数不存在；全仓 grep 无引用残留（确认无调用方后删除；若有调用方，该调用方必然从未成功运行过，一并在 06 记录）。
- **依赖任务**：无。
- **风险**：低（若存在引用，删后报 `UndefVarError` 的位置会提前到调用点——这正是期望的诊断行为）。
- **预期收益**：消除 3 个坏 API 名与误导性实现。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：grep 无残留引用；`@test !isdefined` 式断言（通过 `load_module` 后检查）；runtests 绿。
- **Benchmark 要求**：无（非性能任务）。
- **文档要求**：06 记录删除清单；PHASE 8 写入 CHANGELOG。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-003 — STA_count2eflux/STA_eflux2df 默认参数修复
- **对应 ARCH ID**：ARCH-007（AR-12）
- **Objective**：消除默认参数 `m_int=m_int` 的 UndefVarError。
- **修改文件**：`MAVEN_data/MAVEN_STATIC.jl`（403、439）。
- **修改函数**：`STA_count2eflux`、`STA_eflux2df`。
- **当前行为**：默认值引用模块内不存在的全局 `m_int`，无参调用必崩（AR-12）。
- **目标行为**：签名改为 `STA_count2eflux(dat; m_int::Real=16)`、`STA_eflux2df(dat; m_int::Real=16)`；docstring 注明"必须按离子种类显式传值（H⁺=1、O⁺=16 等，见 ion_mass_range）"；`STA_count2eflux` 注明 m_int 当前未参与计算（保留参数）。
- **依赖任务**：无。
- **风险**：低。默认 16 与 sta_v_4d 的 O⁺ 默认一致；此前无参调用从未成功过，不存在行为回退。
- **预期收益**：两个公开函数首次可无参调用；为后续等价测试铺路。
- **涉及科学计算**：是（df 换算函数）。
- **涉及数值结果**：是。
- **测试要求**：默认调用有定义且与显式 `m_int=16` 逐位一致；合成切片输入输出形状断言；runtests 绿。
- **Benchmark 要求**：无（非性能任务）。
- **文档要求**：06 记录；PHASE 8 同步 api.md。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-004 — get_mag_line_s 键不一致修复
- **对应 ARCH ID**：ARCH-007（AR-8/C3）
- **Objective**：消除 `"B"` vs `:B` 的 KeyError。
- **修改文件**：`Magnetic_Model/IGRF_calculate.jl`（705-718）。
- **修改函数**：`get_mag_line_s`。
- **当前行为**：读字符串键 `data["B"]`，而 `trace_mag_line` 产出 Symbol 键 `:B` → KeyError（C3）。
- **目标行为**：优先 `get(data, :B, nothing)`，缺失时回退 `data["B"]`（兼容历史字符串键输入）；docstring 更新。
- **依赖任务**：无。
- **风险**：低（确定性 bug）。
- **预期收益**：磁力线结果字典可全链路使用。
- **涉及科学计算**：否（键访问修复）。
- **涉及数值结果**：否（输出值不变）。
- **测试要求**：`trace_mag_line` 输出直接过 `get_mag_line_s` 不抛错且 `:S/:alt/:B_total` 长度一致；字符串键输入兼容测试。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-005 — load_mag_l2 表头定位稳健化
- **对应 ARCH ID**：ARCH-007（A8）
- **Objective**：表头 END 行定位不再依赖"前 300 行内必有 END"。
- **修改文件**：`MAVEN_data/MAVEN_load.jl`（320）。
- **修改函数**：`load_mag_l2`。
- **当前行为**：`maximum(findall(line -> startswith(line, "END"), lines[1:300]))`——前 300 行无 END 时对空集取 maximum 报错；MGS 版已用 `findlast`。
- **目标行为**：`findlast(line -> startswith(line, "END"), lines[1:min(300, nums)])`；未找到（`nothing`）时抛含文件名的明确错误。
- **依赖任务**：TASK-002（同文件顺序）。
- **风险**：低。
- **预期收益**：格式变化/长表头文件不再脆弱失败。
- **涉及科学计算**：否（解析逻辑不变）。
- **涉及数值结果**：否。
- **测试要求**：fixtures 短样本（含 >300 行表头构造）通过；缺 END 时错误信息含文件名断言。
- **Benchmark 要求**：无（若有意对比 findlast 与旧实现，可附 bench_01 前后数据，非必须）。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-006 — 读取错误可见化：@warn + error_report
- **对应 ARCH ID**：ARCH-007（AR-15）
- **Objective**：错误从静默 println 变为可聚合、可审计。
- **修改文件**：`MAVEN_data/MAVEN_load.jl`（124-141、241-247）。
- **修改函数**：`load_MAVEN_data`、`load_cdf`。
- **当前行为**：`load_cdf` catch 后 `println` 吞错；`load_MAVEN_data` 单模型失败只给 `flag=false`，无聚合（AR-15）。
- **目标行为**：`load_cdf` catch 分支改 `@warn`（保留 `flag=false` 返回）；`load_MAVEN_data(date; model_index=[], show_filename=false, error_report::Vector{String}=String[])`——每次失败（file_flag=false 或子 loader 抛错）追加 `"<model>: <原因>"`；默认不传行为不变。
- **依赖任务**：TASK-005（同文件顺序）。
- **风险**：低。新增 kwarg 无破坏；@warn 可能让批量脚本日志变多——可接受（这是目的）。
- **预期收益**：批处理错误可审计（AR-15）。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：模拟缺失模型 → error_report 非空、flag=false、@warn 触发；正常路径 error_report 保持空。
- **Benchmark 要求**：无（若实现引入开销，用 bench_08 对比证明 <1%）。
- **文档要求**：06 记录；PHASE 8 api.md/data_reading.md。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-007 — filename_lists 惰性化（A1 修复）
- **对应 ARCH ID**：ARCH-001
- **Objective**：fresh clone 上 `load_module(:MAVEN_load)` 不再崩溃。
- **修改文件**：`MAVEN_data/MAVEN_load.jl`（1460-1462；内部使用者 71-101 相关行）。
- **修改函数**：新增 `filename_list()`；`file_list`、`find_file_of_data` 改走访问器。
- **当前行为**：模块加载期无条件 `open(filename_lists.json)`，文件缺失（gitignored、由 Python scan 生成）即抛错（A1）。
- **目标行为**：加载期不再打开该文件；`filename_list() = isfile(Paths.index_path()) ? JSON.parse(read(...)) : Dict{String,Any}()`（与 `MarsData.load_index` 同模式）；内部不再有全局 `filename_list` 绑定。
- **依赖任务**：TASK-006（同文件顺序）。
- **风险**：低。行为差异仅在"文件缺失"场景（旧：崩溃；新：空字典 → 各模型 file_flag=false 正常容错）。
- **预期收益**：解除全仓最大 testability 阻塞（AR-25）；S0b 快照与 CI 的前提。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：无 filename_lists.json 环境冒烟装载 + `filename_list()` 返回空；有文件时与旧行为一致（文件内容逐键相等）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 data_reading.md 说明惰性行为。
- **建议执行人**：GLM-5（涉及模块加载路径，需谨慎）。

### S0b：真实数据基线

#### TASK-008 — 真实数据 golden 快照 + loader 基准执行
- **对应 ARCH ID**：ARCH-014
- **Objective**：在任何科学改动前，取得真实数据数值基线（R4 的"改动前"证据）。
- **修改文件**：`benchmark/results/baseline_igrf.json`、`baseline_loader.json`（新增）；`benchmark/bench_01/08` 结果。
- **修改函数**：无源码改动（仅运行）。
- **当前行为**：无真实数据基线。
- **目标行为**：E:/MAVEN（及 E:/MGS、E:/Tianwen-1 若可得）存在时：生成 §2.4 两个快照 + 跑 bench_01/08；记录文件路径/哈希。数据不可得时：在 06 明确记录"真实数据基线缺失，以下任务以合成基线为准"，不阻塞后续任务。
- **依赖任务**：TASK-007（无 A1 阻塞）、TASK-001。
- **风险**：中——本地数据不可用则该任务部分空转；缓解：opt-in 设计，缺失不阻塞（03 风险 #3）。
- **预期收益**：真实数据回归能力。
- **涉及科学计算**：是（运行既有函数）。
- **涉及数值结果**：是（快照）。
- **测试要求**：快照可重复（同文件两次运行一致）。
- **Benchmark 要求**：输出 bench_01/08 首份基线（写入 baseline_report.md）。
- **文档要求**：06 记录数据来源/哈希/缺失说明。
- **建议执行人**：DeepSeek V4 Flash。

### S2：路径统一（ARCH-005）

#### TASK-009 — SP_load 路径化与去副作用
- **对应 ARCH ID**：ARCH-005（A3）
- **Objective**：SP_load 走 Paths，移除加载期 INI 读取与 println。
- **修改文件**：`support_data/support_data_load.jl`。
- **修改函数**：模块级初始化（12-14 行）与 `load_omni2_data`/`load_drivers_merge_data` 内部路径拼装。
- **当前行为**：加载期 `read(Inifile(), download_data/MAVEN_download_config.ini)`（文件可能不存在）+ `println` 副作用（A3）。
- **目标行为**：删除加载期 INI 读取与 println；自包含 include paths.jl；`root_path()` 惰性 = `Paths.maven_data_root()`；两个 load 函数内部拼 `support_datas/...`；docstring 注明依赖。
- **依赖任务**：无。
- **风险**：低。TOML 优先/INI 回退/默认值兜底由 Paths 已实现；行为差异仅在"配置缺失"场景从崩溃变为默认值。
- **预期收益**：模块可无副作用加载（AR-2/25）。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：无数据环境可装载；有 INI/TOML 环境读取输出与改动前一致（对比测试）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-010 — TW/MGS 根路径 Paths 化
- **对应 ARCH ID**：ARCH-005（A2）
- **Objective**：消除 `E:/Tianwen-1/`、`E:/MGS/` 硬编码。
- **修改文件**：`TW_data/TW_load.jl`（7）、`TW_data/TW_MINPA.jl`（10）、`MGS_data/MGS_load.jl`（6）。
- **修改函数**：模块级 root_path 初始化（→ 惰性函数或 `Paths.tw_data_root()/mgs_data_root()`）。
- **当前行为**：三文件硬编码 Windows 绝对路径，绕过 Paths（A2）。
- **目标行为**：自包含 include paths.jl 后经 Paths 解析；`read_list`/`build_file_list` 等内部使用者改走同一来源。
- **依赖任务**：TASK-002（TW_load/MGS_load 同文件顺序）。
- **风险**：低。默认值与旧硬编码一致（E:/Tianwen-1/、E:/MGS/），TOML 可覆盖。
- **预期收益**：换机可用；与 MAVEN_load 配置体系一致。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：无数据环境可装载；mock 根目录（临时目录+样本文件）下 read_list 结果正确。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-011 — Call_fortran_dll 路径解析
- **对应 ARCH ID**：ARCH-005（A6）
- **Objective**：DLL 定位不再依赖 D:/ 硬编码与 CWD。
- **修改文件**：`call_fortran_dll.jl`（42、57、98、132 行相关 ccall 路径）；`common/paths.jl`（新增可选键读取函数）。
- **修改函数**：`cold_plasma_linear_growth`、`Bspline_db1ink`、`Bspline_db1var`（路径来源）；`Paths.fortran_dll_dir()`（新增）。
- **当前行为**：`linear_growth_rate.dll` 硬编码 `D:/CODE/Package_for_Julia/`（gitignored）；`Bspline.dll` 相对路径依赖 CWD（A6）。
- **目标行为**：`Paths.fortran_dll_dir()` 解析顺序 = settings.toml 可选键 `paths.fortran_dll_dir`（只读，不改 example.toml）→ 仓库根 → 旧硬编码路径（@warn 一次）；`Bspline.dll` 先仓库根再 CWD；全部缺失时调用抛含指引的清晰错误（列出尝试过的路径）。
- **依赖任务**：无。
- **风险**：低。纯路径解析；ccall 符号不变。
- **预期收益**：换机可诊断；消除机器特定路径（A6）。
- **涉及科学计算**：是（DLL 数值例程）。
- **涉及数值结果**：否（仅定位变化；有 DLL 环境数值不变）。
- **测试要求**：无 DLL 环境调用给出指引性错误；有 DLL 环境（opt-in）数值与改动前一致。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 在 README/文档注明 DLL 放置方式。
- **建议执行人**：Qwen 3.8 Flash。

### S3：装载注册表（ARCH-004）

#### TASK-012 — 显式 LOADER_FUNCS 函数表（去 eval）
- **对应 ARCH ID**：ARCH-004（A9/AR-14）
- **Objective**：JSON 字符串不再经 `eval(Meta.parse(...))` 变代码。
- **修改文件**：`MAVEN_data/MAVEN_load.jl`（1455-1459 及模块级新增函数表）。
- **修改函数**：模块级 `LOADER_FUNCS` 常量；加载期 `read_models` 构建逻辑。
- **当前行为**：`read_models[key] = (value[3], eval(Meta.parse(value[4])))`——JSON 即代码入口（A9）。
- **目标行为**：代码内 `const LOADER_FUNCS = Dict{String,Function}("load_cdf"=>load_cdf, "load_mag_l2"=>load_mag_l2, "load_kp"=>load_kp, ...)`（覆盖 MAVEN_data_format.json 全部 55 产品的 value[4] 字符串；**JSON 文件一字不改**）；加载期 `read_models[key] = (value[3], LOADER_FUNCS[value[4]])`；value[4] 不在表内时加载即抛清晰错误（含键与缺失函数名）。
- **依赖任务**：TASK-007（同文件顺序）。
- **风险**：中——55 个映射若有遗漏/拼写偏差，加载即失败；缓解：新增"JSON 键 ⊆ 函数表"校验测试在提交前跑通。
- **预期收益**：去除任意代码执行入口；键漂移即时暴露（AR-14）。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：全部 55 产品键与函数表一一对应（读取 JSON 校验）；golden 一日加载回归（TASK-008 快照或合成 mock）。
- **Benchmark 要求**：无（若映射构造影响加载期耗时，用加载时间对比证明 <5%）。
- **文档要求**：06 记录；PHASE 8 data_reading.md。
- **建议执行人**：GLM-5。

#### TASK-013 — 文件定位日期索引化
- **对应 ARCH ID**：ARCH-004（AR-14）
- **Objective**：find_file_of_data 从线性子串扫描变为日期索引命中（保留回退）。
- **修改文件**：`MAVEN_data/MAVEN_load.jl`（71-102）。
- **修改函数**：`find_file_of_data`、`file_list`；新增 `_file_index(model)`（每模型惰性缓存）。
- **当前行为**：每次调用对全列表线性 `occursin(yyyymmdd)`，且每次广播拼接全路径（O(N×M) 分配，AR-14）。
- **目标行为**：首次调用按正则 `\d{8}` 从文件名提取日期建 `Dict{String,Vector{String}}` 索引；命中走索引；未命中回退原 `occursin` 子串扫描（行为兼容）；路径拼接缓存复用。
- **依赖任务**：TASK-012（同文件顺序）。
- **风险**：低。回退路径保证兼容；索引提取规则（最长 8 位数字串、多段取末段）需在测试中覆盖。
- **预期收益**：多模型日加载的文件定位从 O(模型数×文件数) 降为近 O(1)（AR-14/22）。
- **涉及科学计算**：否。
- **涉及数值结果**：否（命中结果必须与旧实现一致）。
- **测试要求**：1000 文件名合成列表——索引与旧实现命中结果逐一一致（含无日期文件名、多日期段文件名、无命中回退）；golden 一日加载回归。
- **Benchmark 要求**：**bench_05**（索引化前后计时对比，必须提供）。
- **文档要求**：06 记录。
- **建议执行人**：GLM-5。

### S4：装载一致性（ARCH-003）

#### TASK-014 — MarsCommon 自包含 include
- **对应 ARCH ID**：ARCH-003（AR-3）
- **Objective**：消除 MarsCommon 对装载顺序的脆弱依赖。
- **修改文件**：`common/MarsCommon.jl`（1-2）。
- **修改函数**：模块头部（`using ..constants` → 自包含 include constants.jl）。
- **当前行为**：`using ..constants` 只有在 constants 先装入同一载体时才能解析；直接 include 到 Main 会 UndefVarError（AR-3）。
- **目标行为**：自包含 include；`include("common/MarsCommon.jl")` 直接可用；行为不变（constants 数值相同）。
- **依赖任务**：无。
- **风险**：低（constants 为纯数值，双副本无害——已在 03 §3.3 ARCH-003 论证）。
- **预期收益**：装载顺序脆弱性归零；脚本层直接 include 兼容。
- **涉及科学计算**：否（常量引用方式变化）。
- **涉及数值结果**：否。
- **测试要求**：单独 include MarsCommon 冒烟；`load_module(:MarsCommon)` 冒烟；全部下游测试绿。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-015 — validate_registry 扩展
- **对应 ARCH ID**：ARCH-003
- **Objective**：把"模块实际 include 了什么"纳入注册表自检。
- **修改文件**：`src/modules.jl`（401-429）。
- **修改函数**：`validate_registry`。
- **当前行为**：只校验键/文件/`module` 声明/deps 存在性/无环（AR-3 的两套真相不被检查）。
- **目标行为**：新增校验——(a) 文件含 `using ..X` 且 X 不在 deps → 报问题；(b) 文件自包含 include 的 X 同时又在 deps → 警告级提示（冗余）；输出区分错误与警告。
- **依赖任务**：TASK-014。
- **风险**：低。仅校验逻辑；若误报，调整正则（以 `include(.*\.jl)` 与 `using \.\.[a-zA-Z_]+` 为准）。
- **预期收益**：注册表 deps 成为可信文档（AR-3）。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：runtests 现有 validate 测试扩展（构造含 `using ..X` 无 deps 的临时模块文件触发报告）；当前注册表全绿。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：GLM-5（src/modules.jl 为红线文件，只准加校验不动机制）。

### S5：数据契约中心化（ARCH-011）

#### TASK-016 — DataKeys 模块
- **对应 ARCH ID**：ARCH-011
- **Objective**：键名契约常量中心化。
- **修改文件**：`common/data_keys.jl`（新增）；`src/MarsData.jl`（include + 绑定）；`src/modules.jl`（注册表 +`kind=:preloaded` 条目）。
- **修改函数**：新增 `module DataKeys`（EPOCH/TIME/TIME_UNIX/DATA_LOAD_FLAG/FILENAME/B_FIELD/B_TOTAL/POSITION/ENERGY/DENERGY/DF/EFLUX/DIFF_EN_FLUXES/QUAT_MSO/SC_POT/… 常量 + docstring，与 03 附录 A 一一对应）。
- **当前行为**：键名散落 20+ 文件，拼写漂移到运行时才暴露（AR-7/8）。
- **目标行为**：`MarsData.DataKeys.EPOCH === :epoch` 等；供新代码与重构触及代码引用（存量不强制改，R6）。
- **依赖任务**：TASK-015（src/modules.jl 同文件顺序）。
- **风险**：低（纯常量模块，零行为变化）。
- **预期收益**：契约单一出处；拼写漂移编译期可查。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：DataKeys 常量与附录 A 表逐项一致性测试（键名抽查断言）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 契约表入 docs。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-017 — 就地修改约定 docstring + 契约测试
- **对应 ARCH ID**：ARCH-011（AR-9）
- **Objective**：视图/就地语义成文并被测试锁定。
- **修改文件**：`MAVEN_data/MAVEN_STATIC.jl`（static_slip/STA_count2df docstring）、`common/MarsCommon.jl`（eflux_to_df! docstring）、`src/plotting.jl`（remove_0_point! docstring）。
- **修改函数**：仅 docstring 补充（`!`=原地；视图共享内存；写新键安全/写既有键污染）。
- **当前行为**：语义靠"文档提示"，无机制防御（AR-9）。
- **目标行为**：docstring 明确三约定；不改函数行为。
- **依赖任务**：TASK-016。
- **风险**：低（纯文档）。
- **预期收益**：防隐蔽联动 bug（AR-9）。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：static_slip 视图语义测试（对切片写新键不影响原数据；写既有键会污染——测试只断言"写新键安全"这条承诺）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 data_format.md。
- **建议执行人**：DeepSeek V4 Flash。

### S6：科学修正与出处注释（ARCH-008）

#### TASK-018 — SWEA n1d 删除死变量 tiny（C4）
- **对应 ARCH ID**：ARCH-008（C4/AR-18）
- **Objective**：删除笔误死变量，行为不变。
- **修改文件**：`MAVEN_data/MAVEN_SWEA.jl`（54）。
- **修改函数**：`n1d`。
- **当前行为**：`tiny = 1.0-31`（= -30.0）为笔误（疑为 1e-31），但被 `ff` 截断掩盖，变量实际未被使用（C4）。
- **目标行为**：删除该行；`ff` 截断与能量积分逐字不动；docstring 注明该修正。
- **依赖任务**：TASK-008（真实基线；无数据则以 TASK-001 合成基线为准）。
- **风险**：低（死变量删除）。
- **预期收益**：消除误导常数（AR-18 首项）。
- **涉及科学计算**：是。
- **涉及数值结果**：是（要求证明不变）。
- **测试要求**：合成能谱 n1d 改动前后逐位一致；手算期望值回归（dE·E^(-3/2) 加权解析值）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录对比结论。
- **建议执行人**：GLM-5。

#### TASK-019 — SWIA v_3d 索引维度修复（C5）
- **对应 ARCH ID**：ARCH-008（C5/AR-18）
- **Objective**：v_3d 对 coarse 数据不再 BoundsError。
- **修改文件**：`MAVEN_data/MAVEN_SWIA.jl`（358-401）。
- **修改函数**：`v_3d`。
- **当前行为**：`dat[:theta][time_ind,:,:,:]`/`dat[:domega][time_ind,:,:,:]` 用 4D 索引取 3D 数组（已确认 get_3dc! 写 `(ntime,4,48)`；get_3df! 写 4D）→ coarse 数据必 BoundsError（C5）。
- **目标行为**：theta/domega 按 `ndims` 分支：3D 输入索引 `[time_ind,:,:]` 后 `reshape(...,ntime,1,ndeflect,nenergy)`；4D 输入保持现索引；函数开头对 theta/domega/能量数组做尺寸断言并给出含实际形状的清晰报错；`diff_en_fluxes` 保持 4D 索引（实施时以断言确认）。
- **依赖任务**：TASK-008/001（基线）。
- **风险**：中——修复前该函数从未成功运行，修复即"首次产出数值"；缓解：与 n_3d/j_3d 交叉核对量级与符号。
- **预期收益**：C5 疑点修复；Pickup_ion swi 模式路径的潜在阻塞解除。
- **涉及科学计算**：是。
- **涉及数值结果**：是（首次正确输出）。
- **测试要求**：合成 coarse 网格（theta 3D）与 fine 网格（theta 4D）双输入跑通、密度为正、形状断言；真实 SWIA 一日（opt-in）v_3d 与 n_3d/j_3d 一致性核对（量级/符号），结果入 06。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；对照表（§15 C5）。
- **建议执行人**：GLM-5。

#### TASK-020 — combina_two_dir_trace 自引用修复（C2）
- **对应 ARCH ID**：ARCH-008（C2）
- **Objective**：模块内调用不再 UndefVarError。
- **修改文件**：`Magnetic_Model/IGRF_calculate.jl`（677-678）。
- **修改函数**：`combina_two_dir_trace`。
- **当前行为**：`IGRF_calculate.sphere2pc(...)`/`IGRF_calculate.Bsphere2pc(...)` 模块内自引用，to_pc=true 时 UndefVarError（C2）。
- **目标行为**：改裸名 `sphere2pc`/`Bsphere2pc` 调用；docstring 更新。
- **依赖任务**：TASK-008/001。
- **风险**：低（确定性 bug）。
- **预期收益**：双向磁力线拼接的笛卡尔输出可用。
- **涉及科学计算**：是。
- **涉及数值结果**：是（to_pc 路径首次正确）。
- **测试要求**：`to_pc=true` 调用不抛错；与 `to_pc=false` 结果逐点做球→笛卡尔变换对比（rel ≤ 1e-12）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-021 — trace_mag_line method kwarg（C1）
- **对应 ARCH ID**：ARCH-008（C1/AR-20）
- **Objective**：暴露追踪器选择，**默认保持 :euler 不变**。
- **修改文件**：`Magnetic_Model/IGRF_calculate.jl`（747-786）。
- **修改函数**：`trace_mag_line`。
- **当前行为**：硬编码两次 `mag_trace_Euler_step`（一阶，注释自认系统误差）（C1）。
- **目标行为**：新增 kwarg `method::Symbol=:euler`（`:euler`/`:rk4`/`:adaptive`）；dispatch 到既有 `mag_trace_rk4`/`mag_trace_rk4_fortran_ADAPTIVE_STEP`（签名已确认兼容：同 kwargs + maxfac/minfac/tol，仅 rk4/adaptive 传额外参数）；默认路径输出与改动前逐位一致；docstring 注明"默认 Euler 为一阶精度，改默认需科学负责人批准（03 §15 C1）"。
- **依赖任务**：TASK-001（bench_07 决策数据）、TASK-020（同文件顺序）。
- **风险**：低（默认不变）；rk4/adaptive 支路为"暴露既有代码"，需测试覆盖。
- **预期收益**：精度选择显式化；为 C1 人类决策提供接口。
- **涉及科学计算**：是。
- **涉及数值结果**：是（三支路数值对比）。
- **测试要求**：默认调用输出与改动前逐位一致；三支路同起点输出形状一致（N×6）；`:rk4/:adaptive` 可用；非法 method 报错。
- **Benchmark 要求**：**bench_07** 三法对比（终点偏差 + 耗时），数据入 06/07 供人类裁决（R5 门）。
- **文档要求**：06 记录基准数据；PHASE 8 api.md。
- **建议执行人**：GLM-5。

#### TASK-022 — SWEA shape 硬编码常数具名化（C10）
- **对应 ARCH ID**：ARCH-008（C10/AR-18）
- **Objective**：硬编码常数提取为具名常量 + 出处注释，数值不变。
- **修改文件**：`MAVEN_data/MAVEN_load.jl`（1156、1277-1420 区间）。
- **修改函数**：`carclu_SWEA_pad`、`SWEA_calc_shape_arr`（+模块级常量）。
- **当前行为**：`zeros(1,1,64)`、`indx=13:64`、`n_e=52`、df_iono 模板数组等硬编码无出处（C10）。
- **目标行为**：提取为具名常量（如 `SWEA_NCHANNELS=64`、`SWEA_PAD_INDEX=13:64`、`SWEA_NE=52`、`SWEA_DF_IONO_TEMPLATE`）并附 SPEDAS 出处注释；**数值逐位不变**。
- **依赖任务**：TASK-008/001。
- **风险**：低（纯提取）。
- **预期收益**：AR-18 合规；后续可对照 SPEDAS。
- **涉及科学计算**：是。
- **涉及数值结果**：是（要求证明不变）。
- **测试要求**：SWEA_calc_shape_arr 合成输入改动前后逐位一致。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；对照表条目。
- **建议执行人**：GLM-5（该函数稍后迁至 MAVEN_SWEA，见 TASK-030）。

#### TASK-023 — 记录类常数出处注释（C6/C7/C11/C12/C13）
- **对应 ARCH ID**：ARCH-008（AR-18）
- **Objective**：为"不改值"疑点建立出处注释与对照记录。
- **修改文件**：`TW_data/TW_MINPA.jl`（111-114、441-450）、`MAVEN_data/MAVEN_SWIA.jl`（385、430）、`MAVEN_data/MAVEN_load.jl`（948-969、260）。
- **修改函数**：`load_mod1`/`v3d`、`v_3d`/`n_1d`、`mean_SWEA_pad_pa`、`load_cdf`（仅注释）。
- **当前行为**：C6 denergy 弃用改 `0.2/2`；C7 nvy 负号 + 整体反号；C11 系数 7.224566339926571e-7 与 8.8；C12 NaN 互填逻辑；C13 RV 判定 `flags & 1 == 1`——均无出处注释。
- **目标行为**：每处加"疑点 + 出处 + 待验证"注释块（**不改任何数值/逻辑**）；06 记录《常数出处与 SPEDAS 对照表》条目（03 §15 的 C6/C7/C11/C12/C13 行）。
- **依赖任务**：无。
- **风险**：低（纯注释）。
- **预期收益**：AR-18 合规；后续人类裁决有依据。
- **涉及科学计算**：否（不加注释的数值影响）。
- **涉及数值结果**：否。
- **测试要求**：注释存在性检查（grep 关键词断言）——弱测试，重点是 06 记录。
- **Benchmark 要求**：无。
- **文档要求**：06 对照表条目（必做）。
- **建议执行人**：DeepSeek V4 Flash（文档型）。

### S7：状态显式化（ARCH-009）

#### TASK-024 — Cold_Plasma PlasmaState 重构
- **对应 ARCH ID**：ARCH-009（AR-4/C8）
- **Objective**：色散关系状态显式化，旧 API 全兼容。
- **修改文件**：`models/Cold_Plasma_Dispersion_Relation.jl`。
- **修改函数**：`set_particles`、`Dispersion_Relation`；新增 `make_particles`、`PlasmaState` 类型别名、`calculate_minimum_energy` 别名（旧名 `carculate_minimum_energy` 保留转发）。
- **当前行为**：`set_particles` 写模块全局 Nparticles/Ω_n/Π_2；`Dispersion_Relation` 隐式读全局，未初始化时静默使用未定义状态（AR-4）。
- **目标行为**（对 03 的执行细化，目标不变）：`PlasmaState = NamedTuple{(:Nparticles,:Ω_n,:Π_2)}`；新增纯函数 `make_particles(;ion_rate,ion_mass)::PlasmaState`；`set_particles(...)` 保留写模块 Ref 的副作用**并**返回 PlasmaState（旧脚本零改动可用）；新重载 `Dispersion_Relation(θ,freq,Πe,Ωe,state::PlasmaState)`；旧签名读 Ref，未初始化时抛含指引错误；`carculate_minimum_energy` 增加 `state` 可选参数（默认走旧路径）；新增 `calculate_minimum_energy` 转发。
- **依赖任务**：无。
- **风险**：低（纯状态搬运，公式逐字不动）。
- **预期收益**：可并行/可隔离（AR-27）；误用即时暴露。
- **涉及科学计算**：是。
- **涉及数值结果**：是（要求新旧一致）。
- **测试要求**：新旧路径参数网格逐点 rel ≤ 1e-12；未初始化旧路径给出清晰错误；Threads.@threads 两线程各用独立 state 结果一致。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 api.md。
- **建议执行人**：GLM-5。

#### TASK-025 — load_kp kp_columns kwarg
- **对应 ARCH ID**：ARCH-009（C15）
- **Objective**：KP 列映射显式化，全局行为保持兼容。
- **修改文件**：`MAVEN_data/MAVEN_load.jl`（183-190、403、1454）。
- **修改函数**：`load_kp`、`change_kp_read_data`；模块初始化（1454 → Ref 初始化）。
- **当前行为**：`change_kp_read_data` 在加载期全局重设 `kp_dict`；`load_kp` 隐式读全局（C15）。
- **目标行为**：`load_kp(filename; pc2ss_Matrix_load=false, str_model=false, kp_columns=kp_dict)`（默认行为不变）；`change_kp_read_data` 保留（写模块 Ref，标记弃用倾向）；加载期 1454 行改为初始化 Ref。
- **依赖任务**：TASK-013（同文件顺序）。
- **风险**：低（默认=旧行为）。
- **预期收益**：显式列映射，多脚本同进程不再互相污染（C15）。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：默认调用与改动前输出一致；自定义 kp_columns 生效；change_kp_read_data 兼容路径测试。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 api.md。
- **建议执行人**：GLM-5。

#### TASK-026 — IGRF bcompress 显式变体
- **对应 ARCH ID**：ARCH-009（AR-4）
- **Objective**：并行安全路径 + 旧全局行为不变。
- **修改文件**：`Magnetic_Model/IGRF_calculate.jl`（258-269、293-320、630-787）。
- **修改函数**：`IGRF_fortran`、`RK4_Trace_fortran`、`trace_mag_line`（+各 mag_trace_*）。
- **当前行为**：`B_compress` 模块全局，ccall 每次 `Array{Float64}(B_compress)` 拷贝进参（非线程安全，AR-4/AR-23）。
- **目标行为**：各函数新增 kwarg `bcompress::Vector{Float64}=B_compress`（默认读全局=旧行为；类型标注保持热路径稳定）；`set_B_compress` 保留（标记非线程安全）；新代码/并行代码显式传参。
- **依赖任务**：TASK-021（同文件顺序）。
- **风险**：低（默认不变）。
- **预期收益**：并行追踪安全；为 AR-23 评估铺路。
- **涉及科学计算**：是。
- **涉及数值结果**：是。
- **测试要求**：默认调用与改动前逐位一致；显式 bcompress 生效（改值后输出变化可验证）；两线程不同 bcompress 互不污染。
- **Benchmark 要求**：无（kwarg 默认路径与旧全局查找同开销；如需证明用 bench_07 前后对比）。
- **文档要求**：06 记录；PHASE 8 api.md。
- **建议执行人**：GLM-5。

### S8：去重与权威实现（ARCH-006）

#### TASK-027 — 签名/单位审计表（门禁任务）
- **对应 ARCH ID**：ARCH-006
- **Objective**：先审计后转发——为 TASK-028…035 提供权威依据。
- **修改文件**：无源码改动；产出审计表（写入 06 专属节）。
- **修改函数**：对 Bpc2sphere/Bsphere2pc、bowshock/magnetopause/bowshock_zero、slice2d_cal_rot（4 份：function_coordinate:28、MAVEN_plot:321/561、TW_MINPA:558）、static_c6_*、cyclone_*/cyclotron_*、TimeFormat、load_quat、Vandermonde/polynomial_fit/vector_angle/logticks/interpolate_x_ticks——逐对列出全部调用点、输入单位、返回单位、差异。
- **当前行为**：多份实现并存，单位/命名不一致（AR-6）。
- **目标行为**：审计表定稿（含"已确认：Single_Particle_Orbit.cyclotron_radius 为 SI 输入（B:T、v:m/s），与 calculate_models（B:nT、ek:eV）签名不同 → 不转发，保留并加交叉引用"等结论）；后续任务照表执行。
- **依赖任务**：无（门禁 TASK-028…035）。
- **风险**：低（只读审计）。
- **预期收益**：防止转发破坏调用点（AR-6 风险清零）。
- **涉及科学计算**：否（审计）。
- **涉及数值结果**：否。
- **测试要求**：无（审计质量以 06 表格完整度为验收）。
- **Benchmark 要求**：无。
- **文档要求**：06 审计节（必做）。
- **建议执行人**：GLM-5（主）+ V4 Flash（复核）。

#### TASK-028 — Bpc2sphere/Bsphere2pc 收敛 MarsCommon
- **对应 ARCH ID**：ARCH-006（B3）
- **Objective**：坐标变换单实现。
- **修改文件**：`common/MarsCommon.jl`（新增）、`MAVEN_data/MAVEN_load.jl`（889-904）、`Magnetic_Model/IGRF_calculate.jl`（121 附近）。
- **修改函数**：新增 `MarsCommon.Bpc2sphere(x,y,z,bx,by,bz)`、`Bsphere2pc`（带 `::Real` 标注）；MAVEN_load/IGRF 副本删除改转发别名。
- **当前行为**：两份实现（MAVEN_load 无标注 vs IGRF 带标注）（B3）。
- **目标行为**：仅 MarsCommon 一份；两处对外名保留（转发）。
- **依赖任务**：TASK-027、TASK-014。
- **风险**：低。
- **预期收益**：单一实现（科学一致性）。
- **涉及科学计算**：是。
- **涉及数值结果**：是。
- **测试要求**：转发前后合成输入逐位一致；球↔笛卡尔往返 rel ≤ 1e-12。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-029 — bowshock/magnetopause 收敛 MarsCommon
- **对应 ARCH ID**：ARCH-006（B4）
- **Objective**：Edberg 2008 边界模型单实现。
- **修改文件**：`common/MarsCommon.jl`（新增）、`MAVEN_data/MAVEN_plot.jl`（1514、1541）。
- **修改函数**：新增 `MarsCommon.bowshock(x)`/`magnetopause(x)`（R_Mars 归一化输入；`temp<0` 返回 `NaN`）+ `bowshock_km`（km 输入显式版）；MAVEN_plot 版改转发。
- **当前行为**：三份同公式（head.jl 返回 NaN32、MAVEN_plot 返回 NaN64、function_coordinate.bowshock_zero 返回 0.0）（B4）。
- **目标行为**：权威 = MarsCommon（返回 NaN）；MAVEN_plot 转发（NaN 类型差异无绘图影响）；head.jl 副本随 TASK-036 删除/转发；bowshock_zero 随 TASK-034 改"MarsCommon.bowshock + 钳 0"包装（**保持返回 0.0 语义**）。
- **依赖任务**：TASK-027、TASK-014。
- **风险**：低。注意 NaN32/NaN64 差异：等价测试用 `isnan` 判定而非 `==`。
- **预期收益**：单一实现；调用点行为不变。
- **涉及科学计算**：是（模型公式）。
- **涉及数值结果**：是。
- **测试要求**：网格对比（isnan 感知）与各原实现一致（0.0/NaN 语义按各包装分别断言）；MAVEN_plot 绘图调用点回归。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 data_format.md 单位表。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-030 — SWEA shape 函数迁至 MAVEN_SWEA
- **对应 ARCH ID**：ARCH-006（AR-17）
- **Objective**：MAVEN_load 瘦身；仪器函数归位。
- **修改文件**：`MAVEN_data/MAVEN_SWEA.jl`（迁入）、`MAVEN_data/MAVEN_load.jl`（迁出 + 转发）。
- **修改函数**：迁入 `mean_SWEA_pad_pa`、`carclu_SWEA_pad`（+新增 `calculate_SWEA_pad` 别名）、`SWEA_calc_shape_arr`、`SWEA_calc_shape_arr_mars_towrads`；MAVEN_load 保留同名转发（对外 API 不变）；SWEA 侧新增所需 `using Statistics` 等（按现有文件头核对）。
- **当前行为**：四函数在 MAVEN_load 内（AR-17）。
- **目标行为**：实现归 MAVEN_SWEA；`MAVEN_load.mean_SWEA_pad_pa === MAVEN_SWEA.mean_SWEA_pad_pa` 语义等价。
- **依赖任务**：TASK-027、TASK-022（具名常量随迁）、TASK-018（同模块顺序）。
- **风险**：中——函数依赖 MAVEN_load 内其他助手（如 kp 相关）；实施时先审计依赖闭包（审计表已含）。
- **预期收益**：读取器瘦身；测试可聚焦（AR-17）。
- **涉及科学计算**：是。
- **涉及数值结果**：是。
- **测试要求**：迁移前后合成输入逐位一致；真实 SWEA（opt-in）回归；转发别名调用测试。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 api.md 归属更新。
- **建议执行人**：GLM-5。

#### TASK-031 — static_c6 旧副本转发 + cyclone 转发
- **对应 ARCH ID**：ARCH-006（B2/B8）
- **Objective**：MAVEN_load 内旧副本与 cyclone 系列转为权威转发。
- **修改文件**：`MAVEN_data/MAVEN_load.jl`（989-1056、1057-1120、1229-1260）。
- **修改函数**：`static_c6_mass_mean`、`static_c6_energy_mean`、`cyclone_frequency`、`cyclone_R`。
- **当前行为**：MAVEN_load 内旧 static_c6 副本（无 :df 分支）与 MAVEN_STATIC 新版并存；cyclone_* 与 calculate_models.cyclotron_* 并存（B2/B8）。
- **目标行为**：MAVEN_load 四个函数改转发（static_c6 → MAVEN_STATIC；cyclone_* → calculate_models.cyclotron_*，参数映射按审计表：cyclone_frequency(B)≈cyclotron_frequency(B;nM=…,nQ=-1) 等，**单位/默认值差异以审计表为准并在 docstring 注明**）；Single_Particle_Orbit 的 SI 版 cyclotron_radius **保留**（TASK-027 结论），加交叉引用 docstring。
- **依赖任务**：TASK-027、TASK-025（同文件顺序）。
- **风险**：中——static_c6 转发后行为为"旧输入超集"（新增 :df 输出），需确认下游无形状依赖；cyclone 单位差异必须在审计后映射，否则禁止转发（退化为保留+注释）。
- **预期收益**：单一权威实现。
- **涉及科学计算**：是。
- **涉及数值结果**：是。
- **测试要求**：转发前后合成输入逐位一致（旧签名调用）；MAVEN_STATIC 版带 :df 输入新分支测试；bench_04 前后对比。
- **Benchmark 要求**：**bench_04**（static_c6 转发前后，证明无退化）。
- **文档要求**：06 记录；PHASE 8 api.md。
- **建议执行人**：GLM-5。

#### TASK-032 — 数学工具迁至 MarsCommon
- **对应 ARCH ID**：ARCH-006（B9）
- **Objective**：绘图模块不再兼任数学库。
- **修改文件**：`common/MarsCommon.jl`（新增）、`MAVEN_data/MAVEN_plot.jl`（1346-1497）。
- **修改函数**：迁入 `Vandermonde`、`polynomial_fit`、`vector_angle`、`logticks`、`interpolate_x_ticks`（logticks/interpolate_x_ticks 依赖 Makie rich → 留在 MAVEN_plot，仅迁前三者 + 转发面）；MAVEN_plot 保留转发别名。
- **当前行为**：通用数学工具在绘图模块（B9）。
- **目标行为**：纯数学三函数归 MarsCommon；`logticks`/`interpolate_x_ticks`（Makie 相关）保留 MAVEN_plot 原地；MAVEN_plot 对外名全部不变（转发）。
- **依赖任务**：TASK-027、TASK-014。
- **风险**：低。注意 `polynomial_fit` 内部 `V \ filtered_y` 需 `using LinearAlgebra`（MarsCommon 无此依赖时按需加 stdlib）。
- **预期收益**：分层清晰（AR-10 类）。
- **涉及科学计算**：否（纯数学工具）。
- **涉及数值结果**：是（要求一致）。
- **测试要求**：合成输入逐位一致；polynomial_fit 已知系数恢复测试。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 api.md。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-033 — FunctionCoordinate 模块化
- **对应 ARCH ID**：ARCH-006（B5）
- **Objective**：function_coordinate.jl 包化注册；TW_MINPA 私有副本删除。
- **修改文件**：`common/function_coordinate.jl`（包裹 `module FunctionCoordinate`）、`TW_data/TW_MINPA.jl`（558 附近私有副本）、`src/modules.jl`（注册表条目）。
- **修改函数**：`slice2d_cal_rot`、`pa_*`、`MINPA_*`、`bowshock_zero`（模块化）；TW_MINPA 内副本删除改自包含 include FunctionCoordinate。
- **当前行为**：脚本型（无 module）；TW_MINPA 含私有 slice2d_cal_rot 副本（B5）。
- **目标行为**：注册模块（deps=[constants,MarsCommon]）；`bowshock_zero` = MarsCommon.bowshock + 钳 0 包装（TASK-029 后）；TW_MINPA 引用模块版。
- **依赖任务**：TASK-027、TASK-029、TASK-015（注册表）。
- **风险**：低。注意 MAVEN_plot 内两处 slice2d_cal_rot（321/561）不在本任务范围（绘图内部使用，审计表登记，不强行统一）。
- **预期收益**：可 import 单测；私有副本消除。
- **涉及科学计算**：是（坐标函数）。
- **涉及数值结果**：是。
- **测试要求**：模块化前后合成输入逐位一致；MINPA 往返自洽测试（norm(sphere2xyz(xyz2sphere(p))-p)≈0，文件内既有注释测试转正）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-034 — TimeFormat 合并 + load_quat 交叉引用
- **对应 ARCH ID**：ARCH-006（B6/B7）
- **Objective**：单一 TimeFormat（kwarg 区分格式）；load_quat 同名不同义成文。
- **修改文件**：`src/plotting.jl`（26-33）、`models/Single_Particle_Orbit.jl`（30-36）、`MAVEN_data/MAVEN_load.jl`（794 附近 docstring）、`MAVEN_data/MAVEN_SWEA.jl`（90-106 docstring）。
- **修改函数**：`MarsData.TimeFormat(time1,time2; format=:full)`（:full=HH:MM:SS.mmm、:mmss=MM:SS.mmm）；Single_Particle_Orbit.TimeFormat 改转发（format=:mmss）；两个 load_quat docstring 加交叉引用。
- **当前行为**：两份 TimeFormat 同签名不同格式（B7）；load_quat 同名不同返回类型（B6）。
- **目标行为**：单一实现 + 转发；两种格式输出逐位不变。
- **依赖任务**：TASK-027。
- **风险**：低。Single_Particle_Orbit 依赖包模块 MarsData.TimeFormat（包总是已加载，安全）。
- **预期收益**：格式契约集中。
- **涉及科学计算**：否。
- **涉及数值结果**：否（字符串格式）。
- **测试要求**：两种 format 输出与各自原实现逐字符一致；转发调用测试。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

### S9：脚本层迁移（ARCH-002/ARCH-013）

#### TASK-035 — head.jl → MarsUtils 模块
- **对应 ARCH ID**：ARCH-002
- **Objective**：head.jl 去装载器身份，工具库注册化。
- **修改文件**：`common/head.jl`（整体重构：28-36 装载块删除；36-521 包为 `module MarsUtils`）；`src/modules.jl`（注册表）。
- **修改函数**：safe_log_mean/color_mapping/label_data/get_log_ticks 等 ~20 个工具函数模块化；bowshock/magnetopause 副本按审计表改转发 MarsCommon（TASK-029）。
- **当前行为**：双重身份（裸 include 6 重模块 + 工具库）；A4 大小写隐患。
- **目标行为**：`MarsUtils` 注册模块（deps=[constants,MarsCommon]，自包含 include）；旧 `include("common/head.jl")` 用法被 `MarsData.@load MarsUtils` 取代（Pickup_ion 在 TASK-036 迁移）。
- **依赖任务**：TASK-027、TASK-029。
- **风险**：中——MarsUtils 的 `using`（Optim/LsqFit/DSP 等 20 个）在载体内经 LOAD_PATH 解析（与现状一致）；label_data 依赖 Makie（包依赖内）。
- **预期收益**：两套装载体系收敛（AR-1）。
- **涉及科学计算**：否（工具库搬运）。
- **涉及数值结果**：否（个别工具含数值逻辑如 solve_func，需对比）。
- **测试要求**：@load MarsUtils 冒烟；有数值逻辑的工具（solve_func 等）改动前后对比；validate_registry 绿。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 README 迁移指引。
- **建议执行人**：GLM-5。

#### TASK-036 — Pickup_ion 函数化
- **对应 ARCH ID**：ARCH-013（AR-5/A5）
- **Objective**：隐式全局契约 → 显式入口；删除 D:/ 第三装载路径。
- **修改文件**：`models/Pickup_ion.jl`（全文件重构）。
- **修改函数**：新增 `pickup_ion_analysis(time_event::DateTime; instrument_mode="swi", spice_name="p+", dtime=..., spice_dict=<默认表>, data=nothing, tw_minpa_data=nothing, error_report=String[]) -> NamedTuple`；240 行起顶层全局逻辑局部化；KP 访问旧键（:vars/:var_190）→ 新 kp_dict 语义键；顶部裸 include → `MarsData.@load MAVEN_load MAVEN_STATIC MAVEN_SWIA Maxwellian_Distribution MarsUtils FunctionCoordinate`；273 行 D:/ 回退 include 删除。
- **当前行为**：需预置十余个全局变量 + include 运行；catch 分支硬编码 D:/ 路径（AR-5/A5）。
- **目标行为**：入口函数 + 文件尾全局 shim（检测旧全局仍被预置时调用入口并回填同名全局，@deprecate 标记）；`spice_dict` 默认表在文件内定义（以现脚本实际映射为准，实施前逐行审计）。
- **依赖任务**：TASK-035、TASK-033、TASK-013、TASK-007。
- **风险**：中高——隐式变量清单遗漏会导致行为分叉；缓解：AR-5 清单 + 新旧对比测试。
- **预期收益**：可测试、可复用（AR-5）。
- **涉及科学计算**：是（拾取离子分析全流程）。
- **涉及数值结果**：是。
- **测试要求**：入口函数合成输入冒烟（全分支 swi/sta/minpa）；真实事件（opt-in）新旧入口输出逐位一致。
- **Benchmark 要求**：无（若入口重构影响主流程，附一次总耗时前后对比）。
- **文档要求**：06 记录；PHASE 8 README 使用方式更新。
- **建议执行人**：GLM-5。

#### TASK-037 — Build_data/*.jl 迁移 @load
- **对应 ARCH ID**：ARCH-002
- **Objective**：Build_data 脚本走统一装载。
- **修改文件**：`MAVEN_data/Build_data/build_vsc.jl`、`STATIC_VD.jl`、`STATIC_vfd_3d.jl`、`ngi整合.jl`。
- **修改函数**：顶部相对路径 include → `MarsData.@load MAVEN_load MAVEN_STATIC IGRF_calculate`（按各文件实际使用裁剪）。
- **当前行为**：`include("../MAVEN_load.jl")` 相对路径装载（01 D4 耦合）。
- **目标行为**：@load 装载；脚本输出不变。
- **依赖任务**：TASK-012。
- **风险**：低。注意这些脚本历史较长，逐文件小步迁移、逐文件验证。
- **预期收益**：装载体系统一（AR-1）。
- **涉及科学计算**：是（构建脚本）。
- **涉及数值结果**：是（输出派生数据）。
- **测试要求**：每文件装载冒烟（不要求完整跑数据构建，opt-in）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-038 — example/*.jl 迁移 @load（可选）
- **对应 ARCH ID**：ARCH-002
- **Objective**：示例与官方用法一致化。
- **修改文件**：`example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl`、`MAVEN_overview_cases.jl`。
- **修改函数**：include 段 → `MarsData.@load`；KP_l3 别名兼容保留（03 ARCH-012 兼容期约定）。
- **当前行为**：相对路径 include + KP_l3 双键兼容别名。
- **目标行为**：@load 后行为不变（图输出一致）。
- **依赖任务**：TASK-040（KP 归一完成后再动示例，确保兼容回退已就位）。
- **风险**：低。
- **预期收益**：示例成为迁移范本。
- **涉及科学计算**：否。
- **涉及数值结果**：否（绘图产物一致性以冒烟为准）。
- **测试要求**：两脚本端到端运行无异常（图产物 gitignored，不比较像素）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 README。
- **建议执行人**：DeepSeek V4 Flash。

### S10：绘图与 API 面（ARCH-012/ARCH-010）

#### TASK-039 — plot_module 面板化
- **对应 ARCH ID**：ARCH-012（AR-16）
- **Objective**：12 面板独立可测；缺失键错误可定位。
- **修改文件**：`src/plotting.jl`（71-479 重构）。
- **修改函数**：新增 `panel_orbit!`、`panel_B_xyz!`、`panel_density!`、`panel_H_vel!`、`panel_scpot!`、`panel_SWEA_spec!`、`panel_swea_pad!`、`panel_SWIA_svy_spec!`、`panel_STATIC_c6!`、`panel_STATIC_mass!`、`panel_LPW_wave!` + `_require(data, key)` 辅助；`plot_module` 退化为装配器（签名与输出不变）。
- **当前行为**：plot_module 硬绑定 12 面板名与数据键，缺失即深处 KeyError（AR-16）。
- **目标行为**：面板独立函数显式入参；`_require` 缺失时抛 `"面板 density 需要 data_dict[...][:epoch]，缺失"` 式错误；装配器行为不变。
- **依赖任务**：TASK-034（同文件顺序）。
- **风险**：中——大函数拆分易漏行为；缓解：拆分前后对合成 data_dict 输出做快照对比（Makie 场景图不比较，比较"无异常+面板数量"）+ example 端到端。
- **预期收益**：面板可单测；诊断可读（AR-16）。
- **涉及科学计算**：否。
- **涉及数值结果**：否（绘图）。
- **测试要求**：合成 data_dict 逐面板冒烟；缺失键错误信息断言（含面板名与键路径）；example 端到端。
- **Benchmark 要求**：**bench_06** 拆分前后对比，不得慢于基线 110%。
- **文档要求**：06 记录；PHASE 8 api.md。
- **建议执行人**：GLM-5。

#### TASK-040 — KP 键归一（_get_kp 回退）
- **对应 ARCH ID**：ARCH-012（C17）
- **Objective**：双键收敛为单键 + 兼容回退。
- **修改文件**：`src/plotting.jl`（99、104、112、131 相关行）。
- **修改函数**：新增 `_get_kp(data_dict)`（有 `"KP"` 用之；仅有 `"KP_l3"` 用之并 @warn 一次）；plot_module 内部 KP 读取改走它。
- **当前行为**：同时读 `data_dict["KP_l3"]` 与 `data_dict["KP"]`（C17）。
- **目标行为**：单键读取 + 回退；示例（仍写双键）继续可用。
- **依赖任务**：TASK-039（同文件顺序）。
- **风险**：低。
- **预期收益**：双键补丁收敛为受控回退。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：仅 KP_l3 / 仅 KP / 双键三种输入行为测试（@warn 触发断言）；example 端到端。
- **Benchmark 要求**：无（属 bench_06 覆盖范围）。
- **文档要求**：06 记录。
- **建议执行人**：GLM-5。

#### TASK-041 — 别名层收尾 + export 死名清理
- **对应 ARCH ID**：ARCH-010（A7/AR-10）
- **Objective**：拼写体系收敛，破坏为零。
- **修改文件**：`MAVEN_data/MAVEN_plot.jl`（18）、`models/Cold_Plasma_Dispersion_Relation.jl`（226，若 TASK-024 未覆盖 `alfven_wave` 别名则在此补）。
- **修改函数**：删除 export 死名 `WaveSpactra_heatmap`；确认 `alfven_wave`/`calculate_minimum_energy`/`calculate_SWEA_pad` 别名齐备（其余已随 TASK-024/030）。
- **当前行为**：export 死名（A7）；拼写名散布。
- **目标行为**：export 清理；别名层完整。
- **依赖任务**：TASK-024、TASK-030。
- **风险**：低（白名单机制下 export 无关功能）。
- **预期收益**：命名一致性（AR-10）。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：别名调用与旧名结果一致测试（已有则复跑）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录；PHASE 8 CHANGELOG。
- **建议执行人**：Qwen 3.8 Flash。

#### TASK-042 — 白名单补全
- **对应 ARCH ID**：ARCH-010（AR-13）
- **Objective**：16 个空白名单模块可裸名调用公开入口。
- **修改文件**：`src/modules.jl`（MODULE_REGISTRY allow 字段）。
- **修改函数**：按 `docs/src/api.md` 公开函数清单填写 allow（每模块仅文档明确的公开入口；被删函数不进名单）。
- **当前行为**：仅 MarsCommon/MAVEN_load/IGRF_calculate 有 allow（AR-13）。
- **目标行为**：全部注册模块 allow 齐备（逐模块定稿并写入注册表注释）。
- **依赖任务**：TASK-016、TASK-033（FunctionCoordinate 已注册）。
- **风险**：低——若白名单名与模块实际定义不符，`_apply_allow!` 会抛错（现有机制已保护）。
- **预期收益**：脚本层迁移阻力消除（AR-13）。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：每模块 @load 冒烟 + 逐名引入测试（runtests 扩展）。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：DeepSeek V4 Flash（文档+测试型）。

### S11：清理（ARCH-016）

#### TASK-043 — 死代码与演进痕迹清理
- **对应 ARCH ID**：ARCH-016（AR-29）
- **Objective**：删除注释测试块与注释旧版。
- **修改文件**：`MAVEN_data/MAVEN_STATIC.jl`（1090-1204）、`MAVEN_data/MAVEN_SWEA.jl`（136-195）、`TW_data/TW_load.jl`（10-47）、`MAVEN_data/MAVEN_load.jl`（1465-1471、702-746、1311-1313）。
- **修改函数**：注释块删除（保留"参考 IDL/SPEDAS 文件"类注释）。
- **当前行为**：100+ 行注释测试与注释旧版误导阅读（AR-29）。
- **目标行为**：清理后仅保留出处注释；git 历史可追溯。
- **依赖任务**：TASK-030/031（同文件顺序——确保迁移完成后再清，避免触碰已移动代码）。
- **风险**：低。
- **预期收益**：阅读噪音消除（AR-29）。
- **涉及科学计算**：否。
- **涉及数值结果**：否。
- **测试要求**：runtests 绿；grep 抽查无残留测试块。
- **Benchmark 要求**：无。
- **文档要求**：06 记录。
- **建议执行人**：Qwen 3.8 Flash。

### 条件性性能任务（ARCH-014，全部带门）

#### TASK-044 — sta_v_4d/_new 等价证明与收编【CONDITIONAL】
- **对应 ARCH ID**：ARCH-014（AR-11）
- **Objective**：等价证明后删旧版（保留兼容名）。
- **修改文件**：`MAVEN_data/MAVEN_STATIC.jl`（543-684）。
- **修改函数**：`sta_v_4d`、`sta_v_4d_new`。
- **当前行为**：双版本并存，无等价证明（AR-11）。
- **目标行为**：`sta_v_4d` 内部调用 new 实现（保持旧签名/返回），`sta_v_4d_new` 保留为 deprecated 转发。**门**：bench_03 证明等价（合成+真实 rel ≤ 1e-9）且在 06 记录证据；**不等价 → 跳过本任务**，保留双版本、记录差异、上报科学负责人（03 §3.3 ARCH-014）。
- **依赖任务**：TASK-001。
- **风险**：中（等价性未证则禁止）。
- **预期收益**：双版本维护成本归零（AR-11/22）。
- **涉及科学计算**：是。
- **涉及数值结果**：是。
- **测试要求**：等价性回归测试固化（合成切片，rel ≤ 1e-9）。
- **Benchmark 要求**：**bench_03 前后对比为强制证据**（R2）。
- **文档要求**：06/07 记录证据。
- **建议执行人**：GLM-5。

#### TASK-045 — STATIC 热点轻量 struct 包装【CONDITIONAL】
- **对应 ARCH ID**：ARCH-014（AR-7 P3）
- **Objective**：在证据充分时对矩计算热路径做类型稳定包装。
- **修改文件**：`MAVEN_data/MAVEN_STATIC.jl`（sta_v_4d_new 内部 + 新私有 helper）。
- **修改函数**：新增 `_extract_slice(dat)::NamedTuple`（一次提取 + 类型断言）；sta_v_4d_new 内部使用。
- **当前行为**：循环内多次 `dat[:key]` 的 `Dict{Symbol,Any}` 动态分派（AR-22）。
- **目标行为**：入口处一次提取为类型稳定 NamedTuple；**公开 API 不变（仍接受 Dict）**。**门**：bench_03 显示 Dict 访问开销占比 ≥ 可测阈值（如总耗时 >10%）；改动前后 bench_03 成对对比。
- **依赖任务**：TASK-044。
- **风险**：中——类型假设（Float32 三维数组）需断言防错。
- **预期收益**：矩热路径提速（量化以基准为准）。
- **涉及科学计算**：是。
- **涉及数值结果**：是。
- **测试要求**：数值逐位一致回归。
- **Benchmark 要求**：**bench_03 前后成对对比（强制，R2）**。
- **文档要求**：06/07 记录收益数字。
- **建议执行人**：GLM-5。

#### TASK-046 — STA_count2df_all 向量化【CONDITIONAL】
- **对应 ARCH ID**：ARCH-014（AR-22）
- **Objective**：消除 deepcopy 全量拷贝与逐时刻 4D 构建。
- **修改文件**：`MAVEN_data/MAVEN_STATIC.jl`（274-333）。
- **修改函数**：`STA_count2df_all`。
- **当前行为**：`deepcopy(dat0)` + 每时刻三次索引循环构建 4D 中间数组（作者自注"开销极大"，AR-22）。
- **目标行为**：预分配 + @views 单遍构建（参考 STA_count2eflux_all 的 reshape 模式），输出键与形状不变。**门**：bench_02 证明当前耗时显著（相对下游矩计算不可忽略）。
- **依赖任务**：TASK-001（bench_02）。
- **风险**：中——索引展开逻辑微妙（swp/att/eff 三索引），数值回归必须逐位。
- **预期收益**：批处理主路径提速。
- **涉及科学计算**：是。
- **涉及数值结果**：是。
- **测试要求**：新旧实现合成输入逐位一致。
- **Benchmark 要求**：**bench_02 前后成对对比（强制，R2）**。
- **文档要求**：06/07 记录收益数字。
- **建议执行人**：GLM-5。

#### TASK-047 — plot_module 微优化【CONDITIONAL】
- **对应 ARCH ID**：ARCH-014（AR-22）
- **Objective**：消除重复二分与冗余 convert。
- **修改文件**：`src/plotting.jl`。
- **修改函数**：`plot_module` 及面板函数（time2x 结果缓存、`convert.(Float64,…)` 去冗余）。
- **当前行为**：多次 time2x 重复二分 + 冗余类型转换（AR-22）。
- **目标行为**：同区间 time2x 一次计算复用；仅在确为冗余处去 convert。**门**：bench_06 显示合成耗时 > 明显阈值；优化后不得慢于基线 110%（03 红线）。
- **依赖任务**：TASK-001、TASK-040。
- **风险**：低中（绘图行为不变是硬约束）。
- **预期收益**：概览图合成提速。
- **涉及科学计算**：否。
- **涉及数值结果**：否（绘图；以 example 端到端 + 无异常为证）。
- **测试要求**：example 端到端；单面板冒烟。
- **Benchmark 要求**：**bench_06 前后成对对比（强制，R2）**。
- **文档要求**：06/07 记录。
- **建议执行人**：GLM-5。

#### TASK-048 — IGRF ccall 边界评估【CONDITIONAL/评估】
- **对应 ARCH ID**：ARCH-014（AR-23）
- **Objective**：量化 ccall 边界开销并给出结论报告；仅做无算法风险的微优化。
- **修改文件**：`Magnetic_Model/IGRF_calculate.jl`（258-269、293-320，视评估结论）。
- **修改函数**：`IGRF_fortran`/`RK4_Trace_fortran`（工作区缓冲复用，如预分配 path/B_result 避免每步 Array 分配）。
- **当前行为**：每步追踪 = 每步 ccall + 每步 3 个小 Array 分配（AR-23）。
- **目标行为**：评估报告（bench_07 分解：ccall 自身 vs 分配 vs 循环）；可行微优化 = 缓冲复用（无算法变化）；**任何 Julia 端球谐移植/批量 ccall 接口替换 = R5，仅评估并上报，未经批准禁止实施**。
- **依赖任务**：TASK-001（bench_07）、TASK-026。
- **风险**：中（ccall ABI 小心；缓冲复用需确认 DLL 无内部状态依赖）。
- **预期收益**：30000 步追踪的分配削减；为人类决策提供数据。
- **涉及科学计算**：是。
- **涉及数值结果**：是（缓冲复用要求逐位一致）。
- **测试要求**：缓冲复用前后追踪输出逐位一致。
- **Benchmark 要求**：**bench_07 分解对比（强制，R2）**。
- **文档要求**：06/07 评估报告。
- **建议执行人**：GLM-5。

---

## 4. 硬约束映射检查（R1–R7 逐条）

| 约束 | 本文件落实 |
| --- | --- |
| R1 不删 Markdown | 所有任务只改 .jl/新增 benchmark；文档改动集中 PHASE 8（TASK 文档要求字段标注） |
| R2 性能改动必须 benchmark | §2 口径 + 每性能任务强制成对对比（TASK-013/031/039/044–048） |
| R3 重要修改必须有测试 | 每任务"测试要求"字段 + runtests 绿为完成门 |
| R4 科学修改必须数值验证 | "涉及数值结果=是"的任务全部要求前后对比（合成 rel≤1e-9 或逐位）；S0a/S0b golden 快照为统一"改动前"基准 |
| R5 重大科学算法人类批准 | 03 §15 定稿；本文件 C1（TASK-021 默认不改）、C6/C7/C11/C12/C13（TASK-023 不改值）、DLL 移植（TASK-048 仅评估） |
| R6 无收益重构禁止 | 删除仅限 3 个坏死函数（TASK-002）；其余全部别名/转发/kwarg；CONDITIONAL 任务带证据门 |
| R7 Python 零改动 | 无任何任务触碰 Python 侧；benchmark 独立目录不动包 [deps] |
| R8 阶段隔离 | 本阶段只读源码定点复核 + 写 04；PHASE 6 前不再全仓扫描 |

---

## 5. 只读合规声明

- 输入：`.agent/01_PROJECT_MAP.md`、`.agent/02_ARCHITECTURE_REVIEW.md`、`.agent/03_ARCHITECTURE_PLAN.md`（只读引用）。
- 本阶段定点读取的源码（未重新全仓扫描）：`MAVEN_data/MAVEN_load.jl`(120-234, 400 签名)、`MAVEN_data/MAVEN_STATIC.jl`(260-389, 885-1094)、`MAVEN_data/MAVEN_plot.jl`(1442-1554)、`MAVEN_data/MAVEN_SWEA.jl`（上阶段已读）、`MAVEN_data/MAVEN_SWIA.jl`（上阶段已读）、`Magnetic_Model/IGRF_calculate.jl`(240-309)、`calculate/calculate_models.jl`(100-169)、`models/Single_Particle_Orbit.jl`(1-45, 340-389)、`common/head.jl`(350-424)、`common/function_coordinate.jl`(190-264)、`src/plotting.jl`(20-64)、`call_fortran_dll.jl`(全文)；grep 定位函数签名 2 次。
- 写入：仅 `.agent/04_OPTIMIZATION_PLAN.md`（覆盖占位符）。
- 未修改任何源码、数据、配置文件；未执行全仓扫描。
