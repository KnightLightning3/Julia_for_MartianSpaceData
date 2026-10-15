# 程序与 Julia 函数索引

本页由 `tools/generate_api.jl` 使用 Julia 标准库 `Meta.parseall` 从生产源码静态生成；不加载项目环境、科学依赖、数据或 DLL。

## 当前架构

`using MarsData` 的包初始化会加载绘图栈和 `MAVEN_plot`，提供路径/注册表/索引接口并装配绘图；它不加载科学数据 loader。`src/modules.jl` 管理按需装载的科学模块。`common/` 放共享常量、路径、数据键与计算能力；`MAVEN_data/`、`MGS_data/`、`TW_data/` 和 `support_data/` 放各数据源读取与处理；`models/` 放物理模型；`analysis/` 是依赖预设变量的分析脚本。Python 负责配置、下载和本地文件流水线。

本索引反映当前源码形状，不构成稳定公开 API 承诺。调用时优先使用限定名（如 `MAVEN_load.load_MAVEN_data`）。模块内 `export` 表示 Julia 模块导出；`MarsData.@load` 的裸名则由 `src/modules.jl` 的 `ModuleSpec.allow` 白名单逐名控制，两者相互独立。

当前注册表的裸名白名单（从 `src/modules.jl` 静态读取）：

| 模块 | `@load` 可裸名调用 |
| --- | --- |
| `IGRF_calculate` | `IGRF_pc` |
| `MAVEN_load` | `load_MAVEN_data`、`load_cdf` |
| `MarsCommon` | `e_energy2v`、`ion_energy2v`、`searchsortednearest` |

- 架构说明：[architecture.md](architecture.md)
- 迁移说明：[migration.md](migration.md)
- 配置、下载、扫描到读取流程：[pipeline.md](pipeline.md)

## Python 程序职责

| 路径 | 职责 |
| --- | --- |
| `martian_pipeline/`、`python -m martian_pipeline` | 统一 CLI 入口（扫描、检查与维护） |
| `download_data/MAVEN_download.py` | MAVEN 数据下载，并在完成后触发扫描刷新 |
| `config/`、`download_data/initialize_download_parameters.py` | Julia/Python 共用 TOML 配置与模板初始化 |
| `martian_pipeline/inventory.py`、`tools/scan_and_index.py` | 本地文件扫描、产品清单和索引生成 |
| `tools/push_wiki.py`、`MAVEN_data/build_read_me.py` | Wiki 页面发布与数据产品说明生成 |

## Julia 源码索引

仅索引模块定义与顶层函数定义（包括短定义）；函数体内的局部函数和 lambda 不列入。用途摘录限于已有 docstring 首句，没有 docstring 的条目不推断语义。`export` 标记按扫描文件中的静态声明和完整模块作用域聚合（包括跨文件 include 关系）；不推断运行期生成的导出。源码链接使用 GitLab 仓库绝对 URL，只指向文件，不依赖行号。

### [`MAVEN_data/MAVEN_STATIC.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/MAVEN_data/MAVEN_STATIC.jl)

模块：`MAVEN_STATIC`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MAVEN_STATIC.STA_count2df` | — | 把 STATIC 单时刻计数数据换算为相空间密度（df）。 |
| `MAVEN_STATIC.STA_count2df_all` | — | 对 c6/d1 全时段计数数据一次性换算为相空间密度（df）。 |
| `MAVEN_STATIC.STA_count2eflux` | — | 把 STATIC 单时刻计数数据换算为能量通量（eflux）。 |
| `MAVEN_STATIC.STA_count2eflux_all` | — | 对全时段计数数据一次性换算为能量通量（eflux）。 |
| `MAVEN_STATIC.STA_count3df` | — | 把 c6 数据包（含时间轴）换算为 3D（time×mass×energy）相空间密度。 |
| `MAVEN_STATIC.STA_eflux2df` | — | 把 STATIC 能量通量数据换算为相空间密度（df）。 |
| `MAVEN_STATIC.compare_quality` | — | 判断质量标志是否命中指定的无效标志位集合。 |
| `MAVEN_STATIC.get_quality_flag` | — | 把整数质量标志位解码为 16 元素的布尔元组。 |
| `MAVEN_STATIC.sta_n_4d` | — | 由 STATIC 切片仅计算离子密度。 |
| `MAVEN_STATIC.sta_v_1d` | — | 由 c6 的 3D 相空间密度计算全时段一维离子速度、通量与密度时间序列。 |
| `MAVEN_STATIC.sta_v_4d` | — | 由 STATIC 切片（3D：mass×bins×energy）计算离子速度、通量与密度。 |
| `MAVEN_STATIC.static_c6_energy_mean` | — | 对 c6 的 3D（不含角度）数据在能量维度做筛选求和，得到 EFlux–mass 谱。 |
| `MAVEN_STATIC.static_c6_mass_mean` | — | 对 c6 的 3D（不含角度）数据在质量维度做筛选求和，得到 EFlux–energy 谱。 |
| `MAVEN_STATIC.static_rotation` | — | 把 STATIC 切片的角度网格与磁场矢量旋转到指定坐标系（MSO 或 SC）。 |
| `MAVEN_STATIC.static_slip` | — | 取得 STATIC 数据在指定时刻的切片（不做时间插值）。 |
| `MAVEN_STATIC.static_slip_2_V` | — | 把 STATIC 切片投影到速度空间网格（含航天器速度平移）。 |

### [`MAVEN_data/MAVEN_SWEA.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/MAVEN_data/MAVEN_SWEA.jl)

