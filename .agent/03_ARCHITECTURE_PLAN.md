# 03_ARCHITECTURE_PLAN.md — PHASE 3：架构规划（重构方案与分阶段计划）

> 状态：DONE
> 阶段：PHASE 3 - Architecture Planning
> 负责：DeepSeek V4 Pro (Scientific Architect / Performance Architect)
> 依赖：`.agent/00_PROJECT_SCOPE.md`、`.agent/01_PROJECT_MAP.md`、`.agent/02_ARCHITECTURE_REVIEW.md`（已完成的正式输入，未改动）
> 性质：**只读规划**。本阶段不修改任何源码，仅在 `.agent/` 下覆盖本文件。
> 编号体系：本文档产出架构变更编号 `ARCH-nnn`，供 PHASE 4–9 引用；问题编号引用 02 文档的 `AR-n` 与 01 文档的调查区编号（A/B/C/D）。
> 关键约定：任何架构变更先问"实际收益"，禁止为『架构漂亮』做无收益重构；重大科学算法调整方案在本文件 §15 定稿，实现阶段不得自行决策（R5）。

---

## 0. 本文档如何使用

- §1–§4：现状 → 问题 → 目标 → 论证（决策依据）。
- §5–§9：模块边界 / 数据流 / API / 迁移清单 / 红线（实施输入）。
- §10：迁移顺序（PHASE 6 实施步骤的权威排序）。
- §11–§13：风险、测试要求、Benchmark 要求（PHASE 5/7 验收标准）。
- §14：文档影响；§15：重大科学决策逐项定稿（R4/R5 合规核心）；附录 A：数据键契约表。
- `ARCH-nnn` 全表见 §3.2；每个变更的细节以 §3.3 条目为准，其余章节只引用编号。

---

## 1. Current Architecture（当前架构）

三层 + 两套装载体系（详见 01 §2–§4、02 §2，此处为结论摘要）：

```
L0 包层  MarsData（[deps] 15 个轻量依赖；无数据/无 DLL 环境可 using）
   ├─ Paths（TOML 优先/INI 只读兼容，路径单一出处；preloaded）
   ├─ load_registry / data_model / load_index（读 MAVEN_data_format.json / filename_lists.json）
   ├─ MAVEN_plot 子模块（1554 行绘图基元，内含自拷 constants/MarsCommon；preloaded）
   ├─ plotting.jl（plot_module：12 面板硬绑定 data_dict 键）
   └─ modules.jl（MODULE_REGISTRY 19 条目 / load_module / @load / 白名单 / 运行时载体机制）
L1 载体模块层  19 个注册模块（load_module 在 _MarsDataLoader 载体内 Base.include，
              重依赖经 LOAD_PATH 回退解析；const 别名绑定进 MarsData）
   constants ← MarsCommon ← {MAVEN_load, MAVEN_STATIC, MAVEN_SWIA, MAVEN_SWEA,
   MGS_load, TW_load, TW_MINPA, calculate_models, IGRF_calculate, Cold_Plasma_*,
   Maxwellian_*, Single_Particle_*, SP_load, Call_fortran_dll}
L2 脚本层  include 进 Main（无 module）
   head.jl（双重身份：顶部裸 include 6 个重模块 + 科学辅助函数库）
   function_coordinate.jl、Pickup_ion.jl、Octree.jl、Graham.jl、
   MAVEN_data/Build_data/*.jl、example/*.jl（相对路径 include）
```

关键运行事实（01/02 已确认）：
1. **两套装载体系并存**：`MarsData.load_module`（载体）与 `head.jl` 裸 include（Main）可以装载同一模块的两份实例，全局状态（kp_dict 等）各自独立（AR-1）。
2. **模块加载期 IO**：`MAVEN_load` 加载期无条件 `open(filename_lists.json)`（fresh clone 必崩，A1）；`SP_load` 加载期读 INI + `println`；`IGRF_calculate` 加载期读 gh_gao 并预计算 Schmidt 系数。
3. **字符串反射分派**：`eval(Meta.parse(value[4]))` 把 JSON 字符串变函数引用（A9/AR-14）。
4. **全局可变状态**：kp_dict（+change_kp_read_data）、set_particles（Nparticles/Ω_n/Π_2）、B_compress（+set_B_compress）——函数结果依赖"之前调用了什么"（AR-4）。
5. **数据契约即键名**：`Dict{Symbol,Any}` 全链路传递，键名/形状约定散落 20+ 文件（AR-7/AR-8）；`:time` vs `:epoch`、"B" vs :B、KP_l3 vs KP 双键等不一致已是定时炸弹。
6. **科学计算与读取混层**：MAVEN_load（1471 行 God module）含旧 static_c6 副本、cyclone_*、Bpc2sphere 副本、SWEA shape 函数等（AR-17）。
7. **零 benchmark、零科学自动化测试**（AR-21/AR-26）。

---

## 2. 当前架构存在的问题（引用 02 的 AR-n 编号）

按 02 §13 的优先级总表引用，不重复细节：

| 优先级 | AR 编号 | 问题一句话 | 对应 ARCH |
| --- | --- | --- | --- |
| P0 | AR-2/AR-25 | filename_lists.json 加载期无条件 open，fresh clone 与 runtests 冒烟崩溃（A1） | ARCH-001 |
| P0 | AR-28 | 三份坏死的 calculate_mag/caculate_mag（引用未初始化全局 data，B1） | ARCH-007 |
| P0 | AR-12 | STA_count2eflux/STA_eflux2df 默认参数 `m_int=m_int` → UndefVarError | ARCH-007 |
| P0 | AR-8 | get_mag_line_s 读 `"B"`、trace_mag_line 产 `:B` → KeyError（C3） | ARCH-007 |
| P1 | AR-20 | 磁力线默认一阶 Euler（C1）：系统误差 + 决策被硬编码 | ARCH-008 |
| P1 | AR-18 | 硬编码物理/仪器常数无出处（C4/C5/C6/C10/C11） | ARCH-008 |
| P1 | AR-11 | sta_v_4d vs sta_v_4d_new 双版本无等价证明 | ARCH-014 |
| P1 | AR-2 | IGRF/SP_load 加载期 IO（A3） | ARCH-005 |
| P2 | AR-1 | 两套装载体系：head.jl/Pickup_ion/Build_data 绕过包管理器（A4/A5） | ARCH-002/ARCH-013 |
| P2 | AR-4/AR-27 | 全局可变状态：kp_dict/set_particles/B_compress（C8/C15） | ARCH-009 |
| P2 | AR-7/AR-8 | Dict{Symbol,Any} 无 schema；键名不一致清单 | ARCH-011 |
| P2 | AR-14/AR-15 | eval 反射注册 + 线性子串文件匹配 + 静默失败（A9） | ARCH-004/ARCH-007 |
| P2 | AR-21/AR-26 | 零 benchmark 基线；零科学自动化测试（D1/D2） | ARCH-014/ARCH-015 |
| P2 | AR-3 | 模块 include 策略两套真相（self-include 与 `using ..parent` 混用） | ARCH-003 |
| P2 | AR-6 | 同物理量多份实现：Bpc2sphere/cyclotron/bowshock/static_c6/slice2d/load_quat/TimeFormat（B2–B9） | ARCH-006 |
| P2 | AR-16 | plot_module 对 data_dict 硬绑定 12 面板 + 双键补丁（C17） | ARCH-012 |
| P2 | AR-5 | Pickup_ion 隐式全局契约（十余个外部预置变量） | ARCH-013 |
| P3 | AR-7 | 热点数据结构 schema 化（STATIC 矩轻量 struct） | ARCH-014（PHASE 4） |
| P3 | AR-10/AR-13 | 拼写错误固化 + 白名单覆盖不足（A7/C16） | ARCH-010 |
| P3 | AR-29 | 死代码与演进痕迹（注释测试块、注释旧版） | ARCH-016 |
| P3 | AR-30/D3 | 文档滞后（KP_l3/MAG_pc1s_l3 已下架、无键契约文档） | ARCH-017 |

已登记但**不做**（既定设计/无收益，见 §9 红线）：AR-24/A10（包加载含 MAVEN_plot，README 既定）、C14（docstring 已注明近似）、C16（JSON 拼写键，重命名收益低）、C20（requirement.jl 与 [deps] 不同步，既定）。

---

## 3. Target Architecture（目标架构）

### 3.1 目标层结构

```
L0 包层  MarsData（机制不变；+DataKeys 契约模块 preloaded）
   Paths → DataKeys → load_registry/data_model/load_index → MAVEN_plot → plotting → modules
L1 载体模块层（19+3 注册模块；统一自包含 include；无加载期 IO（版本化 JSON 除外）；
   全部状态显式参数化；读取/处理/物理三层职责）
   common:   constants / MarsCommon(+数学工具) / DataKeys / FunctionCoordinate(新注册) / MarsUtils(新注册)
   读取:     MAVEN_load / TW_load / MGS_load / SP_load —— 只做读取与格式解析
   仪器处理: MAVEN_STATIC / MAVEN_SWIA / MAVEN_SWEA / TW_MINPA —— 只做矩/换算（含迁入的 SWEA shape 函数）
   物理:     IGRF_calculate / Cold_Plasma / Maxwellian / Single_Particle_Orbit / calculate_models
   ccall:    Call_fortran_dll（路径经 Paths 解析）
L2 脚本层（不再是装载体系，只是入口编排）
   Pickup_ion.jl：函数化 + @load（保留全局变量 shim 兼容旧工作流）
   Octree.jl / Graham.jl：保持独立脚本（不改）
   Build_data/*.jl / example/*.jl：include → MarsData.@load
```

### 3.2 架构变更总表（ARCH-001 … ARCH-017）

