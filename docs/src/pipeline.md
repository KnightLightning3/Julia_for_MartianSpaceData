# 项目执行流程

本页整理本仓库当前的端到端执行流程：从环境准备、配置、下载、扫描索引，到派生构建、数据读取与维护校验。架构边界见 [architecture.md](architecture.md)，旧入口迁移见 [migration.md](migration.md)。

## 总览

```
[0] 环境准备           Project.toml / pyproject.toml
        │
        ▼
[1] 配置               config/settings.toml（Python 与 Julia 共用路径配置）
        │
        ▼
[2] 下载               download_data/MAVEN_download.py
        │
        ▼
[3] 扫描与索引         python -m martian_pipeline scan
        │                      │
        │                      └─► lists/*.txt ─► MAVEN_data/filename_lists.json（schema v2）
        ▼
[4] 检查与维护         check（只报告）/ clean（dry-run）/ compress / dedupe
        │
        ▼
[5] 派生构建           Build_data：KP → KP/cdf/、MAG → MAG/l3/ ─► 回到 [3] 刷新索引
        │
        ▼
[6] 读取与计算         Julia：MAVEN_load.load_MAVEN_data / models / 模型计算
        │
        ▼
[7] 测试与文档         python tests/… 、docs/make.jl、tools/push_wiki.py
```

---

## [0] 环境准备

**Julia 侧**（项目依赖由 `Project.toml` 声明，锁定信息见 `Manifest.toml`）：

```julia
using Pkg
Pkg.instantiate()          # 安装 Julia 项目声明的包依赖
using MarsData             # 包入口；公开路径/注册表/索引 API，并加载绘图相关代码
```

`MAVEN_load` 直接使用 `CommonDataFormat`、`TimesDates`、`DataFrames`、`JSON`、`JLD2`、`Rotations` 和 `FortranFiles`；`Dates`、`Statistics`、`Logging` 属于 Julia 标准库。Julia 包依赖由根 `Project.toml`/`Manifest.toml` 管理。`Pkg.instantiate()` 只安装项目声明的 Julia 包，不安装 Python 依赖或 MAVEN 数据文件，也不提供或验证项目依赖之外的 C++/Fortran DLL 等运行时组件。

**Python 侧**：`pyproject.toml` 当前作为依赖清单，仓库采用脚本布局且未声明 `build-system`，因此不要用 editable 安装命令。请在仓库根目录安装脚本所需运行依赖：

```bash
python -m pip install requests beautifulsoup4 tqdm numpy pandas cdflib
```

可选的派生 CDF 构建依赖单独安装：

```bash
python -m pip install spacepy
```

Python 工具从仓库根目录按模块运行，例如 `python -m martian_pipeline scan`；无需先把仓库安装为 Python 包。

> 环境要求：Python ≥ 3.11（配置读取依赖标准库 `tomllib`）、Julia ≥ 1.10。Windows 上派生 CDF 构建依赖 NASA CDF 库；磁场模型依赖对应 C++/Fortran DLL。

---

## [1] 配置

Python 与 Julia 共用 `config/settings.toml` 中的路径配置；所有参数示例见 [`config/settings.example.toml`](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/config/settings.example.toml)。旧 `download_data/MAVEN_download_config.ini` 已弃用，当前代码不读取它，也没有 INI 迁移命令。首次创建配置运行 `python download_data/initialize_download_parameters.py`；该初始化命令不覆盖已有配置。必须设置非空的 `paths.maven_data_root`、`tw_data_root`、`mgs_data_root`；纯空白值会被拒绝，路径中其他首尾空格会保留。相对数据根和相对 `fortran_dll_dir` 均以仓库根解析，与当前工作目录无关；可选 DLL 目录留空时使用仓库根。Julia 在 Paths 模块加载时缓存配置，缺失 `settings.toml` 会明确报错并提示初始化命令。

`[server]`、`[download]`、`[window]` 等其余字段是 Python 下载流程专用参数；Julia 只需要路径配置。

---

## [2] 下载

首次运行初始化器创建 TOML 配置（已有文件不会被覆盖）：

```bash
python download_data/initialize_download_parameters.py
```

执行下载：

```bash
python download_data/MAVEN_download.py
```

