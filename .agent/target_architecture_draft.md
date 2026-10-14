# target_architecture_draft.md — 目标架构 / 迁移 DAG / 功能添加规范（草案，待人工审查）

> 任务：t5 [draft]「设计目标架构、迁移DAG和功能添加规范」
> 执行：chief-architect（总架构师）— attempt 1 / `d3817b96-ed47-423b-b670-a1d71a5464c8`
> 模型身份：本成员在团队配置 `.agent-teams/julia-architecture-refactor/team.json` 中绑定为 `anthropic/claude-opus-5.5`。本草案由该配置下的会话写出，**没有静默换用其他模型**。本成员无法在会话内另行核验 provider 路由；如需更强保证，由队长在 DSH 路由层确认。
> 日期：2026-10-14
> 状态：**草案（DRAFT）**。**不授权任何代码实施**。必须先经人工架构审批（§12 HA-0），并经两名 Pro 独立审查后，才可由队长分派。
> 输入（只读，均已全文或定向阅读）：`.agent/new_plan.md`、`.agent/current_state_recovery.md`（t1）、`.agent/architecture_expert_analysis.md`（t3）、`.agent/science_expert_analysis.md`（t4）、`.agent/03_ARCHITECTURE_PLAN.md`（§3/§5/§7/§8/§9/§10）、`src/modules.jl`、`src/MarsData.jl`、`common/head.jl`、`calculate/calculate_models.jl`、`common/function_coordinate.jl`、`models/*.jl` 头部，以及各文件的函数定义清单（grep）。未见中科大报告，本草案也没有等待它。
> 写入范围：**只有本文件**。没有改代码、测试、配置、`Project.toml`/`Manifest.toml`、`new_plan.md`，没有创建子 Agent，也没有轮询成员。

---

## 0. 结论速览

| # | 架构决定（草案） | 理由 |
|---|---|---|
| 1 | 采用**七个能力层**：Core / Foundation / Data / Instrument / Domain Model / Visualization / Analysis，另设旁路 **Extras（杂项模型沙箱）**。依赖严格单向，并由 AST 工具机器校验 | 回应 new_plan §3.4、§18；把 Function→Capability→Module 显式化 |
| 2 | **保留现有包机制**：MarsData 轻量 L0 + 载体装载器 + 注册表 + allow 白名单。装载机制是红线，不改 | t1 §4-2、t3 §4.2：除 D-1 外仍成立 |
| 3 | **D-1（依赖 16→45）保持开放**，按 A 收敛 / B 接纳 / C 净化三支给出架构后果（§2.4）。本草案对 A、C 两支直接有效；若选 B，只需调整规则 FA-7。**不回滚、不提交、不视为批准** | 队长指令与 t3 §4.1 |
| 4 | `calculate/calculate_models.jl` **解体**：坐标/旋转函数进 FunctionCoordinate，基础等离子体公式与线性拟合进 MarsCommon，逃逸能量进 MarsEnvironment；原模块只保留**转发门面**，弃用一个周期 | 人工批注：calculate_models 与其他组分重合 |
| 5 | `common/head.jl` **按能力拆散**，不再整体包成 MarsUtils：统计/几何进 MarsCommon，火星边界模型进 MarsEnvironment，绘图标签与色标进 MAVEN_plot。head.jl 退化为**兼容 shim 脚本**。这一点**偏离** 03 ARCH-002 的 MarsUtils 方案，需人工确认（H-3） | 人工批注：head.jl 可移除/合并；整体包成 MarsUtils 会造出新的 God module |
| 6 | **新建 `MarsEnvironment`**（`models/Mars_Environment.jl`），作为弓激波/磁层顶/日火距离/逃逸能量等火星经验环境模型的**唯一权威落点**。目前同一 bowshock 至少有 4 份副本 | AR-6；需人工确认是否独立成模块（H-4） |
| 7 | **models 分两级**：注册模型（Domain Model，有稳定 API 和回归用例）与 **Extras 沙箱**（Octree、Graham 等杂项，用 `CATALOG.toml` 登记，有晋升规则）。Magnetic_Model 在**逻辑上**归 Domain Model 层，**物理位置默认不动**（H-6） | 人工批注：杂项模型单独规范；磁场模型可酌情放入 models |
| 8 | **Phase B 验证门禁先于一切迁移**：AST 抽取与层规则校验（MIG-001）、Call Table 加比较器（MIG-002）、行为基线用例（MIG-003，含 TASK-025/004/018/022/003 与 sta_v_4d 等价证据）。**缺证据的函数禁止合并或替换** | new_plan §8/§9；t4 §4 证据分级 |
| 9 | 迁移分解为 **MIG-001…MIG-052**，按「先建权威（只增）→ 再替换为转发（逐文件串行）→ 脚本层 → API 面/清理」四波推进；每个 MIG 声明互斥写范围 | new_plan §7 Phase D、§13 |
| 10 | 施工建议：含队长 **8 Agent**，在现有 6 人基础上增加 `pro-code-official-1` 和 `flash-code-official-1` 两个名额；实现与审查分离 | new_plan §15-8 |

---

## 1. 设计约束（继承，不重新论证）

1. **装载机制红线**：`src/modules.jl` 中的 `_carrier`/`load_module`/`@load`/`:preloaded`/`ModuleLoadError` 语义不改，只允许增补注册表条目、allow 和 validate 校验（03 §9-2）。
2. **科学红线**（t4 §2）：这些是**历史契约**，不是本轮可以自动统一的 bug：
   - `:mass` 键跨模块含义不同：SWIA 存 `mp_eV_per_km_s2`，STATIC/MINPA 存 AMU；
   - 角度约定：SWIA 用度，STATIC 存度、计算时转弧度，MINPA 用弧度，MarsCommon 用度；
   - MGS 返回 `Dict{String,Any}`，`"Vars"` 是位置列表；TW 同时产出 `:time` 与 `:epoch`；
   - 两套 PSD 并存，不得合并；默认磁力线 `:euler`；`get_mag_line_s` 双键回退；`static_slip` 视图共享内存；
   - 全仓统一用 NaN 或 flag 表达缺失，不用 `missing`；
   - `constants` 中的破坏性数值（μ0、e）沿用现值。
3. **C6/C7/C10/C11/C12/C13 不改值**，列为人工待决（§12 H-11）。迁移只能**原样搬运**含这些常数的代码。
4. **合成回归 ≠ 科学正确**（t4 §7）：Call Table 只能证明迁移前后行为一致。
5. **既有未提交代码保持原样**：工作区里 P6 与 TASK-024/025 的 19 个文件，在 R-1 裁定前不提交、不回滚、不重写。
6. **本轮不做函数级性能优化**：TASK-044…048 一律过滤；TASK-026 仅作旧计划续点（H-9）。
7. **不重命名既有模块**（MAVEN_load 等历史名保持）。新模块只限 §3.2 列出的两个。
8. **Python 侧零改动**；`MAVEN_data_format.json`、`KP_vars.json`、`gh_gao`、`IGRF_DLL.dll` 等数据与配置只读。

---

## 2. 目标层次与依赖方向

### 2.1 能力层定义

