# =============================================================================
# Index.jl —— 仓库级索引与名称可解析性（仅依赖 Base）
#
# 建立「文件 → 模块作用域」映射：
#   * 每个 .jl 文件有一个独立的脚本作用域键（@script#N），互不冒充可见；
#   * include 的字面量路径边把被包含文件的内容追加到调用处所在模块；
#   * module 块建立子模块与父模块关系（并按模块名登记，供跨文件限定名使用）；
#   * using/import/别名建立「本模块可见的绑定名」。
#
# 由此判断某个引用点是否能静态解析到定义：defined / imported / submodule /
# external（Base/Core） / unresolved。只有 unresolved 才允许报「悬空引用」，
# 其余不确定情形（外部模块成员、非模块基座、动态构造）一律显式 unknown。
# =============================================================================

struct ParseError
    file::String
    line::Int
    message::String
end

const EMPTY_NAMES = Set{String}()

mutable struct RepoIndex
    root::String
    order::Vector{String}
    scans::Dict{String,FileScan}
    root_keys::Dict{String,String}                  # 文件 → 脚本作用域键
    node_scopes::Dict{String,Set{String}}           # 文件 → 被求值处的绝对作用域键集合
    module_files::Dict{String,Set{String}}          # 作用域键 → 该作用域下被求值的文件
    module_defs::Dict{String,Set{String}}           # 作用域键 → 可见顶层定义名
    module_bound::Dict{String,Set{String}}          # 作用域键 → using/import/别名绑定名
    module_exports::Dict{String,Set{String}}        # 作用域键 → export 名
    module_alias::Dict{String,String}               # "作用域键::本地名" → 目标作用域键（"" 表示外部）
    module_by_name::Dict{String,Set{String}}        # module 名 → 定义它的作用域键集合
    submodule_names::Dict{String,Set{String}}       # 父作用域键 → 子模块名
    submodule_parent::Dict{String,String}           # 子作用域键 → 父作用域键
    key_paths::Dict{String,Vector{String}}          # 作用域键 → 路径
    project_defs::Dict{String,Set{String}}          # 定义名 → 文件集合（任意层级）
    nested_defs::Dict{String,Set{String}}           # 定义名 → 含嵌套同名定义的文件集合
    dynamic_sites::Vector{DynamicSite}
    parse_errors::Vector{ParseError}
    include_missing::Vector{Tuple{String,String,Int}}
    skipped_dirs::Vector{String}                    # 跳过的临时/探针目录（不误当生产源码）
    inventory::Dict{String,Int}
end

function new_index(root::AbstractString, order::Vector{String}, scans::Dict{String,FileScan})
    return RepoIndex(String(root), order, scans,
                     Dict{String,String}(), Dict{String,Set{String}}(),
                     Dict{String,Set{String}}(), Dict{String,Set{String}}(),
                     Dict{String,Set{String}}(), Dict{String,Set{String}}(),
                     Dict{String,String}(), Dict{String,Set{String}}(),
                     Dict{String,Set{String}}(), Dict{String,String}(),
                     Dict{String,Vector{String}}(), Dict{String,Set{String}}(),
                     Dict{String,Set{String}}(), DynamicSite[], ParseError[],
                     Tuple{String,String,Int}[], String[], Dict{String,Int}())
end

pushnamed!(d::Dict{String,Set{String}}, k::AbstractString, v::AbstractString) =
    push!(get!(d, String(k), Set{String}()), String(v))

"""登记作用域键并保存其规范化路径（键即用于比较的字符串）。"""
function register_key!(idx::RepoIndex, path::Vector{String})
    isempty(path) && return ""
    k = mkey(path)
    haskey(idx.key_paths, k) || (idx.key_paths[k] = copy(path))
    return k
end

path_of_key(idx::RepoIndex, k::AbstractString) =
    get(idx.key_paths, String(k), String(k) == "" ? String[] : String.(split(String(k), "/")))

"模块路径文本 `.A.B` → (dots, parts)"
function parse_module_text(txt::AbstractString)
    t = String(txt)
    dots = length(match(r"^\.*", t).match)
    rest = t[(dots + 1):end]
    isempty(rest) && return (dots, String[])
    return (dots, String.(split(rest, ".")))
end

"""临时/探针目录（并发工具产物、团队状态、构建缓存）：默认不当作生产源码扫描。"""
is_probe_dir(name::AbstractString) =
    startswith(name, ".") || lowercase(String(name)) == "node_modules" ||
    lowercase(String(name)) == "tmp" || startswith(lowercase(String(name)), "_tmp")