模块：`MAVEN_SWEA`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MAVEN_SWEA.SWEA_calc_shape_arr` | — |  |
| `MAVEN_SWEA.SWEA_calc_shape_arr_mars_towrads` | — | 计算 SWEA shape parameter 并区分"指向火星(toward)"与"背离火星(away)"。 |
| `MAVEN_SWEA.carclu_SWEA_pad` | — | 对 SWEA PAD 数据按能量窗做加权归并。 |
| `MAVEN_SWEA.load_quat` | — | 读取 IDL 导出的 CSV 姿态数据（ut + 4 个矩阵元素）。 |
| `MAVEN_SWEA.n1d` | — | 由 SWEA 电子能谱计算电子数密度（cm⁻³）。 |

### [`MAVEN_data/MAVEN_SWIA.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/MAVEN_data/MAVEN_SWIA.jl)

模块：`MAVEN_SWIA`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MAVEN_SWIA.get_3dc!` | — | 把 SWIA coarse 3D 原始数据整理为标准四维（time×anode×deflect×energy）网格。 |
| `MAVEN_SWIA.get_3df!` | — | 把 SWIA fine 3D 原始数据整理为标准四维网格（含能量/偏转步数裁剪）。 |
| `MAVEN_SWIA.j_3d` | — | 按指定的时间索引计算 SWIA 质子通量矢量（cm⁻²s⁻¹）。 |
| `MAVEN_SWIA.n_1d` | — | 由 SWIA svy spec（一维能谱）计算质子密度（cm⁻³）。 |
| `MAVEN_SWIA.n_3d` | — | 按指定的时间索引计算 SWIA 质子密度（cm⁻³）。 |
| `MAVEN_SWIA.v_3d` | — | 按指定的时间索引计算 SWIA 质子速度、通量与密度（已通过校验）。 |

### [`MAVEN_data/MAVEN_load.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/MAVEN_data/MAVEN_load.jl)

模块：`MAVEN_load`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MAVEN_load._file_index` | — |  |
| `MAVEN_load.change_kp_read_data` | — | 重设 KP 变量的列映射表。 |
| `MAVEN_load.convert_kp_l3` | — | 把 KP L3 原始字典转换为便于使用的规范字典。 |
| `MAVEN_load.file_list` | — | 获取指定模型在本地已下载的全部文件绝对路径。 |
| `MAVEN_load.filename_list` | — |  |
| `MAVEN_load.find_file_of_data` | — | 在指定模型的本地文件中按日期匹配目标文件。 |
| `MAVEN_load.find_segments` | — | 在布尔掩膜 `y` 中提取所有连续 `true` 段的起止横坐标。 |
| `MAVEN_load.get_orbits` | — | 读取 `orbit_time_range.txt`，返回各轨道的编号与起止时间。 |
| `MAVEN_load.load_MAVEN_data` | `export` | 按日期统一调度并加载多个仪器的数据（顶级调度函数）。 |
| `MAVEN_load.load_NGIMS_den_l3` | — | 读取 NGIMS L3 日产品密度表。 |
| `MAVEN_load.load_NGIMS_den_l4` | — | 读取 NGIMS L4 日产品密度表（JLD2 格式）。 |
| `MAVEN_load.load_NGIMS_sht_l3` | — | 读取 NGIMS L3 重采样标高表。 |
| `MAVEN_load.load_c6_v3d` | — | 读取 STATIC c6 三维（离子速度/通量/密度）数据（JLD2 格式）。 |
| `MAVEN_load.load_cdf` | — | 读取 CDF 数据文件并全部载入内存为字典。 |
| `MAVEN_load.load_d1_v4d` | — | 读取 STATIC d1 四维（离子速度/通量/密度）Fortran 无格式数据。 |
| `MAVEN_load.load_kp` | — | 读取 KP 文本文件（可选解析坐标变换矩阵）。 |
| `MAVEN_load.load_mag_l2` | — | 读取并解析 MAVEN MAG L2 文本磁场文件。 |
| `MAVEN_load.load_mag_vsc` | — | 读取 Fortran 无格式文件中的航天器速度与位置数据。 |
| `MAVEN_load.load_quat` | — | 读取 IDL 导出的四元数 CSV 文件。 |
| `MAVEN_load.load_swea_pad` | — | 读取 SWEA PAD CDF 文件，并可选合并俯仰角数据。 |
| `MAVEN_load.mean_SWEA_pad_pa` | `export` | 把 SWEA PAD 的 360°（16 方向）俯仰角数据平均为 180°（8 方向）。 |
| `MAVEN_load.show_load_models` | — | 列出当前已注册可读取的所有数据模型名称。 |

### [`MAVEN_data/MAVEN_plot.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/MAVEN_data/MAVEN_plot.jl)

