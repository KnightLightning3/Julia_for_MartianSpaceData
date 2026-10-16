# 更新日志

## [2026-10-16] IGRF 纯 Julia 化合并：移除 Fortran DLL，磁力线追踪默认改用 DP5

### 场值内核（`models/IGRF_calculate.jl`，以 `IGRF_new3.jl` 为基线合并）

- 合并阶段 0～3：常数化 `root_dir`/`gh_filename`/`B_compress`；勒让德函数 P/DP 只保留滚动三行、`(AA/r)` 逐阶滚动；新增 `GS_T`/`HS_T`/`REALK_T`/`MFLOAT` 派生系数表（M 连续布局，供 `@simd` 向量化）与 `rebuild_derived_tables!()`；新增 `IGRFWorkspace`、`IGRF!`/`IGRF_dB!`（含 `B_compress` 均匀场项与 9 个偏导）、`IGRF_batch!`/`IGRF_batch`；`cos(mϕ)/sin(mϕ)` 改为每 8 项刷新锚点的分块递推（`fma` 补偿锚点相位误差）。
- **移除全部 Fortran/DLL 代码**：删除 `IGRF_fortran`、`IGRF_fortran_free`、`IGRF_sphere`、`RK4_Trace_fortran`、`mag_trace_rk4`、`mag_trace_rk4_fortran_ADAPTIVE_STEP`、`IGRF_DLL_PATH` 及全部 `ccall`；`trace_mag_line` 的方法只剩 `:dp5`（默认）与 `:euler`，`:rk4`/`:adaptive` 抛 `ArgumentError`；`IGRF_pc` 与 `mag_trace_Euler_step` 改走纯 Julia 内核（Euler 由「Fortran 场值 + 定步长」变为「纯 Julia 场值 + 定步长」）。同时删除二进制资源 `models/IGRF_DLL.dll`；系数文件 `models/gh_gao` 经 `FortranFiles` 读取的路径不变。
- **修复 `IGRF_batch!` 数据竞争（正确性缺陷）**：串行早退分支把工作区声明为 `ws`，而 `Threads.@spawn` 块内同名赋值会被闭包捕获（Julia 捕获变量而非值），导致所有任务共用一个工作区。表现为结果随机错误（n=5000 时约 95% 的点与串行不一致，出现 1e10～1e19 nT 的垃圾值）与耗时虚高。改名 `ws_serial` 后消失。这也解释了交接文档 §7.1「同代码两次实测互相矛盾」：`min_chunk` 之前没有该分支，`mc=1` 与旧代码并非同一路径。

### 磁力线追踪

- `trace_mag_line` 默认方法由 `:euler` 改为 `:dp5`（批注批准），并同步 docstring 与专题文档；`:euler` 保留可用。
- 新增纯 Julia `mag_trace_dp5`（Dormand–Prince 5(4)，FSAL，四阶稠密输出，笛卡尔坐标弧长参数化）与 `trace_mag_lines`（每条线一个任务）；起点/中途点落在极轴时 θ 夹到 `[1e-8, π-1e-8]`。
- 修复既有缺陷：`output_frame != "pc"` 时 `mag_line_num` 未定义导致 `UndefVarError`；`trace_mag_line` 后处理循环类型不稳定（每行约 28 次分配）改为类型断言 + 无临时向量，`"pc"` 输出逐位不变。
- `mag_trace_dp5`/`trace_mag_line` 的 `threaded_output` 默认改为 `false`（避免在 `trace_mag_lines` 外层并行时嵌套并行；数据竞争修复后单线开启它仍有收益，可显式打开）。

### 准确性与效率验证（64 线程，本机实测）

- 场值/导数：黄金参考值（移除前由 Fortran DLL 内核 `IGRF_110`/`RK4_STEP` 生成，已固化在 `models/test.jl`）一般 ϕ 最大相对 |B| 3.3e-15、`B_compress=[12,-7,5]` 1.6e-15、`DB` 1.8e-14；四阶中心差分独立检验 9 个偏导 2.2e-9/2.0e-9/3.0e-10（阈值 1e-8）；`IGRF!`/`IGRF_dB!` 稳态零分配；2 万点 `IGRF_batch!` 与串行逐位一致。
- 合并保真：合并后内核与 `IGRF_new3.jl` 的纯 Julia 内核在 500 个随机点上 `IGRF!`/`IGRF_dB!` 逐位一致；Euler 由 Fortran 内核改纯 Julia 后，同一条线 2092 行位置最大偏差 5.1e-13 km。
- 性能：`IGRF!` 4.94 μs（移除前 Fortran 内核 18.1 μs）、`IGRF_dB!` 7.98 μs；2 万点串行 115.8 ms / 多线程 6.74 ms（17×）。单线 4500 行：DP5 28.3 ms（串行输出）、10.3 ms（单线并行输出）、Euler 25.8 ms、`step=5 km` 5.1 ms；256 条线 922198 行由串行 7.26 s 降到 0.436 s（16.6×，逐位一致）。
- 精度：DP5 到高精度参考线的最大几何偏差 7.99e-4 km（`xtol=1e-3`），Euler 0.858 km；`hmax` 扫描与交接文档一致，默认仍取 25 km。
- `IGRF_batch!` 修复后耗时稳定：1 万点 5～13 ms、5 万点 14 ms（修复前交接文档实测为 422 ms / 2180 ms）。

### 文档与范围

- 同步 `src/modules.jl` 的模块说明、`docs/src/api.md` 的 IGRF 条目、`docs/src/architecture.md` 依赖表、`docs/src/coordinates.md`、`docs/src/migration.md` 及中英文 README 中「IGRF 需要外部 Fortran 运行库与 DLL」的表述；`models/test.jl`、`models/test_trace.jl` 重写为针对合并后模块的黄金参考回归与追踪测试。
- 按用户指示，本次未改动多线程性能优化本身（只修复上述正确性缺陷），也未同步 `test/` 下与 DLL 绑定的既有断言（`igrf_move_test.jl` 的 sha256/文件存在断言、`runtests.jl` 的 `:euler`/`:rk4` 用例、迁移账本 AST hash）——这些验收已完成使命。中间版本 `models/IGRF_new{,2,3}.jl` 不纳入提交。

## [2026-10-15] 运行配置统一为 TOML，弃用 INI

- Julia 与全部 Python 下载、扫描、索引、检查及派生数据脚本统一读取 `config/settings.toml`；移除 INI 读取、列表解析及迁移命令，清理 `IniFile` 依赖。
- 扩充全参数模板，包含共享数据目录，以及 Python 专用的服务器认证、代理、下载模式、线程、重试间隔、外部下载器路径、日期窗口和产品选择设置。
- 初始化器仅生成 TOML，拒绝覆盖已有文件；配置缺失、类型错误、非法下载模式及无效服务器索引明确报错，不再静默回退到旧 INI 或默认磁盘目录。
- 相对文件系统路径以仓库根目录为基准，目录拼接不再依赖末尾斜杠；保留 Windows 绝对路径语义。修复目录下载脚本硬编码服务器编号覆盖配置、自定义清理配置仍依赖默认文件的问题。
- 中英文 README 明确说明 INI 已弃用且不再读取，同步当前指南、API 索引及合成回归测试；不运行真实下载、真实数据或 DLL 验证。
- 依赖清单同时保留本机已有的 Julia 1.12.5 锁定环境及 Rotations、BenchmarkTools 更新；移除根项目及 benchmark 锁定清单中的 IniFile。
- 验证：Python unittest 发现的 18 项及独立 runner 的 20 项检查通过（有效 CDF 写入子场景因缺 cdflib 跳过）；Julia 路径配置与调用点 18 项、API 生成工具 23 项通过，4 组合成跨语言路径一致。Documenter 构建成功（API 页面有大小提示），Wiki 10 页预览与链接自检通过，未发布 Wiki。

