# science_draft_review.md — 目标架构草案的科学语义 / 验证保障独立审查

> 任务：t7 [science-review]「独立审查草案的科学语义和验证保障」
> 执行：pro-science（DeepSeek Pro / Official，科研计算专家）— attempt 1 / `92a312f0-eab8-4eed-a88c-271df5dd046a`
> 日期：2026-10-14
> 被审对象：`.agent/target_architecture_draft.md`（t5，chief-architect，草案 DRAFT，未授权实施）
> 审查范围：**只审科学语义、数据契约、API 科研使用习惯、行为一致性与数值验证保障**；不重复架构层的模块归属/依赖方向/扩展性判断（属 pro-architecture-official）。
> 方法：对照 t4 `.agent/science_expert_analysis.md` 与源码定向复核。本文件是本次 t7 的**唯一写入产物**；未改任何代码/测试/配置/`new_plan.md`，未创建子 Agent，未轮询成员。

---

## 0. 结论速览

**审查结论：草案的科学语义与验证保障基本正确、可作施工底稿，但需并入下述 8 项修正后方可进入 GATE-B 施工。** 无"必须推翻"的 blocker，但有 1 项"若按字面执行会出错"的高优先修正（F-1 cyclotron 转发语义）与 2 项"等价门会误判"的修正（F-2 sta_v_4d 前置条件、F-5 NaN 判等）。

| # | 发现 | 严重度 | 处置 |
|---|---|---|---|
| F-1 | `cyclotron_*` 三份实现**参数化不同**（kg 质量+显式速度 vs AMU 质量数+电荷数+能量），"转发"不是纯别名，且 `MAVEN_load.cyclone_frequency` 默认电子质量不随离子切换 | **高** | §2.1；MIG-005/MIG-020 审计结论须为"保留独立命名或显式换算包装"，禁止裸 alias |
| F-2 | `sta_v_4d` 经 `STA_count2df` **就地副作用**且自足；`sta_v_4d_new` **无副作用但要求 `dat[:df]` 预先存在**。等价门必须写前置条件，否则误判 | **中** | §2.2 |
| F-3 | `color_mapping` 迁入 MAVEN_plot 与内部嵌套同名（`MAVEN_plot.jl:297,537`）存在遮蔽/递归风险 | 中 | §2.3 |
| F-4 | MIG-042 的 `MASS_AMU=:mass` 与 `MASS_EV_PER_KM_S2=:mass` **同值**，会复现 `:mass` 语义歧义 | 低-中 | §2.4 |
| F-5 | Call Table NaN 判等须**位置敏感**并报告 NaN 位置/数量差，science_sensitive 不得靠"可配置 NaN 相等"掩盖 NaN 引入 | 中 | §2.5 |
| F-6 | 缺"科学验证 backlog"长期交付物（C6-C13 + real-data/SPEDAS 交叉验证的 who/when） | 低 | §2.6 |
| F-7 | `sta_v_4d` `println("Invalid Data")` 副作用与 `sta_v_4d_new` 不一致 | 低 | §2.2 |
| F-8 | AST 自检 oracle 写 bowshock"至少 2 份"，§4.3 自称"至少 4 份"，应统一为实际计数 | 低 | §2.7 |

---

## 1. 已正确捕获的科学语义（确认，无需返工）

以下条目草案已正确继承 t4，**审查确认通过**，仅列证据定位：

