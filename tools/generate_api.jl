#!/usr/bin/env julia

"""Generate a deterministic, static index of the repository's production Julia sources."""
module GenerateAPI

const ROOT = normpath(joinpath(@__DIR__, ".."))

struct Entry
    kind::Symbol
    name::String
    summary::String
    exported::Bool
end

struct FileIndex
    path::String
    modules::Vector{String}
    entries::Vector{Entry}
end

const SOURCE_ROOTS = ["src", "common", "MAVEN_data", "MGS_data", "TW_data",
                      "models", "analysis", "support_data"]
const EXTRA_FILES = ["call_fortran_dll.jl"]

function source_files(root::AbstractString=ROOT)
    files = String[]
    for rel in SOURCE_ROOTS
        dir = joinpath(root, rel)
        isdir(dir) || continue
        for (base, dirs, names) in walkdir(dir)
            filter!(d -> !(rel == "MAVEN_data" && d == "Build_data"), dirs)
            for name in names
                endswith(name, ".jl") || continue
                push!(files, relpath(joinpath(base, name), root))
            end
        end
    end
    for rel in EXTRA_FILES
        isfile(joinpath(root, rel)) && push!(files, rel)
    end
    sort!(unique!(files))
    return files
end

function encoded_source_url(path)
    safe = Set(codeunits("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/"))
    encoded = IOBuffer()
    for byte in codeunits(replace(path, "\\" => "/"))
        if byte in safe
            write(encoded, byte)
        else
            write(encoded, "%")
            write(encoded, uppercase(string(byte; base=16, pad=2)))
        end
    end
    return "https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/" * String(take!(encoded))
end

function initial_scope(rel)
    rel in ("src/modules.jl", "src/plotting.jl") && return ["MarsData"]
    startswith(rel, "common/marscommon/") && return ["MarsCommon"]
    return String[]
end

function scope_note(rel)
    rel in ("src/modules.jl", "src/plotting.jl") && return "归属模块：`MarsData`（由包入口 include）"
    startswith(rel, "common/marscommon/") && return "归属模块：`MarsCommon`（由 `common/MarsCommon.jl` include）"
    return nothing
end

function expr_name(x)
    x isa Symbol && return string(x)
    x isa GlobalRef && return string(x.name)
    x isa QuoteNode && return x.value isa Symbol ? string(x.value) : nothing
    x isa Expr || return nothing
    if x.head === :call || x.head === :where || x.head === :(::) || x.head === :curly
        return expr_name(x.args[1])
    elseif x.head === :.
        return join(filter(!isnothing, expr_name.(x.args)), ".")
    end
    return nothing
end

function first_sentence(doc)
    doc isa AbstractString || return ""
    # Julia docstrings commonly start with a four-space usage signature. Skip it;
    # retain only the first prose sentence and never copy whole docstrings.
    for raw in split(strip(doc), '\n')
        line = strip(raw)
        isempty(line) && continue
        startswith(raw, "    ") && continue
        # Usage signatures are the first line in many Julia docstrings; strip
        # them so the index records a responsibility sentence, not a signature.
        if occursin('(', line) && occursin(')', line) &&
           (occursin("->", line) || !occursin(' ', first(line, findfirst('(', line))))
            continue
        end
        startswith(line, "#") && continue
        stop = nothing
        for i in eachindex(line)
            c = line[i]
            if c in ('。', '！', '？')
                stop = i
                break
            elseif c == '.'
                j = nextind(line, i)
                if j > lastindex(line) || isspace(line[j])
                    stop = i
                    break
                end
            end
        end
        return stop === nothing ? line : strip(line[firstindex(line):stop])
    end
    return ""
end

function registry_allowlist(root::AbstractString=ROOT)
    path = joinpath(root, "src", "modules.jl")
    isfile(path) || return Dict{String,Vector{String}}()
    ast = Meta.parseall(read(path, String); filename="src/modules.jl")
    result = Dict{String,Vector{String}}()
    function visit(ex)
        ex isa Expr || return
        if ex.head === :call && !isempty(ex.args) && ex.args[1] === :_spec
            positional = filter(x -> !(x isa Expr && x.head === :parameters), ex.args[2:end])
            name = !isempty(positional) && positional[1] isa QuoteNode ? string(positional[1].value) : nothing
            params = findfirst(x -> x isa Expr && x.head === :parameters, ex.args)
            if name !== nothing && params !== nothing
                for kw in ex.args[params].args
                    kw isa Expr && kw.head === :kw && kw.args[1] === :allow || continue
                    vals = kw.args[2]
                    if vals isa Expr && vals.head === :vect
                        allowed = String[string(v.value) for v in vals.args if v isa QuoteNode]
                        isempty(allowed) || (result[name] = sort!(allowed))
                    end
                end
            end
        end
        foreach(visit, ex.args)
    end
    visit(ast)
    return result
end

