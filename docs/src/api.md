# 程序与函数 Wiki

本页按仓库目录介绍程序职责，并索引源码中的函数。源码文件顶部提供文件级说明；函数的参数细节、单位约定和数据结构以对应实现及其已有函数注释为准。本页只记录用途，不改变程序逻辑。

## 专题文档

- [MAVEN 数据读取指南](data_reading.md)：统一读取入口、返回结构与数据流程。
- [MAVEN 数据格式参考](data_format.md)：数据产品清单、命名格式及仪器数据要点。
- [SWIA 电子修正专题](swia_electron.md)：电子二次发射背景的相关假设与修正算法记录。

## 目录导航

| 路径 | 内容 |
| --- | --- |
| [`MAVEN_data/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/MAVEN_load.jl) | MAVEN 数据统一读取、仪器数据处理、绘图及本地数据构建脚本 |
| [`MGS_data/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MGS_data/MGS_load.jl)、[`TW_data/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/TW_data/TW_load.jl) | MGS 磁场与天问一号数据、MINPA 仪器处理 |
| [`download_data/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/download_data/MAVEN_download.py) | 数据下载、文件清单检查、压缩、清理和版本整理 |
| [`models/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/models/Cold_Plasma_Dispersion_Relation.jl)、[`Magnetic_Model/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/Magnetic_Model/IGRF_calculate.jl) | 等离子体、粒子轨道、分布拟合、磁场及几何模型 |
| [`common/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/common/head.jl)、[`support_data/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/support_data/support_data_load.jl) | 坐标/科学计算通用函数和外部太阳风支持数据读取 |
| [`calculate/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/calculate/calculate_models.jl)、[`call_fortran_dll.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/call_fortran_dll.jl) | 组合物理计算和 Fortran 动态库接口 |
| [`example/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/example/MAVEN_plot_sample/MAVEN_overview_cases.jl) | MAVEN 事件概览图示例 |
| [`MAVEN_data/Build_data/`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/build_vsc.jl) | STATIC、NGIMS、KP 等数据预处理与重建脚本 |
| [`tools/robocopy.ps1`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/tools/robocopy.ps1)、[`requirement.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/requirement.jl) | 数据复制工具与 Julia 依赖名称清单 |

## MAVEN 数据读取与处理

### `MAVEN_data/MAVEN_load.jl`

- `show_load_models`：列出当前注册的数据产品读取器。
- `file_list`：返回指定数据产品的本地文件路径列表。
- `find_file_of_data`：按日期查找指定数据产品文件。
- `data_get_from_date`：按日期和产品列表统一调度读取，并记录各产品加载状态。
- `get_orbits`：读取轨道号对应的时间范围。
- `change_kp_read_data`：修改 KP 文件中要读取的变量编号映射。
- `load_cdf`：把 CDF 变量读入 Julia 字典并整理数据维度；内部 `clean_dimensions` 统一清理维度。
- `load_mag_l2`：读取 MAVEN MAG L2 文本磁场数据；内部 `get_data_from_line_for_mag_read` 解析单行记录。
- `load_mag_vsc`：读取航天器速度数据。
- `load_kp`：读取 KP 数据并按设置提取变量；内部 `kp_indicate` 解析 KP 变量索引。
- `load_swea_pad`：读取 SWEA 俯仰角分布数据。
- `load_NGIMS_den_l3`、`load_NGIMS_den_l4`：读取 NGIMS L3、L4 密度产品。
- `load_NGIMS_sht_l3`：读取 NGIMS L3 标度高度表。
- `load_d1_v4d`、`load_c6_v3d`：读取项目构建的 STATIC d1/c6 四维派生数据。
- `load_quat`：读取从 IDL 导出的姿态四元数数据。
- `convert_kp_l3`：把 KP L3 原始变量映射转换为便于使用的数据字典。
- `Bpc2sphere`：将笛卡尔坐标磁场分量转换为球坐标分量。
- `calculate_mag`：计算指定位置的模型磁场及位置辅助量；内部 `c_alt`、`c_local_time`、`c_latitude` 分别计算高度、地方时和纬度。
- `mean_SWEA_pad_pa`：对 SWEA PAD 俯仰角维度求平均。
- `static_c6_mass_mean`、`static_c6_energy_mean`：分别按质量范围、能量范围汇总 STATIC c6 数据。
- `carclu_SWEA_pad`：处理 SWEA PAD 数据并计算选定能量范围的分布量。
- `rotate_vector_with_Martrix`：用旋转矩阵变换向量。
- `eflux2F`、`ion_eflux2F`：将电子或离子能量通量转换为相空间分布函数。
- `Doppler_Shift`：计算航天器运动引起的波频多普勒变换。
- `sphere2xyz`：将球坐标转换为笛卡尔坐标。
- `energy2v`、`ion_energy2v`：将电子或离子能量换算为速度。
- `find_segments`：根据布尔掩码划分连续区段。
- `cyclone_frequency`、`cyclone_R`：计算带电粒子的回旋频率和回旋半径。
- `SWEA_calc_shape_arr`：计算 SWEA 指定俯仰角/能量范围内的形状参数；内部 `mvn_swe_calc_shape_arr` 完成单组数据计算，`deriv` 计算拟合所需导数。
- `SWEA_calc_shape_arr_mars_towrads`：结合 SWEA 分布和磁场方向，分别统计朝向/背离火星的形状参数。

