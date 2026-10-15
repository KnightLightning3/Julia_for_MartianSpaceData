# ============================================================================
# test/static_mass_regression.jl
# STATIC 质量基准局部回归：dat[:mass] → constants.mp_eV_per_km_s2
#
# 由 test/runtests.jl 直接 include；不引入额外依赖，不建验证平台。
#
# 【改动前基线】源码 commit 5f225db（未改动时实测，只读采集，脚本在仓库外）
#   MP = constants.mp_eV_per_km_s2 = 0.010439684891821985 (Float64)
#   同一确定性夹具下：
#     · dat[:mass] = Float64(MP)（与常量同值）→ BASE_F64（下方 101 个探针）
#     · dat[:mass] = Float32(MP)            → BASE_F32，与 F64 有 100/101 个探针不同，
#                                             最大相对差 7.068977758535884e-8（授权精度提升的实测依据）
#     · dat[:mass] = Float64(MP)*1.0001     → 输出最大相对变化 2.0001e-4（证明改动前该键被消费）
#     · 缺失 :mass                          → KeyError(:mass)（STA_count2df / sta_v_4d / STA_count3df）
#     · dat[:valid] = 0                     → stdout 恰为 "Invalid Data\n"，返回全 NaN
#   改动后要求：Float64 同值基准与 BASE_F64 逐位一致；缺失键/异值键结果同为 BASE_F64。
#
# 探针定义 probes(x) = [x[1], x[end], sum, sum(abs), minimum, maximum]，顺序 = all_probes 内的追加顺序。
# ============================================================================

using Test
using StaticArrays

MarsData.load_module(:MAVEN_STATIC)
const STA = MarsData.MAVEN_STATIC
const MP = STA.constants.mp_eV_per_km_s2