"""发现仓库内待扫描的 .jl 文件（仓库相对 POSIX 路径，已排序）。"""
function discover_files(root::AbstractString; skipped::Union{Nothing,Vector{String}}=nothing)
    files = String[]
    for (dir, dirs, fs) in walkdir(String(root))
        rel_dir = clean_rel(relpath(dir, root))
        keep = String[]
        for d in dirs
            full = rel_dir == "." ? d : rel_dir * "/" * d
            if is_probe_dir(d) || startswith(full, "docs/build")
                skipped === nothing || push!(skipped, full)
                continue
            end
            push!(keep, d)
        end
        empty!(dirs)
        append!(dirs, keep)
        for f in fs
            endswith(f, ".jl") || continue
            rel = clean_rel(rel_dir == "." ? f : joinpath(rel_dir, f))
            startswith(rel, "..") && continue
            push!(files, rel)
        end
    end
    return sort!(unique(files))
end

"""扫描给定文件集，构建仓库索引。"""
function build_index(root::AbstractString; files::Vector{String}, names::Set{String},
                     skipped::Union{Nothing,Vector{String}}=nothing)
    scans = Dict{String,FileScan}()
    order = String[]
    for rel in files
        rel = clean_rel(rel)
        haskey(scans, rel) && continue
        scans[rel] = scan_file(root, rel, names)
        push!(order, rel)
    end
    idx = new_index(root, order, scans)
    skipped === nothing || append!(idx.skipped_dirs, skipped)
    populate_index!(idx)
    return idx
end

function populate_index!(idx::RepoIndex)
    scans = idx.scans
    # ---- 0. 每个文件一个独立脚本作用域键 ----
    for (i, rel) in enumerate(idx.order)
        k = "@script#" * string(i)
        idx.root_keys[rel] = k
        idx.key_paths[k] = [k]
        pushnamed!(idx.node_scopes, rel, k)
    end

    # ---- 1. include 闭包：(文件, 绝对作用域键) ----
    work = Tuple{String,String}[]
    for rel in idx.order
        push!(work, (rel, idx.root_keys[rel]))
    end
    seen = Set{Tuple{String,String}}()
    while !isempty(work)
        (rel, pk) = pop!(work)
        (rel, pk) in seen && continue
        push!(seen, (rel, pk))
        pushnamed!(idx.module_files, pk, rel)
        s = scans[rel]
        base = path_of_key(idx, pk)
        for e in s.includes
            if !haskey(scans, e.included)
                entry = (rel, e.included, e.line)
                entry in idx.include_missing || push!(idx.include_missing, entry)
                continue
            end
            child = register_key!(idx, vcat(base, e.module_path))
            pushnamed!(idx.node_scopes, e.included, child)
            push!(work, (e.included, child))
        end
    end

    # ---- 2. 定义 / 子模块 / 项目定义 ----
    for (pk, files) in idx.module_files
        base = path_of_key(idx, pk)
        for rel in files
            for d in scans[rel].defs
                abs = vcat(base, d.module_path)
                k = register_key!(idx, abs)
                if !d.top_level
                    pushnamed!(idx.nested_defs, d.name, rel)
                    continue
                end
                pushnamed!(idx.module_defs, k, d.name)
                pushnamed!(idx.project_defs, d.name, rel)
                if d.kind == "module" || d.kind == "baremodule"
                    ck = register_key!(idx, vcat(abs, [d.name]))
                    pushnamed!(idx.module_by_name, d.name, ck)   # 模块自身作用域
                    pushnamed!(idx.submodule_names, k, d.name)
                    haskey(idx.submodule_parent, ck) || (idx.submodule_parent[ck] = k)
                end
            end
        end
    end

    # ---- 3. export ----
    for (pk, files) in idx.module_files
        base = path_of_key(idx, pk)
        for rel in files
            for dir in scans[rel].directives
                dir.kind == "export" || continue
                k = register_key!(idx, vcat(base, dir.module_path))
                for (n, _) in dir.names
                    pushnamed!(idx.module_exports, k, n)
                end
            end
        end
    end

    # ---- 4. using / import / 别名 → 本作用域可见绑定名 ----
    for (pk, files) in idx.module_files
        base = path_of_key(idx, pk)
        for rel in files
            s = scans[rel]
            for dir in s.directives
                dir.kind in ("using", "import") || continue
                kbase = vcat(base, dir.module_path)
                k = register_key!(idx, kbase)
                if dir.form == "names" || dir.form == "as"
                    for (_, loc) in dir.names
                        pushnamed!(idx.module_bound, k, loc)
                    end
                    if dir.form == "as"
                        dots, parts = parse_module_text(dir.modpath)
                        tpath = module_target_path(kbase, dots, parts)
                        tk = register_key!(idx, tpath)
                        isproj = haskey(idx.module_files, tk) && !isempty(idx.module_files[tk])
                        for (_, loc) in dir.names
                            idx.module_alias[k * "::" * loc] = isproj ? tk : ""
                        end
                    end
                    continue
                end
                dots, parts = parse_module_text(dir.modpath)
                isempty(parts) && continue
                tpath = module_target_path(kbase, dots, parts)
                tk = register_key!(idx, tpath)
                pushnamed!(idx.module_bound, k, parts[end])
                isproj = (haskey(idx.module_files, tk) && !isempty(idx.module_files[tk])) ||
                         (haskey(idx.module_defs, tk) && !isempty(idx.module_defs[tk])) ||
                         haskey(idx.submodule_names, tk)
                if isproj
                    exps = get(idx.module_exports, tk, EMPTY_NAMES)
                    names = isempty(exps) ? get(idx.module_defs, tk, EMPTY_NAMES) : exps
                    for n in names
                        pushnamed!(idx.module_bound, k, n)
                    end
                end
            end
            for al in s.aliases
                k = register_key!(idx, vcat(base, al.module_path))
                pushnamed!(idx.module_bound, k, al.name)
            end
        end
    end

    # ---- 5. 解析错误 / 动态点 / 清单 ----
    for rel in idx.order
        s = scans[rel]
        if !isempty(s.parse_error)
            push!(idx.parse_errors, ParseError(rel, s.parse_error_line, s.parse_error))
        end
        append!(idx.dynamic_sites, s.dynamic_sites)
    end
    sort!(idx.dynamic_sites; by = x -> (x.file, x.line))
    idx.inventory = compute_inventory(idx)
    return idx
