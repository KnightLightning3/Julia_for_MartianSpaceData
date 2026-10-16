# IGRF 纯 Julia 化与磁力线追踪改造 · 修改报告

> **当前使用说明（2026-10-16 复核）：** 正式实现为 `models/IGRF_calculate.jl`，测试入口为 `models/test.jl` 和 `models/test_trace.jl`。默认追踪方法已按批注改为 `:dp5`，保留纯 Julia `:euler`，已移除 Fortran RK4/自适应追踪分支。§1～§9 保留为 Claude 阶段历史记录，其中“未解决”“默认 Euler”“等待审批”不代表当前状态。`IGRF_new*.jl` 是历史快照，特别是 new3 仍含旧数据竞争，不应作为生产入口。此前接手记录见 §10，本次独立复测与工作区隔离加固见 §11。

生成日期：2026-10-16　｜　交接对象：负责整理与推送的接手 AI

## 1. 结论

- **目标达成。** 纯 Julia 球谐内核单点 4.7～5.1 μs，约为 Fortran dll（18.0～18.6 μs）的 1/3.6～1/3.8；稳态零分配；`B_compress` 项与全部偏导已补齐，可替代 dll 做场值与导数计算。
- **新增纯 Julia 磁力线追踪器（Dormand–Prince 5(4)）。** 几何偏差比 Euler 小约 3 个数量级（最大 8.0e-4 km 对 0.858 km）；4500 行单条线 25.1 ms（Euler 80.2 ms）；256 条线多线程 0.273 s。
- **默认行为未变。** `trace_mag_line` 默认仍是 `:euler`，其 `"pc"` 输出与改动前逐位一致（回归已通过）。是否把默认方法改为 `:dp5` 需按项目流程由科学负责人批准，本次未改。批注：同意修改，也要同步其他地方的说明
- **一个未决问题：** `IGRF_batch!` 两次实测耗时互相矛盾（见 §7.1）。相关默认已设为关闭，不阻塞推送。批注：尝试使用实际环境进行测试，找出原因
- **验证范围说明：** 所有 Julia 代码均由用户在 Windows、64 线程环境实际运行验证（Julia 版本据外部报告为 1.10.0）。作者（Claude）的沙箱里没有 Julia，只用 Python/C 镜像实现验证了算法，没有执行过任何 Julia 代码。

## 2. 交付文件与版本关系

| 文件 | 模块名 | 角色 | 说明 |
| --- | --- | --- | --- |
| `IGRF_new3.jl` | `IGRF_calculate_new3` | **最终候选** | 包含全部改动（阶段 0～4） |
| `test_trace_new3.jl` | — | 追踪器测试 | 第 0～5 节为通过条件；第 6 节仅为诊断 |
| `test_IGRF_new2.jl` | — | 场值/导数/批量测试 | 加载 `IGRF_calculate.jl`、`IGRF_new.jl`、`IGRF_new2.jl`；内核与 new3 相同（外部报告已验证 new2 与 new3 内核四元组逐位一致） |
| `IGRF_new2.jl` | `IGRF_calculate_new2` | 中间版 | 阶段 3 内核，不含追踪器；`test_trace_new3.jl` 用它的 `:euler` 路径做逐位回归基线 |
| `IGRF_new.jl` | `IGRF_calculate_new` | 中间版 | 阶段 2 |
| `IGRF_calculate_step1.jl`、`IGRF_calculate_const.jl` | — | 中间版 | 阶段 1、阶段 0，仅作记录，不建议提交 |
| 作者沙箱里更早的 `IGRF_calculate.jl` | — | **作废** | 基于旧架构，勿使用；以用户仓库里的 `IGRF_calculate.jl` 为基线 |

注意事项：

- 文件均为 **CRLF** 行尾，提交时请保持，避免整文件 diff。
- 当前校验和（md5）：`IGRF_new3.jl` = `cd512fe4c49c9a4fc145858daa73245b`；`test_trace_new3.jl` = `1a00728dece0e7cfaef0e56423abb7b5`；`test_IGRF_new2.jl` = `325e7b8ae18be21c2c16e2fbc38b4e82`；`IGRF_new2.jl` = `bb01343162601c5ccfa21333f40264ea`；`IGRF_new.jl` = `3be4b64bbb26cb268a01c6e803f3eb32`。

