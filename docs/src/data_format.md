# MAVEN 各数据包内容格式

产品名、读取函数与文件名模式以 `MAVEN_data/MAVEN_data_format.json` 中的 `data_model` 为准；下方产品表由 `MAVEN_data/build_read_me.py` 根据该注册表生成。各 loader 返回的字段与维度依产品而异，不能仅凭文件格式推断完整数据结构。

## STATIC 系列示例

当前入口通过 MarsData 模块装载器绑定读取器与 STATIC 处理模块。此例需要本机已配置数据目录、索引和目标日文件；`time_ind` 是该日时间轴上要选取的 Julia 1-based 索引：

```julia
using MarsData, Dates
MarsData.@load MAVEN_load MAVEN_STATIC

errors = String[]
loaded = MAVEN_load.load_MAVEN_data(
    DateTime(2015, 2, 9);
    model_index=["STATIC_cf"],
    error_report=errors,
)
sta_data = loaded["STATIC_cf"]
sta_data[:data_load_flag] || error("STATIC_cf 读取失败: $(join(errors, "; "))")

# 确认这个具体产品含当前 STATIC 处理函数所需的标准键。
# CDF 变量名/维度依文件而异；注册表本身不保证字段契约。
required = [
    :epoch, :swp_ind, :att_ind, :eff_ind, :eflux, :data, :bkg,
    :time_integ, :sc_pot, :quality_flag, :dead, :mode, :bins_sc,
    :quat_mso, :quat_sc, :magf, :pos_sc_mso, :energy, :denergy,
    :theta, :phi, :dtheta, :dphi, :mass_arr, :gf, :eff,
    :geom_factor, :nbins, :nenergy, :nmass, :valid,
]
missing = filter(key -> !haskey(sta_data, key), required)
isempty(missing) || error("STATIC_cf 缺少当前示例所需字段: $missing")
all(key -> sta_data[key] isa Int16, (:nbins, :nenergy)) ||
    error("STA_count2df 要求 :nbins 和 :nenergy 为 Int16")

time_ind = 1  # 按实际 epoch 选择索引
sta_slice = MAVEN_STATIC.static_slip(sta_data, time_ind)
sta_mso = MAVEN_STATIC.static_rotation(sta_slice; frame="MSO")
MAVEN_STATIC.STA_count2df(sta_mso)  # 原地写入 :df_mass_mass 与 :df；需要 geom_factor 等键
vel, flux, density = MAVEN_STATIC.sta_v_4d(
    sta_mso; energy_range=[0, 1e4], mass_range=[0, 2], m_int=1,
    unit_cover=false,
)
velocity_grid = MAVEN_STATIC.static_slip_2_V(
    sta_mso; mass_range=[0, 2], m_int=1,
)
```

`static_slip` 取单时刻切片；`static_rotation` 只旋转角度网格和磁场，不会将计数换算为 `:df`。`STA_count2df` 需要单时刻切片中的 `:nbins`、`:nenergy`、`:energy`、`:gf`、`:eff`、`:geom_factor`、`:time_integ`、`:mass_arr`、`:dead`、`:bkg`、`:data`，会原地写入 `:df_mass_mass` 和 `:df`；随后 `sta_v_4d(unit_cover=false)` 从 `:df_mass_mass` 取值。`sta_v_4d` 另要求 `:valid`。上例先检查这些步骤依赖的键是否存在；键存在不证明实际 CDF 的形状、数值类型或科学含义符合预期，真实产品布局仍需以文件核实。`sta_v_4d` 返回速度（km/s）、通量（cm⁻²·s⁻¹）和密度（cm⁻³）。示例参数仅演示调用方式，质量窗和能量窗应依科学目标选择。

质量相关键必须按具体函数解释：STATIC 输入的测量质量轴是 `:mass_arr`（`MarsData.DataKeys.MASS_ARR` 键名为 `:mass_arr`），不是 `:mass`。`STA_count2df` 以常量 `constants.mp_eV_per_km_s2` 作为质子质量基准，不读取输入 `dat[:mass]`。`static_slip_2_V` 的返回字典把 `:mass` 设为传入的 `m_int`；`static_c6_energy_mean` 的返回字典则把 `:mass` 设为由质量轴计算出的 `mass_out` 数组（该函数注释给出的形状是 `nmass×nswp`）。两处同名键语义不同，不应笼统称作质量谱。上例 `velocity_grid` 还依赖切片中的 `:eflux` 等字段。STATIC 文件中的 `swp_ind` 从 0 计数，切片代码将其加 1 后用于 Julia 索引；STATIC 角度约定见 `MAVEN_data/MAVEN_STATIC.jl` 模块说明。坐标旋转与质量处理是不同步骤。

角度的球坐标约定和各数据集字段需结合产品说明及 `MAVEN_data/MAVEN_STATIC.jl` 中函数文档核实。

## MAG 系列

