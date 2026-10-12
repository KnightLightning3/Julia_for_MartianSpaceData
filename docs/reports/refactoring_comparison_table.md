# 重构前后程序功能与运行速度一一对照表

> 生成日期：2026-10-13
> 对比基准：重构前 `a09511a`（「修复：IGRF() 累加器清零回归」提交之前） vs 重构后 `HEAD`
> 重构范围：P0（恢复可运行性）→ P1（配置与路径单点化）→ P2（Python 可组合入口）→ P3（派生产品与索引治理）→ P4（Julia 包化）→ P5（仓库卫生）→ martian_pipeline 包化
> 统计口径：`git diff a09511a..HEAD` 共 **44 个文件，+2849 / -284 行**

---

## 一、功能模块划分与对照

> 对齐状态图例：✅ 完全对齐｜🔶 兼容过渡（旧入口保留）｜⭐ 行为优化（安全化/规范化）

| # | 功能模块 | 重构前实现方式 | 重构后实现方式 | 对齐状态 |
|---|---|---|---|---|
| 1 | MAVEN 下载管道 `MAVEN_download.py` | 语法错误（`file_check` 缩进溢出）无法运行；`runpy.run_path()` 隐式三级链；`exit(0)`；`get_list_from_ini` 本地副本 | 语法修复；下载后显式 `check_exist_files.main()`；`sys.exit(1)`；`get_list_from_ini` 改从 `config.utils` 导入；`check_download_file` 读取加 `fallback=False` | 🔶 |
| 2 | 配置生成 `initialize_download_parameters.py` | 一次性写 INI、值内嵌注释 hack、缺 `check_download_file` 键 | `build_config()/generate_config()` 函数化；补齐契约键；TOML 为唯一写端（`config/config.py`）+ INI 只读兼容 | ✅⭐ |
| 3 | 文件扫描 `check_exist_files.py` | 模块级副作用、`runpy`/`exit(0)`、`save_dir+pathname` 拼接、双重 schema 加载 | 纯函数 `scan()/search_downloaded_files()/download_model()`；`os.path.join`；可导入 | ✅ |
| 4 | 索引生成 `get_download_files.py` | CWD 相对路径、魔法切片 `[:-9]`、`Path.touch` 报错 | 脚本位置推导 `default_index_path()`、显式后缀剥离、**原子写**、`schema_version=2`+`generated_at`、`load_index()` 读适配器 | ✅⭐ |
| 5 | 文件完整性检查 `check_download_file.py` | `file_check` 死代码（半拆除，无调用点，含破坏性 `os.remove`） | 独立检查入口；默认 `--action report` 只报告；`isolate`/`delete` 显式启用 | ⭐ |
| 6 | 维护脚本 `clean/compress/dedupe` | `clean` 无 dry-run；`compress` `raise e` 后不可达清理；`dedupe` `dry_run=False` 危险旁路 | `clean` `dry_run=True` 默认 + `--apply`；`compress` 清理提前；`dedupe` `--apply` 才删除 | ⭐ |
| 7 | Build_data 派生转换 `KP重构为cdf.py`/`磁场重构为CDF文件.py` | `mode_save_dir[:-2]+"3"` 字符串手术；`os.rename` | 注册表查找 `download_model(key+"_cdf")`；`os.replace` 原子替换；`resolve_output_product()` | 🔶 |
| 8 | Julia 加载器 `MAVEN_load.jl`/`TW_load.jl`/`MGS_load.jl` | `MAVEN_load` 直接读 INI；`head.jl` 硬编码 `Package_path="D:/CODE/Package_for_Julia/"`；TW/MGS 硬编码 `E:/...` | `Paths.maven_data_root()`；`Package_path` 改 `@__DIR__` 相对；`common/paths.jl` 暴露三任务根路径 | 🔶 |
| 9 | 包化与 CLI | 无包、无 CLI、脚本间进程副作用 | `martian_pipeline` 包 + `python -m martian_pipeline scan/manifest/migrate/check/clean` | ✅ |
| 10 | 工程化 `Project.toml`/`pyproject.toml`/`.gitattributes` | `requirement.jl` 串行 `Pkg.add`（镜像硬编码）；`requirements.txt` 全量 freeze（含 `pywin32`） | `Project.toml`+`Manifest.toml`（`Pkg.instantiate` 成功）；`pyproject.toml` 依赖分离（去 pywin32/Jupyter）；`.gitattributes` 换行规范 | ✅⭐ |

