"""MarsData：火星空间数据工具包的轻量公共 API 入口（P4）。

仅暴露路径解析、产品注册表与索引读取等公共 API，不加载任何科学数据 loader，
因此可在无本地数据、无 Fortran DLL 的环境下加载。
"""
module MarsData

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

end
