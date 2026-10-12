"""带电粒子在给定电磁场中的轨道、旋转半径与 ODE 求解工具。"""

module Single_Particle_Orbit
include(joinpath(@__DIR__, "..", "common", "constants.jl"))
using LinearAlgebra
using Dates
using DifferentialEquations
using StaticArrays
export solve_orbit, cyclotron_radius, solve_orbit_ode

"""
    TimeFormat(time1, time2) -> String

把两个时间点之差格式化为 `MM:SS.mmm` 字符串，用于进度日志。

# 功能与算法概述
取时间差的毫秒数并逐级取模，格式化为零填充的 `MM:SS.mmm` 字符串；仅用于日志展示，不参与数值计算。

# 参数说明
- `time1`: 起始时刻（`DateTime`）。
- `time2`: 结束时刻（`DateTime`）。

# 返回值
- `String`: 形如 `"03:07.482"` 的耗时字符串。

# 注意事项
- 不对小时/天数做进位展开：超过 59 分钟时分钟字段会大于 2 位。
- 仅用于**展示**，不参与数值计算。
"""
function TimeFormat(time1, time2)
    elapsed_time_ms = Dates.value(time2 - time1)
    minutes = div(mod(elapsed_time_ms, 3600000), 60000)
    seconds = div(mod(elapsed_time_ms, 60000), 1000)
    milliseconds = mod(elapsed_time_ms, 1000)
    return "$(lpad(minutes, 2, '0')):$(lpad(seconds, 2, '0')).$(lpad(milliseconds, 3, '0'))"
end

# mq # 比荷
"""
    dvdt(v, E_in, B_in, mq) -> AbstractVector

计算带电粒子在电磁场中的**加速度** `dv/dt = mq·(E + v × B)`（洛伦兹力方程）。

# 功能与算法概述
非相对论洛伦兹力方程 `dv/dt = (q/m)(E + v × B)`，是 RK4 主循环与 ODE 右端函数调用的底层热函数。

# 参数说明
- `v`: 粒子速度向量（`AbstractVector`，含 `SVector{3}`；单位 m/s）。
- `E_in`: 电场强度向量（V/m，须与 `v` 同尺寸）。
- `B_in`: 磁感应强度向量（T）。
- `mq`: **比荷** `q/m`（C/kg，带符号；离子取正、电子取负）。

# 返回值
- 加速度向量 `dv/dt`（m/s²）；若输入为 `SVector` 则为栈上 `SVector{3}`，无堆分配。

# 性能
- 位于 `solve_orbit` 的 RK4 主循环中，每步被调用 4 次；
  配合 `SVector` 输入可实现**零堆分配**。

# 备注
- 本函数为**非相对论**形式；`solve_orbit` / `solve_orbit_ode` 均基于此式积分。
"""
function dvdt(v::AbstractVector, E_in::AbstractVector, B_in::AbstractVector, mq::Real)
    ans = mq * (E_in + cross3(v, B_in))
    return ans
end
"""
    cross3(a, b) -> SVector{3}

计算两个三维向量的**叉积** `a × b`，固定返回 `SVector{3}`。

# 功能与算法概述
按行列式公式分量展开，直接构造 `SVector{3}` 返回，全程栈分配。

# 参数说明
- `a`: 第一个三维向量（`AbstractVector`，含 `SVector{3}`）。
- `b`: 第二个三维向量。

# 返回值
- `SVector{3}`: 叉积向量 `a × b`（与 `a` 满足右手法则）。

# 性能
- 是 `dvdt` 的底层热函数；全程栈分配，适合在 RK4/ODE 循环中高频调用。

# 备注
- 未做输入长度检查；传入非 3 维向量会引发 `BoundsError`。
- 若需同时支持任意维度，可直接使用 `LinearAlgebra.cross`。
"""
function cross3(a::AbstractVector, b::AbstractVector)
    ans = SVector(
        a[2] *  b[3] - a[3] * b[2], 
         a[3] * b[1] - a[1] * b[3], 
         a[1] * b[2] - a[2] * b[1]
         )
    return ans
