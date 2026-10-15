# 读取和计算MAVEN数据
# load_MAVEN_data 返回字典dates_dict[:数据类型"][:数据内容"]
# dates_dict[:数据类型"][:data_load_flag]表示读取是否成功
# 所有的CDF文件统一读取为cdf对应的字典,并去除PyObjects
# STATIC中的theta值在球坐标系下,应当为90-Theta.
# 所有物理量,如果没有说明,输入输出皆为IS单位.  运算过程中可能会有归一化
# 默认能量单位: EV. 默认粒子质量单位:AMU
using CommonDataFormat
module MAVEN_load
include(joinpath(@__DIR__, "..", "common", "constants.jl"))
include(joinpath(@__DIR__, "..", "common", "MarsCommon.jl"))
include(joinpath(@__DIR__, "..", "common", "paths.jl"))
using .Paths
using CommonDataFormat
using TimesDates, Dates
using DataFrames
using JSON
using JLD2
using Statistics
using Rotations
using FortranFiles
using Logging
# -------------------------Export parts-------------------------
export load_MAVEN_data
export mean_SWEA_pad_pa

dir = dirname(@__FILE__)
# 模块级 KP 列映射 Ref（TASK-025）：change_kp_read_data 写此处；load_kp 默认读取此处。
const _kp_dict = Ref{Dict}(Dict())
open(dir * "/MAVEN_data_format.json", "r") do f
    data = JSON.parse(f)
    _kp_dict[] = data["kp_dict"]
    global data_model = data["data_model"]
end
root_path = Paths.maven_data_root() # 配置于 config/settings.toml；根路径在 Paths 模块加载时缓存

# filename_lists.json 惰性访问器（TASK-007）：模块加载期不打开文件，调用时才读取。
# 文件缺失时返回空字典，使各模型 file_flag=false 正常容错，避免 fresh clone 崩溃。
function filename_list() :: Dict{String,Any}
    idx = Paths.index_path()
    if isfile(idx)
        return JSON.parsefile(idx)
    else
        return Dict{String,Any}()
    end
end

# 文件定位日期索引缓存（TASK-013）：每个模型首次调用时按文件名中的 8 位日期建索引，
# 后续日期命中降为 O(1)；未命中时保留原 occursin 子串扫描作为回退。
const _FILE_INDEX_CACHE = Dict{String, Dict{String, Vector{String}}}()

function _file_index(model::String)
    if haskey(_FILE_INDEX_CACHE, model)
        return _FILE_INDEX_CACHE[model]
    end
    flist = filename_list()
    filenames = get(flist, model, String[])
    FileList_path = joinpath(root_path, read_models[model][1])
    index = Dict{String, Vector{String}}()
    for fname in filenames
        full = joinpath(FileList_path, fname)
        # 取文件名中最右侧的 8 位连续数字串作为日期键（兼容更长数字串的末 8 位）
        m = match(r"\d{8}(?!\d)", fname)
        if m !== nothing
            date_key = m.match
            push!(get!(index, date_key, String[]), full)
        end
    end
    _FILE_INDEX_CACHE[model] = index
    return index
end

# -------------------------Read filelist parts-------------------------
"""
    show_load_models() -> Vector{String}

列出当前已注册可读取的所有数据模型名称。

# 功能与算法概述
遍历全局 `read_models` 的键并逐个打印，返回键数组。

# 返回值
- `Vector{String}`: 已注册模型/仪器的名称列表。
"""
function show_load_models()
    keys_arr = keys(read_models)
    for key in keys_arr
        println(key)
    end
    return keys_arr
end
"""
    file_list(model::String) -> Vector{String}

获取指定模型在本地已下载的全部文件绝对路径。

# 功能与算法概述
由全局 `read_models` 取该模型的相对子目录，再用 `joinpath` 与
`filename_list[model]` 中的文件名组合，生成完整路径数组。

# 参数说明
- `model`: 模型/仪器标识符（如 `"MAG_l2"`）。

# 返回值
- `Vector{String}`: 该模型所有文件的完整路径。

# 注意事项
- 依赖全局 `root_path`、`read_models`、`filename_list`。
"""
function file_list(model::String)
    path = read_models[model][1]
    file_path = joinpath(root_path, path)
    data = joinpath.(file_path, filename_list()[model])
    return data
end
"""
    find_file_of_data(model::String, date::DateTime) -> (Bool, String)

在指定模型的本地文件中按日期匹配目标文件。

# 功能与算法概述
把日期格式化为 `yyyymmdd`，在文件列表中以子串匹配返回首个命中的文件路径。

# 参数说明
- `model`: 模型/仪器标识符。
- `date::DateTime`: 目标日期。

# 返回值
- `(Bool, String)`: `(是否存在, 文件路径)`；未命中时路径为 `"NaN"`。
"""
function find_file_of_data(model::String, date::DateTime)
    element = Dates.format(date, "yyyymmdd")
    # TASK-013：优先走日期索引（O(1) 命中）
    idx = _file_index(model)
    hits = get(idx, element, String[])
    if !isempty(hits)
        return true, first(hits)
    end
    # 未命中则回退到原线性子串扫描（兼容无日期文件名、特殊命名等）
    flist = filename_list()
    file_list_for_model = get(flist, model, String[])
    FileList_path = joinpath(root_path, read_models[model][1])
    FileList = joinpath.(FileList_path, file_list_for_model)
    for file_name in FileList
        if occursin(element, file_name)
            return true, file_name
        end
    end
    return false, "NaN"
