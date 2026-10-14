"""
    DataKeys

数据键契约常量模块（ARCH-011）。

本模块把散落各处的 `Dict{Symbol,Any}` 键名集中为编译期常量，
新代码与重构触及代码应优先使用这些常量，避免拼写漂移导致的运行时 KeyError。

常量名采用大写下划线形式，对应值多为 Symbol（legacy 字符串键保留原类型）。
形状/单位/语义详见 `.agent/03_ARCHITECTURE_PLAN.md` 附录 A。
"""
module DataKeys

# ---------------------------------------------------------------------------
# 时间与加载元数据
# ---------------------------------------------------------------------------

"观测时间（CDF 源），`Vector{DateTime}`"
const EPOCH = :epoch

"观测时间（文本源，如 KP/MAG_l2/TW/MGS），`Vector{DateTime}`"
const TIME = :time

"Unix 时间，`Vector{Float64}`，单位 s"
const TIME_UNIX = :time_unix

"加载成功标志，`Bool`"
const DATA_LOAD_FLAG = :data_load_flag

"源文件路径，`String`"
const FILENAME = :filename

# ---------------------------------------------------------------------------
# 场与位置
# ---------------------------------------------------------------------------

"磁场矢量，`N×3`，单位 nT"
const B_FIELD = :B

"磁场模，`Vector`，单位 nT"
const B_TOTAL = :B_total

"位置，`N×3`，单位 km（MSO）"
const POSITION = :position

# ---------------------------------------------------------------------------
# 能道与分布函数
# ---------------------------------------------------------------------------

"能道中心，形状见附录 A，单位 eV"
const ENERGY = :energy

"能道宽度，形状见附录 A，单位 eV"
const DENERGY = :denergy

"相空间密度，`1/(cm³·(km/s)³)`（SPEDAS 约定）"
const DF = :df

"微分能量通量，`1/(cm²·s·eV·sr)` 类"
const EFLUX = :eflux

"微分通量（SWEA/SWIA），形状因仪器而异"
const DIFF_EN_FLUXES = :diff_en_fluxes

# ---------------------------------------------------------------------------
# 姿态 / 电位 / 索引 / 网格元数据
# ---------------------------------------------------------------------------

"姿态四元数，`Vector{QuatRotation}`"
const QUAT_MSO = :quat_mso

"航天器电位，标量或向量，单位 eV"
const SC_POT = :sc_pot

"扫参索引，`Vector{Int}`"
const SWP_IND = :swp_ind

"姿态索引，`Vector{Int}`"
const ATT_IND = :att_ind

"效率索引，`Vector{Int}`"
const EFF_IND = :eff_ind

"质量数组（STATIC 网格元数据）"
const MASS_ARR = :mass_arr

"质量数（STATIC 网格元数据）"
const NMASS = :nmass

"扫参数（STATIC 网格元数据）"
const NSWP = :nswp

"能道数（STATIC 网格元数据）"
const NENERGY = :nenergy

"bin 数（STATIC 网格元数据）"
const NBINS = :nbins

# ---------------------------------------------------------------------------
# 磁力线追踪输出
# ---------------------------------------------------------------------------

"磁力线弧长，`Vector`，单位 km"
const S = :S

"海拔，`Vector`，单位 km"
const ALT = :alt

# ---------------------------------------------------------------------------
# Legacy 字符串键（仅登记，不强制重命名）
# ---------------------------------------------------------------------------

"历史 get_mag_line_s 输入键（legacy 字符串键）"
const B_FIELD_LEGACY = "B"

"MGS 旧字典键（legacy 字符串键）"
const VARS_LEGACY = "Vars"

"MGS 旧状态键（legacy 字符串键）"
const DATA_STATUS_LEGACY = "data staute"

# 对外只导出 Symbol 型契约键；legacy 字符串键保留在模块内备查。
export EPOCH, TIME, TIME_UNIX, DATA_LOAD_FLAG, FILENAME,
       B_FIELD, B_TOTAL, POSITION,
       ENERGY, DENERGY, DF, EFLUX, DIFF_EN_FLUXES,
       QUAT_MSO, SC_POT, SWP_IND, ATT_IND, EFF_IND,
       MASS_ARR, NMASS, NSWP, NENERGY, NBINS,
       S, ALT

end # module