## 3. 改动清单（按阶段，全部包含在 `IGRF_new3.jl` 中）

**阶段 0：常数化。**

- `NIGRF`、`IGRF_DLL_PATH`、`GG/HH`、`SS/REALK` 在用户的新架构文件里已是 `const`；本次补上 `root_dir`、`gh_filename`。
- `B_compress` 改为 `const B_compress = zeros(3)`；`set_B_compress` 改为原地 `.=`，增加长度必须为 3 的检查，返回模块里的 `B_compress`（拷贝语义，不再与调用方传入的向量共用内存）。

**阶段 1：滚动缓冲。** 勒让德函数 P/DP 只保留滚动的三行（N-2、N-1、N 阶），`AARR` 表改为逐阶乘 `(AA/r)` 的标量。每次调用分配从约 195 KiB 降到约 7 KiB，数值与整矩阵版逐位一致。

**阶段 2：派生系数表与 SIMD。**

- 新增 `GS_T = SS.*GG`、`HS_T = SS.*HH`、`REALK_T`（`M` 连续布局，下标 `[M+1, N+1]`）与 `MFLOAT`；新增 `rebuild_derived_tables!()`（模块加载时调用一次）。
- 内层循环用 `@simd ivdep`（递推）和 `@simd`（归约）。预乘与归约重排使结果不再与上一版逐位一致。
- 传给 Fortran 的 `GG/HH/SS/REALK` 保持原布局不变。

**阶段 3：工作区、导数、B\_compress、三角递推。**

- `IGRFWorkspace`（11 个预分配缓冲区）；`IGRF!(ws, r, θ, ϕ)` 稳态零分配，返回 `(BR, BT, BP, BB)`，并包含 `B_compress` 均匀场项。
- `IGRF_dB!` / `IGRF_dB`：返回与 Fortran `IGRF_for_RK4_dB` 对应的 20 个字段的 NamedTuple（B 三分量、方向导数 `DRDS/DTDS/DPDS`、`DBBDRR/DBBDTH/DBBDPH`、`DB`、9 个偏导）。
- `IGRF(r, θ, ϕ)` 保留为便捷接口（每次临时创建工作区）。
- `IGRF_batch!` / `IGRF_batch`：多线程批量求值，新增 `min_chunk` 参数；点数不足两块时直接串行。
- `cos(mϕ)/sin(mϕ)` 改为每 8 项刷新一次的分块递推，锚点用 `fma` 补偿 `m*ϕ` 的舍入误差（`_fill_trig!`）。

**阶段 4：磁力线追踪。**

- `mag_trace_dp5`：笛卡尔坐标、弧长参数化、Dormand–Prince 5(4)（FSAL）、四阶稠密输出，按弧长间隔 `step` 输出，输出点磁场再用 `IGRF!` 精确求值。参数 `xtol`（单步位置误差容限，km）、`hmax`、`h0`、`threaded_output`（默认 `false`）、`thread_min`。
- `trace_mag_line(...; method=:dp5)`：新增方法分支和关键字 `xtol`、`hmax`、`threaded_output`、`thread_min`；`trace_mag_lines`：每条线一个任务的多线程批量追踪（仅支持 `:dp5`）。
- 起点或中途点落在极轴时 θ 夹到 `[1e-8, π-1e-8]`（位置偏移约 3 cm），避免 `1/sinθ` 除零。
- **缺陷修复：** `output_frame != "pc"` 时 `mag_line_num` 未定义导致 `UndefVarError`（原文件即有，外部 AI 报告独立复现）。现在在分支前统一赋值。
- **性能修复：** `tracer` 是几种闭包的并集，导致 `trace_mag_line` 后处理循环类型不稳定（每行约 28 次分配）。加了 `::Matrix{Float64}` 断言并去掉逐行临时向量，调用的函数和实参未变，`"pc"` 输出逐位不变。