| ID | 标题 | 引用 AR | 优先级 | 主要落地 |
| --- | --- | --- | --- | --- |
| ARCH-001 | 加载期 IO 惰性化与缺省回退（filename_lists） | AR-2/AR-25/A1 | P0 | PHASE 6 S1 |
| ARCH-002 | 统一装载体系：head.jl 拆分 → MarsUtils；脚本层全部走 @load | AR-1/A4/A5 | P2 | PHASE 6 S9 |
| ARCH-003 | include 策略统一（自包含）+ validate_registry 扩展 | AR-3 | P2 | PHASE 6 S4 |
| ARCH-004 | 显式装载函数注册表（去 eval）+ 文件定位日期索引化 | AR-14/A9 | P2 | PHASE 6 S3 |
| ARCH-005 | 路径解析单一出处推广（TW/MGS/SP_load/Call_fortran_dll） | AR-2/A2/A3/A6 | P1 | PHASE 6 S2 |
| ARCH-006 | 重复实现去重与权威实现归属（含 FunctionCoordinate 模块化） | AR-6/B2–B9 | P1 | PHASE 6 S8 |
| ARCH-007 | P0 修正包（坏函数删除/m_int/键不一致/findlast/错误聚合） | AR-12/AR-28/AR-15/A8/C3 | P0 | PHASE 6 S1 |
| ARCH-008 | 科学疑点修正与验证协议（C1/C2/C4/C5/C10；其余记录不改值） | AR-18/AR-20 | P1 | PHASE 6 S6 |
| ARCH-009 | 全局可变状态显式参数化（PlasmaState/kp_columns/B_compress 变体） | AR-4/AR-27/C8/C15 | P2 | PHASE 6 S7 |
| ARCH-010 | 兼容别名层 + 白名单补全 + export 死名清理 | AR-10/AR-11/AR-13/A7 | P3 | PHASE 6 S10 |
| ARCH-011 | 数据键契约中心化（DataKeys 模块 + 契约表 + 就地修改约定） | AR-7/AR-8/AR-9 | P2 | PHASE 6 S5 |
| ARCH-012 | 绘图管线面板化 + KP 键归一（兼容回退） | AR-16/C17 | P2 | PHASE 6 S10 |
| ARCH-013 | Pickup_ion 函数化（显式入口 + 全局 shim + 去硬编码路径） | AR-5/A5 | P2 | PHASE 6 S9 |
| ARCH-014 | Benchmark 基线（6+2 项）与 sta_v_4d 等价性门 | AR-21/AR-22/AR-23 | P2 | PHASE 4 方案 / PHASE 6 S0 执行 |
| ARCH-015 | 测试基座（单测/fixtures/科学回归/无数据环境） | AR-25/AR-26/AR-27 | P2 | PHASE 5 方案 / PHASE 6 逐步落地 |
| ARCH-016 | 死代码与演进痕迹清理 | AR-29 | P3 | PHASE 6 S11 |
| ARCH-017 | 文档同步（契约表/api/data_reading/README/CHANGELOG） | AR-30/D3 | P3 | PHASE 8 |

### 3.3 各变更条目细节

#### ARCH-001 加载期 IO 惰性化与缺省回退
- 目标：`load_module(:MAVEN_load)` 在 fresh clone 上成功；任何"干净环境"测试可开始。
- 变更内容（定稿）：
  1. `MAVEN_load.jl:1460-1462` 的加载期 `open(filename_lists.json)` 删除；新增惰性访问器
     `filename_list()::Dict{String,Any}`：`isfile(Paths.index_path())` 时 JSON.parse，否则返回 `Dict{String,Any}()`。
     内部使用者（`file_list`/`find_file_of_data`）一律改走访问器。
  2. `MAVEN_data_format.json` 保留加载期解析（**决策理由**：该文件随仓库版本控制、缺失即仓库损坏；
     55 产品的注册表语义与模块装载同生共死；改为惰性只会把失败推迟到首次调用且无缺省值可回退）。
  3. `IGRF_calculate` 的 `const GG,HH = read_gh()` 与 Schmidt 预计算**保持加载期执行**
     （gh_gao 随仓库、且 const 声明是 ccall 热路径免装箱的性能前提；惰性化收益为负）。
  4. `SP_load` 的 INI 加载期读取随 ARCH-005 移除。
- 涉及文件：`MAVEN_data/MAVEN_load.jl`。
- 验证：fresh clone（无 E:/、无 settings.toml、无 filename_lists.json）`load_module(:MAVEN_load)` 与 `test/runtests.jl` 全绿；有 filename_lists.json 时行为与改动前逐位一致。

#### ARCH-002 统一装载体系
- 目标：全仓只剩 `load_module/@load` 一条装载路径；head.jl 失去"装载器"身份。
- 变更内容（定稿）：
  1. `common/head.jl` 顶部装载块（28–36 行）删除；第 36 行以后的科学辅助函数库 + `label_data` 表
     包化为新注册模块 `MarsUtils`（`module MarsUtils … end` 包裹，文件名不变：`common/head.jl`）。
     注册表新增条目 `:MarsUtils => _spec(:MarsUtils, "common/head.jl", …; deps=[:constants,:MarsCommon])`。
     顺带修复 A4（`Maxwellian_Distribution` → `Maxwellian_distribution` 大小写）——该行随装载块一并消失。
  2. `models/Pickup_ion.jl` 顶部裸 include 改为 `MarsData.@load MAVEN_load MAVEN_plot MAVEN_STATIC MAVEN_SWIA Maxwellian_Distribution MarsUtils FunctionCoordinate`（与 ARCH-013 同步）。
  3. `MAVEN_data/Build_data/*.jl`、`example/MAVEN_plot_sample/*.jl` 的相对路径 include 改为 `MarsData.@load`（P3，逐文件小步）。
- 涉及文件：`common/head.jl`、`models/Pickup_ion.jl`、`MAVEN_data/Build_data/*.jl`、`example/*.jl`、`src/modules.jl`（仅注册表）。
- 验证：`MarsData.@load MarsUtils` 后全部工具函数可用；Pickup_ion 新旧入口同事件输出一致；`validate_registry` 空问题。
- 注意：head.jl 内 bowshock/magnetopause 副本按 ARCH-006 处理；label_data 依赖 Makie.rich，经载体 LOAD_PATH 解析（与现状一致）。

#### ARCH-003 include 策略统一 + validate_registry 扩展
- 目标：消除"声明式 deps 与实际 include 依赖两套真相"（AR-3）。
- 变更内容（定稿，选**自包含模式**而非 deps 相对引用模式——改动面最小、直接 include 到 Main 的旧用法仍然可用）：
  1. 统一为：**每个注册模块自包含**（需要 constants/MarsCommon/Paths/FunctionCoordinate 就自己 `include(joinpath(@__DIR__, …))`）。
  2. 删除唯一一处父模块相对引用：`common/MarsCommon.jl:2` 的 `using ..constants` → 改为自包含 include。
     （此改后 MarsCommon 不再依赖装载顺序，`include("common/MarsCommon.jl")` 直接可用。）
  3. `validate_registry` 扩展两项校验：
     a. 文件内若出现 `using ..X`，则 X 必须声明在 `deps` 中（否则报问题）；
     b. 文件内自包含 `include(.../X.jl)` 时，X 若也在 `deps` 中给出警告级提示（冗余但无害），
        用于把注册表 deps 收敛为"文档化语义依赖"。
  4. 注册表 deps 语义改为"文档化依赖声明"（不参与装载去重，仅用于拓扑/提示）；装载逻辑不动。
- 涉及文件：`common/MarsCommon.jl`、`src/modules.jl`（仅 validate_registry + 注释）。
- 验证：`validate_registry()` 返回空；`load_module(:MarsCommon)` 单独装载冒烟；runtests 绿。

#### ARCH-004 显式装载函数注册表 + 文件定位索引化
- 目标：JSON 不再是代码入口；文件匹配从 O(N×M) 线性子串变为 O(1) 日期索引（保留子串回退）。
- 变更内容（定稿）：
  1. 在 `MAVEN_load.jl` 内新增显式函数表（代码内构建，唯一真相）：
     ```julia
     const LOADER_FUNCS = Dict{String,Function}(
         "load_cdf" => load_cdf, "load_mag_l2" => load_mag_l2, "load_kp" => load_kp,
         # …覆盖 MAVEN_data_format.json data_model 全部 55 个产品的 value[4] 字符串
     )
     ```
     加载期构建 `read_models[key] = (value[3], LOADER_FUNCS[value[4]])`；
     `value[4]` 不在表中时**加载即抛清晰错误**（列出键与缺失函数名），不再 `eval(Meta.parse(...))`。
     **JSON 文件本身一字不改**（Python 生成端 out of scope；55 个函数名字符串保持原拼写）。
  2. 文件定位：新增每模型惰性日期索引 `_file_index(model)::Dict{String,Vector{String}}`，
     首次调用时从 `filename_list()[model]` 用正则 `\d{8}` 提取日期（优先取末次出现的最长 8 位数字串），
     `find_file_of_data` 改为：先精确索引命中 → 未命中回退原 `occursin` 子串线性扫描（行为兼容）。
  3. `find_file_of_data`/`file_list` 内部不再每次广播拼接全路径（复用索引缓存）。
- 涉及文件：`MAVEN_data/MAVEN_load.jl`（含 docstring 更新）。
- 验证：55 产品全部键与函数表一一对应（新校验测试）；1000 文件列表索引化前后命中结果一致（对比测试）+ 计时基准（ARCH-014 第 5 项）；`load_MAVEN_data` 一日 golden 回归。

#### ARCH-005 路径解析单一出处推广
- 目标：TW/MGS/SP_load/Call_fortran_dll 全部经 Paths 解析；消除换机即失效。
- 变更内容（定稿）：
  1. `TW_data/TW_load.jl:7`、`TW_data/TW_MINPA.jl:10`、`MGS_data/MGS_load.jl:6`：
     硬编码 root_path 删除，改为自包含 include paths.jl + `root_path = Paths.tw_data_root()/Paths.mgs_data_root()`（函数化惰性取值，避免加载期依赖）。
  2. `support_data/support_data_load.jl:12-14`：加载期 INI 读取与 `println` 删除；
     `root_path = Paths.maven_data_root()`；`support_datas` 子路径在 `load_omni2_data`/`load_drivers_merge_data` 内部拼装。
  3. `call_fortran_dll.jl`（A6）：DLL 路径解析收敛到 Paths：
     - `linear_growth_rate.dll`：按 `config/settings.toml` 可选键 `paths.fortran_dll_dir`（Julia 侧只读，
       不改 example.toml、不生成配置）→ 缺省回退仓库根 `Magnetic_Model/` 同目录查找 → 再回退旧硬编码路径（@warn 一次）→ 仍缺则调用时抛含指引的清晰错误；
     - `Bspline.dll`：先仓库根、再 CWD（现状）、再报错。
