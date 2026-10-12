<table>
  <tr>
    <td width="20%" align="center" style="border: none;">
      <img src="logo.jpg" alt="icon" width="120px"/>
    </td>
    <td width="80%" style="border: none; vertical-align: middle;">
      <h2>火星空间数据处理与科学计算工具包</h2>
      <p><b>Mars Space Data Processing & Scientific Computing Toolkit</b></p>
    </td>
  </tr>
</table>

# 破坏性变更（必读）

> ### ⚠️ `data_get_from_date` 已更名为 `load_MAVEN_data`
>
> **`MAVEN_load.data_get_from_date` 已被删除，且不保留别名。**
> 沿用旧名的外部脚本会立即报 `UndefVarError: data_get_from_date not defined`。
> **函数签名、参数与返回值完全不变**，只需全局改名：
>
> | 旧名（已删除） | 新名 |
> | --- | --- |
> | `MAVEN_load.data_get_from_date` | **`MAVEN_load.load_MAVEN_data`** |
> | `MarsCommon.electron_energy_to_speed` | **`MarsCommon.e_energy2v`** |
> | `MarsCommon.ion_energy_to_speed` | **`MarsCommon.ion_energy2v`** |
>
> ```diff
> - Data_Dict = MAVEN_load.data_get_from_date(date; model_index = ["MAG_pc1s", "LPW_wave"])
> + Data_Dict = MAVEN_load.load_MAVEN_data(date; model_index = ["MAG_pc1s", "LPW_wave"])
> ```
>
> 迁移步骤与影响范围见 [更新日志中的破坏性变更条目](CHANGELOG.md)（位于文件顶部）。

> ### ⚠️ `MarsCommon` 逐元素函数改为**纯标量**：数组请在调用处加 `.`
>
> 以下 10 个函数内部不再做广播运算、参数统一 `::Real`，与 `sin`/`log` 等 Julia 官方函数对齐：
>
> `ion_energy2v`、`ion_speed_to_energy`、`e_energy2v`、`electron_eflux_to_psd`、
> `ion_eflux_to_psd`、`ion_eflux_to_psd_approx`、`doppler_shift`、
> `instrument_sphere_to_cartesian`、`instrument_cartesian_to_sphere`、`spherical_to_cartesian`
>
> ```diff
> - v = MarsCommon.ion_energy2v(energy_array, 16)
> + v = MarsCommon.ion_energy2v.(energy_array, 16)      # 加一个点
>
>   v = MarsCommon.ion_energy2v(energy_scalar, 16)      # 标量调用不变
> ```
>
> 传数组不加点会**立即报 `MethodError`**（不再静默返回无意义结果）。数值与改动前逐位一致。
> `position_altitude` / `position_local_time` / `position_latitude` / `rotate_vector` /
> `eflux_to_df!` / `searchsortednearest(_range)` **不受影响**（本就按数组/矩阵设计）。

# 索引

