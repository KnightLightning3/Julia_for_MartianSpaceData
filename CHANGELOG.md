# 更新日志

本项目所有值得注意的变更都会记录在此文件。

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