### `MAVEN_data/MAVEN_STATIC.jl`

- `static_c6_mass_mean`、`static_c6_energy_mean`：对 STATIC c6 数据按质量或能量区间求平均。
- `STA_count2df`、`STA_count2df_all`：将 STATIC 计数转换为相空间密度，分别用于单个切片和整段数据。
- `STA_count2eflux`、`STA_count2eflux_all`：将 STATIC 计数转换为能量通量，支持切片和整段数据。
- `STA_eflux2df`：将 STATIC 能量通量转换为相空间密度。
- `static_slip`：提取指定时刻的 STATIC 数据切片。
- `sta_v_4d`、`sta_v_4d_new`：由 STATIC 四维分布计算速度、流速和密度。
- `sta_n_4d`：由 STATIC 四维分布计算数密度。
- `static_rotation`：将 STATIC 三维切片旋转到指定坐标系；内部 `sphere2xyz_for_static_rotation`、`xyz2sphere_for_static_rotation` 处理球坐标与笛卡尔坐标互转。
- `static_slip_2_V`：结合切片、质量范围和航天器速度求离子速度量。
- `STA_count3df`：将带时间轴的 STATIC c6 计数转换为相空间密度；内部 `expand_3d` 扩展并对齐输入数据维度。
- `sta_v_1d`：从一维 STATIC 相空间密度计算离子速度、流速和密度。
- `get_quality_flag`、`compare_quality`：提取并判定质量标志。
- `rotate_vector_with_Matrix`：使用矩阵旋转向量。
- `ion_eflux2F`：把离子能量通量转换为相空间密度。
- `sphere2xyz_for_STATIC`、`xyz2sphere_for_STATIC`、`sphere2xyz`：STATIC 相关球坐标与笛卡尔坐标转换。
- `ion_energy2v`、`ion_v2energy`：离子能量与速度互相换算。

### `MAVEN_data/MAVEN_SWIA.jl`

- `get_3dc!`、`get_3df!`：分别整理 SWIA coarse/fine 三维分布及其坐标信息。
- `n_3d`、`j_3d`、`v_3d`：由 SWIA 三维分布计算数密度、通量和速度。
- `n_1d`：从 SWIA 一维扫描谱计算数密度。
- `rotate_vector_with_Martrix`：用旋转矩阵变换向量。
- `sphere2xyz_for_SWIA`、`xyz2sphere_for_SWIA`：SWIA 球坐标和笛卡尔坐标转换。
- `eflux2df!`、`ion_eflux2F`：能量通量到相空间密度的转换。
- `ion_energy2v`、`ion_v2energy`：离子能量和速度换算。

### `MAVEN_data/MAVEN_SWEA.jl`

- `n1d`：从 SWEA 一维能谱计算电子数密度。
- `load_quat`：读取 IDL 导出的姿态四元数。
- `rotate_vector_with_Martrix`：通过旋转矩阵变换向量。
- `eflux2df!`、`ion_eflux2F`：能量通量到相空间密度的转换。
- `sphere2xyz_for_SWIA`、`xyz2sphere_for_SWIA`：球坐标和笛卡尔坐标转换辅助函数（保留源码中的函数名）。
- `ion_energy2v`、`ion_v2energy`：离子能量和速度换算。