```text
                 ┌─────────────────────────────────────────────┐
  L6 Analysis    │ Pickup_ion（pickup_ion_analysis）、Build_data、example │  入口编排，可依赖下方全部层
                 └─────────────────────────────────────────────┘
  L5 Visualization  MAVEN_plot（预装）、src/plotting.jl              依赖 L1、L4（仅纯函数模型）及 DataKeys
  L4 Domain Model   IGRF_calculate、Cold_Plasma_Dispersion_Relation、Maxwellian_Distribution、
                    Single_Particle_Orbit、MarsEnvironment（新）      只依赖 L1（及 L1n Native）
  L3 Instrument     MAVEN_STATIC、MAVEN_SWIA、MAVEN_SWEA、TW_MINPA      只依赖 L1；通过 DataKeys 契约消费 L2 的 Dict
  L2 Data Access    MAVEN_load、TW_load、MGS_load、SP_load            只依赖 L1；只做读取与解析
  L1 Foundation     constants、MarsCommon、FunctionCoordinate（新）    不依赖任何 L2+
       L1n Native   Call_fortran_dll（ccall 绑定，路径经 Paths）
  L0 Core           MarsData：Paths、DataKeys、注册表/装载器、load_registry/index（包层，轻量）
  ─────────────────────────────────────────────────────────────
  X  Extras（旁路）  Octree、Graham……（CATALOG.toml 登记）           只可依赖 L1；任何层不得依赖 X
```

### 2.2 允许的依赖边（AST 规则表 `validation/architecture/layers.toml` 的内容来源）

| 从 \ 到 | L0 | L1 | L1n | L2 | L3 | L4 | L5 | X |
|---|---|---|---|---|---|---|---|---|
| L1 Foundation | Paths/DataKeys | 同层（见注 1） | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| L2 Data | ✓ | ✓ | ✗ | ✗（见注 2） | ✗ | ✗ | ✗ | ✗ |
| L3 Instrument | ✓ | ✓ | ✗ | ✗（只消费 Dict） | ✗ | ✗ | ✗ | ✗ |
| L4 Model | ✓ | ✓ | ✓ | ✗ | ✗ | 同层（见注 3） | ✗ | ✗ |
| L5 Visualization | ✓ | ✓ | ✗ | ✗ | ✗ | ✓（纯函数模型） | 同层 | ✗ |
| L6 Analysis | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓（显式 include） |
| X Extras | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | 同层 |

- 注 1：FunctionCoordinate 可以依赖 MarsCommon，反向禁止。
- 注 2：读取器之间不得互相 include。
- 注 3：L4 内部只允许一跳，且须登记在注册表 `deps`。
- **兼容边（compat edge）**：第二波转发期间，旧位置会通过转发 shim 引用新权威，例如 MAVEN_load 里的旧名转发到 MAVEN_SWEA，形成 L2→L3。这类边**只许**出现在显式标注 `# COMPAT-FORWARD (MIG-xxx)` 的转发函数中，并登记在 `layers.toml [compat_edges]`，带移除期限；其他位置出现即判失败。
- 禁止一切循环（AST 校验 SCC 为空）。

### 2.3 L0 / 载体 / 白名单的关系（沿用并明确）

- L0 只预装 Paths、DataKeys、MAVEN_plot、plotting。MAVEN_plot 依赖的 MarsEnvironment 是**纯函数、无重依赖**模块，可以随 MAVEN_plot 自包含 include 进入预装闭包，不破坏 L0 轻量性。
- L1–L4 的模块经注册表与载体装载（`MarsData.@load X`），沿用既有自包含 include 模式（ARCH-003）。
- Extras 不进 `MODULE_REGISTRY`。原因：新增 `kind` 值等于修改装载机制，触碰红线。Extras 只在 CATALOG 中登记。

### 2.4 D-1 三分支的架构后果（**保持开放**，人工裁决 H-1）

| 分支 | 动作（由人工执行或授权） | 对本目标架构的影响 | 须改的规范 |
|---|---|---|---|
| **A 收敛**（t3 推荐） | `[deps]` 回到 HEAD 的 16 项 | 全部有效：L0 轻量，重依赖经载体 LOAD_PATH 回退 | 无 |
| **B 接纳 45 项** | 维持现状并修订红线 | 层次与 MIG 不变；载体机制的回退理由消失，退化为遗留 shim；`using MarsData` 冷启动变重；AR-24 改判为已接受代价 | FA-7 改为「库运行期依赖可进 `[deps]`，但开发工具（IJulia/Revise/BenchmarkTools）仍禁止」；03 §9-3、§9-9 须改写 |
| **C 净化** | 只保留 L0 实际 import 的依赖，剔除工具与 GUI 依赖 | 与 A 等价，但需要逐项审计 45 个包；可由 MIG-001 的 AST using 清单自动生成审计输入 | FA-7 原样适用 |

**任何 MIG 都不修改 `Project.toml`/`Manifest.toml`**。若出现依赖缺失，记录为阻塞并上报，不自行 `Pkg.add`。验证环境 `validation/` 与 `benchmark/` 一样使用独立环境，或只用标准库（见 §6.1）。

---

## 3. 模块目录：职责、落点、能力归属

### 3.1 现有模块的目标职责

