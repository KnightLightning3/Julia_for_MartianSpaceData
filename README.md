<div align="center">

# 火星空间数据处理与科学计算工具包

**Mars Space Data Processing & Scientific Computing Toolkit**

</div>

[English](README_EN.md) · [Documenter 文档](docs/src/index.md)

本仓库提供 MAVEN、MGS 与天问一号数据的下载、读取和处理工具，以及火星空间环境与等离子体计算代码。Julia 用于数据处理、科学计算和绘图；Python 用于 MAVEN 下载与本地文件维护。具体功能入口见下方目录与文档导航。

## 当前目录

| 路径 | 内容 |
| --- | --- |
| `src/`、`Project.toml` | Julia 包 `MarsData`：路径/索引 API、绘图和模块装载器 |
| `MAVEN_data/` | MAVEN 读取器、STATIC/SWIA/SWEA 处理、绘图基元及产品注册表 |
| `MGS_data/`、`TW_data/` | MGS 与天问一号读取和仪器处理 |
| `common/` | 共享常量、路径、数据键、坐标与物理计算 |
| `models/` | 火星环境、IGRF、色散关系、分布拟合和粒子轨道模型 |
| `models/extras/` | 独立的 Graham 与 Octree 实验代码 |
| `analysis/` | 事件分析脚本，例如 `Pickup_ion.jl` |
| `support_data/` | OMNI 等外部支持数据读取 |
| `download_data/`、`martian_pipeline/` | Python 下载、扫描、索引和文件维护 |
| `config/`、`tools/` | TOML 配置、扫描/API/Wiki 工具 |
| `example/` | 使用示例；部分脚本会读数据、写文件或载入 DLL，运行前请先检查脚本顶部的设置 |
| `docs/` | Documenter 源、Wiki 页面、参考资料及历史报告 |

## Julia 包与共享能力

Julia 要求 1.10 或更新版本。`using MarsData` 会初始化绘图栈（CairoMakie/Makie），并预装绘图子模块；路径、产品注册表和索引 API 本身不加载科学数据读取器，也不要求本地观测数据或 IGRF DLL。

首次使用（fresh clone）前，先创建配置并编辑三个数据根路径；否则首次 `using MarsData` 会因缺少 `config/settings.toml` 报错：

```bash
python download_data/initialize_download_parameters.py
# 使用文本编辑器修改 config/settings.toml 中的 [paths]
```

将 `paths.maven_data_root`、`tw_data_root`、`mgs_data_root` 设置为本机目录后，再启动 Julia。

`MarsData` 的预装实例包括 `MarsData.MarsCommon`、`MarsData.MarsEnvironment`、`MarsData.MAVEN_plot`、`MarsData.Paths` 和 `MarsData.DataKeys`。它们由包初始化，装载器会复用这些实例。包没有把所有 API 名称重新导出为裸名；优先使用明确限定名，例如 `MarsData.project_root()`、`MarsData.DataKeys.ENERGY`。

`common/MarsCommon.jl` 将通用能力拆分到 `common/marscommon/`：

| 文件 | 能力概览 |
| --- | --- |
| `statistics.jl` | 统计与分布相关计算 |
| `geometry.jl` | 坐标变换、位置和磁场几何 |
| `numerics.jl` | 数值拟合及通用数值工具 |
| `cyclotron.jl` | 回旋与波粒相关计算 |

`common/constants.jl` 提供共享物理常量；`common/paths.jl` 解析仓库与数据路径；`common/data_keys.jl` 集中定义数据字典的 Symbol 键契约。`DataKeys.MASS` 是 STATIC/SWIA 数据包共用的质子静止质量基准，单位 `eV/(km/s)^2`；它不同于质量轴 `MASS_ARR` 和比荷参数 `m_int`。

MarsCommon 中逐元素数学函数按标量输入设计。对数组使用 Julia 广播点，例如 `MarsData.MarsCommon.ion_energy2v.(energy, 16)`。位置批处理、矩阵旋转、原地字典处理和时间轴最近邻查找则是数组/矩阵接口；具体签名见 [API 索引](docs/src/api.md)。