end
"""
    load_MAVEN_data(date::DateTime; model_index=[], show_filename=false) -> Dict{String, Any}

按日期统一调度并加载多个仪器的数据（顶级调度函数）。

# 功能与算法概述
遍历 `model_index`，用 `find_file_of_data` 定位文件后按 `read_models` 注册的读取函数动态分发；
成功时注入 `:filename` 与 `:data_load_flag => true`，失败则返回 `Dict(:data_load_flag => false)`。

# 参数说明
- `date::DateTime`: 目标数据日期。
- `model_index`: 需加载的模型标识符列表。
- `show_filename::Bool`: 是否在终端打印正在加载的文件路径。

# 返回值
- `Dict{String, Any}`: 以模型名为键、数据字典为值的主字典。

# 注意事项
- 单个文件缺失不会中断批量加载。
- `date` 参数为 `DateTime` 类型，语义为“读取该日期（一天）的数据”。
"""
function load_MAVEN_data(date::DateTime; model_index=[], show_filename=false, error_report::Vector{String}=String[]) #全局读取函数 date 格式为yyyymmdd
    datas_dict = Dict{String,Any}()
    for model in model_index
        file_flag, filename = find_file_of_data(model, date)
        if !file_flag
            push!(error_report, "$model: file not found")
            datas_dict[model] = Dict(:data_load_flag => false)
            continue
        end
        if !haskey(read_models, model)
            push!(error_report, "$model: model not registered")
            datas_dict[model] = Dict(:data_load_flag => false)
            continue
        end
        function_name = read_models[model][2]
        if show_filename
            println("\033[0;32mloading\033[0m $model from $filename\r")
        end
        try
            datas_dict[model] = function_name(filename)
            datas_dict[model][:filename] = filename
            datas_dict[model][:data_load_flag] = true
        catch e
            push!(error_report, "$model: $(sprint(showerror, e))")
            datas_dict[model] = Dict(:data_load_flag => false)
        end
    end
    return datas_dict
end
"""
    get_orbits() -> Vector

读取 `orbit_time_range.txt`，返回各轨道的编号与起止时间。

# 功能与算法概述
逐行按逗号切分，解析轨道号与两个时间字符串为元组。

# 返回值
- `Vector`: 元素为 `(orbit::Int, start::DateTime, stop::DateTime)` 的数组。

# 注意事项
- 时间字符串格式固定为 `yyyy-mm-ddTHH:MM:SS`。
"""
function get_orbits()  # 获取每个轨道对应的time_range
    file_path = joinpath(root_path, "orbit_time_range.txt")
    lines = readlines(file_path)
    data = []
    for line in lines
        items = split(line, ",")
        orbit = parse(Int, items[1])
        time_range_t = DateTime.(items[2:3], "yyyy-mm-ddTHH:MM:SS")
        push!(data, (orbit, time_range_t...))
    end
    return data
end
"""
    change_kp_read_data(kp_dict_in) -> Dict

重设 KP 变量的列映射表。

# 功能与算法概述
把输入的 `变量名 => 变量序号` 转为 `变量名 => (序号, 列区间)` 并写入模块级 Ref `_kp_dict`，
供 `load_kp` 默认使用。

# 参数说明
- `kp_dict_in`: `Dict{String,Int32}`，变量名到序号的映射。

# 返回值
- `Dict`: 更新后的列映射表。

# 注意事项
- 保留写模块 Ref 的副作用以兼容旧脚本，但**非线程安全**；新代码推荐直接通过 `load_kp(...; kp_columns=...)` 显式传入。
- 未来版本可能标记为弃用。
"""
function change_kp_read_data(kp_dict_in) # 此函数用来修改load_KP能够读取的值有哪些. 格式为Dict{String,Int32}(变量名 => 变量序号)
    kp_dict_out = Dict()
    for (key, n) in kp_dict_in
        kp_dict_out[key] = (n, n * 16 - 16 .+ (4:19))
    end
    _kp_dict[] = kp_dict_out
    return kp_dict_out