MAG 原始 `.sts` 产品由 `MAVEN_load.load_mag_l2` 读取；注册表还列出 CDF 变体和派生产品。坐标系由产品 ID/数据字段表明，例如 `MAG_ss` 表示 MSO，`MAG_pc` 表示 PC。转换必须由明确的产品或处理函数完成，不应把不同坐标产品视为同一坐标数据。

## KP

KP 产品有不同版本，变量排布应结合版本字段与对应说明解释。当前产品注册表给出文件和 loader 映射；KP 列映射由读取器配置维护。不要依赖历史文档中未确认的二进制字段布局作为当前接口约定。

## 其他派生产品字段

- `MAG` 的 `.sts` 文件由 `load_mag_l2` 解析，返回 `:epoch`、`:type`、`:B`（时间×3）、`:B_total` 和 `:position`（时间×3）。产品 ID 的 `ss`/`pc` 表示注册表中的坐标产品；该 loader 的返回字典不附加 `:coordinate` 字段。
- `MAG_ss1s_vsc` 由 `load_mag_vsc` 读取，字段包括 `:epoch`、`:time_unix`、`:vsc` 和 `:position`。
- `STATIC_d1_v4d` 的 `load_d1_v4d` 返回各离子分量的速度、密度和通量，以及 `:P_mso`、`:B_mso`、`:quality_flag`、`:mode`、`:mass_range` 等字段；确切键以该 loader 当前实现为准。
- STATIC 的 `static_c6_mass_mean` 按 `mass_range` 对质量轴求和；`static_c6_energy_mean` 按能量窗汇总并计算质量轴。前者的结果不含 `:mass`，后者的 `:mass` 是质量轴数组。两者只在输入含 `:df` 时才输出汇总后的 `:df`。
- `SWIA_quat` 由 `load_quat` 读取，含 `:epoch`、`:time_unix`、`:quat` 和由文件名给出的 `:coordinate`。

## 数据下载与索引

下载布局、扫描更新索引和维护命令见 [pipeline.md](pipeline.md)。`filename_lists.json` 是读取器按需查询的文件清单；文件列表更新后应重新扫描/刷新索引。架构边界见 [architecture.md](architecture.md)，旧 API 迁移见 [migration.md](migration.md)。

## SPADES 备注

闰秒相关的 SPADES 处理限制属于特定数据/处理流程，使用前应核对实际算法及来源；本页不将历史备注提升为所有 MAVEN 产品通用的时间处理规则。