### `MAVEN_data/MAVEN_plot.jl`（已包化为子模块 `MarsData.MAVEN_plot`）

> 该文件作为子模块被 `src/MarsData.jl` 载入，`using MarsData` 后其导出基元直接可用。

- `vspan_plot`：在时间序列坐标轴上绘制布尔区间。
- `sta_heatmap_test`、`sta_heatmap`：绘制 STATIC 能量/角度分布热图。
- `STA_2d_slip`：生成 STATIC 二维切片图；内部 `remove_repeat_points` 去重、`filter_points_optimized` 筛选有效点、`color_mapping` 映射色标、`slice2d_cal_rot` 计算切片旋转。
- `VDF_2d_slip`：绘制速度分布函数二维切片及辅助边界；内部 `remove_repeat_points`、`filter_points_optimized`、`color_mapping` 和 `slice2d_cal_rot` 分别负责点去重、筛选、着色和旋转。
- `VDF_2d_mask`：绘制带速度空间遮罩的分布图；内部 `get_triangle_mesh` 构建网格，`rotate_func` 转换坐标，`graham_scan`（含方向判定 `ccw`）求投影点凸包，`get_shadow_boundary_polar` 生成遮挡边界，`cartesian_to_polar` 转换极坐标。
- `SWEA_PAD_heatmap`：绘制 SWEA 俯仰角分布热图。
- `WaveSpectra_heatmap`：绘制波动频谱热图。
- `Orbit`：绘制航天器轨道及相关边界/磁场线。
- `PAD_slice`、`PAD_slice_polar`、`PAD_slice_velocity`：分别在能量-俯仰角、极坐标能量和速度坐标中绘制 PAD 切片。
- `time2x`：将时间转换为绘图用 Unix 时间并裁剪到给定范围。
- `time_ticks`：按指定间隔生成时间轴刻度。
- `interpolate_x_ticks`：根据不等距数据位置插值生成横轴刻度；内部 `find_monotonic_intervals` 查找单调区间。
- `logticks`：根据输入数值生成对数坐标刻度标签。
- `vector_angle`：计算二维向量夹角。
- `Vandermonde`、`polynomial_fit`：构造 Vandermonde 矩阵并进行多项式拟合。
- `eflux2F`：将电子能量通量转换为相空间密度。
- `bowshock`、`magnetopause`：计算绘图用火星弓形激波和磁层顶模型边界。

### MAVEN 数据构建脚本

- [`Build_data/KP重构为cdf.py`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/KP重构为cdf.py)：`get_list_from_ini` 解析配置列表；`download_model` 获取产品文件；`parse_kp_version`、`parse_kp_date` 解析版本和日期；`pick_and_clean_kp_files` 选择并清理重复产品；`build_kp_colspecs` 建立 KP 列定义；`convert_kp_to_cdf` 转换 KP 数据为 CDF。
- [`Build_data/磁场重构为CDF文件.py`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/磁场重构为CDF文件.py)：`get_list_from_ini` 解析配置；`download_model` 获取文件；`parse_pds_header_and_data` 解析 PDS 文本头和数据；`convert_pds_to_cdf` 转换为 CDF，内部 `row_to_datetime` 解析逐行时间。
- [`Build_data/build_vsc.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/build_vsc.jl)：`get_vsc` 使用 MAG 位置数据构造航天器速度；内部 `quadratic_fitted_derivative` 计算二次拟合曲线导数，`data2bi` 保存结果。
- [`Build_data/STATIC_VD.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/STATIC_VD.jl)：`get_ion_vel` 结合航天器速度和离子数据计算速度、通量、密度；`data2bi` 写出二进制产品；顶层流程批量生成 STATIC 派生产品。
- [`Build_data/STATIC_vfd_3d.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/STATIC_vfd_3d.jl)：`get_ion_vel` 由 c6 数据计算一维速度、通量和密度；`data2bi` 写出二进制产品。
- [`Build_data/ngi整合.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/ngi整合.jl)：合并同一天的多份 NGIMS L3 文件。
- [`Build_data/get_quats.pro`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/get_quats.pro)：通过 SPEDAS 获取 MAVEN 仪器姿态四元数。
- [`Build_data/sc_pot.pro`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/sc_pot.pro)：配置 SPEDAS/CDF 数据环境并演示航天器电势数据读取。
- [`build_read_me.py`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/build_read_me.py)：从数据格式 JSON 生成产品列表说明。

