# 05_TEST_STRATEGY.md — PHASE 5：测试策略（为 04 每个 TASK 制定分层测试方案）

> 状态：DONE
> 阶段：PHASE 5 - Test Strategy
> 负责：DeepSeek V4 Flash (Worker / Test / Benchmark / Documentation Agent)
> 依赖：`.agent/01_PROJECT_MAP.md`、`.agent/02_ARCHITECTURE_REVIEW.md`、`.agent/03_ARCHITECTURE_PLAN.md`、`.agent/04_OPTIMIZATION_PLAN.md`（均只读引用，未改动）
> 性质：**只读任务**。本阶段不修改任何源码，仅在 `.agent/` 下覆盖本文件。
> 用途：为 04 的每一个 Coding Task（TASK-001…048）制定**可执行、可验收**的测试策略，将五类测试（Unit / Integration / Regression / Scientific / Benchmark）映射到每个任务；科学类任务强制数值/单位/量级/边界/新旧一致性验证（R4）；性能类任务固化基准基线、方法、重复次数、前后对比与可接受波动阈值（R2）。

---

## 1. 测试策略总则

### 1.1 五类测试定义（本文件强制口径）

| 代码 | 类别 | 定义 | 典型工具/结构 | 判定标准 |
| --- | --- | --- | --- | --- |
| U | **Unit Test** | 单个函数/模块的孤立行为，不依赖真实数据/DLL/IO | `test/` 内 `@testset` 分组；合成输入 | 逻辑正确、抛错路径、默认参数、形状断言 |
| I | **Integration Test** | 多个模块/函数联动（装载、读取→处理、转发链、面板装配） | `test/` 跨模块 testset；example 端到端 | 全链路无异常、输出结构符合契约 |
| R | **Regression Test** | 改动前 vs 改动后行为一致性（新旧对比、锁定既有行为） | golden JSON 对比、逐位 `==`、`rel ≤ 阈值` | 数值不漂移（R4）；等价证明后才允许删双实现 |
| S | **Scientific / Numerical Validation** | 验证科学正确性：数值结果、单位、数量级、物理边界、独立解析值、能量守恒等 | 手算解析值、量纲缩放、独立参考实现 | 物理量在物理合理区间、解析值吻合、单位/量级正确 |
| B | **Performance Benchmark** | 性能量化与前后对比（R2） | `benchmark/` 独立环境、BenchmarkTools | 基线入档、成对对比、波动阈值、等价门 |

### 1.2 类别强制约定

1. **涉及科学计算 = 是 且 涉及数值结果 = 是** 的任务：`S` 类**必做**，且不能只靠 `U` 类判断正确——必须覆盖数值结果、单位、数量级、边界条件、新旧实现一致性、可接受误差范围（§1.3 通用口径）。
2. **涉及数值结果 = 是** 的任务：新旧对比按 R4 口径（合成数据 `rel ≤ 1e-9` 或逐位一致；真实数据 opt-in 记录来源/哈希）。
3. **性能类任务**（Benchmark 要求非"无"）：`B` 类必做，含基线、方法、环境、重复次数、前后对比、可接受波动阈值（§1.4 通用口径）。
4. **纯工程/纯文档任务**（涉及数值结果 = 否）：以 `U`/`R` 为主（形状、抛错、兼容回退、注释存在性），`S` 类仅在有数值工具时附加。
5. **每任务三类维度**：`U`（核心单测）、`I`（联动）、`R`（回归/新旧），`S`/`B` 按"涉及科学/涉及性能"条件附加。04 的"测试要求"字段为本策略的**验收基线**，本文件细化但**不降低**任何 04 既有要求。
6. **文件布局**（建议，PHASE 6 落地）：`test/` 下按模块拆分 `test_marscommon.jl`、`test_static.jl`、`test_swia.jl`、`test_swea.jl`、`test_igrf.jl`、`test_coldplasma.jl`、`test_loaders.jl`、`test_plot.jl`、`test_pickup.jl`、`test_contract.jl`、`test_registry.jl`，`test/runtests.jl` 聚合 + `test/fixtures/` 内嵌小样本（每类文本 loader 5–20 行合成行）。
7. **环境矩阵**：无数据/无 DLL/无 settings.toml 环境（fresh clone）必须全绿；真实数据 + DLL 类测试用 `Sys.iswindows()` 与数据存在性条件跳过（`@test_skip` 显式标注），不得假装通过（03 风险 #3/#5）。

### 1.3 科学类任务的通用验证要素（S 类必检清单）

涉及科学计算的修改，S 类测试必须尽可能覆盖以下维度（能覆盖则覆盖，能豁免需在 06 记录理由）：

1. **数值结果**：与独立解析值/参考实现对比（如 n1d 手算 `dE·E^(-3/2)` 加权值、Energy↔Velocity 对照解析公式）。
2. **单位**：输出单位与附录 A 契约/SPEDAS 约定一致（nT、km/s、cm⁻³、eV、1/(cm³·(km/s)³)——见 03 附录 A 单位约定 AR-19）。
3. **数量级**：物理量落在物理合理区间（密度 > 0、SWIA coarse 网格密度恒正、B 场量级 ~nT 等）。
4. **边界条件**：输入边界（空数组、单位阵、越界索引、3D vs 4D 数组、NaN/Inf 输入、无命中）均有断言。
5. **新旧实现一致性**：改动前后输出对比（逐位或 `rel ≤ 阈值`）；转发对等价测试。
6. **可接受误差范围**：每处对比显式声明阈值与理由（纯搬运/键修复 → 逐位一致；坐标往返 → `rel ≤ 1e-12`；等价收编门 → `rel ≤ 1e-9`；真实数据 → 记录哈希 + 抽样值容差）。

### 1.4 性能类任务的通用验证要素（B 类必检清单）