## 已支持数据类型
MAVEN数据模块名列表
|模型名|描述|读取函数|名称格式|
|---|---|---|---|
|KP|KP datas|load_kp|^mvn_kp_insitu_.+\.tab$|
|KP_cdf|KP data in cdf, bulid by MAVEN_data/Build_data/KP2cdf.py|load_cdf|^mvn_kp_insitu_.+\.cdf$|
|MAG_ss|mag 32 Hz data in MSO|load_mag_l2|mvn_mag_l2_\d{7}ss_\d{8}_v\d{2}_r\d{2}\.sts|
|MAG_ss1s|mag 1 Hz data in MSO|load_mag_l2|mvn_mag_l2_\d{7}ss1s_\d{8}_v\d{2}_r\d{2}\.sts|
|MAG_pc|mag 32 Hz data in PC|load_mag_l2|mvn_mag_l2_\d{7}pc_\d{8}_v\d{2}_r\d{2}\.sts|
|MAG_pc1s|mag 1 Hz data in PC|load_mag_l2|mvn_mag_l2_\d{7}pc1s_\d{8}_v\d{2}_r\d{2}\.sts|
|MAG_ss_cdf|mag 32 Hz data in MSO (cdf)|load_cdf|mvn_mag_l2_\d{7}ss_\d{8}_v\d{2}_r\d{2}\.cdf|
|MAG_ss1s_cdf|mag 1 Hz data in MSO (cdf)|load_cdf|mvn_mag_l2_\d{7}ss1s_\d{8}_v\d{2}_r\d{2}\.cdf|
|MAG_pc_cdf|mag 32 Hz data in PC (cdf)|load_cdf|mvn_mag_l2_\d{7}pc_\d{8}_v\d{2}_r\d{2}\.cdf|
|MAG_pc1s_cdf|mag 1 Hz data in PC (cdf)|load_cdf|mvn_mag_l2_\d{7}pc1s_\d{8}_v\d{2}_r\d{2}\.cdf|
|MAG_ss1s_vsc|spacecraft velocity calculated from mag data (binary)|load_mag_vsc|mvn_mag_vsc_ss1s_\d{8}_v\d{2}_r\d{2}\.f77_unformatted|
|SWEA_spec|SWEA l2 survey spectra|load_cdf|mvn_swe_l2_svyspec_.+\.cdf|
|SWEA_pad_arc|SWEA l2 arc pad|load_swea_pad|mvn_swe_l2_arcpad_.+\.cdf|
|SWEA_pad_svy|SWEA l2 survey pad|load_swea_pad|mvn_swe_l2_svypad_.+\.cdf|
|SWEA_arc3d|SWEA l2 arc 3d|load_cdf|mvn_swe_l2_arc3d_.+\.cdf|
|SWEA_svy3d|SWEA l2 svy 3d|load_cdf|mvn_swe_l2_svy3d_.+\.cdf|
|SEP_anc| |load_cdf|mvn_sep_l2_anc_.+\.cdf|
|SEP_counts| |load_cdf|mvn_sep_l2_s1-raw-svy-full_.+\.cdf|
|SEP_spec| |load_cdf|mvn_sep_l2_s1-cal-svy-full_.+\.cdf|
|STATIC_c6|STATIC c6 32e64m|load_cdf|mvn_sta_l2_c6-32e64m_.+\.cdf|
|STATIC_c8|STATIC c8 32e16d|load_cdf|mvn_sta_l2_c8-32e16d_.+\.cdf|
|STATIC_ca|STATIC ca 16e4d16a|load_cdf|mvn_sta_l2_ca-16e4d16a_.+\.cdf|
|STATIC_cf|STATIC cf 16e4d16a16m|load_cdf|mvn_sta_l2_cf-16e4d16a16m_.+\.cdf|
|STATIC_d0|STATIC d0 32e4d16a8m|load_cdf|mvn_sta_l2_d0-32e4d16a8m_.+\.cdf|
|STATIC_d1|STATIC d1 32e4d16a8m|load_cdf|mvn_sta_l2_d1-32e4d16a8m_.+\.cdf|
|STATIC_d1_v4d|STATIC d1 velocity flux (MSO) density (binary), include magnetic field and position data in MSO|load_d1_v4d|mvn_sta_l3_d1_v4d_.+\.f77_unformatted|
|STATIC_d1_v4d_cold|STATIC d1 velocity flux density (binary)|load_d1_v4d|mvn_sta_l3_d1_v4d_cold.+\.f77_unformatted|
|STATIC_d1_v4d_heat|STATIC d1 velocity flux density (binary)|load_d1_v4d|mvn_sta_l3_d1_v4d_heat.+\.f77_unformatted|
|STATIC_c6_v3d|STATIC c6 velocity flux density (binary)|load_c6_v3d|mvn_sta_l3_c6_v3d_.+\.jld2|
|LPW_wave|LPW wave passitive spectra|load_cdf|mvn_lpw_l2_wspecpas_.+\.cdf|
|LPW_wave_act|LPW wave active spectra|load_cdf|mvn_lpw_l2_wspecact_.+\.cdf|
|LPW_mrgscpot|LPW merged spacecraft potential|load_cdf|mvn_lpw_l2_mrgscpot_.+\.cdf|
|LPW_lpiv|LPW lp iv|load_cdf|mvn_lpw_l2_lpiv_.+\.cdf|
|LPW_lpnt|LPW lp nt|load_cdf|mvn_lpw_l2_lpnt_.+\.cdf|
|LPW_wn|LPW w n|load_cdf|mvn_lpw_l2_wn_.+\.cdf|
|LPW_we12|LPW 1D wave|load_cdf|mvn_lpw_l2_we12_.+\.cdf|
|LPW_bursthf| |load_cdf|mvn_lpw_l2_we12bursthf_.+\.cdf|
|LPW_burstmf| |load_cdf|mvn_lpw_l2_we12burstmf_.+\.cdf|
|LPW_burstlf| |load_cdf|mvn_lpw_l2_we12burstlf_.+\.cdf|
|NGIMS_sht_l3|L3 resampled scale height table|load_NGIMS_sht_l3|mvn_ngi_l3_res-sht-.+\.csv|
|NGIMS_sht_l4|combined resampled scale height table|load_NGIMS_sht_l3|mvn_ngi_l4_res-sht-.+\.csv|
|NGIMS_den_l3|L3 resampled average denity table|load_NGIMS_den_l3|mvn_ngi_l3_res-den-.+\.csv|
|NGIMS_den_l4| |load_NGIMS_den_l3|mvn_ngi_l4_res-den-.+\.csv|
|SWIA_mom| |load_cdf|mvn_swi_l2_onboardsvymom_.+\.cdf|
|SWIA_svy_spec| |load_cdf|mvn_swi_l2_onboardsvyspec_.+\.cdf|
|SWIA_fine_svy_3d| |load_cdf|mvn_swi_l2_finesvy3d_.+\.cdf|
|SWIA_fine_arc_3d| |load_cdf|mvn_swi_l2_finearc3d_.+\.cdf|
|SWIA_coarse_svy_3d| |load_cdf|mvn_swi_l2_coarsesvy3d_.+\.cdf|
|SWIA_coarse_arc_3d| |load_cdf|mvn_swi_l2_coarsearc3d_.+\.cdf|
|EUV_l2_bands| |load_cdf|mvn_euv_l2_bands_.+\.cdf|
|EUV_l3_minute|EUV minute averaged data|load_cdf|mvn_euv_l3_minute.+\.cdf|
|EUV_l3_daily|EUV daily averaged data|load_cdf|mvn_euv_l3_daily.+\.cdf|
|SWIA_quat|quat data of SWIA to MSO|load_quat|mvn_spice_swia_qu_.+\.csv|