end
##----------------load parts------------------------
"""
    load_cdf(file::String) -> Dict{Symbol, Any}

读取 CDF 数据文件并全部载入内存为字典。

# 功能与算法概述
遍历 CDF 变量：`epoch` 转为 `DateTime` 数组；记录型变量（RV）把记录维重排到首位；
非记录变量剥离冗余单维或解包为标量。`try-catch` 容错，失败返回 `Dict(:data_load_flag => false)`。

# 参数说明
- `file::String`: CDF 文件路径。

# 返回值
- `Dict{Symbol, Any}`: 变量字典，成功时含 `:data_load_flag => true`。

# 注意事项
- 内部辅助函数 `clean_dimensions` 负责剥离大小为 1 的维度。
- 将数据读入内存以加速后续高频访问，代价是内存占用。
"""
function load_cdf(file::String)  # 将CDF文件读为字典
    """
        clean_dimensions(data) -> typeof(data)

    剥离数组所有大小为 1 的冗余维度。

    # 功能与算法概述
    找出 `size` 为 1 的维度，仅在维度数大于 1 时用 `dropdims` 一次删除全部冗余维。

    # 参数说明
    - `data`: 待处理的数组。

    # 返回值
    - 同类型数组（可能降维）。
    """
    function clean_dimensions(data)
        # 找出所有大小为 1 的维度索引
        local s = size(data)
        # 只有当维度大于 1 且存在大小为 1 的维度时，才执行 dropdims
        # 注意：如果整个数据就是 [1]，我们要小心处理
        local redundant_dims = findall(x -> x == 1, s)
        if !isempty(redundant_dims) && length(s) > 1
            # 删除所有大小为 1 的维度
            # 如果你想保留一维向量，可以只 drop 其中一部分
            return dropdims(data, dims=Tuple(redundant_dims))
        end
        return data
    end
        local cdf_data = []

        try
            cdf_data = CDFDataset(file)
        catch e
            @warn "load_cdf failed" file exception=e
            return Dict(:data_load_flag => false)
        end

        local data_dict = Dict{Symbol,Any}()
        for i in keys(cdf_data)
            local v = cdf_data[i]
            local var_name = Symbol(i)
            if i =="epoch"
                data_dict[var_name] = collect(convert(Vector{DateTime},v))
                continue
            elseif i == "time_unix"
                data_dict[var_name] = collect(v)
            end  # epoch需要为datetime格式，其与time_unix需要读在内存里以加快速度
            local v_num_dims = v.vdr.num_dims
            # C13 疑点：CDF 记录变量（RV）判定使用 v.vdr.flags & 1 == 1。
            # 出处待验证：NASA CDF 规范中 bit0=1 表示记录变变量；旧代码注释提到 flags==3/7。
            # 状态：不改值，仅留此处待人类复核（03 §15 C13）。
            if v_num_dims >= 1 && (v.vdr.flags & 1 == 1)#(v.vdr.flags == 3 || v.vdr.flags == 7)
                # println(i)
                data_dict[var_name] = permutedims(collect(v), [v_num_dims+1; 1:v_num_dims]) # 这里的数据不采用硬盘地址保存方法,以便后续的高级处理
            else
                # println("NRV",i)
                if length(v) == 1
                    data_dict[var_name] = v[]
                else
                    data_dict[var_name] = collect(clean_dimensions(v)) # 这里的数据采用内存保存方法
                end
            end
        end
        data_dict[:data_load_flag] = true
        return data_dict
end
"""
    load_mag_l2(file::String) -> Dict{Symbol, Any}

读取并解析 MAVEN MAG L2 文本磁场文件。

# 功能与算法概述
跳过表头（定位末条以 `END` 开头的行），按固定字符列宽逐行解析时间、磁场与位置，
并计算旋磁总强度 `B_total`。

# 参数说明
- `file::String`: MAG L2 文本文件路径。

# 返回值
- `Dict{Symbol, Any}`: 含 `:epoch`、`:type`、`:B`、`:B_total`、`:position` 的字典。

# 注意事项
- 内部辅助 `get_data_from_line_for_mag_read` 负责单行解析；列宽固定，格式变化需同步修改。
"""
function load_mag_l2(file::String)
    """
        get_data_from_line_for_mag_read(line::String) -> (DateTime, Vector, Vector)

    解析 MAG 文本文件中的单条时间、磁场与位置记录。

    # 功能与算法概述
    按固定字符列宽解析年积日与时刻得到 `epoch`，再解析磁场与位置分量。

    # 参数说明
    - `line::String`: 单行文本。

    # 返回值
    - `(epoch, [bx,by,bz], [x,y,z])`: 时间与磁场、位置分量。
    """
    function get_data_from_line_for_mag_read(line::String)
        # colspecs = [(1,6),(8,10),(12,13),(15,16),(18,19),(21,23),(39,48),(50,58),(60,68),(74,88),(90,103),(105,118)]
        year, doy, hour, min, sec, msec = parse.(Int32, [
            line[1:6], line[8:10], line[12:13], line[15:16], line[18:19], line[21:23]
        ])
        epoch = DateTime(year, 1, 1, hour, min, sec, msec) + Dates.Day(doy - 1)
        bx, by, bz, x, y, z = parse.(Float32, [
            line[39:48], line[50:58], line[60:68], line[74:88], line[90:103], line[105:118]
        ])
        return epoch, [bx, by, bz], [x, y, z]
    end
    lines = readlines(file)
    nums = length(lines)
    line_i = findlast(line -> startswith(line, "END"), lines[1:min(300, nums)])
    if line_i === nothing
        error("load_mag_l2: 无法在文件 $file 的前 min(300, $nums) 行内找到 'END' 表头行")
    end
    lines = lines[line_i+1:end]

    nums = length(lines)
    times = Vector{DateTime}(undef, nums)
    B = Matrix{Float32}(undef, nums, 3)
    position = Matrix{Float32}(undef, nums, 3)

    @inbounds for (i, line) in enumerate(lines)
        times[i], B[i, :], position[i, :] = get_data_from_line_for_mag_read(line)
    end

    B_total = sqrt.(sum(B .^ 2, dims=2))
    B_total = B_total[:, 1]

    type = file[end-24:end-21]
    data = Dict{Symbol,Any}(
        # "Var name" => "time[Ntime], B_total[Ntime],B[Ntime,3],position[Ntime,3]",
        # "Vars" => [times, B_total, B, position],
        :epoch => times,
        :type => type,
        :B_total => B_total,
        :B => B,
        :position => position,
    )
    return data
