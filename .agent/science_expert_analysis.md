# science_expert_analysis.md — 科研语义 / 数据契约 / 单位坐标 / 行为兼容性审查

> 任务：t4 [science-analysis]「分析科研语义、数据契约与兼容性」
> 执行：pro-science（DeepSeek Pro / Official，科研计算专家）— attempt 1 / `cc9b801b-c806-4353-9718-4965d31a48b9`
> 日期：2026-10-14
> 输入（只读）：`new_plan.md`、`.agent/current_state_recovery.md`（t1 交付）、`.agent/03_ARCHITECTURE_PLAN.md`（§15 C 类决策 + 附录 A）、`.agent/06_IMPLEMENTATION_LOG.md`（含《常数出处与 SPEDAS 对照表》）、`.agent/02_ARCHITECTURE_REVIEW.md`（AR-9/18/19/20），以及按需定向读取的源码与 `test/runtests.jl`。
> 方法：**继承旧记录 + 定向复核**，未整仓重扫、未重复架构全量扫描。只回答科研语义、数据契约、单位/坐标约定、行为兼容性问题；不讨论模块归属/依赖方向/扩展性（属 pro-architecture 分工）。
> 本文件是本次 t4 的**唯一写入产物**；未改任何项目代码/测试/配置/`new_plan.md`，未创建子 Agent，未轮询成员。

---

## 0. 结论速览（TL;DR）

| # | 结论 | 证据 |
|---|---|---|
| 1 | `DataKeys` 是**部分契约**：只覆盖"头脸"键，多个高频计算键缺失，最严重是 **`:mass`**（SWIA/STATIC/MINPA/Pickup 全链路使用）与 **`:df_mass_mass`**（STATIC 矩核心 + Pickup_ion） | §1 |
| 2 | **`:mass` 键语义跨模块不一致**（SWIA 存 `mp_eV_per_km_s2` 常量 vs STATIC/MINPA 存 AMU 质量数），属"必须保留、禁止机械统一"的语义红线 | §2.4 |
| 3 | **角度约定跨仪器不一致**：SWIA 内部用度（cosd/sind）、STATIC 存度并转弧度、MINPA 存弧度、MarsCommon 坐标函数用度；迁移严禁混用 | §2.1 |
| 4 | C6/C7/C10/C11/C12/C13 六项疑点**全部无法在当前仓库内闭环**（无 IDL/SPEDAS 参考源码、无真实数据），均须人类裁决；已给出每项的可验证出处 + 方法 + 容差建议 | §3 |
| 5 | P6 科学改动的"行为不变"证据强度：**仅 TASK-019/020/021/024 有自动化测试**；TASK-003/004/018/022/023/025 **无任何自动化测试**（仅 06 日志声明或 grep 断言），须按 §4 分级对待 | §4 |
| 6 | TASK-025（`kp_columns`）**完全可合成验证**（无需真实数据），是最优先补测项；TASK-009/010/011/013 可用无数据/合成 fixture 最小验证；TASK-021 `:adaptive` 受 DLL 符号缺失阻塞 | §5 |
| 7 | 语义红线已清单化：默认磁力线 `:euler`、`get_mag_line_s` 双键回退、`static_slip` 视图共享内存、NaN/Inf/missing 处置、`flags&1` RV 判定、两套 PSD 并存、`constants` 破坏性数值（μ0/e） | §2 |
| 8 | "合成基线 ≠ 科学正确性"边界表述已固化，供最终交付使用 | §7 |

---

## 1. 数据键契约复核（对应 t1 分工问题 1）

### 1.1 已覆盖（DataKeys 常量 ↔ 实际键一致）

`common/data_keys.jl` 的 23 个 Symbol 常量 + 3 个 legacy 字符串键，与 `.agent/03` 附录 A 逐项一致，且有测试断言（`test/runtests.jl:54-73` 共 18 条）。核心时间/场/能道键（`:epoch`/`:time`/`:time_unix`/`:B`/`:B_total`/`:position`/`:energy`/`:denergy`/`:df`/`:eflux`/`:diff_en_fluxes`/`:quat_mso`/`:S`/`:alt` 等）在代码中确有对应生产/消费点，无冲突。

