"""通用科学计算辅助函数：时间、统计、几何、边界模型与绘图支持。"""

using TimesDates, Dates
using ColorTypes
using LinearAlgebra
using Statistics
using GeometryBasics
using DataInterpolations
using Interpolations
using Optim
using LsqFit
using ProgressMeter
using SpecialFunctions
using DSP
using JSON
using IniFile
using Base.Iterators
using StaticArrays
using Base.Threads
using CSV
using DataFrames
using Rotations
using SparseArrays
using JLD2
using QuadGK
using Base.Threads

Package_path = normpath(joinpath(@__DIR__, "..")) * "/"
if !isdefined(Main, :MAVEN_load)
    include(Package_path*"MAVEN_data/MAVEN_load.jl");import .MAVEN_load;
    include(Package_path*"MAVEN_data/MAVEN_plot.jl");import .MAVEN_plot;
    include(Package_path*"MAVEN_data/MAVEN_STATIC.jl");import .MAVEN_STATIC;
    include(Package_path*"support_data/support_data_load.jl");import .SP_load;
    include(Package_path*"MAVEN_data/MAVEN_SWIA.jl");import .MAVEN_SWIA;
    include(Package_path*"models/Maxwellian_Distribution.jl");import .Maxwellian_Distribution;
end

print_f = x -> "$(round(x,digits=3))"
norm2 = x-> [norm(xx) for xx in eachrow(x)]