end
"""
    load_mag_vsc(file::String) -> Dict{Symbol, Any}

读取 Fortran 无格式文件中的航天器速度与位置数据。

# 功能与算法概述
用 `FortranFile` 按 `Int64` 计数后顺序读出 `time_unix`、`vsc`、`position`。

# 参数说明
- `file::String`: Fortran 无格式数据文件路径。

# 返回值
- `Dict{Symbol, Any}`: 含 `:epoch`、`:time_unix`、`:vsc`、`:position` 的字典。

# 注意事项
- `vsc` 与 `position` 为 `(n_time, 3)` 的 `Float32` 数组。
"""
function load_mag_vsc(file::String)
    f = FortranFile(file, "r")
    n_time = read(f, Int64)
    time_unix = read(f, (Float64, n_time))
    vsc = read(f, (Float32, n_time, 3))
    position = read(f, (Float32, n_time, 3))
    close(f)

    times = Dates.unix2datetime.(time_unix)
    # coordinate = file[end-32:end-29]
    data = Dict{Symbol,Any}(
        :epoch => times,
        :time_unix => time_unix,
        # :coordinate => coordinate,
        :vsc => vsc,
        :position => position,
    )
    return data
end
"""
    load_kp(filename::String; pc2ss_Matrix_load=false, str_model=false, kp_columns=_kp_dict[]) -> Dict{Symbol, Any}

读取 KP 文本文件（可选解析坐标变换矩阵）。

# 功能与算法概述
按 `kp_columns` 的列区间抽取各变量（默认解析为 `Float64`，`str_model=true` 时保留字符串），
解析时间为 `DateTime`；`pc2ss_Matrix_load=true` 时额外从指定列区间组装 `pc2ss_Matrix`。

# 参数说明
- `filename::String`: KP 文本文件路径。
- `pc2ss_Matrix_load::Bool`: 是否加载并组装坐标变换矩阵。
- `str_model::Bool`: 是否以字符串形式保留变量值。
- `kp_columns`: 列映射字典（`变量名 => (序号, 列区间)`）。默认读取模块级 `_kp_dict[]`；
  传入自定义映射可避免多脚本同进程互相污染。

# 返回值
- `Dict{Symbol, Any}`: 含各 KP 变量、`:time`（及可选的 `:pc2ss_Matrix`）的字典。

# 注意事项
- 内部辅助 `kp_indicate` 由变量序号推算列区间。
- 旧脚本如调用过 `change_kp_read_data`，默认路径仍保持一致。
"""
function load_kp(filename::String; pc2ss_Matrix_load=false, str_model=false, kp_columns=_kp_dict[])
    """
        kp_indicate(n) -> UnitRange

    由 KP 变量序号计算固定宽度文本中的列区间。

    # 参数说明
    - `n`: 变量序号。

    # 返回值
    - `UnitRange{Int}`: 该变量在行内的字符列区间。
    """
    function kp_indicate(n)
        m = n * 16 - 16 .+ (4:19)
        return m
    end
    lines = readlines(filename)
    lines = [line for line in lines if !startswith(line, "#")]
    time = [line[1:19] for line in lines]
    time_dt = Dates.DateTime.(time, "yyyy-mm-ddTHH:MM:SS")
    Ntime = length(time)

    result_dict = Dict{Symbol,Any}()
    result_dict[:version] = filename[end-10:end-8]

    if str_model
        for (key, value) in kp_columns
            var = [line[value[2]] for line in lines]
            result_dict[key] = var
        end
    else
        for (key, value) in kp_columns
            var = [line[value[2]] for line in lines]
            # var_float = []
            # if "SCP" in var || "SC0" in var || "I" in var || "O" in var
            #     var_float = replace.(var, "SCP" => 1)
            #     var_float = replace.(var_str, "SC0" => 0)
            #     var_float = replace.(var_str, "I" => 1)
            #     var_float = replace.(var_str, "O" => 0)
            # end
            var_float = parse.(Float64, var)
            result_dict[Symbol(key)] = var_float
        end
    end
    # if NaN2missing
    #     for (key, value) in result_dict
    #         ind = findall(x-> isnan(x), value)
    #         var = convert(Vector{Union{Missing, Float64}},value)
    #         var[ind] .= missing
    #         result_dict[key] = var
    #     end
    # end
    result_dict[:time] = time_dt

    if pc2ss_Matrix_load == false
        return result_dict
    else
        pc2ss_Matrix = zeros(Ntime, 3, 3)
        M_dict = Dict()
        for l in (218:226)
            value = kp_indicate(l)
            var = [line[value] for line in lines]
            var_float = parse.(Float64, var)
            M_dict[l-217] = var_float
        end
        for (key, var) in M_dict
            i = div(key - 1, 3) + 1  # 计算行索引(1-based)
            j = rem(key - 1, 3) + 1
            pc2ss_Matrix[:, i, j] = var
        end
        result_dict[:pc2ss_Matrix] = pc2ss_Matrix
        return result_dict
    end