- 涉及文件：`TW_data/TW_load.jl`、`TW_data/TW_MINPA.jl`、`MGS_data/MGS_load.jl`、`support_data/support_data_load.jl`、`call_fortran_dll.jl`、`common/paths.jl`（仅新增只读可选键解析函数，默认值兜底不变）。
- 验证：无数据环境三个模块可装载；有数据环境读取输出与改动前逐位一致；DLL 缺失时错误信息含配置指引。

#### ARCH-006 重复实现去重与权威实现归属
- 目标：同一物理量只保留一份实现（科学一致性 > 一切），其余转转发别名。
- 前置动作（实现第一步）：**签名与单位审计表**——对每个去重对，列出全部调用点与输入单位，审计通过才允许转发。
- 定稿权威归属与转发关系：

| 函数 | 权威实现落点 | 其他位置处理 |
| --- | --- | --- |
| Bpc2sphere/Bsphere2pc（B3） | **MarsCommon**（纯坐标变换；带 `::Real` 标注） | MAVEN_load、IGRF_calculate 改转发别名（删除副本） |
| bowshock/magnetopause（B4，Edberg 2008） | **MarsCommon**（输入约定：R_Mars 归一化距离，与 Pickup_ion 现用法一致；km 输入另提供 `bowshock_km` 显式命名） | MAVEN_plot 转发别名（绘图 API 不变）；head.jl/function_coordinate 副本随 ARCH-002/模块化删除；function_coordinate.bowshock_zero 改转发 |
| slice2d_cal_rot（B5） | common/function_coordinate.jl 现实现（SVector 防共线版）→ 该文件包化为注册模块 **FunctionCoordinate** | TW_MINPA 私有副本删除，改自包含 include FunctionCoordinate |
| static_c6_mass_mean/energy_mean（B2） | MAVEN_STATIC 新版（含 :df 分支） | MAVEN_load 旧副本删除，改转发别名（对外名保留；行为为旧输入的超集，无破坏） |
| cyclone_frequency/cyclone_R（B8） | calculate_models.cyclotron_frequency/cyclotron_radius | MAVEN_load 转发别名；Single_Particle_Orbit 内部用法先审计（若签名/单位不符则保留其私有 helper 并注明，不强行转发） |
| load_quat（B6，同名不同义） | **不合并**（读取层返回 Dict、SWEA 返回 Matrix，语义不同） | docstring 双向交叉引用 + 契约表登记；无代码改动 |
| TimeFormat（B7，两种格式） | MAVEN_plot.TimeFormat 增 `format` kwarg（默认保持现 HH:MM:SS.mmm） | Single_Particle_Orbit 改转发并显式传其原格式；输出逐位对比测试 |
| Vandermonde/polynomial_fit/vector_angle/logticks/interpolate_x_ticks（B9） | **MarsCommon**（纯数学） | MAVEN_plot 转发别名（绘图 API 不变） |
| calculate_mag ×3（B1） | —（坏死） | 删除（属 ARCH-007） |

- 涉及文件：`common/MarsCommon.jl`、`common/function_coordinate.jl`（包化）、`MAVEN_data/MAVEN_plot.jl`、`MAVEN_data/MAVEN_load.jl`、`TW_data/TW_MINPA.jl`、`Magnetic_Model/IGRF_calculate.jl`、`models/Single_Particle_Orbit.jl`、`calculate/calculate_models.jl`、`src/modules.jl`（注册 FunctionCoordinate）。
- 验证：每个转发对做**数值等价测试**（合成输入，rel ≤ 1e-12）；全部现有调用点回归；runtests 绿。等价性未证明前禁止删副本（保留双实现 + 测试对比，直到 PHASE 7 验证报告确认）。

#### ARCH-007 P0 修正包
- 目标：消灭必崩路径与确定性 bug；错误可审计。
- 变更内容（定稿）：
  1. 删除三份坏死函数：`MAVEN_load.calculate_mag`（923-932）、`TW_load.calculate_mag`（128-137）、`MGS_load.caculate_mag`（112-121）——docstring 已自证引用未初始化全局，删除后 CHANGELOG 记录（ARCH-017）。
  2. AR-12 修复（定稿）：`STA_count2eflux(dat; m_int::Real=16)`、`STA_eflux2df(dat; m_int::Real=16)`。
     默认 16 与 `sta_v_4d` 的 O⁺ 默认一致（`sta_v_4d` 现以无参形式调用 `STA_count2df`，不能改必需参数）；
     docstring 注明"必须按离子种类显式传值（H⁺=1、O⁺=16 等，见 ion_mass_range）"；
     `STA_count2eflux` 的 m_int 当前不参与计算（保留参数，注释说明）。
  3. C3 修复：`get_mag_line_s` 读 `:B`（回退兼容字符串键 `"B"`：先 `get(data,:B,nothing)` 再 `data["B"]`）。
  4. A8 修复：`load_mag_l2` 的 `maximum(findall(...lines[1:300]))` → `findlast(line->startswith(line,"END"), lines[1:min(300,nums)])`，未找到时抛带文件名的明确错误。
  5. AR-15 错误聚合：`load_cdf` 捕获分支 `println` → `@warn`（保 flag 语义）；
     `load_MAVEN_data` 新增 kwarg `error_report::Vector{String}=String[]`：每次模型失败追加
     `"<model>: <原因>"`（默认不传 = 行为不变）。
- 涉及文件：`MAVEN_data/MAVEN_load.jl`、`MAVEN_data/MAVEN_STATIC.jl`、`TW_data/TW_load.jl`、`MGS_data/MGS_load.jl`、`Magnetic_Model/IGRF_calculate.jl`。
- 验证：每项对应单测（§12）；`STA_count2eflux(dat)` 默认调用有定义且与 `m_int=16` 一致；error_report 聚合测试。

#### ARCH-008 科学疑点修正与验证协议
- 目标：把 C 类疑点分为"确定性 bug 修复"与"记录不改值"两类；任何改动附带验证证据（R4）；重大算法决策见 §15（本文件定稿，实现阶段不得自行发挥）。
- 变更内容（定稿，逐项方案见 §15 表格）：
  1. 修复类：C2（combina_two_dir_trace 自引用）、C3（并入 ARCH-007）、C4（SWEA tiny 死变量删除）、C5（v_3d 索引维度）、C10（SWEA 64 能道等硬编码提取为具名常量 + 出处注释，数值不变）、C1（trace_mag_line 增 method kwarg，**默认保持 :euler 不改**）。
  2. 记录类（不改值）：C6/C7（TW_MINPA denergy 与符号）、C11（SWIA 两处系数）、C12（mean_SWEA_pad_pa NaN 逻辑）、C13（RV flag 判定）、C14（自转轴倾角近似）、C16（electorn 拼写键）、C18（STATIC 矩核心，仅登记）。
  3. 全部硬编码常数加"出处 + SPEDAS 对照"注释（AR-18 要求），对照结果汇总进 PHASE 7 验证报告附录。
- 涉及文件：`Magnetic_Model/IGRF_calculate.jl`、`MAVEN_data/MAVEN_SWEA.jl`、`MAVEN_data/MAVEN_SWIA.jl`、`MAVEN_data/MAVEN_load.jl`、`TW_data/TW_MINPA.jl`。
- 验证：见 §15 每项"验证协议"列；修复类必须同时有改动前后数值对比。

#### ARCH-009 全局可变状态显式参数化
- 目标：函数结果不再依赖隐式全局；旧 API 以包装层保留（不破坏历史脚本）。
- 变更内容（定稿，均为"公式逐字不动"的纯状态搬运）：
  1. `Cold_Plasma_Dispersion_Relation`：
     - 新增不可变配置 `PlasmaState`（NamedTuple：`Nparticles/Ω_n/Π_2`）；
     - `set_particles(; kw...) -> PlasmaState`（**不再写全局**）；
     - `Dispersion_Relation(θ, freq, Πe, Ωe, state::PlasmaState)` 新重载；
     - 旧签名 `Dispersion_Relation(θ,freq,Πe,Ωe)` 保留为包装：读模块内 `Ref{PlasmaState}`（由旧式
       `set_particles!`-兼容函数写入），未初始化时抛含指引的错误（替代现在静默使用未初始化全局）；
     - 新增 `calculate_minimum_energy` 正确拼写别名（ARCH-010），旧名 `carculate_minimum_energy` 保留转发。
  2. `MAVEN_load.kp_dict`（C15）：模块级 `const kp_dict`（JSON 默认值）保留；
     `load_kp(file; kp_columns=kp_dict)` 新 kwarg（默认行为不变）；
     `change_kp_read_data` 保留为兼容包装（写全局 Ref + @deprecate 文档标记）；
     加载期 1454 行的全局重设改为初始化 Ref。
  3. `IGRF_calculate.B_compress`（AR-4）：保留模块全局与 `set_B_compress`（标记非线程安全）；
     `IGRF_fortran` 与 `trace_mag_line` 新增显式 `bcompress` kwarg 变体（默认=读全局，行为不变）；
     新代码/并行代码用显式变体。
- 涉及文件：`models/Cold_Plasma_Dispersion_Relation.jl`、`MAVEN_data/MAVEN_load.jl`、`Magnetic_Model/IGRF_calculate.jl`。
- 验证：新旧调用路径对同一参数网格逐点一致（rel ≤ 1e-12）；未初始化状态调用给出清晰错误；并行测试（Threads.@threads 两线程各用独立 state）结果一致。

#### ARCH-010 兼容别名层 + 白名单补全
- 目标：历史拼写名不破坏；`@load` 后脚本层常用函数可裸名调用（降低迁移阻力）。
- 变更内容（定稿）：
  1. 别名（旧名保留为转发，不删）：`carculate_minimum_energy`→`calculate_minimum_energy`、`alfven_weve`→`alfven_wave`、`carclu_SWEA_pad`→`calculate_SWEA_pad`、`cyclone_*`→`cyclotron_*`（ARCH-006 已覆盖）。
  2. `MAVEN_plot.jl:18` 的 export 死名 `WaveSpactra_heatmap` 删除（白名单机制下 export 无关紧要，删除仅为一致性）。
  3. 白名单补全：以 `docs/src/api.md` 公开函数清单为准，为 16 个空白名单模块填写 `allow`
     （每模块只放"文档明确的公开入口"，如 MAVEN_STATIC: `sta_v_4d(_new)/sta_n_4d/static_c6_*/static_slip/STA_count2df(_all)` 等；逐模块在实现时定稿并写入注册表注释）。
  4. 被删除的坏死函数（ARCH-007）不进入白名单。