### 1.2 缺失键（DataKeys 与附录 A 均未登记，但代码高频使用）

| 缺失键 | 使用位置（证据） | 语义 | 风险 |
|---|---|---|---|
| **`:mass`** | `common/MarsCommon.jl:389`（`eflux_to_df!` 读 `data[:mass]`）；`MAVEN_data/MAVEN_SWIA.jl:89,197`（`get_3dc!/get_3df!` 写 `dat[:mass]`）；`MAVEN_data/MAVEN_STATIC.jl:442,575,633,732,990`（`STA_eflux2df`/`sta_v_4d`/`sta_v_4d_new`/`sta_n_4d`/`sta_v_1d`）；`TW_data/TW_MINPA.jl:207,366,413,501`；`models/Pickup_ion.jl:76,103,111` | **跨模块语义不一致**（§2.4） | 高：DataKeys 只定义了 `MASS_ARR=:mass_arr`、`NMASS=:nmass`，漏掉最核心的 `:mass` |
| **`:df_mass_mass`** | `MAVEN_data/MAVEN_STATIC.jl:247,332,508,564,624,719,981`；`models/Pickup_ion.jl:93,357` | 未乘 `mass²` 的中间相空间密度 | 中：附录 A 有 `:df / :df_mass_mass`（`.agent/03:735`），但 DataKeys 只有 `DF`，漏掉 `DF_MASS_MASS` |
| 角度/速度网格元数据 `:theta` `:dtheta` `:phi` `:dphi` `:domega` `:nanode` `:ndeflect` `:ntheta` `:nphi` `:ntime` | `MAVEN_SWIA.jl:71-89,179-197`（写）；`MAVEN_SWIA.jl:261,316,375`、`MAVEN_STATIC.jl:570-571,629-630,985-986`、`TW_MINPA.jl:404-415,494-503`、`models/Pickup_ion.jl:74,98-126`（读） | 各仪器角度网格 + 维度元数据 | 中：这些是矩积分公式的输入，键名漂移即数值错误 |
| `:psd` `:data` `:bkg` `:dead` `:gf` `:eff` `:geom_factor` `:time_integ` `:quality_flag` `:bins_sc` `:quat_sc` `:magf` `:pos_sc_mso` | `TW_MINPA.jl:376`（`:psd`）；`MAVEN_STATIC.jl:404-418,479-496`（STATIC 切片键）；`MAVEN_SWEA.jl:135-195`（注释区引用） | 计数/标定/姿态字段 | 低-中：STATIC 切片结构已在 `test/runtests.jl:79-106` 固化，但契约表未登记 |
| `:differential_flux` | `TW_MINPA.jl:193,368,402,490` | MINPA 原始微分方向通量 | 低：MINPA 特有键 |
| `:flag` `:yaw` `:pitch` `:roll` | `TW_data/TW_load.jl:103-106` | TW 2C 质量标志/姿态角 | 低：TW 特有键 |

### 1.3 Legacy 字符串键复核

| 键 | 登记状态 | 证据 | 复核结论 |
|---|---|---|---|
| `"B"` | `DataKeys.B_FIELD_LEGACY`（`data_keys.jl:114`） | `Magnetic_Model/IGRF_calculate.jl:717-720`（`get_mag_line_s` 先 `:B` 后 `"B"` 回退） | 一致，回退语义已被 TASK-004 修复 |
| `"Vars"` | `DataKeys.VARS_LEGACY`（`data_keys.jl:117`） | `MGS_data/MGS_load.jl:91` | 一致 |
| `"data staute"` | `DataKeys.DATA_STATUS_LEGACY`（`data_keys.jl:120`） | `MGS_data/MGS_load.jl:89` | 一致（拼写错误被登记保留） |
| `"Var name"` | **未登记** | `MGS_data/MGS_load.jl:90` | 低：纯描述性元数据键，建议附录 A 补一行 |
| `:vars` `:var_190`（KP L3 旧格式） | 附录 A 登记为 legacy（`.agent/03:742`） | `models/Pickup_ion.jl` 旧路径 | 一致，S9 迁移后消除 |

### 1.4 结构契约差异（非键名，但属契约）

