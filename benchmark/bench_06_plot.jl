# ============================================================================
# benchmark/bench_06_plot.jl — plot_module 合成基准
# 
# 目的：为 TASK-039/040/047 提供绘图性能基线
# 判据：改动后不得慢于基线 110%
# 用法：julia --project=benchmark benchmark/bench_06_plot.jl
# ============================================================================

using Pkg
Pkg.activate(@__DIR__)

using BenchmarkTools
using Dates
using Random
using JSON

const BENCH_SEED = 12345

println("=" ^ 60)
println("bench_06_plot.jl — plot_module 合成基准")
println("=" ^ 60)

# 加载 MarsData
push!(LOAD_PATH, joinpath(@__DIR__, ".."))
using MarsData

# CairoMakie 已经在 MarsData 的 deps 中
using CairoMakie

println("\n加载完成")

# 生成合成 data_dict
println("\n生成合成绘图数据...")
rng = MersenneTwister(BENCH_SEED)

ntime = 200

epoch = collect(DateTime(2020, 1, 1, 0, 0, 0) .+ Second.(0:ntime-1))

# 基础数据
orbit = Dict{Symbol,Any}(
    :epoch => epoch,
    :altitude => Float32.(rand(rng, ntime) .* 500 .+ 200),
    :latitude => Float32.(rand(rng, ntime) .* 180 .- 90),
    :longitude => Float32.(rand(rng, ntime) .* 360),
    :local_time => Float32.(rand(rng, ntime) .* 24),
)

B_xyz = Dict{Symbol,Any}(
    :epoch => epoch,
    :B => Float32.(rand(rng, 3, ntime) .* 50 .- 25),
    :data_load_flag => true,
)

static_d1 = Dict{Symbol,Any}(
    :epoch => epoch,
    :energy => Float32.(exp10.(range(log10(1.0), log10(20000.0), length = 48))),
    :mass_arr => Float32.([1.0, 4.0, 16.0, 32.0]),
    :data_load_flag => true,
)

swia = Dict{Symbol,Any}(
    :epoch => epoch,
    :energy => Float32.(exp10.(range(log10(5.0), log10(25000.0), length = 48))),
    :data_load_flag => true,
)

kp = Dict{Symbol,Any}(
    :epoch => epoch,
    :kp => Float32.(rand(rng, ntime) .* 9),
    :data_load_flag => true,
)

data_dict = Dict{String,Any}(
    "orbit" => orbit,
    "MAG" => B_xyz,
    "STATIC_d1_v4d" => static_d1,
    "SWIA_coarse" => swia,
    "KP" => kp,
)

println("数据条目: $(keys(data_dict))")
println("时间点: $ntime")

# 定义时间范围
time_range = (epoch[1], epoch[end])

# 基准测试
println("\n" * "-" ^ 40)
println("Benchmark: plot_module 合成")
println("-" ^ 40)
println("注意：此基准测试绘图初始化，不测量图像渲染时间")

# 创建 Figure 的基准
println("\n创建 Figure:")
b_fig = @benchmark Figure(; size = (2500, 2500)) samples = 5 evals = 2
println("  min: $(minimum(b_fig))")
println("  median: $(median(b_fig))")

# 尝试调用 plot_module
println("\n尝试 plot_module 调用...")

result = try
    fig = Figure(; size = (2500, 2500))
    MarsData.plot_module(fig, time_range, data_dict; time_step = Dates.Minute(10))
    "SUCCESS"
catch e
    println("  错误: $e")
    "ERROR"
end

println("  结果: $result")

if result == "SUCCESS"
    println("\nplot_module 调用成功")
    
    # 完整基准
    println("\n完整 plot_module 基准:")
    b_plot = @benchmark begin
        fig = Figure(; size = (2500, 2500))
        MarsData.plot_module(fig, $time_range, $data_dict; time_step = Dates.Minute(10))
    end samples = 3 evals = 1
    
    println("  min: $(minimum(b_plot))")
    println("  median: $(median(b_plot))")
else
    println("\n警告：plot_module 调用失败，可能是数据格式不匹配")
    println("  需要检查数据字典结构")
end

# 汇总
println("\n" * "=" ^ 60)
println("基准完成")
println("=" ^ 60)
println("""
后续步骤：
  - TASK-039 面板化后重新运行，对比时间
  - TASK-040 KP 键归一后重新运行
  - TASK-047 微优化后重新运行
  - 判据：改动后 median 不超过基线 110%
""")