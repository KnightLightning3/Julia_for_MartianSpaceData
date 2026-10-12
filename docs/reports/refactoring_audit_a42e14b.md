# a42e14b 重构提交 · 函数一致性审查报告

> **审查对象**：提交 `a42e14b`「重构：公共常量/函数集中化 + 静态数组与 Rotations 迁移 + 全仓 Docstring 规范化」
> **基准版本**：父提交 `af1362e`（diff 范围 `af1362e..a42e14b`，共 29 个文件、约 4,416 行新增 / 1,008 行删除）
> **生成日期**：2026-10-12
> **审查方式**：AST 级函数对比（剥离注释与 docstring） + 逐文件 diff 人工复核 + Julia 动态数值验证
> **源代码状态**：报告生成时未改动源代码；**BUG-1 修复补丁已于 2026-10-12 应用**（见附录 B）。验证脚本位于临时目录 `%TEMP%\pkgdiff\`（可重跑，见附录 A）

---

## 一、结论速览（TL;DR）

| # | 严重度 | 发现 | 位置 | 类型 |
|---|--------|------|------|------|
| 1 | 🔴 **回归缺陷** | **纯 Julia 版 `IGRF()` 结果错误**：本次提交在累加循环内新增了 `BR/BT/BP = 0.0e0`，把跨阶累加器每轮清零，只剩最高阶（N=110）贡献。动态验证：`IGRF(3393.5, 1.0, 0.5)` 旧版 `BB=373.56 nT`，新版 `BB=97.53 nT`（完全不同）。 | `Magnetic_Model/IGRF_calculate.jl:401-403`（新增行），累加在 `:440-442` | 数值错误（行为回归） |
| 2 | 🟠 高（数值不兼容） | `alfven_weve` 所用 `μ_0` 由 `4π×10⁷` 改为 `4π×10⁻⁷`（差 10¹⁴ 倍），Alfvén 速度相差 **10⁷ 倍**。新值才是标准 SI 值，但属于破坏性数值变化。 | `models/Cold_Plasma_Dispersion_Relation.jl`（旧 `:15` 常量 → 新 `constants.μ0`），函数在 `:226-229` | 数值不兼容（可能是有意纠错） |
| 3 | 🟠 高（数值不兼容） | 常量精度统一引起**非“极小”**的数值变化：`e: 1.6e-19 → 1.602176634e-19`（**+0.136%**），直接影响 `Single_Particle_Orbit` 的 `q2me/q2mp`（轨道积分）、`Maxwellian` 及旧 `models/constants.jl` 口径的派生量。 | `common/constants.jl` | 数值不兼容 |
| 4 | 🟡 中（接口变化） | `Quaternion_Rot` / `Quaternion_Rot_reverse` 参数类型由 `QuaternionF64`（Quaternions.jl）改为 `QuatRotation`（Rotations.jl），外部调用者需适配；数值行为已验证**完全等价**（100 组随机单位四元数，正/反向误差 <1e-12）。 | `calculate/calculate_models.jl:50,66` | API 变化 |
| 5 | 🟡 中（行为修复） | `MAVEN_STATIC.static_rotation`：旧版对“向量数组”直接 `quat * xyz` 会抛 `MethodError`（Rotations.jl 不支持该乘法），**旧实现实际不可用**；新版显式逐元素 `map` 旋转并修正 `theta/phi` 索引，属修复。 | `MAVEN_data/MAVEN_STATIC.jl:780-784` | 修复 |
| 6 | 🟡 中（行为修复） | 旧 `common/head.jl:34` `const q2mp = e / m_p` 引用**未定义变量 `m_p`**（旧版 include 该文件即 `UndefVarError`）；新 `constants.jl` 修正为 `e/mp`。 | 旧 `common/head.jl:34` | 修复 |
| 7 | 🟢 低（类型变化） | 若干返回值由 `Vector` 变为 `SVector/NTuple`：`get_quality_flag`（`Vector{Bool}`→`NTuple{16,Bool}`）、`get_min_bounding_box`（→`SVector{6}`）、`sta_v_4d(_new)/sta_n_4d` 的 `flux/vel`、`cross3`、`MINPA_sphere2xyz/xyz2sphere` 等。仓内调用点均为解构/索引使用，**安全**；外部若做 `push!` 等原地操作需适配。 | 多处 | 接口变化 |
| 8 | ⚪ 遗留（非本次引入） | `combina_two_dir_trace` 在模块内部调用 `IGRF_calculate.sphere2pc`（带模块前缀），`to_pc=true` 时必 `UndefVarError`；新旧版本均存在，本次仅补充注释未修复。 | `Magnetic_Model/IGRF_calculate.jl:679-680` | 既有缺陷（未修复） |

> ✅ **修复状态（2026-10-12 更新）**：BUG-1（IGRF 累加器清零）已修复并通过逐位回归验证，补丁与验证证据见附录 B。

**总体评价**：本次重构的函数级等价性总体良好——绝大多数改动的语义是“常量集中化引用”“重复实现合并到 `common/`”“docstring 规范化”，动态数值验证显示这些替换的差异在 0 ~ 2×10⁻⁴ 量级；**唯一真正的回归缺陷是 `IGRF()` 的累加器清零（#1）**，另有 2 处需要知悉的破坏性数值变化（#2、#3）。

---

## 二、审查方法

### 2.1 自动化范围界定（AST 对比）

用 Julia（`Meta.parseall`）分别解析新旧两版全部 `.jl` 文件，剥离注释、`LineNumberNode` 与 `@doc` docstring 后按“文件 :: 函数名/参数个数”逐一对 AST 比较：

- **75 个函数** AST 发生变化（其中 9 个经人工复核实为“函数体内嵌 docstring”造成的假阳性，语义无变化）；
- **43 个函数被删除**；
- **15 个函数新增**（全部在 `common/MarsCommon.jl`）+ 25 个新增常量（`common/constants.jl`）；
- **122 个函数** 剥离注释/docstring 后 AST 完全一致（**按用户要求忽略**）；
- 另有结构性变化：1 个结构体（`OctreeNode`，实为内嵌构造函数 docstring 变化）、若干 `using` 变更、1 个常量文件删除。

> 说明：`models/Pickup_ion.jl` 的绝大部分代码位于顶层 `if` 块内，未被 AST 脚本捕获，已单独用 diff 人工复核。
> 注释/docstring 清理策略说明：函数体内以“裸字符串”形式存在的说明文字不属于 `@doc`，会参与 AST 比较而误报为“变化”，第 2.2 节已逐一核实其语义为无操作。

### 2.2 人工复核

对全部 75+43+15 项逐一查看新旧源码 diff；对高风险项（Rotations 迁移、静态数组迁移、常量集中化、函数合并）另做动态验证。

### 2.3 环境

| 组件 | 版本 |
|------|------|
| Julia | 1.10.0 |
| Rotations | 1.7.1 |
| Quaternions | 0.7.6（仅用于对照旧实现） |
| StaticArrays | 已安装（经 `@v1.10` 全局环境加载） |

---

## 三、详细发现

### 3.1 🔴 BUG-1：纯 Julia `IGRF()` 累加器被逐阶清零（真实回归）

**位置**：`Magnetic_Model/IGRF_calculate.jl`

- 旧版（`af1362e`）：`BR/BT/BP` 在循环**外**初始化一次（旧 `:164-166`），在 `for N = 1:NIGRF` 循环内做**跨阶累加**（旧 `:227-229`：`BR = BR + (N+1)*AARR[N+2]*XX` …）。
- 新版（`a42e14b`）：循环外初始化仍在（`:377-379`），但**在循环体内、累加之前又插入了三行清零**：

```julia
@inbounds for N = 1:NIGRF
    XX = 0.0e0
    YY = 0.0e0
    ZZ = 0.0e0
    BR = 0.0e0     # ← 本次新增（:401-403），导致每轮清零跨阶累加
    BT = 0.0e0
    BP = 0.0e0
    ...
    BR = BR + (N + 1) * AARR[N+2] * XX   # :440，等价于只累加当前 N