模块：`MAVEN_plot`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MAVEN_plot.Orbit` | `export` | 绘制航天器轨道、火星投影及弓形激波/磁层顶边界。 |
| `MAVEN_plot.PAD_slice` | `export` | 绘制能量分箱下的俯仰角相空间密度切片。 |
| `MAVEN_plot.PAD_slice_polar` | `export` | 以极坐标（能量分量）绘制俯仰角分布切片。 |
| `MAVEN_plot.PAD_slice_velocity` | `export` | 将俯仰角分布映射到平行/垂直速度平面绘图。 |
| `MAVEN_plot.STA_2d_slip` | `export` | 在指定二维切面上绘制 STATIC 速度分布（df）切片。 |
| `MAVEN_plot.SWEA_PAD_heatmap` | `export` | 绘制 SWEA 俯仰角分布随时间变化的热图。 |
| `MAVEN_plot.VDF_2d_mask` | — | 绘制速度范围遮罩与投影边界。 |
| `MAVEN_plot.VDF_2d_slip` | — | 把任意三维速度分布投影到指定二维切面绘制。 |
| `MAVEN_plot.WaveSpectra_heatmap` | — | 绘制给定频率范围内的波动功率谱热图（强制对数纵轴）。 |
| `MAVEN_plot.bowshock_plot_nan64` | — | 返回绘图用弓形激波模型边界（Edberg 2008）的纵坐标。 |
| `MAVEN_plot.color_mapping_lut` | — | 把连续数值场**线性量化**为 `1–256` 的整数索引，用于自定义色标查找表（colormap LUT）或 |
| `MAVEN_plot.get_log_ticks` | — | 为**对数坐标轴**生成刻度位置与对应的富文本标签（如 `10ⁿ` 形式）。 |
| `MAVEN_plot.interpolate_x_ticks` | — | 把 `y` 通过分段插值映射到新的横坐标 `xd` 上，用于把刻度标签映射到非单调的时间轴。 |
| `MAVEN_plot.logticks` | — | 生成以 10 为底的指数刻度位置与标签。 |
| `MAVEN_plot.magnetopause_plot_nan64` | — | 返回绘图用磁层顶模型边界的纵坐标。 |
| `MAVEN_plot.sta_heatmap` | `export` | 绘制已准备好的 STATIC 能谱热图数据。 |
| `MAVEN_plot.sta_heatmap_test` | — | 从 STATIC 数据字典绘制能量分布热图。 |
| `MAVEN_plot.time2x` | `export` | 把时间序列裁剪到指定范围并转为相对 Unix 时间戳。 |
| `MAVEN_plot.time_ticks` | `export` | 生成时间范围内以固定步长取样的刻度位置与标签。 |
| `MAVEN_plot.vspan_plot` | — | 根据布尔时间序列在坐标轴上绘制区间色带。 |

### [`MGS_data/MGS_load.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/MGS_data/MGS_load.jl)

模块：`MGS_load`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MGS_load.get_data_from_line_for_mag_read` | — | 解析单条 MGS 磁场文本记录中的时间、磁场与位置。 |
| `MGS_load.load_mag` | — | 读取并解析指定的 MGS 磁场数据文件。 |
| `MGS_load.read_list` | — |  |

### [`TW_data/TW_MINPA.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/TW_data/TW_MINPA.jl)

模块：`TW_MINPA`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `TW_MINPA.MINPA_energy2v` | — | 由能量、角度与质量数网格计算速度空间网格（单位 km/s），并完成视场方向反号。 |
| `TW_MINPA.MINPA_get_psd` | — | 由微分方向通量计算相空间密度（PSD）并原地写入 `dat[:psd]`。 |
| `TW_MINPA.MINPA_sphere2xyz` | — | 将 MINPA 仪器球坐标 `(r, θ, ϕ)` 转换为笛卡尔向量（弧度制输入）。 |
| `TW_MINPA.MINPA_xyz2sphere` | — | 将笛卡尔向量反算为 MINPA 仪器球坐标 `(r, θ, ϕ)`（弧度制输出），是 `MINPA_sphere2xyz` 的逆变换。 |
| `TW_MINPA.build_file_list` | — | 扫描 MINPA 数据目录并构建 `MINPA_list.txt` 文件清单。 |
| `TW_MINPA.load_mod1` | — | 读取并解码指定的 MINPA mod1 数据文件，补齐质量数、能量、极角与方位角网格。 |
| `TW_MINPA.read_list` | — | 读取 MINPA 本地文件清单（`MINPA_list.txt`）并拼上根目录，返回完整路径。 |
| `TW_MINPA.slice2d_cal_rot_matrix` | — | 根据两个方向向量计算二维切片的局部坐标系旋转矩阵。 |
| `TW_MINPA.v3d` | — | 由全时段 MINPA 数据积分得到三维速度、通量与密度时间序列。 |
| `TW_MINPA.v3d_single` | — | 对单个时刻的 MINPA 切片积分得到三维速度、通量与密度。 |