1. **基线**：`benchmark/results/baseline_*.json` 永久版本化入库，任何优化前先跑基线（S0a/S0b）。
2. **方法**：同机同数据、同 Julia 会话配置；`@benchmark` 记录 `minimum` 与 `median`。
3. **环境**：`bench_*.jl` 内记录 `VERSION`、`BLAS.get_num_threads()` 到结果报告；合成数据记录种子与形状，真实数据记录文件路径 + SHA-256。
4. **重复次数**：`@benchmark` 自动采样（samples/evals 均记录显式），CI 外的权威基准手动跑足，每项至少报告 `samples` 与 `evals`。
5. **前后对比**：任何改动必须**成对**出结果（同脚本、同输入、同一次会话）；写入 `benchmark/results/baseline_report.md` 并由 06/07 汇总。
6. **可接受波动阈值**：全局约定——优化**不得慢于基线 110%**（03 §13，#6 红线）；提速类收益以 `median` 相对差为准，`minimum` 仅作旁证；单次波动超过 15% 视为环境噪声，重跑确认；等价门（`sta_v_4d` 等）以 `rel ≤ 1e-9` 为唯一收编依据（不等价则禁止删除双版本）。
7. **CI 约束**：CI 不跑耗时 benchmark（时长）；`golden_snapshot.jl` 的一致性对比设计为秒级可进 CI（快照 vs 当前逐位一致）。

---

## 2. 通用基准与 Golden 方案（S0：TASK-001/008，为后续全部 S/R 提供统一基线）

### 2.1 Golden 快照（TASK-001 合成类 / TASK-008 真实类）

| 快照文件 | 内容 | 生成时机 | 用途 |
| --- | --- | --- | --- |
| `baseline_marscommon.json` | 球↔笛卡尔往返、能量↔速度、eflux→PSD（两版）、bowshock/magnetopause 网格、Bpc2sphere、Vandermonde/polynomial_fit | TASK-001 | ARCH-006 转发对 S4 的等价回归锚点 |
| `baseline_static.json` | 合成切片：STA_count2eflux/STA_eflux2df/sta_v_4d/_new/STA_count3df/sta_v_1d | TASK-001 | ARCH-007/014 的 S 类回归锚点 |
| `baseline_swia_swea.json` | 合成网格：n1d、n_3d、j_3d（v_3d 当前 C5 bug，只快照异常行为注明） | TASK-001 | ARCH-008 修复前后对比锚点 |
| `baseline_coldplasma.json` | set_particles + Dispersion_Relation/DR_wave_vector/calculate_minimum_energy 参数网格 | TASK-001 | ARCH-009 PlasmaState 新旧一致性锚点 |
| `baseline_igrf.json` | IGRF_pc 网格、trace_mag_line（Euler）终点、get_mag_line_s 输出 | TASK-008（DLL） | ARCH-007/008/009 IGRF 系列回归锚点 |
| `baseline_loader.json` | load_mag_l2/load_kp/load_cdf 单文件输出摘要（键集+形状+抽样值） | TASK-008（真实 opt-in） | ARCH-001/004/007 loader 系列回归锚点 |

**通用断言**：任何快照 JSON 可重复生成（两次运行逐位一致）；`golden_snapshot.jl` 支持"对照当前实现重建 vs 旧快照"秒级一致性检查。

### 2.2 八项基准清单（B 类统一口径，供 TASK-013/031/039/044–048 引用）

见 04 §2.3 表；本文件补充每项判据与阈值：

| 基准 | 采样的关键指标 | 阈值/用途 |
| --- | --- | --- |
| bench_01 loader | 文本读取 min/median | 基线入档；解析改动成对对比 |
| bench_02 static 矩 | STA_count2df_all/3df min/median | TASK-046 门证（耗时显著）+ 前后对比 |
| bench_03 sta_v_4d vs _new | 等价网格相邻点差 + 双版本计时 | 等价 rel ≤ 1e-9（收编门）；TASK-044/045 |
| bench_04 static_c6 | static_c6_mass_mean/energy_mean min/median | TASK-031 前后对比（转发无退化） |
| bench_05 findfile | 索引化前后命中一致性 + 计时 | 命中一致 + TASK-013 证据 |
| bench_06 plot | plot_module 合成 12 面板 min/median | TASK-039/040/041/047 前后对比，不得慢于基线 110% |
| bench_07 trace | Euler/RK4/adaptive 终点偏差 + 耗时表 | C1 决策数据（交人类，TASK-021 不改默认）；TASK-048 分解评估 |
| bench_08 fullday | load_MAVEN_data 一日全产品计时 | 基线入档；TASK-013/006 前后对比 |

---

## 3. 任务级测试策略（按 04 的 TASK-001…048 逐一成文）

> 每任务格式：`类别分配`（U/I/R/S/B 是否启用）→ `U` 单测要点 / `I` 联动要点 / `R` 回归要点 / `S` 科学验证要点（涉及科学时）/ `B` 基准要点（性能时）→ `验收门`（汇总到 §4）。

### S0a：TASK-001 — benchmark 基建 + 合成基线 + 纯函数 golden 快照
- 类别：`U` `R` `S` `B`。
- `U`：合成数据生成器形状断言（`gen_static_slice`/`gen_c6_day`/`gen_swea_spec`/`gen_swia_coarse`/`gen_filename_list`/`gen_plot_datadict` 输出形状与 03 附录 A 契约一致——如 coarse theta `(ntime,4,48)`、c6 字典必含 `:epoch/:mass_arr/:df` 等）。
- `R`：golden JSON 两次运行逐位一致（可复现）。
- `S`：快照值抽查物理量级（密度 > 0、能量在 eV 合理区间）；坐标往返 rel ≤ 1e-12。
- `B`：跑通 §2.2 中 2/3/4/5/6/7 可运行项的首份基线并写入 `baseline_report.md`；记录 `samples/evals`、种子、形状。
- 验收：快照可复现 + 形状断言全绿 + 首份基线入档。

### S1（P0 修正包）

#### TASK-002 — 删除三份坏死 calculate_mag/caculate_mag
- 类别：`U` `I` `R`。
- `R`：`grep` 确认无残留引用；`MAVEN_load`/`TW_load`/`MGS_load` 各模块 `load_module` 后 `@test !isdefined(Mod, :calculate_mag)`（用现有 `load_module` 冒烟路径）。
- `I`：三模块装载冒烟（fresh clone 不因该函数删除而失败）；runtests 全绿。
- 验收：无残留引用 + 模块装载冒烟绿。**不涉及科学/数值，S 类豁免。**