| 模块（文件） | 层 | 目标职责 | 迁入 | 迁出 |
|---|---|---|---|---|
| `MarsData`（`src/MarsData.jl`、`src/modules.jl`） | L0 | 路径/注册表/装载/契约 | 注册条目 FunctionCoordinate、MarsEnvironment | — |
| `constants`（`common/constants.jl`） | L1 | 物理常量 | — | —（`KeV_PER_AMU` 命名误导只记录，不改，t4 §6-1） |
| `MarsCommon`（`common/MarsCommon.jl`） | L1 | 轻依赖的坐标/能量/PSD/数学/统计/时间格式/基础等离子体公式 | 见 §4.1 | — |
| `FunctionCoordinate`（`common/function_coordinate.jl`，**包化**） | L1 | 基于旋转对象（Rotations/SVector）的参考系变换、四元数、切片坐标系 | `rotation_matrix`/`Quaternion_Rot`/`Quaternion_Rot_reverse`（来自 calculate_models） | `bowshock_zero` 转发到 MarsEnvironment；`MINPA_sphere2xyz`/`MINPA_xyz2sphere` 保留不合并（与 TW_MINPA 版接口不同，t4/TW_MINPA.jl:234） |
| `DataKeys`、`Paths` | L0 | 契约常量与路径 | 增补键需人工批准（H-10） | — |
| `Call_fortran_dll`（`call_fortran_dll.jl`） | L1n | ccall 绑定 | — | — |
| `MAVEN_load` | L2 | **只做**读取与调度 | — | `Bpc2sphere`→MarsCommon；`static_c6_mass_mean/energy_mean`→MAVEN_STATIC；`cyclone_frequency/cyclone_R`→MarsCommon（单位审计后）；`SWEA_calc_shape_arr*`/`mean_SWEA_pad_pa`/`carclu_SWEA_pad`→MAVEN_SWEA。旧名一律保留转发 |
| `TW_load`、`MGS_load`、`SP_load` | L2 | 读取 | — | 孤儿 docstring 清理（MIG-051） |
| `MAVEN_STATIC`/`SWIA`/`SWEA`、`TW_MINPA` | L3 | 矩/换算 | SWEA 接收 shape 与 PAD 处理 | TW_MINPA 的私有 `slice2d_cal_rot` 改用 FunctionCoordinate（须等价验证） |
| `IGRF_calculate`（`Magnetic_Model/`） | L4 | 磁场模型与磁力线追踪 | — | `Bpc2sphere/Bsphere2pc` 改为转发到 MarsCommon（`pc2sphere/sphere2pc` 留在原处，仍在 allow 中） |
| `Cold_Plasma_Dispersion_Relation`、`Maxwellian_Distribution` | L4 | 注册模型 | 拼写别名（TASK-041） | — |
| `Single_Particle_Orbit` | L4 | 单粒子轨道 | — | `TimeFormat` 转发到 MarsCommon 版并显式传原格式；`cyclotron_radius` 用 SI 输入，与 nT/eV 版**不同义**，保留为私有 helper，不转发 |
| `MarsEnvironment`（**新**，`models/Mars_Environment.jl`） | L4 | 火星经验环境模型 | 见 §4.3 | — |
| `calculate_models`（`calculate/`） | **弃用门面** | 只保留转发 | — | 全部函数迁出（§4.2） |
| `MAVEN_plot`（预装） | L5 | 绘图基元、色标、刻度、标签 | `color_mapping`/`get_log_ticks`/`label_data`/`print_f`（来自 head.jl，等价审计后） | `Vandermonde/polynomial_fit/vector_angle`→MarsCommon；`bowshock/magnetopause`→MarsEnvironment；死名 `WaveSpactra_heatmap` 从 export 删除 |
| `src/plotting.jl` | L5 | 概览合成 | — | `TimeFormat` 改为转发 MarsCommon.TimeFormat |
| `common/head.jl` | **兼容 shim 脚本** | `using MarsData` 加 `@load`，再把旧裸名绑到新权威；不再自带实现 | — | 全部实现迁出；A4 大小写 bug 随旧装载块消失 |
| `models/Pickup_ion.jl` | L6 | `pickup_ion_analysis(time_event; …)` 显式入口，外加全局 shim | — | 去掉 `D:/` 硬编码路径（Pickup_ion.jl:273） |
| `models/Octree.jl`、`models/Graham.jl` | X | Extras | — | 登记 CATALOG；物理位置默认不动（H-7） |

### 3.2 新模块（仅此两个）

| 新模块 | 理由（对照 FA-3） | 依赖 |
|---|---|---|
| `FunctionCoordinate` | 03 已定稿；引入 Rotations/StaticArrays 依赖，有理由与 MarsCommon 分开 | constants、MarsCommon、Rotations、StaticArrays、LinearAlgebra |
| `MarsEnvironment` | 新物理能力域（火星经验边界与环境），目前散在 4 处副本；放进 MarsCommon 会让基础层带上火星专用经验模型。**备选方案（H-4）**：并入 MarsCommon 的 `environment` 分节，API 不变，MIG-012 落点改为 `common/MarsCommon.jl` | constants（只依赖 L1） |

### 3.3 物理文件布局

```text
src/                     L0
common/                  L1：constants、MarsCommon（可拆为子文件，见 FA-4）、function_coordinate、paths、data_keys；head.jl = 兼容 shim
call_fortran_dll.jl      L1n（不动）
MAVEN_data/ TW_data/ MGS_data/ support_data/   L2 + L3（不动）
Magnetic_Model/          L4 IGRF + 只读资产 gh_gao/IGRF_DLL.dll（默认不动，H-6）
models/                  L4 注册模型 + 新增 Mars_Environment.jl；Pickup_ion.jl 暂留（逻辑归 L6，H-8）
models/CATALOG.toml      Extras 登记（新增；Octree/Graham 默认原地登记，H-7）
calculate/               弃用门面（下一轮移除）
validation/              新增：ast/、calltable/、fixtures/、architecture/layers.toml、results/（Phase B）
```

**MOVE 政策**：03 §3.4-2 禁止移动文件，new_plan 允许 MOVE。本草案的折中是：**默认不移动物理文件**，以逻辑层归属与注册表 `note` 表达；三项可选物理迁移（H-6 Magnetic_Model、H-7 Extras、H-8 Pickup_ion）各自单列为可选 MIG，须人工逐项批准。原因：注册表路径、README、docs/api.md 链接、example 相对 include 都会受影响，而收益只是目录观感。

---

## 4. 重复/错位功能的权威归属表（MERGE / MOVE 依据）

> 每一行在替换为转发前，都须满足 §6.3 门禁：Call Table 等价用例通过；如涉及单位，还须有 MIG-005 审计表签字。**缺证据则保持双实现，禁止合并。**

### 4.1 进入 MarsCommon（L1）

| 函数 | 现位置（证据） | 备注 |
|---|---|---|
| `Bpc2sphere`/`Bsphere2pc` | `IGRF_calculate.jl:96,121`；`MAVEN_load.jl:962` | 03 ARCH-006 定稿 |
| `Vandermonde`/`polynomial_fit`/`vector_angle` | `MAVEN_plot.jl:1442,1462,1485` | 纯数学 |
| `Linear_fit` | `calculate_models.jl:178` | 纯数学 |
| `safe_log_mean`/`skipnan`/`nozeros`/`geomean`/`find_range` | `head.jl:104,204,227,251,275` | 统计；NaN 语义原样保留 |
| `get_normal_plane`/`get_angle`/`solve_func` | `head.jl:299,327,458` | 几何/求根（容差 1e-6 原样） |
| `cyclotron_radius`/`cyclotron_frequency`（nT/eV 输入） | `calculate_models.jl:116,149`；`MAVEN_load.jl:1277,1298`（`cyclone_*`） | **单位审计后**才可以让 `cyclone_*` 转发；`Single_Particle_Orbit.cyclotron_radius`（SI）不并入 |
| `TimeFormat(t1,t2; format=:hms_ms)` | `src/plotting.jl:26`；`Single_Particle_Orbit.jl:30`（另一种格式） | 默认格式等于 plotting 现格式；SPO 转发时显式传它原来的格式；输出须逐字一致 |

**不迁入**的函数：`logticks`/`interpolate_x_ticks`/`time_ticks`/`time2x` 属于绘图刻度，留在 L5 MAVEN_plot。这一点修正了 03 中「logticks 进 MarsCommon」的安排。

### 4.2 calculate_models 解体去向

| 函数 | 去向 |
|---|---|
| `rotation_matrix`、`Quaternion_Rot`、`Quaternion_Rot_reverse` | FunctionCoordinate |
| `cyclotron_radius`、`cyclotron_frequency`、`Linear_fit` | MarsCommon |
| `escape_energy` | MarsEnvironment（行星参数；`planet≠"Mars"` 时 v 未定义的旧行为原样保留并记录） |
| 模块本身 | 改为门面：`const cyclotron_radius = MarsCommon.cyclotron_radius` 等形式的转发，注册表 `note` 标注 DEPRECATED，下一轮移除（H-5） |

### 4.3 进入 MarsEnvironment（L4，新）