## [2026-10-15] 三维坐标接口统一与架构文档同步

### 坐标转换

- `FunctionCoordinate` 的点转换统一接收三维 `SVector`，兼容长度为 3 的实数向量，返回 `SVector{3}`；批量转换在调用处使用广播、循环或 `map`，不接受矩阵作为单点输入。
- 增加通用 `pc2sphere` / `sphere2pc`（弧度制、余纬）及 MAVEN 仪器专用 `MAVEN_xyz2sphere` / `MAVEN_sphere2xyz`（角度制、仰角），集中于 `common/function_coordinate.jl`，同步 STATIC 和 Pickup 调用。
- 测试确认 MAVEN 与 MINPA 的坐标轴、角度及退化行为不同，分别保留接口；补充 PA、MINPA、MAVEN 与通用球坐标的定义和边界说明。
- 按函数审查后，将部分三维及投影范数改用 `hypot`，改善极大、极小输入的稳定性；保留旋转构造器中参与共线判断的范数算法。记录浮点末位及混合 NaN/Inf 行为差异，不宣称逐位等价。
- 删除 `Quaternion_Rot` / `Quaternion_Rot_reverse`，文档改用 `q * v`、`inv(q) * v` 与旋转矩阵乘法；说明列向量、行存储 N×3 数据和主动/被动旋转的用法。
- IGRF 高速计算内部的标量坐标函数保留原公式，取消导出及聚合入口中的裸名暴露，仅保留 `IGRF_pc` 白名单。

### 结构与依赖

- 将 Graham、Octree 移入 `models/extras/`，新增 `models/CATALOG.toml` 记录显式加载方式与依赖；将 Pickup 脚本移入 `analysis/`，同步调用及迁移证据。
- STATIC、SWIA、SWEA 计算模块移除未使用的 `CommonDataFormat` 导入；STATIC 显式导入 `QuatRotation`。
- 增加公开键 `DataKeys.MASS`，文档区分质量基准、质量轴与各函数输出的同名键语义。

### 文档与生成工具

- 重写中英文 README，同步架构、数据读取、执行流程、数据格式及 Wiki 导航，增加架构、迁移和坐标转换专题。
- 新增 `docs/pages.toml`，统一维护 Documenter 导航与 Wiki 页面映射；新增静态 AST API 索引生成器 `tools/generate_api.jl`，支持生成及 `--check` 过期检查，无需加载科学模块或 DLL。
- 修正文档中的单日读取接口、依赖边界、STATIC 分布转换步骤及命令；校对产品表的 53 个产品 ID。
- Wiki 预览保留输出目录中的其他文件，修正跨页链接及数学公式定界，保持原有公式内容。
- 更新 AST 迁移记录、文件移动证据及交接说明，增加坐标接口、调用点、文件归属和文档工具回归检查。

### 验证与范围

- 最新坐标接口、生产调用、AST 归属、Pickup、旧坐标迁移及 STATIC 质量回归共 566 项定向检查通过；API 生成器 23 项、Python 文档工具 8 项检查通过。
- Documenter 实际构建成功且无警告，生成 9 个正文页面；Wiki 本地预览生成 10 个文件并通过链接自检，未发布远端。
- 通用迁移检查为 28 ok、0 fail、11 unknown；unknown 不计为通过。完整主套件仍受缺少 `CommonDataFormat`、`FortranFiles` 等环境问题影响，不宣称全套通过。
- 按用户要求挂起真实数据校验，不进行 DLL 验证；逻辑溯源基准为初始提交 `a09511aa7b88c874cefe8ca966c98aa267db9365`，本次定向验证不代表全项目等价性证明。

## [2026-10-13] 文档目录合并：`doc/` 并入 `docs/`，Wiki 改为从文档源生成并推送

### 结构变更

- **删除 `doc/`，`docs/` 成为唯一文档根目录**，`docs/src/*.md` 确认为唯一权威文档源：
  - `doc/MAVEN_instrument_sis/*.pdf` → `docs/references/MAVEN_instrument_sis/`（12 份仪器 SIS 手册）
  - `doc/MAVEN_potential.html` → `docs/references/MAVEN_potential.html`
  - `doc/refactoring_*.md` → `docs/reports/`（4 份报告，作为**历史快照内容不变**，仍保留当时的函数名与路径）
  - `doc/wiki/home.md` → `docs/wiki/home.md`（重写为 Wiki 导航首页）
- **删除 `doc/wiki/` 下 4 个陈旧副本**（`MAVEN_data_format.md`、`MAVEN数据读取.md`、`swia_electron_correlated.md`、`程序与函数Wiki.md`）：内容早已由 `docs/src/` 同名页面取代，且旧副本缺少 `docs/src/api.md` 的「MarsData 包 API」章节。
- `docs/src/*.md` 中的仓库链接统一为 GitLab 规范形式 `…/-/blob/main/<path>`（`api.md` 42 处、`data_reading.md` 1 处）。

### 新增

- `tools/push_wiki.py`：把 `docs/src/*.md` 生成为 GitLab Wiki 页面并推送（`--dry-run` 预览并自检站内链接 / `--push` 发布）。Wiki 是**独立 Git 仓库** `…/Julia_for_MartianSpaceData.wiki.git`，脚本负责克隆或更新、写入、提交、推送，并自动把 `](xxx.md)` 形式的跨页链接改写为 Wiki 页面名。
- `docs/wiki/_sidebar.md`：GitLab Wiki 自定义侧边栏。
- `docs/README.md`：文档体系说明（目录分工、产出命令、Wiki 页面映射、维护约定）。
- `README.md` / `README_EN.md`：新增「Wiki 推送步骤 / Publishing the Wiki」小节，写明 Wiki 是独立 Git 仓库、完整命令（`--dry-run` / `--push` / `--workdir` / `--prune` / `--remote`）、页面映射表与推送后验证方式。
- Wiki 新增页面「项目执行流程」（源 `docs/src/pipeline.md`）。

### 修复

- `MAVEN_data/build_read_me.py` 原先把生成的模型表写回已废弃路径 `doc/wiki/MAVEN_data_format.md`，改为写 `docs/src/data_format.md`。
- `docs/src/data_reading.md` 的 `include(path * "/MAVEN_load.jl")` 与旧 `doc/wiki` 副本的 `include("$path/MAVEN_load.jl")` 不一致，统一采用 `path * "/MAVEN_load.jl"`（与 `common/head.jl`、`models/Pickup_ion.jl` 的 `Package_path*"…"` 写法一致）。

### 验证

- `julia --project=docs docs/make.jl` 构建成功（输出 `DOCS_BUILD_OK`，6 个页面），已确认首页含新增的「文档体系」小节。
- `python tools/push_wiki.py --dry-run`：生成 7 个 Wiki 文件，站内链接自检通过，`api.md` 的 3 处跨页链接正确改写。
- `python tools/push_wiki.py --push`：推送成功，Wiki 仓库新增提交 `3a392f2`（7 个文件，+360 / −30）。
- 逐页访问验证均返回 HTTP 200：`home`、`项目执行流程`、`程序与函数Wiki`、`MAVEN数据读取`、`MAVEN_data_format`、`swia_electron_correlated`、`_sidebar`。
- 注：推送需走 SSH（`git@git.ustc.edu.cn:…wiki.git`）；HTTPS 推送依赖 Git Credential Manager 等交互式凭据。

