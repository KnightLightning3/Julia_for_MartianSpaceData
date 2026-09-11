# 读取和计算支持数据，如omni2，太阳风参数推导等
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
module SP_load
using TimesDates
using CSV, DataFrames, Dates
using JSON
using IniFile
using Statistics
using Rotations

const Q = 1.602176487e-19 # 库仑
const EV = 1.602176487e-19
const C = 3.0e8
const Me = 9.109e-31
const Mp = 1.672621637e-27
const RADG = 180.0 / π

dir = dirname(@__FILE__)
root_path = get(read(Inifile(), dirname(dir) * "/download_data/MAVEN_download_config.ini"), "DEFAULT", "Save_dir") # 所有文件的根目录
println(dirname(dir) * "/download_data/MAVEN_download_config.ini")
# -------------------------Read filelist parts-------------------------
function load_omni2_data(;)
    local file_path = root_path*"support_datas/omni2_all_years.dat"
    col_names = [
        "Year", "DOY", "Hour", "Bartels", "IMF_ID", "SW_ID", "IMF_Points", "Plasma_Points",
        "B_Avg", "B_Vec_Mag", "B_Lat", "B_Long", "Bx_GSE", "By_GSE", "Bz_GSE", "By_GSM", "Bz_GSM",
        "sigma_B_Mag", "sigma_B_Vec", "sigma_Bx", "sigma_By", "sigma_Bz",
        "T", "n", "V", "Phi_V", "Theta_V", "Alpha_Proton", "Pressure", "sigma_T",
        "sigma_n", "sigma-V","sigma-phi-V","sigma-theta-V","sigma-ratio",
        "Electric field",
        "Plasma beta","Alfven mach number",
        "Kp_10",
        "R",
        "DST Index ",
        "AE-index",
        "PROT Flux1MeV",
        "PROT Flux2MeV",
        "PROT Flux4MeV",
        "PROT Flux10MeV",
        "PROT Flux30MeV",
        "PROT Flux60MeV",
        "MSPH Flux Flag",
        "ap-index",
        "f10.7_index",
        "PC_N",
        "AL-index",
        "AU-index",
        "MAC",
        # "Daily Solar Lyman-alpha",
        # "Proton Quasy-Invariant",
    ]# https://omniweb.gsfc.nasa.gov/html/ow_data.html

    # 2. 高速读取
    # OMNI 文件列数非常多且固定，使用 ignorerepeated=true 处理空格
    df = CSV.read(file_path, DataFrame; 
                  header = col_names,
                  delim = ' ', 
                  ignorerepeated = true,
                  normalizenames=true,
                  skipto = 1)

    # 3. 时间转换 (Year + DOY + Hour -> Unix Time)
    # OMNI 的 Hour 是 0-23，DOY 从 1 开始
    function row_to_datetime(y, d, h)
        # 注意：OMNI 的小时代表该小时的平均值（例如 1 代表 01:00 到 02:00）
        # 这里统一取起始时间
        dt = DateTime(Int(y)) + Day(Int(d) - 1) + Hour(Int(h))
        return datetime2unix(dt)
    end

    df.time_unix = row_to_datetime.(df.Year, df.DOY, df.Hour)

    return df
end
function load_drivers_merge_data(;high_res = true) # 读取Halekas等人推导的太阳风参数文件
    # UT, n_proton, n_alpha (per cc), |v_proton|, vx, vy, vz (km/s), T_proton (eV), Bx, By, Bz (nT).
    #  "2014-11-12/11:48:47     2.204     0.131   426.555  -426.431     9.984    -2.617     8.831    -0.232     1.644    -0.331"

    if high_res
        file_path = root_path*"support_datas/drivers_merge_l2_hires.txt"
    else
        file_path = root_path*"/support_datas/drivers_merge_l2.txt"
    end
    col_names = [
        "UT_str", "n_p", "n_alpha", "v_mag", "vx", "vy", "vz", "T_p", "Bx", "By", "Bz"
    ]#UT, n_proton, n_alpha (per cc), |v_proton|, vx, vy, vz (km/s), T_proton (eV), Bx, By, Bz (nT).
    local df = CSV.read(file_path, DataFrame; 
                  header=col_names, 
                  delim=' ', 
                  ignorerepeated=true, 
                  types=Dict(
                    1 => String,
                    2 => Float32,
                    3 => Float32,
                    4 => Float32,
                    5 => Float32,
                    6 => Float32,
                    7 => Float32,
                    8 => Float32,
                    9 => Float32,
                    10 => Float32,
                    11 => Float32,
                    )) # 唯独第1列日期保持 String

    # 3. 矢量化转换时间（这是 DataFrames 的优势，非常快）
    dt_format = dateformat"yyyy-mm-dd/HH:MM:SS"
    df.time_unix = datetime2unix.(DateTime.(df.UT_str, dt_format))
    return df
end


end # module