1. **科学红线清单完整**（草案 §1-2）：`:mass` 跨模块语义、角度约定（SWIA 度/STATIC 存度转弧度/MINPA 弧度/MarsCommon 度）、MGS `Dict{String,Any}`+位置列表 `"Vars"`、TW 双键 `:time/:epoch`、两套 PSD、默认 `:euler`、`get_mag_line_s` 双键回退、`static_slip` 视图共享、NaN/flag 不用 `missing`、`constants` 破坏性数值（μ0/e）——逐条对应 t4 §2，无遗漏。
2. **不合并清单完整**（§4.6）：`load_quat`（Dict vs Matrix）、`MINPA_sphere2xyz`（接口不同）、两套 PSD、`SPO.cyclotron_radius`（SI）、`sta_v_4d/_new`（只出证据不合并）——对应 t4 §2.4/§6 与 03 §15。
3. **容差政策正确**（§6.3）：`pure_move=exact`、转发重排默认 `rtol=1e-12`、放宽容差须 Pro-science 批准、不一致按 new_plan §10 五类归因——与 t4 §2.6 一致。
4. **门禁先于迁移、缺证据禁止合并**（§6.3/§6.4、§0-8）——正确承接 t4 §4 的证据分级（003/004/018/022/025 无测试）。
5. **行为基线表准确**（§6.3）：TASK-025/004/018/022/003 + `sta_v_4d` 等价门 `rel≤1e-9` + `needs_dll/needs_real_data` 标记 skipped 不伪造 DLL——准确补齐 t4 §5 的缺口。
6. **"合成回归 ≠ 科学正确"边界**（§1-4、§12 HA-F）——正确引用 t4 §7。
7. **`escape_energy` 旧行为（planet≠"Mars" 时 v 未定义）原样保留并记录**（§4.2）——正确，防"顺手修复"引入行为漂移。
8. **数据契约是 API 一部分、`:mass` 禁止单一 `MASS`、科学红线作为历史契约保留**（§5.5、§1-2）——方向正确（细化见 F-4）。
9. **API 科研习惯**：三层 API 面 + 全限定名默认 + 转发不发 depwarn（防脚本刷屏）+ 历史模块名不改（§5.1/§5.2/§1-7）——与科研脚本兼容诉求一致。

---

## 2. 须并入的修正（按严重度）

### F-1（高）cyclotron 三实现参数化不同，不能按"转发"处理

草案 §3.1/§4.1 把 `MAVEN_load.cyclone_*` 归为"单位审计后转发"到 `calculate_models.cyclotron_*`。**定向复核发现二者不是同一函数的别名，而是不同参数化**：

| 实现 | 签名 | 质量/电荷约定 | 输入 | 输出 |
|---|---|---|---|---|
| `MAVEN_load.cyclone_frequency` | `(B; mass=constants.me)` | **kg 质量**，默认电子，**不随离子切换** | B(nT) | Hz |
| `MAVEN_load.cyclone_R` | `(v, B; mass=constants.me)` | kg 质量，默认电子 | **v(m/s)**, B(nT) | m |
| `calculate_models.cyclotron_frequency` | `(B; nM=1, nQ=-1)` | **AMU 质量数 + 电荷数**，离子/电子分支 | B(nT) | Hz |
| `calculate_models.cyclotron_radius` | `(B, ek; nM=1, nQ=-1)` | AMU + 电荷数 | **ek(eV)**（内部算 v） | (f, rc, v)=(Hz,m,m/s) |

证据：`MAVEN_load.jl:1277-1302`、`calculate/calculate_models.jl:116-158`。

**问题**：
1. `cyclone_R` 输入**速度**，`cyclotron_radius` 输入**能量**——转发需显式 E↔v 换算，不是裸 alias。
2. `cyclone_frequency` 默认电子质量且对 `nQ>0` **不切质子/离子质量**（`calculate_models.cyclotron_frequency` 会切），直接替换会改变离子情形下的数值。
3. 草案 §4.6 已正确把 `SPO.cyclotron_radius`（SI）排除，但对 `MAVEN_load.cyclone_*` 的**kg-vs-AMU、速度-vs-能量**差异只笼统写"单位审计后"，未点明结论。

**要求**：MIG-005 审计表必须显式记录这三点的结论，MIG-020 的处理应为下列之一（在 HA-1 前定稿）：
- （推荐）**保留独立命名**：`cyclotron_radius_energy`（AMU+ek）与 `cyclotron_radius_velocity`（kg+v），`cyclone_*` 转对应前者或后者并显式换算；
- 或 **保留 `cyclone_*` 为私有 helper 不转发**（与 SPO 处理一致）；
- **禁止**无换算的裸 `const cyclone_R = MarsCommon.cyclotron_radius`。

