# science_final_recheck.md — 最终修订版科研语义 / 验证修正的独立复核

> 任务：t10「独立复核最终修订版的科研语义与验证修正」
> 执行：pro-science（DeepSeek Pro / Official，科研计算专家）— attempt 1 / `67d0fb84-9312-43d7-8f39-3540181eb727`
> 日期：2026-10-14
> 被审对象：`.agent/target_architecture_final.md`（t8，chief-architect，人工审查包，未授权施工）
> 复核依据：`.agent/science_draft_review.md`（t7，本成员对草案的审查）与源码定向复核。按最终版 §12 RR-S 七点，逐项复核 F-1…F-8 的处置。
> 本文件是本次 t10 的**唯一写入产物**；未改最终方案/代码/测试/配置/`new_plan.md`，未创建子 Agent，未轮询成员。

---

## 0. 结论速览

**总体：最终修订版对 F-1…F-8 全部八项均已闭合（文档设计层面），可连同 RR-A 一并提交 HA-0。** 有 **1 项低严重度"仍需修订"**（R-1：草案对 `escape_energy` 的"planet≠Mars 时 v 未定义"显式保留注记，在最终版 §4.2/§9 中丢失），另有 1 条可选增强（R-2）。无 blocker、无"须推翻"项。

| 分类 | 内容 |
|---|---|
| **文档设计已闭合** | F-1、F-2、F-3、F-4、F-5、F-6、F-7、F-8 全部在最终版有精确落点，与 t7 要求一致 |
| **仍需修订** | R-1（低）：`escape_energy` 潜在 bug 注记丢失；R-2（可选）：`TimeFormat` 两版 `Dates.format` 字面量应在 MIG-005 显式采集 |
| **待人工裁决** | HD-04（C/E 边界方案）、HD-07（cyclotron 三选项+命名）、HD-08（sta_v_4d 证据处置+println）、HD-09（color_mapping 改名）、HD-10（:mass 常量方案）、HD-11（C 类+backlog） |
| **待实施验证** | B-CYC、B-STA、B-DUP、V-I1…5/V-F1…3/V-R、MIG-005 审计、§4.1 oracle 复测 |
| **科学正确性边界** | 合成回归仍不能代替科学正确（§1-4、§9 SB-* 全部开放/阻塞）；C6-C13 仍需使用者裁决 |

---

## 1. F-1…F-8 逐项复核结论

### F-1 cyclotron 不同参数体系，禁止裸 alias — **闭合**

- 落点：§4.4 + HD-07 + B-CYC。
- 复核：最终版已列三套体系（kg 质量+显式速度 / AMU 质量数+电荷数+能量 / SPO SI），并明确 `MAVEN_load.cyclone_*` 是 kg+速度体系、`calculate_models.cyclotron_*` 是 AMU+能量体系，**禁止** `const cyclone_R = MarsCommon.cyclotron_radius` 跨体系裸 alias。
- 源码核实（本次）：`MAVEN_load.cyclone_frequency`＝`e·B·1e-9/(2π·mass)`（`MAVEN_load.jl:1277-1280`）；`calculate_models.cyclotron_frequency`＝先 `cc=me/(B1·e)` 再 `f=1/(cc·2π)`（`calculate_models.jl:149-158`）。二者电子情形**代数等价但浮点运算顺序不同**——最终版"不能按逐位一致"的判断**正确**。离子情形二者**不代数等价**（`cyclone_*` 默认电子质量、无离子分支），最终版已明确点出。
- 剩余性质：**HD-07 三选项待人工裁决**（推荐 (a) 独立命名）；数值一致性由 **B-CYC exact 用例 + MIG-005 四项结论**在 GATE-B 实施验证。

### F-2 / F-7 `sta_v_4d` 前置条件与副作用独立用例 — **闭合**

- 落点：§6.3 B-STA 五用例（EQ-STA-1/2、SE-STA-1/2、PRE-STA-1）+ HD-08。
- 复核：EQ-STA-1/2 已写明"先 `STA_count2df` 得到**已含 `:df`** 的 `dat_df`"及类型断言前置条件；PRE-STA-1 把"无 `:df` 时 `sta_v_4d_new` 抛 `KeyError`"归为**前置条件差异、不计为数值不等价**；SE-STA-1/2 把就地写入与 `println("Invalid Data")` 副作用单列。
- 源码核实（本次）：`STA_count2df` 确实就地写 `dat[:df]`/`dat[:df_mass_mass]`（`MAVEN_STATIC.jl:247-248`）；`sta_v_4d(unit_cover=true)` 内部调 `STA_count2df`（`:560-561`，副作用+自足）；`sta_v_4d_new` 直接读 `dat[:df]`（`:624`，无副作用、要求已存在）。与最终版断言一致。
- 剩余性质：SE-STA-1 的"以实测为准"是**实施验证**步骤（保守正确）；`println` 是否改 `@warn` 属 **HD-08 人工裁决**。

