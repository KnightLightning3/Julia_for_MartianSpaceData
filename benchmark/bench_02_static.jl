# ============================================================================
# benchmark/bench_02_static.jl — STATIC 矩计算基准
# 
# 测试：STA_count2df_all, STA_count3df, STA_count2eflux_all
# 用法：julia --project=benchmark benchmark/bench_02_static.jl
# ============================================================================

using Pkg
Pkg.activate(@__DIR__)

using BenchmarkTools
using Dates
using Random

const BENCH_SEED = 12345

println("=" ^ 60)
println("bench_02_static.jl — STATIC 矩计算基准")
println("=" ^ 60)

# 加载 MarsData
push!(LOAD_PATH, joinpath(@__DIR__, ".."))
using MarsData

# 加载 STATIC 模块
println("\n加载 MAVEN_STATIC 模块...")
MarsData.load_module(:MAVEN_STATIC)
sta = MarsData.MAVEN_STATIC

println("模块加载完成")

# 生成合成数据
println("\n生成合成数据...")
rng = MersenneTwister(BENCH_SEED)

ntime = 100
nenergy = 48
nmass = 4

# 简化的切片数据
epoch = collect(DateTime(2020, 1, 1, 0, 0, 0) .+ Second.(0:ntime-1))
energy = Float32.(exp10.(range(log10(1.0), log10(20000.0), length = nenergy)))
mass_arr = Float32.([1.0, 4.0, 16.0, 32.0])
counts_3d = Float32.(rand(rng, ntime, nenergy, nmass) .* 10 .+ 0.1)
eff = Float32.(rand(rng, nenergy) .* 0.3 .+ 0.7)
swp = rand(rng, Bool, ntime)
att = rand(rng, Bool, ntime)
theta = Float32.(rand(rng, ntime) .* 360.0)

dat = Dict{Symbol,Any}(
    :epoch => epoch,
    :energy => energy,
    :mass_arr => mass_arr,
    :counts_3d => counts_3d,
    :eff => eff,
    :swp => swp,
    :att => att,
    :theta => theta,
    :data_load_flag => true,
)

println("数据形状：")
println("  counts_3d: $(size(counts_3d))")
println("  energy: $(length(energy))")
println("  mass_arr: $(mass_arr)")

# Benchmark 1: STA_count2eflux
println("\n" * "-" ^ 40)
println("Benchmark: STA_count2eflux")
println("-" ^ 40)

m_int = 16  # O+ 默认
b_eflux = @benchmark sta.STA_count2eflux($dat; m_int = $m_int) samples = 10 evals = 3

println("结果：")
println("  min: $(minimum(b_eflux))")
println("  median: $(median(b_eflux))")
println("  samples: $(length(samples(b_eflux)))")

# Benchmark 2: STA_eflux2df
println("\n" * "-" ^ 40)
println("Benchmark: STA_eflux2df")
println("-" ^ 40)

b_df = @benchmark sta.STA_eflux2df($dat; m_int = $m_int) samples = 10 evals = 3

println("结果：")
println("  min: $(minimum(b_df))")
println("  median: $(median(b_df))")

# 汇总
println("\n" * "=" ^ 60)
println("基准完成")
println("=" ^ 60)
println("""
备注：
  - TASK-003 修复 m_int 默认参数后重新运行
  - TASK-046 向量化优化前后的对比基准
""")