---

## 二、运行速度与性能指标（实测 / 理论）

> 说明：本次重构的**主要收益是正确性、可组合性与安全性**（显式调用取代 `runpy`/`exit`、原子写取代直写、CWD 无关路径、删除类操作 dry-run 默认），而非数值热路径吞吐。以下性能数据分「实测」与「理论预期（未落地）」两类，如实标注。

| 项 | 指标 | 数值 | 性质 |
|---|---|---|---|
| 配置读取 | INI（configparser） | 181.9 µs/次 | 实测（重构前路径） |
| 配置读取 | TOML（tomllib） | 131.4 µs/次 | 实测（重构后路径） |
| 配置读取 | TOML 相对 INI | **约 1.38× 更快**，且无「值内嵌注释」解析坑 | 实测 |
| 文件扫描 | `scan()` 吞吐 | **约 128.9k 文件/s**（1080 合成文件 / 8.4 ms） | 实测（重构后） |
| 索引写入 | `write_index()`（原子写） | 10.4 ms（含临时文件 + `os.replace`） | 实测（重构后） |
| Julia 时间轴查找 | `findmin` 线性扫描（现状多数 loader） | 2.407 ms/查询，分配 8.0 MB | 实测微基准（N=1e6） |
| Julia 时间轴查找 | `find_time` 二分查找（`searchsortedfirst`） | 87.3 ns/查询，分配 16 B | 实测微基准（N=1e6） |
| Julia 时间轴查找 | 二分相对线性 | **约 27570× 更快，分配少约 500000×** | 实测微基准，**理论预期** |

> ⚠️ **重要澄清（避免误解）**：`find_time`（二分查找）在重构前（`a09511a` 及更早）**已存在于** `common/head.jl`；但多数 loader（`MAVEN_SWIA.jl`、`MAVEN_load.jl`、`MAVEN_plot.jl`、`MAVEN_STATIC.jl` 及示例脚本）**仍在使用 `findmin` 线性扫描**。本次 P0–P5 重构**未改动**这些数值热路径——上表「二分 27570×」是**算法级微基准实测的理论增益**，**尚未在 loader 中落地替换**，属后续优化项（对应报告「P5 性能优化需以基准和正确性测试证明」）。

---

## 三、模块性能/行为变化小结

1. **下载管道**：性能瓶颈在网络 I/O，重构不改吞吐；收益为「下载后索引刷新从『永不触发』变为『显式触发』」的正确性修复。
2. **配置层**：INI→TOML 读取略快（~1.38×）且更健壮；新增 `config/paths.py` 统一路径解析，消除 CWD 依赖。
3. **索引层**：原子写（临时文件 + `os.replace`）避免半写索引，代价为一次同目录重命名（微秒级，可忽略）；`schema_version` 使索引可演进。
4. **维护/删除类**：新增 `dry_run=True` 默认 + 显式 `--apply`，安全性提升，吞吐不变。
5. **Julia 加载器**：路径解析单点化（`common/paths.jl`/`MarsData`），加载核心逻辑未变；`findmin→find_time` 为**未落地的理论优化**。
6. **包化**：`martian_pipeline` 加式薄封装，`python -m` 统一入口，旧脚本 `python download_data/xxx.py` 仍可用，无性能回归。

---

## 四、遗留与后续优化建议

- 将 `findmin(abs.(x .- x0))` 逐点替换为 `find_time`（二分，~27000× 增益）——需以样本数据回归验证 loader 输出逐键一致后再落地。
- 索引 v2 当前为「扁平 + 元数据」，报告 2.3-② 的嵌套 `products{root_key,product_path,pattern,files,count}` 属可选增强（`product_path/pattern` 与注册表冗余）。
- 完整 `Project.toml` 需装齐全部直接依赖（含 `LsqFit`）后取代 `requirement.jl`。
- 中文文件名 ASCII 化、`eval(Meta.parse)` 显式注册、`download_files.py` 的 `Server_ind=1` 残留、`KP_vars.json` 移除为低优先级整理。
