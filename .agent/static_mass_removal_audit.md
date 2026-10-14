# static_mass_removal_audit.md — STATIC 质量常量替换与 `sta_v_4d_new` 删除边界（t3）

> 任务：t3 [science]（团队 `marsdata-flash-execution`）｜执行：official-engineer，**接手**（旧 GLM 已停止）
> attempt 2 / `5db1e6b9-d0c1-4585-b3f0-dc609eac711f`｜日期 2026-10-14
> 基线：`46db822425378d4ad99f8f0b7cfed07360118486`（源码逐字节）
> **范围（按队长收窄令）**：① 仅 `MAVEN_STATIC` 的 `dat[:mass]` 读取点清单 + `constants.mp_eV_per_km_s2` 替换边界；② 全仓 `sta_v_4d_new` 定义/调用/文档引用清单及删除所需关联修改；③ 最少测试建议。**mass_arr 不改、SWIA/MINPA 不改**；用户物理解释（HD-10）为授权，不追溯数据包生产者、不重复推导科学正确性；不跑大型实验、不建验证框架、**不修改源码**；未知项列"待验证"即可。
> **前任交接**：接手时 `.agent/static_mass_removal_audit.md` **不存在**（`Test-Path`=False），无既有成果可保留；本报告为全量重做。
> 纪律：只读；本报告是唯一产出。

> **勘误（2026-10-14，队长复核后；本报告已就地修订并保留修订痕迹）**
> 1. **数值错误已更正**：§1.1 原写 `constants.mp_eV_per_km_s2 ≈ 9.6485e8`，**该值错误**（未实测即写出）。只读 Julia 实测：`mp*1e6/e = 0.010439684891821985`（`typeof = Float64`；倒数 `e/(mp*1e6) = 95.78833177075664`）。报告中该处已改为实测值；凡"量级差 ×N"的未实测倍数一律删除，改为"须以 fixture 实测"。
> 2. **类型过度断言已撤回**：原把 `sta_v_4d_new:631-633` 的局部 `::Float32` 断言当作 `dat[:mass]` 全仓真实 dtype 的证据，并据此推断"其余函数必提升 / 验收只能容差"。**该推断不成立**：`:633` 属**待删函数**的局部假设，不能外推；`dat[:mass]` 真实 dtype 本次未观测（SWIA 路径 `:89/:197` 写入的是 Float64 常量）。
> 3. **判定口径更正**：**是否 exact 或只能用容差，由实际 fixture 与输出证据决定**，本审计不预判（§4 T1 记录"逐位一致则 `isequal`，否则 rtol + 两侧 dtype"两种结果）。

---

## 0. 结论摘要

| # | 结论 |
|---|---|
| 1 | `MAVEN_STATIC.jl` 中 `dat[:mass]` 共 **10 个读取点**（237/301/321/332/442/575/633/732/949/990）；其中 **633 位于待删函数 `sta_v_4d_new` 内** ⇒ 实际待替换 **9 点**。全部读取点语义均为同一角色：**质量基准**（单位特定的质子质量，进入 `mass²`/`mass^-1.5` 因子）。 |
| 2 | **不替换**：`dat[:mass_arr]`（质量数数组，逐能量道的质量数）、`m_int`（离子质量数 1/2/16/22/32/44）、SWIA、MINPA、`MarsCommon.ion_energy2v`（另一套 `KEV_PER_AMU` 约定）。 |
| 3 | 替换**是否为 exact 不能预判，须由实际 fixture 与输出证据决定**：`constants.mp_eV_per_km_s2` 只读实测为 **Float64 = 0.010439684891821985**；`dat[:mass]` 的**真实 dtype 本次未观测**（唯一代码线索是**待删函数** `sta_v_4d_new:631-633` 的局部断言，不能外推为全仓证据）。若其与常量为 Float64 同值，相关路径可逐位一致；若为 Float32/整数，则存在提升或断言差异。详见 §2、§4。 |
| 4 | `sta_v_4d_new` 删除范围 = **`MAVEN_STATIC.jl:597-688`（含 docstring，92 行）**；全仓**无生产调用**，仅 `benchmark/bench_03_sta_v4d.jl` 的等价性对比与 2 处现行文档引用；`test/runtests.jl` **零引用** ⇒ 删除不影响测试面。 |

---

## 1. ① `dat[:mass]` 读取点与替换边界

### 1.1 参照定义

