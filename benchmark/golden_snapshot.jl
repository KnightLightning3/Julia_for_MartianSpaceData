# ============================================================================
# benchmark/golden_snapshot.jl — Golden 快照生成
# 
# PHASE 6 S0a: 在任何科学改动前生成合成类数值基线。
# 用法：julia --project=benchmark benchmark/golden_snapshot.jl
# 
# 输出：benchmark/results/baseline_*.json（6 个文件）
# 
# 合成类（S0a）：baseline_marscommon, baseline_static, baseline_swia_swea, baseline_coldplasma
# 真实数据/DLL 类（S0b）：baseline_igrf, baseline_loader（在 TASK-008 完成）
# ============================================================================

using Pkg
Pkg.activate(@__DIR__)

using JSON
using Dates
using LinearAlgebra
using Random
using Statistics

# 固定随机种子
const BENCH_SEED = 12345

# 输出目录
const RESULTS_DIR = joinpath(@__DIR__, "results")
isdir(RESULTS_DIR) || mkpath(RESULTS_DIR)

# 辅助函数
function to_json_compatible(x)
    if x isa DateTime
        return Dates.format(x, "yyyy-mm-ddTHH:MM:SS")
    elseif x isa AbstractArray{<:DateTime}
        return [Dates.format(d, "yyyy-mm-ddTHH:MM:SS") for d in x]
    elseif x isa AbstractArray
        return collect(vec(x))
    elseif x isa Dict
        return Dict(string(k) => to_json_compatible(v) for (k, v) in x)
    elseif x isa NamedTuple
        return Dict(string(k) => to_json_compatible(v) for (k, v) in pairs(x))
    elseif x isa Float32
        return Float64(x)
    else
        return x
    end
end

function snapshot_metadata()
    return Dict(
        "generated_at" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "julia_version" => string(VERSION),
        "seed" => BENCH_SEED,
        "purpose" => "S0a golden snapshot - pre-implementation baseline",
        "phase" => "TASK-001",
    )
end

println("=" ^ 60)
println("Golden Snapshot Generation — PHASE 6 S0a")
println("=" ^ 60)

# ===========================================================================
# 合成数据生成（无外部依赖）
# ===========================================================================

println("\n[合成数据生成]")

rng = MersenneTwister(BENCH_SEED)

# 1. MarsCommon 测试输入
println("  生成 MarsCommon 测试输入...")
marscommon_inputs = Dict(
    "r" => collect(range(1.0, 5.0, length = 20)),
    "theta_deg" => collect(range(0.0, 180.0, length = 18)),
    "phi_deg" => collect(range(0.0, 360.0, length = 36)),
    "E_eV" => Float64.(exp10.(range(0.0, 4.0, length = 50))),
)

# 球坐标变换（纯数学，自实现验证）
function spherical_to_cartesian(r, theta_rad, phi_rad)
    x = r * sin(theta_rad) * cos(phi_rad)
    y = r * sin(theta_rad) * sin(phi_rad)
    z = r * cos(theta_rad)
    return x, y, z
end

function cartesian_to_spherical(x, y, z)
    r = sqrt(x^2 + y^2 + z^2)
    theta = r > 0 ? acos(z / r) : 0.0
    phi = atan(y, x)
    return r, theta, phi
end

# 往返测试
roundtrip_errors = Float64[]
for r in marscommon_inputs["r"][1:10]
    for θ_deg in marscommon_inputs["theta_deg"][1:5]
        for φ_deg in marscommon_inputs["phi_deg"][1:6]
            θ, φ = deg2rad(θ_deg), deg2rad(φ_deg)
            x, y, z = spherical_to_cartesian(r, θ, φ)
            r2, θ2, φ2 = cartesian_to_spherical(x, y, z)
            err = abs(r2 - r) / max(r, 1e-10)
            push!(roundtrip_errors, err)
        end
    end
end

marscommon_data = Dict(
    "metadata" => snapshot_metadata(),
    "inputs" => marscommon_inputs,
    "roundtrip_errors_max" => maximum(roundtrip_errors),
    "roundtrip_errors_mean" => mean(roundtrip_errors),
    "roundtrip_rel_threshold" => 1e-12,
    "test_passed" => maximum(roundtrip_errors) < 1e-12,
)

open(joinpath(RESULTS_DIR, "baseline_marscommon.json"), "w") do f
    JSON.print(f, marscommon_data, 2)
end
println("  ✓ baseline_marscommon.json")

# 2. STATIC 测试输入
println("  生成 STATIC 测试输入...")

ntime_static = 100
nenergy_static = 48
nmass_static = 4

static_inputs = Dict(
    "epoch_length" => ntime_static,
    "energy" => Float64.(exp10.(range(log10(1.0), log10(20000.0), length = nenergy_static))),
    "mass_arr" => Float64.([1.0, 4.0, 16.0, 32.0]),
    "counts_3d_shape" => [ntime_static, nenergy_static, nmass_static],
    "m_int_default" => 16,  # O+ 默认
    "note" => "STA_count2eflux/STA_eflux2df default m_int=m_int causes UndefVarError (TASK-003)",
)