## ⚠️ [2026-10-13] 破坏性变更（BREAKING）：MarsCommon 逐元素函数改为纯标量

> **本节面向所有直接调用 `MarsCommon` 数学函数的使用者，请优先阅读。**

### 变更内容

`MarsCommon` 中 10 个「逐元素标量数学」函数**内部不再做加点（广播）运算**，
参数统一标注 `::Real`，与 `sin` / `log` 等 Julia 官方函数对齐 ——
**对数组请在调用处加广播点**：

```
instrument_sphere_to_cartesian / instrument_cartesian_to_sphere / spherical_to_cartesian
ion_energy2v / ion_speed_to_energy / e_energy2v
electron_eflux_to_psd / ion_eflux_to_psd / ion_eflux_to_psd_approx
doppler_shift
```

### 会报什么错

```julia
MarsCommon.ion_energy2v(energy_array, 16)     # 之前可用，现在报错
# MethodError: no method matching ion_energy2v(::Vector{Float64}, ::Int64)
```

### 迁移步骤

```diff
- v   = MarsCommon.ion_energy2v(energy_array, 16)
+ v   = MarsCommon.ion_energy2v.(energy_array, 16)          # 加一个点

- v0  = MarsCommon.e_energy2v.(energy_array)
-     # 上面这种已经是正确写法，无需改动

- xyz = MarsCommon.instrument_sphere_to_cartesian(1.0, theta_array, phi_array)
+ xyz = MarsCommon.instrument_sphere_to_cartesian.(1.0, theta_array, phi_array)

  v   = MarsCommon.ion_energy2v(energy_scalar, 16)          # 标量调用完全不变
```

### 为什么这样改

- **与 Julia 惯例一致**：`sin` / `log` 等对数组同样需要加点；本仓库
  `MAVEN_load.Bpc2sphere`、`IGRF_calculate.pc2sphere` / `sphere2pc` / `Bsphere2pc` / `Bpc2sphere`
  本来就是纯标量实现，`MarsCommon` 这批函数是异类。
- **仓库内零行为变化**：已核查全部调用点 —— 批量调用**本来就已经加了点**，标量调用不加点，
  与改动后完全兼容，因此仓库内无一处需要修改。
- **数值完全一致**：新旧实现逐位对拍（能量/速度/PSD 多组输入），最大相对差 `0.0`。
- **误用立即报错**：`::Real` 标注使「传数组不加点」直接抛 `MethodError`，杜绝静默返回
  无意义结果（此前 `instrument_sphere_to_cartesian([1.0,2.0], 30.0, 45.0)` 会静默成功）。

### 未受影响（本身就是按数组/矩阵设计，保持原样）

`position_altitude`、`position_local_time`、`position_latitude`（入 `N×3` 矩阵、出长度 N 向量）、
`rotate_vector`（矩阵乘法）、`eflux_to_df!`（字典原地修改）、
`searchsortednearest` / `searchsortednearest_range`（整条时间轴的二分查找）。

---

## ⚠️ [2026-10-13] 破坏性变更（BREAKING）：`data_get_from_date` → `load_MAVEN_data`

> **本节面向所有下游使用者，请优先阅读。**
> 这是一次**不向后兼容**的改名：**旧名已被删除，且不保留别名**。沿用旧名的脚本会立即报错。

### 会报什么错

```
UndefVarError: `data_get_from_date` not defined
```

### 改名对照（调用方需要替换的部分）

| 旧名（已删除，调用即报错） | 新名 |
| --- | --- |
| `MAVEN_load.data_get_from_date` | **`MAVEN_load.load_MAVEN_data`** |
| `MarsCommon.electron_energy_to_speed` | **`MarsCommon.e_energy2v`** |
| `MarsCommon.ion_energy_to_speed` | **`MarsCommon.ion_energy2v`** |

### 迁移步骤

1. 在调用方代码中全局查找替换：

   ```diff
   - Data_Dict = MAVEN_load.data_get_from_date(date; model_index = ["MAG_pc1s", "LPW_wave"])
   + Data_Dict = MAVEN_load.load_MAVEN_data(date; model_index = ["MAG_pc1s", "LPW_wave"])

   - v = MarsCommon.electron_energy_to_speed(energy_eV)
   + v = MarsCommon.e_energy2v(energy_eV)

   - v = MarsCommon.ion_energy_to_speed(energy_eV, mass_amu)
   + v = MarsCommon.ion_energy2v(energy_eV, mass_amu)
   ```

2. **除名字外无需任何改动**：函数签名（`(date::DateTime; model_index=[], show_filename=false)`）、参数含义、返回结构（`Dict{String,Dict{Symbol,Any}}`，含 `:data_load_flag` / `:filename`）与行为**完全不变**。

3. 若使用包化装载入口，白名单已同步为新名：

   ```julia
   MarsData.@load MAVEN_load
   Data = load_MAVEN_data(date; model_index = ["MAG_ss1s_cdf"])   # 裸名可用
   ```

### 影响范围

- 代码与**现行文档**共 24 个文件已同步改名（含 `README`、`docs/src/*`、`doc/wiki/*`、示例、`download_data/`、`models/Pickup_ion.jl`）。
- **历史快照保留旧名、不作修改**，仅作为记录：`CHANGELOG.md` 既有条目、`doc/refactoring_diagnosis_report.md`、`doc/refactoring_audit_a42e14b.md`。在这些历史文档中看到 `data_get_from_date` 属于正常现象。
- **未受影响的同名函数**：`TW_data/TW_MINPA.jl` 的 `MINPA_energy2v` 是另一个函数；`MarsCommon.ion_speed_to_energy`（逆运算）本次未改名。

---

## [2026-10-13] 裸名白名单落地 + 能量/读取函数重命名 + 依赖自动装载

### 白名单（`src/modules.jl`）

按规格开放三组裸名（`@load` 时引入调用者作用域）：

| 模块 | 放行的裸名 |
| --- | --- |
| `MarsCommon` | `searchsortednearest`、`e_energy2v`、`ion_energy2v` |
| `MAVEN_load` | `load_cdf`、`load_MAVEN_data` |
| `IGRF_calculate` | `IGRF_pc`、`pc2sphere`、`sphere2pc` |

其余 15 个模块白名单仍留空（`@load` 只绑定模块名）。

### 重命名（全局，含代码与现行文档共 24 个文件）

- `electron_energy_to_speed` → **`e_energy2v`**
- `ion_energy_to_speed` → **`ion_energy2v`**
- `data_get_from_date` → **`load_MAVEN_data`**：原别名提升为正名，**旧名彻底删除**（无别名保留）；`MAVEN_load.jl` 中 `load_MAVEN_data = data_get_from_date` 一行移除，docstring 中"别名"说明同步删除。

涉及代码：`common/MarsCommon.jl`、`calculate/calculate_models.jl`、`MAVEN_data/MAVEN_load.jl`、`MAVEN_data/MAVEN_plot.jl`、`MAVEN_data/MAVEN_STATIC.jl`、`MAVEN_data/MAVEN_SWEA.jl`、`TW_data/TW_load.jl`、`models/Pickup_ion.jl`、`download_data/get_all_orbit.jl`、`example/MAVEN_plot_sample/*.jl`、`src/modules.jl`、`test/runtests.jl`。

**未改名（按指令只改这两个正向函数）**：逆函数 `ion_speed_to_energy` 保持原名，因此当前是 `ion_energy2v` ↔ `ion_speed_to_energy` 的不对称命名；`TW_data/TW_MINPA.jl` 的 `MINPA_energy2v` 是另一个函数，未受影响。

**历史快照未改**（保持记录真实）：`CHANGELOG.md` 既有条目、`doc/refactoring_diagnosis_report.md`、`doc/refactoring_audit_a42e14b.md` 中仍保留旧名。

