# 迁移指南

当前架构已替换旧的聚合 include 入口。请先更新路径与模块归属，再按具体函数签名适配调用；不为已移除的入口保留兼容 alias。新项目入口见[项目架构](architecture.md)，实际定义见[程序与函数索引](api.md)。

## 路径与模块

| 旧入口或位置 | 当前用法 |
| --- | --- |
| `common/head.jl` | 已删除；显式 `using` 所需外部包，并用 `MarsData.@load` 或限定名访问所需模块 |
| `calculate/calculate_models.jl`、`:calculate_models` | 已删除；通用计算在 `MarsCommon`，旋转工具在 `FunctionCoordinate`，环境函数在 `MarsEnvironment` |
| `Magnetic_Model/IGRF_calculate.jl` | `models/IGRF_calculate.jl`；推荐 `MarsData.load_module(:IGRF_calculate)` |
| `Magnetic_Model/gh_gao`、`Magnetic_Model/IGRF_DLL.dll` | 随源码移到 `models/`，仍按源码同目录定位；文本备份 `Magnetic_Model/gh_gao.txt` 保留。**后续变更**：IGRF 已纯 Julia 化（2026-10-16），`models/IGRF_DLL.dll` 与其 `ccall` 封装一并删除，仅保留系数文件 `gh_gao` |
| `models/Pickup_ion.jl` | `analysis/Pickup_ion.jl`；仍是依赖事件上下文的脚本，尚未函数化 |
| `models/Graham.jl`、`models/Octree.jl` | `models/extras/`；通过 `models/CATALOG.toml` 查看用途与依赖，显式 include |
| 包装前的 `common/function_coordinate.jl` | 现在定义 `module FunctionCoordinate`；include 后使用模块限定名 |
| 文件名 `models/Mars_Environment.jl` | 文件名保留，模块名为 `MarsEnvironment`，包内规范实例为 `MarsData.MarsEnvironment` |

不要从旧 `head.jl` 的隐式依赖推断新脚本已经导入 Dates、JLD2 或绘图包。请根据脚本实际使用的名字显式导入；`@load` 只提供注册模块与其白名单名字。

## 名称与归属

| 旧写法 | 当前写法及限制 |
| --- | --- |
| `MAVEN_load.data_get_from_date` | `MAVEN_load.load_MAVEN_data`；当前签名接受单个 `DateTime`，参见读取指南 |
| `MarsCommon.electron_energy_to_speed` | `MarsCommon.e_energy2v` |
| `MarsCommon.ion_energy_to_speed` | `MarsCommon.ion_energy2v` |
| `MAVEN_load.carclu_SWEA_pad` | `MAVEN_SWEA.carclu_SWEA_pad`，保留现有拼写 |
| `MAVEN_load` 中的 SWEA shape 计算 | `MAVEN_SWEA.SWEA_calc_shape_arr`、`SWEA_calc_shape_arr_mars_towrads` |
| IGRF 中本地定义的 `Bsphere2pc`、`Bpc2sphere` | 权威实现在 `MarsCommon`；IGRF 内部绑定它们，不再导出这两个名字 |
| `MAVEN_load.Bpc2sphere` 的 sqrt 实现 | `MarsCommon.Bpc2sphere_naive`，不是稳健 `Bpc2sphere` 的 alias |
| `TW_MINPA.slice2d_cal_rot` | `TW_MINPA.slice2d_cal_rot_matrix` |
| `Single_Particle_Orbit.TimeFormat` | `Single_Particle_Orbit.TimeFormatMMSS`；包级 `MarsData.TimeFormat` 仍是另一种格式 |
| 从旧 `head.jl` 使用的 `color_mapping` LUT | `color_mapping_lut`；不要改写绘图函数内部同名局部实现 |
| `sta_v_4d_new` | 已删除；使用 `MAVEN_STATIC.sta_v_4d`，不保留测试版本入口 |
| loader 的 `cyclone_frequency`、`cyclone_R` | `MarsCommon.cyclotron_frequency_kg`、`cyclotron_radius_velocity`；不要替换成单位体系不同的同类函数 |

`mean_SWEA_pad_pa` 保留在 `MAVEN_load`，由读取器 `load_swea_pad` 调用。不要把它与已迁入 SWEA 的 PAD 计算一并批量改名。

## 坐标和旋转接口

`FunctionCoordinate` 不在模块注册表中。迁移旧的隐式裸名调用时，显式 include 并使用限定名：

```julia
using MarsData, StaticArrays
include(joinpath(MarsData.project_root(), "common", "function_coordinate.jl"))
p = SVector(1.0, 2.0, 3.0)
spherical = FunctionCoordinate.pc2sphere(p)
p_back = FunctionCoordinate.sphere2pc(spherical)
```