- 涉及文件：`src/modules.jl`、`MAVEN_data/MAVEN_plot.jl`、`models/Cold_Plasma_Dispersion_Relation.jl`、`MAVEN_data/MAVEN_load.jl`。
- 验证：每模块 `@load` 冒烟 + 白名单逐名引入测试；别名调用结果与原名一致。

#### ARCH-011 数据键契约中心化
- 目标：键名/形状/单位/就地修改约定有唯一权威出处（AR-7/8/9 的折中方案：不做全仓类型化）。
- 变更内容（定稿）：
  1. 新增 `common/data_keys.jl`：`module DataKeys`，定义契约 Symbol 常量与形状/单位注释
     （如 `const EPOCH=:epoch`、`const TIME=:time`、`const B_FIELD=:B`、`const DATA_LOAD_FLAG=:data_load_flag`…），
     注册表 `:DataKeys => kind=:preloaded`，`src/MarsData.jl` include。
  2. 契约表 = 本文件附录 A（键名/语义/形状/单位/生产者/消费者/就地修改约定），PHASE 8 移入 docs（ARCH-017）。
  3. 就地修改约定成文（AR-9）：`!` 后缀 = 明确原地修改；视图型函数（static_slip）docstring 注明共享内存；
     新增"只读视图/深拷贝变体"的判定推迟到 PHASE 4 热点分析（无实证不加 API）。
  4. 新代码与重构触及的代码改用 DataKeys 常量；存量未触及代码不强改（R6，避免无收益批量 diff）。
- 涉及文件：`common/data_keys.jl`（新增）、`src/MarsData.jl`、`src/modules.jl`。
- 验证：DataKeys 常量与附录 A 一致性测试（键名抽查）；`validate_registry` 绿。

#### ARCH-012 绘图管线面板化 + KP 键归一
- 目标：面板可独立测试；数据缺失报错指向数据而非面板深处；KP 双键收敛。
- 变更内容（定稿）：
  1. `src/plotting.jl` 每个面板拆成独立函数（`panel_orbit!`、`panel_B_xyz!`、`panel_density!`、…），
     显式入参（Axis、x_range、必要数据切片）；`plot_module` 退化为装配器（保持签名与输出不变）。
  2. 缺失键防御：面板入口用统一 `_require(data, :key)` 辅助，缺失时抛出
     `"面板 density 需要 data_dict["STATIC_d1_v4d"][:epoch]，缺失"` 式明确错误（替代深处 KeyError）。
  3. KP 键归一（C17）：`plot_module` 只读 `"KP"`，加回退 `_get_kp(data_dict)`：有 `"KP"` 用之；
     仅有 `"KP_l3"` 时用之并 `@warn` 一次。示例文件暂不动（兼容期），PHASE 8 文档更新。
- 涉及文件：`src/plotting.jl`。
- 验证：example 两脚本跑通且产出图与改动前一致（视觉抽查 + 无异常）；合成 data_dict 单面板测试；缺失键错误信息断言。

#### ARCH-013 Pickup_ion 函数化
- 目标：隐式全局契约 → 显式入口；消除第三套装载路径（D:/ 硬编码）。
- 变更内容（定稿）：
  1. 新增主入口函数：
     `pickup_ion_analysis(time_event::DateTime; instrument_mode="swi", spice_name="p+", dtime=…, data_dir=nothing, error_report=String[]) -> NamedTuple`
     函数体 = 现有顶层逻辑迁移（240 行起的全局赋值全部局部化）；数据装载走 `MarsData.@load`；
     KP 访问从旧键（`:vars`/`:var_190`）迁到新 kp_dict 语义键（随 ARCH-004/ARCH-011 契约）。
  2. 保留旧工作流 shim：文件末尾检测预置全局（`time_event/instrument_mode/spice_name/spice_dict/MAVEN_data/…`）
     仍存在时调用新入口并回填同名全局（@deprecate 文档标记）。
  3. 删除 `Pickup_ion.jl:273` 的 `D:/CODE/Package_for_Julia/` 回退 include（ARCH-005 已提供 DLL/路径解析）。
  4. 变量依赖清单：入口签名必须覆盖 AR-5 列出的全部外部变量（time_event/instrument_mode/spice_name/spice_dict/dtime/MAVEN_data/TW_minpa_data）。
- 涉及文件：`models/Pickup_ion.jl`。
- 验证：新旧入口对同一事件输出（points_data_df 等结果）逐位一致；runtests 新增入口函数冒烟（合成输入）。

#### ARCH-014 Benchmark 基线
- 目标：性能改动一律有据（R2）；sta_v_4d 双版本收编有等价性门（AR-11）。
- 内容：`benchmark/` 目录 + BenchmarkTools；8 项清单、方法与验收见 §13。PHASE 4（`04_OPTIMIZATION_PLAN.md`）细化执行口径；**PHASE 6 S0 在一切改动前执行基线快照**。
- 门：`sta_v_4d ≡ sta_v_4d_new`（合成 + 真实数据，rel ≤ 1e-9）证明完成后才允许删除旧版；不等价则保留双版本并在 04/07 记录差异，交科学负责人裁决。

#### ARCH-015 测试基座
- 目标：科学计算零测试 → 分层自动化测试（R3）；PHASE 5（`05_TEST_STRATEGY.md`）细化，PHASE 6 每步落地。
- 内容与验收见 §12。

#### ARCH-016 死代码与演进痕迹清理
- 变更内容（定稿，git 历史可追溯故可删）：
  1. `MAVEN_STATIC.jl:1090-1204`（100+ 行注释测试）、`MAVEN_SWEA.jl:136-195`（注释测试）、
     `TW_load.jl:10-47`（注释旧 load_mag）、`MAVEN_load.jl:1465-1471`（注释测试）、
     `load_c6_v3d` 内注释 Fortran 版（702-746）、`SWEA_calc_shape_arr` 内被覆盖的 `deriv` 首组计算（1311-1313）。
  2. 保留：标注"参考 IDL/SPEDAS 文件"类注释、docstring 内算法出处注释。
- 涉及文件：`MAVEN_data/MAVEN_STATIC.jl`、`MAVEN_data/MAVEN_SWEA.jl`、`TW_data/TW_load.jl`、`MAVEN_data/MAVEN_load.jl`。
- 验证：删除前后 runtests 绿；`grep -n "^\s*#"` 抽查无残留测试块。

#### ARCH-017 文档同步
- PHASE 8 集中执行；清单见 §14。

### 3.4 明确不做（非目标，防过度重构）

1. 不做全仓 `Dict{Symbol,Any}` → struct/NamedTuple 类型化（AR-7 折中；PHASE 4 只评估 STATIC 热点）。
2. 不做模块重命名/目录重排/文件移动（除 head.jl/function_coordinate.jl 的包化包裹）。
3. 不改 `MAVEN_data_format.json`、`KP_vars.json` 内容与生成端（Python）。
4. 不动 Octree.jl / Graham.jl / download_data/get_all_orbit.jl。
5. 不把重依赖并入 `Project.toml [deps]`；不动 requirement.jl（预期无新外部依赖）。
6. 不重写 MAVEN_plot 1554 行；不做风格/格式化批量 diff。
7. 不做任何 Python 侧改动（R7）。

---

## 4. 为什么目标架构更合理（按优先级论证）

> 论证优先级（本任务规定）：科学正确性 > 可维护性 > 性能 > 可测试性 > 模块职责 > 依赖方向 > 数据流清晰度。

### 4.1 科学正确性（最高优先级）

- **单一权威实现消灭公式分叉**（ARCH-006）：当前同一物理量最多三套实现（cyclotron、bowshock、Bpc2sphere、static_c6），修复一处不改他处即产生行为分叉——两套科学数字并存是比任何架构丑都严重的风险。收敛到唯一实现 + 转发别名后，公式只有一处可改，等价性测试保证迁移不漂移。
- **已证实 bug 在验证协议内修复**（ARCH-007/008）：C3（键不一致 KeyError）、C4（tiny 死变量）、C5（v_3d 4D 索引 BoundsError）、AR-12（默认参数 UndefVarError）、A8（END 行查找脆弱）都是确定性错误；修复附改动前后数值对比（R4），风险可控。
- **错误不再静默**（ARCH-007）：`load_cdf` 的 `println` 吞错 → `@warn` + `error_report` 聚合，`flag=false` 的空数据从"看不见"变为"可审计"（AR-15）。
- **状态显式化消除隐式时间耦合**（ARCH-009）：`Dispersion_Relation` 现在的结果依赖"之前是否调用了 set_particles"且无防御；PlasmaState 显式传参后编译器与测试都能抓住误用，公式逐字不动故数值零漂移。
- **科学决策在本文档定稿**（§15）：C1 默认追踪器不换（除非人类批准）、C6/C7/C11/C12/C13 不改值、C10 只提常量不改数值——实现阶段没有任何"顺手改科学"的空间（R5）。

### 4.2 可维护性

- **单一装载体系**（ARCH-002）：消除"同代码双实例 + 第三套 D:/ 回退路径"，包管理器的幂等/白名单/编辑距离诊断覆盖全部脚本（AR-1）。
- **去 eval**（ARCH-004）：JSON 不再是代码入口；函数表是代码内单一真相，键漂移在装载时以清晰错误暴露（A9）。
- **别名层而非破坏性改名**（ARCH-010）：历史拼写名全部保留转发，新名收敛——不制造新的破坏性 API 变更（R6）。
- **死代码清理**（ARCH-016）：注释测试块与注释旧版是"误把注释当实现"的噪音源；git 历史可追溯故删除安全。
- **契约表单一出处**（ARCH-011）：键名漂移有据可查，不再靠运行时 KeyError 发现。

### 4.3 性能

- **文件定位 O(1) 索引**（ARCH-004）：`find_file_of_data` 从每模型 O(N) 子串扫描 + 每次 O(M) 广播拼接，变为日期索引命中 + 回退扫描；`load_MAVEN_data` 多模型调用是主路径入口。
- **benchmark 先行**（ARCH-014）：R2 硬性要求；`sta_v_4d_new` 已有的手写优化首次获得等价性证明与计时数据，双版本维护成本在证明后归零（AR-11/AR-22）。
- **ccall 热路径免装箱保持不变**（ARCH-001 决策）：IGRF 的 `const GG,HH` 加载期读取保留——惰性化的"架构漂亮"会让 30000 步追踪每步多一次 Ref 间接，收益为负，故不做。
- **热点 struct 化留给 PHASE 4**：以 ARCH-014 基线为准定点优化，避免无数据支持的"感觉优化"。