### F-3 `color_mapping` 命名冲突 — **闭合**

- 落点：§4.5 + HD-09 + AST 遮蔽断言。
- 复核：默认改名 `color_mapping_lut`；两处嵌套定义（`MAVEN_plot.jl:297,537`）已定位为 `STA_2d_slip`/`VDF_2d_slip` 局部函数；三版本等价只作证据、本轮不删嵌套版；AST 断言"顶层不新增与嵌套同名定义 + 嵌套调用点解析不变 + shim 精确绑定 `color_mapping_lut`"。§4.1 计数表也把 `color_mapping` 计为"1 顶层 + 2 嵌套 + 1 注释（不计入）"。
- 剩余性质：改名的最终选择属 **HD-09 人工裁决**（默认"改名"）。

### F-4 `:mass` 双常量同值歧义 — **闭合**

- 落点：§5.4 + HD-10。
- 复核：明确"**禁止**定义多个无前缀、值相同、只靠 docstring 区分语义的常量"；HD-10 选项 (a) 单一 `MASS=:mass`+附录 A 按生产模块注释语义（推荐）/ (b) 带生产者前缀名字。与 t7 建议一致。
- 剩余性质：**HD-10 人工裁决**（默认 (a)）；MIG-042 实施。

### F-5 NaN 位置敏感 — **闭合**

- 落点：§6.3 NaN 规则。
- 复核：默认 `nan_policy=positional`；报告旧/新 NaN 数量与新增/消失位置；**任何新增 NaN 位置一律判失败、与容差无关**；`ignore` 须附理由+Pro-science 批准，且对 `science_sensitive` 一律禁止。另补 `exact` 用 `isequal`、带符号零差异判失败。完全覆盖 t7 要求。
- 剩余性质：无；属 GATE-B 比较器实现（MIG-002）验证。

### F-6 科学验证 backlog — **闭合**（且比 t7 要求更完整）

- 落点：§9 + MIG-053（`docs/src/science_validation_backlog.md`）。
- 复核：§9 表已含 SB-C6/C7/C10/C11a/C11b/C12/C13 + SB-D08/D21/D13/STA/K/NOOP/CONST，每项有出处/方法、容差、负责人、触发条件、状态。额外覆盖了 t4 §6 的 KEV_PER_AMU、无操作参数、μ0/e 口径等——比 t7 要求更全。
- 剩余性质：C6-C13 是 **HD-11 使用者裁决**；真实数据/DLL 项（SB-D08/D21/D13）是**环境触发的实施验证**，标注开放/阻塞、不伪造。

### F-7 `sta_v_4d` println 副作用 — **闭合**（见 F-2 的 SE-STA-2）

- 落点：§6.3 SE-STA-2（`redirect_stdout` 捕获，`prints`）+ HD-08。
- 复核：明确"迁移须保持；改 `@warn` 须经人工批准"。正确。

### F-8 AST oracle 副本数统一 — **闭合**

- 落点：§4.1 精确计数表 + §6.2 自检 oracle"必须精确命中"。
- 复核：本次 grep 核实 §4.1 计数**准确**——`bowshock` 顶层 2（`MAVEN_plot.jl:1514`、`head.jl:358`）、`magnetopause` 顶层 2（`:1541`、`:397`）、`bowshock_zero` 1（`function_coordinate.jl:249`）、`get_bowshock_normal` 1（`head.jl:502`）、`mars_sun_dist_phys` 1（`head.jl:134`）、`escape_energy` 1（`calculate_models.jl:87`）。草案"至少 2/至少 4 份"两种模糊说法已作废，改用"3 文件 5 定义"的精确表述，且"复测不得放宽为「至少」"。
- 剩余性质：MIG-000 复测时以实测为准（如不同须附证据更新 oracle）。

---

## 2. RR-S 七点逐点确认

| RR-S 点 | 复核结论 |
|---|---|
| 1. cyclotron 选项 + 浮点序判断 | **正确**（§1 F-1 核实） |
| 2. B-STA 前置条件 + `STA_count2df` 是否写输入 | **正确**；源码确认 `STA_count2df` 就地写、`sta_v_4d` 副作用、`sta_v_4d_new` 无副作用。SE-STA-1 的"以实测为准"为保守且恰当的实施口径 |
| 3. NaN positional 策略与报告字段 | **正确**，字段齐全（旧/新数量、新增/消失位置） |
| 4. HD-10 (a)/(b) | **正确**，(a) 与 t7 推荐一致 |
| 5. §9 backlog 完整性 | **完整**（比 t7 要求更全），见 F-6 |
| 6. §4.1 计数作为 oracle | **足够且准确**（grep 核实），见 F-8 |
| 7. C/E 下 bowshock/magnetopause 等价门禁 | **正确**：§4.2"两份副本先逐点等价，不等价则不同名保留交 Pro-science"，B-DUP 覆盖互比用例 |

