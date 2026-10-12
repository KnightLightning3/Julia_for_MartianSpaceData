"""MarsData：火星空间数据工具包（路径 / 注册表 / 索引 + 绘图功能 + 模块装载）。

- **轻量公共 API**：路径解析、产品注册表与索引读取（不加载任何科学数据 loader）。
- **绘图功能（包化）**：`MAVEN_data/MAVEN_plot.jl` 的绘图基元 + 概览绘图合成
  （`plot_module`），`using MarsData` 即可调用。
- **模块装载管理器**：以函数调用替代 `include` 装载重模块，白名单控制裸名引入面。

用法：
```julia
using MarsData
MarsData.maven_data_root()          # 数据根目录
fig = Figure(; size=(2500, 2500))
MarsData.plot_module(fig, time_range, data_dict; time_step=Dates.Minute(10))

MarsData.load_module(:MAVEN_load)   # ≡ include("MAVEN_data/MAVEN_load.jl") 到 MarsData
MarsData.@load MAVEN_STATIC IGRF_calculate   # 在调用者作用域装载并绑定
```
"""
module MarsData

# ==================== 轻量公共 API：路径 / 注册表 / 索引 ====================
include(joinpath(@__DIR__, "..", "common", "paths.jl"))
using .Paths
using JSON

const REGISTRY_PATH = joinpath(Paths.project_root(), "MAVEN_data", "MAVEN_data_format.json")
const INDEX_PATH = joinpath(Paths.project_root(), "MAVEN_data", "filename_lists.json")

project_root() = Paths.project_root()
maven_data_root() = Paths.maven_data_root()
tw_data_root() = Paths.tw_data_root()
mgs_data_root() = Paths.mgs_data_root()
index_path() = Paths.index_path()

function load_registry()
    open(REGISTRY_PATH, "r") do f
        return JSON.parse(f)
    end
end

function data_model()
    return load_registry()["data_model"]
end

function load_index()
    if !isfile(INDEX_PATH)
        return Dict{String,Any}()
    end
    open(INDEX_PATH, "r") do f
        return JSON.parse(f)
    end
end

# ==================== 绘图功能（包化） ====================
using Dates
using LinearAlgebra
using Statistics
using CairoMakie
using Makie

# 绘图基元：子模块 MAVEN_plot（其内部自带 constants / MarsCommon）
include(joinpath(@__DIR__, "..", "MAVEN_data", "MAVEN_plot.jl"))
using .MAVEN_plot

# 概览绘图合成：TimeFormat / remove_0_point! / plot_module
include(joinpath(@__DIR__, "plotting.jl"))

# ==================== 模块装载管理器（include 的包化入口） ====================
# MarsData.load_module(:MAVEN_load) ≡ include("MAVEN_data/MAVEN_load.jl")
# MarsData.@load MAVEN_load MAVEN_STATIC          # 在调用者作用域绑定
include(joinpath(@__DIR__, "modules.jl"))

end