# ---------------------------------------------------------------------------
# 改动前实测基线（不要手改数值：与源码不一致时测试即失败）
# ---------------------------------------------------------------------------
const BASELINE_F64 = Float64[
    1.705014107264157e-8, 5.254639236932944e-7, 1.0765277534138559e-5, 1.0765277534138559e-5, 2.1346149377715668e-9, 3.979569259585773e-6, 1.705014107264157e-8, 2.0525934519269314e-9,
    8.709446063682102e-8, 8.709446063682102e-8, 2.0525934519269314e-9, 1.705014107264157e-8, 0.0, 1.2658152264942428e-8, 3.0744547971324818e-9, 8.689311078921265e-8,
    8.689311078921265e-8, 2.5306736765512265e-9, 1.4858348849455354e-8, 10.135896599408767, 6.80805679325751, 26.015122801712355, 26.015122801712355, 6.80805679325751,
    10.135896599408767, 11.017719504052577, 7.400357667435778, 28.278438230069185, 28.278438230069185, 7.400357667435778, 11.017719504052577, 1.0869899901829353e-5,
    11.696228094004045, 8.013475731698284, 30.405517325692585, 30.405517325692585, 8.013475731698284, 11.696228094004045, 2.7219888151253935e7, 1.864925267928343e7,
    7.07608276903085e7, 7.07608276903085e7, 1.864925267928343e7, 2.7219888151253935e7, 23.272364331789134, 23.272364331789134, 1.0869899901829353e-5, 1.863538146162684e-8,
    9.615294482705274e-7, 1.522587046354599e-5, 1.522587046354599e-5, 3.817547758246201e-9, 4.693711562980076e-6, 1.863538146162684e-8, 3.755974407306748e-9, 1.1945286816023452e-7,
    1.1945286816023452e-7, 3.755974407306748e-9, 1.863538146162684e-8, 1.7050141072641574e-8, 4.6707904328292843e-7, 2.024211981729695e-5, 2.024211981729695e-5, 1.911936344721647e-9,
    3.944021521670759e-6, 1.7050141072641574e-8, 1.8245275128239392e-9, 1.645006254194195e-7, 1.645006254194195e-7, 1.8245275128239392e-9, 1.7050141072641574e-8, 1.7050141072641568e-8,
    8.830713162067861e-7, 1.3155056457315142e-5, 1.3155056457315142e-5, 3.6568270966269626e-9, 3.944021521670758e-6, 1.7050141072641568e-8, 3.4494973289327584e-9, 1.07042978175342e-7,
    1.07042978175342e-7, 3.4494973289327584e-9, 1.7050141072641568e-8, 16229.264098931868, 19709.76525297731, 35939.02935190918, 35939.02935190918, 16229.264098931868,
    19709.76525297731, 31069.1897126121, 14005.978898476795, 45075.1686110889, 45075.1686110889, 14005.978898476795, 31069.1897126121, 1.914383007792444e-5,
    7.106011472515425e-6, 2.6249841550439864e-5, 2.6249841550439864e-5, 7.106011472515425e-6, 1.914383007792444e-5,
]
const BASELINE_F32 = Float64[
    1.7050139867370895e-8, 5.254638865483665e-7, 1.0765276773143486e-5, 1.0765276773143486e-5, 2.1346147868761123e-9, 3.979568978270907e-6, 1.7050139867370895e-8, 2.052593306829557e-9,
    8.709445448013301e-8, 8.709445448013301e-8, 2.052593306829557e-9, 1.7050139867370895e-8, 0.0, 1.265815159252973e-8, 3.0744546338146133e-9, 8.689310617337062e-8,
    8.689310617337062e-8, 2.5306735421195117e-9, 1.4858348060166184e-8, 10.135896734012938, 6.808056883668142, 26.015123147191808, 26.015123147191808, 6.808056883668142,
    10.135896734012938, 11.017719310483832, 7.400357537419946, 28.278437733249326, 28.278437733249326, 7.400357537419946, 11.017719310483832, 1.0869899566502853e-5,
    11.696228249332652, 8.013475838119088, 30.405517729484867, 30.405517729484867, 8.013475838119088, 11.696228249332652, 2.7219889597199522e7, 1.8649253669948947e7,
    7.076083144918899e7, 7.076083144918899e7, 1.8649253669948947e7, 2.7219889597199522e7, 23.272365258976233, 23.272365258976233, 1.0869899566502853e-5, 1.8635380471698222e-8,
    9.61529397193198e-7, 1.5225869654733737e-5, 1.5225869654733737e-5, 3.81754755545455e-9, 4.693711313645798e-6, 1.8635380144295874e-8, 3.755974141797753e-9, 1.1945285971613784e-7,
    1.1945285971613784e-7, 3.755974141797753e-9, 1.8635380144295874e-8, 1.7050140166922386e-8, 4.6707901847125976e-7, 2.0242118742016915e-5, 2.0242118742016915e-5, 1.911936243157829e-9,
    3.944021312160705e-6, 1.7050139867370898e-8, 1.8245273838484957e-9, 1.6450061379090693e-7, 1.6450061379090693e-7, 1.8245273838484957e-9, 1.7050139867370898e-8, 1.7050139867370895e-8,
    8.830712537826716e-7, 1.315505552738713e-5, 1.315505552738713e-5, 3.6568268381266705e-9, 3.944021242868756e-6, 1.7050139867370895e-8, 3.449497085088561e-9, 1.0704297060849773e-7,
    1.0704297060849773e-7, 3.449497085088561e-9, 1.7050139867370895e-8, 16229.264314457627, 19709.76551471898, 35939.02982917661, 35939.02982917661, 16229.264314457627,
    19709.76551471898, 31069.18916676194, 14005.978652407743, 45075.167819169685, 45075.167819169685, 14005.978652407743, 31069.18916676194, 1.9143829487354742e-5,
    7.1060112533014525e-6, 2.6249840740656194e-5, 2.6249840740656194e-5, 7.1060112533014525e-6, 1.9143829487354742e-5,
]
const MEASURED_F32_VS_F64_MAX_REL = 7.068977758535884e-8   # 改动前：Float32 质量基准 vs Float64 同值基准
const MEASURED_BASIS_F32_REL = 2.6560460581326496e-8       # 改动前：Float32(MP) vs MP 本身