| 函数 | 现副本 | 契约 |
|---|---|---|
| `bowshock`、`magnetopause` | `MAVEN_plot.jl:1514,1541`；`head.jl:358,397` | Edberg 2008，R_M 归一化输入；**各副本须先做逐点等价**，若不等价则以不同名保留，并上报 Pro-science |
| `bowshock_km` | 新增显式命名（03 ARCH-006） | km 输入 |
| `bowshock_zero` | `function_coordinate.jl:249` | 原样搬运 |
| `get_bowshock_normal` | `head.jl:502` | 依赖 bowshock/solve_func |
| `mars_sun_dist_phys` | `head.jl:134` | — |
| `escape_energy` | `calculate_models.jl:87` | — |

### 4.4 进入 MAVEN_SWEA / MAVEN_STATIC（L3）

| 函数 | 现位置 | 去向 |
|---|---|---|
| `SWEA_calc_shape_arr`、`SWEA_calc_shape_arr_mars_towrads` | `MAVEN_load.jl:1333,1474` | MAVEN_SWEA（C10 常数原样搬运） |
| `mean_SWEA_pad_pa`、`carclu_SWEA_pad` | `MAVEN_load.jl:993,1172` | MAVEN_SWEA（C12 NaN 互填原样搬运） |
| `static_c6_mass_mean`/`energy_mean` | `MAVEN_load.jl:1037,1105` | MAVEN_STATIC 新版为权威（03 B2：新版是旧输入的超集）。**须有等价用例**，覆盖旧输入在新版上的结果 |

### 4.5 进入 MAVEN_plot（L5）

`color_mapping`（`head.jl:169`；MAVEN_plot 内另有嵌套同名函数，`MAVEN_plot.jl:297,537`）、`get_log_ticks`（`head.jl:429`，与 `logticks` 须先比对，**不等价则不合并**）、`label_data`、`print_f`、`norm2`（`head.jl:38-81`）。MAVEN_plot 内部嵌套的 `slice2d_cal_rot`/`remove_repeat_points` 等私有函数本轮**不动**。

### 4.6 明确不合并（同名不同义或接口不同）

`load_quat`（读取层返回 Dict，SWEA 返回 Matrix）；`MINPA_sphere2xyz`（FunctionCoordinate 版与 TW_MINPA 版接口不同）；两套 PSD；`Single_Particle_Orbit.cyclotron_radius`（SI 输入）；`sta_v_4d` 与 `sta_v_4d_new`（只出等价证据，**不合并**；收编属 TASK-044，本轮过滤）。

---

## 5. Public API 与 namespace

1. **三层 API 面**（采纳 t3 §5）：
   - 全限定名 `MarsData.X.f` 是默认的稳定形式；
   - allow 白名单裸名只放 `docs/src/api.md` 认定的入口；
   - 模块内的 `export` 不作为裸名引入依据。
2. **迁移不破坏旧调用**：每个被迁出的函数在原模块保留同名转发，写成 `f(args...; kw...) = NewHome.f(args...; kw...)`，或用 `const f = NewHome.f`；docstring 首行标 `DEPRECATED → NewHome.f (MIG-xxx)`。**默认不发 depwarn**，以免科研脚本输出被刷屏；是否开启由 H-13 决定。
3. **新模块命名**：CamelCase，名词表示能力域（FunctionCoordinate、MarsEnvironment）。历史模块名不改。
4. **allow 规则**：新权威的入口进入新模块的 allow。旧模块 allow 中已有的名字（如 IGRF 的 `pc2sphere`）保持不变。转发名**不新增**进 allow。
5. **数据契约是 API 的一部分**：新增或改动 Dict 键必须先登记 DataKeys 与附录 A。`:mass` 只允许以**带语义的多个常量**（如 `MASS_AMU`、`MASS_EV_PER_KM_S2`）登记，**禁止**单一 `MASS`（H-10）。
6. **`MarsData` 顶层 namespace 不扩张**：新功能一律挂在子模块下，不新增顶层函数。例外是 L0 基础设施，例如未来的 `extra_path`，须人工批准。

---

## 6. 验证策略：AST 与 Call Table 先行（Phase B 门禁）

### 6.1 位置与环境

- 目录 `validation/`。仿照 `benchmark/` 使用独立环境，或只用标准库：AST 解析用 `Base.Meta.parseall`（Julia 1.10 自带），TOML 用标准库 `TOML`。**不向主 `Project.toml` 加依赖**。
- **基线冻结**：旧结果必须在任何迁移之前，从**当前工作区状态**（HEAD 94da314 加 19 个未提交文件）采集。若 R-1 批准快照提交，就以该提交为基线 ref；否则以只读副本（worktree 或拷贝）为基线，并记录其文件哈希清单。

### 6.2 AST 工具（MIG-001）最小功能

| 功能 | 输出 |
|---|---|
| 抽取 module、function 定义（含短形式 `f(x)=`、嵌套函数标记）、`using`/`import`/`include`/`export`/`const` 别名 | `validation/results/ast_<ref>.json`，以文件+符号为键，行号只作参考 |
| 函数调用抽取（含 `Mod.f` 限定调用）与跨模块调用图 | call graph（JSON） |
| 层规则校验：依据 `layers.toml` 的模块→层映射与允许边、compat_edges、SCC 循环检测 | pass/fail 报告 |
| 重构前后结构对比：定义的增、删、移位；export/allow 集合差；调用点悬空检测 | `diff_<old>_<new>.md` |
| API 影响：每个 MIG 声明的「预期移动清单」（`validation/migrations/MIG-xxx.toml`）与实际 diff 自动比对；**非预期变化即失败** | pass/fail |
| 副本检测：同名或高度相似定义的列表（bowshock、Bpc2sphere 等用作自检 oracle） | 列表 |

**自检验收**：在当前仓库上运行，确定性输出（两次结果一致）；必须检出已知事实：`head.jl` 存在裸 include（AR-1）、bowshock 至少 2 份副本、`Bpc2sphere` 至少 2 份副本、`WaveSpactra_heatmap` 是死 export、MarsCommon→L2 无边。

### 6.3 Call Table（MIG-002 框架，MIG-003 用例）

- **格式**：`validation/calltable/cases/<module>.toml`。字段：`case_id`、`module`、`function`、`args`（字面量或 fixture 引用）、`kwargs`、`setup`（如 `set_particles`、`change_kp_read_data`）、`expected_behavior`（`value`/`throws`/`mutates`）、`comparison`、`atol`、`rtol`、`nan_equal`、`tags`（如 `pure_move`、`science_sensitive`、`needs_dll`、`needs_real_data`）、`evidence_level`（A/B/C/D，沿用 t4）、`migs`（关联的 MIG）。
- **比较器语义**（new_plan §10）：
  - 递归比较标量、Array、Tuple、NamedTuple、Dict（键集合须相等）、struct（逐字段）、DataFrame（列名加列值）；
  - `NaN` 与 `NaN` 视为相等（可配置）；`Inf` 的符号须一致；出现 `missing` 直接报错（全仓不用 missing，出现即说明行为变化）；
  - 视图与别名语义用 `mutates` 用例单独断言（例如 `static_slip` 共享内存）。