label_data = (
    C_obs = rich("C",font = :italic,rich(subscript("obs"),font = :regular)),
    energy = rich("E",font =:italic,subscript("k", font = :regular)," ",rich("(eV)",font = :regular)),
    time_s = rich("t",font =:italic," ",rich("(s)",font = :regular)),
    dt = rich(rich("Δ",font = :regular),"t",font =:italic," ",rich("(s)",font = :regular)),
    O2 = rich("O",superscript("+"),subscript("2",offset=(-0.6,0))),
    eflux_e=rich("J",font =:italic,subscript("e", font = :regular)),
    eflux_i=rich("J",font =:italic,subscript("i", font = :regular)),
    O = rich("O",superscript("+")),
    H = rich("H",superscript("+")),
    He = rich("He",superscript("2+")),
    p = rich("p",superscript("+")),
    i = rich("i",superscript("+")),
    v =  rich(rich("v",font =:italic), " (km/s)"),
    vpara =  rich(rich("v",font =:italic), subscript("||",offset=(0,0)), " (km/s)"),
    vperp =  rich(rich("v",font =:italic), subscript("⊥",offset=(0,0)), " (km/s)"),
    den_ion = rich("N",font =:italic,subscript("i", font = :regular)," ",rich("(cm",superscript("-3"),")",font = :regular)),
    den_e = rich("N",font =:italic,subscript("e", font = :regular)," ",rich("(cm",superscript("-3"),")",font = :regular)),
    den = rich("N",font =:italic," ",rich("(cm",superscript("-3"),")",font = :regular)),
    flux = rich("F",font=:italic,rich(" (cm",font=:regular,superscript("-2"),"s",superscript("-1"),")")),
    den_pu = rich(
        rich("N", font = :italic),
        subscript("PH"), " ",
        rich("(cm", superscript("-3"), ")", font = :regular)),
    flux_pu = rich(
        rich("F", font = :italic),
        subscript("PH"), " ",
        rich("(cm", superscript("-2"), " s", superscript("-1"), ")", font = :regular)),
    msoX_v =  rich(rich("v",font =:italic), subscript("x,MSO"), " (km/s)"),
    msoY_v =  rich(rich("v",font =:italic), subscript("y,MSO"), " (km/s)"),
    msoZ_v =  rich(rich("v",font =:italic), subscript("z,MSO"), " (km/s)"),
    mseX_v =  rich(rich("v",font =:italic), subscript("x,MSE"), " (km/s)"),
    mseY_v =  rich(rich("v",font =:italic), subscript("y,MSE"), " (km/s)"),
    mseZ_v =  rich(rich("v",font =:italic), subscript("z,MSE"), " (km/s)"),
    PSD = rich("F",font =:italic," ",rich("(s",superscript("3")," cm",superscript("-3")," km",superscript("-3")," sr",superscript("-1"),")",font = :regular)),
    PSD_IS = rich("F",font =:italic," ",rich("(s",superscript("3")," m",superscript("-6"),")",font = :regular)),
    x_mso = rich("X",subscript("MSO")," (",rich("R",font = :italic),subscript("M"),")"),
    z_mso = rich("Z",subscript("MSO")," (",rich("R",font = :italic),subscript("M"),")"),
    x_mse = rich("X",subscript("MSE")," (",rich("R",font = :italic),subscript("M"),")"),
    z_mse = rich("Z",subscript("MSE")," (",rich("R",font = :italic),subscript("M"),")"),
)
"""
    find_time(x, x0) -> Int

在**单调递增**的时间数组 `x` 中查找与目标值 `x0` 最接近的元素索引。

# 功能与算法概述
对已排序序列用二分查找（`searchsortedfirst`，`O(log N)`）定位候选下标，再与其左邻元素比较距离取更近者；两端越界直接短路返回。

# 参数说明
- `x`: 单调递增的时间数组（`Vector{DateTime}`、`Vector{Float64}` 等可比较类型）。
- `x0`: 查找目标值，类型需与 `x` 的元素可比较。

# 返回值
- `Int`: `x` 中最接近 `x0` 的元素下标（1-based）。

# 性能
- 时间复杂度 `O(log N)`，优于 `findmin(abs.(x .- x0))` 的 `O(N)` 且不产生临时数组。

# 备注
- 当 `x0` 恰位于两个元素正中时，返回**较大**的下标（`idx_upper`）。
- 输入 `x` 必须已排序；未排序时不保证结果正确。
"""
function find_time(x, x0)
    local N = length(x)
    # 1. 边界情况处理：如果 x0 小于等于第一个元素
    if x0 <= x[1]
        return 1
    # 2. 边界情况处理：如果 x0 大于等于最后一个元素
    elseif x0 >= x[N]
        return N
    end
    # 3. 使用二分查找找到第一个大于或等于 x0 的元素的索引
    #    此操作的时间复杂度为 O(log N)
    local idx_upper = searchsortedfirst(x, x0)
    
    # idx_upper 现在是 x[idx_upper] >= x0 的最小索引
    # 因此，我们只需要比较 x[idx_upper] 和 x[idx_upper - 1] 即可
    
    local idx_lower = idx_upper - 1
    
    # 4. 比较哪个点更接近 x0
    if abs(x[idx_upper] - x0) <= abs(x[idx_lower] - x0)
        return idx_upper
    else
        return idx_lower
    end
end
"""
    safe_log_mean(x) -> Float64

计算**正值数据的对数均值**，对 `0`、`NaN`、`Inf` 等无效值具有容错能力。

# 功能与算法概述
先剔除 `≤0` 与非有限元素，再对剩余正值取几何平均（`10^mean(log10, ·)`）；无有效元素时返回 `0.0` 而不报错。

# 参数说明
- `x`: 待统计的数值数组（可含 `0`、`NaN`、`Inf`）。

# 返回值
- `Float64`: 有效元素的几何平均值；若不存在有效元素则返回 `0.0`。

# 备注
- 几何平均对量级跨越多个数量级的数据（如等离子体密度、通量）比算术平均更稳健。
- 与 `geomean` 的区别：本函数会**丢弃**非正/非有限值，而 `geomean` 不做筛选。
"""
function safe_log_mean(x)
    # 筛选出大于 0 的有效值
    valid_elements = Base.filter(v -> v > 0 && isfinite(v), x)
    
    if isempty(valid_elements)
        return 0.0  # 如果全是 0 或无效值，返回0.0
    else
        return 10 ^mean(log10, valid_elements)#median(valid_elements)#
    end
end
shape_phi = x -> (x % 360 + 360) % 360 #将phi映射到0-360
get_range = x -> (minimum(x),maximum(x))