### [`TW_data/TW_load.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/TW_data/TW_load.jl)

模块：`TW_load`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `TW_load.get_spc2mso_rot_matrix_via_2c` | — |  |
| `TW_load.load_mag_2c_bydlm` | — | 读取并整理天问一号磁场 2C 数据文件（文本格式，前 19 行为表头）。 |
| `TW_load.read_list` | — | 读取天问磁场本地文件清单（`mag_list.txt`）并拼上根目录，返回完整路径。 |

### [`analysis/Pickup_ion.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/analysis/Pickup_ion.jl)（脚本/附加代码；非 `load_module`）

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `func_E_range` | — | 由中心能量 `E` 与能量分辨率 `dE` 计算**对数等分**的能量区间上下限。 |
| `get_3d_slip_data_from_ins_FOR_PICKUP` | — | 从仪器（SWI / STATIC / MINPA）数据中提取**单个时刻的三维速度切片**，并统一为标准化的 |
| `get_pickup_point` | — | 把三维速度空间中需保留的**采样点**映射回仪器网格索引，返回可用于快速查找的索引元组列表。 |
| `σex` | — |  |

### [`call_fortran_dll.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/call_fortran_dll.jl)

模块：`Call_fortran_dll`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `Call_fortran_dll.Bspline_db1ink` | — | 调用 Fortran B 样条例程生成一维插值系数。 |
| `Call_fortran_dll.Bspline_db1var` | — | 调用 Fortran B 样条例程做单点插值。 |
| `Call_fortran_dll._bspline_dll_path` | — |  |
| `Call_fortran_dll._linear_growth_rate_dll_path` | — |  |
| `Call_fortran_dll.cold_plasma_linear_growth` | — | 调用 Fortran 例程计算冷等离子体线性增长率。 |

### [`common/MarsCommon.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/common/MarsCommon.jl)

模块：`MarsCommon`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MarsCommon.doppler_shift` | `export` | 计算考虑**航天器运动**后的等离子体波频率（多普勒修正），返回**角频率**。 |
| `MarsCommon.e_energy2v` | `export` | 将电子动能（自**静质量起算**）换算为**相对论速度**，单位 m/s。 |
| `MarsCommon.eflux_to_df!` | `export` | **原地**为 SWIA / SWEA 数据字典补充分布函数 `:df`（由微分能通量换算得到）。 |
| `MarsCommon.electron_eflux_to_psd` | `export` | 将**电子能通量（energy flux）**转换为**相空间密度（Phase Space Density, PSD）**。 |
| `MarsCommon.ion_eflux_to_psd` | `export` | 将**离子能通量**转换为**相空间密度（PSD）**，使用精确的相对论动量公式。 |
| `MarsCommon.ion_eflux_to_psd_approx` | `export` | 使用**速度幂次近似式**将离子能通量换算为相空间密度（PSD），与仪器（SWIA/STATIC）常用的 |
| `MarsCommon.ion_energy2v` | `export` | 将离子动能（自**静质量起算**）换算为**相对论速度**，单位 m/s。 |
| `MarsCommon.ion_speed_to_energy` | `export` | 将离子**相对论速度**反算为动能，单位 eV。 |
| `MarsCommon.position_altitude` | `export` | 由**按行堆叠**的行星笛卡尔位置计算每行对应的海拔高度（单位与输入一致，通常为 km）。 |
| `MarsCommon.position_latitude` | `export` | 由行星笛卡尔位置计算**行星纬度**，单位度（−90°–90°）。 |
| `MarsCommon.position_local_time` | `export` | 由行星笛卡尔位置计算**地方时（Local Solar Time, LST）**，单位小时（0–24 h）。 |
| `MarsCommon.rotate_vector` | `export` | 使用旋转矩阵对**单个向量或按行堆叠的向量数组**执行坐标变换。 |
| `MarsCommon.searchsortednearest` | `export` | 在**已排序的时序数据轴** `x` 中查找与目标时刻 `x0` 最接近的元素下标。 |
| `MarsCommon.searchsortednearest_range` | `export` | 把时间区间转换成时间轴 `x` 上的连续索引范围（内部用 `searchsortednearest` 二分定位两端）。 |
| `MarsCommon.spherical_to_cartesian` | `export` | 将**常规球坐标**（余纬自 +Z 轴起算）转换为笛卡尔分量 `(x, y, z)`。 |

### [`common/constants.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/common/constants.jl)

模块：`constants`

未发现顶层函数定义。

### [`common/data_keys.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/common/data_keys.jl)

模块：`DataKeys`

未发现顶层函数定义。

### [`common/function_coordinate.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/common/function_coordinate.jl)