- **MGS `load_mag` 返回 `Dict{String,Any}`，且 `"Vars"` 是位置列表**（`MGS_load.jl:88-92`：`"Vars" => [times, B_total, B, position]`），与 MAVEN/TW 的 `Dict{Symbol,Any}` + 具名键不同。下游按位置取数，迁移/文档须明确标注。
- **TW `load_mag_2c_bydlm` 同时产出 `:time` 与 `:epoch`（同值）**（`TW_load.jl:98-99`），违反"`:epoch` 为 CDF、`:time` 为文本源"的附录 A 约定（`.agent/03:725-726`）。属双键冗余，登记即可，不强制改。

---

## 2. 单位 / 坐标 / 结构语义红线（对应 t1 分工问题 5）

> 这些是"迁移中必须逐字保持、禁止顺手统一"的行为语义；证据均已核到源码行。

### 2.1 角度约定（跨仪器不一致，禁止混用）

| 位置 | 角度单位 | 证据 |
|---|---|---|
| SWIA `get_3dc!/get_3df!` / `n_3d` / `j_3d` / `v_3d` | **度**（`cosd/sind`，`deg2rad(dphi)` 只用于立体角） | `MAVEN_SWIA.jl:69,326-328,404-424` |
| STATIC `sta_v_4d` 等 | **存度、用时转弧度**（`dat[:dtheta] .* constants.inv_RADG`，`inv_RADG = π/180`） | `MAVEN_STATIC.jl:570-571,629-630,985-986`；`constants.jl:10-12` |
| MINPA `load_mod1` / `MINPA_sphere2xyz` / `v3d` | **弧度**（`θ=...[deg] .|> deg2rad`，`cos/sin`） | `TW_MINPA.jl:103-104,237-248,505` |
| MarsCommon 坐标函数 | **度**（`cosd/sind/atand/acosd`） | `common/MarsCommon.jl:69-71,97-98,123-127` |

- 附加约定：`MAVEN_load.jl:5` 头注「STATIC 中的 theta 值在球坐标系下，应当为 90-Theta」，是 STATIC 俯仰角→极角的换算约定，须保留并最终落文档。

### 2.2 输出单位约定（AR-19；"IS 单位"头注是误导）

文件头「所有物理量…输入输出皆为 IS 单位」（`MAVEN_load.jl:6-7`、`MAVEN_SWEA.jl:2-3`、`MAVEN_SWIA.jl:2-3`）与实现不符。实际对外输出为 **SPEDAS 约定**：

| 物理量 | 实际单位 | 证据 |
|---|---|---|
| 密度 | cm⁻³ | `MAVEN_SWIA.jl:225`（`n_3d` 密度 cm⁻³）、`MAVEN_SWIA.jl:353`、`TW_MINPA.jl:464` |
| 速度 | km/s | `MAVEN_SWIA.jl:353,431`（`vel=1e-5·flux/density`）、`MAVEN_STATIC.jl:547`、`TW_MINPA.jl:393` |
| 通量 | cm⁻²s⁻¹ | `MAVEN_SWIA.jl:293,353`、`TW_MINPA.jl:394,462` |
| 相空间密度 | 1/(cm³·(km/s)³)（SPEDAS）与 s³·m⁻⁶（相对论版）**两套并存** | `common/MarsCommon.jl:296,322`（相对论版 s³·m⁻⁶ 量级）vs `ion_eflux_to_psd_approx`（v⁴ 近似）vs `eflux_to_df!`（`MAVEN_STATIC`/`MarsCommon` SPEDAS df） |
| 能量 | eV | `constants.jl:14`；各模块 docstring |
| 质量 | AMU | `MAVEN_STATIC.jl:396`（`m_int` AMU） |
| 磁场 | nT | `DataKeys.B_FIELD`（`data_keys.jl:37`）；`TW_load.jl:64` |
| 距离 | km，`R_Mars = 3393.5 km` | `constants.jl:27`；`DataKeys.POSITION` |

- **迁移红线**：任何去重/合并（ARCH-006）不得把相对论 PSD 与 SPEDAS 近似 PSD 当作同一函数；两者数值在高能区有系统差异（`MarsCommon.jl:357` 已注明"高能区低估"）。