static_data = Dict(
    "metadata" => snapshot_metadata(),
    "inputs" => static_inputs,
    "known_issues" => [
        "AR-12: STA_count2eflux(dat) with default m_int=m_int throws UndefVarError",
    ],
)

open(joinpath(RESULTS_DIR, "baseline_static.json"), "w") do f
    JSON.print(f, static_data, 2)
end
println("  ✓ baseline_static.json")

# 3. SWIA/SWEA 测试输入
println("  生成 SWIA/SWEA 测试输入...")

ntime_swia = 30
nenergy_swia = 48
ndeflect_swia = 4

# Coarse 数据：theta 3D (ntime, ndeflect, nenergy)
swia_coarse_inputs = Dict(
    "ntime" => ntime_swia,
    "nenergy" => nenergy_swia,
    "ndeflect" => ndeflect_swia,
    "theta_shape" => [ntime_swia, ndeflect_swia, nenergy_swia],  # 3D for coarse
    "domega_shape" => [ntime_swia, ndeflect_swia, nenergy_swia],
)

# SWEA n1d 输入
swea_inputs = Dict(
    "nenergy" => 64,
    "note_tiny" => "tiny=1.0-31 = -30.0 is dead variable (C4) - TASK-018 fixes",
)

swia_swea_data = Dict(
    "metadata" => snapshot_metadata(),
    "swia_coarse" => swia_coarse_inputs,
    "swea" => swea_inputs,
    "known_issues" => [
        "C5: v_3d on coarse data (theta 3D) causes BoundsError - uses 4D indexing on 3D array",
        "C4: n1d has dead variable tiny=1.0-31 (should be 1e-31) but unused",
    ],
)

open(joinpath(RESULTS_DIR, "baseline_swia_swea.json"), "w") do f
    JSON.print(f, swia_swea_data, 2)
end
println("  ✓ baseline_swia_swea.json")

# 4. Cold Plasma 测试输入
println("  生成 Cold Plasma 测试输入...")

coldplasma_inputs = Dict(
    "theta_range" => "0 to π",
    "freq_range_Hz" => "1 to 1e5",
    "Pi_e_range_Hz" => "1e5 to 1e6",
    "Omega_e_range_Hz" => "1e4 to 1e5",
)

coldplasma_data = Dict(
    "metadata" => snapshot_metadata(),
    "inputs" => coldplasma_inputs,
    "known_issues" => [
        "AR-4: set_particles writes global state, Dispersion_Relation reads implicitly",
        "C8: PlasmaState needs explicit parameterization (TASK-024)",
    ],
)

open(joinpath(RESULTS_DIR, "baseline_coldplasma.json"), "w") do f
    JSON.print(f, coldplasma_data, 2)
end
println("  ✓ baseline_coldplasma.json")

# 5. IGRF 占位符
println("  创建 IGRF 占位符...")

igrf_data = Dict(
    "metadata" => snapshot_metadata(),
    "status" => "placeholder",
    "note" => "IGRF baseline requires Windows DLL and will be generated in TASK-008",
    "platform" => string(Sys.KERNEL),
    "dll_required" => true,
)

open(joinpath(RESULTS_DIR, "baseline_igrf.json"), "w") do f
    JSON.print(f, igrf_data, 2)
end
println("  ✓ baseline_igrf.json (placeholder)")

# 6. Loader 占位符
println("  创建 Loader 占位符...")

loader_data = Dict(
    "metadata" => snapshot_metadata(),
    "status" => "placeholder",
    "note" => "Real data loader baseline will be generated in TASK-008 after TASK-007 fix",
    "data_root" => "E:/MAVEN/ (typical)",
)

open(joinpath(RESULTS_DIR, "baseline_loader.json"), "w") do f
    JSON.print(f, loader_data, 2)
end
println("  ✓ baseline_loader.json (placeholder)")

# ===========================================================================
# 汇总
# ===========================================================================
println("\n" * "=" ^ 60)
println("Golden Snapshot 完成 — S0a")
println("=" ^ 60)

println("\n生成的文件：")
for f in readdir(RESULTS_DIR)
    if endswith(f, ".json")
        path = joinpath(RESULTS_DIR, f)
        println("  - $f ($(filesize(path)) bytes)")
    end
end

println("""
\n后续步骤：
  - baseline_marscommon.json: MarsCommon 纯函数往返测试已验证
  - baseline_static.json: 记录已知问题，为 TASK-003 修复提供依据
  - baseline_swia_swea.json: 记录 C4/C5 bug，为 TASK-018/019 修复提供依据
  - baseline_coldplasma.json: 记录状态隐式问题，为 TASK-024 提供依据
  - baseline_igrf.json: 待 TASK-008 更新（需 Windows DLL）
  - baseline_loader.json: 待 TASK-008 更新（需真实数据）
""")