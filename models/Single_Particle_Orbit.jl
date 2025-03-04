module Single_Particle_Orbit
using LinearAlgebra
using Dates
using DifferentialEquations
export solve_orbit, cyclotron_radius, solve_orbit_ode

function TimeFormat(time1, time2)
    elapsed_time_ms = Dates.value(time2 - time1)
    minutes = div(mod(elapsed_time_ms, 3600000), 60000)
    seconds = div(mod(elapsed_time_ms, 60000), 1000)
    milliseconds = mod(elapsed_time_ms, 1000)
    return "$(lpad(minutes, 2, '0')):$(lpad(seconds, 2, '0')).$(lpad(milliseconds, 3, '0'))"
end

const e    = 1.6e-19
const me   = 9.1093837e-31
const mp   = 1.67262192e-27
const μ0   = 4e-7 * π
const q2me = -e / me
const q2mp = e / mp
# mq # 比荷
function dvdt(v::Vector{Float64}, E_in::Vector{Float64}, B_in::Vector{Float64}, mq::Float64)::Vector{Float64}
    ans = mq * (E_in + cross3(v, B_in))
    return ans
end
function cross3(a::Vector{Float64}, b::Vector{Float64})::Vector{Float64}
    ans = [
        a[2] *  b[3] - a[3] * b[2], 
         a[3] * b[1] - a[1] * b[3], 
         a[1] * b[2] - a[2] * b[1]
         ]
    return ans
end
function solve_orbit(v0::Vector{Float64}, x0::Vector{Float64}, E, B, t, dt; AMU=1, hide_progress=false, r_range=[0.0, 1e10], particle="ion") # mq: 反比荷
    if particle == "ion"
        mq = q2mp / AMU
    elseif particle == "electron"
        mq = q2me
    end
    # f_b = mq * 1.0 / (2.0 * π) # 此参数乘以磁场得到回旋频率
    v = v0
    x = x0
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
        b0 = B(x)

        # b_total = norm(b0)
        # fc = f_b * b_total # 回旋频率
        # dt = 

        k1v = dvdt(v, E(x), b0, mq)
        k1x = v

        kv = 0.5 * dt * k1v
        kx = 0.5 * dt * k1x
        B_in = B(x + kx)
        E_in = E(x + kx)
        k2v = dvdt(v + kv, E_in, B_in, mq)
        k2x = v + kv

        kv = 0.5 * dt * k2v
        kx = 0.5 * dt * k2x
        B_in = B(x + kx)
        E_in = E(x + kx)
        k3v = dvdt(v + kv, E_in, B_in, mq)
        k3x = v + kv

        kv = dt * k3v
        kx = dt * k3x
        B_in = B(x + kx)
        E_in = E(x + kx)
        k4v = dvdt(v + kv, E_in, B_in, mq)
        k4x = v + kv

        v = v + dt / 6 * (k1v + 2.0 * k2v + 2.0 * k3v + k4v)
        x = x + dt / 6 * (k1x + 2.0 * k2x + 2.0 * k3x + k4x)
        s = s + norm(dt / 6 * (k1x + 2.0 * k2x + 2.0 * k3x + k4x))

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
function solve_orbit_ode(v0::Vector{Float64}, x0::Vector{Float64}, E, B, tspan, dt; AMU=1, particle="ion",hide_progress=false)
    if particle == "ion"
        mq = q2mp / AMU
    elseif particle == "electron"
        mq = q2me
    end

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
function cyclotron_radius(B_in::Real,v::Real;nM=1,nQ=-1) # 国际单位
    B1=B_in  # 输入T
    if nQ == -1
        cc = me /(B1*e)
    else
        cc = mp*nM/(B1*e*nQ)
    end
    # γ=(energy * 1e-3 /E0 + 1)
    # β=sqrt(1.0 - 1.0 / γ^2)
    # V=β * C
    f = 1  / (cc *2*π)
    rc = cc * v
    return f,rc,v
end
function ion_energy2v(energy,AMU) # 离子子能量对应速度(相对论),输入eV, IS单位制
    E0 = 938313.53 * AMU  # 质子静止能量 MeV
    γ= energy*1e-3/E0 + 1.0
    β=sqrt(1.0 - 1.0 / γ^2)
    v = β * 3e8
    return v
end
function ion_v2energy(v,AMU) # 离子子能量对应速度(相对论) v:速度, IS单位制
    E0 = 938313.53 * AMU
    β  = v / 3e8
    γ = 1.0 / sqrt(1.0 - β^2)
    energy = (γ - 1.0) * E0 * 1e3
    return energy
end
function energy2v(energy) # 电子能量对应速度(相对论)
    E0 = 511.0
    γ = (energy * 1e-3 / E0 + 1)
    β = sqrt(1.0 - 1.0 / γ^2)
    v = β .* 3e8
    return v
end
function ion_alvfen(n::Real,B::Real;amu=1) # 阿尔文速度,输入T,m-3,输出m/s

    ρ = n *amu* 1.67262192e-27
    vA = B / sqrt( 4e-7 * π * ρ)
    return vA
end
# 定义电场和磁场函数
E(x::Vector{Float64}) = [0.0, 0.0, 0.0]  # 假设电场沿x轴方向
B(x::Vector{Float64}) = [0.0, 0.0, 0.0]  # 假设磁场沿z轴方向
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
# lines!(ax, x[:, 1]./1e3./3393.5, x[:, 2]./1e3./3393.5, x[:, 3]./1e3./3393.5, color = :blue)
# lines!(ax, x2[:, 1]./1e3./3393.5, x2[:, 2]./1e3./3393.5, x2[:, 3]./1e3./3393.5, color = :red)
# fig