function doc_and_definition(ex)
    if ex isa Expr && ex.head === :macrocall && !isempty(ex.args)
        macro_name = expr_name(ex.args[1])
        if macro_name == "@doc"
            vals = filter(x -> !(x isa LineNumberNode), ex.args[2:end])
            if length(vals) >= 2
                definition, _ = doc_and_definition(vals[end])
                return (definition, first_sentence(vals[end-1]))
            end
        elseif macro_name in ("@inline", "@noinline")
            vals = filter(x -> !(x isa LineNumberNode), ex.args[2:end])
            isempty(vals) || return doc_and_definition(vals[end])
        end
    end
    return (ex, "")
end

function function_name(def)
    def isa Expr || return nothing
    if def.head === :function && !isempty(def.args)
        return expr_name(def.args[1])
    elseif def.head === :(=) && length(def.args) >= 2
        signature = call_signature(def.args[1])
        return signature === nothing ? nothing : expr_name(signature)
    end
    return nothing
end

function call_signature(lhs)
    lhs isa Expr || return nothing
    if lhs.head === :call
        return lhs
    elseif lhs.head in (:(::), :where, :curly) && !isempty(lhs.args)
        return call_signature(lhs.args[1])
    end
    return nothing
end

function is_short_function(def)
    def isa Expr && def.head === :(=) && length(def.args) >= 2 &&
        call_signature(def.args[1]) !== nothing
end

function check_parse_errors!(ex, path)
    ex isa Expr || return
    ex.head in (:error, :incomplete) && error("静态解析失败: $path: $(ex)")
    foreach(x -> check_parse_errors!(x, path), ex.args)
end

function export_map(root, files)
    exports = Dict{String,Set{String}}()
    function visit(ex, scope, path)
        ex isa Expr || return
        if ex.head === :toplevel || ex.head === :block
            foreach(child -> visit(child, scope, path), ex.args)
        elseif ex.head === :module || ex.head === :baremodule
            visit(ex.args[end], vcat(scope, string(ex.args[2])), path)
        elseif ex.head === :export
            module_name = join(scope, ".")
            names = get!(exports, module_name, Set{String}())
            for item in ex.args
                name = expr_name(item)
                name === nothing || push!(names, name)
            end
        end
    end
    for rel in files
        text = read(joinpath(root, rel), String)
        ast = Meta.parseall(text; filename=rel)
        check_parse_errors!(ast, rel)
        visit(ast, initial_scope(rel), rel)
    end
    return exports
end

function index_file(root, rel, exports_by_module=Dict{String,Set{String}}())
    text = read(joinpath(root, rel), String)
    ast = Meta.parseall(text; filename=rel)
    check_parse_errors!(ast, rel)
    entries = Entry[]
    modules = String[]

    function visit(ex, scope::Vector{String}; top=true, pending_doc="")
        ex isa Expr || return
        if ex.head === :toplevel || ex.head === :block
            for child in ex.args
                child isa LineNumberNode && continue
                target, doc = doc_and_definition(child)
                if target !== child
                    visit(target, scope; top=true, pending_doc=doc)
                else
                    visit(child, scope; top=true, pending_doc="")
                end
            end
        elseif ex.head === :module || ex.head === :baremodule
            name = string(ex.args[2])
            full = isempty(scope) ? name : join(vcat(scope, name), ".")
            push!(modules, full)
            visit(ex.args[end], vcat(scope, name); top=true)
        elseif ex.head === :export
            # Export names are resolved after indexing, across files in the same module.
        elseif ex.head === :function || is_short_function(ex)
            name = function_name(ex)
            name === nothing && return
            fq = isempty(scope) ? name : join(vcat(scope, name), ".")
            module_name = join(scope, ".")
            push!(entries, Entry(:function, fq, pending_doc, name in get(exports_by_module, module_name, Set{String}())))
            # Do not walk the body: nested functions and local lambdas are not API entries.
        end
        return
    end
    visit(ast, initial_scope(rel))
    return FileIndex(rel, sort!(unique!(modules)), sort!(entries; by=e -> (e.name, e.kind)))
end

function escape_md(s)
    replace(s, "|" => "\\|")
end