## 4. 行为与兼容性变化

| 项目 | 变化 | 需要注意 |
| --- | --- | --- |
| `trace_mag_line` 默认方法 | 不变（`:euler`） | 改默认方法需科学负责人批准 批注：批准修改 |
| Euler `"pc"` 输出 | 与改动前逐位一致 | 回归断言：`test_trace_new3.jl` 第 0 节 |
| `output_frame="sph"` | 之前会崩溃，现在可用 | `:num_steps` 对任意输出系都有定义 |
| 纯 Julia `IGRF` | 现在包含 `B_compress` 项 | 与旧版相差约 1e-14～1e-13（相对 \|B\|），不再逐位一致 |
| `set_B_compress` | 拷贝语义、长度检查 | 外部若重新赋值 `IGRF_calculate.B_compress` 会报错，应改调本函数 |
| `GG/HH` 原地更新 | 需调用 `rebuild_derived_tables!()` | 否则纯 Julia `IGRF` 仍用旧系数；Fortran 路径不受影响 |
| 线程安全 | 批量期间不要修改 `B_compress`；Fortran 方法（`:euler/:rk4/:adaptive`）未确认线程安全 | `trace_mag_lines` 只支持 `:dp5` |
| 输出的 `ϕ` | DP5 输出已折叠到 `(-π, π]` | Euler 版的 `ϕ` 是累加的，转笛卡尔后一致 |

新增名称均未加入 `export`：`IGRFWorkspace`、`IGRF!`、`IGRF_dB!`、`IGRF_dB`、`IGRF_batch!`、`IGRF_batch`、`rebuild_derived_tables!`、`mag_trace_dp5`、`trace_mag_lines`。

## 5. 验证证据

**5.1 场值与导数（用户实测）。** 相对误差均指最大分量误差除以该点总场强 |B|。

| 检查 | 结果 |
| --- | --- |
| 与原始 Julia（一般 ϕ） | 9.05e-14 |
| 与 Fortran（一般 ϕ） | 8.77e-14 |
| 与 Fortran（ϕ 取 1/1024 整数倍，`M*ϕ` 精确） | 2.62e-14 |
| `B_compress=[12,-7,5]` 与 Fortran | 2.04e-14 |
| `DB` 与 Fortran `RK4_STEP`（100 点） | 最大相对误差 1.81e-14 |
| Jacobian 四阶中心差分检验（∂r、∂θ、∂ϕ） | 1.53e-9、3.19e-10、2.15e-10（阈值 1e-8） |
| `IGRF!`、`IGRF_dB!` 稳态分配 | 0 字节 |
| 2 万点批量与串行 | 逐位一致 |

说明：

- 一般 ϕ 的 9e-14 主要来自参考实现（Fortran/原始 Julia）用 `cos(M*ϕ)` 直接求值，大 m 时乘积本身带约 3e-14 弧度的相位舍入；取 ϕ 为二进制精确值后差异降到 2e-14。残余的 2e-14 来源未再追查，推测为求和顺序与抵消，未验证。
- 外部 AI 报告独立复核（B 对 Fortran 7.2e-14，`DB` 3.98e-15，Jacobian 3.17e-9/4.55e-10/6.46e-10，零分配，批量逐位一致），与上表无矛盾。

**5.2 追踪器精度（用户实测）。** 到高精度参考线（同一积分器，`xtol=1e-8`、`hmax=2`、间隔 0.05 km）的垂直几何偏差，6 条线，各取 1400 km 内的点：

| 方法 | 最大偏差 km | 均方根偏差 km |
| --- | --- | --- |
| Euler 0.5 km | 0.858 | 0.229 |
| DP5 `xtol=1e-2` | 7.99e-4 | 4.83e-5 |
| DP5 `xtol=1e-3` | 7.99e-4 | 4.83e-5 |
| DP5 `xtol=1e-4` | 2.88e-4 | 2.45e-5 |

