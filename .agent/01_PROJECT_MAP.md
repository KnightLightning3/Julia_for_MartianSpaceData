# 01_PROJECT_MAP.md — PHASE 1：项目全量扫描与映射

> 状态：DONE（本项目唯一一次全量扫描；后续阶段一律只读本文件 + 完成任务所需的最小源码，不得再重复全仓扫描）
> 阶段：PHASE 1 - Project Discovery
> 负责：DeepSeek V4 Pro (Project Explorer / deepseek-explorer)
> 依赖：`.agent/00_PROJECT_SCOPE.md`（范围与边界以此为准；Python 侧只登记、不深扫）
> 扫描方式：全部 37 个 `.jl` 文件（共 12,944 行）逐个通读 + 根目录清单文件 + `MAVEN_data/*.json` 结构提取 + `docs/`/`test/`/`example/`/`Build_data/` 目录登记。**未修改任何源码/数据文件**（git status 仅 `.agent/`、`.agent-teams/` 为新增未跟踪）。

---

## 1. 仓库结构与文件清单（Julia 侧全量）

```
Julia_for_MartianSpaceData/
├── src/                     # [包] MarsData（轻量公共 API + 绘图 + 模块装载管理器）
│   ├── MarsData.jl          (73)  包主模块：paths/registry/index + MAVEN_plot 子模块 + plotting + modules
│   ├── modules.jl           (463) MODULE_REGISTRY（19 个条目）+ load_module/@load/validate_registry/载体机制
│   └── plotting.jl          (479) plot_module / TimeFormat / remove_0_point!（概览绘图合成）
├── common/                  # [模块+脚本] 公共层
│   ├── constants.jl         (33)  module constants：SI 常数、火星参数、换算因子
│   ├── paths.jl             (55)  module Paths：TOML 优先/旧 INI 兼容的路径解析唯一出处（Julia 侧）
│   ├── MarsCommon.jl        (472) module MarsCommon：坐标/能量/PSD 标量函数 + searchsortednearest(_range)
│   ├── function_coordinate.jl (265) 脚本（无 module）：slice2d_cal_rot、pa_*、MINPA_*、bowshock_zero
│   └── head.jl              (521) 脚本（无 module）：include 各重模块的"总头文件"+ 科学辅助函数库
├── MAVEN_data/              # [模块+脚本] MAVEN 读取/处理/绘图/构建
│   ├── MAVEN_load.jl        (1471) module MAVEN_load：统一读取入口 load_MAVEN_data / load_cdf / load_kp / …
│   ├── MAVEN_plot.jl        (1554) module MAVEN_plot：绘图基元（已包化为 MarsData.MAVEN_plot）
│   ├── MAVEN_STATIC.jl      (1204) module MAVEN_STATIC：STATIC 仪器矩计算（sta_v_4d 等 15+ 函数）
│   ├── MAVEN_SWIA.jl        (434) module MAVEN_SWIA：get_3dc!/get_3df!/n_3d/j_3d/v_3d/n_1d
│   ├── MAVEN_SWEA.jl        (195) module MAVEN_SWEA：n1d / load_quat
│   ├── MAVEN_data_format.json (13 KB) 数据产品注册表（data_model：55 个产品 → 读取函数名字符串）
│   ├── KP_vars.json         (179 KB) KP 变量表（Build 脚本用）
│   └── Build_data/          # 派生数据构建（.jl 4 个 + .py/.pro 4 个，脚本式）
│       ├── build_vsc.jl (109) / STATIC_VD.jl (220) / STATIC_vfd_3d.jl (226) / ngi整合.jl (58)
├── MGS_data/MGS_load.jl     (154) module MGS_load：MGS 磁场文本读取（root_path 硬编码 E:/MGS/）
├── TW_data/
│   ├── TW_load.jl           (205) module TW_load：天问磁场 2C 读取/姿态旋转矩阵（root_path 硬编码）
│   └── TW_MINPA.jl          (759) module TW_MINPA：MINPA 离子数据读取/PSD/速度矩（root_path 硬编码）
├── models/                  # [模块+脚本] 物理模型
│   ├── Cold_Plasma_Dispersion_Relation.jl (231) module：冷等离子体色散关系（全局状态）
│   ├── Maxwellian_distribution.jl (344) module Maxwellian_Distribution：麦克斯韦拟合（线性+非线性）
│   ├── Single_Particle_Orbit.jl (424) module：RK4/Tsit5 粒子轨道（DifferentialEquations）
│   ├── Pickup_ion.jl        (475) 脚本（无 module）：拾取离子分析主流程（依赖 head.jl）
│   ├── Octree.jl            (259) 脚本（无 module）：八叉树空间剖分（GLMakie）
│   └── Graham.jl            (121) 脚本（无 module）：Graham 凸包
├── Magnetic_Model/
│   ├── IGRF_calculate.jl    (821) module IGRF_calculate：IGRF 110 阶磁场 + 磁力线追踪（Fortran DLL）
│   ├── IGRF_DLL.dll               Fortran 动态库（ccall 目标，Windows x64）
│   └── gh_gao / gh_gao.txt        高斯系数（Fortran 无格式 + 文本备份）
├── calculate/calculate_models.jl (249) module calculate_models：旋转/逃逸能量/回旋/线性拟合
├── support_data/support_data_load.jl (148) module SP_load：OMNI2/太阳风参数读取（依赖旧 INI）
├── test/runtests.jl         (176) Julia 测试（仅模块装载管理器）
├── example/MAVEN_plot_sample/
│   ├── MAVEN_overview_plot_sample.jl (195) 单日概览图示例（含 KP_l3 兼容别名、IGRF 模型磁场）
│   └── MAVEN_overview_cases.jl (208) 批量案例（2 小时窗口切分）
├── call_fortran_dll.jl      (148) module Call_fortran_dll：线性增长率/B 样条 DLL 封装（路径硬编码）
├── download_data/get_all_orbit.jl (114) 脚本：按轨道划分数据（Python 目录内的 Julia 遗留脚本）
├── Project.toml             # 包 MarsData（15 个轻量 deps，julia 1.10）
├── Manifest.toml            # julia_version 1.10.0，1782 行
├── requirement.jl           # 全量 Julia 依赖安装清单（历史脚本，与 [deps] 不同步）
├── docs/                    # 文档唯一根（src/ 6 页权威源 + wiki/ + references/ + reports/ + make.jl）
├── tests/                   # [Python] P0–P3 回归测试 —— out of scope（仅登记）
└── （Python 侧 download_data/、martian_pipeline/、config/、tools/ —— out of scope，见 00_PROJECT_SCOPE.md）
```