模块：`FunctionCoordinate`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `FunctionCoordinate.MAVEN_sphere2xyz` | `export` | 将 MAVEN 仪器球坐标 `(r, theta, phi)` 转换为笛卡尔坐标。 |
| `FunctionCoordinate.MAVEN_sphere2xyz` | `export` |  |
| `FunctionCoordinate.MAVEN_xyz2sphere` | `export` | 将 MAVEN 仪器笛卡尔坐标转换为 `(r, theta, phi)`，角度为角度制；原点行为沿用旧公式。 |
| `FunctionCoordinate.MAVEN_xyz2sphere` | `export` |  |
| `FunctionCoordinate.MINPA_sphere2xyz` | `export` | 将**天问一号 MINPA 仪器坐标系**的球坐标 `(r, θ, ϕ)` 转换为笛卡尔向量，并完成 |
| `FunctionCoordinate.MINPA_sphere2xyz` | `export` |  |
| `FunctionCoordinate.MINPA_xyz2sphere` | `export` | 将笛卡尔向量反算为**天问一号 MINPA 仪器坐标系**球坐标 `(r, θ, ϕ)`（角度制）， |
| `FunctionCoordinate.MINPA_xyz2sphere` | `export` |  |
| `FunctionCoordinate._as_svector3` | — |  |
| `FunctionCoordinate.pa_sphere2xyz` | `export` | 将**俯仰角球坐标** `(r, theta, phi)` 转换为笛卡尔向量，是 `pa_xyz2sphere` 的逆变换。 |
| `FunctionCoordinate.pa_sphere2xyz` | `export` |  |
| `FunctionCoordinate.pa_xyz2sphere` | `export` | 将**笛卡尔向量**转换为**俯仰角球坐标** `(r, theta, phi)`（角度制）。 |
| `FunctionCoordinate.pa_xyz2sphere` | `export` |  |
| `FunctionCoordinate.pc2sphere` | `export` | 将行星笛卡尔坐标 `(x,y,z)` 转为 `(r, θ, ϕ)`：余纬和经度均为弧度。 |
| `FunctionCoordinate.pc2sphere` | `export` |  |
| `FunctionCoordinate.rotation_matrix` | `export` | 由天顶角与方位角生成坐标旋转矩阵。 |
| `FunctionCoordinate.slice2d_cal_rot` | `export` | 根据给定的两个向量 `v1`、`v2`，通过 Gram-Schmidt 正交化构造 **2D 切片局部坐标系**的 3D 旋转矩阵。 |
| `FunctionCoordinate.sphere2pc` | `export` | 将 `(r, θ, ϕ)` 转为行星笛卡尔坐标；角度均为弧度，计算顺序与 |
| `FunctionCoordinate.sphere2pc` | `export` |  |

### [`common/marscommon/cyclotron.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/common/marscommon/cyclotron.jl)

归属模块：`MarsCommon`（由 `common/MarsCommon.jl` include）

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MarsCommon.cyclotron_frequency` | — | 计算带电粒子的回旋频率。 |
| `MarsCommon.cyclotron_frequency_kg` | — | 计算带电粒子的回旋频率。 |
| `MarsCommon.cyclotron_radius` | — | 计算带电粒子的回旋频率、回旋半径与速度。 |
| `MarsCommon.cyclotron_radius_velocity` | — | 计算带电粒子的回旋半径。 |

### [`common/marscommon/geometry.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/common/marscommon/geometry.jl)

归属模块：`MarsCommon`（由 `common/MarsCommon.jl` include）

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MarsCommon.Bpc2sphere` | `export` | 将笛卡尔坐标系下的磁场分量转换为球坐标分量，是 `Bsphere2pc` 的逆变换。 |
| `MarsCommon.Bpc2sphere_naive` | `export` | **非等价变体**（保留原算法，不改为 `hypot`）：笛卡尔磁场分量 → 球坐标分量，半径用 |
| `MarsCommon.Bsphere2pc` | `export` | 将球坐标系下的磁场分量转换为笛卡尔分量（纯旋转变换，不改变大小）。 |
| `MarsCommon.get_angle` | — | 计算两个三维向量之间的**夹角**，输出**角度制**，在极小夹角下仍具有极高数值精度。 |
| `MarsCommon.get_normal_plane` | — | 由平面的**法向量**构造该平面的两个基向量（用于把三维切片投影到二维绘图平面）。 |
| `MarsCommon.vector_angle` | — | 计算两个向量之间的夹角（度）。 |

### [`common/marscommon/numerics.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/common/marscommon/numerics.jl)

归属模块：`MarsCommon`（由 `common/MarsCommon.jl` include）

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MarsCommon.Linear_fit` | — | 对一维数据做最小二乘线性拟合。 |
| `MarsCommon.Vandermonde` | — | 构造指定阶数的 Vandermonde 矩阵。 |
| `MarsCommon.polynomial_fit` | — | 对 `y` 的对数用 n 阶多项式拟合 `x`。 |
| `MarsCommon.solve_func` | — | 用**二分法**求解方程 `func(x) − y0 = 0`，用于求弓激波/磁堆积边界曲面在给定圆柱半径处的 |

### [`common/marscommon/statistics.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/common/marscommon/statistics.jl)