#### TASK-003 — STA_count2eflux/STA_eflux2df 默认参数修复
- 类别：`U` `R` `S`。
- `U`：`STA_count2eflux(dat)` 与 `STA_count2eflux(dat; m_int=16)` 逐位一致（默认有定义）；`STA_eflux2df(dat)` 默认可调用。
- `S`：合成切片输入输出形状断言（:eflux 3D、:df 4D 形状与附录 A 一致）；单位/量级抽查（df 单位 1/(cm³·(km/s)³)，正值断言）；`m_int` docstring 注明"按离子种类显式传值"。
- `R`：`m_int=16` 与显式传值一致（新旧等价，rel ≤ 1e-9 或逐位）。
- 验收：默认调用与 m_int=16 逐位一致 + 形状/量级 S 断言绿。

#### TASK-004 — get_mag_line_s 键不一致修复
- 类别：`U` `I` `R`。
- `U`：`trace_mag_line` 输出（Symbol 键）直接过 `get_mag_line_s` 不抛错，且 `:S/:alt/:B_total` 长度一致；字符串键 `"B"` 输入兼容（回退路径）。
- `I`：`trace_mag_line → get_mag_line_s` 全链路（需 DLL，Windows 条件）。
- `R`：读 `:B` 与读 `"B"`（同一数据转置）输出一致（键访问修复，值不变）。
- 验收：双键兼容单测 + 全链路不抛错。**输出值不变 → 数值关卡严格等于旧 `"B"` 值。**

#### TASK-005 — load_mag_l2 表头定位稳健化
- 类别：`U` `I`。
- `U`：fixtures 短样本（含 >300 行表头构造）`findlast` 正确找到 END；缺 END 时错误信息含文件名断言。
- `I`：`load_mag_l2` 在样本文件上返回结构（`:time/:B/:data_load_flag`）符合契约。
- 验收：END 定位 + 缺 END 报错断言绿。**解析逻辑不变 → 数值 S 类豁免（列值逐位与旧逻辑一致可追加 R 对比）。**

#### TASK-006 — 读取错误可见化：@warn + error_report
- 类别：`U` `I` `R`。
- `U`：模拟缺失模型目录 → `load_MAVEN_data(,..., error_report=...)` 返回 `error_report` 非空、`flag`（各模型）为 false、触发 `@warn`；正常路径 `error_report` 保持空。
- `I`：`load_MAVEN_data` 多模型批处理（合成/构造缺失路径）聚合正确。
- `R`：默认不传 `error_report` 行为与改动前一致（返回结构与 flag 语义不变）。
- 验收：聚合 + @warn 断言绿 + 默认路径回归绿。**不涉及数值结果，S 豁免；若实现引入开销可用 bench_08 证明 <1%（可选）。**

#### TASK-007 — filename_lists 惰性化（A1 修复）
- 类别：`U` `I` `R`。
- `U`：无 `filename_lists.json` 环境 `load_module(:MAVEN_load)` 冒烟 + `filename_list()` 返回空 `Dict`；有文件时逐键与旧全局一致（文件内容逐键相等）。
- `I`：fresh clone（临时去文件）runtests 全流程冒烟（A1 阻塞解除）。
- `R`：文件存在时各模型 `file_flag=false` 容错与前行为一致。
- 验收：无文件装载成功 + 有文件逐键一致。**档案只读，数值 S 豁免。**

### S0b：TASK-008 — 真实数据 golden + loader 基准
- 类别：`R` `S` `B`。
- `R`：`baseline_igrf/loader.json` 同文件两次运行逐位一致。
- `S`：真实数据抽样值物理量级断言；DLL 类快照（IGRF）在 `Sys.iswindows()` + DLL 存在时生成。
- `B`：bench_01/08 首份真实基线（记录文件路径 + SHA-256 + 日期），写入 baseline_report.md。
- 验收：快照可复现 + 基准入档；**数据不可得时在 06 明确记录"缺失、以合成基线为准"并 opt-in 跳过（03 风险 #3），不假装通过。**

### S2：路径统一（ARCH-005）

#### TASK-009 — SP_load 路径化与去副作用
- 类别：`U` `I` `R`。
- `U`：无数据环境 `load_module(:SP_load)` 冒烟（无加载期 INI 读取、无 println 副作用——捕获/观察日志为空）。
- `I`：有 INI/TOML 环境 `load_omni2_data`/`load_drivers_merge_data` 读取输出与改动前逐位一致（对比测试）。
- `R`：配置缺失场景从"崩溃"→"默认值"（新增行为，单测锁定）。
- 验收：无副作用装载 + 有配置输出一致。

#### TASK-010 — TW/MGS 根路径 Paths 化
- 类别：`U` `I`。
- `U`：无数据环境三文件（TW_load/TW_MINPA/MGS_load）装载冒烟。
- `I`：mock 根目录（临时目录 + 样本文件）下 `read_list`/`build_file_list` 结果正确（用样本文件断言文件列表内容）。
- 验收：无数据装载 + mock 根读取正确。**读取输出逐位与硬编码路径版一致可追加 R（数据 opt-in）。**

#### TASK-011 — Call_fortran_dll 路径解析
- 类别：`U` `S` `I`。
- `U`：无 DLL 环境调用 `cold_plasma_linear_growth`/`Bspline_db1ink`/`Bspline_db1var` 抛含指引的清晰错误（列出尝试过的全部路径：settings.toml only→仓库根→旧硬编码→报错）。
- `S`/`I`（opt-in）：有 DLL 环境数值与改动前逐位一致（DLL 符号不变，路径解析不影响数值）。
- 验收：缺失路径报错信息断言；有 DLL 环境数值一致（opt-in）。

### S3：装载注册表（ARCH-004）

#### TASK-012 — 显式 LOADER_FUNCS 函数表（去 eval）
- 类别：`U` `I` `R`。
- `U`：新校验测试——读取 `MAVEN_data_format.json` 全部 55 个产品的 `value[4]` 字符串 ⊂ `LOADER_FUNCS` 键集（一一对应，防拼写遗漏）；`value[4]` 不在表内时 `load_module` 抛清晰错误（含键与缺失函数名）。
- `I`：golden 一日加载回归（TASK-008 快照或合成 mock）——函数表分派与旧 eval 分派结果一致。
- `R`：装载返回结构不变；`read_models` 键/值结构与旧一致。
- `B`（可选）：若映射构造影响加载期耗时，加载时间对比证明 <5%。
- 验收：55 键一一对应校验绿 + 一日加载回归绿。