---

## 2. 模块地图（Julia 侧 19 个可装载模块 + 5 个脚本文件）

### 2.1 已注册进 `MarsData.MODULE_REGISTRY` 的模块（`src/modules.jl`）

| 注册键 | 文件 | kind | deps | allow 白名单 | 关键内容 |
| --- | --- | --- | --- | --- | --- |
| `constants` | common/constants.jl | module | — | — | 物理常数（e、me、mp、μ0、c、k_B、M_Mars、R_Mars=3393.5 km、E0_electron_keV、KEV_PER_AMU、AMU_TO_PROTON_MASS_RATIO…） |
| `MarsCommon` | common/MarsCommon.jl | module | constants | searchsortednearest、e_energy2v、ion_energy2v | 标量约定：球/笛卡尔变换、能量↔速度（相对论）、eflux→PSD（相对论/近似两版）、doppler_shift、eflux_to_df!、位置派生（alt/local_time/latitude）、时间轴二分查找 |
| `Paths` | common/paths.jl | **preloaded** | — | — | TOML(`config/settings.toml`)优先、旧 INI 只读兼容、默认 E:/MAVEN|Tianwen-1|MGS；project_root/index_path |
| `MAVEN_load` | MAVEN_data/MAVEN_load.jl | module | constants, MarsCommon, Paths | load_cdf、load_MAVEN_data | 统一读取调度 + 各产品 loader + SWEA shape parameter + 数据处理函数（详见 §5） |
| `MAVEN_STATIC` | MAVEN_data/MAVEN_STATIC.jl | module | constants, MarsCommon | （空） | static_c6_mass_mean / static_c6_energy_mean / STA_count2df(_all) / STA_count2eflux(_all) / STA_eflux2df / static_slip / sta_v_4d(_new) / sta_n_4d / static_rotation / static_slip_2_V / STA_count3df / sta_v_1d / get_quality_flag / compare_quality |
| `MAVEN_SWIA` | MAVEN_data/MAVEN_SWIA.jl | module | constants, MarsCommon | （空） | get_3dc! / get_3df!（网格规范化+姿态匹配）/ n_3d / j_3d / v_3d / n_1d |
| `MAVEN_SWEA` | MAVEN_data/MAVEN_SWEA.jl | module | constants | （空） | n1d（电子密度矩）/ load_quat（返回裸矩阵版） |
| `MAVEN_plot` | MAVEN_data/MAVEN_plot.jl | **preloaded** | constants, MarsCommon | （空） | 绘图基元：sta_heatmap、STA_2d_slip、VDF_2d_slip、VDF_2d_mask、SWEA_PAD_heatmap、WaveSpectra_heatmap、Orbit、PAD_slice(_polar/_velocity)、time2x、time_ticks、x_ticks、interpolate_x_ticks、logticks、vector_angle、Vandermonde、polynomial_fit、bowshock、magnetopause、vspan_plot |
| `IGRF_calculate` | Magnetic_Model/IGRF_calculate.jl | module | constants | IGRF_pc、pc2sphere、sphere2pc | 球谐磁场（Fortran ccall 110 阶）+ 磁力线追踪（Euler/RK4/自适应）+ B 场坐标变换 |
| `Cold_Plasma_Dispersion_Relation` | models/Cold_Plasma_Dispersion_Relation.jl | module | constants | （空） | set_particles（全局状态）/ get_Πe / Dispersion_Relation / DR_wave_vector / DR_phase_velocity / carculate_minimum_energy / alfven_weve |
| `Maxwellian_Distribution` | models/Maxwellian_distribution.jl | module | constants | （空） | velocity_distribution / fit_velocity_distribution / velocity_density_distribution / fit_velocity_density_distribution / fit_velocity_distribution_nonlinear（LsqFit） |
| `Single_Particle_Orbit` | models/Single_Particle_Orbit.jl | module | constants | （空） | solve_orbit（定步长 RK4）/ solve_orbit_ode（Tsit5）/ cyclotron_radius / ion_alvfen / dvdt / cross3 / TimeFormat |
| `calculate_models` | calculate/calculate_models.jl | module | constants, MarsCommon | （空） | rotation_matrix / Quaternion_Rot(_reverse) / escape_energy / cyclotron_radius / cyclotron_frequency / Linear_fit |
| `MGS_load` | MGS_data/MGS_load.jl | module | constants, MarsCommon | （空） | load_mag（文本解析+坏行容错）/ caculate_mag（坏）/ read_list |
| `TW_load` | TW_data/TW_load.jl | module | constants, MarsCommon | （空） | load_mag_2c_bydlm / get_spc2mso_rot_matrix_via_2c / calculate_mag（坏）/ read_list |
| `TW_MINPA` | TW_data/TW_MINPA.jl | module | constants | （空） | build_file_list / read_list / load_mod1 / MINPA_sphere2xyz(_xyz2sphere) / MINPA_energy2v / MINPA_get_psd / v3d / v3d_single / slice2d_cal_rot（私有副本） |
| `SP_load` | support_data/support_data_load.jl | module | — | （空） | load_omni2_data / load_drivers_merge_data（太阳风参数） |
| `Call_fortran_dll` | call_fortran_dll.jl（仓库根） | module | — | （空） | cold_plasma_linear_growth（ccall linear_growth_rate.dll）/ Bspline_db1ink / Bspline_db1var（ccall Bspline.dll） |

