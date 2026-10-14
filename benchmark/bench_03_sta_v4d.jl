# ============================================================================
# benchmark/bench_03_sta_v4d.jl — sta_v_4d vs sta_v_4d_new 等价性测试
# 
# 目的：为 TASK-044 提供等价性门证据
# 判据：rel ≤ 1e-9 才允许收编（删除旧版）
# 用法：julia --project=benchmark benchmark/bench_03_sta_v4d.jl
# ============================================================================

using Pkg
Pkg.activate(@__DIR__)

using BenchmarkTools
using Dates
using Random
using LinearAlgebra
using JSON

const BENCH_SEED = 12345
const EQUIV_THRESHOLD = 1e-9

println("=" ^ 60)
println("bench_03_sta_v4d.jl — sta_v_4d 等价性门测试")
println("=" ^ 60)

# 加载 MarsData
push!(LOAD_PATH, joinpath(@__DIR__, ".."))
using MarsData

# 加载 STATIC 模块
println("\n加载 MAVEN_STATIC 模块...")
MarsData.load_module(:MAVEN_STATIC)
sta = MarsData.MAVEN_STATIC

# 检查两个函数是否存在
has_old = isdefined(sta, :sta_v_4d)
has_new = isdefined(sta, :sta_v_4d_new)

println("  sta_v_4d 存在: $has_old")
println("  sta_v_4d_new 存在: $has_new")

if !has_old || !has_new
    println("\n警告：双版本未全部存在，等价性测试无法进行")
    println("  等待 TASK-044 修复后再运行")
    exit(0)
end

# 生成合成数据
println("\n生成合成数据...")
rng = MersenneTwister(BENCH_SEED)

ntime = 50
nenergy = 48
nmass = 4

# d1 切片格式
epoch = collect(DateTime(2020, 1, 1, 0, 0, 0) .+ Second.(0:ntime-1))
energy = Float32.(exp10.(range(log10(1.0), log10(20000.0), length = nenergy)))
mass_arr = Float32.([1.0, 4.0, 16.0, 32.0])
counts_3d = Float32.(rand(rng, ntime, nenergy, nmass) .* 10 .+ 0.1)
eff = Float32.(rand(rng, nenergy) .* 0.3 .+ 0.7)

# v_4d 需要的数据键
# 参考 MAVEN_STATIC.jl 中 sta_v_4d 的实际签名
# 这里创建最小必要数据结构

d1_dat = Dict{Symbol,Any}(
    :epoch => epoch,
    :energy => energy,
    :mass_arr => mass_arr,
    :counts_3d => counts_3d,
    :eff => eff,
    :data_load_flag => true,
)

println("数据形状：")
println("  counts_3d: $(size(counts_3d))")
println("  epoch: $(length(epoch))")

# 等价性测试
println("\n" * "-" ^ 40)
println("等价性测试：sta_v_4d vs sta_v_4d_new")
println("-" ^ 40)

# 尝试调用两个版本
result_old = try
    sta.sta_v_4d(d1_dat)
catch e
    println("  sta_v_4d 调用失败: $e")
    nothing
end

result_new = try
    sta.sta_v_4d_new(d1_dat)
catch e
    println("  sta_v_4d_new 调用失败: $e")
    nothing
end

if result_old === nothing || result_new === nothing
    println("\n警告：无法获取双版本结果")
    println("  需要检查函数签名和数据格式")
else
    # 比较结果
    println("\n结果类型：")
    println("  old: $(typeof(result_old))")
    println("  new: $(typeof(result_new))")
    
    # 如果是字典，比较数值
    if result_old isa Dict && result_new isa Dict
        # 找出共同的键
        common_keys = intersect(keys(result_old), keys(result_new))
        println("\n共同键: $common_keys")
        
        max_rel_err = 0.0
        for k in common_keys
            v_old = result_old[k]
            v_new = result_new[k]
            if v_old isa AbstractArray{<:Real} && v_new isa AbstractArray{<:Real}
                rel_err = maximum(abs.(v_old .- v_new) ./ max.(abs.(v_old), 1e-10))
                max_rel_err = max(max_rel_err, rel_err)
                println("  $k: rel_err = $rel_err")
            end
        end
        
        println("\n" * "=" ^ 60)
        if max_rel_err <= EQUIV_THRESHOLD
            println("✓ 等价性测试通过: max_rel_err = $max_rel_err ≤ $EQUIV_THRESHOLD")
            println("  TASK-044 门条件满足，可以收编删除旧版")
        else
            println("✗ 等价性测试未通过: max_rel_err = $max_rel_err > $EQUIV_THRESHOLD")
            println("  必须保留双版本，记录差异并上报")
        end
        println("=" ^ 60)
    end
end

# Benchmark
println("\n" * "-" ^ 40)
println("性能基准")
println("-" ^ 40)

if result_old !== nothing
    b_old = @benchmark sta.sta_v_4d($d1_dat) samples = 5 evals = 2
    println("sta_v_4d:")
    println("  min: $(minimum(b_old))")
    println("  median: $(median(b_old))")
end

if result_new !== nothing
    b_new = @benchmark sta.sta_v_4d_new($d1_dat) samples = 5 evals = 2
    println("sta_v_4d_new:")
    println("  min: $(minimum(b_new))")
    println("  median: $(median(b_new))")
end

println("\n基准完成")