归属模块：`MarsCommon`（由 `common/MarsCommon.jl` include）

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MarsCommon.find_range` | — | 生成布尔掩码，标记数值数组中落入闭区间 `xr` 的元素。 |
| `MarsCommon.geomean` | — | 计算数组的**几何平均值** `exp(mean(log(x)))`，支持沿指定维度归约。 |
| `MarsCommon.nozeros` | — | **原地**把数组中的 `0` 替换为一个极小数 `1e-20`，用于规避对数/除法运算中的奇点。 |
| `MarsCommon.safe_log_mean` | — | 计算**正值数据的对数均值**，对 `0`、`NaN`、`Inf` 等无效值具有容错能力。 |
| `MarsCommon.skipnan` | — | 移除数组中的 `NaN` 元素，返回仅含有限值的紧凑向量。 |

### [`common/paths.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/common/paths.jl)

模块：`Paths`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `Paths._configured_root` | — |  |
| `Paths._is_windows_absolute` | — |  |
| `Paths._load_settings` | — |  |
| `Paths.fortran_dll_dir` | — |  |
| `Paths.index_path` | — |  |
| `Paths.maven_data_root` | — |  |
| `Paths.mgs_data_root` | — |  |
| `Paths.project_root` | — |  |
| `Paths.tw_data_root` | — |  |

### [`models/Cold_Plasma_Dispersion_Relation.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/models/Cold_Plasma_Dispersion_Relation.jl)

模块：`Cold_Plasma_Dispersion_Relation`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `Cold_Plasma_Dispersion_Relation.DR_phase_velocity` | — | 由折射率计算波的**相速度**。 |
| `Cold_Plasma_Dispersion_Relation.DR_wave_vector` | — | 由**折射率**与频率计算波的**波数（波矢大小）** `k`。 |
| `Cold_Plasma_Dispersion_Relation.Dispersion_Relation` | — | 显式状态版本：使用传入的 `PlasmaState` 计算冷等离子体折射率，不依赖模块全局状态。 |
| `Cold_Plasma_Dispersion_Relation.Dispersion_Relation` | — | 求解**冷等离子体色散关系**，返回给定传播角与频率下的**折射率（实部）** `μ`。 |
| `Cold_Plasma_Dispersion_Relation._build_plasma_state` | — |  |
| `Cold_Plasma_Dispersion_Relation._current_state` | — |  |
| `Cold_Plasma_Dispersion_Relation.alfven_weve` | — | 由磁场强度与等离子体**质量密度**计算 **Alfvén 速度** `v_A`。 |
| `Cold_Plasma_Dispersion_Relation.calculate_minimum_energy` | — | `carculate_minimum_energy` 的规范拼写别名，签名与行为完全一致。 |
| `Cold_Plasma_Dispersion_Relation.carculate_minimum_energy` | — | 计算满足**回旋共振条件**的粒子**最小能量** `E_min`。 |
| `Cold_Plasma_Dispersion_Relation.get_Πe` | — | 由电子数密度计算**电子等离子体频率** `Πe`。 |
| `Cold_Plasma_Dispersion_Relation.make_particles` | — | 纯函数版本：根据离子成分构建 `PlasmaState`，**不写模块全局状态**，可安全用于并行/隔离计算。 |
| `Cold_Plasma_Dispersion_Relation.set_particles` | — | 配置多成分**冷等离子体**的成分列表，并初始化本模块的全局归一化参数（回旋频率与等离子体频率平方）。 |

### [`models/IGRF_calculate.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/models/IGRF_calculate.jl)

模块：`IGRF_calculate`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `IGRF_calculate.CALCULATE_SCHMIDT_COEFFICIENTS` | — | 预计算 IGRF 球谐展开所需的 Schmidt 准归一化因子 `SS` 与 Legendre 递推系数 `REALK`。 |
| `IGRF_calculate.IGRF` | — | 纯 Julia 参考实现的球谐磁场求值（无动态库依赖），供校验与教学使用。 |
| `IGRF_calculate.IGRF_fortran` | — | 调用 Fortran IGRF_110 内核计算球谐磁场，`r` 为未归一化的实际半径。 |
| `IGRF_calculate.IGRF_fortran_free` | — | 调用 Fortran 的 IGRF_FREE 内核计算球谐磁场，输入半径必须已归一化（除以 `R_Mars`）。 |
| `IGRF_calculate.IGRF_pc` | `export` | 在行星笛卡尔坐标处计算 IGRF/地壳磁场矢量（nT）。 |
| `IGRF_calculate.RK4_Trace_fortran` | — | 调用 Fortran RK4_STEP 内核执行一次定步长 RK4 磁力线步进。 |
| `IGRF_calculate.combina_two_dir_trace` | — | 把两个相反方向追踪得到的磁力线段拼接为一条完整磁力线。 |
| `IGRF_calculate.get_mag_line_s` | — | 为磁力线结果字典原地补充沿线的弧长、海拔与磁场总强度。 |
| `IGRF_calculate.mag_trace_Euler_step` | — | 用定步长一阶 Euler 法追踪磁力线（速度最快但精度最低）。 |
| `IGRF_calculate.mag_trace_rk4` | — | 用 Julia 侧循环 + Fortran 单步内核执行带自适应步长的 RK4 磁力线追踪。 |
| `IGRF_calculate.mag_trace_rk4_fortran_ADAPTIVE_STEP` | — | 用 Fortran 内核执行自适应步长 RK4 磁力线追踪，输入/输出均为球坐标。 |
| `IGRF_calculate.pc2sphere` | — | 将行星笛卡尔坐标转为球坐标 `(r, θ, ϕ)`（θ 为与 +Z 轴的夹角，即天顶角/余纬）。 |
| `IGRF_calculate.read_gh` | — | 从 Fortran 无格式文件 `gh_gao` 中读取 IGRF 高斯球谐系数 `GG`、`HH`。 |
| `IGRF_calculate.set_B_compress` | — | 更新模块全局的外源磁场压缩修正参数 `B_compress`。 |
| `IGRF_calculate.sphere2pc` | — | 将行星球坐标转为笛卡尔坐标，是 `pc2sphere` 的逆变换。 |
| `IGRF_calculate.trace_mag_line` | `export` | 顶层磁力线追踪接口：从给定起点沿磁场双向追踪并拼接成完整磁力线。 |