---

## 3. 仍需修订项

### R-1（低）`escape_energy` 的"planet≠Mars 时 v 未定义"注记在最终版丢失

- 草案 t5 §4.2 明确写过"`escape_energy`（planet≠"Mars" 时 v 未定义的旧行为原样保留并记录）"，t7 §1.7 已确认该处置正确。
- 最终版 §4.2 的"火星边界与环境函数"表列了 `escape_energy` 的去向，但**未保留**该显式注记；§9 backlog 也无对应 SB 条目（SB-NOOP 只覆盖 `m_int`/`energy_range`，不含 `escape_energy`）。
- 源码核实（本次）：`calculate_models.jl:90-94` 确实只在 `planet=="Mars"` 时给 `v` 赋值，否则 `E=0.5*mass*v^2/eV` 报 `UndefVarError`；docstring `:85` 自述"若 planet 非 "Mars"，v 未定义会报错"。
- **要求（精确位置）**：在 §4.2 环境函数表 `escape_energy` 行加注"（planet≠\"Mars\" 时 v 未定义的旧行为原样保留并记录）"；并可选在 §9 backlog 增一条 `SB-ESC`（owner=用户，触发=文档同步/触及该函数时，状态=记录）。此非数值改动、非 blocker，但人工审查包应保留这条"已知潜在 bug 不得顺手修"的护栏。

### R-2（可选，低）`TimeFormat` 两版格式字面量应在 MIG-005 显式采集

- §4.2 `TimeFormat(t1,t2; format=:hms_ms)` 与 `SPO.TimeFormat` 是**两种不同 `Dates.format` 输出**（`HH:MM:SS.mmm` vs `MM:SS.mmm`，t4/02 AR-B7）。最终版以"输出须逐字一致 + SPO 显式传原格式"作门禁，方向正确。
- 建议（非必改）：MIG-005 审计表把两版的确切 `DateFormat`/`Dates.format` 字面量**逐字采集**，避免实施者只凭记忆填 format 字符串导致静默漂移。属"验证更完备"而非"设计缺陷"。

---

## 4. 待人工裁决 / 实施验证 / 科学正确性边界（明确区分）

### 4.1 待人工裁决（HD-*）

HD-04（C 并入 MarsCommon / E 独立 MarsEnvironment）、HD-07（cyclotron 选项+命名）、HD-08（sta_v_4d 证据处置 + println 是否改 @warn）、HD-09（color_mapping 改名）、HD-10（:mass 常量方案）、HD-11（C6-C13 使用者裁决）。这些已正确门禁在 HA-0/HA-1/HA-F，**未用合成回归代替科学正确性**。

### 4.2 待实施验证（GATE-B 前）

B-CYC（cyclotron 三体系 + HD-07(a) exact）、B-STA（sta_v_4d 五用例）、B-DUP（bowshock/magnetopause 互比、slice2d 共线、static_c6 旧输入、color_mapping 三版本）、V-I1…5/V-F1…3/V-R（实例一致性与转发解析）、MIG-005 审计表、§4.1 oracle 复测。均标记为实施验证、缺证据禁止合并/替换。

### 4.3 科学正确性边界（不可越界）

最终版 §1-4 与 §9 SB-* 已把"合成回归 ≠ 科学正确"固化为交付边界：C6-C13 及真实数据/DLL 项全部开放/阻塞、由使用者裁决，**没有**任何"合成基线通过即算科学正确"的表述。复核确认此边界未被破坏。

---

## 5. 复核结论（供 HA-0 参考）

**pass（文档设计层面）**，条件：R-1 在 HA-0 前并入最终版（一行注记 + 可选 SB-ESC 条目）；R-2 为可选增强。除 R-1 外，最终版对 t7 的 F-1…F-8 全部闭合，RR-S 七点全部经源码核实确认，科学正确性边界保持。**本复核只证明"方案层面的科学语义与验证设计正确"，不证明任何合成数值等于科学真值**；科学正确性仍由 §9 backlog 与使用者裁决闭环。

---

## 6. 合规声明

- **唯一写入**：`.agent/science_final_recheck.md`（本文件）。未改最终方案/代码/测试/配置/`new_plan.md`/`Project.toml`/`Manifest.toml`，未触碰其他成员交付物、`.agent-teams/`。
- **未整仓重扫**：只定向 grep 复核了 §4.1 同名定义计数（bowshock/magnetopause/bowshock_zero/get_bowshock_normal/mars_sun_dist_phys/escape_energy）与 `calculate_models.jl:87-96,149-158`、`MAVEN_STATIC.jl:247-248,560-624` 的关键行；其余结论对照 t7 与最终版自身引用。
- 未创建子 Agent；未查询其他成员进度；未运行会写入仓库的验证命令。