#### TASK-013 — 文件定位日期索引化
- 类别：`U` `I` `R` `B`。
- `U`：`_file_index(model)` 对 1000 文件名合成列表正确建索引——覆盖无日期文件名、多日期段文件名（取末段最长 8 位）、无命中回退 `occursin` 子串扫描。
- `R`：索引与旧实现命中结果逐一一致（行为兼容是硬约束）。
- `I`：golden 一日加载回归 + `find_file_of_data` 通过 `file_list` 链路。
- `B`：**bench_05** 索引化前后计时对比（必做，R2），记录命中一致 + 计时数字。
- 验收：命中一致断言绿 + bench_05 成对对比入档。

### S4：装载一致性（ARCH-003）

#### TASK-014 — MarsCommon 自包含 include
- 类别：`U` `I`。
- `U`：`include("common/MarsCommon.jl")` 单独直接可用（不依赖装载顺序，无 UndefVarError）；`load_module(:MarsCommon)` 冒烟。
- `I`：全部下游测试（MAVEN_STATIC/plot 等依赖模块）装载冒烟。
- 验收：单独 include 冒烟 + 全下游绿。**constants 为纯数值双副本 → 数值 S 豁免（值不变）。**

#### TASK-015 — validate_registry 扩展
- 类别：`U` `I` `R`。
- `U`：构造含 `using ..X` 且 X 不在 deps 的临时模块文件 → `validate_registry` 报告问题；构造自包含 include 且 X 又在 deps → 报警告级提示；当前注册表全绿（空问题）。
- `I`：`validate_registry()` 返回空 + 全模块装载冒烟。
- `R`：既有 validate 测试保持绿。
- 验收：两类新校验触发断言 + 当前注册表全绿。**src/modules.jl 为红线文件，只加校验不动机制。**

### S5：数据契约中心化（ARCH-011）

#### TASK-016 — DataKeys 模块
- 类别：`U` `I` `R`。
- `U`：DataKeys 各常量与 03 附录 A 逐项一致性测试（键名抽查断言，如 `MarsData.DataKeys.EPOCH === :epoch`、`:B_total` 等）；`load_module(:DataKeys)` / preloaded 冒烟。
- `I`：`src/MarsData.jl` include 后 `using MarsData; DataKeys.EPOCH` 可用。
- `R`：零行为变化（纯常量，validate_registry 绿）。
- 验收：附录 A 逐项抽查绿。**纯常量，S 豁免。**

#### TASK-017 — 就地修改约定 docstring + 契约测试
- 类别：`U` `R`。
- `U`：`static_slip` 视图语义测试——对切片写**新键**不影响原数据（承诺锁定）；写**既有键**污染行为仅在 06 记录不做硬断言（docstring 已注明）。`STA_count2df` 写 `:df` 新键不改入参既有键。
- `R`：视图共享内存行为不随时间漂移（回归测试）。
- 验收：写新键安全断言绿。**纯文档+行为锁定，S 豁免。**

### S6：科学修正与出处注释（ARCH-008）

#### TASK-018 — SWEA n1d 删除死变量 tiny（C4）
- 类别：`U` `R` `S`。
- `S`（核心）：合成能谱 `n1d` 改动前后**逐位一致**（删除死变量行为不变证明）；手算期望值回归——`dE·E^(-3/2)` 加权解析值（构造已知能谱，解析 dn/dE，断言与手算吻合）。
- `R`：S 对比固化（删除 tiny 前后 = 同一值）。
- `U`：`n1d` 输入形状/长度断言；空/负能道输入边界。
- 验收：逐位一致 + 手算解析值回归绿。**科学修正必须 R4 证据。**

#### TASK-019 — SWIA v_3d 索引维度修复（C5）
- 类别：`U` `S` `I` `R`。
- `S`（核心）：合成 coarse 网格（theta 3D `(ntime,4,48)`，与 `get_3dc!` 输出一致）过 `v_3d` **不抛 BoundsError**、密度**恒正**、形状断言；fine 网格（theta 4D）现索引路径回归仍正确。
- `U`：函数开头尺寸断言——输入形状不符时抛含实际形状的清晰报错。
- `I`：`diff_en_fluxes` 4D 索引保持（实施时断言确认）。
- `R`/`S`（opt-in）：真实 SWIA 一日 v_3d 与 n_3d/j_3d 一致性核对（量级/符号），结果入 06。
- 验收：coarse+fine 双输入跑通 + 密度正 + 形状断言绿。**修复前的当前错误行为需在 TASK-008 或 001 快照中留档。**

#### TASK-020 — combina_two_dir_trace 自引用修复（C2）
- 类别：`U` `S` `R` `I`。
- `S`：`to_pc=true` 调用不抛错；与 `to_pc=false` 结果逐点做球→笛卡尔变换对比（`rel ≤ 1e-12`）——证明 to_pc 路径确实是同样的点转为笛卡尔。
- `U`：`to_pc=true/false` 双分支输出形状一致。
- `I`：双向磁力线数据流（先 trace 再 combina）拼接无异常。
- 验收：to_pc=true 可用 + 逐点球↔笛卡尔一致 rel ≤ 1e-12。

#### TASK-021 — trace_mag_line method kwarg（C1）
- 类别：`U` `S` `I` `B`。
- `S`：默认 `method=:euler` 调用输出与改动前**逐位一致**（默认行为不变是硬约束）；`:rk4`/`:adaptive` 支路同起点输出形状一致（`N×6`）；三者数值在合理容差（RK4 精度应优于 Euler，断言趋势但以报告为准）。
- `U`：非法 `method`（如 `:bogus`）报错；类型校验。
- `I`：三支路与 `get_mag_line_s` 全链路。
- `B`：**bench_07** 三法终点偏差 + 耗时表（交人类裁决 C1 默认不改；kwarg 本身为工程改动）。
- 验收：默认逐位一致 + 三支路形状 + 非法 method 报错 + bench_07 数据入 06/07。

#### TASK-022 — SWEA shape 硬编码常数具名化（C10）
- 类别：`U` `R`（科学证明不变）。
- `R`（核心）：`SWEA_calc_shape_arr` 合成输入改动前后**逐位一致**（提取常量不改值证明）。
- `U`：具名常量（`SWEA_NCHANNELS=64`、`SWEA_PAD_INDEX=13:64`、`SWEA_NE=52`）存在性 + 出处注释存在性检查。
- `S`：数值如有任何出入即停手上报（03 §15 C10 门）。
- 验收：逐位一致 + 常量/出处注释断言。

