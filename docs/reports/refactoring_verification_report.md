# 重构前后功能与性能校验结果报告

> 生成日期：2026-10-13
> 对比基准：重构前 `a09511a` vs 重构后 `HEAD`
> 测试分工：DeepSeek Flash（测试验证主导）+ Qwen 3.8 Max（配合）+ DeepSeek Pro（架构复核）

---

## 一、沙箱 / 临时目录隔离声明

本次全部校验**严格遵守以下安全边界**：

1. **不对真实科学数据执行破坏性覆盖、删除或批量操作**：所有涉及文件写入/删除的验证均使用 `tempfile.mkdtemp()` 临时目录与合成文件，验证结束即 `shutil.rmtree` 清理。
2. **不进行真实网络下载**：下载类脚本（`MAVEN_download.py`/`download_files.py`）仅做 AST 静态校验与「可导入」验证，不触发真实网络请求。
3. **构建器（Build_data）不运行真实 CDF 转换**：`KP重构为cdf.py`/`磁场重构为CDF文件.py` 依赖 `spacepy.pycdf`（NASA CDF 库），本机无法导入，故仅对其**纯路径/原子写逻辑**做静态校验与单元测试，不做运行时转换。
4. **Julia 侧不加载真实数据**：`Pkg.instantiate`、`using MarsData`、`common/head.jl` 语法解析均不读取科学数据文件。

---

## 二、逐项校验执行结果

### 验证项 A：配置与路径解析

| 校验点 | 方法 | 结果 |
|---|---|---|
| TOML 唯一写端 + INI 只读兼容 | `tests/test_p1.py`（`load_config` 读临时 TOML / 旧 INI 映射） | ✅ 6/6 |
| `check_download_file` 契约键补齐 | 临时 INI 生成后逐条复刻下载器读序 | ✅ 键存在且默认 False |
| `config/paths.py` 路径统一（CWD 无关） | `test_paths_cwd_independent` | ✅ chdir 后路径一致 |
| 迁移 dry-run 幂等、不搬数据 | `tests/test_p1.py` + `python tools/migrate_config.py`（真实 INI dry-run） | ✅ 正确识别 `Server_ind=3`、4 URL、`Aria2c` |
| Julia `common/paths.jl` TOML 分支 + INI 回退 | `julia` 冒烟 | ✅ 三任务根路径正确 |

**结论：A 通过。**

### 验证项 B：扫描与索引刷新

| 校验点 | 方法 | 结果 |
|---|---|---|
| 扫描写出 `lists/<model>_list.txt` | `tests/test_p0.py`（合成树） | ✅ 6/6 |
| 索引生成（空目录/未知模型/正则无匹配/路径分隔符） | `tests/test_p2_cli.py`（5 用例） | ✅ 5/5 |
| 索引 v2（`schema_version`+`generated_at`）读写 | `tests/test_p3.py` | ✅ 6/6 |
| 旧 `filename_lists.json` 读兼容（`load_index` 读适配器） | `test_load_index_legacy` | ✅ 旧扁平格式可读 |
| 下载后索引刷新（显式 `check_exist_files.main()`，替代失效的 `runpy`） | `test_main_refreshes_index` | ✅ 刷新产出正确索引 |

**结论：B 通过。**

### 验证项 C：Python 管道与 Build_data 构建器

| 校验点 | 方法 | 结果 |
|---|---|---|
| 管道可组合（无 `runpy`/`exit(0)` 进程副作用） | 全仓 grep（仅存 `sys.exit(1)` 于 `__main__` 错误分支/test runner） | ✅ |
| `martian_pipeline` CLI 端到端 | `python -m martian_pipeline scan/manifest/migrate/check/clean` | ✅ scan 产出 `schema_version=2` 索引；check 只报告；clean dry-run 不删除 |
| 构建器输出路径注册表化 | `config/paths.py::resolve_output_product` + `tests/test_p3.py` | ✅ MAG_ss→MAG_ss_cdf/MAG/l3/，KP→KP_cdf/KP/cdf/，输出文件名可被对应正则发现 |
| 构建器字符串手术移除 + 原子替换 | `磁场重构为CDF文件.py`/`KP重构为cdf.py` AST + `os.replace` 检查 | ✅ 静态通过 |
| 构建器**运行时** CDF 转换 | — | ⚠️ **未验证**（依赖 `spacepy` + NASA CDF 库，本机无法导入） |

**结论：C 部分通过（运行时构建转换受依赖限制未验证，已声明）。**

### 验证项 D：Julia 端加载器与性能热点