### 2.2 未注册的脚本型文件（无 `module`，include 进 Main 使用）

| 文件 | 职责 | 被谁使用 |
| --- | --- | --- |
| common/head.jl | 科学辅助函数库（safe_log_mean、color_mapping、bowshock/magnetopause、solve_func、get_bowshock_normal、get_log_ticks 等 ~20 个）+ **顶部 include 6 个重模块**（MAVEN_load/MAVEN_plot/MAVEN_STATIC/SP_load/MAVEN_SWIA/Maxwellian_Distribution） | models/Pickup_ion.jl |
| common/function_coordinate.jl | slice2d_cal_rot、pa_xyz2sphere(_sphere2xyz)、MINPA_sphere2xyz(_xyz2sphere)（SVector 版）、bowshock_zero | models/Pickup_ion.jl |
| models/Pickup_ion.jl | 拾取离子分析全流程脚本（依赖外部预置变量 time_event/instrument_mode/spice_dict/MAVEN_data/TW_minpa_data） | 手动/外部驱动 |
| models/Octree.jl | 八叉树空间剖分 + GLMakie 可视化 | 独立使用 |
| models/Graham.jl | Graham 凸包（Point struct + graham_scan! + graham_scan_for_orbit） | 独立使用 |

### 2.3 关键装载机制（阶段 A 产物，重构红线）

- **载体机制**：`load_module` 在运行时载体模块 `_MarsDataLoader`（无 pkgid）中 `Base.include`，再以 `const` 别名绑定进目标命名空间——这是绕过"包模块 `using` 严格依赖校验"的既定架构（README 明确记载，重构不得破坏）。
- **幂等**：同进程每模块只 include 一次；`:preloaded`（Paths/MAVEN_plot）直接返回包内实例。
- **白名单**：`@load` 用 `using .Mod: a, b` 逐名引入，与模块自身 export 无关。
- 副作用：`parentmodule(MarsData.MAVEN_load) === _carrier()`，模块间相对引用（`using ..constants`）依赖 deps 先装入载体。

---

## 3. 依赖地图

### 3.1 包级依赖（Project.toml [deps]，15 个，轻量）

CairoMakie、ColorTypes、DataFrames、DataInterpolations、Dates、DelaunayTriangulation、IniFile、JSON、LaTeXStrings、LinearAlgebra、Makie、ProgressMeter、StaticArrays、Statistics、TimesDates、TOML。
（Manifest 记录 julia_version=1.10.0；`[compat] julia = "1.10"`。）