### 2.3 磁力线追踪语义（AR-20 / C1）

- **默认 `method=:euler`（一阶）必须保持，直至人类批准改默认**（`.agent/03:691`；`IGRF_calculate.jl:748,751`）。
- `trace_mag_line` 返回新增 `:method` 键；`:num_steps` **仅在 `output_frame=="pc"` 时定义**（`IGRF_calculate.jl:749,784-790` 之后），迁移不得假设恒存在。
- `get_mag_line_s` 读 `:B` 后回退 `"B"`（`IGRF_calculate.jl:717-720`），双键容忍须保留。

### 2.4 `:mass` 键语义歧义（最高风险的数据契约红线）

同一个 `:mass` 键在不同模块承载**不同含义与单位**：

| 模块 | `:mass` 含义 | 证据 |
|---|---|---|
| SWIA `get_3dc!/get_3df!` | 质子质量常量 `constants.mp_eV_per_km_s2`（eV/(km/s)² 单位制） | `MAVEN_SWIA.jl:89,197` |
| STATIC `STA_eflux2df`/`sta_v_4d` | AMU 质量数（再乘 `m_int`） | `MAVEN_STATIC.jl:442,575` |
| MINPA `load_mod1` | 质量数列表 `[1,2,4,16,28,32,44,64]` AMU | `TW_MINPA.jl:101,207` |

- **迁移红线**：契约文档必须为 `:mass` 注明"含义随生产者模块而异"，**禁止**为"统一"而改动任一模块的 `:mass` 语义或把 `mp_eV_per_km_s2` 与 AMU 混为一谈。当前 DataKeys 未定义 `MASS`，反而避免了"一刀切"误用——补契约时应以"带语义注释的多个常量"（如 `MASS_AMU` / `MASS_EV_PER_KM_S2`）而非单一 `MASS` 处理。

### 2.5 NaN / Inf / missing 处置（现状盘点，属"必须保持"）

| 位置 | 现状处置 | 证据 | 迁移注意 |
|---|---|---|---|
| `MAVEN_load.mean_SWEA_pad_pa` | NaN **互填后平均**（C12，不改） | `MAVEN_load.jl:1003-1011` | 填补顺序影响结果，禁止改 |
| `MAVEN_load.SWEA_calc_shape_arr` | 无效谱置 `NaN`；`flux[isnan].=0` 后求导 | `MAVEN_load.jl:1427,1441` | 保持 |
| `MAVEN_load.carclu_SWEA_pad` 系列 | NaN → `1e-10`（用于 log 绘图） | `MAVEN_load.jl:1185,1209` | 保持 |
| `MAVEN_SWEA.n1d` | `ff = x-> x>1 ? 1.0 : x` 截断，防 `sqrt(1-prat)` 为负 | `MAVEN_SWEA.jl:78-81` | 保持（C4 只删死变量，clamp 未动） |
| `MarsCommon.ion_speed_to_energy` | `v≥c` 时自然产生 NaN/Inf，不设防 | `MarsCommon.jl:251` | 保持 |
| `TW_MINPA.MINPA_get_psd` | `energy=0` 产生 Inf，不设防 | `TW_MINPA.jl:352` | 保持 |
| `TW_MINPA.load_mod1` | `dfi[dfi.<0].=0` 负通量截零 | `TW_MINPA.jl:132` | 保持 |
| `load_cdf` RV 判定 | `v.vdr.flags & 1 == 1`（C13，不改） | `MAVEN_load.jl:326` | 保持 |
| TW `load_mag_2c_bydlm` | NaN 线性插值修复**被注释掉**（未启用） | `TW_load.jl:85-92` | 保持禁用状态，勿"顺手启用" |

> 全仓**未使用 Julia `missing`**（数据缺失统一用 `NaN` 或 `data_load_flag=false` 表达）。迁移不得引入 `missing` 而不改下游。

### 2.6 数值比较现状（对应 new_plan §10）