# ---------------------------------------------------------------------------
# 确定性小夹具（与改动前基线采集脚本逐字一致，只改质量键的来源/取值）
# ---------------------------------------------------------------------------
det3(f, d1, d2, d3) = [f(i, j, k) for i in 1:d1, j in 1:d2, k in 1:d3]
det3l(f, d1, d2, d3, d4) = [f(i, j, k, l) for i in 1:d1, j in 1:d2, k in 1:d3, l in 1:d4]

const SM_NMASS, SM_NBINS, SM_NENERGY = 2, 2, 3

function sm_slice_fixture(mass; T = Float64, omit_mass = false)
    dat = Dict{Symbol,Any}(
        :nbins        => Int16(SM_NBINS),
        :nenergy      => Int16(SM_NENERGY),
        :nmass        => SM_NMASS,
        :energy       => T.(det3((i, j, k) -> 10.0 * k + 1.0 * j + 0.5 * i, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :denergy      => T.(det3((i, j, k) -> 1.0 + 0.1 * k, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :theta        => T.(det3((i, j, k) -> 15.0 + 7.0 * j + 0.5 * i, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :phi          => T.(det3((i, j, k) -> 25.0 + 11.0 * j + 0.25 * i, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :dtheta       => T.(det3((i, j, k) -> 5.0 + 0.5 * j, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :dphi         => T.(det3((i, j, k) -> 6.0 + 0.25 * j, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :mass_arr     => T.(det3((i, j, k) -> i == 1 ? 1.0 : 16.0, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :gf           => T.(det3((i, j, k) -> 0.5 + 0.05 * k, 1, SM_NBINS, SM_NENERGY)),
        :eff          => T.(det3((i, j, k) -> 0.6 + 0.01 * i, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :geom_factor  => 0.02,
        :time_integ   => 4.0,
        :dead         => T.(det3((i, j, k) -> 1.0 + 0.001 * k, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :bkg          => T.(det3((i, j, k) -> 0.05 * k, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :data         => T.(det3((i, j, k) -> 100.0 + 10.0 * k + i, SM_NMASS, SM_NBINS, SM_NENERGY)),
        :eflux        => T.(det3((i, j, k) -> 3.0 * (1 + i + j + k), SM_NMASS, SM_NBINS, SM_NENERGY)),
        :df_mass_mass => T.(det3((i, j, k) -> 1.0e-3 * (1 + i + j + k), SM_NMASS, SM_NBINS, SM_NENERGY)),
        :sc_pot       => 2.0,
        :valid        => 1,
        :mass         => mass,
    )
    omit_mass && delete!(dat, :mass)
    return dat
end

function sm_all_fixture(mass; nbins, T = Float64, omit_mass = false,
                        ntime = 2, nmass = 2, nenergy = 3, nswp = 2, natt = 2, neff = 2)
    if nbins == 1
        dat = Dict{Symbol,Any}(
            :num_dists   => ntime, :nmass => nmass, :nbins => 1, :nenergy => nenergy,
            :swp_ind     => [0, 1], :att_ind => [0, 1], :eff_ind => [0, 1],
            :energy      => T.(det3((i, j, s) -> 10.0 * s + j, nmass, nenergy, nswp)),
            :mass_arr    => T.(det3((i, j, s) -> i == 1 ? 1.0 : 16.0, nmass, nenergy, nswp)),
            :gf          => T.(det3((a, j, s) -> 0.5 + 0.05 * j, natt, nenergy, nswp)),
            :eff         => T.(det3((i, j, e) -> 0.6 + 0.01 * i, nmass, nenergy, neff)),
            :geom_factor => 0.02,
            :time_integ  => T.([4.0, 4.5]),
            :dead        => T.(det3((t, i, j) -> 1.0 + 0.001 * j, ntime, nmass, nenergy)),
            :bkg         => T.(det3((t, i, j) -> 0.05 * j, ntime, nmass, nenergy)),
            :data        => T.(det3((t, i, j) -> 100.0 + 10.0 * j + t, ntime, nmass, nenergy)),
            :mass        => mass,
        )
    else
        dat = Dict{Symbol,Any}(
            :num_dists   => ntime, :nmass => nmass, :nbins => nbins, :nenergy => nenergy,
            :swp_ind     => [0, 1], :att_ind => [0, 1], :eff_ind => [0, 1],
            :energy      => T.(det3l((i, j, k, s) -> 10.0 * k + j + 0.5 * i, nmass, nbins, nenergy, nswp)),
            :mass_arr    => T.(det3l((i, j, k, s) -> i == 1 ? 1.0 : 16.0, nmass, nbins, nenergy, nswp)),
            :gf          => T.(det3l((a, j, k, s) -> 0.5 + 0.05 * k, natt, nbins, nenergy, nswp)),
            :eff         => T.(det3l((i, j, k, e) -> 0.6 + 0.01 * i, nmass, nbins, nenergy, neff)),
            :geom_factor => 0.02,
            :time_integ  => T.([4.0, 4.5]),
            :dead        => T.(det3l((t, i, j, k) -> 1.0 + 0.001 * k, ntime, nmass, nbins, nenergy)),
            :bkg         => T.(det3l((t, i, j, k) -> 0.05 * k, ntime, nmass, nbins, nenergy)),
            :data        => T.(det3l((t, i, j, k) -> 100.0 + 10.0 * k + t, ntime, nmass, nbins, nenergy)),
            :mass        => mass,
        )
    end
    omit_mass && delete!(dat, :mass)
    return dat
end

function sm_c6_fixture(mass; T = Float64, omit_mass = false, valid = [1, 1],
                       ntime = 2, nmass = 2, nenergy = 3, nswp = 2, natt = 2, neff = 2)
    dat = Dict{Symbol,Any}(
        :num_dists   => ntime, :nmass => nmass, :nenergy => nenergy,
        :nswp        => nswp, :natt => natt, :neff => neff,
        :swp_ind     => [0, 1], :att_ind => [0, 1], :eff_ind => [0, 1],
        :energy      => T.(det3((i, j, s) -> 10.0 * s + j + 0.5 * i, nmass, nenergy, nswp)),
        :denergy     => T.(det3((i, j, s) -> 1.0 + 0.1 * s, nmass, nenergy, nswp)),
        :mass_arr    => T.(det3((i, j, s) -> i == 1 ? 1.0 : 16.0, nmass, nenergy, nswp)),
        :phi         => T.(det3((i, j, s) -> 25.0 + 11.0 * j, nmass, nenergy, nswp)),
        :dphi        => T.(det3((i, j, s) -> 6.0 + 0.25 * j, nmass, nenergy, nswp)),
        :theta       => T.(det3((i, j, s) -> 15.0 + 7.0 * j, nmass, nenergy, nswp)),
        :dtheta      => T.(det3((i, j, s) -> 5.0 + 0.5 * j, nmass, nenergy, nswp)),
        :eff         => T.(det3((i, j, e) -> 0.6 + 0.01 * i, nmass, nenergy, neff)),
        :gf          => T.(det3((a, j, s) -> 0.5 + 0.05 * j, natt, nenergy, nswp)),
        :geom_factor => 0.02,
        :time_integ  => T.([4.0, 4.5]),
        :dead        => T.(det3((t, i, j) -> 1.0 + 0.001 * j, ntime, nmass, nenergy)),
        :bkg         => T.(det3((t, i, j) -> 0.05 * j, ntime, nmass, nenergy)),
        :data        => T.(det3((t, i, j) -> 100.0 + 10.0 * j + t, ntime, nmass, nenergy)),
        :mass        => mass,
        :sc_pot      => T.([2.0, -1.0]),
        :valid       => valid,
    )
    omit_mass && delete!(dat, :mass)
    return dat
end

# ---------------------------------------------------------------------------
# 探针：把各函数输出压成定长向量，便于与改动前基线做逐位比较
# ---------------------------------------------------------------------------
sm_probes(x::AbstractArray) = begin
    y = vec(collect(Float64, x))
    Float64[y[1], y[end], sum(y), sum(abs, y), minimum(y), maximum(y)]
end
sm_probes(x::Real) = Float64[Float64(x)]
sm_probes(v::StaticArrays.SVector{N}) where {N} = sm_probes(collect(v))

sm_relmax(a, b) = maximum(abs.(a .- b) ./ max.(abs.(b), 1e-300))

# 顺序固定；任何顺序改动都会使 == BASELINE_F64 失败，属预期保护。
function sm_all_probes(mass; T = Float64, omit_mass = false)
    out = Float64[]
    kw = (; T = T, omit_mass = omit_mass)

    ret = STA.STA_count2df(sm_slice_fixture(mass; kw...))
    append!(out, sm_probes(ret[:df]))
    append!(out, sm_probes(ret[:df_mass_mass]))
    push!(out, maximum(abs.(ret[:df] .- ret[:df_mass_mass] .* ret[:mass_arr] .^ 2)))

    e = STA.STA_eflux2df(sm_slice_fixture(mass; kw...); m_int = 16)
    append!(out, sm_probes(e[:df]))

    v1, f1, n1 = STA.sta_v_4d(sm_slice_fixture(mass; kw...); mass_range = [0, 40], m_int = 16)
    append!(out, sm_probes(v1)); append!(out, sm_probes(f1)); push!(out, Float64(n1))

    v2, f2, n2 = STA.sta_v_4d(sm_slice_fixture(mass; kw...); mass_range = [0, 40], m_int = 16, unit_cover = false)
    append!(out, sm_probes(v2)); append!(out, sm_probes(f2)); push!(out, Float64(n2))

    push!(out, Float64(STA.sta_n_4d(sm_slice_fixture(mass; kw...); mass_range = [0, 40], m_int = 16)))
    push!(out, Float64(STA.sta_n_4d(sm_slice_fixture(mass; kw...); mass_range = [0, 40], m_int = 16, unit_cover = true)))

    for nb in (1, 2)
        y = STA.STA_count2df_all(sm_all_fixture(mass; nbins = nb, kw...))
        append!(out, sm_probes(y[:df])); append!(out, sm_probes(y[:df_mass_mass]))
    end

    z = STA.STA_count3df(sm_c6_fixture(mass; kw...))
    append!(out, sm_probes(z[:df])); append!(out, sm_probes(z[:df_mass_mass]))

    w = STA.STA_count3df(sm_c6_fixture(mass; kw...))
    v3, f3, n3 = STA.sta_v_1d(w; mass_range = [0, 40], m_int = 16)
    append!(out, sm_probes(v3)); append!(out, sm_probes(f3)); append!(out, sm_probes(n3))

    return out
end

# 捕获函数内的 println（"Invalid Data"），基线实测 stdout 恰为 "Invalid Data\n"
function sm_capture_stdout(f)
    old = stdout
    rd, wr = redirect_stdout()
    res = try
        f()
    finally
        redirect_stdout(old)
        close(wr)
    end
    return res, read(rd, String)
end

@testset "STATIC 质量基准回归（dat[:mass] → constants.mp_eV_per_km_s2）" begin
    @testset "质量基准与探针基线自检" begin
        @test MP isa Float64
        @test MP == 1.67262192e-27 * 1e6 / 1.602176634e-19
        # Float32 基准本身有损：改动前实测相对差 2.6560460581326496e-8
        @test Float32(MP) != MP
        @test abs(Float64(Float32(MP)) - MP) / MP == MEASURED_BASIS_F32_REL
        # 改动前实测：Float32 质量基准与 Float64 同值基准的输出最大相对差 7.068977758535884e-8
        @test length(BASELINE_F64) == length(BASELINE_F32) == 101
        @test sm_relmax(BASELINE_F32, BASELINE_F64) == MEASURED_F32_VS_F64_MAX_REL
        @test count(!isequal(0.0), BASELINE_F32 .- BASELINE_F64) == 100
        # 该差异量级由质量基准本身的相对差决定（10 倍余量）
        @test MEASURED_F32_VS_F64_MAX_REL <= 10 * MEASURED_BASIS_F32_REL
    end

    @testset "改动后：Float64 同值基准与改动前逐位一致（exact）" begin
        @test length(sm_all_probes(Float64(MP))) == 101
        @test sm_all_probes(Float64(MP)) == BASELINE_F64
        @test sm_all_probes(Float64(MP)) == sm_all_probes(Float64(MP))   # 确定性
    end

    @testset "改动后：不再依赖 dat[:mass]（Float32 / 异值 / 缺失 / Float32 数组夹具）" begin
        # 改动前这三个用例分别给出 BASE_F32、与 BASE_F64 差 2.0e-4、KeyError(:mass)
        @test sm_all_probes(Float32(MP)) == BASELINE_F64
        @test sm_all_probes(Float64(MP) * 1.0001) == BASELINE_F64
        @test sm_all_probes(Float64(MP); omit_mass = true) == BASELINE_F64

        # Float32 数组夹具：旧 sta_v_4d_new 的 ::Float32 断言已随函数删除，此处不得再抛类型错误；
        # 数组精度本身不同，故不与 BASELINE_F64 比较，只验证“与质量键无关”与确定性。
        p32 = sm_all_probes(Float32(MP); T = Float32)
        @test length(p32) == 101
        @test all(isfinite, p32)
        @test p32 == sm_all_probes(Float32(MP); T = Float32)
        @test p32 == sm_all_probes(Float64(MP) * 1.0001; T = Float32)
        @test p32 == sm_all_probes(Float64(MP); T = Float32, omit_mass = true)
    end

    @testset "sta_v_4d_new 旧实现已删除、无兼容分支" begin
        @test !isdefined(STA, :sta_v_4d_new)
        @test !any(n -> occursin("sta_v_4d_new", String(n)), names(STA; all = true))
        @test isdefined(STA, :sta_v_4d)
    end

    @testset "STA_count2df：同对象就地修改、df 与 df_mass_mass 关系、缺键可用" begin
        d = sm_slice_fixture(Float64(MP))
        ret = STA.STA_count2df(d)
        @test ret === d                       # 无 `!` 但返回同一对象（AR-9 约定）
        @test haskey(d, :df) && haskey(d, :df_mass_mass)
        @test d[:df] == d[:df_mass_mass] .* d[:mass_arr] .^ 2    # 同函数内同一次广播，逐位成立
        @test maximum(abs.(d[:df] .- d[:df_mass_mass] .* d[:mass_arr] .^ 2)) == 0.0

        d2 = sm_slice_fixture(Float64(MP); omit_mass = true)
        ret2 = STA.STA_count2df(d2)
        @test ret2 === d2
        @test d2[:df] == d[:df] && d2[:df_mass_mass] == d[:df_mass_mass]

        d3 = sm_slice_fixture(Float64(MP) * 3.0)   # 异值质量键不得影响结果
        @test STA.STA_count2df(d3)[:df] == d[:df]
    end

    @testset "STA_count2df_all：nbins==1 与 nbins>1 两分支（基准² 与 基础×mass_arr 分离）" begin
        for nb in (1, 2)
            x = sm_all_fixture(Float64(MP); nbins = nb)
            y = STA.STA_count2df_all(x)
            @test y !== x                                   # 内部 deepcopy，原字典不被注入
            @test !haskey(x, :df) && !haskey(x, :df_mass_mass)
            @test haskey(y, :df) && haskey(y, :df_mass_mass)
            @test size(y[:df]) == size(y[:df_mass_mass])

            m = y[:df] ./ y[:df_mass_mass]
            @test all(m .> 0)
            @test all(isfinite, m)

            # df / df_mass_mass = (基准 × 逐道 mass_arr / 基准)² = 映射后的 mass_arr²
            mapped = nb == 1 ?
                     [x[:mass_arr][i, j, x[:swp_ind][t] + 1] for t in 1:2, i in 1:2, j in 1:3] :
                     [x[:mass_arr][i, j, k, x[:swp_ind][t] + 1] for t in 1:2, i in 1:2, j in 1:2, k in 1:3]
            @test y[:df] ≈ y[:df_mass_mass] .* mapped .^ 2 rtol = 1e-12

            xm = sm_all_fixture(Float64(MP); nbins = nb, omit_mass = true)
            ym = STA.STA_count2df_all(xm)
            @test ym[:df] == y[:df] && ym[:df_mass_mass] == y[:df_mass_mass]
        end
    end

    @testset "STA_eflux2df / sta_n_4d：缺键可用且与同值键一致" begin
        @test STA.STA_eflux2df(sm_slice_fixture(Float64(MP)); m_int = 16)[:df] ==
              STA.STA_eflux2df(sm_slice_fixture(Float64(MP); omit_mass = true); m_int = 16)[:df]
        for cover in (false, true)
            @test STA.sta_n_4d(sm_slice_fixture(Float64(MP)); mass_range = [0, 40], m_int = 16, unit_cover = cover) ==
                  STA.sta_n_4d(sm_slice_fixture(Float64(MP); omit_mass = true); mass_range = [0, 40], m_int = 16, unit_cover = cover)
        end
    end

    @testset "sta_v_4d：有效输入数值、无效输入 Invalid Data 与全 NaN" begin
        d = sm_slice_fixture(Float64(MP))
        vel, flux, den = STA.sta_v_4d(d; mass_range = [0, 40], m_int = 16)
        @test vel isa SVector{3}
        @test flux isa SVector{3}
        @test all(isfinite, vel) && all(isfinite, flux) && isfinite(den)
        @test den > 0
        # unit_cover=false 与 true 都是同一物理量的两条路径，均须可用
        vel2, flux2, den2 = STA.sta_v_4d(sm_slice_fixture(Float64(MP)); mass_range = [0, 40], m_int = 16, unit_cover = false)
        @test all(isfinite, vel2) && all(isfinite, flux2) && isfinite(den2)

        bad = sm_slice_fixture(Float64(MP)); bad[:valid] = 0
        res, text = sm_capture_stdout(() -> STA.sta_v_4d(bad; mass_range = [0, 40], m_int = 16))
        @test text == "Invalid Data\n"
        @test all(isnan, res[1]) && all(isnan, res[2]) && isnan(res[3])

        bad2 = sm_slice_fixture(Float64(MP); omit_mass = true); bad2[:valid] = 0
        res2, text2 = sm_capture_stdout(() -> STA.sta_v_4d(bad2; mass_range = [0, 40], m_int = 16))
        @test text2 == "Invalid Data\n"
        @test all(isnan, res2[1]) && isnan(res2[3])
    end

    @testset "STA_count3df / sta_v_1d：缺键可用、valid=0 的 NaN 位置保留" begin
        z = STA.STA_count3df(sm_c6_fixture(Float64(MP)))
        @test haskey(z, :df) && haskey(z, :df_mass_mass)
        @test z[:df] ≈ z[:df_mass_mass] .* z[:mass_arr3d] .^ 2 rtol = 1e-12

        z0 = STA.STA_count3df(sm_c6_fixture(Float64(MP); omit_mass = true))
        @test z0[:df] == z[:df] && z0[:df_mass_mass] == z[:df_mass_mass]

        w = STA.STA_count3df(sm_c6_fixture(Float64(MP); valid = [0, 1]))
        v, f, n = STA.sta_v_1d(w; mass_range = [0, 40], m_int = 16)
        @test isnan(v[1]) && isnan(f[1]) && isnan(n[1])          # NaN 位置与输入 valid 对应
        @test isfinite(v[2]) && isfinite(f[2]) && isfinite(n[2])

        w0 = STA.STA_count3df(sm_c6_fixture(Float64(MP); valid = [0, 1], omit_mass = true))
        v0, f0, n0 = STA.sta_v_1d(w0; mass_range = [0, 40], m_int = 16)
        @test isnan(v0[1]) && isnan(f0[1]) && isnan(n0[1])
        @test v0[2] == v[2] && f0[2] == f[2] && n0[2] == n[2]
    end
end