#### TASK-023 — 记录类常数出处注释（C6/C7/C11/C12/C13）
- 类别：`R`（弱测试）+ `S`（对照推断）。
- `R`：注释存在性检查（grep 关键词断言 `疑点/出处/待验证`）——弱测试，重点在 06 对照表记录。
- `S`：若可得 MINPA/参考数据：denergy 逐通道积分 vs `0.2/2` 相对差、v3d 速度矩符号对照——记录不判过（记录类不改值，人类裁决）。
- 验收：注释存在性 + 06 对照表条目。**不改任何数值/逻辑 → 无数值回归要求。**

### S7：状态显式化（ARCH-009）

#### TASK-024 — Cold_Plasma PlasmaState 重构
- 类别：`U` `S` `I` `R`。
- `S`（核心）：新旧路径（旧全局签名 vs `Dispersion_Relation(θ,freq,Πe,Ωe,state)`）对**参数网格逐点 rel ≤ 1e-12**（公式逐字不动证明）；`make_particles` 产出与 `set_particles` 写 Ref 后读出的值一致。
- `U`：未初始化旧路径给出**清晰错误**（含指引，非 UndefVarError）；`carculate_minimum_energy` 转发 `calculate_minimum_energy` 一致。
- `I`：`Threads.@threads` 两线程各用独立 state，结果与串行一致（状态隔离证明）。
- `R`：`set_particles` 写 Ref 副作用 + 返回值 PlasmaState（旧脚本零改动兼容回归）。
- 验收：参数网格 rel ≤ 1e-12 + 未初始化报错 + 并行隔离一致 + 兼容回归。

#### TASK-025 — load_kp kp_columns kwarg
- 类别：`U` `R` `I`。
- `U`：默认调用输出与改动前一致（`load_kp(file)` 锁定）；自定义 `kp_columns` 生效（改列映射后输出变化可验证）；非法列映射报错。
- `I`：`change_kp_read_data` 兼容路径测试（写 Ref + `load_kp` 无 kwarg 读到新值）。
- `R`：默认行为不变回归（fixture KP 文件逐位）。
- 验收：默认一致 + 自定义生效 + 兼容路径绿。**不涉及科学数值（列映射逻辑），S 豁免。**

#### TASK-026 — IGRF bcompress 显式变体
- 类别：`U` `S` `I` `R`。
- `S`：默认调用与改动前**逐位一致**（kwarg 默认读全局 = 旧行为）；显式 `bcompress` 生效（改值后输出变化可验证）。
- `R`：`set_B_compress` 兼容；显式传参输出与读同一全局输出一致。
- `I`：`Threads.@threads` 两线程不同 `bcompress` 互不污染（并行安全证明）。
- `B`（可选）：kwarg 默认路径与旧全局查找同开销（如需证明用 bench_07）。
- 验收：默认逐位 + 显式生效 + 并行隔离一致。

### S8：去重与权威实现（ARCH-006）

#### TASK-027 — 签名/单位审计表（门禁任务）
- 类别：`R`（审计质量验收）+ `S`（单位核对）。
- `R`：接受标准 = 06 审计表完整度（逐对列出调用点/输入单位/返回单位/差异；确认 `Single_Particle_Orbit.cyclotron_radius` SI 输入不转发的结论固化）。
- `S`：各单位标注与附录 A 单位约定（AR-19）交叉核对；`cyclone_*`/`cyclotron_*` 单位差异（nT vs T、eV vs SI）必须在 docstring 注明。
- 验收：审计表定稿 + 后续任务照表执行（门禁）。**审计本身无代码，S 验证用于审计质量。**

#### TASK-028 — Bpc2sphere/Bsphere2pc 收敛 MarsCommon
- 类别：`U` `S` `R` `I`。
- `S`（核心）：转发前后合成输入**逐位一致**；球↔笛卡尔往返 `rel ≤ 1e-12`（物理可逆性）。
- `U`：新旧对外名（MAVEN_load/IGRF 转发别名）调用等价单测。
- `I`：坐标变换 → 下游（绘图/物理）链路回归（有 DLL 的 IGRF 路径 opt-in）。
- 验收：逐位一致 + 往返 rel ≤ 1e-12。

#### TASK-029 — bowshock/magnetopause 收敛 MarsCommon
- 类别：`U` `S` `R` `I`。
- `S`：网格对比（**isnan 感知**判定因 NaN32/NaN64 差异）——MarsCommon 权威版与各原实现（head.jl NaN32、MAVEN_plot NaN64、bowshock_zero 0.0）按各包装语义分别断言；`bowshock_zero` 保持返回 0.0（钳 0 语义）。
- `U`：`temp<0 → NaN` 边界；负/零/大距离输入边界。
- `I`：MAVEN_plot 绘图调用点回归（转发后不破坏绘图）。
- `R`：NaN 类型差异由 isnan 判等规避（不做 `==`）。
- 验收：isnan 感知网格等价 + 各包装语义断言 + 绘图调用点回归。

#### TASK-030 — SWEA shape 函数迁至 MAVEN_SWEA
- 类别：`U` `S` `R` `I`。
- `S`（核心）：迁移前后合成输入**逐位一致**（实现搬运不改值）。
- `U`：迁移后 `MAVEN_load.mean_SWEA_pad_pa === MAVEN_SWEA.mean_SWEA_pad_pa` 语义等价；转发别名调用测试。
- `I`：真实 SWEA（opt-in）回归；MAVEN_load 转发面向下游（绘图）链路。
- `R`：依赖闭包审计后（kp 相关助手）确保迁出不破坏 MAVEN_load 其余函数。
- 验收：逐位一致 + 语义等价 + 转发别名可用。

