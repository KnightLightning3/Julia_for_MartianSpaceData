"""仓库路径与数据根路径。配置唯一来源为 `config/settings.toml`。"""
module Paths

using TOML

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const TOML_PATH = joinpath(PROJECT_ROOT, "config", "settings.toml")

project_root() = PROJECT_ROOT
index_path() = joinpath(PROJECT_ROOT, "MAVEN_data", "filename_lists.json")

_is_windows_absolute(path::AbstractString) = occursin(r"^(?:[A-Za-z]:[\\/]|\\\\)", path)

function _configured_root(paths::AbstractDict, key::String)
    haskey(paths, key) || error("Missing paths.$key in $TOML_PATH. Configure it in config/settings.toml.")
    value = paths[key]
    value isa AbstractString || error("paths.$key must be a string in $TOML_PATH.")
    isempty(strip(value)) && error("paths.$key must be a non-empty string in $TOML_PATH.")
    root = value

    if _is_windows_absolute(root)
        return root  # Preserve Windows drive/UNC semantics on non-Windows hosts.
    elseif isabspath(root)
        return normpath(root)
    end
    return normpath(joinpath(PROJECT_ROOT, root))
end

function _load_settings()
    isfile(TOML_PATH) || error("Julia requires config/settings.toml. Create it with `python download_data/initialize_download_parameters.py` (this does not overwrite an existing file), then edit the shared paths in that TOML file.")
    Base.include_dependency(TOML_PATH)  # Invalidate package precompilation when local settings change.
    config = TOML.parsefile(TOML_PATH)
    paths = get(config, "paths", nothing)
    paths isa AbstractDict || error("[paths] must be a TOML table in $TOML_PATH.")

    roots = (
        _configured_root(paths, "maven_data_root"),
        _configured_root(paths, "tw_data_root"),
        _configured_root(paths, "mgs_data_root"),
    )
    dll = get(paths, "fortran_dll_dir", "")
    dll isa AbstractString || error("paths.fortran_dll_dir must be a string in $TOML_PATH.")
    dll_path = if isempty(strip(dll))
        PROJECT_ROOT
    elseif _is_windows_absolute(dll)
        dll
    elseif isabspath(dll)
        normpath(dll)
    else
        normpath(joinpath(PROJECT_ROOT, dll))
    end
    return roots, dll_path
end

const _SETTINGS = _load_settings()
const _ROOTS = _SETTINGS[1]
const _FORTRAN_DLL_DIR = _SETTINGS[2]

maven_data_root() = _ROOTS[1]
tw_data_root() = _ROOTS[2]
mgs_data_root() = _ROOTS[3]
fortran_dll_dir() = _FORTRAN_DLL_DIR

end