| 符号 | 位置 | 值/类型 | 语义 |
|---|---|---|---|
| `constants.mp_eV_per_km_s2` | `common/constants.jl:20` | `mp*1e6/e`，`mp=1.67262192e-27`（`:5`），`e=1.602176634e-19`（`:3`）⇒ **Float64 = 0.010439684891821985**（只读 Julia 实测；其倒数 `e/(mp*1e6)` = 95.78833177075664） | **质子静止质量在「eV/(km/s)²」单位的系数**：`E[eV] = ½·mp_eV_per_km_s2·v[km/s]²` |
| `dat[:mass]` | 数据包（c6）经 `static_slip` 浅拷贝（`:471-474`）进入切片 | **本次未直接观测**；仅待删函数 `sta_v_4d_new:633` 有局部 `(dat[:mass]*m_int)::Float32` 断言，**不能当作全仓真实 dtype 的证据**（SWIA 路径 `:89/:197` 写入的就是 Float64 常量） | **质量基准**（同一物理量，供公式配平） |
| `dat[:mass_arr]` | `:238`、`:504`（按 swp 切片） | 未直接观测（来源同上一行的局部断言，不作全仓结论） | **质量数数组**（逐能量道的质量数） |
| `m_int` | `:18-46` `ion_mass_range`（1/2/16/22；调用处另用 32/44） | Int | **离子质量数** |
| 最终粒子质量 | `dat[:mass] .* dat[:mass_arr]`（`:301/:321`）或 `dat[:mass]*m_int`（`:442/:575/:633/:732/:990`） | — | **质量基准 × 质量数** |

### 1.2 读取点清单（10 点，逐点角色与处置）

| # | 行 | 所在函数 | 表达式 | 角色 | 处置 |
|---|---|---|---|---|---|
| 1 | 237 | `STA_count2df` | `local mass = dat[:mass]` | 质量基准（→ `:243 (mass*mass)/(dt*2.0*1e5)`、`:245 df_t`、`:247 df_mass_mass`） | **替换** |
| 2 | 301 | `STA_count3df_all` | `mass[i,:,:] = dat[:mass].*dat[:mass_arr][:,:,swp_ind+1]` | 基准×质量数 = **最终粒子质量**（3D 支路） | **替换**（只换基准因子） |
| 3 | 321 | 同上 | `mass[i,:,:,:] = dat[:mass].*dat[:mass_arr][:,:,:,swp_ind+1]` | 同上（4D 支路） | **替换** |
| 4 | 332 | 同上 | `dat[:df_mass_mass] = scale .* tmp .* dat[:mass]^2` | **基准²**（`:329` 注释明确此处"没有乘以质量数"） | **替换** |
| 5 | 442 | `STA_eflux2df` | `local mass = dat[:mass].*m_int` | 基准×质量数 = 最终粒子质量（→ `:443 scale`） | **替换** |
| 6 | 575 | `sta_v_4d` | `local mass=dat[:mass]*m_int` | 同上（→ `:577 Const`、`:589 Const`） | **替换** |
| 7 | 633 | `sta_v_4d_new` | `mass = (dat[:mass] * m_int)::Float32` | 同上 | **不替换**（该函数整体删除，见 §3） |
| 8 | 732 | `sta_n_4d` | `local mass=dat[:mass]*m_int` | 同上 | **替换** |
| 9 | 949 | `expand_3d` 系（df 构造） | `scale = dat[:mass]^2*5e-6` | **基准²**（`:950` 注释"没有乘以质量数的平方"） | **替换** |
| 10 | 990 | `sta_v_1d` | `local mass=dat[:mass]*m_int` | 基准×质量数 | **替换** |

> 同函数内的 `dat[:mass_arr]` 使用（`:248 dat[:df] = @. df_t * mass_arr^2`、`:331`、`:951`）**一律不改**：它们是"把假设质量换成逐道质量数"的那一步，替换基准后该关系式仍然成立（见 §4 T6）。

### 1.3 不得替换 / 不得外推（边界）

| 对象 | 位置 | 原因 |
|---|---|---|
| `dat[:mass_arr]`（含 `:mass_arr3d`） | `:238,248,301,321,331,504,572,631,727,830,928,951,987` | 质量数数组，非质量基准 |
| `m_int` | `:18-46` 与各签名 | 离子质量数；HD-10 明示不得外推到 MINPA/其它仪器 |
| `MAVEN_SWIA.jl` | `:89`、`:197` `dat[:mass] = constants.mp_eV_per_km_s2` | **已**采用该常量（本次替换的同一口径，不重复改） |
| `TW_data/TW_MINPA.jl` | `:101 mass=[1,2,4,16,28,32,44,64]`、`:207 :mass => mass` | 质量数数组（硬证据：HD-10 禁止外推） |
| `common/MarsCommon.jl:227 ion_energy2v` | 用 `constants.KEV_PER_AMU`（AMU 相对论约定） | 另一套质量约定；`MAVEN_STATIC.jl:851` 调用它属能量换算，非本次替换面 |
| `MAVEN_plot`/`MAVEN_SWEA`/`MAVEN_load` | 仅注释与副本说明 | 无 `dat[:mass]` 读取 |