不变量：相邻点弦长与 `step` 最大偏差 3.72e-5 km；起点行与输入点相差 2.3e-13 km；极轴起点输出全部有限。

**5.3 作者的镜像验证（Python/C，仅合成场，不是 Julia 运行）。**

- DOPRI5 系数与稠密输出：非线性 ODE 上的收敛测试，局部误差按 h⁶、误差估计按 h⁵、稠密输出按 h⁵ 收敛。
- 追踪算法对照 scipy DOP853（rtol 1e-13）：12 条线上 Euler 偏差 0.07～1.7 km，DP5 偏差 2e-5～6e-3 km。
- 近地表（3 km、15 km 起点）与极区起点：无 NaN。
- Fortran 导数公式用有限差分确认确为 B 对 r、θ、ϕ 的偏导。

## 6. 性能（用户实测，64 线程）

| 场景 | 结果 |
| --- | --- |
| 单点 `IGRF!`（零分配） | 4.69～5.06 μs；Fortran `IGRF_fortran` 18.0～18.6 μs |
| 单点 `IGRF_dB!`（含 9 个偏导） | 7.98～8.07 μs |
| 2 万点批量（Fortran 逐点串行 / Julia 串行 / Julia 多线程） | 353.6～368.7 ms / 99.6～100.4 ms / 6.31～6.35 ms |
| 追踪单条线 4500 行：Euler / DP5 | 80.2 ms / 25.1 ms（82 次分配，1.38 MiB） |
| 追踪稀疏输出（`step=5 km`） | 4.88 ms |
| 256 条线（922198 行）：串行 / `trace_mag_lines` | 5.32 s / 0.273 s（19.5 倍），每条折合 1.07 ms；Euler(Fortran) 每条约 79.8 ms |

单线 25.1 ms 中，4500 个输出点的磁场求值约占 22.8 ms（每点约 5 μs），积分只有约 3 ms。0.5 km 均匀输出时，每行一次场求值是下限；要显著减少计算量应增大 `step`。

`hmax` 扫描（`step=5 km`、`xtol=1e-3`）：

| `hmax` km | 最大偏差 km | 耗时 ms |
| --- | --- | --- |
| 25 | 7.0e-4 | 5.0 |
| 50 | 1.0e-2 | 3.9 |
| 100 | 3.5e-3 | 3.5 |

放大 `hmax` 只快 20%～30%，偏差却大 5～14 倍，所以默认保持 `hmax=25`。

## 7. 已知问题与未决事项

**7.1 `IGRF_batch!` 耗时不一致（未解决，已规避）。**

- 第一次实测（旧分块策略：总是拆成 64 块）：1 万点 3.83 ms，5 万点 13.8 ms，2000 点 12.0 ms（串行 10.1 ms）；小批量有约 10 ms 的固定开销。
- 第二次实测（加入 `min_chunk` 之后；其中 `mc=1` 即旧策略）：1 万点 422 ms，5 万点 2180 ms，2000 点 56.7 ms；串行分别为 49.2 ms、248 ms、9.9 ms。单线追踪里强制多线程输出 180.8 ms，串行 25.1 ms。
- 同一次运行里 `trace_mag_lines`（按线并行）仍有 19.5 倍加速，说明线程池本身工作正常。
- 原因未明。尚未验证的假设：测试期间机器有其它高负载进程；64 线程在 Windows 上被抢占；大堆下 GC 停顿；`IGRF_batch!` 静态分块对被抢占的线程敏感。因为 `mc=1` 与上一次的旧代码路径相同却变慢，作者倾向于环境因素，但没有证据排除代码问题。
- **已采取的措施：** `mag_trace_dp5`、`trace_mag_line` 的 `threaded_output` 默认改为 `false`（数值逐位不变，只影响耗时）；`thread_min` 默认 5000。
- **建议：** 在空闲机器上重测，并用 `-t 16`、`-t 32` 对比；确认前不要在生产路径依赖 `IGRF_batch!`。多条磁力线请用 `trace_mag_lines`。

