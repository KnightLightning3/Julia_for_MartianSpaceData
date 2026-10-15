# ============================================================================
# Mars_Environment.jl —— 火星空间环境与边界模型（权威文件，迁入中）
#
# 本文件是上图/计算中「火星环境几何」函数的**唯一权威落点**：日火距离、
# 弓激波（Bow Shock）与磁堆积边界（MPB）的反解与法向反射。
#
# 迁入来源（逐函数机械复制，签名/默认值/表达式/docstring 均保持原样）：
#   common/head.jl                    mars_sun_dist_phys, bowshock, magnetopause,
#                                     get_bowshock_normal
#   common/function_coordinate.jl     bowshock_zero
#   calculate/calculate_models.jl     escape_energy
# 逐函数来源与状态见 validation/migrations/environment.toml；源文件删除与调用点
# 更新由最终移除任务完成（本文件迁入时 status 保持 pending）。
#
# 依赖：constants（物理常量）、MarsCommon（父模块公共能力）、StaticArrays（SVector）
# 与 LinearAlgebra（cross/dot/normalize）。父已有则复用，否则自包含 include。
# 本模块**无状态**：不写全局可变状态，不产生副作用文件。
# ============================================================================

# 公开规范模块名 = `MarsEnvironment`（registry 键 :MarsEnvironment，kind=:preloaded）。
# 文件路径沿用 models/Mars_Environment.jl（含下划线）；文件名与模块名不同属刻意安排：
# 本模块只保留这一个公开名，不为旧写法新增第二个兼容模块名（避免把路径写法变成重复公开 API）。
module MarsEnvironment

using LinearAlgebra
using StaticArrays

# G-include 护栏（Captain 2026-10-15）：优先复用**宿主（父模块）**已有的 constants /
# MarsCommon 实例；仅当父模块没有（即独立 include 本文件）时才自包含装入，以此保证
# 「环境侧与宿主共用同一权威实例」，不会在 include 宿主内再造第二份实例。
if isdefined(parentmodule(@__MODULE__), :constants)
    const constants = parentmodule(@__MODULE__).constants
else
    include(joinpath(@__DIR__, "..", "common", "constants.jl"))
end
using .constants

if isdefined(parentmodule(@__MODULE__), :MarsCommon)
    const MarsCommon = parentmodule(@__MODULE__).MarsCommon
else
    include(joinpath(@__DIR__, "..", "common", "MarsCommon.jl"))
end
# solve_func 一律复用 MarsCommon 的权威实现（common/marscommon/numerics.jl），
# 本模块不再持有副本。MarsCommon 未 export 该名，故用限定相对导入显式引入；
# 两条 include 路径（父已提供 / 本模块自包含）下 `MarsCommon` 绑定都先于此语句建立。
using .MarsCommon: solve_func

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
    bowshock_zero(xshock) -> Float64

求解火星**弓激波曲面**在给定 Sun-Mars 轴向坐标处的圆柱半径，并把"曲面外"的输入钳制为 `0.0`。

# 功能与算法概述
与 `head.bowshock` 同用 Edberg et al. (2008) 的二次曲线模型，但把无定义的输入区域**钳制为 `0.0`**，以便外层做数值迭代/求根。

# 参数说明
- `xshock`: 日火连线方向（通常为 MSO/MSE 的 X 轴）坐标，单位 **火星半径 `R_Mars`**。

# 返回值
- `Float64`: 弓激波圆柱半径 `√(y²+z²)`（单位 `R_Mars`）；
- `0.0`: 当该 `x` 处曲面无定义（`temp < 0`）时返回。

# 参考文献
- Edberg N J T, Lester M, Cowley S W H, et al., 2008. *Statistical analysis of the location of the
  Martian magnetic pileup boundary and bow shock and the influence of crustal magnetic fields* [J].
  Journal of Geophysical Research: Space Physics, 113(A8).
"""
function bowshock_zero(xshock)
    xF = 0.55 # R_Mars
    ϵ = 1.05
    L = 2.10 # R_Mars
    rSD = 1.58
    temp = (ϵ^2-1.0)*(xshock-xF)^2-2ϵ*L*(xshock-xF)+L^2
    if temp>=0 
        return sqrt(temp)
    else
        return 0.0
    end
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

"""
    escape_energy(; nM=1, planet="Mars") -> Float64

计算指定行星表面逃逸所需的最小粒子能量。

# 功能与算法概述
按 `E = ½·m·v_esc²` 计算并换算为 eV；`planet="Mars"` 时取逃逸速度 5.027 km/s。

# 参数说明
- `nM`: 质量数（AMU），默认 1。
- `planet`: 行星名（当前仅支持 `"Mars"`）。

# 返回值
- `Float64`: 逃逸能量（eV）。

# 注意事项
- 若 `planet` 非 `"Mars"`，`v` 未定义会报错。
"""
function escape_energy(;nM=1,planet="Mars")
    mass = nM * constants.mp
    # G = 6.67430e-11
    if planet == "Mars"
        v = 5.027e3
    end
    # v2 = 2 * G * mass / R
    E = 0.5 * mass * v^2 / constants.eV
    return E
end

end