| 校验点 | 方法 | 结果 |
|---|---|---|
| `Pkg.instantiate` | `julia --project=. -e 'using Pkg; Pkg.instantiate()'` | ✅ 成功，`MarsData` 预编译通过（修正 TOML UUID 后） |
| `using MarsData`（无数据/DLL 加载公共 API） | `julia --project=. -e 'using MarsData'` | ✅ 路径/注册表/索引解析正确 |
| `common/head.jl` 语法 | `Meta.parseall` | ✅ |
| MAVEN/TW/MGS 加载器**运行时** | — | ⚠️ **未验证**（无样本科学数据；且 `head.jl` 依赖未安装的 `LsqFit`） |
| 时间轴二分查找 `find_time` vs 线性 `findmin` | Julia `-O2` 微基准（N=1e6，合成单调时间轴） | ✅ 见下表 |

**结论：D 部分通过（包加载/语法通过；loader 运行时与真实数据回归受样本数据限制未验证）。**

---

## 三、实测性能对比数据

### 3.1 配置读取（重构前 INI vs 重构后 TOML）

| 路径 | 实现 | 平均耗时 | 相对 |
|---|---|---|---|
| 重构前 | `configparser` 读 INI | 181.9 µs/次 | 1.00× |
| 重构后 | `tomllib` 读 TOML | 131.4 µs/次 | **1.38× 更快** |

### 3.2 文件扫描与索引（重构后实测）

| 项 | 数据 | 说明 |
|---|---|---|
| `scan()` 吞吐 | **约 128.9k 文件/s**（1080 合成文件 / 8.4 ms） | 扫描核心算法（`os.listdir`+`re.match`）重构前后等价，吞吐无实质变化 |
| `write_index()` 原子写 | 10.4 ms | 相对直写新增临时文件 + `os.replace`，微秒级，可忽略 |

### 3.3 Julia 时间轴查找（微基准，N = 1,000,000 合成单调时间轴）

| 实现 | 平均耗时/查询 | 分配/查询 | 相对 |
|---|---|---|---|
| `findmin(abs.(x .- x0))`（线性，现状多数 loader） | 2.407 ms | 8.0 MB | 1× |
| `find_time`（`searchsortedfirst` 二分） | 87.3 ns | 16 B | **约 27570× 更快** |

> ⚠️ **诚实声明**：`find_time` 二分查找在重构前已存在于 `common/head.jl`；上表是**算法级微基准实测的理论增益**。本次 P0–P5 重构**未在 loader 中替换 `findmin`**（`MAVEN_SWIA.jl`/`MAVEN_load.jl`/`MAVEN_plot.jl`/`MAVEN_STATIC.jl`/示例脚本仍为线性扫描）。因此该增益**尚未兑现**，属后续性能优化项。

### 3.4 全仓静态与回归

| 项 | 结果 |
|---|---|
| Python AST | 40/40 OK（1 条 SyntaxWarning 来自 gitignored 的 `修改文件树.py`） |
| Python 回归测试 | P0 6/6、P1 6/6、P2 utils 2/2、P2 cli 5/5、P3 6/6、package 3/3 全通过 |
| git push | ✅ 全部提交已推送 `ustc/main` |

---

## 四、最终验证结论

### 结论：**通过（在声明的依赖约束范围内）**

1. **功能对齐**：Python 下载/配置/扫描/索引/维护/包化六类模块在临时目录合成数据上全部通过功能与回归测试；Julia 侧包加载（`Pkg.instantiate` + `using MarsData`）通过。
2. **性能**：本次重构的收益主要是**正确性、可组合性与安全性**（显式调用取代 `runpy`/`exit`、原子写、CWD 无关、dry-run 默认），数值热路径吞吐基本不变；配置读取 TOML 相对 INI 实测约 1.38× 更快。
3. **未落地项（如实列出）**：
   - `findmin→find_time` 二分替换：理论增益 ~27570×，**未在 loader 落地**。
   - 索引嵌套 `products` 契约、完整 `Project.toml`（需 `LsqFit`）、`download_files.py` `Server_ind=1` 残留、`KP_vars.json` 移除、`eval(Meta.parse)` 显式注册、中文文件名 ASCII 化。
4. **受环境限制未验证**：Build_data 真实 CDF 转换（`spacepy`/NASA CDF 库）、MAVEN/TW/MGS loader 真实数据运行时回归（无样本数据）、`head.jl` 全量加载（`LsqFit` 未安装）。

### 优化建议

- **优先**：以最小可再分发样本数据构造 loader 回归 fixture，将 `findmin(abs.(x .- x0))` 逐点替换为 `find_time`（二分），并以「新旧输出逐键 diff 为空」验证后落地，可兑现 ~27000× 时间轴查找加速。
- **次之**：装齐 `LsqFit` 等全部直接依赖，补齐完整 `Project.toml` 并移除 `requirement.jl`。
- **低优先级**：索引嵌套 `products`、中文文件名 ASCII 化、`eval(Meta.parse)` 显式注册。
