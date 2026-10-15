# 读取和计算天问一号数据
# 使用load_MAVEN_data函数做全局读取

module TW_load
include(joinpath(@__DIR__, "..", "common", "constants.jl"))
include(joinpath(@__DIR__, "..", "common", "MarsCommon.jl"))
include(joinpath(@__DIR__, "..", "common", "paths.jl"))
using .Paths
root_path = Paths.tw_data_root()  # 数据根目录由 config/settings.toml 配置
using Dates

# function load_mag(file::String);#弃用，以dlm方法为准

#     lines=readlines(file)
#     lines = lines[20:end]

#     nums = length(lines)
#     times = Vector{DateTime}(undef,nums)
#     B = Matrix{Float32}(undef,nums,3)
#     position = Matrix{Float32}(undef,nums,3)
#     flag = Vector{Int32}(undef,nums)
    
#     @inbounds for (i,line) in enumerate(lines)
#         times[i],B[i,:],position[i,:],flag[i] = get_data_from_line(line)
#     end

#     B_total = sqrt.(sum(B.^2, dims=2)); B_total = B_total[:,1]

#     data=Dict(
#         "data staute" => true,
#         "Var name" => "time[Ntime], B_total[Ntime],B[Ntime,3],position[Ntime,3]",
#         "Vars"     => [times,B_total,B,position],
#         "flag"     => flag
#     )
#     # data = MGS_mag(true,times,B_total,B,position)
#     return data
# end
# function get_data_from_line(line::String)
#     epoch = DateTime(line[1:23], DateFormat("y-m-dTH:M:S.s"))
#     # data_t = [line[33:44],line[45:56],line[57:68],line[69:79],line[80:90],line[91:101]]
#     bx = parse(Float32,line[33:44])
#     by = parse(Float32,line[45:56])
#     bz = parse(Float32,line[57:68])
#     x = parse(Float32,line[69:79])
#     y = parse(Float32,line[80:90])
#     z = parse(Float32,line[91:101])
#     iflag = parse(Int32,line[139:140])
#     return epoch,[bx,by,bz],[x,y,z],iflag
# end
using DelimitedFiles,DataFrames
"""
    load_mag_2c_bydlm(file::String) -> Dict{Symbol, Any}

读取并整理天问一号磁场 2C 数据文件（文本格式，前 19 行为表头）。

# 功能与算法概述
用 `readdlm`+`DataFrame` 载入并按固定列名重命名，解析时间、去重排序后
抽出磁场/位置/姿态/质量标志，并计算旋磁总强度 `B_total`。

# 参数说明
- `file::String`: 天问 2C 磁场文件的路径。

# 返回值
- `Dict{Symbol, Any}`: 含 `:time`/`:epoch`、`:B`、`:B_total`、`:position`、`:flag`、`:yaw`/`:pitch`/`:roll` 与 `:data_load_flag` 的字典（磁场 nT、位置 km）。

# 注意事项
- 文件被截断/字段缺失时 `readdlm` 会直接报错，本函数不做容错。
- 代码中针对 `NaN` 的线性插值修复逻辑目前被注释掉。
"""
function load_mag_2c_bydlm(file::String);
    mag2c1hz = identity.(DataFrame(readdlm(file, skipstart=19), :auto))
    name = ["Time", "Sampling_Rate", "X_MSO", "Y_MSO", "Z_MSO", "Probe_Position_X_MSO", "Probe_Position_Y_MSO", "Probe_Position_Z_MSO", "Roll", "Pitch", "Yaw",  "Quality_Flags"]
    rename!(mag2c1hz, name)
    mag2c1hz[!, :Time] = map(x->DateTime(x[begin:end-4], DateFormat("y-m-dTH:M:S.s")), mag2c1hz[!, :Time])
    unique!(mag2c1hz) #remove depulicate rows
    sort!(mag2c1hz) #sorting

    times = mag2c1hz[!, :Time]
    BMSO1hz = mag2c1hz[:, [:X_MSO, :Y_MSO, :Z_MSO]]
    position = mag2c1hz[:, [:Probe_Position_X_MSO, :Probe_Position_Y_MSO, :Probe_Position_Z_MSO]]
    roll = mag2c1hz[!, :Roll]
    pitch = mag2c1hz[!, :Pitch]
    yaw = mag2c1hz[!, :Yaw]
    flag = mag2c1hz[:, :Quality_Flags]
    # ind0 = findall(x-> !isnan(x), BMSO1hz[!, 1] )
    # ind1 = findall(x-> isnan(x), BMSO1hz[!, 1] )
    # if length(ind1) >= 1 && length(ind0) > 1
    #     for ib in 1:3 
    #         interp_linear = linear_interpolation(magut1hz[ind0], BMSO1hz[ind0, ib]; extrapolation_bc=Line())
    #         BMSO1hz[ind1, ib] = interp_linear(magut1hz[ind1])
    #     end
    # end

    B_total = sqrt.(BMSO1hz[:,:X_MSO].^2 + BMSO1hz[:,:Y_MSO].^2 + BMSO1hz[:,:Z_MSO].^2); B_total = B_total[:,1]

    data=Dict{Symbol,Any}(
        :data_load_flag => true,
        :time => times |> Array,
        :epoch => times |> Array,
        :B => BMSO1hz |> Array,
        :B_total => B_total |> Array,
        :position => position |> Array,
        :flag     => flag |> Array,
        :yaw => yaw |> Array,
        :pitch => pitch |> Array,
        :roll => roll |> Array,
    )
    return data