"""
    mars_sun_dist_phys(Ls_deg) -> Float64

根据**太阳黄经 `Ls`** 计算火星与太阳之间的瞬时距离（日火距离），单位 AU。

# 功能与算法概述
采用开普勒轨道极坐标方程 `r = a(1−e²)/(1+e·cos(Ls−phi))`，参数取火星轨道半长轴 `a = 1.52368 AU`、离心率 `e = 0.09340`（近日点 `Ls = 270°`）。

# 参数说明
- `Ls_deg`: 太阳黄经 `Ls`（**角度制**，0°–360°；0° 为北半球春分）。

# 返回值
- `Float64`: 日火距离，单位 **AU**。取值在近日点约 `1.381 AU`、远日点约 `1.666 AU`。

# 备注
- `Ls` 是火星季节的标准时间变量，可用 `SPICE` 或轨道历元数据获取。
"""
function mars_sun_dist_phys(Ls_deg) # 火星-太阳风距离，单位AU
    # 物理常数定义
    a = 1.52368        # 半长轴 (AU)
    e = 0.09340        # 离心率
    phi = deg2rad(270.0) # 近日点相位 (Ls 坐标系)

    # 极坐标方程计算
    # 分子是半通径 p = a * (1 - e^2)
    numerator = a * (1 - e^2)
    denominator = 1 + e * cos(deg2rad(Ls_deg) - phi)
    
    return numerator / denominator
end

# convert_str2Float64 = x-> parse(Float64,x)
"""
    color_mapping(vars, color_range; scaler=nothing) -> Array{Int}

把连续数值场**线性量化**为 `1–256` 的整数索引，用于自定义色标查找表（colormap LUT）或
逐点着色的散点/等值线渲染。

# 功能与算法概述
把数值线性（或按 `log10`）归一化后量化为 `1–256` 的整数 LUT 索引；`0`/`NaN` 统一替换为 `1e-20` 以兼容对数标度。

# 参数说明
- `vars`: 待映射的数值数组（任意维）。
- `color_range::Tuple` 或 `Vector`: 色标对应区间 `(vmin, vmax)`，与 `scaler` 同一量纲。
- `scaler`: `"log10"` 表示对数映射；其它值（含 `nothing`）表示线性映射。

# 返回值
- `Array{Int}`: 与 `vars` 同形状的整数索引数组，取值范围 `[1, 256]`。

# 备注
- 该函数**不返回颜色本身**，仅返回索引；由调用方用 `colors[idx]` 查表取色。
"""
function color_mapping(vars, color_range; scaler=nothing)
    vars_no_zero = copy(vars)
    vars_no_zero[vars_no_zero.==0] .= 1e-20
    vars_no_zero[isnan.(vars_no_zero)] .= 1e-20
    if scaler == "log10"
        color_range_in = log10.(color_range)
        vars_in = log10.(vars_no_zero)
    else
        color_range_in = color_range
        vars_in = vars_no_zero
    end
    vars_mapped = round.(Int, ((vars_in .- color_range_in[1]) ./ (color_range_in[2] - color_range_in[1])) .* 255 .+ 1)
    vars_mapped[vars_mapped.>256] .= 256
    vars_mapped[vars_mapped.<1] .= 1
    return vars_mapped
end

"""
    skipnan(x) -> Vector

移除数组中的 `NaN` 元素，返回仅含有限值的紧凑向量。

# 功能与算法概述
用 `.!isnan.(x)` 生成布尔掩码后索引，返回去除 `NaN` 的新数组（原数组不被修改）。

# 参数说明
- `x`: 一维数值数组。

# 返回值
- `Vector`: 不含 `NaN` 的新数组（长度 ≤ `length(x)`）。

# 注意事项
- 返回的是**新数组**，不修改入参；元素顺序保持不变，但原索引信息会丢失。
- 若要保留索引，请改用 `findall(!isnan, x)`。
"""
function skipnan(x) # 移除NaN的filter
    ind = .!isnan.(x)
    return x[ind]
end;