### [`models/IGRF_test.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/models/IGRF_test.jl)

模块：`IGRF_calculate_test`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `IGRF_calculate_test.Bpc2sphere` | `export` |  |
| `IGRF_calculate_test.Bsphere2pc` | `export` |  |
| `IGRF_calculate_test.CALCULATE_SCHMIDT_COEFFICIENTS` | — |  |
| `IGRF_calculate_test.IGRF` | — |  |
| `IGRF_calculate_test.IGRF_fortran` | — |  |
| `IGRF_calculate_test.IGRF_fortran_free` | — |  |
| `IGRF_calculate_test.IGRF_pc` | `export` |  |
| `IGRF_calculate_test.RK4_Trace_fortran` | — |  |
| `IGRF_calculate_test.combina_two_dir_trace` | — |  |
| `IGRF_calculate_test.get_mag_line_s` | — |  |
| `IGRF_calculate_test.mag_trace_Euler_step` | — |  |
| `IGRF_calculate_test.mag_trace_rk4` | — |  |
| `IGRF_calculate_test.mag_trace_rk4_fortran_ADAPTIVE_STEP` | — |  |
| `IGRF_calculate_test.pc2sphere` | `export` |  |
| `IGRF_calculate_test.read_gh` | — |  |
| `IGRF_calculate_test.set_B_compress` | — |  |
| `IGRF_calculate_test.sphere2pc` | `export` |  |
| `IGRF_calculate_test.trace_mag_line` | `export` |  |

### [`models/Mars_Environment.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/models/Mars_Environment.jl)

模块：`MarsEnvironment`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MarsEnvironment.bowshock` | — |  |
| `MarsEnvironment.bowshock_zero` | — | 求解火星**弓激波曲面**在给定 Sun-Mars 轴向坐标处的圆柱半径，并把"曲面外"的输入钳制为 `0.0`。 |
| `MarsEnvironment.escape_energy` | — | 计算指定行星表面逃逸所需的最小粒子能量。 |
| `MarsEnvironment.get_bowshock_normal` | — | 由给定位置与太阳风速度，计算**弓激波曲面上的局部法向反射速度**（常用于拾取离子/激波相互作用分析）。 |
| `MarsEnvironment.magnetopause` | — |  |
| `MarsEnvironment.mars_sun_dist_phys` | — | 根据**太阳黄经 `Ls`** 计算火星与太阳之间的瞬时距离（日火距离），单位 AU。 |

### [`models/Maxwellian_distribution.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/models/Maxwellian_distribution.jl)

模块：`Maxwellian_Distribution`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `Maxwellian_Distribution.fit_velocity_density_distribution` | — | 用**线性最小二乘**拟合带数密度与漂移速度的 Maxwell 速度密度分布。 |
| `Maxwellian_Distribution.fit_velocity_distribution` | — | 用**线性最小二乘**拟合速度模分布数据，反演 Maxwell 分布的温度等参数。 |
| `Maxwellian_Distribution.fit_velocity_distribution_nonlinear` | — | 用**非线性最小二乘**（Levenberg–Marquardt）在对数域拟合 Maxwell 速度分布，**同时反演** |
| `Maxwellian_Distribution.velocity_density_distribution` | — | 计算含**数密度**与**漂移速度**的 Maxwell 速度模**密度**分布 `fd(v)`。 |
| `Maxwellian_Distribution.velocity_distribution` | — | 计算**速度模概率分布函数** `f(v)`（Maxwell–Boltzmann），单位 `1/(速度单位)`。 |

### [`models/Single_Particle_Orbit.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/models/Single_Particle_Orbit.jl)