### 4.4 可测试性

- **加载期 IO 清零（版本化 JSON 除外）**（ARCH-001/005）：fresh clone 上 `load_module(:MAVEN_load)` 即可运行——这是全仓最大 testability 障碍的解除（AR-25）。
- **状态显式化**（ARCH-009）：测试可并行、可隔离（AR-27）。
- **函数化 Pickup_ion**（ARCH-013）：从"几十个隐式全局的 include 脚本"变为可调用入口，零测试 → 可测试（AR-5）。
- **面板化绘图**（ARCH-012）：每个面板用合成数据单测；缺失键错误指向数据（AR-16）。
- **契约表 + DataKeys**（ARCH-011）：键名契约成为测试断言依据（AR-7/8）。

### 4.5 模块职责

- 读取器只读取（MAVEN_load/TW/MGS/SP_load）、仪器模块只处理（STATIC/SWIA/SWEA/MINPA）、common 只放纯数学与常量（MarsCommon/DataKeys/FunctionCoordinate）、models 只放物理——MAVEN_load 的 God module 瘦身（AR-17），SWEA shape 函数迁回 MAVEN_SWEA（MAVEN_load 保留转发面，调用方零改动）。
- MarsUtils（head.jl 工具库）与"装载器"身份解耦，职责单一（AR-6 的横向耦合随之消除）。

### 4.6 依赖方向

- 统一自包含 include（ARCH-003）：不再有"声明式 deps 与运行时 include 两套真相"；`using ..parent` 的装载顺序脆弱性消除。
- 依赖方向单向：common ← 仪器/读取 ← 脚本/绘图；跨目录横向 include（TW_MINPA 私有 slice2d 副本、MAVEN_load 内 Bpc2sphere 副本）全部转为对 common 的依赖（ARCH-006）。
- 重依赖仍经载体 LOAD_PATH 回退解析——包"轻量可加载"承诺不变（红线）。

### 4.7 数据流清晰度

- 读取 → 处理 → 分析 → 绘图的单向流显式化：读取器不再兼任科学处理（ARCH-006/ARCH-017 迁移），错误在源头聚合（ARCH-007），KP 键归一 + 回退兼容（ARCH-012），状态经参数传递而非隐式全局（ARCH-009）。
- 数据键契约表（附录 A）使每一跳的数据形状/单位/键名可见。

---

## 5. 模块边界如何变化

| 模块 / 文件 | 现状边界 | 目标边界 | 变更 |
| --- | --- | --- | --- |
| `src/MarsData.jl` | 轻量 API + 绘图 + 装载 | + DataKeys（preloaded） | ARCH-011 |
| `src/modules.jl` | 19 条目注册表 | +DataKeys/MarsUtils/FunctionCoordinate；allow 补全；validate_registry 扩展；**装载机制不动** | ARCH-002/003/006/010/011 |
| `src/plotting.jl` | 12 面板内联合成 | 面板函数 + 装配器；KP 归一 | ARCH-012 |
| `common/constants.jl` | 物理常量 | 不变 | — |
| `common/MarsCommon.jl` | 坐标/能量/PSD | +Bpc2sphere/bowshock/magnetopause/Vandermonde/polynomial_fit/vector_angle/logticks（数学工具权威）；自包含 include | ARCH-003/006 |
| `common/paths.jl` | 三根路径 + 索引 | +可选只读键解析（fortran_dll_dir 等，默认值兜底） | ARCH-005 |
| `common/head.jl` | 装载器 + 工具库 | `module MarsUtils`（纯工具库，注册） | ARCH-002 |
| `common/function_coordinate.jl` | 脚本 | `module FunctionCoordinate`（注册）；bowshock_zero 转发 | ARCH-006 |
| `common/data_keys.jl` | — | 新增：契约常量（preloaded） | ARCH-011 |
| `MAVEN_data/MAVEN_load.jl` | 读取 + 科学处理 + 反射 + 全局 | 纯读取调度；惰性 filename_list；显式函数表；日期索引；error_report；科学函数转发别名；kp_columns kwarg | ARCH-001/004/006/007/009 |
| `MAVEN_data/MAVEN_plot.jl` | 绘图 + 数学工具 | 纯绘图基元；数学工具转发 MarsCommon；export 死名清理 | ARCH-006/010 |
| `MAVEN_data/MAVEN_STATIC.jl` | STATIC 矩（内聚最好） | m_int 修复；注释测试清理；static_c6 权威 | ARCH-007/016 |
| `MAVEN_data/MAVEN_SWIA.jl` | SWIA 处理 | v_3d 修复；常数出处注释 | ARCH-008 |
| `MAVEN_data/MAVEN_SWEA.jl` | SWEA 处理 | tiny 删除；shape 函数迁入（MAVEN_load 转发）；注释测试清理 | ARCH-006/008/016 |
| `MGS_data/MGS_load.jl` | 读取（硬编码路径） | Paths 化；删除 caculate_mag | ARCH-005/007 |
| `TW_data/TW_load.jl` | 读取（硬编码路径） | Paths 化；删除 calculate_mag；注释块清理 | ARCH-005/007/016 |
| `TW_data/TW_MINPA.jl` | MINPA 处理（硬编码路径 + slice2d 副本） | Paths 化；slice2d 用 FunctionCoordinate；C6/C7 记录不改 | ARCH-005/006/008 |
| `Magnetic_Model/IGRF_calculate.jl` | 磁场模型 | :B 键修复；method kwarg；B_compress 显式变体；C2 修复 | ARCH-007/008/009 |
| `models/Cold_Plasma_Dispersion_Relation.jl` | 色散（全局状态） | PlasmaState 显式化 + 兼容包装 + 别名 | ARCH-009/010 |
| `models/Maxwellian_distribution.jl` | 拟合 | 不变（+白名单） | ARCH-010 |
| `models/Single_Particle_Orbit.jl` | 轨道 | cyclotron 转发（审计后）；TimeFormat 转发 | ARCH-006 |
| `models/Pickup_ion.jl` | 全局契约脚本 | 函数化 + shim + @load | ARCH-002/013 |
| `models/Octree.jl` / `models/Graham.jl` | 独立脚本 | **不动** | — |
| `calculate/calculate_models.jl` | 组合计算 | cyclotron 权威 | ARCH-006 |
| `support_data/support_data_load.jl` | OMNI（INI+println） | Paths 化、去副作用 | ARCH-005 |
| `call_fortran_dll.jl` | ccall 封装（硬编码路径） | DLL 路径经 Paths 解析 + 清晰错误 | ARCH-005 |
| `MAVEN_data/Build_data/*.jl` | 相对 include | @load（P3） | ARCH-002 |
| `example/MAVEN_plot_sample/*.jl` | 相对 include + KP_l3 别名 | 保持可跑（兼容期）；@load 迁移（P3） | ARCH-002/012 |
| `test/runtests.jl` | 仅装载管理器 | 分层扩展（§12） | ARCH-015 |
| `benchmark/` | — | 新增基准套件 | ARCH-014 |

---

## 6. 数据流如何变化

### 6.1 主读取管线（MAVEN）

```
【现状】
模块加载期: JSON + filename_lists.json(无条件 open) → data_model/kp_dict/filename_list 全局
调用期: load_MAVEN_data → 每 model: find_file_of_data(线性 occursin + 每次广播拼接)
        → eval(Meta.parse(JSON 字符串)) 分派 → 失败 println 吞掉 → flag=false 静默

【目标】
模块加载期: 仅 JSON（版本化、随仓库）→ data_model/kp_dict(Ref) / LOADER_FUNCS 显式函数表
调用期: filename_list() 惰性(缺省空) → 每 model: 日期索引命中(未命中回退 occursin)
        → 函数表分派(键漂移装载即报) → 失败 @warn + error_report 聚合 → flag=false 可审计
```

### 6.2 科学计算流

```
【现状】set_particles 写全局 → Dispersion_Relation 隐式读全局；B_compress/kp_dict 进程级可变
【目标】set_particles 返回 PlasmaState → Dispersion_Relation(…, state) 显式；
       B_compress/kp_columns 为 kwarg（默认读模块常量 = 旧行为）；并行用显式变体
```

### 6.3 脚本与绘图流

```
【现状】Pickup_ion: 预置全局 → include head.jl(裸装载 6 模块) → 顶层赋值十余个全局 → (catch 分支 D:/ 第三路径)
【目标】pickup_ion_analysis(time_event; …) 显式入口 → MarsData.@load → 局部数据流 → 返回结果
       （旧全局 shim 保留，@deprecate）
【绘图】plot_module 内联读 data_dict["KP_l3"]/["KP"] 双键 → _get_kp 归一(回退 @warn) + 面板函数显式入参
```

---

## 7. API 如何变化

> 总原则（R6）：删除仅限已证实坏死的 3 个函数；其余一律"新增别名 / 追加 kwarg（默认保持旧行为）/ 转发"。

### 7.1 删除

| API | 原因 | 处置 |
| --- | --- | --- |
| `MAVEN_load.calculate_mag` | 引用未初始化全局，调用必崩（AR-28） | 删除 + CHANGELOG |
| `TW_load.calculate_mag` | 同上 | 删除 + CHANGELOG |
| `MGS_load.caculate_mag` | 同上（且拼写错） | 删除 + CHANGELOG |
| `MAVEN_plot` export 死名 `WaveSpactra_heatmap` | 定义名为 `WaveSpectra_heatmap`，export 无意义（A7） | 删除 export 行 |

### 7.2 新增

