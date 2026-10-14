using JSON
using LinearAlgebra
using Statistics
using Random

# 固定随机种子，保证两次运行输入一致
rng = MersenneTwister(12345)

# 通过 include 方式临时加载 constants（不依赖重模块装载）
include(joinpath(@__DIR__, "..", "common", "constants.jl"))

# 直接 include MAVEN_SWEA 模块（当前工作目录应在仓库根时，模块内相对路径正确）
include(joinpath(@__DIR__, "..", "MAVEN_data", "MAVEN_SWEA.jl"))

# 合成 SWEA 输入：64 能道对数网格 + 各向同性 eflux
nenergy = 64
ntime = 10
energy = 10.0 .^ range(0, 4, length = nenergy)  # 1 eV ~ 10 keV
eflux = rand(rng, ntime, nenergy) .* 1e6

dat = Dict{Symbol,Any}(
    :energy => energy,
    :diff_en_fluxes => eflux,
)

result = MAVEN_SWEA.n1d(dat; sc_pot = 0.0)

out = Dict(
    "n1d" => result,
    "mean_n" => mean(result),
    "std_n" => std(result),
    "min_n" => minimum(result),
    "max_n" => maximum(result),
)

mkpath(joinpath(@__DIR__, "results"))
open(joinpath(@__DIR__, "results", "task018_verify.json"), "w") do f
    JSON.print(f, out, 2)
end

println("TASK-018 verification saved: ", joinpath("benchmark", "results", "task018_verify.json"))
println("mean(n1d)=", out["mean_n"], " min=", out["min_n"], " max=", out["max_n"])
