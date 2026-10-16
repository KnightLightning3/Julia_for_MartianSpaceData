using BenchmarkTools
using Random
using LinearAlgebra
using Statistics

# ============================================================================
# models/test_trace.jl —— 合并后的纯 Julia 磁力线追踪测试（models/IGRF_calculate.jl）
#
# 变化说明（本次按批注合并）：
#   * 模块只有一份：M = IGRF_calculate（纯 Julia，无 Fortran/DLL）。
#   * trace_mag_line 默认方法 = :dp5；:euler 保留但改用纯 Julia 内核；
#     :rk4 / :adaptive 随 Fortran RK4_STEP 与 ADAPTIVE_STEP_TRACE 一并移除。
#   * 合并前的 Euler "pc" 逐位回归（对 IGRF_new2 的 Fortran 内核）已由
#     tmp/verify_merge.jl 完成并记录：改用纯 Julia 内核后，同一条线 2092 行
#     的位置最大偏差 5.1e-13 km（见交接文档 §5）。
# ============================================================================

include("IGRF_calculate.jl");  M = IGRF_calculate
M.set_B_compress([0.0, 0.0, 0.0])

const R_MARS = Float64(M.constants.R_Mars)
const STEP = 0.5          # 输出弧长间隔 (km)
const REF_STEP = 0.05     # 参考线的输出间隔：折线弦高误差 ≈ κ·ℓ²/8，ℓ 取小才不会盖过 xtol
const MAXROWS = 3000      # 每个方向最多 3000 行 → 弧长 ≤ 1500 km
const S_CAP = 1400.0      # 只在距起点 1400 km 内比较，保证落在参考线覆盖范围内

println("线程数 = ", Threads.nthreads(), "  （批量并行测试需用 julia -t auto 启动）")

# ---------------------------------------------------------------- 工具函数
trace_with(start, method; kwargs...) =
    M.trace_mag_line(start[1], start[2], start[3]; method=method, input_frame="pc", output_frame="pc", kwargs...)

"在高度 alt（km）范围内随机生成 n 个笛卡尔起点（避开极轴附近）。"
function random_starts(n; alt=(100.0, 500.0), seed=2024)
    rng = MersenneTwister(seed)
    starts = NTuple{3,Float64}[]
    for _ in 1:n
        r = R_MARS + alt[1] + (alt[2] - alt[1]) * rand(rng)
        θ = acos(0.9 * (2 * rand(rng) - 1))
        ϕ = -π + 2π * rand(rng)
        push!(starts, M.sphere2pc(r, θ, ϕ))
    end
    return starts
end

"点 p 到线段 ab 的距离。"
@inline function seg_dist(px, py, pz, ax, ay, az, bx, by, bz)
    abx = bx - ax; aby = by - ay; abz = bz - az
    apx = px - ax; apy = py - ay; apz = pz - az
    L2 = abx^2 + aby^2 + abz^2
    t = L2 > 0 ? clamp((apx * abx + apy * aby + apz * abz) / L2, 0.0, 1.0) : 0.0
    dx = apx - t * abx; dy = apy - t * aby; dz = apz - t * abz
    return sqrt(dx^2 + dy^2 + dz^2)
end