**7.2 `xtol` 是单步（局部）容限。** 全线偏差随步数累积，实测约为 `xtol` 的 1～10 倍（`hmax` 限制步长时约 1 倍；`hmax` 放大或线很长时更大）。要保证全线偏差不超过 ε，取 `xtol ≈ ε/10`。在用户数据上 `xtol=1e-2` 与 `1e-3` 的结果完全相同，说明此时 `hmax=25` 才是实际起作用的限制。

**7.3 多线程并行度上限约 16～19 倍（64 线程）。** 三类测试（2 万点批量、256 条线、5 万点）都在这个范围。作者猜测与物理核数、超线程、全核降频有关，未验证；可用 `-t 16`、`-t 32` 对比。

**7.4 测试覆盖缺口。**

- 追踪器精度的参考线是同一积分器的高精度结果；场到笛卡尔转换若有共同错误会同时出现在两边。Euler 提供了约 1 km 量级的独立交叉检查，Python 镜像用 scipy DOP853 做过独立参考，但只在合成场上。
- 只比较了起点 1400 km 内的点；更长的线、闭合磁力线、磁零点、步长拒绝次数均未覆盖。
- 仓库里现有的 `models/test.jl` 只加载原始版、`IGRF_new.jl`、`IGRF_new2.jl`，没有加载 `IGRF_new3.jl`（外部报告指出）。
- Fortran 自适应追踪器 `:adaptive` 按用户要求排除在测试之外（dll 本身有问题），本次未改动也未测试。

**7.5 未经运行的最后改动。** 最后一轮把 `threaded_output` 默认改为 `false`，并同步了测试脚本标签；该改动只改默认值，但没有再执行一遍。接手后请至少运行一次 `test_trace_new3.jl` 的第 0～5 节作为冒烟测试。

## 8. 给接手 AI 的清单

1. **合并方式（建议）：** 把 `IGRF_new3.jl` 作为新的 `IGRF_calculate.jl`，将 `module IGRF_calculate_new3` 改回 `module IGRF_calculate`；测试脚本里的 `include` 与 `M/M2/M3/M4` 别名也要相应调整。保留相对路径 `include(joinpath(@__DIR__, "..", "common", "constants.jl"))` 等原有写法不变。
2. **全库检索调用方：** 搜索 `IGRF_calculate.IGRF`（语义现在包含 `B_compress`）、`B_compress`（外部重新赋值会报错）、`set_B_compress`（现为拷贝语义和长度检查）、`:num_steps`。
3. **建议拆分提交：** (a) 常数化与 `set_B_compress`；(b) 滚动缓冲、派生表、`@simd`；(c) 工作区、`IGRF_dB!`、`IGRF_batch!`、三角递推；(d) 追踪器 `:dp5` 与 `trace_mag_lines`；(e) `mag_line_num` 缺陷修复与后处理类型稳定（可单独提交，便于审阅，它改动了既有路径）。
4. **不要提交** 中间版本（`IGRF_calculate_step1.jl`、`IGRF_calculate_const.jl`）和沙箱里作废的旧 `IGRF_calculate.jl`；`IGRF_new.jl`、`IGRF_new2.jl` 仅在需要保留回归基线时才放入测试目录。
5. **提交前运行：** `test_IGRF_new2.jl` 第 1～4 节、`test_trace_new3.jl` 第 0～5 节（需 `julia -t auto`）；两者的第 6 节与批量耗时仅作诊断，不作通过条件。
6. **提交说明里应写明：** 默认追踪方法未变；`:dp5` 为可选方法；`threaded_output` 默认关闭的原因（§7.1）。
7. **需要审批的事项：** 将默认 `method` 改为 `:dp5`（目前不建议，须由科学负责人批准）。

## 9. 更正记录（供审阅者参考）

