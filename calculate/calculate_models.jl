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
    return pc2ss_data
end
function Quaternion_Rot(u::AbstractVector,q::QuaternionF64)
    #使用四元数计算坐标系变换。
    q_u = QuaternionF64(0, u[1], u[2], u[3])
    q_v = q*q_u*conj(q)
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

const EV=1.602176487e-19
const C=3.0e8
const Me=9.109e-31

end # module