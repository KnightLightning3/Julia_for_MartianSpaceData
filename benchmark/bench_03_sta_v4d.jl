# ============================================================================
# benchmark/bench_03_sta_v4d.jl — `sta_v_4d` 单函数有效合成夹具基准
#
# 目的：用一次性构建的**有效** STATIC 单时刻切片，检查 `sta_v_4d` 数值输出有限性，
#       并用 Base 计时给出小性能测量。
#
# 与旧版的差异（历史）：旧脚本用缺键夹具 + try/catch + `exit(0)` 构成“伪通过”，
#       并对比已删除的 `sta_v_4d_new`。旧版已整体重写：只保留单函数有效夹具，
#       不保留 `isdefined` 兼容分支，不引入 BenchmarkTools/JSON 等新依赖（仅 Base 计时）。
#
# 用法：julia --project=. benchmark/bench_03_sta_v4d.jl
# 失败即非零退出（不吞异常）。
# ============================================================================

using Dates
using MarsData

MarsData.load_module(:MAVEN_STATIC)
const STA = MarsData.MAVEN_STATIC

println("=" ^ 60)
println("bench_03_sta_v4d.jl — sta_v_4d 单函数基准（Base 计时）")
println("=" ^ 60)

# ---------------------------------------------------------------------------
# 确定性有效合成夹具（Float32 数组，模拟 STATIC d1/c6 单时刻切片）
# ---------------------------------------------------------------------------
const NMASS, NBINS, NENERGY = 4, 8, 48
const MASS_NUMBERS = Float32[1.0, 4.0, 16.0, 32.0]

det3(f, d1, d2, d3) = [f(i, j, k) for i in 1:d1, j in 1:d2, k in 1:d3]

function sta_slice_raw(; mass_basis = Float64(STA.constants.mp_eV_per_km_s2))
    return Dict{Symbol,Any}(
        :nbins        => Int16(NBINS),
        :nenergy      => Int16(NENERGY),
        :nmass        => NMASS,
        # mass_arr = 逐道质量数（不是质量基准）
        :mass_arr     => Float32.(det3((i, j, k) -> MASS_NUMBERS[i], NMASS, NBINS, NENERGY)),
        :energy       => Float32.(det3((i, j, k) -> 10.0 * k + j, NMASS, NBINS, NENERGY)),
        :denergy      => Float32.(det3((i, j, k) -> 1.0 + 0.1 * k, NMASS, NBINS, NENERGY)),
        :theta        => Float32.(det3((i, j, k) -> 15.0 + 7.0 * j, NMASS, NBINS, NENERGY)),
        :phi          => Float32.(det3((i, j, k) -> 25.0 + 11.0 * j, NMASS, NBINS, NENERGY)),
        :dtheta       => Float32.(det3((i, j, k) -> 5.0 + 0.5 * j, NMASS, NBINS, NENERGY)),
        :dphi         => Float32.(det3((i, j, k) -> 6.0 + 0.25 * j, NMASS, NBINS, NENERGY)),
        :gf           => Float32.(det3((i, j, k) -> 0.5 + 0.05 * j, 1, NBINS, NENERGY)),
        :eff          => Float32.(det3((i, j, k) -> 0.6 + 0.01 * i, NMASS, NBINS, NENERGY)),
        :geom_factor  => 0.02,
        :time_integ   => 4.0,
        :dead         => Float32.(det3((i, j, k) -> 1.0 + 0.001 * k, NMASS, NBINS, NENERGY)),
        :bkg          => Float32.(det3((i, j, k) -> 0.05 * k, NMASS, NBINS, NENERGY)),
        :data         => Float32.(det3((i, j, k) -> 100.0 + 10.0 * k + i, NMASS, NBINS, NENERGY)),
        :sc_pot       => 1.5,
        :valid        => 1,
        :mass         => mass_basis,
    )
end

# 生产链（同 MAVEN_data/Build_data/STATIC_VD.jl）：切片 → STA_count2df → sta_v_4d(unit_cover=false)
# 夹具同样先过一次 STA_count2df，使 unit_cover=false 分支拿到与计数同量级的 df_mass_mass。
sta_slice_fixture(; kwargs...) = STA.STA_count2df(sta_slice_raw(; kwargs...))