- 作者曾说「递推 cos/sin 比直接求值更接近真值」。对最初的分块实现不成立（锚点用舍入后的 `M*ϕ`，与直接求值同量级误差）；已改为 `fma` 补偿锚点，合成场上误差约降到 1/4。
- 作者曾说「求值次数可少一到两个数量级」。只在稀疏输出时成立；每 0.5 km 输出一行带 B 的点时，总求值数与 Euler 相当，提速来自内核更快、并行与更大的 `step`。
- 作者曾说「全线最大偏差约为 `xtol` 的 1～2 倍」。只适用于短线或 `hmax` 限制步长的情形；已更正为 1～10 倍（§7.2）。
- `mag_line_num` 缺陷是原文件就有的，作者阅读代码时在文档里看到过相关说明，当时未告知用户；外部 AI 报告独立复现后已修复。

## 10. 接手处理记录（2026-10-16，接手 AI 完成）

**批注落实情况**

1. §1/§4 批注「同意修改默认方法并同步说明」：`trace_mag_line` 默认 `method=:dp5`（`IGRF_new3.jl` 中已是该值，本次随合并进入主文件），docstring、`docs/src/api.md` 与专题文档同步；`:euler` 保留（改用纯 Julia 内核）。
2. §1 批注「尝试使用实际环境进行测试，找出原因」：**原因已查明，不是环境问题，而是 `IGRF_batch!` 的数据竞争。** 串行早退分支把工作区声明为 `ws`，`Threads.@spawn` 块内同名赋值会被 Julia 闭包捕获（捕获变量而非值），于是所有任务共用同一个工作区：n=5000 时约 95% 的点与串行不一致（出现 1e10～1e19 nT 的垃圾值），耗时也随竞争虚高。改名 `ws_serial` 后现象消失。这同时解释了 §7.1 的「两次实测互相矛盾」：`min_chunk` 之前没有这个分支，`mc=1` 与旧代码并不是同一条路径。
3. `IGRF_new3.jl` 行内批注「移除 ADAPTIVE_STEP 与 Fortran rk4 及其对应部分」：已随「模块内彻底移除 Fortran/DLL」一并完成（见下）。

**合并与移除范围**

- 主文件 `models/IGRF_calculate.jl` 以 `IGRF_new3.jl` 为基线，模块名改回 `IGRF_calculate`；保留相对 `include` 与 `String`/`GG/HH` 等对外可见结构不变。
- 删除 `IGRF_fortran_free`、`IGRF_fortran`、`IGRF_sphere`、`RK4_Trace_fortran`、`mag_trace_rk4`、`mag_trace_rk4_fortran_ADAPTIVE_STEP`、`IGRF_DLL_PATH` 及全部 `ccall`；`trace_mag_line` 只保留 `:dp5`（默认）与 `:euler`，`:rk4`/`:adaptive` 抛 `ArgumentError`。`IGRF_pc`、`mag_trace_Euler_step` 改走纯 Julia 内核（Euler 由「Fortran 场值」变为「纯 Julia 场值」，不再是逐位基线）。
- 删除二进制资源 `models/IGRF_DLL.dll`；`models/gh_gao` 仍由 `FortranFiles` 按源码同目录读取。
- `mag_trace_dp5`、`trace_mag_line` 的 `threaded_output` 默认改为 `false`（避免在 `trace_mag_lines` 外层嵌套并行）；修复竞争后单线开启它仍有收益（4500 行 28.3 ms → 10.3 ms），可显式打开。
- 中间版本 `IGRF_new.jl`、`IGRF_new2.jl`、`IGRF_new3.jl` 未提交、未删除；`test/` 下与 DLL 绑定的旧断言按决定不同步。

**验证结果（本机 64 线程，`julia -t auto`）**

