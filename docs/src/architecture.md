# 项目架构

本页描述当前工作树中的代码组织与装载方式。旧路径、旧名称和非等价函数的区别见[迁移指南](migration.md)，按文件生成的定义清单见[程序与函数索引](api.md)。

## 代码分工

| 位置 | 职责 | 使用入口 |
| --- | --- | --- |
| `src/MarsData.jl` | Julia 包入口、路径与产品注册表、绘图和装载管理 | `using MarsData` |
| `src/modules.jl` | 模块注册表、依赖装载、裸名白名单、自检 | `MarsData.load_module`、`MarsData.@load` |
| `common/paths.jl` | 配置与数据根路径解析 | `MarsData.Paths` 或包级路径函数 |
| `common/data_keys.jl` | 字典键契约 | `MarsData.DataKeys` |
| `common/constants.jl` | 物理常量 | 各计算模块内部的 `constants` |
| `common/MarsCommon.jl`、`common/marscommon/` | 通用坐标、几何、统计、数值与回旋计算 | `MarsData.MarsCommon` |
| `common/function_coordinate.jl` | 标准、MAVEN、PA、MINPA 点坐标定义与旋转矩阵构造 | 显式 include 后的 `FunctionCoordinate` |
| `MAVEN_data/MAVEN_load.jl` | CDF/文本/二进制读取及产品调度 | `MAVEN_load.load_MAVEN_data` |
| `MAVEN_data/MAVEN_STATIC.jl`、`MAVEN_SWIA.jl`、`MAVEN_SWEA.jl` | 对仪器数据字典做切片、分布与物理量计算 | 对应模块的限定名 |
| `MAVEN_data/MAVEN_plot.jl`、`src/plotting.jl` | 绘图基元与概览图组合 | `MarsData.MAVEN_plot`、`MarsData.plot_module` |
| `MGS_data/`、`TW_data/`、`support_data/` | MGS、天问一号与外部支持数据 | 注册表中的相应模块 |
| `models/` | 火星环境、IGRF、色散、分布和轨道模型 | 按注册表名称装载 |
| `analysis/Pickup_ion.jl` | 拾取离子事件分析脚本 | 准备上下文后显式 include |
| `models/extras/`、`models/CATALOG.toml` | 实验性附加算法及用途、依赖清单 | 显式 include，不进模块注册表 |
| `config/`、`martian_pipeline/`、`download_data/` | Python 配置、下载、库存、索引与维护 | `python -m martian_pipeline` 及下载脚本 |
| `MAVEN_data/Build_data/` | 派生产品构建脚本 | 按[执行流程](pipeline.md)单独运行 |

`Magnetic_Model/` 保留历史系数文本备份；现行 IGRF 代码和运行资源在 `models/`。`common/head.jl` 与 `calculate/calculate_models.jl` 已删除。

## 包初始化与按需装载

`using MarsData` 会读取路径配置，载入绘图栈与 `MAVEN_plot`，并暴露 `Paths`、`DataKeys`、`MarsCommon`、`MarsEnvironment`。它不启动 MAVEN 科学数据读取器，也不调用 IGRF 动态库；这并不表示包初始化没有绘图依赖。

注册表位于 `src/modules.jl`，以 `ModuleSpec` 记录模块名、源码路径、依赖、装载种类和 `allow` 白名单。可以查询实际配置：

```julia
using MarsData
MarsData.available_modules()
MarsData.module_info(:MAVEN_STATIC)
MarsData.module_path(:IGRF_calculate)
MarsData.validate_registry()
```

普通模块在运行时载体中求值，再以模块别名绑定到目标命名空间。注册表的 `deps` 会先递归装载；同一会话重复装载通常复用载体中的实例。`force=true` 会重新求值，不建议用它代替重启会话来解决已有绑定冲突。

```julia
using MarsData
M = MarsData.load_module(:MAVEN_STATIC)  # 返回模块，绑定 MarsData.MAVEN_STATIC
MarsData.@load MAVEN_SWEA              # 顶层绑定当前作用域的 MAVEN_SWEA
```

`Paths`、`DataKeys`、`MarsCommon`、`MarsEnvironment`、`MAVEN_plot` 为 `:preloaded`，返回包内已有对象。`MarsData.MarsCommon` 和 `MarsData.MarsEnvironment` 分别绑定到 `MAVEN_plot` 内的规范实例；注册表装载的 IGRF 会复用该 `MarsCommon`。其他文件仍可能自行 include 通用模块，不能据此推断全仓所有嵌套实例都相同。