end

"""`using .X` / `using ..X` 的相对模块解析：dots=1 为当前模块，2 为父模块…"""
function module_target_path(kbase::Vector{String}, dots::Int, parts::Vector{String})
    dots <= 0 && return copy(parts)
    cut = max(0, length(kbase) - (dots - 1))
    return vcat(kbase[1:cut], parts)
end

function compute_inventory(idx::RepoIndex)
    inv = Dict{String,Int}()
    inc!(c) = inv[c] = get(inv, c, 0) + 1
    inv["files"] = length(idx.order)
    inv["parse_errors"] = length(idx.parse_errors)
    for rel in idx.order
        s = idx.scans[rel]
        for d in s.defs
            if d.top_level
                inc!("defs_top")
                inc!("def_" * replace(d.kind, "-" => "_"))
                d.has_docstring && inc!("docstrings")
            else
                inc!("defs_nested")
            end
        end
        for dir in s.directives
            inc!(dir.kind)
            dir.form == "names" && inc!("directive_named")
            dir.form == "as" && inc!("directive_as")
        end
        inv["include_literal"] = get(inv, "include_literal", 0) + length(s.includes)
        for ds in s.dynamic_sites
            if ds.kind == "include-dynamic"
                inc!("include_dynamic")
            elseif ds.kind == "field-access"
                inc!("dynamic_field")
            elseif ds.kind == "symbol-construction"
                inc!("dynamic_symbol")
            elseif ds.kind == "absence-probe"
                inc!("dynamic_absence")
            else
                inc!("dynamic_" * replace(ds.kind, "@" => "at"))
            end
        end
        for al in s.aliases
            inc!("alias_" * al.kind)
        end
    end
    inv["dynamic_total"] = length(idx.dynamic_sites)
    inv["defs_nested_names"] = length(idx.nested_defs)
    inv["scopes"] = length(idx.key_paths)
    return inv
end

# ---------------------------------------------------------------------------
# 可解析性
# ---------------------------------------------------------------------------

"""引用点所属的文件 + 文件内相对模块路径 → 候选绝对作用域键。"""
function resolve_scope_keys(idx::RepoIndex, file::AbstractString, mpath::Vector{String})
    keys = String[]
    for base in get(idx.node_scopes, String(file), EMPTY_NAMES)
        if isempty(mpath)
            push!(keys, base)
        else
            push!(keys, mkey(vcat(path_of_key(idx, base), mpath)))
        end
    end
    isempty(keys) && push!(keys, mkey(mpath))
    return unique(keys)
end