| API | 说明 |
| --- | --- |
| `DataKeys` 模块（preloaded） | 数据键契约常量（ARCH-011） |
| `MarsUtils` 模块（注册） | head.jl 工具库包化（ARCH-002） |
| `FunctionCoordinate` 模块（注册） | function_coordinate.jl 包化（ARCH-006） |
| `MAVEN_load.filename_list()` | 惰性文件清单访问器（ARCH-001） |
| `load_MAVEN_data(...; error_report=String[])` | 失败聚合（ARCH-007） |
| `trace_mag_line(...; method=:euler)` | :euler/:rk4/:adaptive；默认不变（ARCH-008） |
| `IGRF_fortran`/`trace_mag_line` 显式 `bcompress` 变体 | 并行安全路径（ARCH-009） |
| `load_kp(...; kp_columns=kp_dict)` | 显式列映射（ARCH-009） |
| `set_particles(...) -> PlasmaState` + `Dispersion_Relation(θ,freq,Πe,Ωe,state)` | 显式状态（ARCH-009） |
| 正确拼写别名：`calculate_minimum_energy`、`alfven_wave`、`calculate_SWEA_pad`、`cyclotron_radius`、`cyclotron_frequency` | 旧名保留（ARCH-010） |
| `pickup_ion_analysis(time_event; ...)` | Pickup_ion 显式入口（ARCH-013） |
| `MarsCommon.Bpc2sphere/Bsphere2pc/bowshock/bowshock_km/magnetopause/Vandermonde/polynomial_fit/vector_angle/logticks` | 权威实现迁移（ARCH-006） |

### 7.3 行为修复（默认参数/键）

| API | 改动 |
| --- | --- |
| `STA_count2eflux(dat; m_int=16)` / `STA_eflux2df(dat; m_int=16)` | 原默认 `m_int=m_int` 是 UndefVarError；改为有定义默认 16（与 sta_v_4d O⁺ 默认一致），docstring 注明按离子种类显式传值（ARCH-007） |
| `get_mag_line_s(data)` | 读 `:B`（回退 `"B"`）（ARCH-007） |
| `load_mag_l2` 内部 END 行查找 | `findlast` + 缺失明确报错（ARCH-007） |
| `load_cdf` 捕获分支 | `println` → `@warn`（ARCH-007） |
| `MAVEN_SWEA.n1d` | 删除死变量 `tiny=1.0-31`；行为不变（ARCH-008） |
| `MAVEN_SWIA.v_3d` | theta/domega 改 3D 索引（coarse）+ ndims 分支兼容 fine（ARCH-008） |
| `IGRF_calculate.combina_two_dir_trace` | 模块内自引用 `IGRF_calculate.` 前缀移除（ARCH-008） |

### 7.4 别名 / 弃用（旧名保留，转发）

- `MAVEN_load.static_c6_mass_mean/energy_mean` → MAVEN_STATIC 新版转发（对外名不变）。
- `MAVEN_load.Bpc2sphere` → MarsCommon；`MAVEN_load.cyclone_*` → calculate_models.cyclotron_*。
- `MAVEN_plot.bowshock/magnetopause/Vandermonde/polynomial_fit/vector_angle/logticks` → MarsCommon 转发。
- `Cold_Plasma.carculate_minimum_energy`/`alfven_weve` → 新拼写转发；旧 `set_particles`/`Dispersion_Relation` 旧签名 → 包装（@deprecate 标记）。
- `change_kp_read_data`、`set_B_compress` → 保留，标记非线程安全/弃用倾向（新代码用 kwarg 路径）。
- `Pickup_ion` 全局变量 shim → 保留，@deprecate。

### 7.5 明确不破坏

`load_module/@load/available_modules/module_info/validate_registry` 签名与语义；`plot_module` 签名与输出；`load_MAVEN_data` 返回结构；`load_cdf` 返回结构；`sta_v_4d` 返回；示例脚本可跑性。

---

## 8. 哪些代码需要迁移

| 文件 | 迁移内容 | ARCH | 步骤 |
| --- | --- | --- | --- |
| `MAVEN_data/MAVEN_load.jl` | 惰性 filename_list；显式函数表；日期索引；error_report；删 3 个坏死函数副本（calculate_mag/旧 static_c6/cyclone_*/Bpc2sphere）；kp_columns kwarg；SWEA shape 函数迁出（转发保留）；@warn | 001/004/006/007/009 | S1/S3/S6/S8 |
| `MAVEN_data/MAVEN_STATIC.jl` | m_int 默认修复；注释测试删除；static_c6 权威化 | 007/016 | S1/S11 |
| `MAVEN_data/MAVEN_SWIA.jl` | v_3d 索引修复 + 形状断言；常数出处注释 | 008 | S6 |
| `MAVEN_data/MAVEN_SWEA.jl` | tiny 删除；shape 函数迁入；64 能道等具名常量；注释测试删除 | 008/016 | S6/S11 |
| `MAVEN_data/MAVEN_plot.jl` | 数学工具移交 MarsCommon（转发）；export 死名清理 | 006/010 | S8/S10 |
| `common/MarsCommon.jl` | 自包含 include；接收 Bpc2sphere/bowshock/magnetopause/数学工具 | 003/006 | S4/S8 |
| `common/head.jl` | 拆分为 module MarsUtils；装载块删除 | 002 | S9 |
| `common/function_coordinate.jl` | 包化 module FunctionCoordinate | 006 | S8 |
| `common/data_keys.jl` | 新增契约模块 | 011 | S5 |
| `common/paths.jl` | 新增可选只读键解析（fortran_dll_dir） | 005 | S2 |
| `MGS_data/MGS_load.jl` | Paths 化；删 caculate_mag | 005/007 | S2/S1 |
| `TW_data/TW_load.jl` | Paths 化；删 calculate_mag；注释块清理 | 005/007/016 | S2/S1/S11 |
| `TW_data/TW_MINPA.jl` | Paths 化；slice2d 用 FunctionCoordinate；C6/C7 仅注释记录 | 005/006/008 | S2/S6/S8 |
| `Magnetic_Model/IGRF_calculate.jl` | :B 键修复；method kwarg；bcompress 变体；C2 修复 | 007/008/009 | S1/S6/S7 |
| `models/Cold_Plasma_Dispersion_Relation.jl` | PlasmaState；别名；包装 | 009/010 | S7/S10 |
| `models/Single_Particle_Orbit.jl` | cyclotron/TimeFormat 转发（审计后） | 006 | S8 |
| `models/Pickup_ion.jl` | 函数化 + shim + @load + 去 D:/ 路径 | 002/013 | S9 |
| `calculate/calculate_models.jl` | cyclotron 权威（docstring 补单位） | 006 | S8 |
| `support_data/support_data_load.jl` | Paths 化、去 println | 005 | S2 |
| `call_fortran_dll.jl` | DLL 路径解析 | 005 | S2 |
| `src/MarsData.jl` | include DataKeys | 011 | S5 |
| `src/modules.jl` | 注册表 +3 条目；allow 补全；validate_registry 扩展 | 002/003/010/011 | S4/S5/S10 |
| `src/plotting.jl` | 面板化 + _get_kp 归一 | 012 | S10 |
| `MAVEN_data/Build_data/*.jl` | @load 迁移 | 002 | S9（P3） |
| `example/MAVEN_plot_sample/*.jl` | @load 迁移（可选，兼容期不动） | 002 | S9（P3） |
| `test/runtests.jl` | 分层扩展 | 015 | 各步 |
| `benchmark/` | 新增基准套件 | 014 | S0 |

---

## 9. 哪些代码不应该修改（红线）

1. **Python 侧全部零改动**（R7）：`download_data/`、`martian_pipeline/`、`config/*.py`、`config/settings.example.toml`、`tools/`、`tests/*.py`、`requirements.txt`、`pyproject.toml`、`MAVEN_data/build_read_me.py`、`MAVEN_data/Build_data/` 内的 .py/.pro 文件。
2. **载体机制本身**：`src/modules.jl` 的 `_carrier`/`load_module` 装载语义、幂等、`const` 别名绑定、`@load` 白名单逐名引入、`:preloaded` 行为、`ModuleLoadError` 保留 cause——只允许增补注册表条目 / allow 白名单 / validate_registry 校验，不允许改机制（01 §2.3 红线）。
3. **包"轻量可加载"承诺**（AR-24/A10）：`using MarsData` 在无数据、无 DLL 环境必须可加载；重依赖不并入 `[deps]`；`MAVEN_plot` 随包预装保持。
4. **数据与配置只读**：`MAVEN_data/MAVEN_data_format.json`（ARCH-004 只改 Julia 侧对 `value[4]` 的解释，**JSON 内容一字不改**）、`KP_vars.json`、`Magnetic_Model/gh_gao`、`gh_gao.txt`、`IGRF_DLL.dll`、`color_117_modified.txt`、外部数据目录（E:/MAVEN、E:/Tianwen-1、E:/MGS，只读打开）、`example/*.png`。
5. **科学算法红线**（R5）：系数/模型/数值方法更改需人类批准——C1 默认追踪器保持 :euler 直到批准；C6/C7/C11/C12/C13 不改值；gh_gao 系数不动；ARCH-009 是纯状态搬运（公式逐字不动）。
6. **Markdown 不删除**（R1）：`docs/reports/` 历史快照只读；`README.md`/`README_EN.md`/`CHANGELOG.md` 在 PHASE 8 才同步（提前不改）。
7. **禁止破坏性 API 变更**（R6）：除 §7.1 四个条目外一律别名/追加 kwarg。
8. **独立脚本不动**：`models/Octree.jl`、`models/Graham.jl`、`download_data/get_all_orbit.jl`。
9. **依赖清单不动**：`Project.toml [deps]`、`requirement.jl`（预期无新增外部依赖）。
10. `.agent-teams/`（运行时状态，只读诊断）；`.agent/00–02`（已完成的正式输入，只读引用）。
11. 不做纯风格/格式化批量改动（R6）。

---

## 10. 迁移顺序

> 每步 = 独立提交单元；上一步绿灯才允许下一步；每步携带测试（ARCH-015）与必要 benchmark 证据（ARCH-014）。PHASE 6 实施，GLM-5 主实施，Qwen 3.8 Flash 承担边界清晰的批量步骤。