### 实现修正：依赖自动装载

`ModuleSpec.deps` 现在会在装载目标模块**之前**递归装入同一载体。原因是实测发现 `common/MarsCommon.jl` 首行为 `using ..constants`（相对父模块），单独装载会报 `UndefVarError: constants not defined`；先装 `constants` 再装 `MarsCommon` 才成功。修复后 `MarsData.load_module(:MarsCommon)` 可独立使用，用户要求的 `MarsCommon` 白名单才真正可用。

### 文档

- `README.md` / `README_EN.md`：模块装载章节补充"已开放的白名单"表与用法示例、依赖自动装载说明。
- `docs/src/api.md`：同步白名单表与依赖自动装载说明；`load_MAVEN_data` 名称更新。

### 验证

- `julia --project=. test/runtests.jl` → **82/82 通过**（新增「白名单内容与生效」15 项：白名单内容断言、`MarsCommon` 独立装载、裸名可用性、未列入者不可裸名、白名单函数可调用）。
- 15 个改动 `.jl` 文件 `Meta.parseall` 语法检查全部通过。
- 端到端回归：概览绘图示例仍正常出图 → `%TEMP%/maven_rename_regress/MAVEN_overview_20150719_0200-0400.png`。

## [2026-10-12] 模块装载管理器（阶段 A）：load_module / @load + 白名单 + 载体机制

### 新增

- **`src/modules.jl`**
  - `ModuleSpec` 与注册表 `MODULE_REGISTRY`（18 条）：constants、MarsCommon、Paths、MAVEN_load、MAVEN_STATIC、MAVEN_SWIA、MAVEN_SWEA、MAVEN_plot、IGRF_calculate、Cold_Plasma_Dispersion_Relation、Maxwellian_Distribution、Single_Particle_Orbit、calculate_models、MGS_load、TW_load、TW_MINPA、SP_load、Call_fortran_dll；每条含 `deps`（语义前置）与 `allow` 白名单（**全部刻意留空**）。
  - `load_module(name; into=MarsData, force=false, verbose=false)`：等价于 `include(对应文件)`；`name=:all` 按依赖拓扑序装载；同进程幂等。
  - `@load Name1 Name2 …`：在调用者作用域装载并绑定（展开为 `const`，仅限顶层）。
  - 查询与自检：`available_modules` / `loaded_modules` / `module_path` / `module_info` / `validate_registry`。
  - `ModuleLoadError`：包装装载失败并保留原始异常为 `cause`。
- **`test/runtests.jl`**：Julia 测试 67 项。

### 设计要点（均已实测）

- **白名单是唯一闸门**：`@load` 一律使用逐名引入 `using .模块: 白名单…`，**从不**整体 `using`。实测确认 Julia 的逐名引入对**未 export** 的名字同样有效（未 export 可裸名 / 已 export 但不在白名单则不可裸名），因此「能否裸名调用」完全由注册表 `allow` 决定。当前 18 条 `allow` 留空 ⇒ 只绑定模块名、零裸名。
- **载体机制**：实测发现 Julia 对**包模块**内的 `using` 做严格依赖校验——把 `MAVEN_load.jl` 直接 include 进 `MarsData` 会因 `using CommonDataFormat` 等不在本包 `[deps]` 而失败（`Package MarsData does not have CommonDataFormat in its dependencies`）；而运行时 `Module(:X)` 载体没有 pkgid，其 `using` 走 `LOAD_PATH` 回退（与 `Main` 一致）。故模块在载体中求值后，再以 `const` 别名绑定进 `MarsData`，**无需**新增 CommonDataFormat/JLD2/FortranFiles/Rotations/CSV/DifferentialEquations/LsqFit 等 8 个重依赖。
- 副作用：`parentmodule(MarsData.MAVEN_load)` 是载体而非 `MarsData`；全进程共享同一模块实例（不重复编译）。

### 修改

- **`Project.toml`**：新增 `[extras] Test` 与 `[targets] test`。
- **`README.md` / `README_EN.md`**：新增「模块装载 / Module Loading」章节；并**修正上一轮的错误说法**——`using MarsData` 并不会把绘图基元（`time2x`、`sta_heatmap` 等）变成裸名，只有 `plot_module`/`TimeFormat`/`remove_0_point!` 被导出。
- **`docs/src/api.md`**：新增「MarsData 包 API」章节（轻量 API / 绘图 API / 模块装载管理器，含白名单与载体机制说明）。

### 本次未做（按约定归阶段 B/C）

- 未改动任何模块的 `export` 行，未改示例、`MAVEN_data/Build_data/`、`download_data/`。

### 验证

- `julia --project=. test/runtests.jl` → **67/67 通过**（覆盖：注册表自检、查询、未知模块报错与相近建议、幂等、`:preloaded`、空白名单零裸名、非空白名单可裸名、`into` 隔离、`@load` 顶层绑定、`:all` 拓扑序、MAVEN_load 重模块冒烟）。
- 端到端回归：`example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl`（仍走 include 路径）正常出图。
- `julia --project=docs docs/make.jl` 文档重建成功。

## [2026-10-12] 绘图功能包化：MarsData 提供 plot_module 与绘图基元

### 新增

- **`src/plotting.jl`**：概览绘图合成（`TimeFormat` / `remove_0_point!` / `plot_module`），由 `example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl` 迁入包内、在 `module MarsData` 中 include，通过 `using MarsData` 直接调用。
- **`Project.toml`** 新增绘图依赖（UUID 由 `Pkg.add` 写入）：CairoMakie、Makie、ColorTypes、DataFrames、DataInterpolations、DelaunayTriangulation、LaTeXStrings、ProgressMeter、StaticArrays、TimesDates、LinearAlgebra、Statistics。

### 修改

- **`src/MarsData.jl`**：在轻量公共 API（路径 / 注册表 / 索引）之上 include `MAVEN_data/MAVEN_plot.jl`（作为子模块 `MarsData.MAVEN_plot`）与 `src/plotting.jl`，并以 `using .MAVEN_plot` 使绘图基元随 `using MarsData` 可用。
- **`example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl`**：659 → 196 行。删除本地 `TimeFormat` / `remove_0_point!` / `plot_module` 定义与 `MAVEN_plot.jl` 直接 include，改为 `using MarsData`；仅保留数据准备（`mag2sphere` / `get_data` / `get_B_model_ss`）。
- **`example/MAVEN_plot_sample/MAVEN_overview_cases.jl`**：670 → 209 行，同样改造。
- **`README.md` / `README_EN.md`**：新增「绘图 / Plotting」章节与目录项；项目结构表更新 `src/` 说明。
- **`docs/src/index.md`、`pipeline.md`、`api.md`**：补充包化绘图用法、快速开始绘图步骤与函数索引说明。

### 验证

- `using MarsData` 加载成功；`MarsData.plot_module`、`MarsData.TimeFormat`、子模块 `MarsData.MAVEN_plot` 与导出基元 `time2x` 均可用；`MarsData.TimeFormat(2015-07-19 02:00, 04:00)` → `02:00:00.000`。
- 单日概览示例（2015-07-19 02:00-04:00）运行成功 → `%TEMP%/maven_plot_pkg/MAVEN_overview_20150719_0200-0400.png`（5.36 MB）。
- 批量示例（2015-07-19 全天 12 个 2 小时窗口）运行成功 → `%TEMP%/maven_plot_pkg_batch/2015/07/*.png`（含目标窗口 `2015-07-19_02.png`）。
- `julia --project=docs docs/make.jl` 文档重建成功。

### 说明