end
"""
    solve_orbit(v0, x0, E, B, t, dt; AMU=1, hide_progress=false, particle=:ion, stop_condition=nothing) -> Dict

用**定步长 RK4** 积分带电粒子在给定电磁场中的完整轨道，返回速度、位置、磁场与弧长等时间序列。

# 功能与算法概述
固定步长**四阶 Runge-Kutta（RK4）**积分：每步 4 次调用 `dvdt` 求斜率，再加权平均更新速度/位置并累加弧长；状态全程保持为 `SVector{3}` 以避免主循环堆分配。

# 参数说明
- `v0`: 初始速度向量（m/s，长度为 3 的 `AbstractVector`）。
- `x0`: 初始位置向量（与 `v0` 同坐标系，单位由 `E`/`B` 回调约定）。
- `E`: 电场函数 `x -> E(x)`，返回长度 3 的向量（V/m）。
- `B`: 磁场函数 `x -> B(x)`，返回长度 3 的向量（T）。
- `t`: 积分总时长（秒）。
- `dt`: 定步长（秒）。
- `AMU`: 离子质量数（仅 `particle = :ion` 时生效）。
- `hide_progress`: 是否屏蔽控制台进度输出。
- `particle`: `:ion` 或 `:electron`。
- `stop_condition`: 预留的停止条件参数（**当前未实现**，恒被忽略）。

# 返回值
- `Dict`: 键为 `:description`、`:vel`（`Nt×3`）、`:r`（`Nt`）、`:pos`（`Nt×3`）、`:mag`（`Nt×3`）、`:s`（`Nt`）、`:time`。

# 性能
- 初始化后 `v`、`x` 及全部 RK4 中间量为 `SVector{3,Float64}`，主循环**零堆分配**。
- 总开销由步数 `Nt = t/dt + 1` 与 `E`/`B` 回调的代价决定。

# 注意事项
- 使用**定步长**且**非相对论**方程，故 `dt` 需小于回旋周期的约 1/10 以保证能量守恒。
- 若 `particle` 既非 `:ion` 也非 `:electron`，`mq` 未定义，将直接报错。
"""
function solve_orbit(v0::AbstractVector, x0::AbstractVector, E, B, t, dt; AMU=1, hide_progress=false, particle=:ion, stop_condition = nothing) # mq: 反比荷
    if particle == :ion
        mq = constants.q2mp / AMU
    elseif particle == :electron
        mq = constants.q2me
    end
    # stop_condition = nothing # 目前不支持停止条件

    # Conditions = Dict(
    #     :pa_limit => 90,
    #     :r_limit => 200,
    # )
    # f_b = mq * 1.0 / (2.0 * π) # 此参数乘以磁场得到回旋频率
    local v = SVector{3,Float64}(v0)
    local x = SVector{3,Float64}(x0)
    s = 0.0
    time = 0:dt:t
    Nt = length(time)
    v_data = zeros(Nt, 3)
    x_data = zeros(Nt, 3)
    b_data = zeros(Nt, 3)
    s_data = zeros(Nt)
    r_data = zeros(Nt)
    t_data = time

    v_data[1, :] = v
    x_data[1, :] = x
    s_data[1] = s
    r_data[1] = norm(x)
    b_data[1, :] = B(x)

    if !hide_progress
        global time01 = Dates.now()
        print("\033[42mStart Tarcing\033[0m at (\033[33m$time01\033[0m) Step = \033[36m $dt\033[0m\r")
    end

    @inbounds for i in 2:Nt
        local b0 = B(x)

        # b_total = norm(b0)
        # fc = f_b * b_total # 回旋频率
        # dt = 

        local k1v = dvdt(v, E(x), b0, mq)
        local k1x = v

        local kv1 = 0.5 * dt * k1v
        local kx1 = 0.5 * dt * k1x
        local B_1 = B(x + kx1)
        local E_1 = E(x + kx1)
        local k2v = dvdt(v + kv1, E_1, B_1, mq)
        local k2x = v + kv1

        local kv2 = 0.5 * dt * k2v
        local kx2 = 0.5 * dt * k2x
        local B_2 = B(x + kx2)
        local E_2 = E(x + kx2)
        local k3v = dvdt(v + kv2, E_2, B_2, mq)
        local k3x = v + kv2

        local kv3 = dt * k3v
        local kx3 = dt * k3x
        local B_3 = B(x + kx3)
        local E_3 = E(x + kx3)
        local k4v = dvdt(v + kv3, E_3, B_3, mq)
        local k4x = v + kv3

        v += dt / 6 * (k1v + 2.0 * k2v + 2.0 * k3v + k4v)
        x += dt / 6 * (k1x + 2.0 * k2x + 2.0 * k3x + k4x)
        s += norm(dt / 6 * (k1x + 2.0 * k2x + 2.0 * k3x + k4x))

        v_data[i, :] = v
        x_data[i, :] = x
        s_data[i] = s
        b_data[i, :] = b0
        r_data[i] = norm(x)
    end

    # fliter_index =  r_data .>= r_range[1] .&& r_data .<= r_range[2]
    # if false in fliter_index
    #     v_data = v_data[fliter_index,:]
    #     x_data = x_data[fliter_index,:]
    #     s_data = s_data[fliter_index]
    #     b_data = b_data[fliter_index,:]
    #     t_data = t_data[fliter_index]
    #     r_data = r_data[fliter_index]
    # end
    if !hide_progress
        time02 = Dates.now()
        total_time = TimeFormat(time01, time02)
        println("\033[42mEnd Tarcing\033[0m at (\033[33m$time02\033[0m) Step = \033[36m $dt\033[0m, Total_Time = \033[36m$total_time\033[0m")
    end

    return_data = Dict(
        :description => "velocity,position,B_field,distance",
        :vel => v_data,
        :r => r_data,
        :pos => x_data,
        :mag => b_data,
        :s => s_data,
        :time => t_data
    )
    return return_data