```

**后果**：最终 `BR/BT/BP` 只保留 `N = NIGRF = 110` 一阶的贡献，丢失 N=1..109 的全部球谐项（含偶极项），结果完全错误。

**动态证据**（同输入、分别加载新旧模块运行旧/新 `IGRF()`）：

| 输入 `(r, θ, φ)` | 旧版 `(BR, BT, BP, BB)` | 新版 `(BR, BT, BP, BB)` |
|---|---|---|
| `(3393.5, 1.0, 0.5)` | `(222.81, 228.24, 194.46, 373.56)` | `(-30.06, 92.75, -2.33, 97.53)` |
| `(4393.5, 0.7, -1.2)` | `(-0.4936, -0.2437, -0.2309, 0.5970)` | `(~1e-11 量级，接近 0)` |
| `(6000.0, 0.3, 2.0)` | `(-0.3933, -0.0373, -0.0472, 0.3979)` | `(~1e-26 量级，接近 0)` |
| `(3593.5, 1.2, -0.4)` | `(50.95, 20.83, 4.91, 55.26)` | `(-0.244, 0.063, 0.068, 0.261)` |

旧版表面 ~374 nT 符合火星壳磁场量级，新版为错误值。

**影响范围**：
- `IGRF()`（纯 Julia 参考实现）未被 `export`，仓内也无调用点（示例与 `IGRF_pc` 走 Fortran DLL 内核 `IGRF_fortran`，**不受影响**）；
- 但对直接调用 `IGRF_calculate.IGRF(r,θ,φ)` 的使用者（教学/校验场景）构成**从“可用”到“错误”的行为回归**。

**修复状态**：✅ **已于 2026-10-12 修复**。修复方式：删除循环内三行 `BR/BT/BP = 0.0e0`（原 `:401-403`），保留循环外初始化并在其上补充防回归注释；恢复后输出与旧版基准**逐位一致**（4 组测试点 16 位有效数字完全相同），证据与复现命令见附录 B。

**复现命令**（详见附录 B）：

```powershell
julia --project=@v1.10 "$env:TEMP\pkgdiff\igrf_test.jl" "$env:TEMP\pkgdiff\old"
julia --project=@v1.10 "$env:TEMP\pkgdiff\igrf_test.jl" "$env:TEMP\pkgdiff\new"
```

---

### 3.2 🟠 IMPACT-1：`alfven_weve` 的 `μ_0` 相差 10¹⁴ 倍

旧 `models/Cold_Plasma_Dispersion_Relation.jl:15` 定义 `μ_0 = 4π×10⁷`（比标准 SI 值大 10¹⁴ 倍，疑似单位书写错误）；新代码改用 `common/constants.jl` 的 `μ0 = 4π×10⁻⁷`。

`alfven_weve(B, ρ) = B/sqrt(μ_0·ρ)` 受影响：**新/旧结果比值 = 10⁷**（sqrt(10¹⁴)）。

- 新值是标准 SI（v_A 单位 m/s，与函数文档一致），属于“纠正”；
- 但若此前有外部代码围绕旧（错误）量级使用，其结果将发生巨变——**必须知悉**；
- 仓内 `alfven_weve` 无调用点（仅同文件其他函数与文档），实际波及面有限。

其余 `Cold_Plasma` 函数（`Dispersion_Relation`、`DR_wave_vector`、`DR_phase_velocity`、`carculate_minimum_energy`、`set_particles`、`get_πe`）仅做常量限定替换：`me` +1.7e-7、`eV` +9.2e-8、`c` 不变，公式逐项一致。

---

### 3.3 🟠 IMPACT-2：常量精度统一的量化差异（CHANGELOG 中“极小量级”的说法需修正）

以新 `common/constants.jl` 为基准，对比旧版各文件中的常量定义：

| 常量 | 旧值（旧文件口径） | 新值 | 相对差 |
|------|--------------------|------|--------|
| `e` | `1.6e-19`（旧 `models/*`、`Single_Particle_Orbit`） | `1.602176634e-19` | **+0.136%** |
| `e`（head 口径） | `1.602176634e-19` | 同 | 0 |
| `eV` / `Q` | `1.602176487e-19`（MAVEN 系、SP、calc） | `1.602176634e-19` | +9.2e-8 |
| `Q`（TW_MINPA） | `1.60217662e-19` | 同新 | +8.7e-9 |
| `me` | `9.109e-31`（MAVEN/plot/STATIC/SWIA/SWEA） | `9.1093837e-31` | +4.2e-5 |
| `me`（CPDR） | `9.10938215e-31` | 同新 | +1.7e-7 |
| `mp` | `1.672621637e-27`（MAVEN 系） | `1.67262192e-27` | +1.7e-7 |
| `mp`（TW_MINPA） | `1.6726219e-27` | 同新 | +1.2e-8 |
| `mp`（head） | `1.67262192369e-27` | 同新 | −2.2e-9 |
| `k_B`（旧 `κ`，Maxwellian） | `1.38064852e-23` | `1.380649e-23` | +3.5e-7 |
| `μ_0`（CPDR） | `4π×10⁷` | `4π×10⁻⁷` | **比值 10⁻¹⁴（见 3.2）** |
| `RAD/RADG/inv_RADG/R_Mars/G/M_Mars` | 各文件 | 数值等价 | 0 |

**受影响的派生量与函数**（动态验证，相同输入下的最大相对差）：

| 派生/函数 | 对照旧实现 | 最大相对差 | 波及模块 |
|---|---|---|---|
| `q2me`、`q2mp` | 旧 `1.6e-19` 口径 | **±0.136%** | `Single_Particle_Orbit.solve_orbit/solve_orbit_ode`（轨道积分 mq）、及其他曾使用旧 `models/constants.jl` 口径的调用者 |
| `ion_energy_to_speed` | 旧 `ion_energy2v`（938313.53·AMU，3e8） | **0**（逐项相同） | STATIC/SWEA/SWIA/plot/Pickup_ion |
| `ion_speed_to_energy` | 旧 `ion_v2energy` | 0（逐项相同） | Pickup_ion 等 |
| `ion_eflux_to_psd_approx` | 旧 STATIC/SWIA/SWEA `ion_eflux2F`（2·eflux·1e4/V⁴） | **0** | — |
| `ion_eflux_to_psd` | 旧 MAVEN_load `ion_eflux2F`（相对论 P² 公式） | 7.7e-8 | — |
| `electron_eflux_to_psd` | 旧 plot/load `eflux2F`（相对论 P² 公式） | 4.2e-5 | `MAVEN_plot.PAD_slice*` 三处调用 |
| `eflux_to_df!` | 旧 SWIA `eflux2df!`（硬编码 48 能量道） | 1.6e-4（mass 口径差）；公式逐项一致 | `Pickup_ion:322` |
| `n1d`（SWEA） | 旧 `5.6856296585483802e-6` 硬编码 | 7.8e-8 | MAVEN_SWEA |
| `n_1d`（SWIA） | 旧 `sqrt(5.68566e-6*1836*1.6e-22/(2*1.6e-12))*8.8` | 3.9e-5 | MAVEN_SWIA |
| `PAD_slice_velocity` v0 | 旧 `sqrt(2E/me·EV)` | −2.1e-5 | MAVEN_plot |
| `cyclotron_frequency/radius`（电子分支） | 旧 `Me=9.109e-31, Q` | +4.2e-5 | calculate_models |
| `alfven_weve` | 旧 `4π×10⁷` | **×10⁷** | 见 3.2 |

> 结论：CHANGELOG 中“对依赖这些常量的数值结果会有极小量级的变化”对绝大多数条目成立，但对 **`e: 1.6e-19（0.136%）`** 与 **`μ_0`（10¹⁴ 倍）** 两个条目不成立，报告与 CHANGELOG 表述宜同步修正。

---

### 3.4 🟡 CHANGE-1：接口 / 类型变化清单（内部已验证安全）

| 项目 | 旧 | 新 | 仓内影响 | 外部影响 |
|---|---|---|---|---|
| `calculate_models.Quaternion_Rot(_reverse)` | `q::QuaternionF64` | `q::QuatRotation` | 无调用点 | 传入 `QuaternionF64` 将 `MethodError`，需改用 `QuatRotation` |
| `calculate_models.Matrix_Rot` | 存在 | 删除（→ `MarsCommon.rotate_vector`） | 无调用点 | 外部需改名并注意参数顺序不变（`rotate_vector(data, R) = R*data`） |
| `MAVEN_STATIC.get_quality_flag` | `Vector{Bool}` | `NTuple{16,Bool}` | 无调用点 | 索引兼容；`push!` 类操作不兼容 |
| `Octree.get_min_bounding_box` | `Vector{Float64}(6)` | `SVector{6}` | 无调用点 | 索引兼容；`push!` 不兼容 |
| `sta_v_4d / sta_v_4d_new / sta_n_4d` 返回 | `[x,y,z]`（Vector） | `SVector` | `Build_data/STATIC_VD.jl` 仅解构，兼容 | 广播/索引兼容 |
| `models/Single_Particle_Orbit.solve_orbit` 内部状态 | `Vector` | `SVector`（含 `E/B` 默认回调返回 `SVector`） | 仅内部 | 若外部自定义 `E(x)` 返回 `Vector`，混合运算可正常工作（类型不稳定但不报错） |
| `MINPA_sphere2xyz / MINPA_xyz2sphere`（TW_MINPA） | `Vector` | `SVector` | `v3d/v3d_single` 广播/索引，兼容；`vv .*= -1` 为重新绑定广播，兼容 | 同上 |
| `core` 常量名删除 | `Me/Mp/EV/C/Q/RADG/Rm/E0/m_e/κ` 等 | 统一 `constants.*` | 已全量替换（静态扫描 0 处裸引用残留） | 外部脚本若裸引用旧名需适配；`models/constants.jl` 已删除 |
| `requirement.jl` | 含 `"Quaternions"` | 移除 | 一致（代码中已无 `Quaternions` 引用） | 依赖环境无需再装 Quaternions |

---

### 3.5 🟡 FIX：本次提交顺带修复的旧缺陷（新旧行为对比）

1. **`common/head.jl` 的 `q2mp = e / m_p`**：旧代码 `m_p` 未定义——只要 include `head.jl` 就会 `UndefVarError`（除非外部先定义 `m_p`）；新版统一为 `constants.q2mp = e/mp`。**行为：从不可加载 → 正常**。
2. **`MAVEN_STATIC.static_rotation`**：旧版 `quat * xyz`（`xyz` 为“向量数组”）在 Rotations.jl 下无对应方法。动态验证（Rotations 1.7.1）：`QuatRotation * Vector{Vector}` → `DimensionMismatch`；`QuatRotation * Array{Vector,3}` → `MethodError`（`hasmethod == false`）。**旧实现必然报错**；新版逐元素 `map(p -> quat*p, xyz)`，并把从 `(theta, phi)` 中取值的下标从旧 `var[1]/var[2]` 修正为新 `(r,θ,φ)` 的 `var[2]/var[3]`，映射关系前后等价。**行为：从崩溃 → 正确**。
3. **旧 `MAVEN_load.eflux2F` / `calculate_models.eflux2F` 等副本**引用未定义变量（`M = me`、`E0` 在对应模块不存在；旧 MAVEN_load 只有 `Me`，calculate_models 只有 `Me/Mp`）。这些副本在旧版即为死代码/坏代码；新版统一到 `MarsCommon.electron_eflux_to_psd`。**行为：坏了 → 可用**（且公式与旧 MAVEN_plot 口径一致，见 3.3 表）。
4. 旧 `MAVEN_SWIA/SWEA` 的 `eflux2df!` 硬编码 `reshape(..., 48)` 能量道；新版 `eflux_to_df!` 使用 `length(data[:energy])`（SWIA/SWEA 均为 48，等价且更通用）。
5. 删除死代码（无任何仓内调用点的重复实现）：`Matrix_Rot`、`Doppler_Shift`、`energy2v`、`eflux2F`、`ion_eflux2F`（各副本）、`ion_energy2v`、`ion_v2energy`、`rotate_vector_with_Matrix/Martrix`、`sphere2xyz(_for_STATIC/_for_SWIA)`、`xyz2sphere_for_STATIC/_for_SWIA`、`STATIC_sphere2xyz/STATIC_xyz2sphere`（common 版）、`call_fortran_dll.RAD`（定义但从未使用）。全部在旧树中确认无调用点或仅有注释/测试残留；新树中亦无旧名残留（已全量 grep 验证）。

---

### 3.6 ⚪ LEGACY：既有问题（非本次引入，未修复，供后续处置）

| 问题 | 位置（新） | 说明 |
|---|---|---|
| `combina_two_dir_trace` 模块内使用 `IGRF_calculate.` 前缀调用自身函数 | `IGRF_calculate.jl:679-680` | `to_pc=true` 时 `UndefVarError`；新旧版一致存在 |
| `calculate_mag/caculate_mag` 向未初始化全局 `data` 写入 | `MAVEN_load.jl:928`、`TW_load.jl:133`、`MGS_load.jl:117` | 与旧版一致；新 docstring 已注明 |
| `STA_count2df/STA_eflux2df` 默认关键字参数引用未定义全局 `m_int` | `MAVEN_STATIC.jl`（`STA_count2df`、`STA_eflux2df`） | 与旧版一致；调用方需显式传参 |
| `MAVEN_SWEA.n1d` 中 `tiny = 1.0-31`（疑为 `1e-31` 笔误） | `MAVEN_SWEA.jl:47` 附近 | 与旧版一致；新 docstring 已注明 |
| 路径硬编码（`D:/CODE/...`、`E:/Tianwen-1/`、`E:/MGS/` 等） | `common/head.jl:29` 等 | 与旧版一致 |

---

## 四、函数级核对汇总

### 4.1 语义无变化（假阳性复核为“仅注释/docstring”）

`graham_scan!`（内嵌 `ccw` docstring）、`OctreeNode`（内嵌构造函数 docstring）、`get_vsc`（内嵌 docstring）、`SP_load.load_omni2_data`（内嵌 docstring）、`SWEA_calc_shape_arr`、`load_cdf`、`load_kp`、`load_mag_l2`（均为内嵌函数 docstring）、`STA_count3df`（内嵌 docstring）、`interpolate_x_ticks`（移除了函数体内旧的裸说明字符串）——共 9 项，语义均无变化。

### 4.2 等价（含常量限定替换 / 类型等价替换 / 合并调用），已逐项验证

- **等价、数值差 ≤ 2×10⁻⁴**（均已在 3.3 表量化）：`static_rotation`（同时是修复）、`static_slip_2_V`、`sta_v_4d`、`sta_v_4d_new`、`sta_n_4d`、`sta_v_1d`、`get_quality_flag`、`n1d`、`get_3dc!`、`get_3df!`、`n_1d`、`MINPA_energy2v`、`MINPA_get_psd`、`MINPA_sphere2xyz`、`MINPA_xyz2sphere`、`v3d`、`v3d_single`、`calculate_mag`（MAVEN/TW）、`caculate_mag`（MGS）、`cyclone_frequency`、`cyclone_R`、`cyclotron_radius`、`cyclotron_frequency`（calculate_models）、`escape_energy`、`Quaternion_Rot`、`Quaternion_Rot_reverse`、`PAD_slice`、`PAD_slice_polar`、`PAD_slice_velocity`、`Orbit`、`STA_2d_slip`、`VDF_2d_slip`、`VDF_2d_mask`、`Velocity_distribution` 系 5 函数（Maxwellian）、`set_particles`、`carculate_minimum_energy`、`DR_phase_velocity`、`DR_wave_vector`、`ion_alvfen`、`dvdt`、`cross3`、`B/E`（SPO 默认回调）、`solve_orbit`、`solve_orbit_ode`、`read_gh`（返回元组，调用点解构不变）、`pc2sphere`、`Bpc2sphere`（`norm→hypot`，数学等价）、`IGRF_fortran_free`、`mag_trace_*` 系 3 函数（默认参数 `Rm→constants.R_Mars`，值相同）、`get_mag_line_s`、`trace_mag_line`、`get_bowshock_normal`、`get_normal_plane`（Vector→SVector）、`build_octree!`（角落点 Vector→SVector）、`get_min_bounding_box`（返回 SVector）、`set_B_compress`（探底 const 化后仍可 `global` 重绑）等。
- **公式逐项一致的完全等价**（数值差 0）：`ion_energy_to_speed`、`ion_speed_to_energy`、`ion_eflux_to_psd_approx`、`doppler_shift`、`spherical_to_cartesian`、`instrument_sphere_to_cartesian`、`instrument_cartesian_to_sphere`（新增 clamp 属鲁棒性增强）、`rotate_vector`、`position_altitude/local_time/latitude`。

### 4.3 被删除函数 → 新实现的映射（43 项）

| 旧函数（出现于多处副本） | 新实现 | 备注 |
|---|---|---|
| `ion_energy2v(energy, AMU/;m_int)` | `MarsCommon.ion_energy_to_speed(energy, mass_amu)` | 公式：938313.53·AMU keV 相对论，输出 m/s |
| `ion_v2energy(v, AMU/;m_int)` | `MarsCommon.ion_speed_to_energy(speed, mass_amu)` | 逆运算 |
| `energy2v(energy)`、`energy2v(;type,nM)`（电子/离子） | `MarsCommon.electron_energy_to_speed` / `ion_energy_to_speed` | `511·nM·1836.23 = 938313.53·nM` 恒等 |
| `eflux2F(energy, eflux)`（电子） | `MarsCommon.electron_eflux_to_psd` | 相对论 P² 公式；旧 load/calc 副本引用了未定义 `me/E0`（坏代码） |
| `ion_eflux2F(energy, eflux, mION)`（MAVEN_load 版） | `MarsCommon.ion_eflux_to_psd` | 相对论 P² 公式 |
| `ion_eflux2F(energy, eflux; m_int)`（STATIC/SWIA/SWEA 版） | `MarsCommon.ion_eflux_to_psd_approx` | 近似式 `2·eflux·1e4/V⁴`（注释注明“与 STA 方法差 1e3 倍”的版本） |
| `eflux2df!(dat)`（SWIA/SWEA） | `MarsCommon.eflux_to_df!` | 硬编码 48 → 通用长度 |
| `sphere2xyz_for_STATIC/SWIA`、`sphere2xyz_for_static_rotation` | `MarsCommon.instrument_sphere_to_cartesian` | 仰角定义（cosθ 形式） |
| `xyz2sphere_for_STATIC/SWIA`、`xyz2sphere_for_static_rotation` | `MarsCommon.instrument_cartesian_to_sphere` | 逆变换（新增 clamp） |
| `sphere2xyz(r,θ,ϕ)`（MAVEN_load，余纬定义） | `MarsCommon.spherical_to_cartesian` | 两条公式均保留、未混淆 |
| `rotate_vector_with_Matrix` / `rotate_vector_with_Martrix`（拼写笔误）/ `Matrix_Rot` | `MarsCommon.rotate_vector` | `R*data`，参数顺序不变 |
| `Doppler_Shift` | `MarsCommon.doppler_shift` | 公式一致 |
| `c_alt/c_local_time/c_latitude`（嵌套于 calculate_mag/caculate_mag） | `MarsCommon.position_altitude/local_time/latitude` | 公式一致 |
| `STATIC_xyz2sphere/STATIC_sphere2xyz`（common 版，SVector 入参） | 删除（不设替代；`MINPA_*` 等价函数保留在 `common/function_coordinate.jl`） | 旧调用点 `Pickup_ion` 已改为 `MarsCommon.instrument_cartesian_to_sphere` |
| 各模块常量（`EV/C/Me/Mp/Q/RADG/inv_RADG/Rm/E0/m_e/κ/μ_0` 等） | `common/constants.jl` | 见 3.3 表 |
| `models/constants.jl`（整文件） | 删除 | 其旧 `e=1.6e-19` 等口径并入统一常量 |

### 4.4 新增函数（15 项，全部在 `common/MarsCommon.jl`）

`instrument_sphere_to_cartesian`、`instrument_cartesian_to_sphere`、`spherical_to_cartesian`、`rotate_vector`、`position_altitude`、`position_local_time`、`position_latitude`、`ion_energy_to_speed`、`ion_speed_to_energy`、`electron_energy_to_speed`、`electron_eflux_to_psd`、`ion_eflux_to_psd`、`ion_eflux_to_psd_approx`、`eflux_to_df!`、`doppler_shift` —— 均已与旧副本逐一对照验证（见 4.3 / 3.3）。

---

## 五、验证工件（附录 A：关键复现）

### A.1 AST 函数级对比（判定“哪些函数真正变了”）

- 脚本：`%TEMP%\pkgdiff\compare_funcs.jl`
- 输出：`%TEMP%\pkgdiff\func_compare_list.txt`（263 条条目）、`func_compare_full.txt`（逐函数新旧归一化 AST 全文）

### A.2 裸常量引用静态检查（防止“删常量但漏改引用”）

- 脚本：`%TEMP%\pkgdiff\check_bare_refs.jl`、`check_bare2.jl`
- 结果：0 处真实残留（3 处 `catch e` 为误报；局部变量 `e/c/G` 均为函数内合法绑定）。

### A.3 四元数等价性测试（Rotations vs Quaternions）

- 脚本：`%TEMP%\pkgdiff\test_rotations2.jl`
- 结果：
  - `QuatRotation([w,x,y,z])` 与 `QuaternionF64(w,x,y,z)` 旋转矩阵/向量作用**等价**（100 组随机样本，正/反变换 `atol=1e-12`）；
  - 反向 `inv(q)*u ≡ conj(q)*u*q` 等价；
  - `QuatRotation * Array{Vector,3}` 无方法（复现旧 `static_rotation` 的 `MethodError`），`map` 逐元素旋转正常。

### A.4 IGRF 新旧数值对比

- 脚本：`%TEMP%\pkgdiff\igrf_test.jl`（加载指定版本树后运行 `IGRF()` 并打印）
- 结果见 3.1 表。

### A.5 常量与公式数值对比

- 脚本：`%TEMP%\pkgdiff\num_check.jl`
- 结果见 3.3 表。

---

## 六、建议与优先级（仅供决策，未改动任何源码）

1. **P0（已完成 ✅，2026-10-12）**：已修复 `IGRF_calculate.jl` 的累加器清零（删除循环内三行并补充防回归注释），已按 3.1 表中的输入回归验证与旧版逐位一致（详见附录 B）。
2. **P1（发布说明中明示）**：在 CHANGELOG/迁移说明中修正两处表述：
   - `alfven_weve`：`μ_0` 由 `4π×10⁷ → 4π×10⁻⁷`，v_A 结果 ×10⁷（若外部使用需重新定标）；
   - `e: 1.6e-19 → 1.602176634e-19` 带来 **0.136%** 的 `q2me/q2mp` 变化，会影响 `Single_Particle_Orbit` 轨道积分与一切旧 `models/constants.jl` 口径的派生结果；“极小量级”仅适用于其余条目（≤2×10⁻⁴）。
3. **P2（可顺手修复，均非本次引入）**：`combina_two_dir_trace` 去掉 `IGRF_calculate.` 前缀；`calculate_mag`/`caculate_mag` 的未定义全局 `data`；`STA_count2df/STA_eflux2df` 的默认参数 `m_int`；`n1d` 的 `1.0-31` 笔误。
4. **P3（对外兼容性备注）**：`Quaternion_Rot` 参数类型、`get_quality_flag`、`get_min_bounding_box`、`sta_v_4d` 等返回值类型变化，建议在迁移文档中列出，外部代码按第 3.4 节清单适配。

---

## 附录 B：BUG-1 修复记录（2026-10-12）

**修复对象**：`Magnetic_Model/IGRF_calculate.jl` 中纯 Julia `IGRF()` 的累加器清零缺陷（报告第 3.1 节）。

**补丁（最小改动，净 −2 行）**：

```diff
@@ 循环外初始化（保留并补充注释）
     P[1, 1] = 1.0e0
     DP[1, 1] = 0.0e0 #; DDP[1,1] = 0.0e0
+    # BR/BT/BP 为跨阶累加器：仅在此处初始化一次，循环内只做累加、切勿重新清零
     BR = 0.0e0
     BT = 0.0e0
     BP = 0.0e0
@@ for N = 1:NIGRF（删除循环内清零）
         XX = 0.0e0
         YY = 0.0e0
         ZZ = 0.0e0
-    BR = 0.0e0
-    BT = 0.0e0
-    BP = 0.0e0
```

**回归验证**（修复后的工作区实现 vs 旧版 `af1362e` 基准，逐位对比）：

| 输入 `(r, θ, φ)` | 修复后 & 旧版基准 `(BR, BT, BP, BB)`（两者完全一致） |
|---|---|
| `(3393.5, 1.0, 0.5)` | `(222.8124601609425, 228.2354235064542, 194.4571322343599, 373.56442178418627)` |
| `(4393.5, 0.7, -1.2)` | `(-0.4936054274357313, -0.24372346416745122, -0.23088785027319209, 0.5969561494645732)` |
| `(6000.0, 0.3, 2.0)` | `(-0.3933491506744059, -0.03727671529521287, -0.04723712191362957, 0.39792518584045405)` |
| `(3593.5, 1.2, -0.4)` | `(50.94863948372746, 20.832404983331703, 4.909258721172984, 55.26168459089706)` |

**副作用检查**（冒烟测试，修复未触及该函数以外的任何代码）：

- `pc2sphere` → `sphere2pc` 往返误差 `4.4e-16`；
- `Bpc2sphere` → `Bsphere2pc`（修正坐标系传参后）往返误差 `5.6e-17`；
- 模块加载、`IGRF()` 调用均正常，静态检查（IDE 诊断）无告警。

**复现命令**：

```powershell
julia --project=@v1.10 "$env:TEMP\pkgdiff\igrf_test.jl" "c:/Users/chengsw/Projects/Package_for_Julia_of_csw"
```

---

*报告完。本报告基于 `af1362e..a42e14b` 的静态与动态证据；动态验证环境为 Julia 1.10.0 + Rotations 1.7.1 + Quaternions 0.7.6。附录 B 的修复补丁于 2026-10-12 追加。*
