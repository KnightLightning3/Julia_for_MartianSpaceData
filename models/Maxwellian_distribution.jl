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
function velocity_density_distribution(v, T, N0; m=mp)
    # 计算速度模密度分布函数 对数域
    # v: 速度
    # T: 温度 (开尔文)
    # m: 粒子质量 (kg)
    a1 = m / (2 * κ * T)
    fd = N0*(a1 / π)^1.5 * exp(-a1 * v^2)
    return fd
end
function fit_velocity_density_distribution(v, fd; fit_function=:Linear,m=mp)
    # 拟合计算速度分布函数 对数域, 默认粒子为质子
    Y = log.(fd)
    X = hcat(ones(length(v)), v.^2)
    P = (X' * X) \ (X' * Y)
    C_fit, neg_a1_fit = P
    a1_fit = -neg_a1_fit
    T_estimated = m / (2 * κ * a1_fit)

    # 估计温度
    # 确保 a1_fit 为正，否则无法计算有效温度
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
    return (T_estimated = T_estimated, N_estimated=N_estimated,C_fit = C_fit, a1_fit = a1_fit, ssr = ssr, r_squared = r_squared)

    # return T_estimated
end
end
# using CairoMakie
# vs = 10 .^(-1:0.01:4.3)  # 速度范围
# ff = velocity_distribution.(vs, mp, 1000)
# rr = fit_velocity_distribution(vs,ff)
# lines(vs, ff, color=:blue, linewidth=2, label="Velocity Distribution")