end
"""
    solve_orbit_ode(v0, x0, E, B, tspan, dt; AMU=1, particle=:ion, hide_progress=false) -> Dict

用 **DifferentialEquations.jl 的自适应求解器（Tsit5）**求解粒子轨道，适合需要高精度或变步长的场景。

# 功能与算法概述
将运动方程写成状态空间一阶 ODE（`u = [x; v]`），交由 `DifferentialEquations.jl` 的**自适应步长** `Tsit5` 求解，适合需要高精度或变步长的场景。

# 参数说明
- `v0`: 初始速度向量（m/s）。
- `x0`: 初始位置向量。
- `E`: 电场函数 `x -> E(x)`（V/m）。
- `B`: 磁场函数 `x -> B(x)`（T）。
- `tspan`: 积分时间区间 `(t0, t1)`（秒）。
- `dt`: 传给求解器的步长建议值（自适应算法中作为最大步长约束）。
- `AMU`: 离子质量数。
- `particle`: `:ion` 或 `:electron`。
- `hide_progress`: 是否屏蔽控制台进度输出。

# 返回值
- `Dict`: 键为 `:description`、`:vel`、`:pos`、`:time`、`:r`、`:mag`。

# 性能
- 自适应步长在平缓区可取大步长，在回旋密集区自动细化，**总步数通常少于定步长 RK4**。
- 代价：`DUAL` 类型与内部切片（`u[1:3]`）会带来分配，不适合对分配敏感的批量追踪。

# 注意事项
- 与 `solve_orbit` 的输出键不完全一致（无 `:s` 弧长）。
- **相对论效应未包含**，仅适用于非相对论能量区间。
"""
function solve_orbit_ode(v0::AbstractVector, x0::AbstractVector, E, B, tspan, dt; AMU=1, particle=:ion,hide_progress=false)
    if particle == :ion
        mq = constants.q2mp / AMU
    elseif particle == :electron
        mq = constants.q2me
    end

    """
        ODE!(du, u, p, t) -> Nothing

    `solve_orbit_ode` 的**ODE 右侧函数**，把电磁场运动方程写成 `du/dt = f(u)` 形式。

    # 功能与算法概述
    把状态 `[x; v]` 映射为导数 `[v; dvdt(v, E(x), B(x), mq)]`，满足 `DifferentialEquations.jl` 的原地右端函数接口。

    # 参数说明
    - `du`: 导数输出向量（原地写入，长度 6）。
    - `u`: 状态向量 `[x; v]`（长度 6）。
    - `p`: 参数（**本实现未使用**）。
    - `t`: 当前时间（**本实现未使用**，仅满足接口签名）。

    # 返回值
    - `Nothing`: 结果通过原地写入 `du` 返回。

    # 备注
    - 内层函数闭包捕获了外层 `E`、`B` 与 `mq`。
    """
    function ODE!(du, u, p, t)
        x = u[1:3]
        v = u[4:6]
        du[1:3] = v
        du[4:6] = dvdt(v, E(x), B(x), mq)
    end

    if !hide_progress
        global time01 = Dates.now()
        print("\033[42mStart Tarcing\033[0m at (\033[33m$time01\033[0m) Step = \033[36m $dt\033[0m\r")
    end

    u0 = vcat(x0, v0)
    prob = ODEProblem(ODE!, u0, tspan)
    sol = solve(prob, Tsit5(); dt=dt)
    Nt = length(sol.t)
    x_data = sol[1:3, :]'
    v_data = sol[4:6, :]'
    t_data = sol.t

    b_data = zeros(Nt, 3)
    r_data = zeros(Nt)

    for i in eachindex(t_data)
        x = x_data[i, :]
        b_data[i,:] = B(x)
        r_data[i] = norm(x)
    end
    if !hide_progress
        time02 = Dates.now()
        total_time = TimeFormat(time01, time02)
        println("\033[42mEnd Tarcing\033[0m at (\033[33m$time02\033[0m) Step = \033[36m $dt\033[0m, Total_Time = \033[36m$total_time\033[0m")
    end

    return_data = Dict(
        :description => "velocity,position,time",
        :vel => v_data,
        :pos => x_data,
        :time => t_data,
        :r => r_data,
        :mag => b_data,
    )
    return return_data
