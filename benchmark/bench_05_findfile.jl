# ============================================================================
# benchmark/bench_05_findfile.jl — 文件定位索引化基准
# 
# 目的：为 TASK-013 提供索引化前后对比证据
# 测试：find_file_of_data 性能（O(N) 线性扫描 vs O(1) 日期索引）
# 用法：julia --project=benchmark benchmark/bench_05_findfile.jl
# ============================================================================

using Pkg
Pkg.activate(@__DIR__)

using BenchmarkTools
using Dates
using Random
using JSON

const BENCH_SEED = 12345

println("=" ^ 60)
println("bench_05_findfile.jl — 文件定位基准")
println("=" ^ 60)

# 加载 MarsData
push!(LOAD_PATH, joinpath(@__DIR__, ".."))
using MarsData

# 生成合成文件列表
println("\n生成合成文件列表...")
rng = MersenneTwister(BENCH_SEED)

nfiles = 1000
date_range = collect(Date(2015, 1, 1):Day(1):Date(2017, 12, 31))

file_list = String[]
target_dates = String[]

for i in 1:nfiles
    d = date_range[rand(rng, 1:length(date_range))]
    date_str = Dates.format(d, "yyyymmdd")
    filename = "mvn_l2_sta_c6_$date_str_v01_r01.cdf"
    push!(file_list, filename)
    if i <= 10  # 保存一些目标日期用于查询
        push!(target_dates, date_str)
    end
end

println("生成文件数: $nfiles")
println("日期范围: $(date_range[1]) 到 $(date_range[end])")
println("目标日期样本: $(target_dates[1:min(5, length(target_dates))])")

# 模拟旧版线性扫描
function find_file_linear(files::Vector{String}, date_str::String)
    for f in files
        if occursin(date_str, f)
            return f
        end
    end
    return nothing
end

# 模拟新索引版
function build_date_index(files::Vector{String})
    index = Dict{String,Vector{String}}()
    date_pattern = r"\d{8}"
    for f in files
        m = match(date_pattern, f)
        if m !== nothing
            date_str = m.match
            if !haskey(index, date_str)
                index[date_str] = String[]
            end
            push!(index[date_str], f)
        end
    end
    return index
end

function find_file_indexed(index::Dict{String,Vector{String}}, date_str::String)
    return get(index, date_str, nothing)
end

# 构建索引
println("\n构建日期索引...")
index = build_date_index(file_list)
println("索引条目数: $(length(index))")

# 基准测试
println("\n" * "-" ^ 40)
println("基准测试：线性扫描 vs 索引")
println("-" ^ 40)

# 测试查询
test_dates = target_dates[1:min(5, length(target_dates))]

# 线性扫描
println("\n线性扫描:")
b_linear = @benchmark begin
    for d in $test_dates
        find_file_linear($file_list, d)
    end
end samples = 10 evals = 5

println("  min: $(minimum(b_linear))")
println("  median: $(median(b_linear))")

# 索引查询
println("\n索引查询:")
b_indexed = @benchmark begin
    for d in $test_dates
        find_file_indexed($index, d)
    end
end samples = 10 evals = 5

println("  min: $(minimum(b_indexed))")
println("  median: $(median(b_indexed))")

# 正确性验证
println("\n" * "-" ^ 40)
println("正确性验证")
println("-" ^ 40)

all_match = true
for d in target_dates
    linear_result = find_file_linear(file_list, d)
    indexed_result = find_file_indexed(index, d)
    if linear_result !== nothing && indexed_result !== nothing
        # indexed 返回数组，取第一个
        if linear_result != indexed_result[1]
            println("  不匹配: $d -> linear=$linear_result, indexed=$(indexed_result[1])")
            all_match = false
        end
    end
end

if all_match
    println("  ✓ 全部匹配")
end

# 速度比
t_linear = median(b_linear).time
t_indexed = median(b_indexed).time
speedup = t_linear / t_indexed

println("\n" * "=" ^ 60)
println("结果汇总")
println("=" ^ 60)
println("  线性扫描: $t_linear ns")
println("  索引查询: $t_indexed ns")
println("  加速比: $(round(speedup, digits=1))x")
println("\n  命中一致性: $all_match")
println("=" ^ 60)