### 三维点与坐标旋转

通用的点坐标转换位于未注册的 `FunctionCoordinate` 模块。先显式 include，再使用限定名；单点优先传 `SVector{3}`，长度为 3 的 `AbstractVector{<:Real}` 也可作为适配输入，结果为 `SVector{3}`。批量点可写 `f.(points)`；`N×3` 行存坐标则逐行调用 `map`，不要把点内部的三分量拆开广播：

```julia
using MarsData, StaticArrays, Rotations
include(joinpath(MarsData.project_root(), "common", "function_coordinate.jl"))
FC = FunctionCoordinate

p = SVector(1.0, 2.0, 3.0)
spherical = FC.pc2sphere(p)       # (r, 余纬 θ, 方位角 ϕ)，角度为弧度
p_back = FC.sphere2pc(spherical)
FC.pc2sphere([1.0, 2.0, 3.0])     # 长度为 3 的普通向量也可输入
FC.MAVEN_sphere2xyz(SVector(1.0, 0.0, 0.0)) # MAVEN角度为度：仰角自XY平面，方位角自+X朝+Y

points = [SVector(1.0, 0.0, 0.0), SVector(0.0, 1.0, 0.0)]
spheres = FC.pc2sphere.(points)   # 每个点调用一次标量函数
P = [1.0 0.0 0.0; 0.0 1.0 0.0] # 两行分别是一个点
P_spherical = map(i -> FC.pc2sphere(view(P, i, :)), axes(P, 1))

θ = π / 2
q = Rotations.QuatRotation(cos(θ / 2), 0.0, 0.0, sin(θ / 2))
v = SVector(1.0, 0.0, 0.0)
v_rotated = q * v                # +Z 轴主动旋转 +90°
v_restored = inv(q) * v_rotated
R = Rotations.RotMatrix(q)       # static 3×3 matrix for the same rotation
v_matrix = R * v                 # 矩阵作用于列向量
```

`q * v`、`R * v` 是对列向量的作用。说清坐标变换时，应注明 `R_source_to_target` 表示源基底到目标基底的分量映射；仅凭某个矩阵乘法形式不能推断其方向。对 `N×3` 行存点，若列向量关系为 `p_target = R_source_to_target * p_source`，则整体写作 `P_target = P_source * transpose(R_source_to_target)`；逆向为 `P_source = P_target * R_source_to_target`（实数正交旋转）。标准 `pc2sphere` 用弧度余纬；MAVEN 仪器球坐标用角度制仰角，两者定义见[坐标转换专题](docs/src/coordinates.md)。

包内元数据入口可单独使用，不需要载入 MAVEN 读取器：

```julia
using MarsData
MarsData.project_root()
MarsData.maven_data_root()
MarsData.data_model()     # MAVEN 产品注册表
MarsData.load_index()     # 缺少索引文件时返回空字典
```

这些函数通过 `MarsData.` 限定访问。数据根目录由配置解析，产品注册表来自仓库内的 `MAVEN_data/MAVEN_data_format.json`，文件索引位于 `MAVEN_data/filename_lists.json`。

## 配置与数据路径

所有 Python 与 Julia 路径配置统一编辑 `config/settings.toml`；全参数模板见 [`config/settings.example.toml`](config/settings.example.toml)。旧 `download_data/MAVEN_download_config.ini` 已弃用且不再读取。首次初始化可运行 `python download_data/initialize_download_parameters.py`；该命令只在配置文件不存在时创建，不覆盖已有设置。Python 下载器独有的服务器、下载方式、线程数和日期窗口也保存在同一 TOML 中，但只有 Python 下载流程使用这些参数。