## MGS 与天问数据

### `MGS_data/MGS_load.jl`

- `get_data_from_line_for_mag_read`：解析 MGS 磁场文本记录。
- `load_mag`：读取 MGS 磁场文件。
- `caculate_mag`：计算指定位置的 MGS 磁场及位置辅助量；内部 `c_alt`、`c_local_time`、`c_latitude` 分别计算高度、地方时和纬度。
- `read_list`：读取 MGS 数据文件清单。

### `TW_data/TW_load.jl`

- `load_mag_2c_bydlm`：读取天问磁场数据文件。
- `calculate_mag`：计算指定位置的磁场及位置辅助量；内部 `c_alt`、`c_local_time`、`c_latitude` 分别计算高度、地方时和纬度。
- `get_spc2mso_rot_matrix_via_2c`：依据读取的磁场/姿态数据取得坐标旋转矩阵。
- `read_list`：读取天问数据文件清单。

### `TW_data/TW_MINPA.jl`

- `build_file_list`、`read_list`：构建并读取 MINPA 文件清单。
- `load_mod1`：读取 MINPA mod1 数据文件。
- `ion_energy2v`、`ion_v2energy`：离子能量与速度换算。
- `MINPA_sphere2xyz`、`MINPA_xyz2sphere`：MINPA 仪器坐标的球坐标与笛卡尔坐标转换。
- `MINPA_energy2v`：提取指定质量数对应的速度分布。
- `MINPA_get_psd`：由角度、能量和质量数据计算相空间密度。
- `v3d`、`v3d_single`：计算完整数据或指定时刻的三维速度分布。
- `slice2d_cal_rot`：根据两个方向向量计算二维切片旋转关系。

## 磁场与公共计算

### `Magnetic_Model/IGRF_calculate.jl`

- `pc2sphere`、`sphere2pc`：行星笛卡尔坐标与球坐标互转。
- `Bsphere2pc`、`Bpc2sphere`：磁场矢量在球坐标与笛卡尔坐标间转换。
- `CALCULATE_SCHMIDT_COEFFICIENTS`：生成球谐展开所需 Schmidt 系数。
- `read_gh`：读取磁场球谐系数。
- `IGRF_fortran_free`、`IGRF_fortran`：调用 Fortran 磁场计算核心。
- `RK4_Trace_fortran`：调用 Fortran RK4 磁力线追踪步进。
- `IGRF_pc`、`IGRF`：计算指定笛卡尔或球坐标位置的磁场。
- `mag_trace_rk4_fortran_ADAPTIVE_STEP`：以可变步长 RK4 追踪磁力线。
- `mag_trace_rk4`、`mag_trace_Euler_step`：以固定步长 RK4 或 Euler 方法追踪磁力线。
- `combina_two_dir_trace`：合并两个反向追踪结果为一条定向磁力线。
- `get_mag_line_s`：计算标准磁力线数据中的沿线距离。
- `trace_mag_line`：按输入/输出坐标系设置追踪磁力线。
- `set_B_compress`：更新压缩磁场数据的系数。

### `common/function_coordinate.jl`

- `slice2d_cal_rot`：由两个方向向量计算二维切片旋转。
- `rotate_vector_with_Matrix`：用矩阵旋转向量。
- `pa_xyz2sphere`、`pa_sphere2xyz`：俯仰角坐标和笛卡尔坐标互转。
- `STATIC_xyz2sphere`、`STATIC_sphere2xyz`：STATIC 仪器坐标转换。
- `MINPA_sphere2xyz`、`MINPA_xyz2sphere`：MINPA 仪器坐标转换。
- `bowshock_zero`：求弓形激波模型在指定位置的零值/边界交点。

### `common/head.jl`

