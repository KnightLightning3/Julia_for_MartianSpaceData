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

#默认参数
const e    = 1.602176634E-19
const m_e   = 9.1093837e-31
const mp   = 1.67262192e-27
const μ0   = 4e-7 * π
const q2me = -e / m_e
const q2mp = e / m_p
const RAD  = 1.0 / 180 * π
const eV   = 1.602176487e-19
const c    = 3e8
const EV   = 1.602176487e-19
const C    = 3.0e8
const Me   = 9.109e-31
const Mp   = 1.67262192369e-27
const RADG = 180.0/π
const R_Mars = 3393.5
const inv_R_Mars = 1.0/ R_Mars
const G = 6.67430e-11
const k_B = 1.380649E-23
const M_Mars = 6.4169e23

Package_path = "D:/CODE/Package_for_Julia/"
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
# find_time = (x, x0) -> findmin(abs.(x .- x0))[2];
```
寻找被排序过的时间中最接近目标值的一项,
x: 单调递增的数据
x0: 查找目标的数据
```
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

function ion_v2energy(v; m_int=1) # 离子子能量对应速度(相对论) v:速度, IS单位制
    E0 = 938313.53 * m_int
    β  = v / 3e8
    γ = 1.0 / sqrt(1.0 - β^2)
    energy = (γ - 1.0) * E0 * 1e3
    return energy
end
function ion_energy2v(energy; m_int=1) # 离子子能量对应速度(相对论),输入eV, IS单位制
    local E0 = 938313.53 * m_int  # 质子静止能量 MeV
    local γ= energy*1e-3/E0 + 1.0
    local β=sqrt(1.0 - 1.0 / γ^2)
    return β * 3e8
end
    
# convert_str2Float64 = x-> parse(Float64,x)
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

function skipnan(x) # 移除NaN的filter
    ind = .!isnan.(x)
    return x[ind]
end;

function nozeros(x) # 消0点为1e-20
    x[iszero.(x)] .= 1e-20
    return x
end;

function geomean(x; dims=1) # 几何平均
    # local flag = x .== 0
    return exp.(mean(log.(x); dims=dims))
end;

function find_range(x,xr)
    ind = (x .>= xr[1]) .& (x .<= xr[2])
    return ind
end

function find_time_range(x,time_range)
    xi = find_time(x,time_range[1]):find_time(x,time_range[2])
    return xi
end

function get_normal_plane(vec)# 通过法向向量制作平面函数
    a,b,c = vec[1],vec[2],vec[3]
    local func_plane = (x,y) -> (a*x + b*y) / -c
    v1 = func_plane(1.0,0.0)
    v2 = func_plane(0.0,1.0)
    v1 = [1,0,v1]
    v2 = [0,1,v2]
    return v1,v2
end

"""
    get_angle(v1, v2) -> Real

基于 atan2/atand 的 3D 向量夹角计算，在极小角度下具有极高的数值精度，输出角度制
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

function get_log_ticks(p_min::Real, p_max::Real; step=2) # 获取对数轴的label对应
    powers = p_min:step:p_max
    tick_values = Float64.(powers)
    tick_labels = [rich("10", superscript(string(p))) for p in powers]
    return (tick_values, tick_labels)
end

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

function get_bowshock_normal(p0,v_sw)
    #输入坐标返回bowshock的反射矢量
    x,y,z = p0[1]/3393.5,p0[2]/3393.5,p0[3]/3393.5
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