必须填写 `[paths]` 中非空的 `maven_data_root`、`tw_data_root` 和 `mgs_data_root`。仅由空白组成的值会被拒绝；其他路径值会保留首尾空格。绝对路径按其平台语义保留；相对路径均以仓库根目录为基准，与启动 Julia/Python 时的当前目录无关。可选的 `fortran_dll_dir` 留空时使用仓库根目录。Julia 加载路径模块时读取并缓存配置；缺少 `settings.toml` 会明确提示运行上述初始化命令，不会自动切换到某个磁盘目录。

Python 工具要求 Python 3.11 或更新版本。Python 运行依赖与可选构建依赖列于 `pyproject.toml`；`spacepy` 属于派生 CDF 构建的可选依赖。详细配置、下载和索引流程见[项目执行流程](docs/src/pipeline.md)。

Julia 的 `Project.toml` 列出 `MarsData` 主环境的直接依赖，包含绘图栈。`Pkg.instantiate()` 只按该项目环境安装依赖，不会自动提供所有外部 loader、插件或独立 extra 所需的软件包。运行完整 MAVEN 读取器需另外确保其运行环境能解析 `CommonDataFormat`、`JLD2`、`FortranFiles` 等依赖；仪器处理模块还使用 `TimesDates`、`DataInterpolations`、`Rotations` 等包。具体按目标模块准备依赖，不要把“包能载入”当作“所有模块依赖已安装”。

`MAVEN_STATIC`、`MAVEN_SWIA`、`MAVEN_SWEA` 当前源码不导入 `CommonDataFormat`；可在已有输入数据字典上做仪器计算。读取 CDF 的 `MAVEN_load` 仍需要相应 CDF/文件格式依赖。`models/extras/Graham.jl` 与 `Octree.jl` 是显式 include 的独立代码，其外部依赖见 `models/CATALOG.toml`，不属于 MarsData 主依赖清单。

## 最小读取示例

下面示例使用一个 `DateTime`（读取该日）和一个当前注册的产品名。运行前需配置本地数据根、生成/刷新文件索引，并在 Julia 环境中安装读取器所需外部依赖。它不会下载数据或验证本机 DLL。

```julia
using Dates
using MarsData

MarsData.@load MAVEN_load
day = DateTime(2014, 12, 20)
data = MAVEN_load.load_MAVEN_data(day; model_index = ["MAG_pc1s_cdf"])
mag = data["MAG_pc1s_cdf"]

if get(mag, :data_load_flag, false)
    B = mag[:B]          # 磁场分量，nT；读取产品的时间轴为 epoch
    t = mag[:epoch]      # DateTime 时间序列
end
```

读取器按产品分别返回字典，成功时附带 `:filename` 与 `:data_load_flag`；缺文件或读取失败的产品会返回失败标志。MAVEN 的数据产品名称、格式和键结构见[数据读取指南](docs/src/data_reading.md)与[数据格式参考](docs/src/data_format.md)。一般约定：时间轴为排序后的时序数据；位置为 km，磁场为 nT，能量为 eV，质量轴为 AMU。坐标系与特殊字段单位以产品及对应函数为准，不能把 PC 产品直接视为 MSO。

## 模块装载与白名单

`MarsData.load_module(name)` 从注册表载入模块；`MarsData.@load Name...` 在调用者顶层绑定模块名。普通模块在运行时 carrier 中求值，再作为别名绑定到 `MarsData` 或调用者命名空间；因此它不是把源文件直接 include 到 `MarsData`。装载器按注册表依赖顺序准备模块，并复用预装实例。

当前白名单只把以下名称引入 `@load` 调用者作用域：

| 模块 | 裸名白名单 |
| --- | --- |
| `MarsCommon` | `searchsortednearest`、`e_energy2v`、`ion_energy2v` |
| `MAVEN_load` | `load_cdf`、`load_MAVEN_data` |
| `IGRF_calculate` | `IGRF_pc` |

其他模块的白名单为空：`@load` 只绑定模块名。即使某个子模块中的名字可通过完整限定名访问，也不表示它会被 `@load` 导入为裸名。`MarsData.MAVEN_plot.WaveSpectra_heatmap` 使用完整限定名访问。查询注册表可用 `MarsData.available_modules()`、`MarsData.module_info(:MAVEN_load)` 和 `MarsData.validate_registry()`。