end
"""
    load_swea_pad(file::String; mean_PA=true) -> Dict{Symbol, Any}

读取 SWEA PAD CDF 文件，并可选合并俯仰角数据。

# 功能与算法概述
先 `load_cdf` 载入，`mean_PA=true` 时再经 `mean_SWEA_pad_pa` 把 360° 的 16 方向平均为 180° 的 8 点。

# 参数说明
- `file::String`: SWEA PAD CDF 文件路径。
- `mean_PA::Bool`: 是否执行俯仰角平均。

# 返回值
- `Dict{Symbol, Any}`: 数据字典（`mean_PA=true` 时含 `:diff_en_fluxes_mean`、`:pa_mean` 等）。
"""
function load_swea_pad(file::String; mean_PA=true)
    # 默认将360°的数据投影到180°
    # "diff_en_fluxes_mean"
    # "g_pa_mean"
    # "pa_mean"
    data_dict = load_cdf(file)
    if mean_PA
        data_dict = mean_SWEA_pad_pa(data_dict)
    end
    return data_dict
end
"""
    load_NGIMS_den_l3(file::String) -> Dict{String, Any}

读取 NGIMS L3 日产品密度表。

# 功能与算法概述
跳过表头后逐行按逗号切分，把 `t_unix` 转为 `DateTime`，并按 `species` 分组存入字典。

# 参数说明
- `file::String`: NGIMS L3 密度表文件路径。

# 返回值
- `Dict{String, Any}`: 以中性成分名为键，值为含 `:epoch`、`:orbit`、`:alt`、`:mass`、`:density_bins`、`:quality` 等的字典。

# 注意事项
- 列序固定，格式变化需同步修改。
"""
function load_NGIMS_den_l3(file::String)
    lines = readlines(file)
    lines = lines[2:end]
    #t_utc,t_unix,t_sclk,t_tid,tid,orbit,focusmode,alt,mass,species,density_bins,quality
    n = length(lines)
    str_vars = Matrix{String}(undef, n, 12)
    for (i, line) in enumerate(lines)
        vars = split(line, ",")
        str_vars[i, :] = vars
    end
    t_unix = parse.(Float64, str_vars[:, 2])
    t_datetime = unix2datetime.(t_unix)
    data_out_dict = Dict{String,Any}()
    species = str_vars[:, 10]
    unique_elements = unique(species)
    for element in unique_elements
        indices = findall(x -> x == element, species)
        data_out_dict[element] = Dict{Symbol,Any}(
            :epoch => t_datetime[indices],
            :orbit => parse.(Int32, str_vars[indices, 6]),
            :focusmode => str_vars[indices, 7],
            :alt => parse.(Float64, str_vars[indices, 8]),
            :mass => parse.(Float64, str_vars[indices, 9]),
            :density_bins => parse.(Float64, str_vars[indices, 11]),
            :quality => str_vars[indices, 12],
        )
    end
    return data_out_dict
end
"""
    load_NGIMS_den_l4(file::String) -> Any

读取 NGIMS L4 日产品密度表（JLD2 格式）。

# 功能与算法概述
打开 JLD2 文件并直接取出 `"data"` 字段。

# 参数说明
- `file::String`: NGIMS L4 文件路径。

# 返回值
- `Any`: 文件中 `"data"` 字段的内容。
"""
function load_NGIMS_den_l4(file::String)
    f = jldopen(file, "r")
    data_out_dict = f["data"]
    close(f)
    return data_out_dict
end
"""
    load_NGIMS_sht_l3(file::String) -> Dict{String, Any}

读取 NGIMS L3 重采样标高表。

# 功能与算法概述
跳过表头逐行按逗号切分，`t_unix` 转 `DateTime` 后按 `species` 分组，
输出标高、温度及其误差、拟合残差与质量等字段。

# 参数说明
- `file::String`: NGIMS L3 标高表文件路径。

# 返回值
- `Dict{String, Any}`: 以成分名为键，值为含 `:epoch`、`:exo_alt`、`:scale_height`、`:Temperature`、`:fit_residual`、`:quality` 等的字典。
"""
function load_NGIMS_sht_l3(file::String) # L3 resampled scale height table of NGIMs
    lines = readlines(file)
    lines = lines[2:end]
    #t_utc,t_unix,t_sclk,t_tid,tid,orbit,exo_alt,mass,species,scale_height,scale_height_error,Temperature,Temperature_error,fit_residual,quality
    n = length(lines)
    str_vars = Matrix{String}(undef, n, 15)
    for (i, line) in enumerate(lines)
        vars = split(line, ",")
        str_vars[i, :] = vars
    end
    t_unix = parse.(Float64, str_vars[:, 2])
    t_datetime = unix2datetime.(t_unix)
    data_out_dict = Dict{String,Any}()
    species = str_vars[:, 10]
    unique_elements = unique(species)
    for element in unique_elements
        indices = findall(x -> x == element, species)
        data_out_dict[element] = Dict{Symbol,Any}(
            :epoch => t_datetime[indices],
            :orbit => parse.(Int32, str_vars[indices, 6]),
            :exo_alt => parse.(Float64, str_vars[indices, 7]),
            :mass => parse.(Float64, str_vars[indices, 8]),
            :species => parse.(Float64, str_vars[indices, 9]),
            :scale_height => parse.(Float64, str_vars[indices, 10]),
            :scale_height_error => parse.(Float64, str_vars[indices, 11]),
            :Temperature => parse.(Float64, str_vars[indices, 12]),
            :Temperature_error => parse.(Float64, str_vars[indices, 13]),
            :fit_residual => parse.(Float64, str_vars[indices, 14]),
            :quality => str_vars[indices, 15]
        )
    end
    return data_out_dict
