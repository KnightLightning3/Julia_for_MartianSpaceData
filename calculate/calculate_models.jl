module calculate_models
using Quaternions

function Matrix_Rot(in_data,Rotation_Matrix)
    #使用旋转矩阵计算坐标系变换。逆变换时输入矩阵的inv()逆即可
    out_data = Rotation_Matrix * in_data
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
function Doppler_Shift(f,V_sc,k,θ) # wave frequency shift with spacecraft velocity
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
function Linear_fit(x::AbstractVector, y::AbstractVector)
    # 确保输入数据长度一致
    if length(x) != length(y)
        error("输入向量 x 和 y 的长度必须一致。")
    end
    
    n = length(x)
    if n < 2
        error("至少需要两个数据点进行线性拟合。")
    end

    # --- 1. 计算必要的统计量 (使用高效的求和) ---
    
    # 均值
    x_mean = sum(x) / n
    y_mean = sum(y) / n
    
    # 协方差的分子 (S_xy) 和 x 的方差的分子 (S_xx)
    S_xy = 0.0
    S_xx = 0.0
    
    # 循环一次计算所有差值的乘积和平方和
    for i in 1:n
        x_diff = x[i] - x_mean
        y_diff = y[i] - y_mean
        
        S_xy += x_diff * y_diff # ∑(xᵢ - x̄)(yᵢ - ȳ)
        S_xx += x_diff * x_diff # ∑(xᵢ - x̄)²
    end

    # --- 2. 计算斜率 (P₂) 和截距 (P₁) ---

    if S_xx ≈ 0.0
        # 如果 S_xx 接近于零，意味着所有 x 值都相同
        error("所有 x 值都相同 (S_xx ≈ 0)。无法计算唯一的斜率。")
    end

    # 斜率 (Slope): P₂
    P2 = S_xy / S_xx
    
    # 截距 (Intercept): P₁ (利用通过均值点 (x̄, ȳ) 的特性)
    P1 = y_mean - P2 * x_mean

    # --- 3. 计算拟合优度 (可选但推荐) ---
    
    # 总平方和 (SST) - y 的总变异性
    SST = sum((y .- y_mean).^2)
    
    # 残差平方和 (SSR)
    Y_predicted = P1 .+ P2 .* x
    SSR = sum((y .- Y_predicted).^2)
    
    # 决定系数 (R²)
    r_squared = (SST > eps()) ? (1.0 - (SSR / SST)) : 1.0

    # --- 4. 返回结果 ---
    return (
        P1 = P1, # 截距
        P2 = P2, # 斜率
        r_squared = r_squared, # 拟合优度
        # 返回拟合函数本身，方便后续计算预测值
        fit_function = new_x -> P1 .+ P2 .* new_x
    )
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