"""名字在给定作用域键集合能否解析：defined / imported / submodule / external / unresolved。"""
function resolves_any(idx::RepoIndex, keys::Vector{String}, name::AbstractString)
    nm = String(name)
    for k in keys
        nm in get(idx.module_defs, k, EMPTY_NAMES) && return :defined
        nm in get(idx.module_bound, k, EMPTY_NAMES) && return :imported
        nm in get(idx.submodule_names, k, EMPTY_NAMES) && return :submodule
    end
    if isdefined(Base, Symbol(nm)) || isdefined(Core, Symbol(nm))
        return :external
    end
    return :unresolved
end

resolves_in(idx::RepoIndex, file::AbstractString, mpath::Vector{String}, name::AbstractString) =
    resolves_any(idx, resolve_scope_keys(idx, file, mpath), name)

"""
限定引用 `A.n` / `A.B.n` 里限定基座解析出的候选模块作用域键；
返回 `["*external*"]`（外部模块，成员无法静态判定）或 nothing（基座不是可判定模块）。

多段基座（t27：`MarsData.MarsCommon.get_angle`）：先解析首段，再逐段下降，
每段必须是当前候选作用域的子模块、或该作用域内已绑定且项目内确有其名的模块；
任一段不可判定即返回 nothing（调用侧记 NON_MODULE_BASE 提示，不判悬空）。
"""
function resolve_base_module(idx::RepoIndex, file::AbstractString, mpath::Vector{String},
                             base::AbstractString)
    isempty(base) && return nothing
    segments = String.(split(String(base), "."))
    splice!(segments, findall(isempty, segments))          # 容错：去掉空段
    isempty(segments) && return nothing
    first_seg = segments[1]
    keys = resolve_scope_keys(idx, file, mpath)
    local current::Vector{String}
    for k in keys
        ak = k * "::" * first_seg
        if haskey(idx.module_alias, ak)
            t = idx.module_alias[ak]
            return isempty(t) ? ["*external*"] : [t]
        end
    end
    resolved = nothing
    for k in keys
        if first_seg in get(idx.submodule_names, k, EMPTY_NAMES)
            resolved = [mkey(vcat(path_of_key(idx, k), [first_seg]))]
            break
        end
    end
    if resolved === nothing && haskey(idx.module_by_name, first_seg)
        resolved = sort(collect(idx.module_by_name[first_seg]))
    end
    if resolved === nothing
        for k in keys
            first_seg in get(idx.module_bound, k, EMPTY_NAMES) && return ["*external*"]
        end
        if isdefined(Base, Symbol(first_seg)) || isdefined(Core, Symbol(first_seg))
            return ["*external*"]
        end
        return nothing
    end
    current = resolved
    for seg in segments[2:end]
        next = String[]
        for k in current
            if seg in get(idx.submodule_names, k, EMPTY_NAMES)
                push!(next, mkey(vcat(path_of_key(idx, k), [seg])))
            end
            if (seg in get(idx.module_defs, k, EMPTY_NAMES) ||
                seg in get(idx.module_bound, k, EMPTY_NAMES)) && haskey(idx.module_by_name, seg)
                append!(next, sort(collect(idx.module_by_name[seg])))
            end
        end
        next = unique(next)
        isempty(next) && return nothing                    # 该段不是可判定模块
        current = next
    end
    return current
end

"""限定引用的成员是否能在目标模块中解析。"""
function member_resolves(idx::RepoIndex, targets::Vector{String}, name::AbstractString)
    all(t -> t == "*external*", targets) && return :external
    nm = String(name)
    for t in targets
        t == "*external*" && continue
        nm in get(idx.module_defs, t, EMPTY_NAMES) && return :defined
        nm in get(idx.submodule_names, t, EMPTY_NAMES) && return :submodule
    end
    return :unresolved
end

"""某文件里是否存在嵌套同名定义。"""
is_nested_name_file(idx::RepoIndex, name::AbstractString, file::AbstractString) =
    String(file) in get(idx.nested_defs, String(name), EMPTY_NAMES)

"""目标文件中的顶层定义（按名字过滤）。"""
top_defs(scan::FileScan, name::AbstractString) =
    [d for d in scan.defs if d.top_level && d.name == String(name)]

"""目标文件中的任意层级定义（按名字过滤）。"""
any_defs(scan::FileScan, name::AbstractString) =
    [d for d in scan.defs if d.name == String(name)]

"""目标定义（首个顶层定义）；没有则 nothing。"""
function target_definition(idx::RepoIndex, file::AbstractString, name::AbstractString)
    haskey(idx.scans, String(file)) || return nothing
    ds = top_defs(idx.scans[String(file)], name)
    return isempty(ds) ? nothing : ds[1]
end
