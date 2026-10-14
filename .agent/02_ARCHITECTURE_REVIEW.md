# 02_ARCHITECTURE_REVIEW.md — PHASE 2：架构审查

> 状态：DONE
> 阶段：PHASE 2 - Architecture Review
> 负责：DeepSeek V4 Pro (Scientific Architect / Performance Analyst / Senior Reviewer)
> 依赖：`.agent/01_PROJECT_MAP.md`（唯一全量扫描事实源）+ 按需定点读取真实代码
> 性质：**只读审查**。本阶段不修改任何源码，仅在 `.agent/` 下写入本文档。
> 编号体系：本文档问题编号 `AR-n`（Architecture Review finding），供 PHASE 3 重构计划引用；与 01 文档调查区编号（A1–A10 / B1–B9 / C1–C20 / D1–D4）交叉引用。

---

## 1. 审查方法与范围

- 事实源：`.agent/01_PROJECT_MAP.md`（PHASE 1 全量扫描，282 行，37 个 .jl 文件 12,944 行）。
- 本阶段定点复核的文件（**未重新全仓扫描**）：
  - 包层：`src/MarsData.jl`(73)、`src/modules.jl`(463)、`src/plotting.jl`(479)
  - 公共层：`common/paths.jl`(55)、`common/constants.jl`(33)、`common/MarsCommon.jl`(472)、`common/head.jl`(1–130)
  - 数据层：`MAVEN_data/MAVEN_load.jl`(1471 全读)、`MAVEN_data/MAVEN_STATIC.jl`(1204 全读)、`MAVEN_data/MAVEN_SWIA.jl`(434)、`MAVEN_data/MAVEN_SWEA.jl`(195)、`MAVEN_data/MAVEN_data_format.json`(头部)、`MGS_data/MGS_load.jl`(154)、`TW_data/TW_load.jl`(205)
  - 科学层：`models/Cold_Plasma_Dispersion_Relation.jl`(231)、`models/Maxwellian_distribution.jl`(1–90)、`models/Pickup_ion.jl`(1–80, 240–309)、`Magnetic_Model/IGRF_calculate.jl`(1–75, 620–819)、`calculate/calculate_models.jl`(249)、`support_data/support_data_load.jl`(148)
  - 佐证 grep：拼写/export（MAVEN_plot.jl）、硬编码绝对路径全仓（18 处命中）、`global`/`eval(Meta.parse)`（MAVEN_load.jl）
- 审查维度：模块职责、耦合、依赖方向、数据结构、API、pipeline、科学计算组织、性能架构、testability、maintainability。
- 只读确认：本阶段未执行任何源码写操作；新增文件仅 `.agent/02_ARCHITECTURE_REVIEW.md`。

---

## 2. 架构总览：三层 + 两套装载体系

```
┌─────────────────────────────────────────────────────────────────┐
│ L0 包层  MarsData（Project.toml 15 个轻量 deps，可空环境加载）       │
│   Paths(TOML 路径单一出处) → 注册表读取(load_registry/load_index)   │
│   MAVEN_plot 子模块(1554 行绘图基元) → plotting.jl(plot_module)    │
│   modules.jl(MODULE_REGISTRY/load_module/@load/载体机制)            │
├─────────────────────────────────────────────────────────────────┤
│ L1 载体模块层  19 个注册模块（运行时 include 进 _MarsDataLoader）      │
│   constants ← MarsCommon ← {MAVEN_load, MAVEN_STATIC, MAVEN_SWIA,  │
│   MAVEN_SWEA, MGS_load, TW_load, TW_MINPA, calculate_models,       │
│   IGRF_calculate, Cold_Plasma_*, Maxwellian_*, Single_Particle_*,  │
│   SP_load, Call_fortran_dll}（重依赖经 LOAD_PATH 回退解析）          │
├─────────────────────────────────────────────────────────────────┤
│ L2 脚本层  include 进 Main（无 module 封装）                         │
│   head.jl(总头文件+科学工具库) function_coordinate.jl Pickup_ion.jl │
│   Octree.jl Graham.jl Build_data/*.jl example/*.jl                 │
└─────────────────────────────────────────────────────────────────┘
```

**总体评价**：L0 包层是 2024 年阶段 A 重构的高质量产物（注册表、载体机制、白名单、错误消息均精心设计）；L1 模块层职责边界清晰度中等（读取器混入科学计算、绘图模块混入数学工具）；L2 脚本层与 L0/L1 **完全脱钩**——存在**两套并行的模块装载体系**（`MarsData.load_module` 与 `head.jl` 裸 include），这是当前最大的架构裂缝。

---

## 3. 模块职责与内聚性（cohesion）