`FunctionCoordinate` 的单点坐标转换使用 `SVector{3}` 输入输出，并接受长度为 3 的 `AbstractVector{<:Real}` 适配输入。批量点在调用端用 `f.(points)`；行存 `N×3` 数据逐行调用，见[坐标转换专题](coordinates.md)。IGRF 的 `pc2sphere(x,y,z)`、`sphere2pc(r,θ,ϕ)` 仍为内部标量辅助函数，不 `export` 且不由 `@load IGRF_calculate` 裸名开放；白名单仅保留 `IGRF_pc`。通用点 API 使用 `FunctionCoordinate`，模型场值入口使用 `IGRF_pc`。

旧 `Quaternion_Rot` 和 `Quaternion_Rot_reverse` 包装已删除。对列向量直接使用 `Rotations.QuatRotation` 的 `q * v`、`inv(q) * v`，或使用 `R * v`。`rotation_matrix(θ, φ)` 仍返回普通 `3×3 Matrix`，`slice2d_cal_rot(v1, v2)` 返回 `RotMatrix{3}`；二者都是矩阵构造函数，调用方需定义 source/target 基底方向。列形式 `p_target = R_source_to_target * p_source` 对应行存点 `P_target = P_source * transpose(R_source_to_target)`。

## 代表性调用

```julia
using MarsData, Dates
MarsData.@load MAVEN_load MAVEN_STATIC

errors = String[]
data = MAVEN_load.load_MAVEN_data(
    DateTime(2015, 2, 9);
    model_index=["MAG_ss1s_cdf"],
    error_report=errors,
)
# 数据文件与读取器额外依赖必须提前准备；先检查成功标志再访问物理量。
if data["MAG_ss1s_cdf"][:data_load_flag]
    B = data["MAG_ss1s_cdf"][:B]
end
```

`model_index` 使用产品注册表中的别名。多日读取由调用方对 `DateTime` 循环；不要把旧示例中的日期字符串数组直接传给当前单日接口。

通用能量换算是标量接口，处理数组时在调用处广播：

```julia
energy = [100.0, 1000.0]
v = MarsData.MarsCommon.ion_energy2v.(energy, 1)
```

## 不能当作同一实现替换的函数

| 实现 | 必须保留的区别 |
| --- | --- |
| `MarsCommon.Bpc2sphere` 与 `Bpc2sphere_naive` | 前者用 `hypot`，后者用 `sqrt`；大坐标时上溢行为不同 |
| `FunctionCoordinate.slice2d_cal_rot` 与 `TW_MINPA.slice2d_cal_rot_matrix` | 返回类型及共线输入的异常/结果行为不同 |
| `MarsEnvironment.bowshock`、`magnetopause` 与绘图模块的 `*_plot_nan64` | Float32/NaN32 与 Float64/NaN64 路径分别保留 |
| kg/速度体系与 AMU/能量体系的回旋计算 | 质量、输入速度或能量、输出单位及浮点运算顺序均需按签名核对 |
| `MarsData.TimeFormat` 与 `Single_Particle_Orbit.TimeFormatMMSS` | 分别为 `HH:MM:SS.mmm` 与 `MM:SS.mmm` |

## 质量基准与逻辑溯源

STATIC 数据包的 `:mass` 与 SWIA 中的同名量都是单位特定的质子静止质量。当前 STATIC 计算直接使用 Float64 常量 `constants.mp_eV_per_km_s2`，而不是包内通常为 Float32 的 `dat[:mass]`。这是已记录的精度提升，不应描述为与旧 Float32 路径逐位相同。质量轴 `mass_arr` 和计算参数 `m_int` 的角色没有因此互换。

本项目逻辑比较的初始代码基准为 `a09511aa7b88c874cefe8ca966c98aa267db9365`。重构中的移动、独立命名及上述精度变化需分别解释；旧中间提交上的局部回归不能用来声称全部代码已与该初始提交一致。

2026-10-16 已完成六份真实文件的读取与复跑比对，详见[验证记录](../reports/real_data_validation_2026-10-16.md)；尚未进行重构前逐值对照或 DLL 验证。合成夹具和静态代码检查仍可保护公式、运算顺序、NaN 位置、异常类型与就地修改行为。文档构建不装载科学模块、不运行 Pickup 脚本，也不调用 DLL。

`docs/reports/` 与 `CHANGELOG.md` 保留历史事实；里面的旧路径不作为当前入口。后续维护请修改当前文档源并重新生成 API 索引和 Wiki。