end
"""
    load_d1_v4d(file::String) -> Dict{Symbol, Any}

读取 STATIC d1 四维（离子速度/通量/密度）Fortran 无格式数据。

# 功能与算法概述
按 `Int64` 计数后顺序读出 H/He/O/O2/CO2 的速度、通量与密度，以及位置、磁场、
质量标志、模式与 vsc 质量标志，组装为字典。

# 参数说明
- `file::String`: d1 v4d 数据文件路径（已由 sc_pot 与 vsc 修正）。

# 返回值
- `Dict{Symbol, Any}`: 含 `:epoch`、`:*_vel`、`:*_f`、`:*_den`、`:pos_sc_mso`、`:mag_mso`、`:quality_flag`、`:mode`、`:vsc_quality` 的字典。
"""
function load_d1_v4d(file::String) # build using STATIC d1 data. already been corrected by sc_pot(static) and vsc by MAG_ss1s
    f = FortranFile(file, "r")
    Ntime = read(f, Int64)
    time_unix = read(f, (Float64, Ntime))
    H_vel = read(f, (Float32, Ntime, 3))
    He_vel = read(f, (Float32, Ntime, 3))
    O_vel = read(f, (Float32, Ntime, 3))
    O2_vel = read(f, (Float32, Ntime, 3))
    CO2_vel = read(f, (Float32, Ntime, 3))
    H_f = read(f, (Float32, Ntime, 3))
    He_f = read(f, (Float32, Ntime, 3))
    O_f = read(f, (Float32, Ntime, 3))
    O2_f = read(f, (Float32, Ntime, 3))
    CO2_f = read(f, (Float32, Ntime, 3))
    H_den = read(f, (Float32, Ntime))
    He_den = read(f, (Float32, Ntime))
    O_den = read(f, (Float32, Ntime))
    O2_den = read(f, (Float32, Ntime))
    CO2_den = read(f, (Float32, Ntime))
    pos_mso = read(f, (Float32, Ntime,3))
    mag_mso = read(f, (Float32, Ntime,3))
    quality_flag = read(f, (Int16, Ntime))
    mode = read(f, (Int4, Ntime))
    vsc_quality = read(f, (Bool, Ntime))
    close(f)
    data = Dict{Symbol,Any}(
        :epoch => unix2datetime.(time_unix),
        :time_unix => time_unix,
        :H_vel => H_vel,
        :He_vel => He_vel,
        :O_vel => O_vel,
        :O2_vel => O2_vel,
        :CO2_vel => CO2_vel,
        :H_f => H_f, # flux
        :He_f => He_f, # flux
        :O_f => O_f,
        :O2_f => O2_f,
        :CO2_f => CO2_f,
        :H_den => H_den,
        :He_den => He_den,
        :O_den => O_den,
        :O2_den => O2_den,
        :CO2_den => CO2_den,
        :pos_sc_mso => pos_mso,
        :mag_mso => mag_mso,
        :quality_flag => quality_flag,
        :mode => mode,
        :vsc_quality => vsc_quality,
    )
    return data
end
"""
    load_c6_v3d(file::String) -> Dict{Symbol, Any}

读取 STATIC c6 三维（离子速度/通量/密度）数据（JLD2 格式）。

# 功能与算法概述
打开 JLD2 取出 `"data"` 字段，把简写键映射为规范键
（如 `:H_v → :H_vel`、`:H_n → :H_den`、`:pos → :P_mso`）。

# 参数说明
- `file::String`: c6 v3d 数据文件路径。

# 返回值
- `Dict{Symbol, Any}`: 含各离子速度/通量/密度、`:P_mso`、`:B_mso`、`:quality_flag`、`:mode`、`:mass_range`、`:discribe` 的字典。

# 注意事项
- 文件内键名为简写（`H_v`/`H_f`/`H_n` 等），须与映射保持一致。
"""
function load_c6_v3d(file::String) # build using STATIC d1 data. already been corrected by sc_pot(static) and vsc by MAG_ss1s
    # f = FortranFile(file, "r")
    # Ntime = read(f, Int64)
    # time_unix = read(f, (Float64, Ntime))
    # H_vel = read(f, (Float32, Ntime))
    # He_vel = read(f, (Float32, Ntime))
    # O_vel = read(f, (Float32, Ntime))
    # O2_vel = read(f, (Float32, Ntime))
    # H_f = read(f, (Float32, Ntime))
    # He_f = read(f, (Float32, Ntime))
    # O_f = read(f, (Float32, Ntime))
    # O2_f = read(f, (Float32, Ntime))
    # H_den = read(f, (Float32, Ntime))
    # He_den = read(f, (Float32, Ntime))
    # O_den = read(f, (Float32, Ntime))
    # O2_den = read(f, (Float32, Ntime))

    # b_mso = read(f, (Float32, Ntime,3))
    # pos_mso = read(f, (Float32, Ntime,3))
    # quality_flag = read(f, (Int16, Ntime))
    # mode = read(f, (Int16, Ntime))
    # mass_range = trimstring(read(f, FString{64}))
    # close(f)

    # data = Dict{Symbol,Any}(
    #     :epoch => unix2datetime.(time_unix),
    #     :time_unix => time_unix,
    #     :H_vel => H_vel,
    #     :He_vel => He_vel,
    #     :O_vel => O_vel,
    #     :O2_vel => O2_vel,
    #     :H_f => H_f, # flux
    #     :He_f => He_f, # flux
    #     :O_f => O_f,
    #     :O2_f => O2_f,
    #     :H_den => H_den,
    #     :He_den => He_den,
    #     :O_den => O_den,
    #     :O2_den => O2_den,
    #     :P_mso => pos_mso,
    #     :B_mso => b_mso,
    #     :quality_flag => quality_flag,
    #     :mode => mode,
    #     :mass_range => mass_range,
    # )
    # return data
    local f = jldopen(file, "r")
    local data0 = f["data"]
    data_out_dict = Dict{Symbol,Any}(
        :time_unix => data0[:time_unix],
        :H_vel => data0[:H_v],
        :He_vel => data0[:He_v],
        :O_vel => data0[:O_v],
        :O2_vel => data0[:O2_v],
        :CO2_vel => data0[:CO2_v],
        :H_den => data0[:H_n],
        :He_den => data0[:He_n],
        :O_den => data0[:O_n],
        :O2_den => data0[:O2_n],
        :CO2_den => data0[:CO2_n],
        :H_f => data0[:H_f],
        :He_f => data0[:He_f],
        :O_f => data0[:O_f],
        :O2_f => data0[:O2_f],
        :CO2_f => data0[:CO2_f],
        :P_mso => data0[:pos],
        :B_mso => data0[:b],
        :quality_flag => data0[:quality_flag],
        :mode => data0[:mode],
        :mass_range => data0[:mass_range],
        :discribe => data0[:discribe]
    )
    close(f)
    return data_out_dict