- 测试内已用 `≈`（`isapprox` 默认）与显式 `rtol`：`test/runtests.jl:187-188`（`≈` 默认）、`:243,255-256,267`（`rtol=1e-12`）。
- 现有科学回归门用 `rel ≤ 1e-12`（`03 §12.2`、`:15` ARCH-009）与 `rel ≤ 1e-9`（`sta_v_4d` 等价门）。**无全局容差定义**（abs/rel/NaN/Inf/missing 语义未落代码，t1 §6.4-2 已指出），Phase B 建 Call Table 时必须定义比较方法，不得用 `==` 统一科学比较。

---

## 3. C 类疑点验证方案（对应 t1 分工问题 2）

> 原则：**全部为"记录不改值"项**（`.agent/03 §15` R5）。当前仓库**没有** IDL/SPEDAS 参考源码、**没有**真实数据，因此本节给出"可验证出处 + 方法 + 容差建议 + 谁来裁决"，**不宣称可闭环**。

| ID | 疑点（证据位置） | 建议 SPEDAS/IDL 出处 | 验证方法（建议） | 容差建议 | 裁决方 |
|---|---|---|---|---|---|
| C6 | `TW_MINPA.v3d` 密度归一化 `1.0E-6*0.2/2`（`TW_MINPA.jl:455,537`）且**弃用 `denergy`** | TW MINPA IDL 矩计算；官方 L2 矩（nH/nO/nO₂/VH/TH，`TW_MINPA.jl:617-631` 注释中的 .mat 参考量） | 同一事件：`v3d` 输出密度/速度 vs 官方矩逐点对比；并算 `Σ dE·E^(-1/2)`（真 denergy 口径）与 `0.2/2` 口径的相对差 | 密度量级一致（1× 内）；速度三分量符号一致，量级 <2× | **使用者**（无参考数据则永久留档） |
| C7 | `TW_MINPA.v3d` `nvy` 取负 + 整体 `vel=-vel`（`TW_MINPA.jl:448,460`） | MINPA 视场方向定义 / MOMAG 速度方向交叉核对 | 与 `TW_load.get_spc2mso_rot_matrix_via_2c` 转到 MSO 后，速度矢量方向与官方/磁场横流方向一致性 | 符号必须一致（方向错误是定性错误） | **使用者** |
| C10 | SWEA shape 能量通道 `13:64`（52 道）+ `df_iono` 模板（`MAVEN_load.jl:1304-1307,1388-1406`） | SPEDAS `mvn_swe_calc_shape_arr.pro` 的模板能量范围 | 核对模板数组 `df_lres/df_hres` 与参考 .pro 逐元素一致；核对 `13:64` 是否对应参考能量范围 | 模板逐元素一致（rel <1e-12） | **使用者**（数值如与参考不符须上报） |
| C11a | SWIA `n_3d/v_3d` 密度系数 `7.224566339926571e-7`（`MAVEN_SWIA.jl:274,417`） | SPEDAS `mvn_swia_get_3dc.pro` / `general/science/n_3d.pro` | 量纲推导：`C = 1e-5·√(m_p/2)/√(2e)` 类常数逐位推导 + 与 SPEDAS 源码常数比对 | 常数解析推导一致（或 rel <1e-6） | **使用者** |
| C11b | SWIA `n_1d` 系数 `sqrt(mp/(2·erg_per_eV))*8.8`（`MAVEN_SWIA.jl:465`） | SPEDAS `mvn_swia_get_spectrum.pro` | 同上：`8.8` 是否为几何因子/单位换算 | 同上 | **使用者** |
| C12 | `mean_SWEA_pad_pa` NaN 互填（`MAVEN_load.jl:1003-1011`） | SPEDAS `mvn_swe_pad_180.pro` | 已知 PAD 文件，对比互填 vs 跳过 vs 单侧三种策略的 180° 平均结果 | 策略须与参考一致；不一致则人工定 | **使用者** |
| C13 | CDF RV 判定 `flags & 1 == 1`（`MAVEN_load.jl:326`） | NASA CDF 规范（vdr.flags bit0）+ `CommonDataFormat.jl` 语义 | 对已知 RV/NRV 文件打印 `flags` 分布，核对 bit0=1 是否为 RV 判据 | 判定规则一致 | **使用者**（规则变更需人类批准） |

