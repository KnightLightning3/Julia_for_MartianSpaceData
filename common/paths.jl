"""路径解析单一出处（P1）：MAVEN/TW/MGS 根路径与索引/清单路径。

TOML 为唯一写端（config/settings.toml），旧 INI（download_data/MAVEN_download_config.ini）只读兼容。
所有路径由本文件位置推导，与运行时 CWD 无关。
"""
module Paths

using TOML
using IniFile

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const TOML_PATH = joinpath(PROJECT_ROOT, "config", "settings.toml")
const LEGACY_INI_PATH = joinpath(PROJECT_ROOT, "download_data", "MAVEN_download_config.ini")

const DEFAULT_MAVEN = "E:/MAVEN/"
const DEFAULT_TW = "E:/Tianwen-1/"
const DEFAULT_MGS = "E:/MGS/"

function _roots_from_toml(d)
    maven = DEFAULT_MAVEN
    tw = DEFAULT_TW
    mgs = DEFAULT_MGS
    if haskey(d, "paths")
        p = d["paths"]
        if p isa Dict
            maven = get(p, "maven_data_root", maven)
            tw = get(p, "tw_data_root", tw)
            mgs = get(p, "mgs_data_root", mgs)
        end
    end
    return (maven, tw, mgs)
end

function _load_roots()
    if isfile(TOML_PATH)
        return _roots_from_toml(TOML.parsefile(TOML_PATH))
    elseif isfile(LEGACY_INI_PATH)
        ini = read(Inifile(), LEGACY_INI_PATH)
        maven = get(ini, "DEFAULT", "Save_dir", DEFAULT_MAVEN)
        return (maven, DEFAULT_TW, DEFAULT_MGS)
    else
        return (DEFAULT_MAVEN, DEFAULT_TW, DEFAULT_MGS)
    end
end

const _ROOTS = _load_roots()

maven_data_root() = _ROOTS[1]
tw_data_root() = _ROOTS[2]
mgs_data_root() = _ROOTS[3]

project_root() = PROJECT_ROOT
index_path() = joinpath(PROJECT_ROOT, "MAVEN_data", "filename_lists.json")

"""Fortran DLL 定位目录（ARCH-005，只读可选键）。

解析顺序：`config/settings.toml` 的可选键 `paths.fortran_dll_dir` → 仓库根目录。
该函数只返回目录，不检查具体 DLL 文件是否存在；具体查找由 `call_fortran_dll.jl` 完成。
"""
function fortran_dll_dir()
    if isfile(TOML_PATH)
        d = TOML.parsefile(TOML_PATH)
        if haskey(d, "paths") && d["paths"] isa Dict
            p = d["paths"]
            if haskey(p, "fortran_dll_dir")
                return String(p["fortran_dll_dir"])
            end
        end
    end
    return PROJECT_ROOT
end

end