const KW = (; energy_range = [0, 1e5], mass_range = [14, 20], m_int = 16)

println("\n夹具：nmass=$NMASS nbins=$NBINS nenergy=$NENERGY  (Float32 数组, 有效切片 valid=1)")
println("  :mass_arr = $MASS_NUMBERS（逐道质量数）")
println("  数据包 :mass 键（改动后不再被读取）= ", repr(Float64(STA.constants.mp_eV_per_km_s2)))

# ---------------------------------------------------------------------------
# 正确性：两条分支都必须给出有限结果；行为不得依赖数据包 :mass
# ---------------------------------------------------------------------------
dat = sta_slice_fixture()
vel, flux, density = STA.sta_v_4d(dat; KW...)
println("\nsta_v_4d(unit_cover=true)")
println("  vel     = ", vel)
println("  flux    = ", flux)
println("  density = ", density)

vel_nc, flux_nc, density_nc = STA.sta_v_4d(sta_slice_fixture(); KW..., unit_cover = false)
println("sta_v_4d(unit_cover=false)")
println("  vel     = ", vel_nc)
println("  flux    = ", flux_nc)
println("  density = ", density_nc)

isfinite_tuple((v, f, d)) = all(isfinite, v) && all(isfinite, f) && isfinite(d)

@assert isfinite_tuple((vel, flux, density)) "sta_v_4d(unit_cover=true) 输出非有限"
@assert isfinite_tuple((vel_nc, flux_nc, density_nc)) "sta_v_4d(unit_cover=false) 输出非有限"

# 两条分支在 m_int 与掩膜选中的 mass_arr 一致时应逐位一致（夹具取 m_int=16、mass_arr=16 的道）
@assert isequal(vel, vel_nc) && isequal(flux, flux_nc) && isequal(density, density_nc) "两条分支结果不一致"
println("\n检查通过：两条分支在 m_int=mass_arr 时结果逐位一致")

# 改动后不再读取数据包 :mass：键缺失/异值必须给出相同结果
dat_nomass = sta_slice_fixture()
delete!(dat_nomass, :mass)
vel_nm, flux_nm, density_nm = STA.sta_v_4d(dat_nomass; KW...)
@assert isequal(vel_nm, vel) && isequal(flux_nm, flux) && isequal(density_nm, density) "缺失 :mass 时输出变化"

dat_shift = sta_slice_fixture(; mass_basis = Float64(STA.constants.mp_eV_per_km_s2) * 1.5)
vel_sh, flux_sh, density_sh = STA.sta_v_4d(dat_shift; KW...)
@assert isequal(vel_sh, vel) && isequal(flux_sh, flux) && isequal(density_sh, density) "异值 :mass 改变了输出"
println("\n检查通过：输出有限；缺失/异值 :mass 结果逐位一致（质量基准取自 Float64 常量）")

# ---------------------------------------------------------------------------
# 小性能测量（Base 计时：先预热，再取 5 批 × 100 次的最小值与分配量）
# ---------------------------------------------------------------------------
function bench(f; batches = 5, evals = 100)
    f()                                    # 预热（编译）
    best = Inf
    for _ in 1:batches
        t = @elapsed for _ in 1:evals
            f()
        end
        best = min(best, t)
    end
    alloc = @allocated f()
    return best / evals, alloc
end

dat_cover = sta_slice_fixture()
dat_nocover = sta_slice_fixture()
t_cover, a_cover = bench(() -> STA.sta_v_4d(dat_cover; KW...))
t_nocov, a_nocov = bench(() -> STA.sta_v_4d(dat_nocover; KW..., unit_cover = false))

println("\n" * "-" ^ 40)
println("性能（Base @elapsed，最佳批次平均；@allocated 为单次调用）")
println("-" ^ 40)
println("unit_cover=true  : ", round(t_cover * 1e6; digits = 2), " µs/call,  ",
        round(a_cover / 1024; digits = 1), " KiB")
println("unit_cover=false : ", round(t_nocov * 1e6; digits = 2), " µs/call,  ",
        round(a_nocov / 1024; digits = 1), " KiB")
println("\n基准完成（单函数 sta_v_4d；sta_v_4d_new 已删除，不再做双版本对比）")