### 1.4 相关"写入点"（替换后可能成为新风险源，须一并记录）

| 行 | 写入 | 类型 | 影响 |
|---|---|---|---|
| 178 / 188 | `:mass => mass_out` | `mass_out[:, :] = mean(mass_arr .* mask, dims=2)`（`MAVEN_load.jl:1131`） ⇒ **质量数均值数组** | 名为 `:mass` 实为质量数：若被下游当基准使用则数值量级错误（具体偏差须以 fixture 实测，本审计不给倍数）；替换基准后 STATIC 内部不再读它，风险降低 |
| 867 | `:mass => m_int`（`static_slip_2_V` 返回） | **Int** | 生产链（§1.5）不使用该返回；但若有人把它喂给 `sta_v_4d`/`sta_n_4d`/`sta_v_1d`，会把**质量数**当作质量基准使用，数值量级错误（具体偏差须以 fixture 实测，本审计不给倍数） |

### 1.5 生产链（确认上表角色，非追溯生产者）

`MAVEN_data/Build_data/STATIC_VD.jl:56 → 60 → 63/67/71/75/79`：`static_slip(ion_data, time_ind)` → `STA_count2df` → `sta_v_4d(...; unit_cover=false)`。
`static_slip`（`MAVEN_STATIC.jl:470-474`）浅拷贝**全部键**后按 swp 重切 ⇒ `dat_slip[:mass]` = 数据包原始基准（**不是** `m_int`）⇒ §1.2 的角色判定成立。

---

## 2. 浮点类型与运算次序（**显式报告，不预判 exact/容差**）

| # | 事实 | 依据 |
|---|---|---|
| F1 | `constants.mp_eV_per_km_s2` **实测**为 Float64（`0.010439684891821985`）；`dat[:mass]` 的**真实 dtype 本次未观测**——`:631-633` 的 `::Float32` 是**待删函数**内的局部断言，不构成全仓证据（U-B） | 只读 Julia 实测；`constants.jl:5,20`；`MAVEN_STATIC.jl:631-633`（仅作线索） |
| F2 | **条件性**：仅当 `dat[:mass]` 现为 Float32/整数时，`(dat[:mass]*m_int)::Float32` 在替换为 Float64 常量后会得 Float64 ⇒ `TypeError`；该行随 `sta_v_4d_new` 删除而消失（§3），故**不构成本次替换的实际风险** | `:633` |
| F3 | **条件性**：**若** `dat[:mass]` 现为 Float32，则替换后 `Const`/`flux0`/`masked_data`/`scale`/`df` 由 Float32 参与变为 Float64 参与 ⇒ 可能产生末位差异；**若**现为 Float64（如 SWIA 路径），则无提升。是否发生**由 fixture 与输出证据判定**，本审计不预判 | `:243,330,443,577,589,637,949` |
| F4 | 若为保持类型改用 `Float32(constants.mp_eV_per_km_s2)`：**实测** `Float32(0.010439684891821985) = 0.010439685 ≠ 常量本身`（该转换本身有损）；它与**数据包原值**是否逐位相等仍未验证（U-A） | 只读 Julia 实测；无 CDF 数据 |
| F5 | **运算次序**：`2.0/mass/mass*1e5`（`:577`）、`mass^(-1.5)`（`:589`/`:638`）、`(mass*mass)/(dt*2.0*1e5)`（`:243`）写法各异；**只允许替换质量来源，禁止顺带重排或改写为 `mass^2` 形式**，否则引入额外舍入差 | `:243,577,589,638` |
| F6 | 既有混合类型：同一函数内 `data0::Float64`（`:624`）与其余 `Float32`（`:625-631`）混用；`sta_v_4d` 的 `data0` 来自 `dat[:df]`（`:562`；`STA_count2df:247` 写出） | `:562,624-631` |
| F7 | `mass^(-1.5)`：Float32 底数 + Float64 字面指数 ⇒ **今天已是 Float64 结果**；替换不改变该算子类型，只改变底数来源 | `:589,638`；Julia 类型提升规则 |

**结论**：以"完全等效"为依据的替换在**物理语义**上成立（用户授权）。**是否可声称 exact、还是必须记录容差，取决于实际 fixture 与输出证据**：常量已实测为 Float64（`0.010439684891821985`），而 `dat[:mass]` 的真实 dtype 本次未观测。因此 §4 的 T1 同时记录"逐位一致 → `isequal`"与"否则 → rtol + 两侧 dtype"两种结果，**不预先规定只能容差**。