| 步 | 内容 | ARCH | 验收门（全部满足才进入下一步） |
| --- | --- | --- | --- |
| S0 | **基线快照**：改动前跑 benchmark 8 项 + 关键数值 golden 快照（load_cdf 单文件、sta_v_4d 一日、IGRF_pc 网格、trace_mag_line、n1d、v_3d 修复前的当前行为记录） | 014 | 基线数据入库（04/07 引用）；数值快照文件生成 |
| S1 | **地基（P0，零科学风险）**：坏函数删除、m_int 默认、:B 键、findlast、@warn+error_report、filename_lists 惰性 | 001/007 | fresh clone runtests 绿；每项单测绿；CHANGELOG 记录删除 |
| S2 | **路径统一**：SP_load/TW/MGS/Call_fortran_dll 走 Paths | 005 | 无数据环境可装载；有数据环境输出逐位一致 |
| S3 | **装载注册表**：显式函数表 + 日期索引 | 004 | 55 产品对照校验绿；golden 一日加载回归；索引基准 |
| S4 | **装载一致性**：自包含 include + validate 扩展 | 003 | validate_registry 空；全模块装载冒烟 |
| S5 | **契约中心化**：DataKeys + 附录 A 固化 | 011 | 契约一致性测试绿 |
| S6 | **科学修正（验证先行）**：C2/C4/C5/C10 修复 + C1 method kwarg；记录类加出处注释 | 008 | §15 每项验证协议出证据；科学回归测试绿 |
| S7 | **状态显式化**：PlasmaState / kp_columns / bcompress 变体 | 009 | 新旧路径逐点一致（≤1e-12）；并行测试绿 |
| S8 | **去重**：签名审计表 → 权威实现 + 转发别名 | 006 | 每转发对等价测试绿；调用点全审计 |
| S9 | **脚本层迁移**：head.jl → MarsUtils；Pickup_ion 函数化；Build_data/example @load | 002/013 | 新旧入口同事件输出一致；文档更新 |
| S10 | **绘图与 API 面**：面板化 + KP 归一 + 别名层 + 白名单补全 | 012/010 | example 全跑产出图；别名测试绿 |
| S11 | **清理**：注释测试/旧版删除 | 016 | grep 抽查 + runtests 绿 |
| — | **PHASE 7**：全量验证（科学回归、benchmark 对比、风险核对） | 014/015 | 07_VERIFICATION.md |
| — | **PHASE 8**：文档同步 | 017 | 08_DOCUMENTATION_SYNC.md |
| — | **PHASE 9**：独立最终评审 | — | 09_FINAL_REVIEW.md |

- **顺序理由**：S1 先解除 fresh-clone 阻塞（一切测试的前提）；S2–S5 是纯工程改造（科学零接触）；S6 科学修复在 golden 基线（S0）与无科学接触的改造之后进行，任何漂移都可归因；S7–S8 以 S6 后的稳定数值为回归基准；S9 依赖 S8 的 FunctionCoordinate/MarsUtils 存在；S10 依赖契约（S5）与别名面（S8）。
- **回滚**：每步独立提交；删除类先记 CHANGELOG；科学等价性未证明前双实现并存（S8/S6 内建"证明后删"门）。

---

## 11. 风险

| # | 风险 | 等级 | 缓解 |
| --- | --- | --- | --- |
| 1 | 重构导致科学结果漂移（最大风险） | 高 | S0 golden 快照 + 每步数值回归（R4）；等价性证明后删；不改常数（R5） |
| 2 | head.jl 生态脚本断裂（脚本层裸 include 依赖） | 中 | MarsUtils 同名工具 + 别名转发；Pickup_ion shim；迁移指引写入文档（PHASE 8） |
| 3 | 真实数据不可得导致验证受阻（本地 E:/ 数据不可用） | 中 | 合成数据测试 + opt-in 真实数据基准；受阻项在 05/07 明确标记 blocked 并上报，不假装通过 |
| 4 | sta_v_4d 与 sta_v_4d_new 不等价 | 中 | 保留双版本；差异记录进 04/07；删除决策交科学负责人 |
| 5 | IGRF 依赖 Windows x64 DLL，CI/Linux 环境跑不了磁场测试 | 中 | `Sys.iswindows()` 条件跳过 + 显式 @test_skip 标注；纯 Julia 路径（坐标/键）测试不依赖 DLL |
| 6 | Pickup_ion 隐式全局清单遗漏导致函数化不完整 | 中 | 实施前逐行变量审计（AR-5 已列清单），入口签名必须覆盖；新旧对比测试兜底 |
| 7 | 白名单裸名引入与调用方已有名冲突 | 低 | 逐名引入冲突即报错；每模块 @load 冒烟测试 |
| 8 | Makie 版本升级引发绘图回归 | 低 | Manifest 锁定；example 冒烟测试 |
| 9 | JSON 键漂移导致函数表缺项 | 低 | 装载期全量校验（ARCH-004）给出清晰错误 |
| 10 | 迁移顺序颠倒造成半成品 | 低 | §10 绿灯门禁，禁止跳步 |

---

## 12. 测试要求

> 详见 PHASE 5（05_TEST_STRATEGY.md）；此处为 PHASE 6 各步的强制验收口径（R3/R4）。

1. **模块管理器**（既有测试保持绿 + validate_registry 新校验）：注册表自检、幂等、白名单、载体隔离、@load、:all 拓扑序、MAVEN_load 冒烟装载（A1 修复后不再被 filename_lists 阻塞）。
2. **MarsCommon 纯函数单测**：球↔笛卡尔坐标往返（rel ≤ 1e-12）；能量↔速度（相对论）对照解析值；eflux→PSD 两版合成输入对比；searchsortednearest 边界（首/末/越界/空）；position_altitude/local_time 已知点；ARCH-006 迁入的 bowshock/magnetopause/Bpc2sphere/数学工具等价性。
3. **MAVEN_STATIC**：合成切片字典 → STA_count2eflux/STA_eflux2df 默认 m_int 行为（=16 且有定义）；sta_v_4d vs sta_v_4d_new 合成数据等价（rel ≤ 1e-9，ARCH-014 门）；static_slip 形状与视图语义。
4. **MAVEN_SWIA**：合成 coarse 网格（theta 3D `(ntime,4,48)`，与 get_3dc! 输出一致）过 v_3d 不抛 BoundsError 且密度为正（C5 回归）；n_3d/j_3d 恒正性；常数出处注释存在性检查。
5. **MAVEN_SWEA**：n1d 合成能谱 vs 手算期望（dE·E^(-3/2) 加权解析值）；tiny 删除前后行为不变回归；shape 函数迁入后等价测试。
6. **IGRF**：改动前数值快照回归（S0 快照 vs 改动后，逐位或可论证容差）；trace method kwarg 三种方法输出形状一致 + Euler 默认行为不变；get_mag_line_s :B 键回归；combina_two_dir_trace(to_pc=true) 可调用且与球坐标逐点变换一致；网格 ∇·B 数值散度 sanity check。
7. **Cold_Plasma**：PlasmaState 版与旧全局版对参数网格逐点一致（rel ≤ 1e-12）；未初始化状态调用给出清晰错误（非 UndefVarError）。
8. **文本 loader（MAG l2 / KP / MGS / TW）**：`test/fixtures/` 内嵌小样本（每类 5–20 行合成行）：列解析、坏行容错、END 定位（findlast 回归）、错误信息含文件名。
9. **load_MAVEN_data 错误聚合**：模拟缺失模型 → error_report 非空、flag=false、@warn 出现。
10. **Pickup_ion**：入口函数合成输入冒烟；新旧 shim 对同一事件输出一致（需要真实数据，opt-in）。
11. **绘图面板**：合成 data_dict 单面板测试；缺失键错误信息断言（含面板名与缺失键路径）；example 两脚本端到端。
12. **环境矩阵**：fresh clone（无数据/无 settings.toml）runtests 全绿；有 settings.toml 有数据（opt-in）科学回归套件绿。
13. **回归基线（PHASE 7）**：全部科学函数改动前后 golden 对比报告（R4 的"对比方法、样本与结论"格式）。

---

## 13. Benchmark 要求

> 方案细节归 PHASE 4（04_OPTIMIZATION_PLAN.md）；此处为强制清单与口径（R2）。

**方法**：`benchmark/` 目录；BenchmarkTools；同机同数据、多次取中位（`minimum`/`median` 均记录）；合成数据为主（可复现），真实数据基准 opt-in（标注数据文件哈希与日期）；每次优化前后成对记录，结果写入 04/07 文档。

| # | 项目 | 数据 | 成功判据 |
| --- | --- | --- | --- |
| 1 | 文本 loader（load_mag_l2 单日 / MGS load_mag） | 真实单文件 opt-in | 基线入档；后续解析改动成对对比 |
| 2 | STA_count3df / STA_count2df_all | 合成 STATIC 切片 | 基线入档（STA_count2df_all 已知"开销极大"，PHASE 4 定点） |
| 3 | **sta_v_4d vs sta_v_4d_new 等价 + 计时** | 合成 + 真实（opt-in） | 等价 rel ≤ 1e-9 且计时记录 → 之后才可删旧版（门） |
| 4 | static_c6_mass_mean | 合成一日 c6 | 基线入档 |
| 5 | find_file_of_data 索引化前后 | 1000 文件名合成列表 | 命中结果一致 + 计时对比（ARCH-004 证据） |
| 6 | plot_module 合成 | 合成 data_dict | 基线入档；S10 面板化前后对比（不许变慢 > 10%，否则回退） |
| 7 | **磁力线追踪 Euler vs RK4 vs adaptive** | gh_gao 模型、固定起点、step=0.5 km、max_trace=30000 | 终点偏差 + 耗时对比表 → C1 决策数据（交人类） |
| 8 | load_MAVEN_data 一日全产品 | 真实数据 opt-in | 基线入档；S3 索引化前后对比 |

**硬性规则**：任何以性能为理由的改动必须携带对应基准对比；无 benchmark 数据的"优化"不得合入（R2）。

---

## 14. 文档影响

1. **本文件附录 A《数据键契约表》** → PHASE 8 移入 `docs/src/data_contract.md`（新增页，不删除任何旧页）。
2. **docs/src/api.md**：新增模块（DataKeys/MarsUtils/FunctionCoordinate）、新 kwarg（error_report/method/kp_columns/bcompress）、别名层、删除函数登记。
3. **docs/src/data_reading.md**：核对已下架产品名（KP_l3/MAG_pc1s_l3 等，D3）；补充 filename_lists.json 惰性行为与 error_report 用法。
4. **README/README_EN**：脚本层新用法（`MarsData.@load` 迁移后的 Pickup_ion 入口）；`load_module` 行为不变。**CHANGELOG**：删除的 3 个坏死函数、别名层、行为修复条目。
5. **docs/src/index.md**：三层结构图更新（DataKeys/MarsUtils/FunctionCoordinate）。
6. **docs/src/data_format.md**：单位约定表（AR-19 要求）与常数出处注释汇总。
7. **PHASE 7 报告附录**：SPEDAS 常数对照表（AR-18 验证产物）归档。

---

## 15. 重大科学决策记录（C 类逐项定稿，R5 合规）