- `using MarsData` 现在会加载 CairoMakie/Makie，首次加载较慢（预编译后约数十秒）；`Figure` / `save` 等仍由 `using CairoMakie` 提供（MarsData 不重新导出 Makie）。

## [2026-10-12] example 概览/批量绘图适配 + MAVEN_plot 加载阻塞修复

### 修复

- **`MAVEN_data/MAVEN_plot.jl`**：修复 `logticks` docstring 中未转义的 `$(round(x))`——它在模块加载时被当作字符串插值求值，抛出 `UndefVarError: x not defined`，**阻塞 `MAVEN_plot.jl`（及所有引用它的示例）加载**；转义为 `\$(round(x))`。

### 修改（示例适配当前程序）

`example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl` 与 `MAVEN_overview_cases.jl`：

- KP 产品由已不存在的 `KP_l3` 改为注册表产品 **`KP`**（`load_kp(...; pc2ss_Matrix_load=true)` + `change_kp_read_data` 扩展绘图所需变量）；
- `MAG_pc1s_l3` → 注册表产品 **`MAG_pc1s_cdf`**；
- 新增 `load_model_safe` **逐产品容错**（个别产品缺文件或格式异常不再中断整幅图）；
- 新 MAG CDF 产品无 `:B_total`，改由 `:B` 三分量计算总场；
- `:Ne` 由矩阵索引 `[i,1]` 改为向量索引 `[i]`（`load_kp` 返回向量）；
- 时间轴轨道定位改用二分 **`MarsCommon.searchsortednearest`**（时序数据约定）；
- 绘图参数（日期 / 时间范围 / 输出目录）参数化，输出改为可配置目录并**保存 PNG**；批量脚本支持环境变量 `MAVEN_OVERVIEW_OUTDIR`，并修复 `parent_dir * filename` 字符串拼接为 `joinpath`。

### 验证

- **单日概览**：2015-07-19 02:00-04:00 → `%TEMP%/maven_overview_sample/MAVEN_overview_20150719_0200-0400.png`（4.75 MB，5000×5000），轨道三视图 + (a)-(k) 全仪器面板正常。
- **批量**：2015-07-19 全天 12 个 2 小时窗口 → `%TEMP%/maven_overview_batch/2015/07/*.png`（含目标窗口 `2015-07-19_02.png`）；首图 36 s（含编译），之后每图约 4 s。
- **已知限制**：`STATIC_d1_v4d`（`mvn_sta_l3_d1_v4d_*.f77_unformatted`）当前 `load_d1_v4d` 读取报 `FortranFilesError`（`_cold_` 与非 cold 两变体均失败），(b) 面板因此缺 STATIC 离子密度；已由逐产品容错跳过，不影响其余面板。

### 环境

- 为运行示例，向 Julia `@v1.10` 环境补装 **`StaticArrays`**（`common/MarsCommon.jl` 依赖，此前缺失导致 `using StaticArrays` 失败）。

## [2026-10-12] 文档化：执行流程整理 + README 更新 + Documenter Wiki

### 新增

- **`docs/`（Julia Documenter 文档工程）**：
  - `docs/Project.toml` / `docs/Manifest.toml`：Documenter v1.19 独立文档环境。
  - `docs/make.jl`：构建脚本（`julia --project=docs docs/make.jl`，产物 `docs/build/`）。
  - `docs/src/index.md`：文档首页与快速开始。
  - `docs/src/pipeline.md`：**项目执行流程**整理（环境准备 → 配置 → 下载 → 扫描索引 → 检查维护 → 派生构建 → 读取计算 → 测试文档），含可复制命令与产物位置。
  - `docs/src/data_reading.md`、`data_format.md`、`swia_electron.md`、`api.md`：由原 `doc/wiki/*.md` 迁入并适配（源码链接改为仓库绝对链接，页面互链改为新文件名）。
- **`.gitignore`**：新增 `docs/build/`（构建产物不入库）。

### 修改

- **`README.md`**：项目结构表更新（config/、martian_pipeline/、tools/、tests/、src/、docs/、pyproject.toml）；新增「项目执行流程」与「文档构建」小节；下载节改用 `pyproject.toml` 依赖与 `martian_pipeline` CLI；读取节新增 `MarsData` 轻量公共 API 与时间轴 `searchsortednearest` 约定；Wiki 链接指向 `docs/src/`。
- **`README_EN.md`**：与中文 README 同步（结构表、执行流程、Configuration/Requirements、Reading Data、Program and Function Index、Documentation Build）。

### 验证

- `julia --project=docs docs/make.jl` 构建成功，产出 6 个 HTML 页面（index / pipeline / data_reading / data_format / swia_electron / api）+ 搜索索引。
- 文档内源码链接改写为仓库绝对链接（api.md 41 处、data_reading.md 1 处），无残留 `../../` 相对链接。
- 遗留：Documenter 对数学公式中的 `$` 给出「Julia 插值」警告（误报，`warnonly=true`，MathJax 正常渲染）。

## [2026-10-12] 时间轴最近邻查找二分化：findmin → searchsortednearest

### 改动

- **`find_time` 更名为 `searchsortednearest`**，`find_time_range` 更名为 `searchsortednearest_range`，并**迁入共享模块 `common/MarsCommon.jl`**（各 loader 均 include 的公共模块），使其可被 MAVEN_load/MAVEN_SWIA 等模块调用。
- **`searchsortednearest` 的 docstring 明确强调**：本函数**只能用于已排序的时序数据查找**；在空间数据处理中，所有被读取的数据除非特别说明，其时间轴都是排序后的时序数据，时间轴最近邻查找一律用本函数（二分，`O(log N)`），严禁用于未排序数组、能量轴、色标 levels 等非时序数据。
- **`common/head.jl`**：删除旧 `find_time`/`find_time_range` 定义，改为 `const searchsortednearest = MAVEN_load.MarsCommon.searchsortednearest`（透传供脚本层调用）。
- **替换 6 处时间轴 `findmin(abs.(x .- x0))` 线性扫描为 `searchsortednearest` 二分**：
  - `MAVEN_data/MAVEN_SWIA.jl`（2 处，姿态四元数时间匹配）
  - `MAVEN_data/MAVEN_load.jl`（1 处，MAG/SWEA 时间对齐）
  - `example/MAVEN_plot_sample/MAVEN_overview_cases.jl`（2 处）
  - `example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl`（1 处）
- **`models/Pickup_ion.jl`**：`find_time`/`find_time_range` 调用点更新为新名。
- **保留未替换**：`MAVEN_load.jl` 的能量轴 `findmin(energy_arr)`、`MAVEN_plot.jl` 的色标 `findmin(levels)` 属非时序数据，按约定不替换。

### 验证

- 7 个改动 .jl 文件全部通过 `Meta.parseall` 语法检查。
- 算法正确性：对排序 DateTime 轴（5000 次）与 Float64 轴（10000 次）随机验证，`searchsortednearest` 返回的索引其 `abs(x[idx]-x0)` 恒等于 `minimum(abs.(x .- x0))`（距离最小）；边界与区间用例通过。
- 微基准（N=1e6）：`searchsortednearest` 二分约 `87.3 ns/查询`，相对 `findmin` 线性 `2.4 ms/查询` 约 **27570× 加速**、分配减少约 500000×。
- 注：`searchsortednearest` 在 `x0` 恰处于两元素正中时返回**较大**下标（与原 `find_time` 一致），与 `findmin` 返回较小下标的 tie-breaking 不同；对最近邻时间匹配无影响。

## [2026-10-12] 补完未完成项（Pkg 验证 + 维护脚本 + CLI 子命令）