"""
    line_deviation(pos, i0, refpos, j0, ref_step; win_km=100.0, s_cap=S_CAP) -> (dmax, drms)

测试线 `pos`（N×3，笛卡尔，km）上每个点到参考折线 `refpos` 的最短距离（点到线段，只在沿线弧长相近的窗口内搜索）。
`i0`、`j0` 分别是两条线中起点所在的行号。度量的是垂直于磁力线方向的几何偏差，与沿线取样位置无关。
"""
function line_deviation(pos, i0, refpos, j0, ref_step; win_km=100.0, s_cap=S_CAP)
    n = size(pos, 1)
    m = size(refpos, 1)
    win = round(Int, win_km / ref_step)
    s = zeros(n)
    for i in 2:n
        s[i] = s[i-1] + sqrt((pos[i, 1] - pos[i-1, 1])^2 + (pos[i, 2] - pos[i-1, 2])^2 + (pos[i, 3] - pos[i-1, 3])^2)
    end
    s .-= s[i0]
    dmax = 0.0
    dsum2 = 0.0
    cnt = 0
    for i in 1:n
        abs(s[i]) > s_cap && continue
        jg = j0 + round(Int, s[i] / ref_step)
        lo = clamp(jg - win, 1, m - 1)
        hi = clamp(jg + win, 1, m - 1)
        d = Inf
        for j in lo:hi
            d = min(d, seg_dist(pos[i, 1], pos[i, 2], pos[i, 3],
                refpos[j, 1], refpos[j, 2], refpos[j, 3],
                refpos[j+1, 1], refpos[j+1, 2], refpos[j+1, 3]))
        end
        dmax = max(dmax, d)
        dsum2 += d^2
        cnt += 1
    end
    return dmax, sqrt(dsum2 / max(cnt, 1))
end

function serial_loop!(f!, ws, out, rs, θs, ϕs)
    @inbounds for i in eachindex(rs)
        out[i] = f!(ws, rs[i], θs[i], ϕs[i])
    end
    return out
end

sig3(x) = round(x; sigdigits=3)

starts = random_starts(6)

# ---------------------------------------------------------------- 0. 默认方法、输出系、已移除的方法
println("\n==== 0. 默认方法 / 输出系 / 已移除的 Fortran 方法 ====")
let st = starts[1]
    res = M.trace_mag_line(st[1], st[2], st[3]; input_frame="pc", output_frame="pc", max_trace=MAXROWS)
    @assert res[:method] === :dp5 "trace_mag_line 默认方法不是 :dp5"
    println("默认方法（不传 method）= ", res[:method], " ✓")

    for m in (:rk4, :adaptive)
        threw = try
            M.trace_mag_line(st[1], st[2], st[3]; method=m, max_trace=10)
            false
        catch e
            e isa ArgumentError
        end
        @assert threw "method=:$m 未按预期抛 ArgumentError（Fortran 内核已移除）"
    end
    println(":rk4 / :adaptive 已随 Fortran 内核移除，均抛 ArgumentError ✓")

    rs = M.trace_mag_line(st[1], st[2], st[3]; method=:dp5, input_frame="pc", output_frame="sph", max_trace=MAXROWS)
    rp = M.trace_mag_line(st[1], st[2], st[3]; method=:dp5, input_frame="pc", output_frame="pc", max_trace=MAXROWS)
    P = rs[:position]
    n = size(P, 1)
    @assert rs[:num_steps] == n == size(rp[:position], 1) "球坐标输出的 :num_steps 不对"
    ok = all(M.sphere2pc(P[i, 1], P[i, 2], P[i, 3]) == (rp[:position][i, 1], rp[:position][i, 2], rp[:position][i, 3]) for i in 1:n)
    @assert ok "球坐标输出转笛卡尔后与 \"pc\" 输出不一致"
    println("output_frame=\"sph\" 可用，:num_steps = ", rs[:num_steps], "，与 \"pc\" 输出逐位一致 ✓")

    re = M.trace_mag_line(st[1], st[2], st[3]; method=:euler, input_frame="pc", output_frame="pc", max_trace=MAXROWS)
    @assert re[:method] === :euler && size(re[:position], 1) > 1 "method=:euler 不可用"
    println("method=:euler（纯 Julia 内核）仍可用，行数 = ", size(re[:position], 1), " ✓")
end