> 本表即实现阶段的"唯一真理"：实现 Agent 不得超出下表方案；任何表中未覆盖的科学改动一律停手并上报。

| ID | 问题 | 决策 | 定稿方案 | 验证协议 | 决策门 |
| --- | --- | --- | --- | --- | --- |
| C1 | trace_mag_line 默认一阶 Euler（AR-20） | **不换默认** | 新增 kwarg `method=:euler`（:euler/:rk4/:adaptive 三选一，默认保持 :euler）；实现时先核对 RK4/自适应签名并统一关键字名（r_range/max_trace/step/dir），签名不兼容则该支路暂不暴露并注释说明 | benchmark 第 7 项：三法同起点/步长对比终点偏差 + 耗时，数据入 04/07 | **人类批准后才可改默认值**；kwarg 本身是工程改动 |
| C2 | combina_two_dir_trace 模块内自引用 `IGRF_calculate.` 前缀 | 修复 | 前缀移除改裸名调用（确定性 UndefVarError bug，非算法改动） | to_pc=true 调用测试；结果与 to_pc=false 逐点坐标变换一致 | 无需人类批准（bug 修复） |
| C3 | get_mag_line_s `"B"` vs `:B`（并入 ARCH-007） | 修复 | 读 `:B`，回退 `"B"` | trace_mag_line → get_mag_line_s 全链路测试 | 同上 |
| C4 | SWEA `tiny = 1.0-31` 笔误 | 修复（删死变量） | 删除 tiny 行；clamp 逻辑（`ff`）与能量积分**逐字不动**，行为不变 | n1d 改动前后逐位一致测试 | 同上；若未来要改 clamp 逻辑需 SPEDAS 对照 + 人类批准 |
| C5 | SWIA v_3d 用 4D 索引取 3D theta（已确认 get_3dc! 输出 `(ntime,4,48)`；get_3df! 输出 4D） | 修复 | theta/domega 按 ndims 分支：3D 输入索引 `[time_ind,:,:]` 后 reshape 至 `(ntime,1,ndeflect,nenergy)`；4D 输入保持现索引；v_3d 开头加尺寸断言并给出清晰报错 | 合成 coarse 网格回归；真实 SWIA 一日 v_3d 与 n_3d/j_3d 一致性核对（密度符号/量级） | 无需人类批准（bug 修复）；量级异常时上报 |
| C6 | TW_MINPA denergy 弃用、改 `0.2/2` 经验常数 | **不改值** | 代码加出处注释 + 疑点注释；对照表记录 | 若可得 MINPA 参考数据：denergy 逐通道积分 vs 0.2/2 相对差记录 | **人类批准后才改**；无参考数据则留档 |
| C7 | TW_MINPA v3d 的 nvy 符号与整体 `vel=-vel` | **不改** | 疑点注释 + 对照表记录 | 与 MINPA 官方/参考速度矩（若可得）逐事件对比 | 同上 |
| C8 | Cold_Plasma 全局状态（AR-4） | 重构（算法公式逐字不动） | ARCH-009：PlasmaState + 新重载 + 旧签名包装（未初始化报清晰错误） | 新旧路径参数网格逐点 rel ≤ 1e-12 | 无需人类批准（纯状态搬运） |
| C9 | 分度制/弧度注释矛盾 | 文档修正 | 顶部注释改为"弧度"（与实现一致） | 无数值影响 | — |
| C10 | SWEA 64 能道/`13:64`/`n_e=52`/df_iono 模板硬编码 | 提常量不改值 | 提取为具名常量 + 出处注释；数组模板逐元素保持 | SWEA_calc_shape_arr 改动前后逐位一致测试 | 数值如有任何出入即停手上报 |
| C11 | SWIA `7.224566339926571e-7` 与 n_1d `8.8` 系数 | **不改值** | 具名常量 + 推导式注释（从 eflux→df→密度积分的量纲推导记录）；SPEDAS 源码对照写入对照表 | 符号推导核对 + 与 n_3d/j_3d 一致性 | 推导证明不一致时上报人类裁决 |
| C12 | mean_SWEA_pad_pa NaN 互填逻辑 | **不改** | 对照 SPEDAS 平均逻辑的记录注释 | 有 golden 数据则回归对比 | 人类批准后才改 |
| C13 | load_cdf RV 判定 `flags & 1 == 1` 与注释不符 | **不改逻辑** | 注释与实现对齐（注明实际判定），对照表记录 SPEDAS 行为 | 对已知 RV 文件打印 flags 分布核对记录 | 判定规则变更需人类批准 |
| C14 | position_local_time/latitude 忽略倾角 | 不改（docstring 已注明） | — | — | 新功能另议 |
| C16 | `electorn density` 拼写键 | 不改 | 契约表登记 + 注释 | — | 重命名需 JSON+代码+下游三方同步，人类批准 |
| C18 | STATIC 矩核心（sta_v_4d 等） | 只登记 | 任何触及处以 golden 回归为准（S0 快照） | sta_v_4d/_new 等价门（ARCH-014） | 公式改动需人类批准 |

---

## 16. 只读合规声明

- 本阶段输入：`.agent/00_PROJECT_SCOPE.md`、`.agent/01_PROJECT_MAP.md`、`.agent/02_ARCHITECTURE_REVIEW.md`（只读引用）。
- 本阶段定点读取的源码（未重新全仓扫描）：`src/MarsData.jl`、`src/modules.jl`、`src/plotting.jl`(60-139)、`common/paths.jl`、`common/head.jl`(1-60)、`MAVEN_data/MAVEN_load.jl`(1-120, 230-339, 880-999, 1427-1471)、`MAVEN_data/MAVEN_STATIC.jl`(1-80, 385-459, 540-699)、`MAVEN_data/MAVEN_SWIA.jl`(60-239, 355-434)、`MAVEN_data/MAVEN_SWEA.jl`(全文)、`MGS_data/MGS_load.jl`(全文)、`TW_data/TW_load.jl`(1-60)、`TW_data/TW_MINPA.jl`(400-479)、`Magnetic_Model/IGRF_calculate.jl`(620-821)、`models/Cold_Plasma_Dispersion_Relation.jl`(全文)、`models/Pickup_ion.jl`(1-100, 230-319)、`support_data/support_data_load.jl`(全文)。
- 写入：仅 `.agent/03_ARCHITECTURE_PLAN.md`（覆盖占位符）。
- 未修改任何源码、数据、配置文件；未执行全仓扫描。

---

## 附录 A：数据键契约表（v1，ARCH-011 权威出处）

> 符号键为准；标注 `(legacy)` 的字符串键仅登记、不强制重命名。

| 键（Symbol） | 语义 | 形状 | 单位 | 生产者 → 消费者 |
| --- | --- | --- | --- | --- |
| `:epoch` | 观测时间 | `Vector{DateTime}` | — | load_cdf/NGIMS/d1/c6/quat → 全下游 |
| `:time` | 观测时间（文本源） | `Vector{DateTime}` | — | load_kp/load_mag_l2/TW/MGS → 下游 |
| `:time_unix` | Unix 时间 | `Vector{Float64}` | s | CDF/SP_load → 二分查找 |
| `:data_load_flag` | 加载成功标志 | `Bool` | — | 所有 loader → 调用方/plot_module |
| `:filename` | 源文件路径 | `String` | — | load_MAVEN_data |
| `:B` | 磁场矢量 | `N×3` | nT | trace_mag_line(:B)、load_mag_l2(:B) → 绘图/科学 |
| `"B"` `(legacy)` | 同 `:B` | `N×3` | nT | 历史 get_mag_line_s 输入（已修复读 :B） |
| `:B_total` | 磁场模 | `Vector` | nT | MAG/trace → 绘图 |
| `:position` | 位置 | `N×3` | km（MSO） | trace_mag_line/load_mag_l2 → 绘图 |
| `:energy` / `:denergy` | 能道中心/宽度 | `(nenergy,)` 或 `(1,nmass,nenergy)` 等 | eV | 仪器模块 → 矩计算 |
| `:df` / `:df_mass_mass` | 相空间密度 | 3D/4D | `1/(cm³·(km/s)³)`（SPEDAS 约定） | STA_count2df/eflux_to_df! → sta_v_4d/Pickup |
| `:eflux` | 微分能量通量 | 3D | `1/(cm²·s·eV·sr)` 类 | STA_count2eflux → 矩/绘图 |
| `:diff_en_fluxes` | 微分通量（SWEA/SWIA） | SWEA `(ntime,64)`；SWIA coarse `(ntime,nanode,ndeflect,nenergy)`、fine 4D | 同上 | get_3dc!/get_3df!/n1d → v_3d/n_3d |
| `:quat_mso` | 姿态四元数 | `Vector{QuatRotation}` | — | load_quat → get_3dc!/3df!/Pickup |
| `:swp_ind` / `:att_ind` / `:eff_ind` | 扫参/姿态/效率索引 | `Vector{Int}` | — | c6/d1 → static_slip |
| `:mass_arr` / `:nmass` / `:nswp` / `:nenergy` / `:nbins` | STATIC 网格元数据 | — | — | c6 → static_c6_*/sta_v_4d |
| `:sc_pot` | 航天器电位 | 标量/向量 | eV | LPW → n1d/sta_v_4d |
| `:vars` + `:var_190` `(legacy)` | KP L3 旧格式 | — | — | 仅 Pickup_ion 旧路径（S9 迁移后消除） |
| `"Vars"` / `"data staute"` `(legacy)` | MGS 旧字典键 | — | — | MGS_load 输出（登记，不重命名） |
| `:S` / `:alt` / `:B_total` | 磁力线弧长/海拔/场强 | `Vector` | km/nT | get_mag_line_s |

**就地修改约定（AR-9）**：`!` 后缀 = 原地修改入参（eflux_to_df!、STA_count2df 写 `:df` 新键、get_3dc!/get_3df!）；视图型函数（static_slip）返回值与入参共享内存，docstring 必须注明；对切片写**既有键**的值会污染原数据（写新键安全）。
**单位约定（AR-19）**：文件头"IS 单位"声明仅指 SI 换算中间量；对外输出沿用 SPEDAS 约定（密度 cm⁻³、速度 km/s、通量 cm⁻²s⁻¹、df `1/(cm³·(km/s)³)`、能量 eV、质量 AMU、磁场 nT、距离 km）。PHASE 8 在 data_format.md 落表。