### 验证（此前被沙箱阻断，现已通过）

- **git push**: 全部提交已推送至 `ustc/main`（`a09511a..ba32ac2`）。
- **Julia `Pkg.instantiate`**: 修正 `Project.toml` 中 TOML stdlib UUID（`fa267bd1...` → `fa267f1f-6049-4f14-aa54-33bafae1ed76`），生成 `Manifest.toml`，`MarsData` 预编译成功，`using MarsData` 验证通过。

### 修改

- **`download_data/compress_cdf.py`**: 修复 `raise e` 之后的不可达清理（先清理临时文件再抛出，避免留下半成品）。
- **`download_data/clean_files.py`**: `clean_pydownload_files` 增加 `dry_run=True` 默认，`__main__` 改 argparse `--apply`（删除类操作安全化）。
- **`example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl`**: 修复 `!isfile` JLD2 缓存判断反转（改为 `isfile`）。
- **`.gitignore`**: `.DS_store` 修正为 `.DS_Store`。
- **`martian_pipeline/cli.py` + `check.py`**: 新增 `check`（默认 report 只报告）与 `clean`（默认 dry-run）子命令。

### 验证

- `python -m martian_pipeline --help` 列出 scan/manifest/migrate/check/clean。
- `check` 端到端报告损坏 CDF 而不删除；`clean` dry-run 不删除。
- 全仓 Python AST: 40/40 OK。

### 仍未完成（受依赖限制，列出供后续）

- 索引嵌套 `products` 契约（当前为扁平 + 元数据，人工批注视 `product_path/pattern` 为可选）。
- Julia `:time` 统一键 + MGS/TW shim（需可分发样本数据做 loader 输出比对）。
- 完整 `Project.toml`（需装齐 `LsqFit` 等全部直接依赖后取代 `requirement.jl`）。
- `download_files.py` NAIF 下载器 `Server_ind=1` 残留、`KP_vars.json` 移除、`eval(Meta.parse)` 显式注册、中文文件名 ASCII 化。

## [2026-10-12] martian_pipeline 包化

### 新增

- **`martian_pipeline/` 包**：对既有函数化模块（`config/`、`download_data/`）的薄封装/再导出，提供统一公共 API（`load_config/scan/write_index/load_index/resolve_output_product/project_root/...`）。
  - `__init__.py`: 公共 API 再导出。
  - `inventory.py`: 薄封装 `download_data/check_exist_files.py`。
  - `manifest.py`: 薄封装 `download_data/get_download_files.py`。
  - `cli.py` + `__main__.py`: 统一 CLI，子命令 `scan` / `manifest` / `migrate`，支持 `python -m martian_pipeline <子命令>`。
- **`download_data/__init__.py` / `tools/__init__.py`**: 使二者成为可被 `download_data.<模块>` / `tools.<模块>` 导入的包（不影响各脚本 `python xxx.py` 独立运行）。
- **`tests/test_package.py`**: 3 个用例覆盖公共 API 导入、CLI scan 端到端、CLI migrate dry-run。

### 说明

- 采用**加式薄封装**（不搬目录、不破坏既有脚本）；旧入口 `python download_data/xxx.py`、`python tools/xxx.py` 保持可用。
- 子命令 `check` / `download` / `build` / `clean` / `compress` / `dedupe` 可后续按同一薄封装模式接入（`check` 需先解决 `check_download_file.py` 的扁平 import 依赖）。

### 验证

- `python -m martian_pipeline --help` 正常；`scan` 端到端产出 schema_version=2 的索引。
- 全仓 Python AST: 39/39 OK（Flash 交叉校验 + 独立复核一致）。
- 回归: P0 6/6、P1 6/6、P2 utils 2/2、P2 cli 5/5、P3 6/6、package 3/3 全通过。

### 多模型协同

- Architect (DeepSeek V4 Pro): 定义加式封装方案并落地（Qwen 子代理连续 null 未落盘，Code 由架构师直接完成）。
- Debug (DeepSeek Flash): 全仓 AST 交叉校验。

## [2026-10-12] P5: 目录整理与优化（仓库卫生）

### 新增

- **`pyproject.toml`**: Python 依赖清单（`requires-python >= 3.11`），运行依赖（requests/beautifulsoup4/tqdm/numpy/pandas/cdflib）与可选依赖（build: spacepy、notebook: jupyter/ipykernel/matplotlib）分离；移除无条件 pywin32 与 Jupyter 全家桶传递依赖（对应报告 5.2-⑦）。
- **`.gitattributes`**: 统一 `text=auto` 换行符规范，二进制文件（jld2/dll/图片/PDF）不参与转换（对应报告风险 #8）。

### 修改

- **`README.md`**: 新增「配置迁移（INI → TOML）」小节，文档化 `tools/migrate_config.py` 的 dry-run/--apply/--force 用法（对应报告 5.2-④）；新增「环境要求」小节，注明 Python ≥ 3.11、Julia ≥ 1.10、派生 CDF 构建需 NASA CDF 库、磁场模型需 C++/Fortran DLL。

### 说明

- 本阶段未做源文件目录搬迁与中文文件名 ASCII 化——报告明确将其列为「低优先级独立清理」且需在前述兼容测试稳定后执行；`requirements.txt`（120 包 pip freeze）暂保留作为环境快照，现已由 `pyproject.toml` 取代为权威依赖清单。

### 验证

- `pyproject.toml` 经 `tomllib` 解析通过。
- 全仓 Python AST: 31/31 OK。

### 多模型协同

- Architect (DeepSeek V4 Pro): 界定 P5 低风险范围并直接落地元数据/文档。
- Debug (DeepSeek Flash): 校验。

## [2026-10-12] P4: Julia 包化与 loader 兼容

### 新增

- **`Project.toml`**: 正式 Julia package 清单（name=MarsData, uuid, deps: Dates/IniFile/JSON/TOML, compat julia=1.10）。
- **`src/MarsData.jl`**: 轻量公共 API 入口，仅暴露路径解析（`project_root/maven_data_root/tw_data_root/mgs_data_root/index_path`）、产品注册表（`load_registry/data_model`）与索引读取（`load_index`），不加载任何科学数据 loader，因此可在无本地数据、无 Fortran DLL 的环境加载。

### 修改

- **`common/head.jl`**: 硬编码 `Package_path = "D:/CODE/Package_for_Julia/"` 改为 `normpath(joinpath(@__DIR__, "..")) * "/"`（由文件位置推导包根，去除绝对路径硬编码，对应报告发现 #5）。

### 验证

- `src/MarsData.jl` 冒烟通过（include 加载 + 路径/注册表/索引解析全部正确，`MARS_DATA_SMOKE_OK`）。
- `common/head.jl` 经 `Meta.parseall` 语法解析通过。
- 保留现有 `include` 入口：`MAVEN_load.jl` 等仍按原 include 方式加载，行为不变。

### 说明（受环境限制未验证部分）

- `Pkg.instantiate` 无法在本沙箱运行（Julia Pkg 的子进程管道被沙箱命名管道限制阻断，与 git push 同因）；`Project.toml` 的依赖 UUID 已按本机已装包逐一核实，需在沙箱外运行 `Pkg.instantiate` 确认。
- `:time` 统一键规范化（报告 5.2-⑤）与 loader 输出逐键比对，需可再分发样本数据，留待后续；本阶段不强制。

### 多模型协同

- Architect (DeepSeek V4 Pro): 拆分增量、核实依赖 UUID。
- Code (Qwen 3.8 MAX): 编写 Project.toml、src/MarsData.jl、head.jl 修复。
- Debug (DeepSeek Flash): 辅助校验。

## [2026-10-12] P3: 派生产品和索引治理