---

## 3. ② `sta_v_4d_new` 定义/调用/文档清单与删除关联修改

### 3.1 定义与删除边界

| 项 | 位置 | 处置 |
|---|---|---|
| docstring | `MAVEN_STATIC.jl:597-616`（含 `:598` 签名行、`:600` "`sta_v_4d` 的优化实现"、`:608` 参数说明、`:614` "与 `sta_v_4d` 数值等价"） | **连同函数一并删除**（不保留兼容、不留转发） |
| 函数体 | `:617-688`（`:619` valid 检查、`:623-634 @views` 类型锚定、`:637-638` 常数、`:647-681` 单循环、`:684-687` 返回） | **删除** |
| 删除区间 | **597–688 共 92 行**（`:596` 为 `sta_v_4d` 的 `end`；`:689` 起为 `sta_n_4d` 的 docstring） | 删除后需保留 1 个空行分界（现状 `:596` 与 `:597` 之间为换行直连，`:688` 与 `:689` 亦直连 ⇒ 删完自然衔接，专人确认无多余空行） |
| 导出 | `:15` `# export …sta_v_4d`（**注释行**，未含 `_new`） | 无需改 |

### 3.2 引用清单（定义之外）

| 载体 | 位置 | 内容 | 处置 |
|---|---|---|---|
| benchmark（**必须处理**） | `benchmark/bench_03_sta_v4d.jl:2`（标题"`sta_v_4d` vs `sta_v_4d_new` 等价性测试"）、`:22`（println 标题）、`:35-39`（`has_new=isdefined(sta,:sta_v_4d_new)` 与打印）、`:81`（"等价性测试：…"）、`:93-95`（`sta.sta_v_4d_new(d1_dat)` 调用与失败打印）、`:143-151`（`b_old`/`b_new` 双基准对比） | 等价性/性能对比段 | 按任务口径**更新或移除比较段**（建议：删除 new 侧全部引用；文件改为单函数基线，标题/println 同步），**不得**保留 `isdefined` 兼容分支 |
| 现行文档 | `docs/src/api.md:119`（"`sta_v_4d`、`sta_v_4d_new`：由 STATIC 四维分布计算速度…"） | 并列介绍 | 改为只列 `sta_v_4d` |
| 历史记录（**只保留历史说明，不改写**） | `docs/reports/refactoring_audit_a42e14b.md:21,171,209,278`；`benchmark/results/baseline_report.md:81`（表格"⏳ 待创建 \| sta_v_4d vs sta_v_4d_new"） | 历史审计/计划表 | 不改；如需标注，仅在 t10 交接层记录"该函数已删除" |
| 测试 | `test/runtests.jl` | **零引用**（全仓 grep `sta_v_4d_new` 无 runtests 命中） | 无需改；删除后测试计数应保持 t7 现场值 **141 Pass / 1 Broken** |
| 生产调用点 | `MAVEN_data/Build_data/STATIC_VD.jl:63,67,71,75,79` 全部调用 `sta_v_4d` | 无 `_new` 调用 | 无需改 |

> **净影响**：删除 1 个定义（92 行）+ 1 段 benchmark 对比 + 1 行现行文档；无生产调用点断裂，无测试引用。

---

## 4. ③ 最少测试建议（不建框架，人工/既有 runtests 可选挂载）

| ID | 输入 | 断言（**由 fixture 实测决定 exact 或 rtol，不预判**） | 目的 |
|---|---|---|---|
| T1 | `dat[:mass]` 取 `constants.mp_eV_per_km_s2` 同值，Float64 与 Float32 各一轮 | 逐项比对替换前后 `sta_v_4d`/`sta_n_4d`/`sta_v_1d`/`STA_count2df`/`STA_count3df_all` 输出：**逐位一致则记 `isequal`（exact）**，否则记 rtol 与两侧 dtype | 同值情形：确定该路径究竟逐位一致还是仅有末位差 |
| T2 | `dat[:mass]` 取与常量**明显不同**的值（如 `constants.mp_eV_per_km_s2 * 1.0001`，另跑 Float32 变体） | 结果相对 T1 **改变**（超出 T1 实测得到的判定阈值） | 证明替换真的生效，防"空改" |
| T3 | `delete!(dat, :mass)`（**缺失**） | 替换后上述函数**不再抛 `KeyError`** | 证明替换边界穷尽（9 点全覆盖） |
| T4 | Float32 输入 / Float64 输入各一遍 | 记录输出 dtype 与控制台类型变化；Float32 输入不得因类型断言抛错（`:633` 已删） | 覆盖 F1/F2/F3 |
| T5 | `dat[:valid] = 0` | `sta_v_4d` 仍返回 `(SVector(NaN,NaN,NaN), SVector(NaN,NaN,NaN), NaN)` 并打印 `"Invalid Data"` | 保 NaN/println 行为（`:548-551`） |
| T6 | 任意有效切片 | `dat[:df] ≈ dat[:df_mass_mass] .* mass_arr.^2`（`:248`、`:331-332`、`:950-951` 三处关系） | 替换基准后"基准²·质量数²"关系仍成立 |
| T7 | benchmark | `bench_03` 删除 `_new` 段后可运行（`has_old=true`），无对 `sta_v_4d_new` 的残留引用（`grep` 零命中） | 对比段处置闭环 |