"""
    nozeros(x) -> Vector

**原地**把数组中的 `0` 替换为一个极小数 `1e-20`，用于规避对数/除法运算中的奇点。

# 功能与算法概述
定位 `iszero` 的元素并**原地**改写为 `1e-20`，使数据仍可用于对数/除法运算而不产生奇点。

# 参数说明
- `x`: 数值数组（需支持 `setindex!`，即非 `SVector` 等不可变容器）。

# 返回值
- `Vector`: 与入参**同一对象**（原地修改后返回）。

# 注意事项
- 函数名未带 `!` 但**会修改入参**，调用前请对需要保留的原始数据做 `copy`/`deepcopy`。
- 仅处理 `0`，不处理 `NaN` 或负值。
"""
function nozeros(x) # 消0点为1e-20
    x[iszero.(x)] .= 1e-20
    return x
end;

"""
    geomean(x; dims=1) -> AbstractArray

计算数组的**几何平均值** `exp(mean(log(x)))`，支持沿指定维度归约。

# 功能与算法概述
在对数域求均值再指数还原（`exp(mean(log(x)))`），支持沿 `dims` 归约；不对无效值做筛选。

# 参数说明
- `x`: 数值数组（所有参与归约的元素必须 **> 0**）。
- `dims`: 归约维度，默认 `1`。

# 返回值
- 与 `x` 在非归约维度上形状一致的几何平均值数组。

# 注意事项
- 与 `safe_log_mean` 不同，本函数**不筛选**无效值：含有 `0` 或负值会产生 `−Inf`/`NaN`。
- 几何平均适合量级跨度大的物理量（密度、通量），可抑制极端值影响。
"""
function geomean(x; dims=1) # 几何平均
    # local flag = x .== 0
    return exp.(mean(log.(x); dims=dims))
end;

"""
    find_range(x, xr) -> BitVector

生成布尔掩码，标记数值数组中落入闭区间 `xr` 的元素。

# 功能与算法概述
用两个比较结果按位与（`.&`）生成闭区间 `[xr[1], xr[2]]` 的布尔掩码。

# 参数说明
- `x`: 数值数组。
- `xr`: 长度为 2 的区间 `(下限, 上限)`。

# 返回值
- `BitVector`: 与 `x` 同形状的布尔掩码，`true` 表示该元素在区间内。

# 备注
- 可直接用于 `x[mask]` 提取子集，或与其它掩码做逻辑运算。
- 若 `xr[1] > xr[2]`，结果全为 `false`。
"""
function find_range(x,xr)
    ind = (x .>= xr[1]) .& (x .<= xr[2])
    return ind
end

"""
    find_time_range(x, time_range) -> UnitRange{Int}

把时间**区间**转换成时间数组 `x` 上的连续索引范围。

# 功能与算法概述
分别对区间两端调用 `find_time` 定位最接近的索引，再拼成可直接用于切片（如 `x[range]`）的 `UnitRange`。

# 参数说明
- `x`: 单调递增的时间数组（`DateTime`、`Float64` 等）。
- `time_range`: 长度为 2 的区间 `(起始时刻, 结束时刻)`。

# 返回值
- `UnitRange{Int}`: 覆盖该时间区间的索引范围（含两端）。

# 注意事项
- 若 `time_range[1]` 对应的索引大于 `time_range[2]` 对应的索引，返回**空范围**。
- 依赖 `x` 已排序，否则结果无意义。
"""
function find_time_range(x,time_range)
    xi = find_time(x,time_range[1]):find_time(x,time_range[2])
    return xi
end

