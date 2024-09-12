module Single_Particle_Orbit
using LinearAlgebra
using Dates

function TimeFormat(time1, time2)
    elapsed_time_ms = Dates.value(time2 - time1)
    minutes = div(mod(elapsed_time_ms, 3600000), 60000)
    seconds = div(mod(elapsed_time_ms, 60000), 1000)
    milliseconds = mod(elapsed_time_ms, 1000)
    return "$(lpad(minutes, 2, '0')):$(lpad(seconds, 2, '0')).$(lpad(milliseconds, 3, '0'))"
end

const e = 1.6e-19
const me = 9.1093837e-31
const mp = 1.67262192e-27
const q2me = -e / me
const q2mp = e / mp

# mq # 比荷
function dvdt(v::Vector{Float64}, E_in::Vector{Float64}, B_in::Vector{Float64}, mq::Float64)
    ans = mq * (E_in + cross3(v, B_in))
    return ans
end
function cross3(a::Vector{Float64}, b::Vector{Float64})
    ans = [a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]]
    return ans
end
function solve_orbit(v0::Vector{Float64}, x0::Vector{Float64}, E, B, t, dt; AMU=1, hidde_progress=false, r_range=[0.0, 1e10], particle="ion") # mq: 反比荷
    if particle == "ion"
        mq = q2mp / AMU
    elseif particle == "electron"
        mq = q2me
    end

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

    if !hidde_progress
        global time01 = Dates.now()
        println("\033[42mStart Tarcing\033[0m at (\033[33m$time01\033[0m) Step = \033[36m $dt\033[0m")
    end

    @inbounds for i in 2:Nt
        b0 = B(x)

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

        kv = 0.5 * dt * k3v
        kx = 0.5 * dt * k3x
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
    if !hidde_progress
        time02 = Dates.now()
        total_time = TimeFormat(time01, time02)
        println("\033[42mEnd Tarcing\033[0m at (\033[33m$time02\033[0m) Step = \033[36m $dt\033[0m, Total_Time = \033[36m$total_time\033[0m")
    end

    return_data = Dict(
        "discription" => "velocity,position,B_field,distence",
        "vel" => v_data,
        "r" => r_data,
        "pos" => x_data,
        "mag" => b_data,
        "s" => s_data,
        "time" => t_data
    )
    return return_data
end

# 定义电场和磁场函数
E(x::Vector{Float64}) = [0.0, 0.0, 0.0]  # 假设电场沿x轴方向
B(x::Vector{Float64}) = [0.0, 0.0, 0.0]  # 假设磁场沿z轴方向
end

# # 测试
# using .Single_Particle_Orbit
# using GLMakie
# EnvironmentPath = "D:/CODE/Package_for_Julia/"
# include(EnvironmentPath*"Megnetic_Model/IGRF_carculate.jl")
# import .IGRF_carculate;

# v0 = [18.00650385330508,-12.447101833421216,-12.513798039815253] .* 1e3 .*(-1)
# x0 = [-2278.430908203125,-126.21499633789062,-2851.4990234375] .*1e3
# dt = 0.1
# t = 0:dt:10
# function B_field(x) 
#     BB = IGRF_carculate.IGRF_pc(x[1]/1e3,x[2]/1e3,x[3]/1e3).*1e-9
#     return [BB[1],BB[2],BB[3]] # 返回磁场值，单位nT
# end
# _,_,x = Single_Particle_Orbit.solve_orbit(v0, x0, Single_Particle_Orbit.E, B_field, t, dt,mq=Single_Particle_Orbit.q2mp/16.0)

# fig = Figure()
# ax = Axis3(fig[1, 1])
# lines!(ax, x[:, 1]./1e3./3393.5, x[:, 2]./1e3./3393.5, x[:, 3]./1e3./3393.5, color = :blue)
# fig
