# MarsData.jl 文档

火星空间数据处理与科学计算工具包（*Mars Space Data Processing & Scientific Computing Toolkit*）。

本项目提供火星空间科学数据的**下载、读取、处理、可视化与物理模型计算**工具：主要数据处理与科学计算使用 Julia，数据下载与文件整理主要使用 Python，部分磁场计算通过 Fortran 动态库加速。

## 文档导航

| 页面 | 内容 |
| --- | --- |
| [项目执行流程](pipeline.md) | 从环境准备到数据读取的端到端流程与命令 |
| [MAVEN 数据读取](data_reading.md) | 统一读取入口、返回结构与数据流程 |
| [MAVEN 数据格式](data_format.md) | 数据产品清单、命名格式与仪器数据要点 |
| [SWIA 电子修正](swia_electron.md) | 电子二次发射背景的假设与修正算法 |
| [程序与函数索引](api.md) | 按目录浏览各程序职责与主要函数 |

## 快速开始

```julia
# 1. 环境（Julia 侧依赖）
using Pkg; Pkg.instantiate()

# 2. 轻量公共 API（路径 / 注册表 / 索引，无需本地数据与 DLL）
using MarsData
MarsData.maven_data_root()      # 数据根目录
MarsData.data_model()           # 产品注册表
```

```julia
# 3. 读取某一天的数据（完整加载器）
include("path/to/MAVEN_data/MAVEN_load.jl"); import .MAVEN_load
Data_Dict = MAVEN_load.data_get_from_date(["20141220"], model_index = ["MAG_pc1s", "LPW_wave"])
mag_data = Data_Dict["MAG_pc1s"][:B]
```

```bash
# 4. 下载与索引（Python 侧）
python tools/migrate_config.py --apply          # 一次性：INI → TOML 配置
python -m martian_pipeline scan                 # 扫描本地文件并刷新索引
```

详见 [项目执行流程](pipeline.md)。

## 项目结构

| 目录/文件 | 用途 |
| --- | --- |
| `MAVEN_data/` | MAVEN 数据读取、仪器数据处理、绘图及数据格式定义 |
| `MGS_data/`、`TW_data/` | MGS 与天问一号数据读取和仪器处理 |
| `download_data/` | MAVEN 数据下载、完整性检查、压缩及清理工具 |
| `config/` | 唯一配置层：`settings.example.toml` 模板 + `config.py`/`paths.py`/`utils.py` |
| `martian_pipeline/` | Python 包化入口与统一 CLI（`python -m martian_pipeline`） |
| `tools/` | 配置迁移（`migrate_config.py`）与扫描索引（`scan_and_index.py`）CLI |
| `tests/` | 临时目录合成数据的回归测试（P0–P3 + 包化） |
| `models/`、`Magnetic_Model/` | 等离子体、粒子轨道、磁场等模型与计算 |
| `common/`、`support_data/` | 通用坐标/物理计算函数和外部支持数据读取 |
| `calculate/` | 模型计算流程与组合入口 |
| `example/` | 绘图和数据分析示例 |
| `src/`、`Project.toml` | Julia 包 `MarsData`（轻量公共 API 入口） |
| `pyproject.toml` | Python 运行依赖与可选依赖清单 |
| `docs/` | 本 Documenter 文档源与构建产物 |

## 数据说明

- 所有 MAVEN 产品（原始与派生）共用同一 MAVEN 数据根，保持 `MAVEN/仪器/处理级别/yyyy/mm/文件` 结构；产品 ID、路径与文件名正则负责区分。
- 配置以 TOML 为唯一写端（`config/settings.toml`），旧 INI 保留为只读兼容输入。
- 所有被读取数据的时间轴（除特别说明）均为**排序后的时序数据**；时间轴最近邻查找统一使用 `MarsCommon.searchsortednearest`（二分，`O(log N)`）。