- 合并保真：与 `IGRF_new3.jl` 的纯 Julia 内核在 500 个随机点上 `IGRF!`/`IGRF_dB!` **逐位一致**。
- 场值/导数：黄金参考值（移除前由 Fortran DLL 生成并固化进 `models/test.jl`）一般 ϕ 相对 |B| 3.3e-15、`B_compress=[12,-7,5]` 1.6e-15、`DB` 1.8e-14；四阶中心差分检验 9 个偏导 2.2e-9/2.0e-9/3.0e-10（阈值 1e-8）；`IGRF!`/`IGRF_dB!` 零分配；2 万点批量与串行逐位一致。
- 效率：`IGRF!` 4.94 μs（移除前 Fortran 内核 18.1 μs）、`IGRF_dB!` 7.98 μs；2 万点串行 115.8 ms / 多线程 6.74 ms。追踪：DP5 到高精度参考线最大偏差 7.99e-4 km（Euler 0.858 km）；单线 4500 行 DP5 28.3 ms、Euler 25.8 ms、`step=5 km` 5.1 ms；256 条线 922198 行 7.26 s → 0.436 s（16.6×）；`IGRF_batch!` 修复后 1 万点 5～13 ms、5 万点 14 ms，重复测量稳定。
- §7.4 的测试覆盖缺口已部分补齐：`models/test.jl` 改为黄金参考 + 有限差分双路回归，`models/test_trace.jl` 第 0～6 节全部重跑通过（含 `IGRF_batch!` 与串行逐位一致的断言）。
- 提交记录见 `CHANGELOG.md`「2026-10-16 IGRF 纯 Julia 化合并」条目。

## 11. 本次独立复测与工作区隔离加固（2026-10-16）

### 范围与已有状态

本次只检查 IGRF 系列、本报告和两个指定测试脚本；执行模块时正常加载其依赖，没有展开检查项目其他部分。开始工作时，主文件已含 §10 的 `ws_serial` 修复、默认 `:dp5` 和 Fortran 追踪器移除；这些并非本次新增改动。旧 `IGRF_new3.jl` 仍保留原始缺陷，作为历史复现材料保留，不再作为候选正式入口。

### 本次修改

- `IGRF_calculate.jl`：把创建工作区和逐点求值放到独立 `_igrf_chunk!` 函数。串行路径直接调用它，并行路径为每个块启动一次调用；工作区属于函数调用的局部变量，避免依赖“串行分支不能叫 ws”这种易被后续重构破坏的约定。不改变球谐求值顺序、分块策略或默认参数。
- `test.jl`：在 0、1、255、256、257、513、2000、5000 点上，覆盖 `min_chunk=1/256/n+1`，每种组合同时启动 4 个独立批量请求，每个重复 3 次，并逐位对照串行结果。覆盖空输入、串行回退、分块边界和嵌套任务调度。
- `test_trace.jl`：增加最长单线 `threaded_output=true, thread_min=1` 与串行输出的位置、磁场逐位一致检查，重复 3 次。
- 修正 `min_chunk` 说明：它控制目标块大小，末块可更小；旧异常耗时不能一概解释为线程唤醒开销。保留 `min_chunk=256`、`threaded_output=false` 的默认值；多条线优先在线级并行，单条长线可显式打开并行输出。

### 复测方法

由 GPT Luna 测试代理在本机 Windows、Julia 1.10.0 上顺序运行独立进程，不同时启动多个性能测试。`-t auto` 得到 64 个 Julia 工作线程。命令从仓库根目录执行：

```powershell
julia --startup-file=no -t auto models/test.jl
julia --startup-file=no -t auto models/test_trace.jl
julia --startup-file=no -t 1 models/test.jl
julia --startup-file=no -t 16 models/test.jl
julia --startup-file=no -t 32 models/test.jl
```

`@btime`/`@belapsed` 的性能表为预热后的最小时间；256 条线的计时沿用脚本单次墙钟时间，不能当作严格的稳态速度保证。准确性是通过条件，耗时仅作本机诊断。历史 Fortran 黄金值使用现有测试数据，本次没有重新生成 DLL 参考。

### 最终版本验证结果