#### TASK-031 — static_c6 旧副本转发 + cyclone 转发
- 类别：`U` `S` `R` `B`。
- `S`（核心）：转发前后合成输入逐位一致（旧签名调用）；MAVEN_STATIC 版带 `:df` 输入新分支测试（超集行为）。
- `U`：转发别名绑定正确（`MAVEN_load.static_c6_mass_mean` 调用 MAVEN_STATIC 实现）；cyclone_* 映射按审计表（单位差异在 docstring 注明）。
- `R`：下游无形状/键依赖破坏（转发输出含 `:df` 分支确认无破坏）。
- `B`：**bench_04** 转发前后对比，证明无退化（R2）。
- 验收：逐位一致 + 新分支测试 + bench_04 无退化。**cyclone 单位差异必须审计后映射，否则退化为保留+注释。**

#### TASK-032 — 数学工具迁至 MarsCommon
- 类别：`U` `S` `R`。
- `S`：`polynomial_fit` 已知系数恢复测试（构造 `y=V·c`，断言拟合出 `c`）；迁入三函数（Vandermonde/polynomial_fit/vector_angle）合成输入逐位一致。
- `U`：迁入后 `using LinearAlgebra` 无缺失；转发别名（MAVEN_plot 对外名保留）。
- `R`：`logticks`/`interpolate_x_ticks` 留 MAVEN_plot（Makie 依赖）不受影响。
- 验收：系数恢复 + 逐位一致 + 转发可用。

#### TASK-033 — FunctionCoordinate 模块化
- 类别：`U` `S` `R` `I`。
- `S`：MINPA 往返自洽测试——`norm(sphere2xyz(xyz2sphere(p)) - p) ≈ 0`（文件内既有注释测试转正）；模块化前后合成输入逐位一致。
- `U`：`bowshock_zero` = MarsCommon.bowshock + 钳 0 包装断言（TASK-029 后）；注册表条目冒烟。
- `I`：TW_MINPA 引用模块版（私有副本删除）+ MAVEN_plot 内两处 slice2d（321/561）不强行统一（审计表登记）回归。
- 验收：往返自洽 + 逐位一致 + 注册冒烟。

#### TASK-034 — TimeFormat 合并 + load_quat 交叉引用
- 类别：`U` `R` `I`。
- `U`：两种 `format`（`:full` HH:MM:SS.mmm、`:mmss` MM:SS.mmm）输出与各自原实现**逐字符一致**；转发调用测试（Single_Particle_Orbit → MarsData.TimeFormat format=:mmss）。
- `R`：同输入双格式分别对比各自旧实现。
- `I`：两个 `load_quat` docstring 交叉引用存在性检查。
- 验收：双格式逐字符一致 + 转发可用。**非数值（字符串格式），S 豁免。**

### S9：脚本层迁移（ARCH-002/013）

#### TASK-035 — head.jl → MarsUtils 模块
- 类别：`U` `I` `R` `S`。
- `U`：`MarsData.@load MarsUtils` 冒烟——全部工具函数（safe_log_mean/color_mapping/label_data/get_log_ticks/solve_func 等 ~20 个）可访问；A4 大小写修复验证。
- `I`：`validate_registry` 绿 + 注册表条目 deps 正确。
- `R`/`S`：有数值逻辑的工具（`solve_func` 等）改动前后对比；`bowshock/magnetopause` 副本改 MarsCommon 转发（TASK-029 已证等价）。
- 验收：@load 冒烟 + validate_registry 绿 + 数值工具对比。

#### TASK-036 — Pickup_ion 函数化
- 类别：`U` `I` `S` `R`。
- `S`/`R`（核心）：入口函数 `pickup_ion_analysis` 合成输入冒烟（全分支 swi/sta/minpa）；真实事件（opt-in）新旧入口输出（points_data_df 等）**逐位一致**。
- `U`：入口签名覆盖 AR-5 全部外部变量（time_event/instrument_mode/spice_name/spice_dict/dtime/data/tw_minpa_data）；KP 访问从旧键（:vars/:var_190）迁到新 kp_dict 语义键；D:/ 回退 include 删除断言。
- `I`：旧全局 shim（预置全局 → 调用入口回填）兼容路径测试。
- `B`（可选）：入口重构影响主流程时一次性总耗时前后对比。
- 验收：全分支冒烟 + 新旧逐位一致（opt-in）+ shim 兼容 + D:/ 删除断言。

#### TASK-037 — Build_data/*.jl 迁移 @load
- 类别：`I` `R`。
- `I`：每文件（build_vsc/STATIC_VD/STATIC_vfd_3d/ngi整合）装载冒烟（不要求完整跑数据构建，opt-in）。
- `R`：脚本输出（派生数据）不走完整构建时以装载成功为准；有数据环境输出与旧 include 一致（opt-in）。
- 验收：逐文件装载冒烟成功。

#### TASK-038 — example/*.jl 迁移 @load（可选）
- 类别：`I` `R`。
- `I`：两脚本端到端运行无异常（图产物 gitignored，不比较像素）。
- `R`：KP_l3 兼容回退（TASK-040 已就位）下行为不变。
- 验收：端到端无异常。

### S10：绘图与 API 面（ARCH-012/010）

#### TASK-039 — plot_module 面板化
- 类别：`U` `I` `R` `B`。
- `U`：合成 data_dict 逐面板（11 个 panel_*! + _require）独立冒烟；缺失键错误信息断言（含面板名与键路径，如"面板 density 需要 data_dict[...][:epoch]，缺失"）。
- `I`：`plot_module` 装配器签名与输出不变（example 端到端）。
- `R`：拆分后对合成 data_dict 无异常 + 面板数量回归。
- `B`：**bench_06** 拆分前后对比，不得慢于基线 110%（硬门）。
- 验收：逐面板冒烟 + 缺失键断言 + example 端到端 + bench_06 不慢于 110%。

#### TASK-040 — KP 键归一（_get_kp 回退）
- 类别：`U` `I` `R`。
- `U`：仅 `"KP"` / 仅 `"KP_l3"`（@warn 触发断言）/ 双键 三种输入行为测试。
- `I`：plot_module 内部 KP 读取改走 `_get_kp` 后 example 端到端。
- `R`：例文脚本（仍写双键）继续可用（兼容期）。
- 验收：三态行为断言 + example 端到端。**非数值，S 豁免。**

#### TASK-041 — 别名层收尾 + export 死名清理
- 类别：`U` `R`。
- `U`：别名调用与旧名结果一致测试（`alfven_wave`/`calculate_minimum_energy`/`calculate_SWEA_pad` 已有则复跑）；export 死名 `WaveSpactra_heatmap` 清理后无导出断言。
- `R`：白名单机制下 export 清理不破坏 `@load`（回归）。
- 验收：别名一致 + export 清理绿。