模块：`Single_Particle_Orbit`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `Single_Particle_Orbit.B` | — |  |
| `Single_Particle_Orbit.E` | — |  |
| `Single_Particle_Orbit.TimeFormatMMSS` | — | 把两个时间点之差格式化为 `MM:SS.mmm` 字符串，用于进度日志。 |
| `Single_Particle_Orbit.cross3` | — | 计算两个三维向量的**叉积** `a × b`，固定返回 `SVector{3}`。 |
| `Single_Particle_Orbit.cyclotron_radius` | `export` | 由磁场强度与速度计算粒子的**回旋频率**、**回旋半径**，并回传速度。 |
| `Single_Particle_Orbit.dvdt` | — | 计算带电粒子在电磁场中的**加速度** `dv/dt = mq·(E + v × B)`（洛伦兹力方程）。 |
| `Single_Particle_Orbit.ion_alvfen` | — | 由数密度与磁场强度计算** Alfvén 速度**。 |
| `Single_Particle_Orbit.solve_orbit` | `export` | 用**定步长 RK4** 积分带电粒子在给定电磁场中的完整轨道，返回速度、位置、磁场与弧长等时间序列。 |
| `Single_Particle_Orbit.solve_orbit_ode` | `export` | 用 **DifferentialEquations.jl 的自适应求解器（Tsit5）**求解粒子轨道，适合需要高精度或变步长的场景。 |

### [`models/extras/Graham.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/models/extras/Graham.jl)（脚本/附加代码；非 `load_module`）

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `graham_scan!` | — | 对二维点集执行 **Graham 扫描（凸包算法）**，**原地**重排 `points` 并返回凸包顶点序列。 |
| `graham_scan_for_orbit` | — | 从轨道位置序列中提取**二维凸包**，返回可用于绘图的多边形边界点坐标。 |

### [`models/extras/Octree.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/models/extras/Octree.jl)（脚本/附加代码；非 `load_module`）

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `build_octree!` | — | 根据区域判定函数**递归细分**八叉树节点，标记哪些节点位于目标区域内部。 |
| `get_min_bounding_box` | — | 根据区域判定函数，用八叉树搜索并返回目标的**最小轴对齐包围盒**（AABB）。 |
| `is_sphere` | — | 判断给定点是否位于**单位球**内（本文件用于验证八叉树的示例区域判定函数）。 |

### [`models/test.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/models/test.jl)

未发现顶层函数定义。

### [`src/MarsData.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/src/MarsData.jl)

模块：`MarsData`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MarsData.data_model` | — |  |
| `MarsData.index_path` | — |  |
| `MarsData.load_index` | — |  |
| `MarsData.load_registry` | — |  |
| `MarsData.maven_data_root` | — |  |
| `MarsData.mgs_data_root` | — |  |
| `MarsData.project_root` | — |  |
| `MarsData.tw_data_root` | — |  |

### [`src/modules.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/src/modules.jl)

归属模块：`MarsData`（由包入口 include）

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MarsData.Base.showerror` | — |  |
| `MarsData._apply_allow!` | — | 按白名单把 `into` 命名空间内的模块 `name` 的指定名字逐名引入。 |
| `MarsData._carrier` | — | 返回（并按需创建）**运行时载体模块**，所有被装载模块都在其中求值。 |
| `MarsData._editdistance` | — |  |
| `MarsData._spec` | — |  |
| `MarsData._spec_of` | — |  |
| `MarsData._topo_order` | — |  |
| `MarsData._unknown_message` | — |  |
| `MarsData.available_modules` | `export` | 返回全部可装载模块名（按字母序）。 |
| `MarsData.load_module` | `export` | 把注册表中的模块装载进 `into` 命名空间，等价于 `include(对应文件)`。 |
| `MarsData.loaded_modules` | `export` | 返回已装载到 MarsData 命名空间的注册模块。 |
| `MarsData.module_info` | `export` | 返回该模块的注册信息与当前状态（是否已装载到 MarsData 命名空间）。 |
| `MarsData.module_path` | `export` | 返回注册表中该模块的**绝对路径**（已归一化，不检查文件是否存在）。 |
| `MarsData.validate_registry` | `export` | 自检注册表：键与 `name` 一致、文件存在、文件内确有 `module <name>`、`deps` 均在注册表中、 |

### [`src/plotting.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/src/plotting.jl)

归属模块：`MarsData`（由包入口 include）

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `MarsData.TimeFormat` | `export` | 把两个时间点之间的时长格式化为 `HH:MM:SS.mmm` 字符串。 |
| `MarsData.plot_module` | `export` | 向图形对象添加 MAVEN 多仪器时间序列绘图面板。 |
| `MarsData.remove_0_point!` | `export` | 将非正绘图数据原地替换为 `NaN`。 |

### [`support_data/support_data_load.jl`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/support_data/support_data_load.jl)

模块：`SP_load`

| 限定名/函数名 | 标记 | docstring 首句 |
| --- | --- | --- |
| `SP_load.load_drivers_merge_data` | — | 读取 Halekas 等人推导的太阳风参数文件。 |
| `SP_load.load_omni2_data` | — | 读取并整理 OMNI2 太阳风支持数据。 |
| `SP_load.root_path` | — |  |

## 非模块脚本

`analysis/Pickup_ion.jl` 含交互式分析流程，依赖预先设置的事件变量；它是脚本入口，不能经 `MarsData.load_module` 装载。`models/extras/` 下的 Graham/Octree 为独立附加代码，不在模块注册表中，也不能经 `load_module` 装载。

`call_fortran_dll.jl` 提供动态库调用封装；索引只解析其语法，不会加载或调用 DLL。