- `find_time`：查找最接近目标时刻的索引。
- `safe_log_mean`：计算适用于对数数据的安全均值。
- `mars_sun_dist_phys`：根据太阳经度估算火星日心距离。
- `ion_v2energy`、`ion_energy2v`：离子速度与能量互换。
- `color_mapping`：把数值映射到绘图颜色范围。
- `skipnan`、`nozeros`：过滤 NaN 或替换零值。
- `geomean`：计算几何平均。
- `find_range`、`find_time_range`：查找数值区间或时间区间对应的数据范围。
- `get_normal_plane`：由法向量构造平面表示。
- `get_angle`：计算两个向量的夹角。
- `bowshock`、`magnetopause`：计算火星弓形激波和磁层顶模型位置。
- `get_log_ticks`：生成对数坐标刻度。
- `solve_func`：用二分法求解一元函数零点。
- `get_bowshock_normal`：计算弓形激波表面法向量。

### `calculate/calculate_models.jl` 与 `call_fortran_dll.jl`

- `Matrix_Rot`、`rotation_matrix`：通过矩阵或角度构造坐标旋转。
- `Quaternion_Rot`、`Quaternion_Rot_reverse`：使用四元数执行正向或逆向向量旋转。
- `eflux2F`：将能量通量转换为相空间密度。
- `Doppler_Shift`：计算运动参考系中的波频率偏移。
- `energy2v`：按粒子类型和质量数将能量换算为速度。
- `escape_energy`：计算指定行星和粒子质量对应的逃逸能量。
- `cyclotron_radius`、`cyclotron_frequency`：计算回旋半径和回旋频率。
- `Linear_fit`：执行线性拟合。
- `cold_plasma_linear_growth`：调用 Fortran 例程计算冷等离子体线性增长率。
- `Bspline_db1ink`、`Bspline_db1var`：准备 B 样条插值数据并执行单点插值。

## 物理与几何模型

### `models/Cold_Plasma_Dispersion_Relation.jl`

- `set_particles`：设置电子/离子组分及归一化参数。
- `get_Πe`：由电子密度计算电子等离子体频率。
- `Dispersion_Relation`：按冷等离子体色散关系计算折射率。
- `DR_wave_vector`、`DR_phase_velocity`：由折射率和频率计算波矢、相速度。
- `carculate_minimum_energy`：计算给定波模条件下的共振粒子最小能量。
- `alfven_weve`：计算 Alfvén 速度。

### `models/Maxwellian_distribution.jl`

- `velocity_distribution`、`velocity_density_distribution`：计算归一化或含密度的 Maxwell 分布。
- `fit_velocity_distribution`、`fit_velocity_density_distribution`：对速度分布数据执行拟合。
- `fit_velocity_distribution_nonlinear`：使用非线性方法拟合分布；内部 `log_maxwellian_model` 提供对数空间模型。

### `models/Single_Particle_Orbit.jl`

- `TimeFormat`：构造轨道求解所需的时间采样序列。
- `dvdt`：计算带电粒子的速度变化率。
- `cross3`：计算三维向量叉积。
- `solve_orbit`、`solve_orbit_ode`：分别通过迭代或 DifferentialEquations 求解粒子轨道；ODE 内部函数 `ODE!` 描述微分方程。
- `cyclotron_radius`：计算粒子回旋半径。
- `ion_energy2v`、`ion_v2energy`、`energy2v`：离子或电子能量/速度换算。
- `ion_alvfen`：计算离子 Alfvén 速度。

### `models/Pickup_ion.jl`

- `func_E_range`：按对数间隔生成能量分箱。
- `get_3d_slip_data_from_ins_FOR_PICKUP`：从选定仪器读取拾取离子分析所需三维切片。
- `get_pickup_point`：从角度和能量网格中高效提取指定拾取分布点。

### `models/Graham.jl`、`models/Octree.jl`

- `graham_scan!`：原地执行 Graham 凸包扫描；内部 `ccw` 判断三点转向。
- `graham_scan_for_orbit`：从轨道点构造凸包。
- `OctreeNode`：构造八叉树节点。
- `build_octree!`：按空间判定函数递归细分八叉树。
- `get_min_bounding_box`：依据空间判定函数计算最小包围盒；内部 `find_boundaries` 搜索边界。
- `is_sphere`：判定点是否位于球形区域。

### `support_data/support_data_load.jl`

- `load_omni2_data`：读取 OMNI2 太阳风数据。
- `load_drivers_merge_data`：读取并合并已有的太阳风驱动参数；内部 `row_to_datetime` 将年积日和时分转换为时间。

## 下载和文件维护

### `download_data/MAVEN_download.py`