- 数据落盘格式：`SAVE_PATH/<仪器>/<处理级别>/<yyyy>/<mm>/<文件>`。
- 下载模式由 `[download] mode` 决定（`python.request` / `win.idm` / `Aria2c`）。
- 下载完成后，脚本会**显式调用**扫描与索引刷新（`check_exist_files.main()`），不再依赖已失效的 `runpy` 隐式链。
- 可选服务器：USTC（校内快、可能不完整）、UCLA（稳定、无 NGIMS）、LASP（压缩、推荐）、Berkeley（部分需账号）。

> 安全约束：不进行真实网络下载的测试一律使用临时目录/合成文件，见 [测试与文档](#7-测试与文档)。

---

## [3] 扫描与索引

扫描本地文件、写出各产品清单并刷新索引：

```bash
python -m martian_pipeline scan                                   # 全部产品
python -m martian_pipeline scan --models MAG_ss KP                # 指定产品（未知产品会被忽略）
python -m martian_pipeline scan --index-output E:/tmp/index.json   # 指定索引输出
```

等价独立入口：`python tools/scan_and_index.py`（同一实现）。

内部流程（均为可导入纯函数，无 `runpy`/`exit()` 进程副作用）：

1. `inventory.load_config()` → `inventory.load_schema()` 读取配置与产品注册表；
2. `inventory.scan(save_dir, data_model)` → 遍历 `<产品路径>/yyyy/mm/`，写出 `lists/<产品>_list.txt`（相对路径用正斜杠）；
3. `manifest.write_index(save_dir, output_path)` → **原子写**（同目录临时文件 + `os.replace`）生成索引 JSON。

索引格式（v2，`schema_version=2`，扁平 + 元数据，向后兼容旧加载器）：

```json
{
  "schema_version": 2,
  "generated_at": "2026-10-13T12:00:00",
  "KP": ["2014/10/mvn_kp_insitu_20141010_v01_r01.tab"],
  "MAG_ss": ["2014/10/mvn_mag_l2_2014283ss_20141010_v01_r01.sts"]
}
```

读端适配器 `manifest.load_index()` 同时兼容 v2（含元数据）与旧版纯扁平格式。

---

## [4] 检查与维护

| 操作 | 命令 | 说明 |
| --- | --- | --- |
| 文件完整性检查 | `python -m martian_pipeline check [--models …] [--action report\|isolate\|delete]` | **默认 `report` 只报告**；`isolate`/`delete` 必须显式启用 |
| 清理未完成下载 | `python -m martian_pipeline clean [--apply]` | **默认 dry-run** 只列出将删除项 |
| 压缩 CDF | `python download_data/compress_cdf.py` | 就地压缩，先写临时文件再 `os.replace`，失败清理残留 |
| 去重低版本 | `python download_data/移除重复文件中的低版本文件.py [--apply]` | **默认 dry-run**，`--apply` 才物理删除 |

> 约定：所有「删除类」操作默认 `dry_run=True`，需显式 `--apply` 才真正落盘。

---

## [5] 派生数据构建

派生产品沿用 MAVEN 根与标准层级，构建器使用**注册表**中的输出产品路径（不再做字符串手术），并以 `os.replace` 原子替换、跳过已存在输出：

| 构建器 | 输入 → 输出 | 产物路径 |
| --- | --- | --- |
| `MAVEN_data/Build_data/KP重构为cdf.py` | KP 文本 `.tab` → CDF | `KP/cdf/yyyy/mm/*.cdf` |
| `MAVEN_data/Build_data/磁场重构为CDF文件.py` | MAG L2 `.sts` → CDF | `MAG/l3/yyyy/mm/*.cdf` |

派生路径由 `config/paths.resolve_output_product(source_model, data_model)` 按「`source_model + "_cdf"`」约定解析（如 `MAG_ss → MAG_ss_cdf → MAG/l3/`、`KP → KP_cdf → KP/cdf/`），输出文件名可被对应产品正则发现。

> **构建后必须重新执行 [3] 扫描与索引**，使派生产品进入索引闭环。

---

## [6] 读取与计算

**MAVEN 文件读取器**（Julia）：

```julia
using MarsData, Dates
MarsData.@load MAVEN_load
errors = String[]
data = MAVEN_load.load_MAVEN_data(
    DateTime(2014, 12, 20);
    model_index=["MAG_ss"],
    error_report=errors,
)
mag = data["MAG_ss"]
mag[:data_load_flag] && (B = mag[:B])
```

**MarsData 包 API**：

```julia
using MarsData
MarsData.project_root(); MarsData.maven_data_root(); MarsData.index_path()
MarsData.data_model();  MarsData.load_index()
```

`using MarsData` 会加载包中绘图实现（包括 CairoMakie/Makie 依赖）；因此不应称它为不加载绘图的轻量包。模块装载管理器可用 `MarsData.@load MAVEN_load` 在调用者顶层装载读取器。`load_MAVEN_data` 实际接受单个 `DateTime`，不是字符串或日期向量；已注册产品缺文件和 loader 异常会以 `:data_load_flag => false` 返回，详情可从 `error_report` 读取。未知产品 ID 可能在查找阶段抛出 `KeyError`。索引 JSON 在读取器装载后仍是惰性访问，按模型首次构建并缓存日期索引。

模块、模型和计算入口以当前源码与注册表为准；不要依赖已删除的 `common/head`、旧 `calculate/` 或旧 `Magnetic_Model/` 路径。环境初始化只说明 Julia 包依赖，不会安装外部 MAVEN 数据文件；需要 DLL 的能力也不能由 `Pkg.instantiate()` 推断为已验证。

**绘图**：绘图 API 随 `using MarsData` 提供，无需手动 `include`：

```julia
using MarsData, CairoMakie
fig = Figure(; size=(2500, 2500))
fig, t0, xtimes = MarsData.plot_module(fig, time_range, data_dict; time_step=Dates.Minute(10))
save("overview.png", fig)
```

其中 `plot_module` / `TimeFormat` / `remove_0_point!` 定义于 `src/plotting.jl`，绘图基元来自子模块 `MarsData.MAVEN_plot`（源文件 `MAVEN_data/MAVEN_plot.jl`）。示例见 `example/MAVEN_plot_sample/`。

**时间轴查找**：所有被读取数据的时间轴（除特别说明）均为排序时序数据；时间轴最近邻查找统一使用 `MarsCommon.searchsortednearest`（二分，`O(log N)`），**不要**使用 `findmin(abs.(x .- x0))`（线性扫描）。能量轴、色标等非时序数据仍用 `findmin`。

---

## [7] 测试与文档

**回归测试**（全部使用临时目录/合成文件，不触碰真实科学数据、不进行真实网络下载）：

```bash
python tests/test_p0.py          # 配置初始化 / 扫描 / 索引 / 下载后刷新
python tests/test_p1.py          # TOML 类型/范围校验、拒绝 INI、初始化不覆盖
python tests/test_config_wiring.py # 下载配置接线，使用替身禁止联网
python tests/test_p2_utils.py    # 共享纯函数
python tests/test_p2_cli.py      # 扫描/索引边界（空目录、未知模型、正则无匹配、路径分隔符）
python tests/test_p3.py          # 索引 v2、派生输出路径注册表解析
python tests/test_package.py     # martian_pipeline 包与 CLI 端到端
julia --project=. test/paths_config_test.jl # Julia TOML 路径配置（临时仓库）
julia --project=. test/path_callsite_test.jl # 不带尾分隔符的目录与清单拼接
```

**文档构建与发布**：

```bash
julia --project=docs docs/make.jl      # Documenter：生成 HTML 到 docs/build/
python tools/push_wiki.py --dry-run    # GitLab Wiki：生成到临时目录并自检，不推送
python tools/push_wiki.py --push       # GitLab Wiki：生成、提交并推送
```

- Documenter 站点源为 `docs/src/*.md`，产物 `docs/build/` 不入库。
- [GitLab Wiki](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/wikis/home) 正文同样由 `docs/src/*.md` 生成，跨页链接自动改写为 Wiki 页面名；Wiki 首页与侧边栏取自 `docs/wiki/`。

**语法检查**：

```bash
python -c "import ast,pathlib; [ast.parse(p.read_text(encoding='utf-8'),filename=str(p)) for p in pathlib.Path('.').rglob('*.py')]"
julia -e 'Meta.parseall(read("MAVEN_data/MAVEN_load.jl", String))'
```