常用入口包括 `MAVEN_load`、`MAVEN_STATIC`、`MAVEN_SWIA`、`MAVEN_SWEA`、`IGRF_calculate`、`Cold_Plasma_Dispersion_Relation`、`Maxwellian_Distribution`、`Single_Particle_Orbit`、`MGS_load`、`TW_load`、`TW_MINPA` 和 `SP_load`。以 `MarsData.available_modules()` 返回值为准。

## MarsEnvironment、模型与独立脚本

火星环境几何实现位于 `models/Mars_Environment.jl`，模块名为 `MarsEnvironment`，包内规范实例为 `MarsData.MarsEnvironment`，并与 `MarsData.MAVEN_plot.MarsEnvironment` 是同一实例。IGRF 实现和伴随资源位于 `models/`；模型注册入口为 `IGRF_calculate`，使用时需要其外部 Fortran 运行库和 DLL。科学逻辑对照基线为 `a09511aa7b88c874cefe8ca966c98aa267db9365`；本 README 不代表全仓行为已逐项证明与基线一致。真实数据验证目前暂停，本轮也未验证 DLL。

`analysis/Pickup_ion.jl` 是分析脚本入口；`models/extras/` 中的 Graham/Octree 需按其目录说明显式载入。它们不属于通用装载器白名单；独立脚本可能依赖用户预设变量、专用包或本地数据，不作为无副作用 quickstart。

旧入口和已改名 API 集中见[迁移说明](docs/src/migration.md)。`CHANGELOG.md` 与 `docs/reports/` 保留历史记录，不因路径或 API 迁移而改写；历史报告不作为当前接口规范。当前模块关系见[架构说明](docs/src/architecture.md)，函数职责见[API 索引](docs/src/api.md)。

## 绘图

绘图概览合成由 `MarsData.plot_module` 提供；常用格式函数为 `MarsData.TimeFormat` 和 `MarsData.remove_0_point!`。绘图基元在 `MarsData.MAVEN_plot` 子模块中，使用完整限定名，例如 `MarsData.MAVEN_plot.sta_heatmap`、`MarsData.MAVEN_plot.WaveSpectra_heatmap`。示例源码位于 `example/MAVEN_plot_sample/`；脚本可能读取本地数据并写出图片，运行前请检查参数与副作用。

绘图 API 接收 Makie 图形对象与已读取的数据字典；`using MarsData` 不会把 CairoMakie 的 `Figure`、`Axis` 或 `save` 重新导出：

```julia
using MarsData, CairoMakie
fig = Figure()
MarsData.plot_module(fig, time_range, data_dict)
save("overview.png", fig)
```

此片段仅展示调用形状。实际图面需要符合该函数所需产品和键的数据字典；请先查阅绘图示例源码及 [API 索引](docs/src/api.md)。

## 文档与生成流程

- [文档首页](docs/src/index.md)：Documenter 页面导航。
- [项目执行流程](docs/src/pipeline.md)：环境、配置、下载与索引流程。
- [数据读取](docs/src/data_reading.md) · [数据格式](docs/src/data_format.md)：MAVEN 读取接口和数据结构。
- [架构说明](docs/src/architecture.md) · [迁移说明](docs/src/migration.md) · [API 索引](docs/src/api.md)：分别说明模块关系、破坏性迁移和源码入口。
- [SWIA 电子修正](docs/src/swia_electron.md)：专题说明。

Documenter HTML 与 Python Wiki 是同一批 `docs/src/` 文档源的两种输出。Documenter 构建 HTML：

```bash
julia --project=docs docs/make.jl
```

生成 API 页面源：

```bash
julia --startup-file=no tools/generate_api.jl
```

预览 Python Wiki 输出（dry-run，不发布）：

```bash
python3 tools/push_wiki.py --dry-run
```

独立文档环境的准备、生成检查和正式发布步骤见[文档维护说明](docs/README.md)。