- `get_list_from_ini`：解析 INI 中的逗号分隔配置项。
- `sleep_local`：显示等待进度并暂停。
- `test_proxies`：测试数据服务器或代理连通性。
- `search_url`：在服务器目录中查找匹配文件。
- `download_unit_convert`：格式化下载字节数。
- `requests_download`：使用 HTTP 请求下载单个文件。
- `idm_add_download_links`、`aria2_download`：将下载任务提交给外部下载器。
- `download_model`：按产品配置执行下载流程。
- `find_downloaded_file`：在文件清单中定位已下载项目。
- `read_last_line_large_file`：从大文件尾部读取最后一行。
- `file_check`：检查下载文件存在性和有效性。
- `get_element_from_filename`：解析文件名中的版本等字段。
- `search_downloaded_files`：搜索匹配数据产品的本地文件。
- `month_delta`：推进到下一个月的起始日期。
- `download_from_head`：根据目录索引继续发现并加入下载链接。

### 其他 `download_data` 脚本

- [`download_files.py`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/download_data/download_files.py)：`get_list_from_ini` 解析配置；`sleep_local` 显示等待；`test_proxies` 测试代理；`search_url` 检索服务器文件；`requests_download` 下载文件；`find_downloaded_file` 匹配本地文件；`print_download_statue` 输出状态统计；`add_urls` 写入待下载链接。
- [`check_exist_files.py`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/download_data/check_exist_files.py)：`get_list_from_ini` 解析配置；`download_model` 读取产品配置；`search_downloaded_files` 检查指定目录中的文件。
- [`clean_files.py`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/download_data/clean_files.py)：`get_list_from_ini` 解析配置；`clean_pydownload_files` 清理未完成下载文件。
- [`compress_cdf.py`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/download_data/compress_cdf.py)：`check_if_compressed` 判断压缩状态；`compress_single_cdf` 压缩单个 CDF；`batch_compress_cdf_files` 批量处理目标目录。
- [`移除重复文件中的低版本文件.py`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/download_data/移除重复文件中的低版本文件.py)：`get_list_from_ini` 解析配置；`download_model` 获取文件列表；`parse_file_info` 解析文件名产品/版本信息；`remove_low_version_files` 按版本识别重复项并支持 dry-run。
- [`get_all_orbit.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/download_data/get_all_orbit.jl)：`get_data` 读取轨道数据；`time_by_orbits` 按轨道号筛选时间范围；`val_combine` 合并多组轨道数据。
- [`get_download_files.py`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/download_data/get_download_files.py)：扫描数据目录并生成下载文件清单。
- [`initialize_download_parameters.py`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/download_data/initialize_download_parameters.py)：首次生成 MAVEN 下载配置文件。

## 示例程序

概览绘图流程已**包化进 `MarsData`**：`TimeFormat`（时长字符串）、`remove_0_point!`（非正绘图值置 NaN）、`plot_module`（多仪器时间序列面板）定义于 [`src/plotting.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/src/plotting.jl)，随 `using MarsData` 可用；绘图基元来自子模块 `MarsData.MAVEN_plot`。

[`MAVEN_overview_cases.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/example/MAVEN_plot_sample/MAVEN_overview_cases.jl) 与 [`MAVEN_overview_plot_sample.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl) 只保留数据准备部分：`mag2sphere` 转换磁场分量；`get_data` 读取所需产品（KP 用 `load_kp` + 坐标变换矩阵）；`get_B_model_ss` 计算模型磁场；随后调用 `MarsData.plot_module` 绘图。

## 其他无函数入口文件

- [`models/constants.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/models/constants.jl)：模型共享的基本物理常量。
- [`requirement.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/requirement.jl)：Julia 依赖包名称列表。
- [`tools/robocopy.ps1`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/tools/robocopy.ps1)：按规则在数据盘之间复制文件。
- [`MAVEN_data/Build_data/STATIC_VD.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/STATIC_VD.jl)、[`STATIC_vfd_3d.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/STATIC_vfd_3d.jl)、[`ngi整合.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/ngi整合.jl)、[`get_quats.pro`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/get_quats.pro)、[`sc_pot.pro`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/blob/main/MAVEN_data/Build_data/sc_pot.pro)：由顶层流程完成 STATIC 产品构建、NGIMS 合并、姿态数据提取和电势数据读取，没有单独导出的 Julia/Python 函数 API。
