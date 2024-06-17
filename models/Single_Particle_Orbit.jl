module Single_Particle_Orbit
using LinearAlgebra
using ProgressMeter

const e = 1.6e-19
const me = 9.1093837e-31
const mp = 1.67262192e-27
const q2me = -e/me
const q2mp = e/mp

# mq # 比荷
function dvdt(v,E,B,mq)
    return mq * (E + cross(v, B))
end

function solve_orbit(v0, x0, E, B, t, dt;mq=q2me)
    v = v0
    x = x0
    s = 0.0
    Nt = length(t)
    v_data = zeros(Nt,3)
    x_data = zeros(Nt,3)
    b_data = zeros(Nt,3)
    s_data = zeros(Nt)
    t_data = t
    @showprogress dt=1 desc="carcu_orbit" for i in 1:Nt-1
        b0 = B(x)
        
        k1v = dvdt(v, E(x), b0,mq);                k1x = v
        
        kv = 0.5*dt*k1v; kx = 0.5*dt*k1x
        k2v = dvdt(v + kv, E(x + kx), B(x + kx),mq); k2x = v + kv
        
        kv = 0.5*dt*k2v; kx = 0.5*dt*k2x
        k3v = dvdt(v + kv, E(x + kx), B(x + kx),mq); k3x = v + kv
        
        kv = 0.5*dt*k3v; kx = 0.5*dt*k3x
        k4v = dvdt(v + kv, E(x + kx), B(x + kx),mq); k4x = v + kv

        v_data[i,:] = v
        x_data[i,:] = x
        s_data[i]   = s
        b_data[i,:] = b0

        v = v + dt/6 * (k1v + 2.0*k2v + 2.0*k3v + k4v)
        x = x + dt/6 * (k1x + 2.0*k2x + 2.0*k3x + k4x)
        s = s + norm(dt/6 * (k1x + 2.0*k2x + 2.0*k3x + k4x))
    end
        v_data[Nt,:] = v
        x_data[Nt,:] = x
        s_data[Nt]   = s
        b_data[Nt,:] = B(x)
    return_data = Dict(
        "discription"   => "velocity,position,B_field,distence",
        "vel"           => v_data,
        "pos"           => x_data,
        "mag"           => b_data,
        "s"             => s_data,
        "time"          => t_data
    )
    return return_data
end

# 定义电场和磁场函数
E(x) = [0.0, 0.0, 0.0]  # 假设电场沿x轴方向
B(x) = [0.0, 0.0, 0.0]  # 假设磁场沿z轴方向
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
