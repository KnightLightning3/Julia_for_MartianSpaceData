module calculate_models
using Quaternions
# using TimesDates, Dates
# using DataFrames
# using DelimitedFiles
# using JSON
# using Statistics
function Martrix_Rot(in_data,Rotation_Martrix)
    #使用旋转矩阵计算坐标系变换。逆变换时输入矩阵的inv()逆即可
    out_data = Rotation_Martrix * in_data
    return out_data
end
function rotation_matrix(θ, φ)
    # 创建绕z轴旋转φ的旋转矩阵
    Rz = [cos(φ) -sin(φ) 0;
          sin(φ)  cos(φ) 0;
          0       0      1]

    # 创建绕y轴旋转θ的旋转矩阵
    Ry = [cos(θ)  0  sin(θ);
          0       1  0;
         -sin(θ)  0  cos(θ)]

    # 计算总旋转矩阵，先绕y轴旋转，然后绕z轴旋转
    return Rz * Ry
end
function Quaternion_Rot(u::AbstractVector,q::QuaternionF64) # rotate_vector_with_quat
    #使用四元数计算坐标系变换。
    q_u = QuaternionF64(0, u[1], u[2], u[3])
    q_v = q*q_u*conj(q)
    return [imag_part(q_v)...]
end
function Quaternion_Rot_reverse(u::AbstractVector, q::QuaternionF64)
    local q_u = QuaternionF64(0, u[1], u[2], u[3])
    local q_v = conj(q) * q_u * q
    return [imag_part(q_v)...]
end
function eflux2F(energy,eflux)
    # 电子eflux2F
    M = me
    # E0=M*C^2/EV   #静止能量 eV
    #energy 与 eflux 一一对应
    # E0=M*C^2/EV
    γ=(energy * 1e-3 /E0 + 1)
    β=sqrt(1.0 - 1.0 / γ^2)
    P=γ *M * β *C        # kg m/s
    # V=β .* C
    F = (γ*M)^3 * eflux/energy *1e4 /EV / P^2
    return F
end
function Doppler_Shift(f,V_sc,k,θ) # wave frequence shift with spacecraft velocity
    # θ angle between SC and wave vector
    ω_obs = f * 2 * π
    ω_real = ω_obs - k * V_sc * cos(θ)
    return ω_real
end
function energy2v(energy;type="e",nM=1)
    if type == "e"
        E0 = 511.0
    elseif type == "ion"
        E0 = 511.0 * nM * 1836.23 
    end
    γ=(energy * 1e-3 /E0 + 1)
    β=sqrt(1.0 - 1.0 / γ^2)
    v = β .* 3e8
    return v
end
function escape_energy(;nM=1,planet="Mars")
    mass = nM * Mp
    # G = 6.67430e-11
    if planet == "Mars"
        v = 5.027e3
    end
    # v2 = 2 * G * mass / R
    E = 0.5 * mass * v^2 /EV
    return E
end
function cyclotron_radius(B,ek;nM=1,nQ=-1)
    B1=B*1e-9  # 输入nT，转T
    if nQ == -1
        cc = Me /(B1*Q)
        v = energy2v(ek)
    else
        cc = Mp*nM/(B1*Q*nQ)
        v = energy2v(ek;type="ion",nM=nM)
    end
    # γ=(energy * 1e-3 /E0 + 1)
    # β=sqrt(1.0 - 1.0 / γ^2)
    # V=β * C
    f = 1  / (cc *2*π)
    rc = cc * v
    return f,rc,v
end
function cyclotron_frequency(B;nM=1,nQ=-1)
    B1=B*1e-9  # 输入nT，转T
    if nQ == -1
        cc = Me /(B1*Q)
    else
        cc = Mp*nM/(B1*Q*nQ)
    end
    f = 1  / (cc *2*π)
    return f
end
const EV=1.602176487e-19
const C=3.0e8
const Me=9.109e-31
const Mp=1.67262192e-27
const Q = 1.602176634e-19
const M_to_Q_e = Me/Q
const M_to_Q_p = Mp/Q
end # module

# import .calculate_models

# freq,rc,v = calculate_models.cyclotron_radius(200.0,100;nM=32,nQ=1)
# println([freq,rc/1000,v/1000])
# freq,rc,v = calculate_models.cyclotron_radius(200.0,100;nQ=-1)
# println([freq,rc/1000,v/1000])