| 模块 | 名义职责 | 实际职责 | 评估 |
| --- | --- | --- | --- |
| `MAVEN_load`(1471 行) | MAVEN 统一读取入口 | 读取 + KP/NGIMS/d1/c6/quat 各 loader + **科学处理函数**（`static_c6_mass_mean/energy_mean` 旧副本、`mean_SWEA_pad_pa`、`carclu_SWEA_pad`、`SWEA_calc_shape_arr(_mars_towrads)`、`Bpc2sphere`、`cyclone_*`）+ 注册表解析/反射 | **God module**。职责横跨"读取"与"科学处理"两个域，且与 `MAVEN_STATIC`/`IGRF_calculate` 功能重叠 |
| `MAVEN_plot`(1554 行) | 绘图基元 | 绘图基元 + **通用数学工具**（`Vandermonde`/`polynomial_fit`/`vector_angle`/`logticks`/`interpolate_x_ticks`，1442–1541 行）+ 边界模型（bowshock/magnetopause） | 工具类函数放错层，见 AR-10 |
| `MAVEN_STATIC`(1204 行) | STATIC 仪器矩计算 | 纯 STATIC 处理（切片区/单位换算/矩计算/质量标志） | 内聚性**最好**的仪器模块，但文件末尾 100+ 行注释掉的测试代码混入正文 |
| `MAVEN_SWIA/SWEA` | SWIA/SWEA 处理 | 网格规范化 + 矩计算；SWEA 文件 60% 是注释掉的旧代码 | 职责清晰，死代码过多 |
| `MarsCommon`(472 行) | 公共坐标/能量/PSD | 标量约定 + 时间轴二分查找 | 内聚性好；文档明确"标量函数广播约定"，是近期质量标杆 |
| `head.jl`(521 行) | "总头文件" | **双重身份**：顶部 include 6 个重模块（装载器）+ 科学辅助函数库（safe_log_mean、bowshock/magnetopause、solve_func 等 ~20 个）+ 绘图 label 表 | 装载与工具库耦合，脚本层依赖它即隐式依赖 6 个重模块，见 AR-6 |
| `Cold_Plasma_Dispersion_Relation` | 色散关系 | 色散关系 + 全局状态初始化（`set_particles`） | 职责清晰但状态管理为反模式，见 AR-14 |
| `paths.jl` / `constants.jl` | 路径/常量单一出处 | 名副其实 | 健康 |

---

## 4. 耦合与依赖方向（dependency direction）

### AR-1 两套装载体系并存，脚本层绕过包管理器（严重度：高）
- **位置**：`common/head.jl:28-36`（裸 `include` 6 个重模块，以 `isdefined(Main, :MAVEN_load)` 判重）；`models/Pickup_ion.jl:3-4`（`include("../common/head.jl")` + `function_coordinate.jl`）；`MAVEN_data/Build_data/*.jl`、`example/*.jl`（相对路径 include）。
- **影响**：(a) 同一模块可能以两种方式装载（Main 里一份、载体内一份），**同代码双实例**，全局状态（kp_dict 等）各自独立，跨脚本状态不一致；(b) 包管理器的幂等/白名单/错误诊断（ModuleLoadError、编辑距离建议）对脚本层无效；(c) `Pickup_ion.jl:273` 在 catch 分支又硬编码 `D:/CODE/Package_for_Julia/` 回退 include，形成**第三套装载路径**。
- **方向**：PHASE 3 应把 head.jl/Pickup_ion/Build_data 迁移到 `MarsData.@load` 体系，消除裸 include。

### AR-2 模块加载期 IO 副作用——加载即执行（严重度：高）
- **位置**：
  - `MAVEN_load.jl:27-32` 模块加载期读 `MAVEN_data_format.json`；`MAVEN_load.jl:1460-1462` 模块加载期**无条件 open** `filename_lists.json`（不存在即抛错，= A1）；
  - `IGRF_calculate.jl:788-795` 模块加载期 `read_gh()` 读系数文件 + `CALCULATE_SCHMIDT_COEFFICIENTS()` 预计算；
  - `support_data_load.jl:13-14` 模块加载期读 INI + `println` 副作用（= A3）；
  - `MAVEN_SWIA/SWEA` 加载期无 IO（好）；`MAVEN_STATIC` 加载期仅定义 `ion_mass_range`（好）。
- **影响**：fresh clone 上 `load_module(:MAVEN_load)` 必失败（A1）；任何测试/文档构建都必须先伪造完整数据环境；模块装载不再是纯代码操作而是 IO 操作。**这是全仓最大的 testability 障碍**。
- **方向**：所有加载期 IO 改为惰性（首次调用时读取/构造，缺省回退空值）；IGRF 系数读取保留惰性 const 或注入。