### 新增

- **索引 v2**（`download_data/get_download_files.py`）：`write_index` 写入 `schema_version=2` + `generated_at` 顶层元数据（扁平 + 元数据，向后兼容旧加载器）；新增 `load_index()` 读适配器，同时兼容 v2 与旧版扁平格式。
- **`config/paths.py` 新增 `resolve_output_product(source_model, data_model)`**：按 `source_model + "_cdf"` 派生约定解析派生产品的注册信息，返回 `(output_product_id, output_product_dir, output_regex)`。
- **`tests/test_p3.py`**：6 个用例覆盖索引 v2 写入/读取/旧版兼容、MAG/KP 派生解析、未知模型 KeyError。

### 修改

- **`MAVEN_data/Build_data/磁场重构为CDF文件.py`**：`__main__` 中 `mode_save_dir[:-2]+"3"` 字符串手术改为注册表查找 `download_model(key + "_cdf")`；`os.rename` → `os.replace`（原子替换，不覆盖已有有效输出）。
- **`MAVEN_data/Build_data/KP重构为cdf.py`**：`os.rename` → `os.replace`（原子替换）。

### 验证

- 全仓 Python AST: 31/31 OK（Flash 交叉校验 + 独立复核一致）。
- 回归: P0 6/6、P1 6/6、P2 utils 2/2、P2 cli 5/5、P3 6/6 全通过。
- 派生输出路径经注册表解析、输出文件名可被对应产品正则发现（测试断言）。

### 说明

- 构建器依赖 `spacepy.pycdf`（NASA CDF 库），本机无法端到端运行 CDF 转换；本次仅改动纯路径/原子写逻辑并做 AST 级验证，运行时验证需在具备 spacepy + CDF 库的环境进行。

### 多模型协同

- Architect (DeepSeek V4 Pro): 拆分增量、细化规格。
- Code (Qwen 3.8 MAX): 逐增量实现。
- Debug (DeepSeek Flash): 全仓 AST 交叉校验。

## [2026-10-12] P2: Python 可组合入口

### 新增

- **`config/utils.py`**: 共享纯函数模块，收敛 `get_list_from_ini` 与 `read_last_line_large_file` 的权威实现。
- **`tools/scan_and_index.py`**: 独立 CLI（scan → manifest），无 `runpy`/`exit()` 进程副作用，`--models` 忽略未知产品。
- **`tests/test_p2_utils.py`**: 覆盖 `get_list_from_ini`/`read_last_line_large_file` 边界（空串、无换行、空文件等）。
- **`tests/test_p2_cli.py`**: 覆盖空目录、未知模型、正则无匹配、路径分隔符、最小模型扫描+索引、CLI 端到端。

### 修改

- **`download_data/get_download_files.py`**: `write_index` 改为原子写（同目录临时文件 + `os.replace`），避免半写索引。
- **`download_data/check_download_file.py`**: 本地 `read_last_line_large_file` 改为从 `config.utils` 导入。
- **`download_data/MAVEN_download.py` / `download_files.py`**: 本地 `get_list_from_ini` 改为从 `config.utils` 导入；`exit(0)` 改为 `sys.exit(1)`（修正"失败却返回成功码"）。
- **`download_data/clean_files.py`**: 删除死代码 `get_list_from_ini`。
- **`download_data/移除重复文件中的低版本文件.py`**: 删除死代码 `get_list_from_ini`；`__main__` 修复 dry-run 默认被旁路的问题（默认 dry-run，`--apply` 才物理删除）。

### 验证

- 全仓 Python AST: 31/31 OK（Flash 交叉校验 + 独立复核一致）。
- 回归: P0 6/6、P1 6/6、P2 utils 2/2、P2 cli 5/5 全通过。
- 无 `runpy` 调用、无 `exit(0)`（剩余 `sys.exit(1)` 均为 `__main__` 错误退出/test runner 合法用法）。

### 多模型协同

- Architect (DeepSeek V4 Pro): 拆分增量、细化规格。
- Code (Qwen 3.8 MAX): 逐增量实现。
- Debug (DeepSeek Flash): 全仓 AST 交叉校验。

## [2026-10-12] P1: 配置与路径单点化

### 新增

- **`config/settings.example.toml`**: TOML 配置模板（唯一写端格式），含 MAVEN/TW/MGS 根 + server/download/window。
- **`config/config.py`**: `load_config()` — TOML 优先 → 旧 INI 只读回退 → DEFAULTS，dataclass 强类型返回。
- **`config/paths.py`**: 路径解析单一出处 — `project_root/index_path/lists_dir/data_root/product_dir`，全部脚本位置推导、CWD 无关。
- **`tools/migrate_config.py`**: INI→TOML 一次性迁移命令（dry-run 默认、`--apply`/`--force`、幂等、不搬数据）。
- **`common/paths.jl`**: Julia 侧 `Paths` 模块（TOML 优先 + INI 回退），暴露三任务根路径与 `index_path`。
- **`tests/test_p1.py`**: 6 个用例覆盖 TOML 读取、INI 兼容映射、迁移 dry-run/幂等、路径 CWD 无关、product_dir。

### 修改

- **`MAVEN_data/MAVEN_load.jl`**: `root_path` 改经 `Paths.maven_data_root()`（行为不变）。
- **`.gitignore`**: 追加 `config/settings.toml`（本地配置不入库）。

### 验证

- Python AST: 27/27 OK（Flash 校验 + 独立复核一致）。
- 测试: P0 6/6 + P1 6/6 PASS。
- Julia paths.jl 冒烟: TOML 分支与 INI 回退均正确。
- 迁移 dry-run 对用户真实 INI 正确识别 `Server_ind=3`、4 URL、`Aria2c` 模式。

### 多模型协同

- Architect (Qwen 3.8 MAX): 定义契约与规格。
- Code (Qwen 3.8 MAX): 编写 Python config 层 + Julia paths.jl。
- Debug (DeepSeek Flash via USTC): 全仓 AST 校验。

## [2026-10-12] P0: 阻断级问题修复与行为对齐

### 修复

- **`download_data/MAVEN_download.py`**: 删除缩进错误的死函数 `file_check`/`read_last_line_large_file`（修复 AST 失败）；末尾 `runpy.run_path` 改为显式 `check_exist_files.main()`；`check_download_file` 读取加 `fallback=False`（旧 INI 不再 NoOptionError）。
- **`download_data/initialize_download_parameters.py`**: 重构为可测试的 `build_config()`/`generate_config(output_path)`；补齐 `check_download_file` 键；修复 `download_mode` 值中缺失 `;` 前缀导致的 ParsingError；Windows 路径改 raw string 消除 SyntaxWarning。
- **`download_data/check_exist_files.py`**: 扫描逻辑收敛为可导入函数（`load_config/load_schema/download_model/search_downloaded_files/scan/main`）；去除重复 schema 加载、`runpy`、`exit(0)`；`save_dir + pathname` 改为 `os.path.join`。
- **`download_data/get_download_files.py`**: 索引写入收敛为 `write_index(save_dir, output_path=None)`；输出路径改为脚本位置推导（`default_index_path()`）；`Path.touch` 报错改为 `os.makedirs`。

### 新增

- **`download_data/check_download_file.py`**: 独立文件完整性检查入口（决策 D1），默认 `--action report` 只报告 CDF/KP 校验结果，`isolate`/`delete` 必须显式启用。
- **`tests/test_p0.py`**: 6 个用例覆盖配置初始化、文件扫描、索引生成、下载后刷新、完整性检查报告/隔离/删除。

### 验证