**共同结论**：这六项在仓库内**无任何可自动验证的参考**；验证动作全部需要（a）SPEDAS/IDL 参考源码 或（b）真实/官方数据 二者之一，当前均不可得。因此它们**不属于 Phase B/D 的自动化回归范围**，只能作为"人工复核待办"移交，且必须随最终交付的 §7 边界表述一起呈现。

---

## 4. P6 科学改动等价性证据强度分级（对应 t1 分工问题 3）

> 分级定义：**A=有自动化测试且数值可断言**；**B=有自动化测试但只证形状/可用、不证数值**；**C=无自动化测试，仅合成推理或日志声明**；**D=无任何证据**。

| TASK | 改动 | 当前自动化测试（`test/runtests.jl`） | 合成 golden 覆盖 | 强度 | 说明 |
|---|---|---|---|---|---|
| 003 | `STA_count2eflux/STA_eflux2df` `m_int::Real=16` | **无**（runtests 无 `STA_count2eflux` 调用） | `baseline_static.json` 有基线，但**无前后对比记录** | **D** | 06 声称"默认调用与 16 逐位一致"未见测试；且 docstring 仍残留旧口径"默认值引用未定义全局 m_int"（`MAVEN_STATIC.jl:387,402,423,438`） |
| 004 | `get_mag_line_s` 读 `:B` 回退 `"B"` | **无**（runtests 无 `get_mag_line_s` 调用） | 无 | **D** | `trace_mag_line` 测试（C1）未覆盖 `get_mag_line_s` 双键路径 |
| 018 | SWEA `n1d` 删死变量 `tiny` | **无**（runtests 无 `n1d` 测试） | `baseline_swia_swea.json` 有基线，**无前后对比** | **D** | "逐位一致"仅 06 日志声明；`c1/c2` 死常量仍存（`MAVEN_SWEA.jl:51-52`） |
| 019 | SWIA `v_3d` 维度分支（C5） | **有**：`runtests.jl:119-170`（coarse/fine/非法三维） | `baseline_swia_swea.json` | **B** | 只断言形状 + 密度 >0，**不证数值正确**；但 C5 是确定性 bug 修复，形状断言已覆盖核心回归 |
| 020 | `combina_two_dir_trace` 裸名（C2） | **有**：`runtests.jl:172-189`（to_pc=true 与手动 `sphere2pc` 一致，`≈`） | 无 | **B** | 只证 to_pc 与 to_pc=false 内部一致性（自洽），非独立参考 |
| 021 | `trace_mag_line` `method` kwarg（C1） | **有**：`runtests.jl:191-213`（euler 默认/rk4 可用/非法抛错） | `baseline_igrf.json` 为**占位** | **B** | `:adaptive` 被 DLL 符号缺失 gated，未测；bench_07 未做 |
| 022 | SWEA shape 常数具名化（C10） | **无**（runtests 无 `SWEA_calc_shape_arr`） | 无 | **D** | "数值不变"仅靠常量定义等价（`13`/`52`），无回归 |
| 023 | C6/C7/C11/C12/C13 注释（不改值） | **无**（注释改动，runtests 无断言） | 无 | **C** | 06 的"grep 关键词断言"是人工动作，非测试 |
| 024 | Cold_Plasma `PlasmaState`（C8） | **有**：`runtests.jl:215-269`（未初始化报错/纯函数/副作用/rtol=1e-12/线程隔离） | `baseline_coldplasma.json` | **A** | 等价性（旧签名 vs 显式 state）有 `≈ rtol=1e-12` 断言，证据最完整 |
| 025 | `load_kp` `kp_columns` kwarg | **无**（runtests 仅白名单处 `load_kp` 名字断言） | `baseline_loader.json` 为**占位** | **D** | t1 §3 已确认"三条测试缺失"；见 §5.1 |

**分级结论**：P6 十项科学相关改动中，**6 项（003/004/018/022/023/025）在自动化测试上无证据**；只有 024 达 A 级、019/020/021 达 B 级（且 B 级多只证自洽不证数值）。这意味着 S8–S11 大批迁移若依赖"P6 已稳定"的前提，证据是不充分的；**Phase B 的 Call Table 必须先补齐 003/004/018/022/025 的合成回归**（其中 025/004/018/022 完全可合成，无真实数据依赖）。

---