### AR-3 模块级相对父模块引用依赖装载顺序（严重度：中）
- **位置**：`common/MarsCommon.jl:2`（`using ..constants`）；模块内 `include(constants.jl)` 与 `include(MarsCommon.jl)` 混用。
- **影响**：`MarsCommon` 的 `using ..constants` 只有在 `constants` **先**装入同一载体时才能解析——该顺序由 `ModuleSpec.deps` 的语义声明保证（`src/modules.jl:360-362`），但**编译器无法静态校验**：若直接 `include("common/MarsCommon.jl")`（脚本层常见）则炸 `UndefVarError`。声明式 deps 与实际 include 依赖存在两套真相（例：`MAVEN_SWEA` deps 仅 `[constants]` 而文件内只 include constants，一致；但 `TW_MINPA` deps 仅 `[constants]` 却含私有 `slice2d_cal_rot` 副本，语义上依赖 function_coordinate 的实现）。
- **方向**：统一各模块 include 策略（全部走 deps 装载 + 相对父引用，或全部自带 include），并把"模块实际 include 了什么"纳入 `validate_registry` 校验。

### AR-4 科学计算模块的全局可变状态（严重度：高）
- **位置**：`Cold_Plasma_Dispersion_Relation.jl:6-39`（`Nparticles/Ω_n/Π_2` 全局 + `set_particles` 副作用初始化）；`IGRF_calculate.jl:796,817-820`（可变全局 `B_compress` + `set_B_compress`，注释自认"非线程安全"）；`MAVEN_load.jl:30,188,1454`（全局 `kp_dict` + `change_kp_read_data` 全局重设，= C15）。
- **影响**：函数结果依赖"之前调用了什么"（隐式时间耦合：`Dispersion_Relation` 必须先 `set_particles`，无任何防御）；同一进程多分析脚本/多线程共享状态互相污染；测试无法并行/隔离。
- **方向**：把状态改为显式参数（`Dispersion_Relation(θ, freq, Πe, Ωe, particles)`）或不可变配置对象；`kp_dict` 改为 `load_kp` 的 kwarg 参数 + 默认值常量。

### AR-5 脚本层对"外部预置全局变量"的隐式契约（严重度：高）
- **位置**：`models/Pickup_ion.jl:1`（注释明示需预置 `time_event/instrument_mode/spice_name`）、`:60`（"minpa" 分支需全局 `TW_minpa_data`）、`:240-247`（直接消费 `instrument_mode/spice_dict/time_event/dtime`）、`:255-309`（`global MAVEN_data/date_str/...` 十余个全局赋值）。
- **影响**：该脚本只能以"预置变量的 include"方式运行，无法封装为可调用函数/模块；任何一次重构都可能在几十个隐式依赖上翻车；testability 为零。
- **方向**：PHASE 3 起把 Pickup_ion 逐步函数化（入口函数显式接收 `time_event/instrument_mode/...`，数据装载走 `@load`）。

### AR-6 横向耦合：读取模块内部复制其他模块的实现（严重度：中）
- **位置**：`MAVEN_load.jl:889-904`（`Bpc2sphere` 副本，与 `IGRF_calculate.jl:121` 重复，= B3）；`MAVEN_load.jl:1229-1254`（`cyclone_frequency/cyclone_R` 与 `calculate_models.jl:116-158` 的 `cyclotron_radius/cyclotron_frequency`、`Single_Particle_Orbit.jl:355` 三套近似实现，= B8）；`MAVEN_load.jl:989/1057`（`static_c6_*` 旧副本，= B2）；`MAVEN_load.jl:794` 与 `MAVEN_SWEA.jl:106`（同名 `load_quat` 不同返回类型，= B6）。
- **影响**：同一物理量的实现分散，单位/命名不一致（cyclone_R 输入 m/s 输出 m vs cyclotron_radius 输入 nT/eV 输出 (Hz,m,m/s)），调用方极易用错；修复一处不改他处即产生行为分叉。
- **方向**：PHASE 3 去重计划（删坏函数、选权威实现、其他模块转依赖）。

---

## 5. 数据结构与跨模块契约

### AR-7 全链路无 schema 的 `Dict{Symbol,Any}`（严重度：中）
- **位置**：`MAVEN_load.load_MAVEN_data`（`Dict{String,Any}` 主字典 → 各 loader 的 `Dict{Symbol,Any}`）；`src/plotting.jl` 全程 `data_dict["..."][:...]`；`MAVEN_STATIC`/`SWIA`/`SWEA`/`TW_*` 全部消费/产出此类字典。
- **影响**：(a) **类型不稳定**：`Any` 值导致每次访问动态分派，矩计算热路径（sta_v_4d 对 (nmass,nbins,nenergy) 数组逐元素广播）有实质性能代价；(b) **契约即键名**：`:data_load_flag/:epoch/:time/:energy/:denergy/:diff_en_fluxes/:swp_ind/:att_ind/:eff_ind/...` 的拼写与形状约定散落在 20+ 文件，任何拼写漂移（如 `:electorn_density`、`"data staute"`）都要到运行时 KeyError 才暴露（典型实例 C3：`get_mag_line_s` 读字符串键 `"B"`、`trace_mag_line` 产出 Symbol 键 `:B`）；(c) 无编译期/静态 schema 校验，docs/src/data_format.md 只覆盖部分产品。
- **评估**：对"CDF 变量名即数据模型"的场景，Dict 有其合理性；**不建议 PHASE 3 全面类型化**（改动面过大且科学风险高）。建议折中：PHASE 3 先集中**键名与形状常量**（一个 `DataKeys` 模块），PHASE 4+ 对热点（STATIC 矩计算）引入轻量 struct/`NamedTuple` 包装并保留 Dict 兼容。