end
"""
    load_quat(filename::String) -> Dict{Symbol, Any}

读取 IDL 导出的四元数 CSV 文件。

# 功能与算法概述
先统计行数预分配 `n×5` 矩阵，按固定列宽解析 `ut` 与 4 个四元数分量，
再用 `Rotations.QuatRotation` 构造四元数数组。

# 参数说明
- `filename::String`: 文件路径（格式 `(I10,1x,4(f14.10,1x),4(f14.10,1x))`）。

# 返回值
- `Dict{Symbol, Any}`: 含 `:epoch`、`:time_unix`、`:quat`、`:coordinate` 的字典。

# 注意事项
- 采用固定字符列宽解析；`:coordinate` 由文件名约定给出。
"""
function load_quat(filename::String)::Dict{Symbol,Any}#读取idl导出的quat数据
    # 数据格式, filename = file.csv ut, scrotmat, msorotmat, format="(I10,1x,4(f14.10,1x),4(f14.10,1x))"
    # 统计行数以预分配矩阵
    local n = 0
    open(filename) do io
        for _ in eachline(io)
            n += 1
        end
    end
    # 预分配矩阵，每行包含ut和8个浮点数
    local data = Matrix{Float64}(undef, n, 5)
    # 逐行解析数据
    open(filename) do io
        for (i, line) in enumerate(eachline(io))
            # 提取各字段并转换为Float64
            local ut   = parse(Float64, SubString(line, 1, 10))
            local mso1 = parse(Float64, SubString(line, 12, 25))
            local mso2 = parse(Float64, SubString(line, 27, 40))
            local mso3 = parse(Float64, SubString(line, 42, 55))
            local mso4 = parse(Float64, SubString(line, 57, 70))
            
            # 填充数据到矩阵
            @inbounds data[i, :] .= (ut, mso1, mso2, mso3, mso4)
        end
    end
    # 使用 Rotations 的 QuatRotation（原 Quaternions 写法已弃用）
    local quat_s = [QuatRotation(data[i,2:5]) for i in 1:n]
    dd0 = Dict{Symbol,Any}(
        :epoch => unix2datetime.(data[:, 1]),
        :time_unix => data[:, 1],
        :quat => quat_s,
        :coordinate => "SWIA to mso", # 读取文件名中的坐标系
    )
    return dd0
end
## ------------------------------数据处理--------------------------------
kp_dict_0 = Dict(
    :electorn_density => 2,
    :GEO_x => 187,
    :GEO_y => 188,
    :GEO_z => 189,
    :MSO_x => 190,
    :MSO_y => 191,
    :MSO_z => 192,
    :Orbit_Number => 210,
    :Shape_parameter => 39,
)
"""
    convert_kp_l3(data::Dict; kp_dict=kp_dict_0) -> Dict{Symbol, Any}

把 KP L3 原始字典转换为便于使用的规范字典。

# 功能与算法概述
先复制元信息类键（`:time`、`:pc2ss_Matrix` 等），再按 `kp_dict` 把 `:vars` 中对应的
按序号命名变量重命名为语义化键名。

# 参数说明
- `data::Dict`: KP L3 数据字典，需含 `:vars` 与各元信息键。
- `kp_dict`: 语义名到变量序号的映射（默认 `kp_dict_0`）。

# 返回值
- `Dict{Symbol, Any}`: 重命名后的字典。

# 注意事项
- 若 `data` 缺少 `:vars` 中对应序号的键会报错。
"""
function convert_kp_l3(data::Dict;kp_dict=kp_dict_0)
    data_out = Dict{Symbol,Any}()
    for key in [:sc2ss_Matrix, :filename, :varsion, :data_load_flag, :pc2ss_Matrix, :time]
        data_out[key] = data[key]
    end
    for (key, value) in kp_dict
        symobl_i = Symbol("var_$value")
        data_out[key] = data[:vars][symobl_i]
    end
    return data_out