### F-2（中）sta_v_4d 等价门必须写前置条件与副作用差异

复核 `MAVEN_STATIC.jl:547-596`（`sta_v_4d`）与 `:617-659`（`sta_v_4d_new`）：

- `sta_v_4d`（`unit_cover=true` 默认）内部调用 `STA_count2df(dat)`，**就地写回 `dat[:df]`/`dat[:df_mass_mass]`**（副作用），因此**自足**（无 `:df` 也能跑）。
- `sta_v_4d_new` **不调用** `STA_count2df`，直接 `data0 = dat[:df]`，**要求 `:df` 已存在**（无副作用）。
- 另：`sta_v_4d` 有 `println("Invalid Data")` 副作用（`:549`），`sta_v_4d_new` 无（`:619`）。

**要求**：等价门（§6.3 的 `rel≤1e-9` 用例）必须显式声明前置条件"`dat` 已含 `:df`（即先经 `STA_count2df`）"，并单独记录两条副作用差异（F-7）。否则对"未预计算 `:df` 的输入"，`sta_v_4d_new` 会 `KeyError`，门会误判为"不等价"。结论仍应只出证据不合并（H-12 正确），但证据要能区分"数值差异"与"前置条件/副作用差异"。

### F-3（中）color_mapping 迁入 MAVEN_plot 存在同名遮蔽/递归风险

§4.5 要把 `head.jl:169` 的 `color_mapping` 迁入 `MAVEN_plot`，但草案自己标注 `MAVEN_plot.jl:297,537` 已存在**嵌套同名 `color_mapping`**。**要求**：MIG-015 必须显式消歧（顶层迁入名重命名，或确认嵌套定义只在其局部作用域内、不会遮蔽/递归调用新迁入的顶层名），并加一条"调用图无新增同名歧义"的 AST/用例断言。此为 API 科研习惯风险：`color_mapping` 在 head.jl 生态被裸名使用（`TW_MINPA.jl:598-612` 注释区有独立副本逻辑），迁移后裸名绑定到错误版本会静默改变色标映射。

### F-4（低-中）`:mass` 常量方案细化（H-10）

草案 §5.5/MIG-042 提议 `MASS_AMU=:mass` 与 `MASS_EV_PER_KM_S2=:mass`。二者**值相同（都是 `:mass`）**，既不能防拼写错（键名本就一样），又复现了"哪个语义"的歧义。**要求**（三选一，并入 H-10）：
- （推荐）只登记单一 `MASS=:mass`（防拼写漂移），在**附录 A 按生产者模块注释语义**（SWIA=`mp_eV_per_km_s2` 常量；STATIC/MINPA=AMU 质量数）；
- 或 用**带生产者前缀**的常量名（`SWIA_MASS_EV_PER_KM_S2` / `STATIC_MASS_AMU`），其值仍 `:mass`，靠名字承载语义；
- **避免**两个无前缀、同值、仅靠 docstring 区分语义的常量。

### F-5（中）NaN 判等须位置敏感 + 报告 NaN 位置/数量差

§6.3 比较器写"NaN 与 NaN 视为相等（可配置）"。方向正确，但对 `science_sensitive` 用例，**必须在 exact/rtol 模式外额外报告 NaN 的位置集合差与数量差**（`old_nan_pos != new_nan_pos` 即行为变化）。否则一次迁移"恰好"引入 NaN（如错误的掩膜/除零）而两侧 NaN 计数相同，会被"NaN 相等"吞掉。建议在 Call Table schema 增加 `nan_policy ∈ {positional, ignore}`，`science_sensitive` 默认 `positional`。

### F-6（低）缺"科学验证 backlog"长期交付物