### AR-8 数据键不一致清单（严重度：低，但每项都是定时炸弹）
- `:time`（KP/TW/MGS）vs `:epoch`（CDF/NGIMS/d1/c6/quat）同一语义两键名；
- `:data_load_flag`（新）vs `"data staute"`（MGS_load.jl:87 旧拼写，且 MGS 用 `Dict{String,Any}`）；
- `:B`（trace_mag_line 输出）vs `"B"`（get_mag_line_s 读取，C3）；
- `:vars` + `:var_190`（KP L3 旧格式）vs 新 `kp_dict` 语义键（C17：plot_module 双键 `"KP_l3"`/`"KP"` 兼容）；
- `:P_mso/:B_mso`（c6_v3d）vs `:pos_sc_mso/:mag_mso`（d1_v4d）同语义不同键。
- **方向**：PHASE 3 输出一份《数据键契约表》（docs/ 或 .agent/），后续重构一律以表为准。

### AR-9 就地修改与视图别名效应（严重度：中）
- **位置**：`MAVEN_STATIC.static_slip`（`@views` 生成切片并浅拷贝字典，466-516 行）；`STA_count2df/STA_eflux2df`（原地写 `dat[:df]`）；`MarsCommon.eflux_to_df!`（原地写 `:df`）；`src/plotting.remove_0_point!`（原地置 NaN）；`models/Graham.graham_scan!`（原地改入参）。
- **影响**：`static_slip` 返回的切片与原始全时段数组**共享内存**；对切片调用 `STA_count2df` 会写 `dat[:df]` 新键（安全），但任何对切片既有键的原地写会污染原数据；`eflux_to_df!` 后绘图例程再改 `:diff_en_fluxes` 会产生隐蔽联动 bug。docstring 已提示（static_slip 注意事项），但"文档提示"代替不了机制防御。
- **方向**：PHASE 3 统一约定：视图型函数返回只读视图（或 `deepcopy` 型变体），`!` 后缀只用于明确原地操作。

---

## 6. API 与命名

### AR-10 公开 API 拼写错误已固化（严重度：低–中）
- `caculate_mag`（MGS_load.jl:112）、`carculate_minimum_energy`（Cold_Plasma:187）、`carclu_SWEA_pad`（MAVEN_load.jl:1124）、`alfven_weve`（Cold_Plasma:226）、`WaveSpactra_heatmap` export 死名（MAVEN_plot.jl:18 vs 定义 `WaveSpectra_heatmap`:958，= A7）、JSON 键 `electorn density`（C16）、`discribe`（load_c6_v3d.jl:771）。
- **影响**：白名单机制下 export 死名无功能影响，但**拼写已进入 MAVEN_data_format.json 的 load 函数名字符串**（`eval(Meta.parse(value[4]))` 反射注册，A9），重命名需要 JSON + 代码 + 调用方三方同步；历史论文/脚本兼容性也绑死这些名字。
- **方向**：PHASE 3 建立"兼容别名层"（旧名 = 新名转发 + `@deprecate` 或 docstring 标记），不直接改 JSON。

### AR-11 同义函数多版本并存，无弃用策略（严重度：中）
- `sta_v_4d` vs `sta_v_4d_new`（MAVEN_STATIC.jl:543/613，后者是手写优化版，注释称"数值等价"但**无测试证明**）；
- `static_c6_mass_mean/energy_mean` 新旧两份（MAVEN_load.jl vs MAVEN_STATIC.jl，新版多 `:df` 分支，B2）；
- `TimeFormat` 双份不同格式（src/plotting.jl:26 HH:MM:SS.mmm vs Single_Particle_Orbit.jl:30 MM:SS.mmm，B7）；
- `load_quat` 同名不同返回类型（Dict vs 裸 Matrix，B6）；
- `sta_v_1d` 的 `time_ind` 参数已废弃仍留在签名（MAVEN_STATIC.jl:973 注释"暂时无效"）。
- **影响**：调用方无法知道哪个是权威版；`_new` 命名一旦被旧版行为分叉，科学结果将出现两套数字（违反 R5 科学一致性）。
- **方向**：PHASE 3 对每个重复对做**数值等价验证**（golden 对比）后删旧留新，删除前在 CHANGELOG 记录。