补充：`mass_arr`/`m_int`/SWIA/MINPA **不在任何测试中作为被改对象**（回归面为零）。

---

## 5. 风险与未知（明确列"待验证"）

| ID | 项 | 级别 | 说明 |
|---|---|---|---|
| R-1 | 替换后**可能**发生 Float32→Float64 提升（取决于 fixture 的实际 dtype）而引入末位差异 | 中 | §2 F1/F3；须以实测记录 dtype 与差异，不得预判为 exact 或容差 |
| R-2 | 若只替换部分读取点（漏 1 点），会出现"半数用常量、半数用数据包"的**混合基准**，结果自相矛盾 | 高（执行风险） | 9 点须同批；§1.2 表即核对清单 |
| R-3 | 顺带重排运算（把 `2.0/mass/mass*1e5` 改成 `mass^2`）引入额外舍入差 | 中 | §2 F5 禁止 |
| R-4 | 历史文档若被"顺手更新"，破坏历史可追溯性 | 低 | §3.2 明确仅保留历史说明 |
| R-5 | benchmark 若保留 `isdefined(:sta_v_4d_new)` 兼容分支，违背"不保留兼容"口径 | 中 | §3.2 明确 |
| U-A | 数据包（c6）`dat[:mass]` 的**实际 dtype 与取值**（是否等于 `constants.mp_eV_per_km_s2`，或等于 `Float32(常量) = 0.010439685`）；本次无 CDF 数据、按授权不追溯生产者 | — | **待验证**（有 fixture 后 1 行断言即可判定该路径是 exact 还是仅容差一致） |
| U-B | `dat[:mass]`/`dat[:mass_arr]` 的真实 dtype 本次**未直接观测**；`:631-633` 的 `::Float32` 属**待删函数**的局部断言，**不得**当作全仓证据，也不得据此认定其余函数 dtype 必提升 | — | 待验证 |
| U-C | 是否仍有仓外脚本调用 `sta_v_4d_new`（仓内已确认为零生产调用） | — | 待验证（HD-13：仅文档标注） |
| U-D | `:mass => mass_out`（`:178/:188`）与 `:mass => m_int`（`:867`）这两个"名为 mass 实为质量数/整数"的输出是否另有消费者依赖 | — | 待验证（超出本任务收窄范围，已记录不追） |

---

### 附：本次审计实际执行的只读命令（可复现）

```
grep -n ":mass|mp_eV_per_km_s2|AMU|1\.67262192|938313" MAVEN_data/MAVEN_STATIC.jl      # 41 命中
grep -n "m_int" MAVEN_data/MAVEN_STATIC.jl                                             # 52 命中
grep -rn "sta_v_4d_new|sta_v_4d\b" .                                                    # 43 命中
grep -rn ":mass\s*=>|\[:mass\]\s*=" --glob "*.jl"                                       # 9 命中（写入点）
grep -n "mp_eV_per_km_s2" MAVEN_data/MAVEN_SWIA.jl                                     # :89 :197
grep -n -A4 "function ion_energy2v" common/MarsCommon.jl                               # :227
（人工阅读）MAVEN_STATIC.jl:228-251, 295-340, 436-446, 470-511, 545-602, 603-618, 617-692, 940-955 ;
          common/constants.jl:1-30 ; MAVEN_data/Build_data/STATIC_VD.jl:50-74 ;
          benchmark/bench_03_sta_v4d.jl（引用行）; docs/src/api.md:119
Test-Path .agent/static_mass_removal_audit.md   # False（前任未落盘）
```

> 报告结束。本文件为 t3 唯一产出；**未修改任何源码**。执行者按 §1.2 的 9 点清单 + §3.1 的 597–688 删除区间 + §3.2 的 benchmark/文档处置执行，并以 §4 的 T1–T7 验收。