- **容差政策**：
  - `pure_move`（代码逐字搬运）一律 `comparison="exact"`，只放宽 NaN 判等；
  - 转发重排或参数化的情况，默认 `rtol=1e-12`；
  - 放宽容差必须在用例中写 `tolerance_justification`，并经 Pro-science 批准，**禁止为了通过而放宽**；
  - 结果不一致时，按 new_plan §10 的五类原因归因并上报，不得静默改用例。
- **必须先入表的行为基线（门禁内容）**：

| 用例组 | 来源 | 可行性 | 门禁作用 |
|---|---|---|---|
| TASK-025 `load_kp` `kp_columns` 三条：默认、自定义、`change_kp_read_data` 兼容 | t4 §5.1 | 完全可合成 | 放行任何触及 MAVEN_load 的 MIG |
| TASK-004 `get_mag_line_s` 读 `:B` 和回退 `"B"` | t4 §4 | 合成 Dict | 放行 MIG-022 |
| TASK-018 `MAVEN_SWEA.n1d` | t4 §4 | 合成 | 放行 MIG-013 |
| TASK-022 `SWEA_calc_shape_arr` | t4 §4 | 合成谱 | 放行 MIG-013/020 中 SWEA shape 的迁移 |
| TASK-003 `STA_count2eflux`/`STA_eflux2df` 默认 `m_int`（含 `m_int` 不参与计算这一无操作语义） | t4 §4、§6-2 | 合成 | 放行 STATIC 相关迁移 |
| `sta_v_4d` 与 `sta_v_4d_new` 等价门 `rel≤1e-9` | t4 U-3 | 合成 | **只出证据**。不等价时记录并交人工，不合并（H-12） |
| §4 每一行权威归属的「旧副本 vs 新权威」逐点用例 | 本草案 | 合成 | 放行对应的转发 MIG |
| 已有 `test/runtests.jl` 141 pass / 1 broken | t1 | 已可运行 | 全程不得回退 |
| `needs_dll`（`:adaptive`）、`needs_real_data`（C 类） | t4 §3、§5.4 | 不可运行 | 标记 skipped。**不伪造 DLL**；不计入通过 |

### 6.4 每个 MIG 的标准验收（缺一项即不得合并）

1. AST diff 与 `MIG-xxx.toml` 预期移动清单一致；层规则通过；无新增未登记边。
2. Call Table：该 MIG 关联的全部用例与基线比较通过；`pure_move` 结果逐位一致。
3. `julia --project=. test/runtests.jl` 通过，pass 数不低于 141（新增测试可以使总数增加），broken 不增加。
4. `validate_registry()` 不新增 errors；每个受影响模块 `load_module` 冒烟成功；allow 逐名引入冒烟成功。
5. 写入范围只限于该 MIG 的 Owned Files（通过 git diff 文件清单自动核对）。
6. 实现者与审查者分离；标记 `science_sensitive` 的 MIG 须经 Pro-science 审查通过。

---

## 7. 迁移单元（MIG）

图例：操作类型为 CREATE、MOVE、MERGE、SPLIT、RENAME、DEPRECATE、AUDIT；**Owned** 表示独占写范围。所有 MIG 都在 **HA-0 人工批准之后**才可启动。

### 波 B：验证门禁（Phase B）

| ID | 类型 | 原 → 目标 | Owned（互斥写） | API 影响 | 依赖 | 验证 |
|---|---|---|---|---|---|---|
| MIG-000 | AUDIT/冻结 | 采集基线：AST 快照，并在冻结后跑 Call Table 旧结果 | `validation/results/baseline/**` | 无 | HA-0、R-1 裁定 | 文件哈希清单 + 快照可复现 |
| MIG-001 | CREATE | AST 工具 + `layers.toml` + 迁移清单格式 | `validation/ast/**`、`validation/architecture/**`、`validation/migrations/README.md` | 无 | HA-0 | §6.2 自检 |
| MIG-002 | CREATE | Call Table schema + runner + 比较器 + 比较器自身单测 | `validation/calltable/{schema.md,runner.jl,compare.jl,selftest.jl}` | 无 | HA-0 | 比较器单测覆盖 NaN/Inf/missing/Dict/NamedTuple/struct/DataFrame |
| MIG-003 | CREATE | 行为基线用例与 fixtures（§6.3 表） | `validation/calltable/cases/**`、`validation/fixtures/**` | 无 | MIG-002 | 用例全部能在基线上运行并记录旧结果（经 MIG-000） |
| MIG-004 | CREATE | `test/runtests.jl` 末尾增加一个可选的验证冒烟入口（环境变量开关） | `test/runtests.jl`（**仅追加**） | 无 | MIG-002 | 默认行为不变：141/1 |
| MIG-005 | AUDIT | TASK-027 签名/单位审计表：依据 AST 调用图列出全部调用点及输入单位 | `.agent/audit_signature_units.md` | 无 | MIG-001 | Pro-science 审查 |
| **GATE-B** | 门禁 | 框架自检通过 + 基线冻结 + 审计表完成 → **HA-1 人工确认** | — | — | 000–005 | — |

### 波 1：建立权威（只增不删，旧实现保持不动）

| ID | 类型 | 原 → 目标 | Owned | API 影响 | 依赖 | 验证 |
|---|---|---|---|---|---|---|
| MIG-010 | CREATE+MERGE | `common/function_coordinate.jl` 包为 `module FunctionCoordinate`（自包含 include）；复制 `calculate_models.rotation_matrix/Quaternion_Rot/_reverse` | `common/function_coordinate.jl` | 新增模块 API；该文件原以裸 include 方式提供的函数，经 head.jl shim 保持可用（MIG-026） | GATE-B | pure_move 用例逐位一致 |
| MIG-011 | MERGE | 将 §4.1 所列函数复制进 MarsCommon（可按 FA-4 拆成子文件 `common/marscommon/*.jl`） | `common/MarsCommon.jl`、`common/marscommon/**` | 新增 MarsCommon API | GATE-B、MIG-005（cyclotron） | 新副本与旧副本逐点一致 |
| MIG-012 | CREATE | `models/Mars_Environment.jl`（`module MarsEnvironment`），收入 §4.3 函数 | `models/Mars_Environment.jl` | 新模块 | GATE-B | 各旧副本两两等价用例；不等价则上报 |
| MIG-013 | MERGE | SWEA shape 与 PAD 函数复制进 MAVEN_SWEA（§4.4） | `MAVEN_data/MAVEN_SWEA.jl` | 新增 SWEA API | GATE-B（TASK-018/022 用例） | exact |
| MIG-014 | CREATE | 注册表增加 `:FunctionCoordinate`、`:MarsEnvironment` 条目（deps、note、allow 初值） | `src/modules.jl`（只改注册表区） | 新可装载模块 | 010、012 | validate_registry、load 冒烟、allow 冒烟 |
| MIG-015 | MERGE | MAVEN_plot 收入 head.jl 中 §4.5 的可视化函数 | `MAVEN_data/MAVEN_plot.jl` | 新增绘图 API | GATE-B | 等价用例；`get_log_ticks` 与 `logticks` 比对结论 |
| MIG-016 | MERGE | `MarsCommon.TimeFormat(...; format)` | 包含在 MIG-011 内 | — | — | 与 plotting 版、SPO 版逐字一致 |