# ---------------------------------------------------------------- 1. 不变量与边界情形
println("\n==== 1. 不变量与边界情形 ====")
let st = starts[1]
    res = trace_with(st, :dp5; step=STEP, max_trace=MAXROWS)
    pos = res[:position]
    B = res[:B]
    i0 = res[:start_position]
    n = size(pos, 1)
    chords = [norm(pos[i+1, :] - pos[i, :]) for i in 1:n-1]
    println("行数 = ", n, "，起点行 = ", i0)
    println("相邻点弦长与 step 的最大偏差 = ", sig3(maximum(abs.(chords .- STEP))), " km（期望 ≲ 1e-2）")
    println("起点与输入点的距离 = ", sig3(norm(pos[i0, :] .- collect(st))), " km（期望 ≈ 0）")
    @assert maximum(abs.(chords .- STEP)) < 0.02 "弦长与输出间隔不符：检查稠密输出或步长控制"
    @assert norm(pos[i0, :] .- collect(st)) < 1e-6 "起点行与输入起点不一致"
    @assert all(isfinite, pos) && all(isfinite, B) "输出含 NaN/Inf"
end
let pole = (0.0, 0.0, R_MARS + 300.0)      # 恰在极轴上
    res = trace_with(pole, :dp5; step=STEP, max_trace=MAXROWS)
    println("极轴起点：行数 = ", size(res[:position], 1), "，全部有限 = ", all(isfinite, res[:position]) && all(isfinite, res[:B]))
    @assert all(isfinite, res[:position]) && all(isfinite, res[:B]) "极轴起点产生 NaN/Inf"
end

# ---------------------------------------------------------------- 2. 精度对比
println("\n==== 2. 精度：到高精度参考线（xtol=1e-8, hmax=2, 间隔 0.05 km）的几何偏差 ====")
entries = [
    ("Euler 0.5 km", :euler, (;)),
    ("DP5 xtol=1e-2", :dp5, (xtol=1e-2,)),
    ("DP5 xtol=1e-3", :dp5, (xtol=1e-3,)),
    ("DP5 xtol=1e-4", :dp5, (xtol=1e-4,)),
]
dmax = zeros(length(entries))
drms = zeros(length(entries))
nrows = zeros(Int, length(entries))
refs = Tuple{NTuple{3,Float64},Matrix{Float64},Int}[]
for st in starts
    ref = trace_with(st, :dp5; step=REF_STEP, max_trace=30000, xtol=1e-8, hmax=2.0)
    refpos = ref[:position]
    j0 = ref[:start_position]
    push!(refs, (st, refpos, j0))
    for (k, (name, m, kw)) in enumerate(entries)
        res = trace_with(st, m; step=STEP, max_trace=MAXROWS, kw...)
        d, rms = line_deviation(res[:position], res[:start_position], refpos, j0, REF_STEP)
        dmax[k] = max(dmax[k], d)
        drms[k] += rms / length(starts)
        nrows[k] += size(res[:position], 1)
    end
end
println(rpad("方法", 18), rpad("最大偏差 km", 14), rpad("均方根偏差 km", 16), "总行数")
for (k, (name, m, kw)) in enumerate(entries)
    println(rpad(name, 18), rpad(string(sig3(dmax[k])), 14), rpad(string(sig3(drms[k])), 16), nrows[k])
end
@assert dmax[3] < 0.01 "DP5 (xtol=1e-3) 偏差过大"

# ---------------------------------------------------------------- 3. 单线性能
println("\n==== 3. 单条磁力线性能（取行数最多的一条）====")
nlong = [size(trace_with(st, :dp5; max_trace=30000)[:position], 1) for st in starts]
st_long = starts[argmax(nlong)]
println("所选起点的磁力线行数 = ", maximum(nlong))
print("Euler (纯 Julia 内核)     : "); @btime trace_with($st_long, :euler; max_trace=30000)
print("DP5 默认（串行输出）      : "); @btime trace_with($st_long, :dp5; max_trace=30000)
print("DP5 单线并行输出          : "); @btime trace_with($st_long, :dp5; max_trace=30000, threaded_output=true, thread_min=1)
print("DP5 step=5 km（稀疏输出） : "); @btime trace_with($st_long, :dp5; step=5.0, max_trace=30000)

