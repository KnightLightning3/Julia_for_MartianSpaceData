# 制作麦克斯韦分布的函数包

module Maxwellian_Distribution
# dir = dirname(dirname(@__FILE__))
# include(dir*"/models/constants.jl")
using LinearAlgebra
using Statistics
const e    = 1.6e-19
const me   = 9.1093837e-31
const mp   = 1.67262192e-27
const μ0   = 4e-7 * π
const q2me = -e / me
const q2mp = e / mp
const RAD=1.0 / 180 * π
const eV=1.602176487e-19
const c=3e8
const κ = 1.38064852e-23  # 玻尔兹曼常数


#----------速度模概率分布 单位: 1/unit.velocity------------
function velocity_distribution(v,T;m=mp)
    # 计算速度模分布函数 对数域
    # v: 速度
    # T: 温度 (开尔文)
    # m: 粒子质量 (kg)
    a1 = m / (2 * κ * T)
    fv = 4π * (a1 / π)^1.5 * v^2 * exp(-a1 * v^2)
    return fv
end
function fit_velocity_distribution(v, fv; fit_function=:Linear,m=mp)
    # 拟合计算速度分布函数 对数域, 默认粒子为质子
    Y = log.(fv ./ (v.^2))
    X = hcat(ones(length(v)), v.^2)
    P = (X' * X) \ (X' * Y)
    C_fit, neg_a1_fit = P
    a1_fit = -neg_a1_fit
    T_estimated = m / (2 * κ * a1_fit)

    # 估计温度
    # 确保 a1_fit 为正，否则无法计算有效温度
    T_estimated = (a1_fit > 0) ? (m / (2 * κ * a1_fit)) : NaN

    # --- 计算拟合优度指标 ---
    # 预测值 Y_predicted
    Y_predicted = X * P

    # 残差 (residuals)
    residuals = Y - Y_predicted

    # 残差平方和 (SSR)
    ssr = sum(abs2, residuals)

    # 总平方和 (SST) - 衡量因变量的总变异性
    # 如果 Y 是一个单元素的数组，var(Y) 会返回 NaN，因此需要特殊处理
    if length(Y) > 1
        sst = sum(abs2, Y .- mean(Y))
    else
        sst = 0.0 # 单个数据点没有变异性
    end


    # 决定系数 (R^2)
    # 如果 SST 接近零（所有 Y 值都相同），R^2 可能无意义或为 NaN/Inf
    r_squared = (sst > eps()) ? (1 - (ssr / sst)) : 1.0 # 如果 SST 极小，认为 R^2 为 1.0

    # 返回一个具名元组
    return (T_estimated = T_estimated, C_fit = C_fit, a1_fit = a1_fit, ssr = ssr, r_squared = r_squared)

    # return T_estimated
end
#----------速度模密度分布 单位 unit.density/(unit.velocity)^3------------
function velocity_density_distribution(v, T, N0; m=mp, v0 = 0)
    # 计算速度模密度分布函数 对数域
    # v: 速度
    # T: 温度 (开尔文)
    # m: 粒子质量 (kg)
    a1 = m / (2 * κ * T)
    fd = N0*(a1 / π)^1.5 * exp(-a1 * (v-v0)^2)
    return fd
end
function fit_velocity_density_distribution(v, fd; fit_function=:Linear,m=mp,v0=0)
    if length(fd) <= 1
        @warn "数据点不够"
        return (T_estimated = NaN, N_estimated=NaN,C_fit = NaN, a1_fit = NaN, ssr = NaN, r_squared = NaN)
    end
    # 拟合计算速度分布函数 对数域, 默认粒子为质子
    Y = log.(fd)
    X = hcat(ones(length(v)), (v .- v0).^2)
    P = (X' * X) \ (X' * Y)
    C_fit, neg_a1_fit = P
    a1_fit = -neg_a1_fit
    T_estimated = m / (2 * κ * a1_fit)

    # 估计温度
    # 确保 a1_fit 为正，否则无法计算有效温度
    if a1_fit < 0 
        @warn "拟合为负值"
        return (T_estimated = NaN, N_estimated=NaN,C_fit = NaN, a1_fit = NaN, ssr = NaN, r_squared = NaN)
    end
    T_estimated = (a1_fit > 0) ? (m / (2 * κ * a1_fit)) : NaN

    # 估计总密度
    N_estimated = exp(C_fit) / (1/π * a1_fit)^(3/2)

    # --- 计算拟合优度指标 ---
    # 预测值 Y_predicted
    Y_predicted = X * P

    # 残差 (residuals)
    residuals = Y - Y_predicted

    # 残差平方和 (SSR)
    ssr = sum(abs2, residuals)

    # 总平方和 (SST) - 衡量因变量的总变异性
    # 如果 Y 是一个单元素的数组，var(Y) 会返回 NaN，因此需要特殊处理
    if length(Y) > 1
        sst = sum(abs2, Y .- mean(Y))
    else
        sst = 0.0 # 单个数据点没有变异性
    end

    # 决定系数 (R^2)
    # 如果 SST 接近零（所有 Y 值都相同），R^2 可能无意义或为 NaN/Inf
    r_squared = (sst > eps()) ? (1 - (ssr / sst)) : 1.0 # 如果 SST 极小，认为 R^2 为 1.0

    # 返回一个具名元组
    return (
        T_estimated = T_estimated, 
        N_estimated=N_estimated,
        C_fit = C_fit, 
        a1_fit = a1_fit, 
        ssr = ssr, 
        r_squared = r_squared,
        # 取得拟合函数
        fit_function = vs-> Maxwellian_Distribution.velocity_density_distribution.(vs,T_estimated,N_estimated;v0=v0)
        )
    # return T_estimated
