# 更新日志

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