## 5. 最小可执行验证清单（对应 t1 分工问题 4）

> 按"完全可合成（无真实数据）→ 需 fixture → 需 DLL/真实数据"排序；每个都给降级方案。

### 5.1 TASK-025（`kp_columns`）— 最高优先，完全可合成

- 前置：`MAVEN_load` 加载期已从 `MAVEN_data_format.json` 读入 `kp_dict`（`MAVEN_load.jl:31-33`），故默认路径用 JSON 列映射；`change_kp_read_data` 写 `_kp_dict[]`（`:252`）。
- 最小三条测试（合成 KP 文本 fixture，固定列宽，5–20 行）：
  1. `load_kp(fixture)` 默认 `kp_columns` 解析出 JSON `kp_dict` 中的列；
  2. `load_kp(fixture; kp_columns=custom)` 解析自定义列，结果与手算一致；
  3. `change_kp_read_data(custom)` 后 `load_kp(fixture)`（不传 kwarg）取到新映射（兼容路径），且不污染其它模型。
- **无需真实数据**；这是 t1 明确标记"缺测试"且当前唯一可零成本补足的项。

### 5.2 TASK-009/010/011（路径化）— 无数据环境可验，fixture 增强

| 项 | 最小验证 | 数据依赖 |
|---|---|---|
| 009 SP_load | `load_module(:SP_load)` 无 `IniFile` 读/`println` 副作用；`root_path()` 返回 `Paths.maven_data_root()`；`load_omni2_data` 拼装路径正确 | 无 |
| 010 TW/MGS | `load_module(:TW_load)`/`(:MGS_load)` 在无数据环境成功；`root_path` 等于 `Paths` 默认 | 无；增强：合成 MGS/TW 文本行过 `get_data_from_line_for_mag_read`/`load_mag_2c_bydlm` 验列解析 |
| 011 DLL | `_linear_growth_rate_dll_path()`/`_bspline_dll_path()` 在无 DLL 时抛含指引的清晰错误 | 无 DLL（回退路径测试）；ccall 数值一致性需真实 DLL（opt-in） |

### 5.3 TASK-013（日期索引）— 合成文件列表

- 构造 1000 文件名的合成 `filename_lists.json`，验证 `_file_index` 索引命中与旧 `occursin` 回退**结果一致**（`MAVEN_load.jl:51-72`），并跑 `bench_05` 计时对比。
- 降级：无真实列表时按 t1 口径"空索引 + 回退返回 false/NaN 一致"已是可接受的最小通过。

### 5.4 TASK-021（`trace_mag_line :adaptive`）— DLL 阻塞

- `:euler`/`:rk4` 已测（`runtests.jl:191-213`）；`:adaptive` 需 `IGRF_DLL.dll` 提供 `MAIN_mp_ADAPTIVE_STEP_TRACE` 符号。
- 降级：保持 `:adaptive` 接口 gated 不测，明确标记 blocked；**不要**为过测试而伪造 DLL。

---

## 6. 科学风险清单（额外发现，供队长/人工知悉）

1. **`constants.KeV_PER_AMU = 938313.53`（= 511×1836.23）实为"质子质量 keV"，非"原子质量单位"**（`constants.jl:17`）。`m_int=16` 实际按 16×质子质量计（O⁺ 偏高约 0.7% 量级）。命名误导但数值自洽（`ion_energy2v` 与 `ion_eflux_to_psd` 用同一常数，相对一致）；属"记录不改值"类，勿顺手改。
2. **`STA_count2eflux` 的 `m_int` 参数当前不参与计算**（`MAVEN_STATIC.jl:396,412` 已注明），是无操作参数——用户可能误以为选了离子种类；须在 API 文档显著标注。
3. **`MAVEN_SWEA.n1d` 的 `energy_range` 参数当前未用于掩膜**（docstring `MAVEN_SWEA.jl:38` 已注明）——无操作参数，同样需标注。
4. **`sta_v_4d` vs `sta_v_4d_new` 双实现无等价性证明**（AR-11 门 `rel≤1e-9` 未做）——两套数字并存风险仍在，S8 前必须先跑等价门（合成即可）。
5. **`n_3d/v_3d/n_1d` 假定所有离子为质子**（SWIA 只区分质子，docstring 已注明）——重离子污染密度，科研解释须注意。
6. **`TW_MINPA.v3d` 密度用 `0.2/2` 而非 `denergy`**（C6），与 `load_mod1` 返回的 `denergy` 口径不一致（docstring `TW_MINPA.jl:399` 已注明）——MINPA 密度量级存疑。
7. **SWEA `n1d` 的 `c1/c2` 死常量**（`MAVEN_SWEA.jl:51-52`）未用，属清理项（TASK-043），非科学风险。
8. **`load_mag_l2` 表头定位**（TASK-005）与 `MGS load_mag` 表头定位（`findlast`，`MGS_load.jl:63`）均依赖 `END` 行，坏行容错为"静默丢弃"（`MGS_load.jl:71-80`）——数据质量标志需靠 `flag` 字段（但 MGS 未导出 `flag`）。