- 全仓 Python AST: 22/22 OK（修复前 1 FAIL）。
- 测试: 6/6 PASS。
- 下载器对现有用户 INI 导入成功（`Server_ind=3`, `check_download_file` fallback 生效）。

本项目所有值得注意的变更都会记录在此文件。

## [2026-10-12] 函数一致性审查与 IGRF 回归修复

对重构提交 `a42e14b` 完成全量函数级一致性审查，并修复审查中发现的 1 处回归缺陷。

### 修复

- **`Magnetic_Model/IGRF_calculate.jl`：修复 `IGRF()`（纯 Julia 参考实现）的累加器清零回归。**
  - 现象：重构时在 `for N = 1:NIGRF` 循环内误加的三行 `BR/BT/BP = 0.0e0` 会在每轮迭代
    清零跨阶累加器，结果只保留最高阶（N = 110）贡献；表面测试点 `IGRF(3393.5, 1.0, 0.5)`
    的 `BB` 由正确的 `373.56 nT` 变为错误的 `97.53 nT`。
  - 修复：删除循环内三行初始化，保留循环外初始化并补充防回归注释；修复后输出与 `af1362e`
    基准逐位一致。
  - 范围说明：`IGRF_pc` / `trace_mag_line` 等生产路径使用 Fortran DLL 内核，不受影响。

### 文档

- 新增 `doc/refactoring_audit_a42e14b.md`：函数级一致性审查报告，包含 AST 校验方法、
  逐函数核对表、新旧数值差异量化表（常量精度统一、四元数迁移、函数合并）及本次修复记录。

### 验证

- **本次修改经过 AST 校验**：以 Julia 解析器剥离注释/docstring 后，对 `af1362e..a42e14b`
  的全部 Julia 文件逐函数比对新旧 AST（75 个函数发生语义变化、43 个删除、15 个新增、
  122 个仅注释/docstring 不变），并以裸引用静态检查确认无“删除常量后漏改引用”；
  修复后再次 AST 比对确认 `IGRF()` 与旧版仅剩常量限定名差异（`Rm → constants.R_Mars`，
  两者数值均为 3393.5）。
- 动态回归：修复后 `IGRF()` 4 组测试点的 `(BR, BT, BP, BB)` 与 `af1362e` 基准 16 位
  有效数字逐位一致；`pc2sphere`/`sphere2pc`、`Bpc2sphere`/`Bsphere2pc` 往返误差 < 1e-15；
  Rotations 迁移以 100 组随机单位四元数验证与旧 Quaternions 实现等价（atol = 1e-12）。

### 兼容性

- 无接口变化；`IGRF()` 修复后恢复与旧版一致的数值行为。
- 审查报告同时记录了 2 处需知悉的数值不兼容项：`Cold_Plasma_Dispersion_Relation.alfven_weve`
  的 `μ_0` 数量级纠错（`4π×10⁷ → 4π×10⁻⁷`），以及旧 `e = 1.6e-19` 口径统一为
  `1.602176634e-19` 带来的 0.136% 变化；两者方向均为“更接近标准值”，代码保持现状，
  外部使用者如有依赖请参阅报告第 3.2/3.3 节。

## [2026-10-12]

本次提交对 Julia 处理部分做了一次结构性整理：集中公共常量与公共函数、迁移静态数组与
旋转库依赖，并为全仓 Julia 函数补齐/规范化了文档注释。

### 重构

- **公共常量集中化**：新增 `common/constants.jl`，把原先散落在各模块中各自定义的物理
  常量（`e`、`me`、`mp`、`μ0`、`eV`、`c`、`RAD`/`RADG`/`inv_RADG`、`R_Mars`、`M_Mars`、
  `G`、`k_B` 等）统一收敛到单一来源，并补充 `me_eV_per_km_s2`、`mp_eV_per_km_s2`、
  `mp_g`、`erg_per_eV`、`M_to_Q_e`、`M_to_Q_p` 等派生常量。
  - 删除重复定义的 `models/constants.jl`。
  - 清理 `models/`、`common/`、`MAVEN_data/`、`Magnetic_Model/`、`TW_data/`、`MGS_data/`
    等文件内部的重复常量（`Me`/`Mp`/`EV`/`C`/`Q` 等），统一改为引用 `constants.*`。
  - 常量取值以 CODATA 定义为准做了精度统一（如 `e: 1.6e-19 → 1.602176634e-19`、
    `me: 9.109e-31 → 9.1093837e-31`、`mp: 1.672621637e-27 → 1.67262192e-27`），
    **对依赖这些常量的数值结果会有极小量级的变化**。

- **公共函数下沉到 `common/`**：新增 `common/MarsCommon.jl`，将原先在多个模块中重复实现
  的坐标系变换与能量/通量换算函数统一为单一实现并导出，包括
  `instrument_sphere_to_cartesian`、`instrument_cartesian_to_sphere`、`spherical_to_cartesian`、
  `rotate_vector`、`position_altitude`、`position_local_time`、`position_latitude`、
  `ion_energy_to_speed`、`ion_speed_to_energy`、`electron_energy_to_speed`、
  `electron_eflux_to_psd`、`ion_eflux_to_psd`、`ion_eflux_to_psd_approx`、`eflux_to_df!`、
  `doppler_shift` 等。
  - 同步删除各文件中的重复副本（`sphere2xyz_for_SWIA/STATIC`、`xyz2sphere_for_SWIA/STATIC`、
    `rotate_vector_with_Matrix/Martrix`、重复的 `ion_energy2v`/`ion_v2energy`/`energy2v`/
    `eflux2df!` 等）。
  - `common/function_coordinate.jl`、`common/head.jl` 整理为集中式工具模块，去除与
    `common/` 的重复实现。

### 性能与依赖

- **StaticArrays 迁移**：核心数值路径改用 `SVector` / `SMatrix` / `NTuple`（涉及
  `common/`、`models/`、`MAVEN_data/`），减少主循环中的堆分配。
  - `Magnetic_Model/IGRF_calculate.jl` 的 `read_gh` 改为返回**元组**，并把读取到的系数
    矩阵声明为 `const` 以提升 `ccall` 访问性能。
- **旋转库现代化**：以 `Rotations.jl`（`QuatRotation`、`RotMatrix`）全面替代已弃用的
  `Quaternions`；`requirement.jl` 中移除 `Quaternions` 依赖。

### 文档

- **函数 Docstring 批量规范化**：为全仓约 470 个 Julia 函数补齐或重写为「工业级 API
  Reference」风格注释，统一采用如下结构：
  `签名 → 一句话核心概述 → # 功能与算法概述 → # 参数说明 → # 返回值 → # 注意事项`。
  - 迁移过程中移除了旧的「逐步翻译代码逻辑」式说明，改为聚焦接口契约与算法要点。
  - 覆盖 `common/`、`models/`、`MAVEN_data/`、`Magnetic_Model/`、`TW_data/`、`calculate/`、
    `MGS_data/`、`support_data/`、`call_fortran_dll.jl`、`download_data/`、`example/` 等目录。
  - 在注释中标注了若干既有隐患（如 `calculate_mag` 引用未定义全局 `data`、
    `MAVEN_SWEA.n1d` 的 `1.0-31` 疑为 `1e-31` 笔误等），仅作记录，未改动代码逻辑。

### 影响与兼容性

- 本次变更以**结构调整与文档为主**，未改变数值算法流程；但因常量精度统一与重复实现
  合并，个别数值结果可能与旧版本存在极小差异。
- `models/constants.jl` 已被移除，若外部脚本直接 `include` 该文件，请改为
  `include(joinpath(@__DIR__, "..", "common", "constants.jl"))` 并通过 `constants.` 前缀访问。