- [破坏性变更（必读）](#破坏性变更必读)
- [索引](#索引)
- [介绍](#介绍)
- [项目结构](#项目结构)
- [项目执行流程](#项目执行流程)
- [下载数据](#下载数据)
- [读取数据](#读取数据)
- [其他模型](#其他模型)
  - [火星磁场模型](#火星磁场模型)
  - [冷等离子体色散关系](#冷等离子体色散关系)
  - [麦克斯韦分布拟合](#麦克斯韦分布拟合)
  - [单粒子轨道追踪](#单粒子轨道追踪)
- [MAVEN数据说明](#maven数据说明)
- [绘图](#绘图)
- [模块装载](#模块装载)
- [程序与函数索引](#程序与函数索引)
- [文档构建](#文档构建)
- [其他](#其他)
  - [闰秒修正](#闰秒修正)
- [ToDo List](#todo-list)

# 介绍

[English](README_EN.md) / 简体中文

本项目提供火星空间科学数据的下载、读取、处理、可视化与物理模型计算工具。主要数据处理和科学计算使用 Julia，数据下载与文件整理主要使用 Python，部分磁场计算通过 Fortran 动态库加速。

## 项目结构

| 目录/文件 | 用途 |
| --- | --- |
| `MAVEN_data/` | MAVEN 数据读取、仪器数据处理、绘图及数据格式定义 |
| `MGS_data/`、`TW_data/` | MGS 与天问一号数据读取和仪器处理 |
| `download_data/` | MAVEN 数据下载、完整性检查、压缩及清理工具 |
| `config/` | 唯一配置层：`settings.example.toml` 模板 + `config.py`/`paths.py`/`utils.py` |
| `martian_pipeline/` | Python 包化入口与统一 CLI（`python -m martian_pipeline`） |
| `tools/` | 配置迁移 `migrate_config.py`、扫描索引 `scan_and_index.py` |
| `tests/` | 临时目录/合成数据的回归测试（P0–P3 + 包化） |
| `models/`、`Magnetic_Model/` | 等离子体、粒子轨道、磁场等模型与计算 |
| `common/`、`support_data/` | 通用坐标/物理计算函数和外部支持数据读取 |
| `calculate/` | 模型计算流程与组合入口 |
| `example/` | 绘图和数据分析示例 |
| `src/`、`Project.toml` | Julia 包 `MarsData`：轻量公共 API + 包化绘图（`plot_module` 等） |
| `pyproject.toml` | Python 运行依赖与可选依赖清单 |
| `docs/` | 唯一文档根目录：[文档源](docs/src/index.md)（Documenter 页面）+ [GitLab Wiki](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/wikis/home)、[参考资料](docs/references)、[历史报告](docs/reports) |

各程序文件职责及函数说明见 [程序与函数索引](docs/src/api.md)。

## 项目执行流程

完整流程见 [项目执行流程](docs/src/pipeline.md)，概览：

```
[0] 环境准备  →  [1] 配置(TOML)  →  [2] 下载  →  [3] 扫描与索引
                                                        │
                          [6] 读取与计算  ←  [5] 派生构建 ─┘
                                                        │
                          [7] 测试与文档  ←  [4] 检查与维护
```

关键命令：

```bash
python tools/migrate_config.py --apply      # 配置：INI → TOML（dry-run 为默认）
python -m martian_pipeline scan             # 扫描本地文件并刷新索引
python -m martian_pipeline check            # 文件完整性检查（默认只报告）
python -m martian_pipeline clean            # 清理未完成下载（默认 dry-run）
julia --project=docs docs/make.jl           # Documenter：构建 HTML 到 docs/build/
python tools/push_wiki.py --dry-run         # GitLab Wiki：预览生成结果
python tools/push_wiki.py --push            # GitLab Wiki：发布
```

# 下载数据

使用 Python 程序下载和整理 MAVEN 数据。建议创建虚拟环境并安装运行依赖（清单见 `pyproject.toml`，运行依赖与可选依赖已分离）：

```
pip install -e .            # 运行依赖：requests / beautifulsoup4 / tqdm / numpy / pandas / cdflib
pip install -e ".[build]"   # 可选：派生 CDF 构建需要 spacepy（依赖 NASA CDF 库）
```

首次下载时,**需要先产生初始化设置文件**:

运行 [download_data/initialize_download_parameters.py](download_data/initialize_download_parameters.py)。

初始化后，根据本机的下载配置调整服务器、保存目录、日期范围和数据产品；下载脚本从 `download_data/MAVEN_download_config.ini` 读取设置。该配置属于本地运行配置，不一定包含在仓库中。

[download_data/MAVEN_download.py](download_data/MAVEN_download.py)负责从配置的服务器下载数据。

下载后可统一用 `martian_pipeline` CLI 或独立脚本维护：

```bash
python -m martian_pipeline scan      # 扫描本地文件并刷新索引（check_exist_files + get_download_files）
python -m martian_pipeline check     # 文件完整性检查（默认只报告；isolate/delete 需显式启用）
python -m martian_pipeline clean     # 清理未完成下载（默认 dry-run）
python download_data/compress_cdf.py                        # 压缩 CDF（就地，原子替换）
python download_data/移除重复文件中的低版本文件.py --apply   # 去重低版本（默认 dry-run）
```

也可继续使用等价独立脚本：`download_data/check_exist_files.py`（扫描）、`download_data/get_download_files.py`（索引）。

可以使用的MAVEN外部服务器(可能需要VPN):

- USTC源,校内速度快,服务器不一定运行,数据不一定完整: http://222.195.76.155:8000/MAVEN/
- UCLA源,服务器稳定,没有NGIMS数据，数据未经压缩，体积过大: https://pds-ppi.igpp.ucla.edu/data/
- LASP源,服务器稳定，数据经过压缩，建议使用此版本: https://lasp.colorado.edu/maven/sdc/public/data/sci/
- berkeley源,格式与LASP类似,SPADES库默认服务器,相当部分的数据需要账户密码,不可直接访问: http://sprg.ssl.berkeley.edu/data/maven/data/sci/

其中'https://pds-ppi.igpp.ucla.edu/data/'的文件树与后两者不同,且没有NGIM数据

每次更新下载数据后，重新运行扫描以刷新索引与文件清单：`python -m martian_pipeline scan`。

## 配置迁移（INI → TOML）

自重构 P1 起，配置的唯一写端为 TOML（`config/settings.toml`），旧 INI（`download_data/MAVEN_download_config.ini`）保留为只读兼容输入。将旧 INI 一次性迁移为 TOML：

```
# dry-run：仅打印将要生成的 TOML，不写文件（默认）
python tools/migrate_config.py

# 实际写入 config/settings.toml
python tools/migrate_config.py --apply

# 覆盖已存在的 settings.toml
python tools/migrate_config.py --apply --force
```

迁移幂等、不搬动任何数据目录、也不改动原 INI；迁移后 Julia/Python 侧会优先读取 TOML。

## 环境要求

- Python ≥ 3.11（配置读取依赖标准库 `tomllib`；依赖清单见 `pyproject.toml`）。
- Julia ≥ 1.10（依赖标准库 `TOML`）。
- Windows 上派生 CDF 构建（`MAVEN_data/Build_data/`）依赖 NASA CDF 库（`spacepy.pycdf`）；磁场模型（`Magnetic_Model/IGRF_calculate.jl`）依赖对应 C++/Fortran DLL。

# 读取数据

## 轻量公共 API（Julia 包 `MarsData`）

`src/MarsData.jl` 提供路径解析、产品注册表与索引读取等公共 API，**不加载任何科学数据 loader**，因此可在无本地数据、无 Fortran DLL 的环境下加载：

```julia
using Pkg; Pkg.instantiate()   # 按 Project.toml + Manifest.toml 安装依赖
using MarsData
MarsData.project_root(); MarsData.maven_data_root(); MarsData.tw_data_root(); MarsData.mgs_data_root()
MarsData.index_path();   MarsData.data_model();      MarsData.load_index()
```

## 完整读取入口

MAVEN 数据的统一读取入口为 `MAVEN_data/MAVEN_load.jl`：

```
Data_Dict = MAVEN_load.load_MAVEN_data(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```

> ⚠️ **该入口此前名为 `data_get_from_date`，现已删除且不留别名。** 旧脚本请全局改名，详见 [破坏性变更（必读）](#破坏性变更必读)。

此程序需要特定的读取文件树格式,
与下载部分共用文件树格式

Julia 中的引用方式:

```Julia
include("path/MAVEN_data/MAVEN_load.jl")
include("path/Magnetic_Model/IGRF_calculate.jl")
import .MAVEN_load
import .IGRF_calculate
```

> 时间轴约定：所有被读取数据的时间轴（除特别说明）均为**排序后的时序数据**；时间轴最近邻查找统一使用 `MarsCommon.searchsortednearest`（二分，`O(log N)`），不要用 `findmin(abs.(x .- x0))`（线性扫描）。能量轴、色标等非时序数据仍用 `findmin`。

具体读取方法: [MAVEN 数据格式](docs/src/data_format.md)

读取介绍：[MAVEN 数据读取](docs/src/data_reading.md)

# 绘图

绘图功能已**包化进 `MarsData`**，无需再手动 `include MAVEN_plot.jl`：

```julia
using MarsData          # 提供 plot_module / TimeFormat / remove_0_point!
using CairoMakie        # Figure / Axis / save 等图形对象

fig = Figure(; size=(2500, 2500))
fig, t0, xtimes = MarsData.plot_module(fig, time_range, data_dict; time_step=Dates.Minute(10))
save("overview.png", fig)
```

- **包内实现**：`src/plotting.jl` 提供概览合成 `plot_module` / `TimeFormat` / `remove_0_point!`，这三个由 `using MarsData` 直接导出；绘图基元位于 `MAVEN_data/MAVEN_plot.jl`，作为子模块载入为 `MarsData.MAVEN_plot`。
- **基元访问方式**：`using MarsData` **不会**把绘图基元变成裸名，需写 `using MarsData.MAVEN_plot`，或调用时带前缀（如 `MarsData.MAVEN_plot.time2x`）。基元清单：`time2x`、`time_ticks`、`x_ticks`、`sta_heatmap`、`STA_2d_slip`、`SWEA_PAD_heatmap`、`WaveSpectra_heatmap`、`Orbit`、`PAD_slice`、`PAD_slice_polar`、`PAD_slice_velocity`。
- **完整示例**：`example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl`（单日概览）、`MAVEN_overview_cases.jl`（批量，按 2 小时窗口切分，输出目录可用环境变量 `MAVEN_OVERVIEW_OUTDIR` 覆盖）。

# 模块装载

重模块（`MAVEN_load`、`MAVEN_STATIC`、`MAVEN_SWIA`、`MAVEN_SWEA`、`IGRF_calculate`、`Cold_Plasma_Dispersion_Relation` 等）**仍以 include 为主**，但已提供包化的装载入口，一次调用等价于 `include(对应文件)`：

```julia
using MarsData

MarsData.load_module(:MAVEN_load)        # ≡ include("MAVEN_data/MAVEN_load.jl")，落点 MarsData
MarsData.MAVEN_load.load_MAVEN_data(date, model_index=["MAG_ss1s_cdf"])

MarsData.@load MAVEN_STATIC IGRF_calculate   # 在调用者作用域装载并绑定模块名
MAVEN_STATIC.static_c6_mass_mean(sta)         # 直接可用

MarsData.available_modules()   # 可装载清单
MarsData.loaded_modules()      # 已装载清单
MarsData.module_info(:MAVEN_load)   # 路径 / 依赖 / 白名单 / 状态
MarsData.validate_registry()        # 注册表自检（路径、module 名、依赖环）
```

- **白名单约定**：`@load` 一律使用逐名引入 `using .模块: 白名单…`，**从不**整体 `using`。因此「能否裸名调用」完全由注册表 `ModuleSpec.allow` 决定，与模块自身 `export` 无关（Julia 的逐名引入对未 export 的名字同样有效）。
- **已开放的白名单**：

  | 模块 | 放行的裸名 |
  | --- | --- |
  | `MarsCommon` | `searchsortednearest`、`e_energy2v`、`ion_energy2v` |
  | `MAVEN_load` | `load_cdf`、`load_MAVEN_data` |
  | `IGRF_calculate` | `IGRF_pc`、`pc2sphere`、`sphere2pc` |

  其余模块留空，`@load` 只绑定模块名。用法：

  ```julia
  MarsData.@load MarsCommon MAVEN_load IGRF_calculate
  searchsortednearest(time_axis, t)                       # 裸名可用
  Data = load_MAVEN_data(date; model_index=["MAG_ss1s_cdf"])
  x, y, z = pc2sphere(r, theta, phi)
  ```
- **依赖自动装载**：`ModuleSpec.deps` 在装载目标模块**之前**递归装入同一载体，以满足相对父模块引用（`common/MarsCommon.jl` 的 `using ..constants` 需要载体里先有 `constants`）。
- **幂等**：同一进程内每个模块只 include 一次，重复调用返回**同一对象**；`:preloaded`（`Paths`、`MAVEN_plot`）直接返回包内实例。
- **载体机制**：模块实际在运行时载体模块（`MarsData._carrier()`）中求值，再以 `const` 别名绑定进 `MarsData`。原因是 Julia 对**包模块**内的 `using` 做严格依赖校验——直接把 `MAVEN_load.jl` include 进 `MarsData` 会因 `using CommonDataFormat` 等不在本包 `[deps]` 中而报 `Package MarsData does not have CommonDataFormat in its dependencies`；运行时载体无 pkgid，其 `using` 走 `LOAD_PATH` 回退（与 `Main` 一致），因此**无需**把 CommonDataFormat/JLD2/FortranFiles/Rotations/CSV/DifferentialEquations/LsqFit 等重依赖声明进本包。副作用：`parentmodule(MarsData.MAVEN_load)` 是载体而非 `MarsData`。

# 其他模型

## 火星磁场模型

./Magnetic_Model/IGRF_calculate.jl
利用 IGRF 模型计算火星模拟磁场, 含有Fortran导出的dll库, 因此需要电脑存在对应的C++和Fortran环境.

模型来源: [A Spherical Harmonic Martian Crustal Magnetic Field Model Combining Data Sets of MAVEN and MGS](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2021EA001860)

## 冷等离子体色散关系

./models/Cold_Plasma_Dispersion_Relation.jl

## 麦克斯韦分布拟合

./models/Maxwellian_distribution.jl

## 单粒子轨道追踪

./models/Single_Particle_Orbit.jl

# MAVEN数据说明

见 [MAVEN 数据读取](docs/src/data_reading.md)，以及 [SWIA 电子修正专题](docs/src/swia_electron.md)。

## 程序与函数索引

按目录查看程序职责、主要入口和函数说明：[程序与函数索引](docs/src/api.md)。

# 文档构建与发布

文档只有一处根目录 `docs/`，`docs/src/*.md` 是唯一权威源：

| 产出 | 命令 | 位置 |
| --- | --- | --- |
| Documenter HTML 站点 | `julia --project=docs docs/make.jl` | `docs/build/index.html`（不入库） |
| GitLab Wiki | `python tools/push_wiki.py --push` | [Wiki 首页](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/wikis/home) |

Documenter 页面：首页、[项目执行流程](docs/src/pipeline.md)、[MAVEN 数据读取](docs/src/data_reading.md)、[MAVEN 数据格式](docs/src/data_format.md)、[SWIA 电子修正](docs/src/swia_electron.md)、[程序与函数索引](docs/src/api.md)。

GitLab Wiki 是一个独立 Git 仓库（`…/Julia_for_MartianSpaceData.wiki.git`）：`tools/push_wiki.py` 从 `docs/src/*.md` 生成页面（跨页链接改写为 Wiki 页面名），首页与侧边栏取自 `docs/wiki/`；`--dry-run` 可先预览。目录分工、页面映射与维护约定见 [docs/README.md](docs/README.md)。

## Wiki 推送步骤

GitLab Wiki **不是可直接编辑的网页，而是一个独立的 Git 仓库**：

```
git@git.ustc.edu.cn:KnightLightning/Julia_for_MartianSpaceData.wiki.git
```

页面正文统一由 `docs/src/*.md` 生成，所以**不要在 Wiki 网页界面直接改内容**（下次发布会覆盖）。完整流程：

```bash
# 0. 先改仓库里的文档源（唯一权威源）
#    docs/src/*.md          —— 页面正文（执行流程 / 数据读取 / 数据格式 / SWIA 修正 / 程序与函数索引）
#    docs/wiki/home.md      —— Wiki 首页
#    docs/wiki/_sidebar.md  —— Wiki 侧边栏

# 1. 预览：生成到临时目录并自检站内链接，不碰远端
python tools/push_wiki.py --dry-run

# 2. 发布：克隆/更新 wiki 仓库 -> 写入页面 -> 提交 -> 推送到 main
python tools/push_wiki.py --push

# 可选参数
python tools/push_wiki.py --push -m "自定义提交信息"      # 自定义提交信息
python tools/push_wiki.py --push --workdir D:/tmp/wiki   # 指定本地克隆目录（默认系统临时目录）
python tools/push_wiki.py --push --prune                 # 顺带删除远端不在生成集中的页面
```

首次发布前需确保本机对该仓库有写权限（SSH key 或访问令牌），克隆地址见上。

推送时的页面映射（源文件 → Wiki 页面名）：

| 文档源 | Wiki 页面 |
| --- | --- |
| `docs/src/pipeline.md` | `项目执行流程` |
| `docs/src/data_reading.md` | `MAVEN数据读取` |
| `docs/src/data_format.md` | `MAVEN_data_format` |
| `docs/src/swia_electron.md` | `swia_electron_correlated` |
| `docs/src/api.md` | `程序与函数Wiki` |
| `docs/wiki/home.md` | `home` |
| `docs/wiki/_sidebar.md` | `_sidebar` |

说明：

- 脚本自动把 `](xxx.md)` 形式的跨页链接改写为 Wiki 页面名（GitLab 相对链接使用页面 slug），并在推送前做站内链接自检；自检失败会中止而不推送。
- 默认远端走 **SSH**（与主仓库 remote 同源，无需交互式凭据）；改用 HTTPS 时加 `--remote https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData.wiki.git`，此时需要 Git Credential Manager 或访问令牌。
- 新增/重命名页面时要同步三处：`docs/src/` 文件名、`docs/make.jl` 的 `pages`、`tools/push_wiki.py` 的 `PAGE_MAP`，以及其它页面里的相对链接。
- 推送后逐页验证：打开 `https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/wikis/<页面名>` 应正常显示。

# 其他

## 闰秒修正

  MAVEN的CDF文件普遍使用**CDF_TIME_TT2000**, 等价于**J2000**,该时间由**TAI** (国际原子时 - International Atomic Time)得到.

$$
$$\text{TT} = \text{TAI} + 32.184 \text{ s}
$$

  与此同时, 由于地球自转的不均匀性, **UTC** (协调世界时 - Coordinated Universal Time) 会在**TAI**的基础上, 定期加入闰秒修正来匹配地球的自然自转, 根据闰秒表, 可以得到每段时间的闰秒差异.

$$
$$\text{TAI} = \text{UTC} + (\text{累积闰秒数})
$$

  由此, 当我们将MAVEN中的J2000时间戳与**UTC**相匹配时, 需要考虑闰秒问题:

$$
$$\text{TT} = \text{UTC} + (\text{累积闰秒数}) + 32.184 \text{ s}
$$

  预计可以使用一个函数来将原始的**CDF_TIME_TT2000**时间戳改为**UTC**时间戳. 只是使用MAVEN数据时不用考虑闰秒问题.

  目前, 程序读取CDF文件epoch使用的cdflib方法,会自动处理闰秒问题. SPEDAS和spacepy同理. IDL中直接使用公式转换**CDF_TIME_TT2000**的方法可能存在闰秒修正的潜在问题.

```julia
  unix2datetime.(cdflib.cdfepoch.unixtime(get(data, "epoch")))
```

  潜在问题: 计算通常以unix时间戳为主, julia是否在处理unix时间戳和UTC时间的关系时考虑闰秒

# ToDo List

- [X] 云 MAVEN 数据
  - [ ] 支持从刘佳佳老师的LINUX服务器上以ssh-scp方式下载数据
- [ ] 利用SPEDAS包的spice核计算各个仪器的坐标变换矩阵并保存为文件
  - [X] SWIA
  - [ ] SEP
  - [ ] SWEA
- [ ] 全仪器读取
- [X] 计算shape parameter/ projects\maven\swea\mvn_swe_calc_shape_arr.pro
- [X] overview 事件绘制 example
- [ ] 优化 CDF 读取为针对仪器的模式(为每个数据包写需要的变量列表,去除不用的量的读取和 PyObject 的判定)
- [X] 优化KP_l3的读取，写一个数字->变量名的程序来处理之
- [X] 让所有的数据在读取后包含UNIX时间戳的结果(数据本身就自带了unix时间戳)
- [X] 修改下载程序,让 download_data\get_download_files.py 可以自动读取文件目录来生成列表文件
- [X] 下载程序可以检查数据版本
- [X] 简易 Julia 绘图包
- [X] 外接读取文件树
- [ ] 更多磁场模型
- [ ] Aria2的下载用户凭证
- [X] 天问数据
- [X] 磁力线追踪
- [X] 文件树去适配 SPEDAS 的结构
- [X] MAVEN STATIC
- [X] 增加项目初始化和文件处理流程的流程图
- [ ] STATIC 的处理函数目前只能对 4 维数据(时间,质量,方位角,能量)起效,更新为将所有值reshape为最高维数组后进行数组运算
- [X] 使用直接读取链接的方式, 优化下载程序: 直接读取yyyy和mm级别的路径,减去请求不存在月份的步骤
- [X] 由于julia的公共变量问题,把所有需要掩码计算的物理量以掩码模式进行
- [X] 闰秒处理：cdflib自带闰秒处理
- [ ] SWIA仪器为固定安装，理论上SWIA pl坐标系转sc坐标将为常数，因此可以先以固定值旋转pl坐标系的结果到SC坐标系，再以kp中携带的SC转MSO矩阵旋转之。同样的操作可以用于SWEA

随作者需求更新