#### TASK-042 — 白名单补全
- 类别：`U` `I` `R`。
- `U`：每模块 `@load` 冒烟 + 逐名引入测试（runtests 扩展——16 个空白名单模块的 allow 逐个可裸名调用）。
- `R`：`_apply_allow!` 冲突即报错（现有机制保护）回归。
- `I`：全模块白名单补全后 example/脚本层裸名调用路径。
- 验收：逐模块冒烟 + 逐名引入绿。

### S11：清理（ARCH-016）

#### TASK-043 — 死代码与演进痕迹清理
- 类别：`U` `R`。
- `R`：删除前后 runtests 全绿（既有测试仍通过）；`grep "^\s*#"` 抽查无残留测试块。
- `U`：保留"参考 IDL/SPEDAS"类注释存在性抽查（防误删参考注释）。
- 验收：runtests 绿 + grep 抽查。

### 条件性性能任务（ARCH-014，全部带门——门未满足不许硬做，在 06 记录决策）

#### TASK-044 — sta_v_4d/_new 等价证明与收编【CONDITIONAL】
- 类别：`S`（等价门）`R` `B`。
- `S`（门）：合成切片 `sta_v_4d` vs `sta_v_4d_new` 输出网格 rel ≤ 1e-9（逐元素相邻点差与阈值）；**不等价 → 跳过任务，保留双版本、记录差异、上报科学负责人**。
- `R`：等价性回归测试固化（合成切片 rel ≤ 1e-9），收编后 `sta_v_4d` 调用 new 实现保持旧签名/返回。
- `B`：**bench_03 前后成对对比为强制证据（R2）**，记录等价性证明与计时。
- 验收：等价证明 rel ≤ 1e-9 入档 + bench_03 成对 + 收编后回归绿。**等价未证即失败，禁止删旧版。**

#### TASK-045 — STATIC 热点轻量 struct 包装【CONDITIONAL】
- 类别：`S` `R` `B` `U`。
- `S`：数值**逐位一致**回归（`_extract_slice(dat)` 提取 + 类型稳定包装后输出不变）——基准为 TASK-044 收编后 sta_v_4d_new 输出。
- `U`：类型假设（Float32 三维数组）断言防错；`_extract_slice` 返回 NamedTuple 形状校验。
- `B`/门：bench_03 显示 Dict 访问开销占比 ≥ 可测阈值（如总耗时 >10%）——门证据；改动前后 bench_03 成对对比（强制 R2）。
- 验收：逐位一致 + 门证据入档 + 成对基准。**公开 API 不变（仍接受 Dict）。**

#### TASK-046 — STA_count2df_all 向量化【CONDITIONAL】
- 类别：`S` `R` `B` `U`。
- `S`：新旧实现合成输入**逐位一致**（索引展开 swp/att/eff 三索引正确）；输出键与形状不变。
- `U`：预分配 + @views 单遍构建的边界（小/空输入）断言。
- `B`/门：bench_02 证明当前耗时显著（相对下游矩不可忽略）——门证据；改动前后 bench_02 成对对比（强制 R2）。
- 验收：逐位一致 + 门证据 + 成对基准。

#### TASK-047 — plot_module 微优化【CONDITIONAL】
- 类别：`R` `S` `B` `I`。
- `S`/`R`：绘图行为不变是硬约束——example 端到端 + 单面板冒烟（不比较像素，无异常为证）。
- `U`：time2x 同区间一次计算复用的结果与重复二分一致。
- `B`/门：bench_06 显示合成耗时 > 明显阈值（门证据）；优化后**不得慢于基线 110%**（硬门）。
- 验收：端到端无异常 + 结果一致 + bench_06 不慢于 110%。

#### TASK-048 — IGRF ccall 边界评估【CONDITIONAL/评估】
- 类别：`S` `R` `B`。
- `S`（核心）：缓冲复用前后追踪输出**逐位一致**（工作区缓冲复用无算法变化）；确认 DLL 无内部状态依赖。
- `U`：预分配 path/B_result 无越界断言。
- `B`：**bench_07 分解对比（强制 R2）**——ccall 自身 vs 分配 vs 循环的耗时占比评估报告。
- 状态：**任何 Julia 端球谐移植/批量 ccall 接口替换 = R5，仅评估并上报，未经批准禁止实施**（03 §15/红线）。
- 验收：评估报告入档 + 逐位一致（若做缓冲复用）+ R5 上报不越界。

---

## 4. 综合验收门（PHASE 7 全量验证入口 + 每任务绿灯）

### 4.1 全量测试运行门（每任务完成即跑）

| 命令 | 覆盖 | 通过标准 |
| --- | --- | --- |
| `julia --project=. test/runtests.jl` | 全部 U/I/R/S 测试（分层 testset 已在 runtests 聚合） | 零失败；`Sys.iswindows()`/数据缺失的显式 `@test_skip` 除外 |
| `julia --project=benchmark benchmark/golden_snapshot.jl`（秒级一致性检查） | 快照 vs 当前数值回归（S/R） | 逐位一致（或可论证容差） |
| 各 benchmark 脚本成对对比脚本 | B 类（TASK-013/031/039/044–048） | 波动阈值（≤110% 上限 / R2 成对） |
| `grep -n "^\s*#"`（ARCH-016 清理） | 死代码清理（TASK-043） | 无残留测试块 |

### 4.2 每任务绿灯汇总表（PHASE 6 执行清单）