"""
    get_normal_plane(vec) -> (SVector{3}, SVector{3})

由平面的**法向量**构造该平面的两个基向量（用于把三维切片投影到二维绘图平面）。

# 功能与算法概述
由平面方程 `a·x + b·y + c·z = 0` 反解出 `z = −(a·x + b·y)/c`，分别取 `(x,y) = (1,0)` 与 `(0,1)` 得到平面内两条线性无关的基向量。

# 参数说明
- `vec`: 长度为 3 的法向量 `(a, b, c)`，要求 `c ≠ 0`（即平面不垂直于 X-Y 平面）。

# 返回值
- `(v1, v2)`: 两个 `SVector{3}` 平面内基向量，两者线性无关，可张成该平面。

# 注意事项
- 当 `c == 0` 时发生除零，结果为 `±Inf`；调用方需保证法向量有非零 Z 分量。
- 返回的基向量**未归一化**，如需正交归一基请再做 Gram-Schmidt。
- 本函数当前在仓库内无调用者（保留供切片绘图扩展使用）。
"""
function get_normal_plane(vec)# 通过法向向量制作平面函数
    a,b,c = vec[1],vec[2],vec[3]
    local func_plane = (x,y) -> (a*x + b*y) / -c
    v1 = func_plane(1.0,0.0)
    v2 = func_plane(0.0,1.0)
    v1 = SVector(1.0, 0.0, v1)
    v2 = SVector(0.0, 1.0, v2)
    return v1,v2
end

"""
    get_angle(v1, v2) -> Real

计算两个三维向量之间的**夹角**，输出**角度制**，在极小夹角下仍具有极高数值精度。

# 功能与算法概述
使用双参数反正切 `atand(‖v1×v2‖, v1·v2)`，等价于 `atan(sinθ, cosθ)`，相比 `acos(dot/(n₁n₂))` **不损失小角度精度**，且无需预先归一化。

# 参数说明
- `v1`: 第一个三维向量（`AbstractVector`，含 `SVector{3}`）。
- `v2`: 第二个三维向量。

# 返回值
- `Real`: 夹角（**角度制**），理论范围 `[0°, 180°]`；退化为零向量时返回 `NaN`。

# 备注
- 对于高精度需求场景，本实现严格优于 `rad2deg(acos(clamp(dot/(n1*n2), -1, 1)))` 的经典写法。
"""
function get_angle(v1, v2)
    return atand(norm(cross(v1, v2)), dot(v1, v2))
end

"""
    bowshock(xshock::Real) -> Float32/Float64

    计算火星**弓激波（Bow Shock）**在指定 Sun-Mars 轴向坐标 `x` 处的圆柱辐射距离 `r`（单位：火星半径 \$R_M\$）。

    # 物理背景与模型
    根据 Edberg et al. (2008) 的统计二次曲线拟合模型，弓激波形状采用双曲线（\$\\epsilon = 1.05 > 1\$）表示：
    \$r(x) = \\sqrt{(\\epsilon^2 - 1)(x - x_F)^2 - 2\\epsilon L(x - x_F) + L^2}\$

    # 参数说明
    - `xshock`: 日火连线方向（MSE/MSO 坐标系 X 轴）的位置坐标，以火星半径 \$R_M\$ 为单位（火星中心为原点，指向太阳为正）。

    # 模型经验常数 (Edberg et al., 2008)
    - \$x_F = 0.55\\ R_M\$：焦点 X 轴坐标
    - \$\\epsilon = 1.05\$：双曲线离心率 (Eccentricity)
    - \$L = 2.10\\ R_M\$：半正焦弦参数 (Semi-latus rectum)
    - \$r_{SD} = 1.58\\ R_M\$：日下点距离 (Subsolar Distance)

    # 返回值
    - `r` (\$> 0\$): 弓激波距 Sun-Mars 线的圆柱半径 \$r = \\sqrt{y^2 + z^2}\$（\$R_M\$）。
    - `NaN32`: 当输入坐标超出双曲线有效物理区域（开方内部值为负数）时返回。

    # 参考文献
    - Edberg N J T, Lester M, Cowley S W H, et al., 2008. Statistical analysis of the location of the 
    Martian magnetic pileup boundary and bow shock and the influence of crustal magnetic fields [J]. 
    Journal of Geophysical Research: Space Physics, 113(A8): 2008JA013096.
"""
function bowshock(xshock) #Edberg N J T, Lester M, Cowley S W H, et al., 2008. Statistical analysis of the location of the  Martian magnetic pileup boundary and bow shock and the influence of crustal magnetic fields [J]. Journal of Geophysical Research: Space Physics, 113(A8): 2008JA013096.
    xF = 0.55 # R_Mars
    ϵ = 1.05
    L = 2.10 # R_Mars
    rSD = 1.58
    temp = (ϵ^2-1.0)*(xshock-xF)^2-2ϵ*L*(xshock-xF)+L^2
    if temp>=0 
        return sqrt(temp)
    else
        return NaN32
    end