end
"""
    mean_SWEA_pad_pa(data_dict) -> Dict{Symbol, Any}

把 SWEA PAD 的 360°（16 方向）俯仰角数据平均为 180°（8 方向）。

# 功能与算法概述
将前 8 与后 8 个方向（反序）配对求平均，先做互 NaN 填补再平均，写出
`:diff_en_fluxes_mean`、`:g_pa_mean`、`:pa_mean`。

# 参数说明
- `data_dict`: SWEA PAD CDF 字典，需含 `:diff_en_fluxes`、`:pa`、`:g_pa`。

# 返回值
- `Dict{Symbol, Any}`: 已注入平均结果的同一字典。
"""
function mean_SWEA_pad_pa(data_dict)  # 输入SWEA PAD的CDF字典,将其角度做平均. pad数据返回360°的16个方向的数据,可以做平均,使其变为180°的8个数据点
    flux = data_dict[:diff_en_fluxes]
    pitch_angle = data_dict[:pa]
    g_pa = data_dict[:g_pa]

    pitch_angle_mean = (pitch_angle[:, 1:8, :] .+ pitch_angle[:, 16:-1:9, :]) ./ 2
    g_pa_mean = (g_pa[:, 1:8, :] .+ g_pa[:, 16:-1:9, :]) ./ 2

    flux1 = flux[:, 1:8, :]
    flux2 = flux[:, 16:-1:9, :]
    nan_indices_flux1 = findall(isnan.(flux1))
    nan_indices_flux2 = findall(isnan.(flux2))
    # C12 疑点：NaN 互填逻辑——先用对侧有效值填补本侧 NaN，再平均。
    # 出处待验证：SPEDAS/IDL 对 SWEA PAD 180° 平均是否采用同样的互填规则？填补顺序是否影响结果？
    # 状态：不改值，仅留此处待人类复核（03 §15 C12）。
    flux1[nan_indices_flux1] = flux2[nan_indices_flux1]
    flux2[nan_indices_flux2] = flux1[nan_indices_flux2]

    flux_mean = (flux1 + flux2) ./ 2

    data_dict[:diff_en_fluxes_mean] = flux_mean
    data_dict[:g_pa_mean] = g_pa_mean
    data_dict[:pa_mean] = pitch_angle_mean
    return data_dict
end
"""
    find_segments(x::Vector{T}, y::BitVector) -> (Vector, Vector)

在布尔掩膜 `y` 中提取所有连续 `true` 段的起止横坐标。

# 功能与算法概述
线性扫描 `y`，遇到 `1` 记起点、回到 `0` 记终点，返回两段起止值；
末尾仍为 `1` 时以 `x[end]` 收尾。

# 参数说明
- `x::Vector{T}`: 与 `y` 同长的横坐标。
- `y::BitVector`: 布尔掩膜。

# 返回值
- `(starts, stops)`: 各 `true` 段的起始与终止 `x` 值。
"""
function find_segments(x::Vector{T}, y::BitVector) where {T}
    segments1 = []
    segments2 = []
    start_idx = nothing
    for i in eachindex(y)
        if y[i] == 1
            if start_idx === nothing
                start_idx = i
            end
        elseif start_idx !== nothing
            push!(segments1, x[start_idx])
            push!(segments2, x[i-1])
            start_idx = nothing
        end
    end
    if start_idx !== nothing
        push!(segments1, x[start_idx])
        push!(segments2, x[end])
    end
    return segments1, segments2
end

_kp_dict[] = change_kp_read_data(_kp_dict[])

# 显式 loader 函数表（TASK-012）：JSON value[4] 字符串 → 模块内真实函数。
# 彻底去除 eval(Meta.parse(...)) 的任意代码执行入口；JSON 文件一字不改。
const LOADER_FUNCS = Dict{String,Function}(
    "load_cdf"            => load_cdf,
    "load_c6_v3d"         => load_c6_v3d,
    "load_d1_v4d"         => load_d1_v4d,
    "load_kp"             => load_kp,
    "load_mag_l2"         => load_mag_l2,
    "load_mag_vsc"        => load_mag_vsc,
    "load_NGIMS_den_l3"   => load_NGIMS_den_l3,
    "load_NGIMS_den_l4"   => load_NGIMS_den_l4,
    "load_NGIMS_sht_l3"   => load_NGIMS_sht_l3,
    "load_quat"           => load_quat,
    "load_swea_pad"       => load_swea_pad,
)

read_models = Dict{String,Tuple{String,Function}}()
for (key, value) in data_model
    loader_name = value[4]
    if !haskey(LOADER_FUNCS, loader_name)
        error("MAVEN model '$(key)' references unknown loader function '$(loader_name)'. " *
              "Add it to LOADER_FUNCS in MAVEN_data/MAVEN_load.jl.")
    end
    read_models[key] = (value[3], LOADER_FUNCS[loader_name])
end
end # module

# ----test
# EnvironmentPath = "D:/CODE/Package_for_Julia/"
# include(EnvironmentPath * "MAVEN_data/MAVEN_load.jl")
# import .MAVEN_load;
# file = raw"C:\Users\Odysseus Lightning\Desktop\mvn_mag_l2_2015193pc_20150712_v01_r02.sts"
# lines = readlines(file)
# MAVEN_load.load_mag_l2(file)