end
using LsqFit, LinearAlgebra

# 定义拟合模型函数 (在对数域)
# v 是自变量数据 (速度值)
# p 是参数数组: p[1] = ln(C), p[2] = a1, p[3] = v0
function fit_velocity_distribution_nonlinear(v, fd; m=mp)
    function log_maxwellian_model(v, p)
        C_fit, a1_fit, v0_fit = p
        # 模型: log(f(v)) = C_fit - a1_fit * (v - v0_fit)^2
        return C_fit .- a1_fit .* (v .- v0_fit).^2
    end
    if length(fd) <= 1
        @warn "数据点不够"
        return (T_estimated = NaN, N_estimated=NaN,C_fit = NaN, a1_fit = NaN, ssr = NaN, r_squared = NaN)
    end
    # ------------------ 1. 设定初值 (Initial Guess) ------------------
    # 好的初值对非线性拟合至关重要。
    
    # 估算 C_fit (ln(f_max))
    C_init = log(maximum(fd))
    
    # 估算 v0_fit (漂移速度，可简单取数据的加权平均或中值)
    v0_init = mean(v) # 简单估算
    
    # 估算 a1_fit (从温度估算)
    # 假设一个合理的初始温度 T_init，例如 10 eV 或 10^5 K
    T_init = 100.0 * 1.602e-19 / κ # 假设 100 eV (转换为 K)
    a1_init = m / (2 * κ * T_init)
    
    # 初始参数向量 p0
    p0 = [C_init, a1_init, v0_init]

    # ------------------ 2. 执行非线性拟合 ------------------
    # 将 fd 转换为对数域进行拟合
    Y = log.(fd)

    # curve_fit(模型函数, x数据, y数据, 初始参数)
    fit = curve_fit(log_maxwellian_model, v, Y, p0)
    
    # 提取拟合结果
    C_fit, a1_fit, v0_fit = fit.param

    # ------------------ 3. 提取物理量 ------------------
    
    if a1_fit < 0
         @warn "拟合参数 a1 为负值，物理温度无效。"
         return (T_estimated = NaN, N_estimated=NaN,C_fit = NaN, a1_fit = NaN, ssr = NaN, r_squared = NaN)
    end

    # 温度 T 的估计
    T_estimated = m / (2 * κ * a1_fit)

    # 密度 N 的估计 (假设拟合的是三维分布的截面 f(vx, 0, 0))
    # N = exp(C_fit) * (π / a1_fit)^(3/2)
    N_estimated = exp(C_fit) * (π / a1_fit)^(1.5)

    # ------------------ 4. 计算拟合优度 (可选) ------------------
    # LsqFit.jl 提供了残差平方和
    ssr = sum(fit.resid.^2) 
    
    # R-squared (需计算总平方和 SST)
    sst = sum(abs2, Y .- mean(Y))
    r_squared = 1.0 - (ssr / sst)
    
    # ------------------ 5. 返回结果 ------------------
    return (
        T_estimated = T_estimated, 
        N_estimated = N_estimated,
        v0_estimated = v0_fit, # 新增的漂移速度
        C_fit = C_fit, 
        a1_fit = a1_fit, 
        ssr = ssr, 
        r_squared = r_squared,
        fit_function = vs-> exp.(log_maxwellian_model(vs, fit.param))
    )
end

end
# using CairoMakie
# import .Maxwellian_Distribution
# vs = 10 .^(0:0.01:4.3)  # 速度范围
# v0 = 10000
# ff = Maxwellian_Distribution.velocity_density_distribution.(vs, 3000,10e6;v0=v0)

# rr = Maxwellian_Distribution.fit_velocity_density_distribution(vs,ff;v0=v0)
# # ff_fit = Maxwellian_Distribution.velocity_density_distribution.(vs,rr.T_estimated,rr.N_estimated;v0=v0)
# ff_fit= rr.fit_function.(vs)
# rr2 = Maxwellian_Distribution.fit_velocity_distribution_nonlinear(vs,ff)
# ff_fit2= rr2.fit_function.(vs)
# fig = Figure()
# ax = Axis(fig[1,1],xscale=log10,yscale=log10)
# scatter!(ax, vs, ff, color=:red, label="Velocity Distribution")
# lines!(ax, vs, ff_fit, linewidth=2, label="Velocity Distribution")
# lines!(ax, vs, ff_fit2, linewidth=2, label="Velocity Distribution")
# fig