end
"""
    cyclotron_radius(B_in, v; nM=1, nQ=-1) -> (f, rc, v)

由磁场强度与速度计算粒子的**回旋频率**、**回旋半径**，并回传速度。

# 功能与算法概述
非相对论回旋运动公式：由 `cc = m/(|q|B)` 得回旋频率 `f = 1/(2πcc)` 与回旋半径 `rc = cc·v`。

# 参数说明
- `B_in`: 磁场强度（**T**，SI 单位）。
- `v`: 粒子速度（**m/s**）。
- `nM`: 离子质量数（仅 `nQ ≠ -1` 时生效）。
- `nQ`: 电荷数；`-1` 表示电子，其它正值表示离子。

# 返回值
- `(f, rc, v)`: 回旋频率（Hz）、回旋半径（m）、原样回传的速度。

# 注意事项
- 输入须为 SI 单位；若 `B` 以 nT 给出需先乘 `1e-9`。
- **非相对论**公式；高能粒子需引入 `γ` 修正。
- 返回第三个元素 `v` 仅为方便链式调用。
"""
function cyclotron_radius(B_in::Real,v::Real;nM=1,nQ=-1) # 国际单位
    B1=B_in  # 输入T
    if nQ == -1
        cc = constants.me /(B1*constants.e)
    else
        cc = constants.mp*nM/(B1*constants.e*nQ)
    end
    # γ=(energy * 1e-3 /E0 + 1)
    # β=sqrt(1.0 - 1.0 / γ^2)
    # V=β * C
    f = 1  / (cc *2*π)
    rc = cc * v
    return f,rc,v
end
"""
    ion_alvfen(n, B; amu=1) -> Real

由数密度与磁场强度计算** Alfvén 速度**。

# 功能与算法概述
理想 MHD 关系 `v_A = B/√(μ₀ρ)`，其中质量密度由数密度与离子质量数给出。

# 参数说明
- `n`: 离子数密度（**m⁻³**）。
- `B`: 磁场强度（**T**）。
- `amu`: 离子质量数（AMU），默认 1（质子）。

# 返回值
- Alfvén 速度（**m/s**）。

# 注意事项
- 函数名中的 `alvfen` 为 `alfven` 的拼写笔误，为保证向后兼容沿用原名。
- 输入须为 SI 单位；专用于**离子**惯性尺度。
"""
function ion_alvfen(n::Real,B::Real;amu=1) # 阿尔文速度,输入T,m-3,输出m/s

    ρ = n * amu * constants.mp
    vA = B / sqrt(constants.μ0 * ρ)
    return vA
end
# 定义电场和磁场函数
E(x::AbstractVector) = SVector(0.0, 0.0, 0.0)  # 假设电场沿x轴方向
B(x::AbstractVector) = SVector(0.0, 0.0, 0.0)  # 假设磁场沿z轴方向
end

# # # 测试
# using .Single_Particle_Orbit
# using GLMakie
# EnvironmentPath = "D:/CODE/Package_for_Julia/"
# include(EnvironmentPath*"Magnetic_Model/IGRF_calculate.jl")
# import .IGRF_calculate;

# v0 = [18.00650385330508,-12.447101833421216,-12.513798039815253] .* 1e3 .*(-1)
# x0 = [-2278.430908203125,-126.21499633789062,-2851.4990234375] .*1e3
# dt = 0.001
# t = 10
# function B_field(x) 
#     BB = IGRF_calculate.IGRF_pc(x[1]/1e3,x[2]/1e3,x[3]/1e3).*1e-9
#     return [BB[1],BB[2],BB[3]] # 返回磁场值，单位nT
# end
# data_1 = Single_Particle_Orbit.solve_orbit(v0, x0, Single_Particle_Orbit.E, B_field, t, dt;)
# data_2 = Single_Particle_Orbit.solve_orbit_ode(v0, x0, Single_Particle_Orbit.E, B_field, t, dt;)

# fig = Figure()
# ax = Axis3(fig[1, 1])
# x = data_1[:pos]
# x2 = data_2[:pos]
# lines!(ax, x[:, 1]./1e3./constants.R_Mars, x[:, 2]./1e3./constants.R_Mars, x[:, 3]./1e3./constants.R_Mars, color = :blue)
# lines!(ax, x2[:, 1]./1e3./constants.R_Mars, x2[:, 2]./1e3./constants.R_Mars, x2[:, 3]./1e3./constants.R_Mars, color = :red)
# fig