| TASK | 类别 | 核心验收（绿即完成） | 关联门 |
| --- | --- | --- | --- |
| 001 | U/R/S/B | 快照可复现 + 形状断言 + 首份基线 | — |
| 002 | U/I/R | 无残留引用 + 装载冒烟 | — |
| 003 | U/R/S | 默认=m16 逐位 + 形状/量级 | — |
| 004 | U/I/R | :B 与 "B" 兼容 + 全链路 | — |
| 005 | U/I | findlast + 缺 END 报错 | — |
| 006 | U/I/R | error_report 聚合 + @warn + 默认回归 | — |
| 007 | U/I/R | 无文件装载 + 有文件逐键一致 | A1 解除 |
| 008 | R/S/B | 真实快照可复现 + 基线入档（缺数据 opt-in 记录） | S0b |
| 009 | U/I/R | 无副作用装载 + 有配置一致 | — |
| 010 | U/I | 无数据装载 + mock 根读取 | — |
| 011 | U/S/I | 缺失路径报错 + DLL 数值一致(opt-in) | — |
| 012 | U/I/R | 55 键一一对应 + 一日回归 | — |
| 013 | U/I/R/B | 命中一致 + bench_05 成对 | R2 |
| 014 | U/I | 单独 include + 全下游 | — |
| 015 | U/I | 两类新校验 + 注册表全绿 | — |
| 016 | U/I/R | 附录 A 抽查 | — |
| 017 | U/R | 写新键安全 | — |
| 018 | U/R/S | 逐位一致 + 手算解析值 | R4 |
| 019 | U/S/I | coarse/fine 双输入 + 密度正 + 形状 | C5 修复 |
| 020 | U/S/R/I | to_pc 可用 + 往返 rel≤1e-12 | C2 |
| 021 | U/S/I/B | 默认逐位 + 三支路 + bench_07 | C1 决策 |
| 022 | U/R | 逐位一致 + 常量/注释 | C10 |
| 023 | R/S | 注释存在 + 06 对照表 | C6/7/11/12/13 不改值 |
| 024 | U/S/I/R | 网格 rel≤1e-12 + 报错 + 并行隔离 | C8 状态搬运 |
| 025 | U/R/I | 默认一致 + 自定义生效 + 兼容 | C15 |
| 026 | U/S/I/R | 默认逐位 + 并行隔离 | AR-4 |
| 027 | R/S | 审计表定稿 + 单位核对 | 门禁 028–034 |
| 028 | U/S/R/I | 逐位 + 往返 rel≤1e-12 | B3 |
| 029 | U/S/R/I | isnan 感知等价 + 各包装语义 | B4 |
| 030 | U/S/R/I | 逐位 + 语义等价 + 转发 | AR-17 |
| 031 | U/S/R/B | 逐位 + 新分支 + bench_04 无退化 | B2/B8 |
| 032 | U/S/R | 系数恢复 + 逐位 + 转发 | B9 |
| 033 | U/S/R/I | 往返自洽 + 逐位 | B5 |
| 034 | U/R/I | 双格式逐字符 + 转发 | B6/B7 |
| 035 | U/I/R/S | @load 冒烟 + validate 绿 + 数值工具对比 | AR-1 |
| 036 | U/I/S/R | 全分支冒烟 + 新旧逐位(opt-in) + shim | AR-5 |
| 037 | I/R | 逐文件装载冒烟 | — |
| 038 | I/R | 端到端无异常 | — |
| 039 | U/I/R/B | 逐面板 + 缺失键 + example + bench_06 | AR-16 |
| 040 | U/I/R | 三态行为 + example | C17 |
| 041 | U/R | 别名一致 + export 清理 | AR-10 |
| 042 | U/I/R | 逐模块冒烟 + 逐名引入 | AR-13 |
| 043 | U/R | runtests 绿 + grep 抽查 | AR-29 |
| 044 | S/R/B | 等价 rel≤1e-9 + bench_03（不等价即失败） | AR-11 门 |
| 045 | S/R/B/U | 逐位 + 门(>10%)证据 + 成对 | AR-22 门 |
| 046 | S/R/B/U | 逐位 + 门证据 + 成对 | AR-22 门 |
| 047 | R/S/B/I | 端到端 + bench_06 ≤110% | AR-22 门 |
| 048 | S/R/B | 逐位 + bench_07 分解 + R5 上报 | AR-23 门 |

### 4.3 环境门（fresh clone 冒烟）

| 场景 | 必须通过 |
| --- | --- |
| 无 E:/、无 settings.toml、无 filename_lists.json（fresh clone） | `using MarsData` + `test/runtests.jl` 全绿 |
| 有数据 + 有 DLL（opt-in） | 科学回归套件绿（S 类 + bench_01/08） |
| Windows + DLL | IGRF 系列测试跑通；非 Windows `@test_skip` 显式标注（03 风险 #5） |

---

## 5. 风险与测试覆盖的对应

| 03 风险 | 测试缓解（本文件对应任务/类别） |
| --- | --- |
| 1. 科学漂移 | S0 golden + 每 S 任务 R4 对比 + 逐位/rel 阈值（TASK-018/019/020/022/028/029/030/031/024/026） |
| 2. head.jl 生态断裂 | MarsUtils @load 冒烟 + 数值工具对比（TASK-035）+ Pickup shim（036） |
| 3. 真实数据不可得 | opt-in 设计 + 合成基线兜底 + 06/07 显式 blocked 标注不假装通过（TASK-008 等） |
| 4. sta_v_4d 不等价 | 等价门 rel≤1e-9 + 双版本保留（TASK-044） |
| 5. DLL 依赖 | `Sys.iswindows()` + `@test_skip`；纯 Julia 路径不依赖 DLL（003/004/021/026/028） |
| 6. Pickup 隐式全局遗漏 | AR-5 清单 + 入口签名覆盖 + 新旧对比兜底（TASK-036） |
| 7. 白名单冲突 | 逐名引入冲突即报错（TASK-042） |
| 8. Makie 升级 | Manifest 锁定 + example 冒烟（038/039/040） |
| 9. JSON 键漂移 | 55 键一一对应校验（TASK-012）+ validate_registry（015） |
| 10. 迁移顺序颠倒 | §4.2 绿灯门禁 + 依赖排序执行 |

---

## 6. 只读合规声明

- 输入：`.agent/01_PROJECT_MAP.md`、`.agent/02_ARCHITECTURE_REVIEW.md`、`.agent/03_ARCHITECTURE_PLAN.md`、`.agent/04_OPTIMIZATION_PLAN.md`（只读引用，未改动）；`test/runtests.jl` 定点读取（既有测试基座）。
- 本阶段定点读取源码/测试文件：`test/runtests.jl`（全文）；`03`/`04`（全文）。未重新全仓扫描。
- 写入：仅 `.agent/05_TEST_STRATEGY.md`（覆盖占位符）。
- 未修改任何源码、数据、配置文件；未执行全仓扫描。