- 64 线程的两个脚本全部通过，包括新增的工作区隔离和单线并行输出断言。为缩短纯诊断采样，最终 `test_trace.jl` 使用 `using BenchmarkTools; BenchmarkTools.DEFAULT_PARAMETERS.seconds=0.5; include(...)` 包装执行；所有正确性检查与数据规模不变。基线两个脚本以默认采样时长完整执行。
- 黄金场值、均匀场和 DB 回归通过；9 个偏导的有限差分误差（径向、余纬、经度）为约 `2.15e-9 / 1.98e-9 / 3.04e-10`，阈值 `1e-8`。
- `IGRF!` 与 `IGRF_dB!` 稳态零分配；最终单点最小时间分别为 `4.886 μs` 和 `7.967 μs`。
- 最终 64 线程下 2 万点串行 `98.489 ms`、批量 `6.114 ms`，约 `16.1×`；修改前本次基线为 `101.664 ms / 6.320 ms`。这点差别在本机计时波动范围内，不把函数作用域加固宣称为新的额外提速。
- 最终 256 条磁力线共 922198 行，串行 `5.72 s`、并行 `0.337 s`，约 `17.0×`，位置和磁场与串行逐位一致。

不同线程数的最终 `test.jl` 均通过（包括所有新增断言），2 万点 `@btime` 最小耗时如下。各行来自独立进程，串行基线也有明显波动，因此这不是固定核数下的严格扩展性曲线：

| Julia 线程数 | 串行循环 ms | IGRF_batch! ms |
| --- | ---: | ---: |
| 1 | 103.317 | 100.977 |
| 16 | 99.631 | 6.531 |
| 32 | 144.098 | 5.269 |
| 64 | 98.489 | 6.114 |

本机此轮 32 线程批量最小值优于 64 线程，但不能据一次扫描断言普遍最优，更不能推断物理核/NUMA 根因；没有把并行度硬编码为 32。最终最长单线 DP5 串行输出 `26.809 ms`、并行输出 `9.652 ms`、稀疏输出（step=5）`5.370 ms`。`min_chunk=256` 的 500/2000/10000/50000 点批量最小时间分别为 `1.51/2.32/4.84/14.3 ms`，与串行逐位一致。

### 旧版根因的独立复现

从 `IGRF_new3.jl` **只抽取旧 `IGRF_batch!` 函数**，改名 `batch_before!` 后在当前主模块内求值，共用相同球谐内核与系数；不加载旧版 DLL。固定随机种子，64 线程、5000 点、`min_chunk=1`，预热后重复 3 次：

| 实现 | 第1/2/3次错误点数（对照串行） | 第1/2/3次耗时 ms |
| --- | --- | --- |
| 旧 new3 批量函数 | 4121 / 4714 / 4845 | 246.7 / 218.9 / 225.8 |
| 当前批量函数 | 0 / 0 / 0 | 36.08 / 13.62 / 13.33 |

此表为诊断脚本单次测量，不是 BenchmarkTools 最小值，不能直接与前面的稳态性能表相除。旧函数关键字实现的 `Base.uncompressed_ast` 明确含 `ws@_11 = Core.Box()`；当前实现对应的关键字函数中没有 `Core.Box`。结合源码，串行分支和任务闭包内对同一个 `ws` 绑定赋值，使各任务共享被捕获的工作区绑定；内核同时写入缓冲，导致错误数值和性能恶化。即使串行分支在该次调用没有执行，词法作用域仍然决定捕获行为。

结论：§7.1 的核心故障是代码中的数据竞争，不能归因于 Windows 负载或 GC；此次验证了 §10 已有修复的结论，并以独立函数作用域加固。修复后仍存在小批量调度开销和进程间耗时波动，不能承诺所有输入在 64 线程下都更快。

本次原始日志及可重跑诊断脚本保存在本机 `C:\Users\chengsw\AppData\Local\Temp\csw-julia-tests-20261016`：`final-test-auto.log`、`final-test-t1.log`、`final-test-t16.log`、`final-test-t32.log`、`final-test_trace.log`、`old-batch-repro.log`、`old-batch-lowered.log`、`repro-old-batch.jl`。临时目录可能被系统清理，关键结果已固化于本节。

版本管理记录：`models/test.jl` 原被现有通用 Git 忽略规则排除；按用户要求记录 changelog 并提交时，将该指定测试脚本显式纳入版本控制，忽略规则不变。历史版本文件保持原样，不纳入本次提交。