### 波 2：替换为转发（逐文件串行；删除旧实现体，保留旧名）

| ID | 类型 | 文件内容 | Owned | API 影响 | 依赖 | 验证 |
|---|---|---|---|---|---|---|
| MIG-020 | DEPRECATE | MAVEN_load：`Bpc2sphere`、`static_c6_*`、`cyclone_*`、SWEA shape/PAD 改为 COMPAT-FORWARD | `MAVEN_data/MAVEN_load.jl` | 旧名保留；登记 L2→L3 compat 边 | 011、013、MIG-005；TASK-025 用例 | 全部关联用例 + layers 校验 |
| MIG-021 | DEPRECATE | MAVEN_plot：`bowshock/magnetopause`→MarsEnvironment，数学函数→MarsCommon；删除死 export `WaveSpactra_heatmap` | `MAVEN_data/MAVEN_plot.jl` | 绘图 API 不变；删除一个死 export | 011、012、015 | 用例；`using MarsData` 冒烟；plotting golden（bench_06） |
| MIG-022 | DEPRECATE | IGRF：`Bpc2sphere/Bsphere2pc`→MarsCommon | `Magnetic_Model/IGRF_calculate.jl` | 不变 | 011；TASK-004 用例 | 用例 + 磁力线回归（`:euler`/`:rk4`） |
| MIG-023 | MERGE | TW_MINPA 私有 `slice2d_cal_rot`→FunctionCoordinate | `TW_data/TW_MINPA.jl` | 不变 | 010、014 | 两实现逐点等价（共线情况的行为须一致，否则保留副本并上报）；`science_sensitive` |
| MIG-024 | DEPRECATE | Single_Particle_Orbit：`TimeFormat` 转发，并显式传原格式 | `models/Single_Particle_Orbit.jl` | 不变 | 011 | 逐字一致 |
| MIG-025 | DEPRECATE | calculate_models 改为纯门面 | `calculate/calculate_models.jl` | 旧名保留 | 010、011、012 | 门面用例 |
| MIG-026 | SPLIT/DEPRECATE | head.jl 改为兼容 shim：删除裸 include 块与实现体，改为 `using MarsData` + `@load` + 绑定旧名 | `common/head.jl` | 脚本侧旧裸名保持可用 | 010–015、014 | 「include head.jl 后旧名集合 ⊇ 迁移前」由 AST 断言；用例 |
| MIG-027 | DEPRECATE | function_coordinate 中 `bowshock_zero`→MarsEnvironment | `common/function_coordinate.jl` | 不变 | 010、012 | 用例 |
| MIG-028 | DEPRECATE | `src/plotting.jl` 中 `TimeFormat`→MarsCommon | `src/plotting.jl` | 不变 | 011 | 逐字一致；plot 冒烟 |
| **GATE-2** | 门禁 | 全部转发用例通过，AST 不再检出 §4 中的重复实现（compat 转发除外）→ **HA-2** | — | — | 020–028 | — |

### 波 3：脚本与 Analysis 层

| ID | 类型 | 内容 | Owned | 依赖 | 验证 |
|---|---|---|---|---|---|
| MIG-030 | SPLIT | Pickup_ion 函数化：`pickup_ion_analysis` + `@load` + 全局 shim + 去掉 `D:/` 路径（TASK-036） | `models/Pickup_ion.jl` | GATE-2 | `science_sensitive`；合成事件下新旧入口一致；无真实数据时标注证据等级 C |
| MIG-031 | MOVE（装载方式） | `MAVEN_data/Build_data/*.jl` 改用 `@load`（TASK-037） | `MAVEN_data/Build_data/*.jl` | GATE-2 | AST：无相对 include；能解析和装载 |
| MIG-032 | MOVE（装载方式） | `example/MAVEN_plot_sample/*.jl` 改用 `@load`（TASK-038） | `example/**/*.jl` | GATE-2 | 同上 |

### 波 4：API 面、契约、Extras、清理（各自需 HA 批准的标注见右列）

| ID | 类型 | 内容 | Owned | 依赖 | 备注 |
|---|---|---|---|---|---|
| MIG-040 | CREATE | allow 白名单补全（TASK-042，保守） | `src/modules.jl` | MIG-014 完成后 | 只放 api.md 认定的入口 |
| MIG-041 | RENAME（别名） | 正确拼写别名（TASK-041）：Cold_Plasma 等 | `models/Cold_Plasma_Dispersion_Relation.jl`、`models/Maxwellian_distribution.jl` | GATE-B | 旧名保留 |
| MIG-042 | CREATE | DataKeys 增补：`MASS_AMU`/`MASS_EV_PER_KM_S2`/`DF_MASS_MASS`/角度网格键/`"Var name"`，只增加不强制使用 | `common/data_keys.jl`、`.agent/03` 附录 A | **H-10** | 契约测试 |
| MIG-043 | CREATE | `models/CATALOG.toml` 登记 Extras（Octree、Graham），写明晋升规则 | `models/CATALOG.toml` | HA-0 | 不改 Octree/Graham 本体 |
| MIG-044 | MOVE（可选） | `Magnetic_Model/IGRF_calculate.jl`→`models/`（资产留原处，路径经 Paths） | IGRF 文件、注册表、docs 链接 | **H-6** | 默认**不做** |
| MIG-045 | MOVE（可选） | Octree/Graham→`models/extras/` | 两个文件 + CATALOG | **H-7** | 默认不做 |
| MIG-046 | MOVE（可选） | Pickup_ion→`analysis/` | 文件 + 文档 | **H-8** | 默认不做 |
| MIG-047 | 可选 | 绘图面板化与 KP 归一（TASK-039/040） | `src/plotting.jl` | GATE-2，需单独批准 | 范围大，建议下一轮 |
| MIG-048 | 条件 | TASK-026 IGRF `bcompress` | `Magnetic_Model/IGRF_calculate.jl` | **H-9** | 默认不做 |
| MIG-050 | 文档 | 把规范落为 `docs/src/architecture.md` 与 `docs/src/feature_addition.md`；同步 api.md | `docs/src/**` | GATE-2 | PHASE 8 |
| MIG-051 | DEPRECATE→删 | 死代码与孤儿 docstring（TASK-043，含 D-4 `TW_load.jl:111-129`、`MGS_load.jl:96-113`，D-7 tmp 重复） | 逐文件，须在该文件所有其他 MIG 完成之后 | 全部 | AST：只删注释与字符串表达式 |
| MIG-052 | 文档补录 | `.agent/06` 补记 TASK-024/025（D-2） | `.agent/06_IMPLEMENTATION_LOG.md` | 任意 | 队长或文档实例负责 |

### 7.1 DAG