---

## 7. "合成基线 ≠ 科学正确性"边界表述（对应 t1 分工问题 6；供最终交付引用）

> 本项目的自动化验证（`test/runtests.jl` + `benchmark/results/baseline_*.json` + 计划中的 AST/Call Table）**只能证明"重构前后行为一致"**，不能证明"当前行为在科学上正确"。合成 golden 快照是**自洽性基线**，不是**真值**。
>
> 科研正确性还需依次满足：(1) 与 SPEDAS/IDL 参考实现逐项对照（C 类疑点，§3）；(2) 真实 MAVEN/TW/MGS 数据交叉验证（密度/速度量级与符号、守恒关系）；(3) 物理 sanity check（密度 >0、通量量级、磁力线闭合/漂移、速度方向与磁场/电场关系）。**在 (1)(2)(3) 达成前，任何"科学正确"声明均不成立**，最终裁决权归项目使用者（`new_plan.md` §17）。

---

## 8. 须用户/队长裁决项汇总

| # | 事项 | 关联 | 建议 |
|---|---|---|---|
| U-1 | C6/C7/C10/C11/C12/C13 六项疑点 | §3 | 全部**使用者裁决**；AI 不改值，仅留注释与对照表 |
| U-2 | `:mass` 键语义歧义是否在 DataKeys/附录 A 中显式登记（`MASS_AMU` vs `MASS_EV_PER_KM_S2`） | §1.2/§2.4 | 建议补契约，**不**改任一模块语义 |
| U-3 | `sta_v_4d` vs `sta_v_4d_new` 等价门（rel≤1e-9）未做即 S8 是否放行 | §6.4 | 建议先补合成等价测试再进 S8 |
| U-4 | `constants` 破坏性数值（μ0=4e-7π、e=1.602176634e-19）派生量口径 | t1 §4.5 | 沿用现有值；下游派生量在文档标注"基于新常量" |
| U-5 | 默认磁力线 `:euler` 是否升级为 `:rk4`/`:adaptive` | §2.3 | 保持 `:euler`；bench_07（三法对比）交人类后再定 |
| U-6 | 是否允许"合成 fixture 补测 025/004/018/022"（写测试，不改产品代码） | §5.1 | 建议列入 Phase B 前置，低成本高收益 |

---

## 9. 合规声明

- **唯一写入**：`.agent/science_expert_analysis.md`（本文件）。未改任何项目代码/测试/配置/`new_plan.md`/`Project.toml`/`Manifest.toml`；未触碰 `.agent/00–06`、`.agent-teams/`。
- **未整仓重扫**：只定向读取了 `common/constants.jl`、`common/MarsCommon.jl`、`common/data_keys.jl`、`MAVEN_data/MAVEN_{load,SWIA,SWEA,STATIC}.jl`、`TW_data/TW_{load,MINPA}.jl`、`MGS_data/MGS_load.jl`、`Magnetic_Model/IGRF_calculate.jl`、`test/runtests.jl`，以及 `.agent/02/03/06` 的相关章节。
- 未创建子 Agent；未查询其他成员进度；未运行会写入仓库的验证命令（无副作用）。
- 所有"证据位置"以**符号名 + 行号**标注，行号随 P6 未提交改动可能漂移（t1 D-5），引用时以符号名为准。