end
"""
    magnetopause(xmp::Real) -> Float32/Float64

    计算火星**磁堆积边界（Magnetic Pileup Boundary, MPB / 感应磁层边界）**在指定 Sun-Mars 轴向坐标 `x` 处的圆柱辐射距离 `r`（单位：火星半径 \$R_M\$）。

    # 物理背景与模型
    根据 Edberg et al. (2008) 的统计二次曲线拟合模型，MPB 形状采用椭圆曲线（\$\\epsilon = 0.92 < 1\$）表示：
    \$r(x) = \\sqrt{(\\epsilon^2 - 1)(x - x_F)^2 - 2\\epsilon L(x - x_F) + L^2}\$

    # 参数说明
    - `xmp`: 日火连线方向（MSE/MSO 坐标系 X 轴）的位置坐标，以火星半径 \$R_M\$ 为单位（火星中心为原点，指向太阳为正）。

    # 模型经验常数 (Edberg et al., 2008)
    - \$x_F = 0.86\\ R_M\$：焦点 X 轴坐标
    - \$\\epsilon = 0.92\$：椭圆离心率 (Eccentricity)
    - \$L = 0.90\\ R_M\$：半正焦弦参数 (Semi-latus rectum)
    - \$r_{SD} = 1.33\\ R_M\$：日下点距离 (Subsolar Distance)

    # 返回值
    - `r` (\$> 0\$): 磁堆积边界距 Sun-Mars 线的圆柱半径 \$r = \\sqrt{y^2 + z^2}\$（\$R_M\$）。
    - `NaN32`: 当输入坐标超出椭圆有效边界（如过深的夜侧截断或开方内部值为负）时返回。

    # 参考文献
    - Edberg N J T, Lester M, Cowley S W H, et al., 2008. Statistical analysis of the location of the 
    Martian magnetic pileup boundary and bow shock and the influence of crustal magnetic fields [J]. 
    Journal of Geophysical Research: Space Physics, 113(A8): 2008JA013096.
"""
function magnetopause(xmp)#Edberg N J T, Lester M, Cowley S W H, et al., 2008. Statistical analysis of the location of the  Martian magnetic pileup boundary and bow shock and the influence of crustal magnetic fields [J]. Journal of Geophysical Research: Space Physics, 113(A8): 2008JA013096.
    rSD = 1.33
	xF = 0.86
	ϵ  = 0.92
	L  = 0.90
    temp = (ϵ^2-1.0)*(xmp-xF)^2-2ϵ*L*(xmp-xF)+L^2
    if temp>=0 
        return sqrt(temp)
    else
        return NaN32
    end
end

"""
    get_log_ticks(p_min, p_max; step=2) -> (Vector, Vector)

为**对数坐标轴**生成刻度位置与对应的富文本标签（如 `10ⁿ` 形式）。

# 功能与算法概述
按指数步长生成幂次序列 `p_min:step:p_max`，以指数值作为对数轴刻度位置，并用 Makie 富文本生成 `10ⁿ` 标签。

# 参数说明
- `p_min`: 指数下限（如 `-12` 表示 `1e-12`）。
- `p_max`: 指数上限（如 `0` 表示 `1`）。
- `step`: 指数步长，默认 `2`（即每隔两个数量级一个刻度）。

# 返回值
- `(tick_values, tick_labels)`: 刻度位置向量与等长的 Makie 富文本标签向量，可直接传给 `yticks`。

# 备注
- 依赖 Makie/Fugue 的富文本能力，主要用于 `MAVEN_plot` 等绘图模块。
"""
function get_log_ticks(p_min::Real, p_max::Real; step=2) # 获取对数轴的label对应
    powers = p_min:step:p_max
    tick_values = Float64.(powers)
    tick_labels = [rich("10", superscript(string(p))) for p in powers]
    return (tick_values, tick_labels)