### 3.2 模块级外部依赖（不在包 [deps] 中，经载体 LOAD_PATH 回退解析 —— 架构决策，勿并入包）

| 外部包 | 使用处 |
| --- | --- |
| CommonDataFormat | MAVEN_load、MAVEN_STATIC、MAVEN_SWIA、MAVEN_SWEA（CDF 读取核心） |
| FortranFiles | MAVEN_load（vsc/d1 无格式）、IGRF_calculate（gh_gao 系数） |
| JLD2 | MAVEN_load（NGIMS L4、c6_v3d）、Build_data、example |
| Rotations | MAVEN_load/SWIA/SWEA（QuatRotation）、calculate_models、Build_data |
| DifferentialEquations | models/Single_Particle_Orbit（Tsit5） |
| LsqFit | models/Maxwellian_distribution（非线性拟合）、head.jl |
| GLMakie | models/Octree |
| Interpolations / Optim / DSP / CSV / QuadGK / SparseArrays / SpecialFunctions / GeometryBasics | common/head.jl（总头文件，一次性 using） |
| DelimitedFiles | TW_load、TW_MINPA |

### 3.3 本地二进制依赖（ccall）

| DLL / 数据 | 使用处 | 位置 | 风险 |
| --- | --- | --- | --- |
| `IGRF_DLL.dll` | IGRF_calculate（IGRF_FREE_MODEL_mp_IGRF_FREE / IGRF_110_MODEL_mp_IGRF_110 / RK4_STEP / MAIN_mp_ADAPTIVE_STEP_TRACE） | Magnetic_Model/（入仓库） | Windows x64 专用；无 DLL 环境模块加载失败 |
| `gh_gao` | IGRF_calculate 模块加载期 `const GG,HH = read_gh()` | Magnetic_Model/（入仓库） | 文件缺失→模块加载失败 |
| `linear_growth_rate.dll` | call_fortran_dll.cold_plasma_linear_growth | **硬编码 D:/CODE/Package_for_Julia/**（gitignored） | 机器特定路径 |
| `Bspline.dll` | call_fortran_dll.Bspline_db1ink/db1var | 相对路径"Bspline.dll"（gitignored） | CWD 相关 |

### 3.4 数据/配置文件依赖

| 文件 | 读取处 | 生成方 | 状态 |
| --- | --- | --- | --- |
| `MAVEN_data/MAVEN_data_format.json` | MAVEN_load 模块加载期（data_model + kp_dict） | 仓库内维护 | ✅ 存在（55 个产品） |
| `MAVEN_data/filename_lists.json` | MAVEN_load 模块加载期**无条件 open** | Python `martian_pipeline scan` | ❌ **不存在**（gitignored）→ 见调查区 A1 |
| `config/settings.toml` | common/paths.jl（TOML 优先） | Python migrate_config.py | gitignored，本地可选（有默认值兜底） |
| `download_data/MAVEN_download_config.ini` | SP_load（直接 IniFile）、paths.jl（只读兼容） | 本地 | gitignored，可能不存在 |
| `E:/Tianwen-1/List/mag_list.txt`、`MINPA_list.txt` | TW_load/TW_MINPA read_list | TW_MINPA.build_file_list | 外部 |
| `E:/MGS/MAG_SUNSTATE_list` | MGS_load.read_list | 外部 | 外部 |
| 原始 CDF/文本数据 | 各 loader | 外部下载（E:/MAVEN 等） | 外部只读 |

### 3.5 模块间依赖（include/using 关系，含相对父模块引用）

```
MarsData(包) ──include── Paths ── MAVEN_plot(子模块, 内含 constants+MarsCommon) ── plotting ── modules
MarsData.load_module ──→ 载体: constants ← MarsCommon(using ..constants)
                                      ← MAVEN_load(include constants/MarsCommon/Paths)
                                      ← MAVEN_STATIC / MAVEN_SWIA / MAVEN_SWEA (include constants[,MarsCommon])
                                      ← IGRF_calculate / Cold_Plasma_* / Maxwellian_* / Single_Particle_Orbit (include constants)
                                      ← calculate_models(include constants+MarsCommon) / MGS_load / TW_load / TW_MINPA
                                      ← SP_load(无 constants) / Call_fortran_dll
head.jl(脚本) ──include──→ MAVEN_load + MAVEN_plot + MAVEN_STATIC + SP_load + MAVEN_SWIA + Maxwellian_Distribution
Pickup_ion.jl ──include──→ head.jl + function_coordinate.jl(+constants/MarsCommon 防重复)
Build_data/*.jl、example/*.jl ──include──→ MAVEN_load / MAVEN_STATIC / IGRF_calculate（相对路径）
```

---

## 4. 数据流

### 4.1 主读取管线（MAVEN）

```
config/settings.toml (TOML) ──Paths──→ maven_data_root (E:/MAVEN/)
MAVEN_data_format.json ──模块加载期──→ data_model(55 产品: URL/文件名正则/保存路径/load 函数名)
filename_lists.json（scan 生成，缺失则加载失败）──→ filename_list
load_MAVEN_data(date; model_index) ──find_file_of_data(date 子串匹配)──→
  ├─ load_cdf：CDFDataset → epoch→DateTime / RV 重排 / NRV 降维 → Dict(:data_load_flag)
  ├─ load_mag_l2：MAG .sts 固定列宽解析（B/B_total/position）
  ├─ load_kp：KP .tab 按 kp_dict 列区间解析（可选 pc2ss_Matrix 218–226 列）
  ├─ load_NGIMS_* / load_d1_v4d(Fortran 无格式) / load_c6_v3d(JLD2) / load_quat(IDL CSV)
  └─ load_swea_pad：load_cdf + mean_SWEA_pad_pa(360°→180°)
→ 返回 Dict{model => Dict{Symbol}(数据 + :data_load_flag + :filename)}
```

### 4.2 仪器矩计算管线（读取后处理）

```
STATIC: static_c6_mass_mean / static_c6_energy_mean（质量/能量维掩膜求和）→ plot 面板
        STA_count2df(_all) → static_slip → sta_v_4d(_new)/sta_n_4d/sta_v_1d（密度/速度/通量矩）
SWIA:   get_3dc!/get_3df!（网格规范化+quat 最近邻匹配，Δt>4s 标记质量）→ eflux_to_df! → n_3d/j_3d/v_3d
SWEA:   n1d（能谱密度矩，sc_pot 低能截断）；SWEA_calc_shape_arr(_mars_towrads)（shape parameter）
KP:     change_kp_read_data 全局重设 kp_dict → load_kp 按列区间取变量
```

### 4.3 科学计算管线

```
磁场:   IGRF_pc(x,y,z km) → pc2sphere → IGRF_fortran(ccall DLL) → Bsphere2pc → B(nT)
        磁力线: trace_mag_line → mag_trace_Euler_step(默认一阶!)/mag_trace_rk4/ADAPTIVE_STEP → [r,θ,φ,Br,Bθ,Bφ]
色散关系: set_particles → get_Πe → Dispersion_Relation(Stix/Appleton-Hartree 单分支) → DR_wave_vector/DR_phase_velocity → carculate_minimum_energy
拟合:    Maxwellian_Distribution（对数域线性拟合 + LsqFit 非线性拟合）
轨道:    Single_Particle_Orbit.solve_orbit(RK4)/solve_orbit_ode(Tsit5)，E/B 以闭包注入（IGRF_pc 常见）
拾取离子: Pickup_ion.jl 脚本 → head.jl 数据装载 → get_3d_slip_data_from_ins_FOR_PICKUP(swi/sta/minpa) → 拾取环点球坐标 → get_pickup_point 区间命中 → points_data_df
支持数据: SP_load.load_omni2_data / load_drivers_merge_data → DataFrame(time_unix)
```

### 4.4 绘图管线

```
plot_module(fig, x_range, data_dict) —— MarsData 包内
  └─ MAVEN_plot 基元: time2x/time_ticks/sta_heatmap/WaveSpectra_heatmap/Orbit/PAD_slice/SWEA_PAD_heatmap…
  面板: 轨道投影 / B_xyz(MAG+MAG_model_ss) / density(LPW-STATIC-SWIA) / H_vel / scpot /
        LPW_wave(+fce) / STATIC_c6 / STATIC_mass / SWEA_spec / swea_pad_low|high / SWIA_svy_spec
```

---

## 5. 程序入口与核心函数

| 入口 | 位置 | 用途 |
| --- | --- | --- |
| `using MarsData` → `MarsData.project_root/data_model/load_index/…` | src/MarsData.jl | 轻量公共 API（无数据、无 DLL 可加载） |
| `MarsData.plot_module(fig, x_range, data_dict)` | src/plotting.jl | 概览绘图合成 |
| `MarsData.load_module(:X)` / `MarsData.@load X Y` | src/modules.jl | 重模块包化装载（19 个模块） |
| `MAVEN_load.load_MAVEN_data(date; model_index)` | MAVEN_data/MAVEN_load.jl | **MAVEN 数据统一读取入口**（README 主 API） |
| `MAVEN_load.load_cdf(file)` | 同上 | CDF 通用读取 |
| `IGRF_calculate.IGRF_pc(x,y,z)` / `trace_mag_line(...)` | Magnetic_Model/IGRF_calculate.jl | 磁场模型与磁力线 |
| `Cold_Plasma_Dispersion_Relation.Dispersion_Relation(θ,freq,Πe,Ωe)` | models/ | 色散关系 |
| `Single_Particle_Orbit.solve_orbit / solve_orbit_ode` | models/ | 粒子轨道 |
| `calculate_models.*` | calculate/ | 组合物理量（回旋、逃逸能量、旋转） |
| `SP_load.load_omni2_data / load_drivers_merge_data` | support_data/ | 太阳风支持数据 |
| `TW_load.load_mag_2c_bydlm`、`TW_MINPA.load_mod1/v3d` | TW_data/ | 天问数据 |
| `MGS_load.load_mag` | MGS_data/ | MGS 数据 |
| `example/MAVEN_plot_sample/*.jl` | example/ | 官方使用示例（含 KP_l3 旧键兼容别名） |
| `docs/make.jl` | docs/ | Documenter 构建（`julia --project=docs docs/make.jl`） |

核心函数全表见 §2 各模块行 + `docs/src/api.md`（357 行，已是较完整的函数索引，PHASE 8 同步基准）。

---

## 6. 测试现状

| 测试 | 范围 | 状态 |
| --- | --- | --- |
| `test/runtests.jl`（176 行） | 仅 `src/modules.jl` 模块装载管理器：注册表自检、查询 API、幂等、白名单、载体隔离、@load、:all 拓扑序、MAVEN_load 冒烟装载 | 运行方式 `julia --project=. test/runtests.jl`；**依赖 MAVEN_load 冒烟成功** → 受调查区 A1（filename_lists.json 缺失）阻塞 |
| `tests/*.py`（P0–P3 + package） | Python 下载/配置/CLI 管线 | out of scope（不动） |
| 科学计算/读取逻辑 | **零自动化测试**（无数值回归、无 golden 数据） | PHASE 5 重点补强 |
| 历史报告 | `docs/reports/refactoring_*.md`（4 份历史快照） | 只读 |

---

## 7. 文档现状

- 唯一文档根 `docs/`；权威源 `docs/src/*.md` 6 页（index/pipeline/data_reading/data_format/swia_electron/api）。
- `docs/src/api.md`（357 行）为逐目录函数索引，覆盖度较高，与代码注释的 docstring 体系并存。
- `docs/src/data_reading.md` 描述自建数据（KP_l3/MAG_l3/VSC/STATIC_d1_v4d/c6_v3d/SWIA_quat）与读取逻辑；`data_format.md` 描述 STA/MAG/KP 格式。
- 注意：`data_reading.md` 中的 `KP_l3`/`MAG_pc1s_l3` 产品已从注册表移除（README 与示例注释说明），文档可能滞后 → PHASE 8 核对。
- `docs/build/` gitignored；Wiki 由 Python `tools/push_wiki.py`（out of scope）从 docs/src 生成。

---

## 8. 需要进一步调查的区域（后续阶段重点核查清单）

> 按严重度排序；编号供 PHASE 2/3 引用。

### A. 加载与运行健壮性

| # | 问题 | 位置 | 影响 |
| --- | --- | --- | --- |
| A1 | `filename_lists.json` **不存在**（gitignored、由 Python scan 生成），但 MAVEN_load 模块加载期无条件 `open()` | MAVEN_load.jl:1460-1462 | fresh clone 上 `load_module(:MAVEN_load)` / runtests 冒烟直接抛错；应改为缺省空字典 + 懒加载 |
| A2 | `TW_load`/`TW_MINPA`/`MGS_load` 硬编码 `E:/Tianwen-1/`、`E:/MGS/`，绕过 `Paths` 的 TOML 配置 | TW_load.jl:7、TW_MINPA.jl:10、MGS_load.jl:6 | 与 MAVEN_load 的配置解析不一致；换机即失效 |
| A3 | `SP_load` 走旧 INI（`download_data/MAVEN_download_config.ini`，gitignored、可能不存在）且模块加载期 `println` 副作用 | support_data_load.jl:13-14 | 与 paths.jl 的 TOML 优先策略冲突 |
| A4 | `head.jl` include `models/Maxwellian_Distribution.jl`（大写 D）vs 实际文件名 `Maxwellian_distribution.jl`（小写 d）；注册表用小写 d | head.jl:35 | Windows 不敏感、Linux/CI 必失败；大小写统一 |
| A5 | `Pickup_ion.jl` 硬编码 `D:/CODE/Package_for_Julia/` | Pickup_ion.jl:273 | 机器特定路径 |
| A6 | `call_fortran_dll.jl` 硬编码 `D:/CODE/Package_for_Julia/linear_growth_rate.dll` + 相对 `Bspline.dll`（均 gitignored） | call_fortran_dll.jl:42,57,98,132 | 换机不可用 |
| A7 | `export WaveSpactra_heatmap`（拼写）vs 定义 `WaveSpectra_heatmap` | MAVEN_plot.jl:18 vs :958 | export 名为死名；白名单机制下无功能影响但属不一致 |
| A8 | `load_mag_l2` 用 `maximum(findall(...lines[1:300]))`，若前 300 行无 "END" 报错；MGS 版用 `findlast` 更稳 | MAVEN_load.jl:320 | 格式变化时脆弱 |
| A9 | `read_models` 用 `eval(Meta.parse(load 函数名字符串))` 从 JSON 生成函数引用 | MAVEN_load.jl:1455-1459 | JSON 即代码入口；安全/可维护性 |
| A10 | `MarsData` 包加载即 include 编译 MAVEN_plot（1554 行 + CairoMakie/Makie/Delaunay…） | src/MarsData.jl:62 | 包加载时延与依赖重量（属 README 既定设计，仅记录） |

### B. 重复代码与坏函数（重构候选）

| # | 问题 | 位置 |
| --- | --- | --- |
| B1 | `calculate_mag` 三份，且**全部**引用未初始化全局 `data` → 调用必 UndefVarError（docstring 已自曝） | MAVEN_load.jl:923、TW_load.jl:128、MGS_load.jl:112 |
| B2 | `static_c6_mass_mean`/`static_c6_energy_mean` 旧副本（无 :df 分支）与 MAVEN_STATIC 新版并存 | MAVEN_load.jl:989/1057 vs MAVEN_STATIC.jl:69/142 |
| B3 | `Bpc2sphere` 双份（MAVEN_load 无类型标注 vs IGRF_calculate 带 ::Real） | MAVEN_load.jl:889、IGRF_calculate.jl:121 |
| B4 | `bowshock`/`magnetopause` 三份（head.jl、function_coordinate.jl 的 bowshock_zero、MAVEN_plot.jl 的 bowshock/magnetopause），同一 Edberg 2008 公式 | head.jl:358/397、function_coordinate.jl:249、MAVEN_plot.jl:1514/1541 |
| B5 | `slice2d_cal_rot` 双份（common 版防共线+零分配 SMatrix vs TW_MINPA 私有副本） | function_coordinate.jl:28、TW_MINPA.jl:558 |
| B6 | `load_quat` 双份同名不同义（MAVEN_load 返回 Dict{QuatRotation 数组}；MAVEN_SWEA 返回裸 Matrix） | MAVEN_load.jl:794、MAVEN_SWEA.jl:106 |
| B7 | `TimeFormat` 双份不同格式（HH:MM:SS.mmm vs MM:SS.mmm） | src/plotting.jl:26、Single_Particle_Orbit.jl:30 |
| B8 | `cyclotron_radius`/`cyclotron_frequency` 多份近似实现（calculate_models、Single_Particle_Orbit、MAVEN_load.cyclone_* 单位/命名不一致） | calculate_models.jl:116/149、Single_Particle_Orbit.jl:355、MAVEN_load.jl:1229/1250 |
| B9 | `Vandermonde`/`polynomial_fit`/`vector_angle`/`logticks` 等通用数学工具放在绘图模块 | MAVEN_plot.jl:1442-1541 |

### C. 科学计算疑点（改动前必须做科学结果验证，见 00 文件 R4/R5）

| # | 问题 | 位置 |
| --- | --- | --- |
| C1 | `trace_mag_line` 默认 `mag_trace_Euler_step`（**一阶**欧拉）做磁力线追踪；RK4/自适应版本存在但未默认 | IGRF_calculate.jl:761 |
| C2 | `combina_two_dir_trace` 模块内自引用 `IGRF_calculate.sphere2pc`（模块内无此名，直接 include 到 Main 时调用会 UndefVarError；经载体装载后可用） | IGRF_calculate.jl:677-678 |
| C3 | `get_mag_line_s` 读字符串键 `"B"` 而 `trace_mag_line` 产出 Symbol 键 `:B` → KeyError | IGRF_calculate.jl:717 |
| C4 | `MAVEN_SWEA.n1d`：`tiny = 1.0-31` 笔误（疑为 1e-31），当前被 `ff` 截断掩盖；`energy_range` 参数未生效 | MAVEN_SWEA.jl:54,48 |
| C5 | `MAVEN_SWIA.v_3d` 用 4D 索引取 3D `dat[:theta]`（`[time_ind,:,:,:]`），与 get_3dc! 写入的 3D 形状不符 → 疑 BoundsError（n_3d/j_3d 用 3D 索引正常） | MAVEN_SWIA.jl:369 |
| C6 | `TW_MINPA.load_mod1` 的 `denergy` 定义"可能不对"（源码注释）；`v3d`/`v3d_single` 积分弃用 denergy、改用经验常数 `0.2/2` | TW_MINPA.jl:111-114,445 |
| C7 | `TW_MINPA.v3d` 中 nvy 加负号而 nvx/nvz 为正（与 MINPA_sphere2xyz 的 -y/-z 约定不一致），最终统一反号 `vel=-vel` —— 符号约定需与参考数据核对 | TW_MINPA.jl:441-450 |
| C8 | `Cold_Plasma_Dispersion_Relation` 全局可变状态（Nparticles/Ω_n/Π_2）非线程安全；只取单分支较大根；`carculate_minimum_energy` θ→0 发散 | models/Cold_Plasma_Dispersion_Relation.jl |
| C9 | `Dispersion_Relation` 顶部注释称"分度制"、实现按弧度（docstring 已注明） | 同上:92 |
| C10 | `carclu_SWEA_pad` 硬编码 64 能道（`zeros(1,1,64)`）；`SWEA_calc_shape_arr` 硬编码 `indx=13:64`、`n_e=52`、df_iono 模板数组 | MAVEN_load.jl:1156,1356-1350 |
| C11 | `SWIA.n_3d/j_3d/v_3d` 质子假设 + 硬编码系数 7.224566339926571e-7；`n_1d` 系数 `sqrt(mp_g/(2*erg_per_eV))*8.8` 待核对 | MAVEN_SWIA.jl |
| C12 | `mean_SWEA_pad_pa` 360°→180° 平均的 NaN 互填逻辑（先填后均）需与 SPEDAS 行为核对 | MAVEN_load.jl:948-969 |
| C13 | `load_cdf` 的 RV 判定 `v.vdr.flags & 1 == 1` 与注释的 `flags==3||7` 不一致；epoch 用 `convert(Vector{DateTime},v)` 依赖 CommonDataFormat 闰秒处理 | MAVEN_load.jl:254,260 |
| C14 | `position_local_time`/`position_latitude` 忽略自转轴倾角（docstring 已注明近似） | MarsCommon.jl:181/202 |
| C15 | `kp_dict` 全局可变 + `change_kp_read_data` 全局重设；示例/绘图共享全局状态，多脚本同进程复用有状态污染风险 | MAVEN_load.jl:188,1454 |
| C16 | `MAVEN_data_format.json` 的 kp_dict 键名拼写 "electorn density"（与代码中 `:electorn_density` 一致）——历史拼写，重命名需全链路同步 | MAVEN_data_format.json |
| C17 | `plot_module` 同时读 `data_dict["KP_l3"]` 与 `data_dict["KP"]`（旧键兼容），示例靠双写别名兜底 | src/plotting.jl:99,104 vs example:95-96 |
| C18 | `MAVEN_STATIC.sta_v_4d(_new)`/`STA_count*` 等 STATIC 矩计算为科学核心，本阶段仅登记函数签名，PHASE 2 需逐行复核（含单位与掩膜约定） | MAVEN_STATIC.jl |
| C19 | `Graham.jl`/`Octree.jl`/`function_coordinate.jl`/`head.jl`/`Pickup_ion.jl` 为脚本型（无模块），与模块化体系并存；`Graham.graham_scan!` 原地改入参 | models/ |
| C20 | `requirement.jl` 与 `Project.toml [deps]` 不同步（重依赖清单 vs 轻量包依赖）——已属既定架构，记录 | 根目录 |

### D. 测试与文档缺口

| # | 问题 | 位置 |
| --- | --- | --- |
| D1 | Julia 测试仅覆盖模块管理器；数据读取、坐标变换、矩计算、磁场模型、色散关系、轨道积分 **零自动化测试** | test/runtests.jl |
| D2 | 无 benchmark 基线（性能优化前必须先建基线，00 文件 R2） | — |
| D3 | `docs/src/data_reading.md` 中 `KP_l3`/`MAG_pc1s_l3` 等产品名与当前注册表不符，PHASE 8 核对同步 | docs/src/data_reading.md |
| D4 | `MAVEN_data/Build_data/` 含 `.py`/`.pro` 混合构建脚本（部分 out of scope），其 `.jl` 脚本与主读取器耦合（include ../MAVEN_load.jl） | MAVEN_data/Build_data/ |

---

## 9. 扫描方法记录（供审计）

- 通读全部 37 个 `.jl` 文件（共 12,944 行）：src(3)、common(5)、MAVEN_data(5+Build_data 4)、MGS_data(1)、TW_data(2)、models(6)、Magnetic_Model(1)、calculate(1)、support_data(1)、test(1)、example(2)、根目录 call_fortran_dll.jl、download_data/get_all_orbit.jl。
- 结构提取：MAVEN_data_format.json（data_model 55 产品 + kp_dict）、KP_vars.json（仅登记）。
- 目录登记：docs/（src 6 页 + wiki + references 13 件 + reports 4 份 + make.jl）、tests/（Python P0–P3，out of scope）、.gitignore 中与 Julia 相关条目（filename_lists.json、*.jld2、Bspline.dll、linear_growth_rate.dll 等）。
- 未读取（超出本阶段范围）：Python 文件全文、二进制（DLL/PDF/PNG）、`Manifest.toml` 全文（仅头部确认 julia_version）、外部数据目录。
- 只读确认：`git status --porcelain` 仅 `.agent/`、`.agent-teams/` 未跟踪，无任何源码改动。