```text
HA-0（人工：本草案 + D-1 + R-1 + H 项）
  ├─► MIG-001 ─┬─► MIG-005 ───────────────┐
  ├─► MIG-002 ─┼─► MIG-003 ─► MIG-000* ───┤   (*基线采集在 003 用例就绪后执行；AST 基线可提前)
  │            └─► MIG-004                 │
  └─► MIG-043, MIG-052（非关键路径，可交 ustc）
                                           ▼
                                   GATE-B / HA-1
          ┌──────────┬──────────┬──────────┼──────────┬──────────┐
       MIG-010    MIG-011    MIG-012    MIG-013    MIG-015    MIG-041
          │  (016⊂011)  │          │          │          │
          └────┬────────┴────┬─────┘          │          │
             MIG-014        │                 │          │
               │            │                 │          │
   ┌───────┬───┴───┬────────┼───────┬─────────┼──────────┤
 MIG-023 MIG-027 MIG-025  MIG-022 MIG-024  MIG-020   MIG-021   MIG-028
   └───────┴───────┴────────┴───────┴─────────┴──────────┴─────► MIG-026（head shim 最后）
                                           ▼
                                   GATE-2 / HA-2
                     ┌──────────┬──────────┼──────────┬──────────┐
                  MIG-030    MIG-031    MIG-032    MIG-040    MIG-042(H-10)
                     └──────────┴──────────┴──────────┴─► MIG-050 ─► MIG-051 ─► 终审 HA-F
可选/条件：MIG-044/045/046/047/048 只在对应 H 项批准后插入，且须遵守文件锁。
```

### 7.2 文件锁（同一时刻只允许一个 MIG 持有）

| 文件 | 持有顺序 |
|---|---|
| `common/MarsCommon.jl` | 011 →（不再改） |
| `common/function_coordinate.jl` | 010 → 027 |
| `MAVEN_data/MAVEN_plot.jl` | 015 → 021 |
| `MAVEN_data/MAVEN_load.jl` | 020 → 051 |
| `MAVEN_data/MAVEN_SWEA.jl` | 013 → 051 |
| `src/modules.jl` | 014 → 040（→ 044 可选） |
| `src/plotting.jl` | 028 →（047 可选） |
| `Magnetic_Model/IGRF_calculate.jl` | 022 →（048/044 可选） |
| `calculate/calculate_models.jl` | 025 |
| `common/head.jl` | 026 |
| `test/runtests.jl` | 004 → 之后的 MIG 只许追加，且须串行 |

---

## 8. 杂项 models（Extras）规范

1. **两级分类**：
   - **Registered Model（L4）**：进注册表；`module X … end` 自包含；只依赖 L1/L1n；有 Call Table 用例；入口进 allow；改动受科学红线约束。
   - **Extra（X）**：探索性或工具性杂块，例如八叉树、凸包、一次性数值实验。不进注册表，在 `models/CATALOG.toml` 登记。
2. **CATALOG 条目字段**：`name`、`file`、`purpose`、`status`（experimental / maintained / frozen）、`external_deps`、`entry`（示例调用）、`owner_note`、`promotion_candidate`（bool）。
3. **调用手段**：显式 `include(joinpath(MarsData.project_root(), entry.file))`。任何注册模块与 L0 **不得**依赖 Extra。Extra 的重依赖（如 Octree 的 GLMakie）**永不**进入 `[deps]`。
4. **Extra 的最低要求**（低摩擦）：文件头一行说明；不在加载期读写外部路径；如定义模块，名字不得与注册模块冲突。无测试要求。
5. **晋升为 Registered Model 的条件**（满足任一即应晋升）：被 ≥2 处非脚本代码调用；被 Analysis 层的正式入口依赖；用户要求对其结果做回归保护。晋升动作 = 包成 module、写注册表条目、补 Call Table 用例、登记 allow。
6. **降级或冻结**：注册模型长期无人使用时，可标为 `frozen`，但仍保留在注册表中，不删除。
7. **磁场模型**：IGRF 在逻辑上属于 Registered Model（L4）。是否在物理上迁到 `models/` 取决于 H-6；不迁不影响本规范的适用。

---

## 9. Feature Addition Convention（未来功能添加规范）

> 原则：**新功能可以快速增加，但必须落在可预测的位置**。新增一个函数，最少只需回答 FA-1 的一个问题，再完成 FA-8 的三步清单。

### FA-1 归属判定（按顺序问，第一个「是」即为落点）

| # | 问题 | 落点 |
|---|---|---|
| 1 | 是一次性探索、不确定是否长期保留？ | Extras（CATALOG 登记），或直接写在个人脚本里 |
| 2 | 是物理/数学常量？ | `common/constants.jl` |
| 3 | 是读取或解析某种数据文件或产品？ | 对应数据源的 L2 读取模块（MAVEN_load/TW_load/MGS_load/SP_load）；全新数据源则按 FA-3 新建 `XXX_load` |
| 4 | 是某仪器的矩、标定、单位换算？ | 对应的 L3 仪器模块 |
| 5 | 是坐标或参考系变换？ | 标量或数组式（度制、无 Rotations 依赖）→ MarsCommon；使用旋转对象或四元数 → FunctionCoordinate；仪器专属视场变换 → 该仪器模块 |
| 6 | 是与行星无关的数学、统计、拟合、时间格式工具？ | MarsCommon |
| 7 | 是火星电离层、环境、边界的**经验或专用计算**？ | MarsEnvironment（或 H-4 选定的落点）；若属于成体系的物理模型（如新的磁场模型、色散关系），则新建或放入 L4 模型模块 |
| 8 | 是绘图基元、色标、刻度、标签？ | MAVEN_plot；多面板概览合成 → `src/plotting.jl` |
| 9 | 是组合多个模块完成的一次科研流程？ | L6 Analysis：函数化入口加 `@load`，不放进下层模块 |

### FA-2 同时依赖两个已有模块的新函数

- 如果两个依赖都在同一层或更低层，函数放在**更高的消费层**：例如需要 MAVEN_STATIC 和 IGRF 的函数，属于 L6 Analysis 入口，而不是塞进其中任何一个模块。
- 如果这类组合反复出现（≥3 个函数），新建**组合模块**，放在两者之上的层，并登记注册表 `deps`。
- **禁止复制**其中一个模块的实现来规避依赖（AR-6 的教训）；禁止为方便而引入反向边。

### FA-3 何时新建 Module

满足任一条即新建，否则加入既有模块：
1. 新的数据源或仪器；
2. 新的物理能力域，与现有模块职责不重叠；
3. 引入一个现有模块都没有使用的重外部依赖（新模块隔离该依赖，依赖经载体解析，见 FA-7）；
4. Extra 满足晋升条件（§8-5）。

新建模块的固定动作：`module X … end` 自包含 include；写注册表条目（`deps`、`note`、空 allow）；在 `layers.toml` 中登记层；添加至少一条 Call Table 用例。

### FA-4 何时拆分 Module 或建立子层

- 一个模块横跨 ≥2 个能力层（例如读取与科学处理并存，即 AR-17 的 God module）→ **SPLIT**。原位置保留转发，迁移按 MIG 流程走。
- 模块很大但能力内聚（例如 MarsCommon 超过约 1000 行或超过 6 个分节）→ 在**同一 module 内拆成子文件**（`common/marscommon/*.jl`）。API 不变，这不算拆分模块。
- 同一层出现 ≥3 个同族模块（例如 3 个以上磁场模型）→ 可以建立**子层目录**（`models/magnetic/`），先在 `layers.toml` 登记，再移动。

### FA-5 依赖方向

严格遵守 §2.2 表格。新边若不在表中，即视为架构变更，须总架构师审定。AST 层规则（MIG-001）在每次合并前自动检查。