### AR-12 默认参数引用未定义全局（严重度：高）
- **位置**：`MAVEN_STATIC.jl:403`（`STA_count2eflux(dat; m_int=m_int)`）、`:439`（`STA_eflux2df(dat; m_int=m_int)`）——默认值 `m_int` 在模块内**不存在**（`ion_mass_range` 里只有每离子条目内的 `m_int` 字段）。
- **影响**：任何人以默认参数调用这两个公开函数，会得到 `UndefVarError`（在默认参数求值时触发）。这是 PHASE 1 未列入清单的**新发现**（属于 B 类坏函数）。
- **方向**：改为必需参数或 `m_int::Real`（删除默认值）；同时全仓 grep 类似模式。

### AR-13 白名单覆盖面不足 + 两套入口的 API 不一致（严重度：低）
- **位置**：`src/modules.jl:59-120`（19 个模块仅 MarsCommon/MAVEN_load/IGRF_calculate 三个有 `allow`）。
- **影响**：其余 16 个模块 `@load` 后必须全限定名调用，脚本层（head.jl 生态）习惯裸名（因裸 include 全部进 Main），迁移时会大量 `UndefVarError`——这是 head.jl 生态迟迟不迁移的阻力之一。
- **方向**：PHASE 3 逐步补全白名单（以 docs/src/api.md 的公开函数清单为准）。

---

## 7. Pipeline 组织

### AR-14 读取管线：反射注册 + 线性文件匹配（严重度：中）
- **位置**：`MAVEN_load.jl:1455-1459`（`eval(Meta.parse(value[4]))` 把 JSON 字符串变函数引用，= A9）；`MAVEN_load.jl:92-102`（`find_file_of_data` 对文件名列表线性 `occursin` 子串匹配）。
- **影响**：(a) JSON 即代码入口：JSON 被篡改/键名漂移时产生任意函数解析（安全/可审计性）；(b) 子串匹配 O(N) 且**误匹配风险**（日期串 `yyyymmdd` 可能命中其他日期前缀，如 `20250101` 匹配 `...202501010...` 与 `...120250101...`）；(c) `load_MAVEN_data` 对每个 model 重新调 `find_file_of_data`（重复构建全路径列表 `root_path .* path .* filename_list`，广播拼接每次 O(M) 分配）。
- **方向**：PHASE 3 用显式注册表（Symbol => Function 的 Dict，代码内构建）替代字符串反射；文件匹配改为"先建日期→文件索引、再精确正则匹配"。

### AR-15 静默失败路径过多（严重度：中）
- **位置**：`MAVEN_load.jl:241-247`（`load_cdf` try-catch 后 `println` 吞错，返回 `Dict(:data_load_flag=>false)`）；`MGS_load.jl:69-78`（坏行 try-catch 跳过不报）；`load_MAVEN_data` 单文件缺失不中断（设计如此，是**优点**）；`get_3dc!/get_3df!` quat 缺失仅 `@warn` 并全置 false（MAVEN_SWIA.jl:92-95）。
- **影响**：批处理中错误被稀释，用户可能拿 `:data_load_flag==false` 的静默空数据画图而不自知（plot_module 检查 flag 后静默跳过面板）。容错是好事，但当前**无聚合错误报告**（哪些模型失败、为何失败）。
- **方向**：PHASE 3 给 `load_MAVEN_data` 增加 `errors` 汇总返回（或可选 `verbose`），保留 flag 语义。

### AR-16 绘图管线与数据契约硬绑定（严重度：中）
- **位置**：`src/plotting.jl:71-479`——`plot_module` 对 `data_dict` 的依赖包括固定 12 面板名 + 键 `"KP_l3"/"KP"/"MAG_ss1s_cdf"/"MAG_model_ss"/"STATIC_d1_v4d"/"SWIA_mom"/"STATIC_c6"/"STATIC_c6_origin"/"STATIC_mass"/"LPW_mrgscpot"/"LPW_wave"/"SWEA_spec"/"swea_pad_low|high"/"SWIA_svy_spec"` 及每个子字典的 `:data_load_flag/:epoch/:time/:MSO_x/...`，无任何缺失键防御（C17 双键兼容只是打补丁）。
- **影响**：数据键契约任何一处变化，绘图立即 KeyError 且报错位置不指向数据缺失而是面板代码深处；无法单独测试面板（必须造全量假数据）。
- **方向**：PHASE 3 起面板函数参数化（每个面板独立函数 + 明确入参），`plot_module` 退化为装配器。

---

## 8. 科学计算组织

### AR-17 科学核心与仪器读取混层，且存在"读取器内的科学函数"（严重度：中）
- **位置**：`MAVEN_load.jl` 内的 `mean_SWEA_pad_pa/carclu_SWEA_pad/SWEA_calc_shape_arr/SWEA_calc_shape_arr_mars_towrads/static_c6_*（旧）/cyclone_*`（= B2 部分）与 `MAVEN_STATIC/SWEA/SWIA/TW_MINPA` 的科学处理并存。
- **影响**：科学函数分散在两个模块，跨模块调用图混乱（plot 管线中 `MAVEN_load.carclu_SWEA_pad` 被注释掉、又直接消费数据字典键）；单元测试与科学验证无法聚焦。
- **方向**：PHASE 3 把 MAVEN_load 中的纯科学处理函数迁移到对应仪器模块（保留 MAVEN_load 转发别名），删除坏副本。