function render(root::AbstractString=ROOT)
    files = source_files(root)
    exports_by_module = export_map(root, files)
    indexes = [index_file(root, p, exports_by_module) for p in files]
    allowlist = registry_allowlist(root)
    out = String["# 程序与 Julia 函数索引", "",
        "本页由 `tools/generate_api.jl` 使用 Julia 标准库 `Meta.parseall` 从生产源码静态生成；不加载项目环境、科学依赖、数据或 DLL。", "",
        "## 当前架构", "",
        "`using MarsData` 的包初始化会加载绘图栈和 `MAVEN_plot`，提供路径/注册表/索引接口并装配绘图；它不加载科学数据 loader。`src/modules.jl` 管理按需装载的科学模块。`common/` 放共享常量、路径、数据键与计算能力；`MAVEN_data/`、`MGS_data/`、`TW_data/` 和 `support_data/` 放各数据源读取与处理；`models/` 放物理模型；`analysis/` 是依赖预设变量的分析脚本。Python 负责配置、下载和本地文件流水线。", "",
        "本索引反映当前源码形状，不构成稳定公开 API 承诺。调用时优先使用限定名（如 `MAVEN_load.load_MAVEN_data`）。模块内 `export` 表示 Julia 模块导出；`MarsData.@load` 的裸名则由 `src/modules.jl` 的 `ModuleSpec.allow` 白名单逐名控制，两者相互独立。", "",
        "当前注册表的裸名白名单（从 `src/modules.jl` 静态读取）：", "",
        "| 模块 | `@load` 可裸名调用 |", "| --- | --- |"]
    if isempty(allowlist)
        push!(out, "| （未配置） | — |")
    else
        for name in sort!(collect(keys(allowlist)))
            push!(out, "| `$(name)` | " * join(("`$(x)`" for x in allowlist[name]), "、") * " |")
        end
    end
    append!(out, ["",
        "- 架构说明：[architecture.md](architecture.md)",
        "- 迁移说明：[migration.md](migration.md)",
        "- 配置、下载、扫描到读取流程：[pipeline.md](pipeline.md)", "",
        "## Python 程序职责", "",
        "| 路径 | 职责 |", "| --- | --- |",
        "| `martian_pipeline/`、`python -m martian_pipeline` | 统一 CLI 入口（扫描、检查与维护） |",
        "| `download_data/MAVEN_download.py` | MAVEN 数据下载，并在完成后触发扫描刷新 |",
        "| `config/`、`download_data/initialize_download_parameters.py` | Julia/Python 共用 TOML 配置与模板初始化 |",
        "| `martian_pipeline/inventory.py`、`tools/scan_and_index.py` | 本地文件扫描、产品清单和索引生成 |",
        "| `tools/push_wiki.py`、`MAVEN_data/build_read_me.py` | Wiki 页面发布与数据产品说明生成 |", "",
        "## Julia 源码索引", "",
        "仅索引模块定义与顶层函数定义（包括短定义）；函数体内的局部函数和 lambda 不列入。用途摘录限于已有 docstring 首句，没有 docstring 的条目不推断语义。`export` 标记按扫描文件中的静态声明和完整模块作用域聚合（包括跨文件 include 关系）；不推断运行期生成的导出。源码链接使用 GitLab 仓库绝对 URL，只指向文件，不依赖行号。", ""]
    )
    for idx in indexes
        suffix = startswith(idx.path, "analysis/") || startswith(idx.path, "models/extras/") ? "（脚本/附加代码；非 `load_module`）" : ""
        push!(out, "### [`$(idx.path)`]($(encoded_source_url(idx.path)))$suffix", "")
        note = scope_note(idx.path)
        note === nothing || push!(out, note, "")
        isempty(idx.modules) || push!(out, "模块：" * join(("`$(m)`" for m in idx.modules), "、"), "")
        if isempty(idx.entries)
            push!(out, "未发现顶层函数定义。", "")
            continue
        end
        push!(out, "| 限定名/函数名 | 标记 | docstring 首句 |", "| --- | --- | --- |")
        for e in idx.entries
            mark = e.exported ? "`export`" : "—"
            push!(out, "| `$(escape_md(e.name))` | $mark | $(escape_md(e.summary)) |")
        end
        push!(out, "")
    end
    push!(out, "## 非模块脚本", "",
          "`analysis/Pickup_ion.jl` 含交互式分析流程，依赖预先设置的事件变量；它是脚本入口，不能经 `MarsData.load_module` 装载。`models/extras/` 下的 Graham/Octree 为独立附加代码，不在模块注册表中，也不能经 `load_module` 装载。", "",
          "`call_fortran_dll.jl` 提供动态库调用封装；索引只解析其语法，不会加载或调用 DLL。", "")
    return join(out, "\n")
end

function output_path(arg, root)
    target = abspath(arg)
    isdir(target) && return joinpath(target, "api.md")
    endswith(arg, "/") && return joinpath(target, "api.md")
    isempty(splitext(target)[2]) && return joinpath(target, "api.md")
    return target
end

function main(args=ARGS)
    check = false
    dest = joinpath(ROOT, "docs", "src", "api.md")
    i = 1
    while i <= length(args)
        if args[i] in ("--help", "-h")
            println("用法：julia --startup-file=no tools/generate_api.jl [--check] [--output DIR|FILE]")
            println("默认写入 docs/src/api.md；--check 只比较、不写入；DIR 输出为 DIR/api.md。")
            return 0
        elseif args[i] == "--check"
            check = true
        elseif args[i] == "--output"
            i += 1
            i <= length(args) || error("--output 需要 DIR 或 FILE")
            dest = output_path(args[i], ROOT)
        else
            error("未知参数: $(args[i])")
        end
        i += 1
    end
    generated = render(ROOT)
    if check
        if !isfile(dest) || read(dest, String) != generated
            println(stderr, "API 文档已过期：$(relpath(dest, ROOT))")
            return 1
        end
        println("API 文档是最新的：$(relpath(dest, ROOT))")
        return 0
    end
    mkpath(dirname(dest))
    write(dest, generated)
    println("已生成：$(relpath(dest, ROOT))")
    return 0
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    exit(GenerateAPI.main())
end