### FA-6 API、命名与状态

- 新入口优先全限定名。只有写入 `docs/src/api.md` 的入口才可以加入 allow。加入时须同步三件事：api.md、allow、`@load` 冒烟测试。
- 不新增模块级可变全局变量。状态用显式参数或不可变配置（`PlasmaState` 模式）。
- 新 Dict 键先登记 DataKeys 与附录 A；单位写进 docstring，并与「实际输出为 SPEDAS 单位」的现状保持一致标注。

### FA-7 `Project.toml` 依赖边界（取决于 D-1 裁决）

- 分支 A/C：只有 L0 自身使用的依赖可以进入 `[deps]`；L1–L6 模块的依赖经载体 LOAD_PATH 解析；开发工具依赖永不进库包。
- 分支 B：运行期依赖可以进入 `[deps]`，开发工具依赖仍然禁止。
- 任何 `[deps]` 变更都须在 `.agent/06`（或后续日志）登记理由。无日志的 `Pkg.add` 视为架构事件（D-1 的教训）。

### FA-8 三步清单（每个新函数或新模块）

1. 按 FA-1 选定落点；如属新模块，按 FA-3 完成固定动作。
2. 写 docstring，包含单位、角度制、就地修改语义。如有 Dict 键，登记 DataKeys。
3. 至少添加一条 Call Table 用例。纯探索代码走 Extras 可以免除这一步；AST 层规则必须通过。

---

## 10. 施工组织建议（含队长最多 8 Agent）

| 槽位 | 角色 | 现状 | 实施期职责 | 写入范围 |
|---|---|---|---|---|
| 1 | captain | 在岗 | 调度、文件锁、证据汇总；不编码 | `.agent/` 状态文档 |
| 2 | chief-architect | 在岗 | GATE-B/2/F 架构审定；审查 MIG 清单与层规则变更；不编码 | 架构文档 |
| 3 | pro-architecture-official | 在岗 | 独立审查：本草案、layers.toml、每个 MIG 的 AST diff | 只写审查文档 |
| 4 | pro-science-official | 在岗 | 独立审查：MIG-005 审计表、science_sensitive MIG（013/020/023/030）、容差放宽 | 只写审查文档 |
| 5 | flash-recovery（转为 flash-validation） | 在岗 | MIG-001、002、003、000、004 | `validation/**`、`test/runtests.jl`（004） |
| 6 | deepseek-code-ustc-1 | 在岗 | 非关键路径：MIG-043、052、050 文档草稿；AST 副本报告的整理 | 各自 Owned |
| 7 | **pro-code-official-1**（新增名额） | 待加 | 复杂迁移：MIG-011、012、020、023、026、030 | 按文件锁 |
| 8 | **flash-code-official-1**（新增名额） | 待加 | 常规迁移：MIG-010、013、014、015、021、022、024、025、027、028、031、032、040、041、051 | 按文件锁 |

- **实现与审查分离**：两名代码实例都不审查自己的 MIG；Pro 审查实例不写代码。
- **并行上限**：波 1 最多同时进行 2 条实施线（两个代码实例）加 1 条验证线。波 2 受文件锁约束。
- **汇报驱动**：每个 MIG 完成或阻塞时主动汇报，不轮询。
- **慢渠道**：ustc 实例不放在关键路径上；需要转交时，先撤销原所有权，再转交（new_plan §15-6）。
- 名额紧张时，可在 GATE-2 之后让 flash-recovery 的验证工作并入 flash-code，释放出一个名额给第二个 pro-code。

---

## 11. 风险（架构增量）

| ID | 风险 | 缓解 |
|---|---|---|
| RA-1 | 基线采自未提交的工作区，若被清理则不可复现 | R-1 先裁定；MIG-000 记录哈希清单 |
| RA-2 | head.jl 改为 shim 后，依赖其副作用的旧脚本失效（例如隐式 `using` 了大量包） | shim 保留原 `using` 列表；AST 断言旧名集合是迁移后集合的子集 |
| RA-3 | bowshock 各副本可能不等价（单位或拟合系数不同） | MIG-012 先出等价证据；不等价就分名保留，并交 Pro-science |
| RA-4 | MAVEN_plot 预装闭包变大 | MarsEnvironment 无重依赖；MIG-021 增加 `using MarsData` 耗时对比，只作记录，不做性能优化 |
| RA-5 | compat 边长期滞留 | `layers.toml` 中为每条 compat 边写移除期限；终审时列出剩余边 |
| RA-6 | D-1 裁决延迟 | 所有 MIG 都不触碰 `Project.toml`；FA-7 两套文本都已备好 |

---

## 12. 人工审批点与待决项

### 审批点

- **HA-0**：审批本草案，以及下列 H 项中至少 H-1、H-2、H-3、H-4、H-5。批准前**一律不施工**。
- **HA-1**（GATE-B）：确认验证框架可以运行、基线已冻结、审计表已完成。
- **HA-2**（GATE-2）：确认去重转发的等价证据成立。
- **HA-F**：最终架构审查，以及科研正确性边界声明（t4 §7）。

### 待决项

| ID | 事项 | 本草案立场 |
|---|---|---|
| H-1 | D-1 依赖清单：A 收敛 / B 接纳 / C 净化 | 倾向 A（同 t3）；保持开放 |
| H-2 | R-1：是否先把工作区快照提交 | 建议先固化，作为基线 ref |
| H-3 | head.jl 按能力拆散，而不是整体包成 MarsUtils（偏离 03 ARCH-002） | 建议拆散 |
| H-4 | MarsEnvironment 独立成模块，还是并入 MarsCommon | 建议独立 |
| H-5 | calculate_models 解体，并保留一个周期的门面 | 建议执行 |
| H-6 | Magnetic_Model 物理迁入 models/ | 建议本轮不迁，只做逻辑归类 |
| H-7 | Extras 物理迁到 models/extras/ | 建议不迁，只登记 CATALOG |
| H-8 | Pickup_ion 迁到 analysis/ | 建议不迁 |
| H-9 | 是否纳入 TASK-026（bcompress） | 建议不纳入 |
| H-10 | DataKeys 的 `:mass` 多语义常量等增补 | 建议只增不改语义 |
| H-11 | C6/C7/C10/C11/C12/C13 | 使用者裁决；本轮只原样搬运 |
| H-12 | sta_v_4d 与 sta_v_4d_new 等价结果的处置 | 只出证据，不合并 |
| H-13 | 弃用转发是否发 depwarn | 建议默认不发 |
| H-14 | 是否放宽 03 「不移动文件」红线 | 建议只为可选 MIG 逐项放宽 |

---

## 13. 合规声明

- 唯一写入：`.agent/target_architecture_draft.md`。没有改动代码、测试、配置、`Project.toml`/`Manifest.toml`、`new_plan.md`、`.agent/00–06`，也没有改动其他成员的交付物。
- 没有创建子 Agent，没有轮询成员进度，没有运行写入仓库的命令。
- 已继承 t1/t3/t4 的结论，没有重新扫描全仓；只为权威归属表定向 grep 了函数定义位置，行号以符号名为准（D-5）。
- 本草案**不授权实施**；后续工作须经 HA-0。