### AR-18 硬编码物理/仪器常数无出处（严重度：高，科学风险）
- **位置**：`MAVEN_SWIA.jl:274`（`Const = 7.224566339926571e-7`）、`:430`（`sqrt(mass/(2*erg_per_eV)) * 8.8` 的 8.8，C11）、`:45`（`denergy = energy .* 0.15` 硬编码 15% 分辨率）、`:139`（fine 12×48 裁剪）；`MAVEN_SWEA.jl:57`（`zeros(64)` 64 能道）、`:79`（`ff` 截断）、`:54`（`tiny = 1.0-31` 笔误，C4）；`MAVEN_load.jl:1156`（`zeros(1,1,64)`）、`:1356-1357`（`n_e=52; indx=13:64`）、`:1332-1350`（df_iono 模板数组）；`TW_MINPA.jl:445`（积分弃用 denergy 改 `0.2/2` 经验常数，C6）。
- **影响**：这些常数是 SPEDAS 移植产物，一旦数值与参考实现不符（如 C4 笔误、C6 存疑），全部下游科学结论静默偏移；无测试基线时无法察觉。**违反 R4/R5 的"科学结果验证"前置条件**。
- **方向**：PHASE 3 逐项建立"常数出处注释 + SPEDAS 对照表"（.agent 文档），PHASE 4/5 以 golden 数据验证；**任何常数修改必须先过科学验证，禁止顺手改**。

### AR-19 单位约定混杂（严重度：中）
- **位置**：文件头统一声明"IS 单位"（MAVEN_load.jl:6、MAVEN_STATIC.jl:2），但实际：SPEDAS 单位（df `1/(cm³·(km/s)³)`、密度 cm⁻³、速度 km/s、通量 cm⁻²s⁻¹，MAVEN_STATIC.jl:197-205 自述）；`MarsCommon` 相对论 PSD（s³·m⁻⁶ 量级）与 `ion_eflux_to_psd_approx`（SPEDAS 近似）两套并存；`constants.me_eV_per_km_s2`（电子质量以 eV/(km/s)² 表示）这类混合单位常量。
- **影响**：单位换算错误是最常见科学 bug；两套 PSD 函数并存让调用方无法判断该用哪个。
- **方向**：PHASE 3 出一张《单位约定表》，每个科学函数 docstring 标注单位（部分已做，继续补齐）。

### AR-20 磁力线追踪默认一阶 Euler（严重度：高，科学精度）
- **位置**：`IGRF_calculate.jl:761-762`（`trace_mag_line` 硬编码调用 `mag_trace_Euler_step`，注释自认"一阶精度要求很小步长、磁力线会偏离真实轨迹"；RK4/自适应版本 `mag_trace_rk4*` 存在但被注释掉，= C1）。
- **影响**：默认路径产出的磁力线有系统误差；`step=0.5` km 默认值下长磁力线（max_trace=30000）径向漂移累积；论文级结果风险。
- **方向**：**改动前必须科学验证**（R4/R5）：先建 Euler vs RK4 vs 自适应对比基准，再由科学负责人决定默认值；本阶段只记录不改。

---

## 9. 性能相关架构问题

### AR-21 零 benchmark 基线（严重度：高，违反 R2）
- **位置**：全仓无 BenchmarkTools 脚本；`docs/reports/` 无性能报告；`MAVEN_STATIC.jl` 尾部注释掉的 `@time` 测试（1126-1129 行）是唯一性能痕迹。
- **影响**：R2 规定"性能优化必须 benchmark"；当前任何优化（如 sta_v_4d_new 已做的）都无法证明收益，任何回归无法察觉。
- **方向**：PHASE 3 建 `benchmark/` 基线（数据读取、STA_count3df、sta_v_4d(_new)、load_cdf、绘图、磁力线追踪 6 项），固化到 CI。

### AR-22 类型不稳定热路径（严重度：中）
- **位置**：`Dict{Symbol,Any}` 取值（所有矩计算函数）；`sta_v_4d` 对 (nmass,nbins,nenergy) 数组做多重全数组广播与掩膜临时分配（MAVEN_STATIC.jl:577-586）；`static_c6_*` 的 `for i in 1:ntime` 逐时刻切片循环（MAVEN_STATIC.jl:92-98）；`STA_count2df_all` 自注释"开销极大，考虑替换掉"（274 行）；`plot_module` 中 `convert.(Float64, ...)` 与多次 `time2x` 重复二分（src/plotting.jl:190 等）。
- **影响**：STATIC c6 全时段矩计算与绘图合成是用户主路径；`sta_v_4d_new` 的手写优化说明作者已知痛点，但两版并存 + 无等价测试 = 风险。
- **方向**：PHASE 4 以 AR-21 基线为准做定点优化（先证明 sta_v_4d_new ≡ sta_v_4d，再删旧版）；PHASE 3 仅登记。