end

"""
    solve_func(x, y0, func) -> Float64

用**二分法**求解方程 `func(x) − y0 = 0`，用于求弓激波/磁堆积边界曲面在给定圆柱半径处的
轴向坐标。

# 功能与算法概述
在给定区间上用**二分法**迭代求解 `func(x) = y0`，收敛容差固定为 `1e-6`；端点同号时直接返回 `NaN64`。

# 参数说明
- `x`: 长度为 2 的搜索区间 `[x0, x1]`，要求 `func` 在端点异号。
- `y0`: 目标函数值（如弓激波在该处的圆柱半径）。
- `func`: 单参数函数（如 `bowshock`、`magnetopause`）。

# 返回值
- `Float64`: 方程 `func(x) = y0` 的根。
- `NaN64`: 当区间端点同号（区间内可能无根）时返回。

# 注意事项
- 收敛容差固定为 `1e-6`（绝对量），对于 `R_Mars` 量级坐标约合 `3.4 m` 分辨率。
- 仅在区间内函数单调且变号时结果可靠；多根情形下只返回其中一个。
"""
function solve_func(x,y0,func) # 二分法解方程
    # x = [x0,x1]
    # func = bowshock
    x0 = x[1]
    x1 = x[2]
    f0 = func(x0) - y0
    f1 = func(x1) - y0
    if f0*f1 > 0
        return NaN64
    end
    while abs(x1-x0) > 1e-6
        xmid = (x0+x1)/2.0
        fmid = func(xmid) - y0
        if fmid*f0 < 0
            x1 = xmid
            f1 = fmid
        else
            x0 = xmid
            f0 = fmid
        end
    end
    return (x0+x1)/2.0
end

"""
    get_bowshock_normal(p0, v_sw) -> Vector{Float64}

由给定位置与太阳风速度，计算**弓激波曲面上的局部法向反射速度**（常用于拾取离子/激波相互作用分析）。

# 功能与算法概述
在弓激波曲面上沿 `y`、`z` 方向做微小偏移（`0.01 R_Mars`），用 `solve_func` 反解轴向坐标得到三邻点，叉积求单位法向（统一指向日侧）后对太阳风速度做镜面反射。

# 参数说明
- `p0`: 航天器/观测点在 MSO 系中的位置（**km**）。
- `v_sw`: 太阳风速度矢量（与 `p0` 同坐标系，通常为 km/s）。

# 返回值
- `Vector{Float64}`: 反射速度矢量，与 `v_sw` 同量纲。

# 注意事项
- 采样步长固定为 `0.01 R_Mars`，过小的步长会放大数值噪声，过大则引入几何偏差。
- 若 `solve_func` 在偏移点处返回 `NaN64`（区间内无根），法向结果将失效。
- 依赖 `bowshock` 模型（Edberg et al., 2008），仅适用于火星弓激波。
"""
function get_bowshock_normal(p0,v_sw)
    #输入坐标返回bowshock的反射矢量
    x,y,z = p0[1]/constants.R_Mars,p0[2]/constants.R_Mars,p0[3]/constants.R_Mars
    x0 = solve_func([-2,1.57],sqrt(y^2+z^2),bowshock)
    x1 = solve_func([-2,1.57],sqrt((y+0.01)^2+z^2),bowshock)
    x2 = solve_func([-2,1.57],sqrt((z-0.01)^2+y^2),bowshock)

    v1 = [x1,y+0.01,z] .- [x0,y,z]
    v2 = [x2,y,z-0.01] .- [x0,y,z]

    #通过两个平面向量返回法向向量
    v3 = cross(v1,v2)
    v3 .*= sign(v3[1])
    v3 = normalize(v3)

    v0 = v_sw
    # v0相对于法向的反射方向
    v_reflect = v0 .- 2 .* dot(v0,v3) .* v3
    return v_reflect
end