## 模块名、export 与裸名白名单

推荐使用 `MAVEN_STATIC.sta_v_4d` 等限定名。`@load` 仅按 `allow` 逐名引入函数，不会整体 `using` 一个模块；`export` 列表不等同于装载器白名单。

| 模块 | 当前 allow |
| --- | --- |
| `MarsCommon` | `searchsortednearest`、`e_energy2v`、`ion_energy2v` |
| `MAVEN_load` | `load_cdf`、`load_MAVEN_data` |
| `IGRF_calculate` | `IGRF_pc` |

其余注册模块的 `allow` 为空，只绑定模块名。`FunctionCoordinate`、Pickup 和 Extras 不在注册表里，不能照搬 `@load` 示例：

```julia
using MarsData
include(joinpath(MarsData.project_root(), "common", "function_coordinate.jl"))
R = FunctionCoordinate.slice2d_cal_rot([1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
```

IGRF 装载器只把 `IGRF_pc` 引入裸名；其内部标量 `pc2sphere`、`sphere2pc` 不通过 `@load` 白名单开放。通用三维点版本使用 `FunctionCoordinate.pc2sphere`、`FunctionCoordinate.sphere2pc`。MAVEN 仪器角使用独立的 `MAVEN_sphere2xyz`、`MAVEN_xyz2sphere` 点接口。该模块不在注册表中，需显式 include 且通过限定名访问。坐标方向、批量行存约定和各仪器球坐标的差异见[坐标转换](coordinates.md)。

Extras 为独立脚本；建议 include 到独立命名空间，避免 `Point` 等类型与绘图库重名。Pickup 仍含顶层执行流程，依赖调用方的事件变量、数据和外部包，不能把 include 当作无副作用的 API 查询。

## 环境边界

根 `Project.toml` 声明 Julia 包的直接依赖；`Pkg.instantiate()` 只负责该环境。载体机制不会自动安装额外包。

| 功能 | 额外条件 |
| --- | --- |
| MAVEN 读取器 | `CommonDataFormat`、`JLD2`、`FortranFiles` 等源码导入必须能从 `LOAD_PATH` 解析；配置、索引和数据文件另行准备 |
| STATIC/SWIA/SWEA 字典计算 | 需要相应模块的计算依赖；三模块已移除未使用的 `CommonDataFormat` 导入 |
| 单粒子 ODE | `DifferentialEquations` |
| IGRF | `FortranFiles`（读取系数文件 `models/gh_gao`）；场值与磁力线追踪为纯 Julia 实现，无动态库依赖 |
| Extras | 以 `models/CATALOG.toml` 为准，在独立或全局环境准备所需包 |
| 文档 | `docs/Project.toml` 的独立 Documenter 环境；静态 API 索引生成仅用 Julia 标准库 |

不要为了构建说明文档而装载科学读取器、运行分析脚本或执行真实数据流程。IGRF 的文件位置说明不构成动态库可用性验证。

## 数据契约与计算边界

读取器按产品 ID 返回数据字典，仪器模块消费这些字典，分析和绘图层组合结果。实际读取参数、错误报告和产品表见[数据读取](data_reading.md)与[数据格式](data_format.md)。

`DataKeys` 固定公共键的拼写。`MASS = :mass` 是 STATIC/SWIA 数据包中同一个质子静止质量基准，单位 `eV/(km/s)^2`；`MASS_ARR = :mass_arr` 是 STATIC 质量轴，`m_int` 是计算参数，三者不能替换。STATIC 的质量基准已使用 `constants.mp_eV_per_km_s2`，以保留 Float64 精度。

能量、速度、密度和坐标约定以具体函数为准。标准余纬与仪器角定义不同；标量函数处理数组时需要调用处广播。坐标转换边界见[坐标专题](coordinates.md)，其他接口变更见[迁移指南](migration.md)。

## 文档与验证

`docs/src/` 是专题正文来源，`docs/pages.toml` 统一登记页面。Documenter 生成 HTML，Python Wiki 脚本把同一正文转换成 Wiki 页面；API 定义索引由 `tools/generate_api.jl` 静态产生。

逻辑比较的初始基准为提交 `a09511aa7b88c874cefe8ca966c98aa267db9365`。现有迁移夹具有些仍引用中间提交 `5f225db`，它们的通过结果不能替代对初始基准的完整证明。2026-10-16 已完成六份真实文件的读取与复跑比对，详见[验证记录](../reports/real_data_validation_2026-10-16.md)；未执行 DLL 验证，本页不宣称已完成全仓科学等价性审查。