### AR-23 ccall 边界与逐点调用模式（严重度：中）
- **位置**：`mag_trace_Euler_step` 每步调用 `IGRF_fortran`（ccall DLL，含全局 `B_compress` 查找，IGRF_calculate.jl:637,796-820）；`Call_fortran_dll` 的 linear_growth_rate/Bspline 每次调用重开 DLL 路径（硬编码，A6）。
- **影响**：30000 步追踪 = 30000 次 ccall；`B_compress` 非 const 全局的每次查找也进 ccall 参数路径。
- **方向**：PHASE 4 评估批量 ccall 接口或 Julia 端球谐实现（**科学验证优先**）；Call_fortran_dll 路径改为 Paths 解析。

### AR-24 包加载与编译成本（严重度：低，既定设计）
- **位置**：`src/MarsData.jl:58-66`（`using MarsData` 即加载 CairoMakie/Makie + include 1554 行 MAVEN_plot，= A10）；载体模块每次新进程运行时 include 编译（无预编译）。
- **影响**：冷启动 `using MarsData` 数十秒级；但属 README 既定设计（轻量 deps + 载体机制），本阶段仅记录不改。

---

## 10. Testability

### AR-25 模块不可在无数据环境加载（严重度：高）
- 由 AR-2（加载期 IO）+ AR-5（脚本隐式全局）+ A2/A5/A6（硬编码路径）共同导致：CI 上 `load_module(:MAVEN_load)` 需要 `MAVEN_data_format.json`（存在）而 `filename_lists.json`（**不存在**）；`load_module(:IGRF_calculate)` 需要 `gh_gao` + Windows x64 DLL；`SP_load` 需要 INI。任何"干净环境"测试都无法开始。
- **方向**：PHASE 3 第一优先：A1 修复（缺省空 dict + 惰性加载）让 runtests 冒烟可跑；随后逐模块惰性化 IO、路径注入化。

### AR-26 科学计算零自动化测试（严重度：高，= D1）
- **位置**：`test/runtests.jl`（176 行）仅覆盖 src/modules.jl；坐标变换/能量换算/矩计算/磁场/色散/轨道/拟合 **零测试**；无 golden 数据、无数值回归。
- **影响**：任何重构（即使是"纯搬移"）都无法证明科学结果不变——直接违反 R3/R5 的"重要修改必须有测试/科学结果验证"。
- **方向**：PHASE 3 建测试基座：MarsCommon 纯函数单测（低成本高收益）+ 小尺寸合成数据测矩函数 + IGRF 已知值验证（如行星表面偶极场解析值）。

### AR-27 全局状态与脚本层阻隔测试隔离（严重度：中）
- `kp_dict`/`set_particles`/`B_compress` 的进程级可变状态使测试无法并行、前后污染；head.jl/Pickup_ion/Octree/Graham 无 module 无法 `import` 单测。
- **方向**：随 AR-4/AR-5 修复同步解决。

---

## 11. Maintainability

### AR-28 三份"坏的" calculate_mag 是复制退化的活标本（严重度：高）
- **位置**：`MAVEN_load.jl:923-932`、`TW_load.jl:128-137`、`MGS_load.jl:112-121`——三份同源函数，**全部**引用未初始化全局 `data`（调用必 UndefVarError），且 docstring 均已自曝（B1）。
- **影响**：复制粘贴导致三处同时腐烂且无人使用/无人删；占用公共 API 名（`caculate_mag` 拼写错）。
- **方向**：PHASE 3 直接删除三份坏函数（docstring 已确认无用），在 CHANGELOG 记录。

### AR-29 死代码与演进痕迹堆积（严重度：低）
- **位置**：MAVEN_STATIC.jl:1090-1204（100+ 行注释掉的测试）、MAVEN_SWEA.jl:136-195（整段注释测试）、TW_load.jl:10-47（注释掉的旧 load_mag）、MAVEN_load.jl:1465-1471（注释测试）、load_c6_v3d 内 40 行注释掉的 Fortran 版（702-746 行）、`SWEA_calc_shape_arr` 内 `deriv` 中第一组 `d` 计算被覆盖（1311-1313 行被 1323 行覆盖）。
- **影响**：阅读噪音与误导（误把注释代码当实现）；维护者不知道哪些是"还在用的旧版"。
- **方向**：PHASE 3 统一清理策略：注释块移除（git 历史可追溯），保留"参考 IDL 文件"类注释。

### AR-30 文档质量两级分化（严重度：低）
- **强项**：近全量中文 docstring（每函数含功能/参数/返回/注意），`docs/src/api.md` 357 行索引，MarsCommon 的"标量约定"文档尤其优秀。
- **弱项**：docs 产品名滞后（D3：KP_l3/MAG_pc1s_l3 已下架）、`docs/src/data_reading.md` 与当前注册表不符、无数据键契约文档（AR-8）。
- **方向**：PHASE 8 按计划同步；PHASE 3 顺手补《数据键契约表》。