H-11 只写"C6/C7/C10/C11/C12/C13 使用者裁决；本轮只原样搬运"。**要求**：在 HA-F 前，把 C 类六项 + real-data/SPEDAS 交叉验证固化为一条**长期待办文档条目**（含每项的出处/方法/容差，直接引用 t4 §3 表），不随架构工作结束而消失；否则这些疑点会在"原样搬运"中被静默淹没。

### F-7（低）sta_v_4d 的 println 副作用

见 F-2。建议一并记录到行为基线（`mutates`/`prints` 类用例），迁移后保持或经人工批准改 `@warn`。

### F-8（低）AST 自检 oracle 副本数统一

§6.2 自检 oracle 写"bowshock 至少 2 份副本"，§4.3 标题写"至少 4 份副本"。**要求**：oracle 用实际计数（`MAVEN_plot.jl:1514`、`head.jl:358`、`head.jl:397`(magnetopause)、`function_coordinate.jl:249`(bowshock_zero) 及相关）核对后统一，避免门禁自检的 oracle 弱于真实副本数。

---

## 3. 数值验证保障的补充要求（汇总，供 GATE-B 落地）

1. Call Table 比较器单测（MIG-002）必须覆盖：`NaN` 位置敏感策略、`Inf` 符号、`missing` 即报错、`Dict` 键集合相等、`NamedTuple`/`struct` 逐字段、`DataFrame` 列名+列值、以及**视图/别名（`mutates`）**用例（§6.3 已列，确认）。
2. `pure_move=exact` 是最强保证，**exact 失败本身就是红警**，不允许"放宽"到 rtol 蒙混；放宽必须 `tolerance_justification` + Pro-science 批准（§6.3 已写，确认）。
3. 行为基线必须从**当前工作区状态**采集（§6.1 已写，确认），并与 R-1 快照提交联动，防基线丢失（RA-1 已列）。
4. 每个 `science_sensitive` MIG（013/020/023/030）除数值用例外，还须有一条**"调用图无新增悬空调用/无同名遮蔽"**的 AST 断言（补 F-3 的通用化）。

---

## 4. 必须用户裁决项汇总（科学相关增量）

| # | 事项 | 关联草案项 | 建议 |
|---|---|---|---|
| U-1 | cyclotron 三实现处置：保留独立命名 / 换算包装 / 不合并 | F-1；MIG-005/020 | 倾向"保留独立命名 + `cyclone_*` 转发到速度版"，HA-1 前定稿 |
| U-2 | `sta_v_4d/_new` 等价门前置条件与副作用差异的最终确认 | F-2/F-7；H-12 | 等价证据须注明"前提=已含 :df"，副作用差异单列 |
| U-3 | `:mass` 常量命名方案（单常量+注释 vs 生产者前缀） | F-4；H-10 | 倾向"单 `MASS` + 附录 A 按生产者注释" |
| U-4 | `color_mapping` 迁入 MAVEN_plot 的重命名/作用域决策 | F-3 | 并入 H-3 或单列，MIG-015 前定 |
| U-5 | C6-C13 + real-data/SPEDAS 交叉验证的长期 backlog 固化 | F-6；H-11 | 在 HA-F 前落为文档条目 |

> 注：草案 H-1…H-14 中与科学直接相关的 H-10/H-11/H-12 立场正确，无需推翻；上述 U-* 是对其的**细化/补充**，不是新增推翻项。

---

## 5. 合规声明

- **唯一写入**：`.agent/science_draft_review.md`（本文件）。未改任何项目代码/测试/配置/`new_plan.md`/`Project.toml`/`Manifest.toml`，未触碰 `.agent/00–06`、其他成员交付物、`.agent-teams/`。
- **未整仓重扫**：只定向复核了 `calculate/calculate_models.jl:105-184`、`MAVEN_data/MAVEN_STATIC.jl:210-339,540-660`、`MAVEN_data/MAVEN_load.jl:1265-1309`，其余结论对照 t4 与草案自身引用。
- 未创建子 Agent；未查询其他成员进度；未运行会写入仓库的验证命令。