# ---------------------------------------------------------------- 4. hmax 扫描（稀疏输出时积分本身占主导）
println("\n==== 4. hmax 扫描（step=5 km，xtol=1e-3）====")
println(rpad("hmax km", 10), rpad("最大偏差 km", 14), "耗时 ms（最长那条线）")
for hmax in (25.0, 50.0, 100.0)
    dm = 0.0
    for (st, refpos, j0) in refs
        res = trace_with(st, :dp5; step=5.0, max_trace=MAXROWS, hmax=hmax)
        d, _ = line_deviation(res[:position], res[:start_position], refpos, j0, REF_STEP)
        dm = max(dm, d)
    end
    tt = @belapsed trace_with($st_long, :dp5; step=5.0, max_trace=30000, hmax=$hmax)
    println(rpad(string(hmax), 10), rpad(string(sig3(dm)), 14), sig3(1e3 * tt))
end

# ---------------------------------------------------------------- 5. 多条磁力线批量
println("\n==== 5. 批量追踪（trace_mag_lines，每条线一个任务）====")
many = random_starts(256; seed=5)
serial_lines(ss) = [trace_with(s, :dp5; max_trace=30000) for s in ss]
serial_lines(many[1:2])                    # 预热
M.trace_mag_lines(many[1:2]; max_trace=30000)
t0 = time(); serial = serial_lines(many); t_serial = time() - t0
t0 = time(); batch = M.trace_mag_lines(many; max_trace=30000); t_batch = time() - t0
same = all(batch[i][:position] == serial[i][:position] && batch[i][:B] == serial[i][:B] for i in eachindex(batch))
println("256 条磁力线：串行 = ", sig3(t_serial), " s，多线程 = ", sig3(t_batch), " s，加速 = ", sig3(t_serial / t_batch), "×")
println("总行数 = ", sum(size(d[:position], 1) for d in batch), "；多线程与串行逐位一致 = ", same)
@assert same "批量结果与串行不一致"
t0 = time()
for s in many[1:8]
    trace_with(s, :euler; max_trace=30000)
end
t_eu = time() - t0
println("对照：Euler(纯 Julia) 追踪 8 条 = ", sig3(t_eu), " s（折合每条 ", sig3(t_eu / 8), " s；DP5 批量折合每条 ", sig3(t_batch / 256), " s）")

# ---------------------------------------------------------------- 6. IGRF_batch! 开销扫描与正确性
println("\n==== 6. IGRF_batch! 开销扫描（每个任务至少 min_chunk 个点；mc=1 = 总是拆成 nthreads 块）====")
println("    注：合并前串行早退分支的 ws 会被所有 @spawn 闭包捕获（共用工作区）⇒ 结果错误且耗时虚高；")
println("        本次已修复（改名 ws_serial），下表结果必须与串行逐位一致。")
ws = M.IGRFWorkspace()
f! = M.IGRF!
mcs = (1, 64, 256, 1024)
println(rpad("点数", 9), rpad("串行 ms", 11), join([rpad("mc=" * string(mc) * " ms", 13) for mc in mcs]), "逐位一致")
for n in (500, 2000, 10000, 50000)
    rng = MersenneTwister(n)
    rs = [R_MARS + 500.0 * rand(rng) for _ in 1:n]
    θs = [0.2 + (π - 0.4) * rand(rng) for _ in 1:n]
    ϕs = [-π + 2π * rand(rng) for _ in 1:n]
    out = Vector{NTuple{4,Float64}}(undef, n)
    out_ref = similar(out)
    serial_loop!(f!, ws, out_ref, rs, θs, ϕs)
    ts = @belapsed serial_loop!($f!, $ws, $out_ref, $rs, $θs, $ϕs)
    cols = String[]
    ok = true
    for mc in mcs
        tp = @belapsed M.IGRF_batch!($out, $rs, $θs, $ϕs; min_chunk=$mc)
        ok &= (out == out_ref)
        push!(cols, rpad(string(sig3(1e3 * tp)), 13))
    end
    @assert ok "n=$n 时 IGRF_batch! 结果与串行不一致"
    println(rpad(string(n), 9), rpad(string(sig3(1e3 * ts)), 11), join(cols), ok)
end