---

## 12. 既有优点（重构红线，不得破坏）

1. **MarsData 包层设计精良**：注册表单一事实源、`_spec_of` 编辑距离错误建议、`ModuleLoadError` 保留 cause、`validate_registry` 自检、`@load` 白名单逐名引入、载体机制文档化——阶段 A 产物质量高（src/modules.jl）。
2. **Paths 单一出处**：TOML 写端/INI 只读兼容/默认值兜底，路径由文件位置推导与 CWD 无关（common/paths.jl）。
3. **MarsCommon 标量约定**：标量函数 + 广播调用 + `::Real` 标注防误用 + docstring 明确单位/角度制——近期质量标杆。
4. **searchsortednearest 二分查找**：O(log N) 并文档禁止线性扫描（MarsCommon.jl:417-459）。
5. **容错设计**：load_cdf try-catch、MGS 坏行跳过、单文件缺失不中断批加载、`:data_load_flag` 语义统一。
6. **仪器矩计算组织**（MAVEN_STATIC）：切片→单位换算→矩积分的三步管线清晰，SPEDAS 来源注释完整。
7. **models/ 物理模型模块化**：Maxwellian/Single_Particle_Orbit/Cold_Plasma 相互独立、职责单一。
8. **文档习惯**：中文 docstring 全覆盖是重构可持续的保障。

---

## 13. 架构债务优先级与建议路线图（PHASE 3 输入）

> 严重度定义：P0 = fresh clone 不可运行/必崩路径；P1 = 高风险正确性/科学风险；P2 = 结构性债务；P3 = 长期演进。

| 优先级 | 编号 | 内容 | 对应 01 文档 ID |
| --- | --- | --- | --- |
| **P0** | AR-2/AR-25 | `filename_lists.json` 缺失 → 缺省空 dict + 惰性加载（恢复 fresh clone 与 runtests 冒烟） | A1 |
| **P0** | AR-28 | 删除三份坏的 `calculate_mag/caculate_mag` | B1 |
| **P0** | AR-12 | `STA_count2df/STA_eflux2df` 默认参数 `m_int=m_int` UndefVarError | 新发现 |
| **P0** | AR-8 | `get_mag_line_s` 键 `"B"` vs `trace_mag_line` 键 `:B` 不一致 | C3 |
| **P1** | AR-20 | 磁力线默认一阶 Euler → **先建精度对比基线，科学负责人定夺，禁止顺手改** | C1 |
| **P1** | AR-18 | 硬编码常数逐项建出处注释 + SPEDAS 对照（含 tiny 笔误、v_3d 4D 索引、TW_MINPA denergy） | C4/C5/C6/C11 |
| **P1** | AR-11 | `sta_v_4d` vs `sta_v_4d_new` 数值等价验证后删旧 | B 区/C18 |
| **P1** | AR-2 | IGRF/SP_load 模块加载期 IO 惰性化 | A3 |
| **P2** | AR-1 | 统一装载体系：head.jl/Pickup_ion/Build_data 迁移到 `@load` | A4/A5 |
| **P2** | AR-4/AR-27 | 全局状态封装（kp_dict/set_particles/B_compress 显式参数化） | C8/C15 |
| **P2** | AR-7/AR-8 | 数据键契约表 + 键名常量集中 | 新产出 |
| **P2** | AR-14/AR-15 | 反射注册改显式注册；find_file_of_data 索引化；错误聚合报告 | A9 |
| **P2** | AR-21/AR-26 | benchmark 基线与测试基座（MarsCommon 单测 + IGRF 已知值 + 合成数据矩测试） | D1/D2/R2/R3 |
| **P3** | AR-7 | 热点数据结构 schema 化（STATIC 矩计算轻量 struct） | — |
| **P3** | AR-10/AR-13 | 拼写别名层 + 白名单补全 | A7/C16 |
| **P3** | AR-29 | 死代码清理 | — |

**给 PHASE 3 的三条硬约束**：
1. 任何 P1 科学项（AR-18/AR-20）的修改必须先有科学结果验证记录（对照 SPEDAS/解析值/golden 数据），否则只登记不修改（R4/R5）。
2. P0/P1 修复不得触碰 Python 侧与载体机制（00 文档 R7 + 01 文档 §2.3 红线）。
3. 每个 PR 级改动必须携带对应 benchmark/测试证据（R2/R3）。

---

## 14. 只读合规声明

- 本阶段执行的操作：读取 `.agent/01_PROJECT_MAP.md` + 定点读取 15 个源码/数据文件（清单见 §1）+ 3 次 grep 佐证；写入 `.agent/02_ARCHITECTURE_REVIEW.md`。
- 未修改任何源码、数据、配置文件；未执行全仓扫描。
- git 工作区净变化仅 `.agent/`（本文件覆盖占位符）与 `.agent-teams/`（团队状态，工具管理）。