end

"""
    calculate_mag(position; models=["alt"])

根据位置矩阵计算天问数据的海拔、地方时、纬度辅助量。

# 功能与算法概述
以名称到 `MarsCommon` 位置派生函数的映射表为基础，遍历 `models` 逐个求值并写入结果字典。

# 参数说明
- `position`: `N×3` 的位置矩阵（通常为 MSO 坐标，单位 km）。
- `models`: 需要计算的物理量名称列表，默认只算 `"alt"`。

# 返回值
- `Dict`: 以 `model` 名称为键的结果字典。

# 注意事项
- 函数体中直接引用了**未定义**的全局变量 `data`（缺少初始化），直接调用会报 `UndefVarError`。
- `MarsCommon` 需已在调用环境中引入。
"""
"""
    get_spc2mso_rot_matrix_via_2c(dat) -> (Vector{DateTime}, Array{Float64,3})

由天问姿态角（Roll/Pitch/Yaw）构造星座系（SC）到 MSO 系的旋转矩阵时间序列。

# 功能与算法概述
把三个欧拉角由度转弧度后，逐时刻按 Z-Y-X（Yaw-Pitch-Roll）顺序写出
`ntime×3×3` 旋转矩阵，并与时间向量一起返回。

# 参数说明
- `dat::Dict`: `load_mag_2c_bydlm` 的返回值，需含 `:time`、`:pitch`、`:yaw`、`:roll`。

# 返回值
- `(times, rot_matrix)`: 时间向量与 `ntime×3×3` 的旋转矩阵数组。

# 注意事项
- 用法：`B_mso[i, :] = rot_matrix[i, :, :] * B_sc[i, :]`。
- 公式假定标准 YPR 约定；若天问定义不同（例如符号约定差异），需校对矩阵元素。
"""
function get_spc2mso_rot_matrix_via_2c(dat) # 需要load_mag_2c_bydlm的返回值\
    ntime = length(dat[:time])
    rot_matrix = zeros(ntime,3,3)

    local pitch = dat[:pitch].|>deg2rad
    local yaw   = dat[:yaw]  .|>deg2rad
    local roll  = dat[:roll] .|>deg2rad
    rot_matrix = zeros(Float64, ntime, 3, 3)
    for i in 1:ntime
        local r,p,y = roll[i],pitch[i],yaw[i]
        local cp = cos(p)
        local sp = sin(p)
        local cy = cos(y)
        local sy = sin(y)
        local cr = cos(r)
        local sr = sin(r)
        rot_matrix[i,1,:] = [cp*cy, sy*cr+sr*sp*cy, sr*sy-cr*sp*cy]
        rot_matrix[i,2,:] =  [-cp*sy, cr*cy-sr*sp*sy, sr*cy+cr*sp*sy]
        rot_matrix[i,3,:] = [sp, -sr*cp, cr*cp]
    end
    return dat[:time],rot_matrix
end
"""
    read_list() -> Vector{String}

读取天问磁场本地文件清单（`mag_list.txt`）并拼上根目录，返回完整路径。

# 功能与算法概述
逐行读取清单中的相对路径，再用 `joinpath` 与 `root_path` 组合。

# 参数说明
- 无参数；依赖本文件顶部的全局 `root_path`。

# 返回值
- `Vector{String}`: 所有磁场数据文件的完整路径。

# 注意事项
- `root_path` 经 `common/paths.jl` 解析（`Paths.tw_data_root()`，由
  `config/settings.toml` 的 `paths.tw_data_root` 配置）。
- 清单文件不存在时会报 `SystemError`。
"""
function read_list()
    list_path = joinpath(root_path, "List", "mag_list.txt")
    files = readlines(list_path)
    files = joinpath.(root_path, files)
    return files
end

end
