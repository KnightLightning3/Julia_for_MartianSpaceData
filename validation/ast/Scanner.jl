# =============================================================================
# Scanner.jl —— 单文件 AST 扫描（仅依赖 Base）
#
# 输入：一个 .jl 源文件 + 关注名称集合。
# 输出：FileScan ——
#   defs          : 全部定义（含嵌套），带 top_level / quoted / docstring / hash
#   directives    : using / import / export 指令项（含 as 别名）
#   includes      : include 的「字面量」路径边（解析失败的一律记入 dynamic_sites）
#   dynamic_sites : eval / getfield / Symbol(…) / 动态 include 等不可静态解析点
#   refs          : 只收集「关注名称」的引用点（调用 / 值 / 限定名）
#   aliases       : import-别名、using-别名、const 别名
#
# 扫描按 Meta.parse 的字节位置逐块推进：既不丢语句，也不把解析失败吞掉。
# =============================================================================

struct Definition
    name::String
    qualifier::String
    kind::String
    file::String
    line::Int
    top_level::Bool
    quoted::Bool
    module_path::Vector{String}
    has_docstring::Bool
    hash::String
end

struct Directive
    kind::String                            # using | import | export
    modpath::String                         # using/import 的模块路径文本（含前导点）
    names::Vector{Pair{String,String}}      # 目标名 => 本地名
    file::String
    line::Int
    module_path::Vector{String}
    form::String                            # module | names | as | export
end

struct IncludeEdge
    file::String
    included::String
    line::Int
    module_path::Vector{String}
end

struct DynamicSite
    kind::String                            # eval | @eval | field-access | symbol-construction | include-dynamic | absence-probe
    file::String
    line::Int
    module_path::Vector{String}
    unknown_name::Bool
    hint::String
    snippet::String
end

struct RefSite
    name::String
    file::String
    line::Int
    module_path::Vector{String}
    role::String                            # call | value | qualified | qualified-call | type
    base::String
    shadowed::Bool                          # true = 该名字在当前局部作用域被绑定（形参/局部变量…）→ 非全局引用
end

struct Alias
    name::String
    target::String
    base::String
    kind::String                            # using | import | const
    file::String
    line::Int
    module_path::Vector{String}
end

struct FileScan
    rel::String
    parse_error::String
    parse_error_line::Int
    defs::Vector{Definition}
    directives::Vector{Directive}
    includes::Vector{IncludeEdge}
    dynamic_sites::Vector{DynamicSite}
    refs::Vector{RefSite}
    aliases::Vector{Alias}
    str_consts::Dict{String,String}          # 模块级字符串常量（用于 include 路径静态求值）
end

empty_scan(rel::AbstractString; parse_error::AbstractString="", parse_error_line::Int=0) =
    FileScan(String(rel), String(parse_error), parse_error_line,
             Definition[], Directive[], IncludeEdge[], DynamicSite[], RefSite[], Alias[],
             Dict{String,String}())

# ---------------------------------------------------------------------------
# 动态构造的判定集合
# ---------------------------------------------------------------------------

const INCLUDE_FUNCS = Set{String}(["include", "Base.include", "Core.include"])
const EVAL_FUNCS = Set{String}(["eval", "Core.eval", "Base.eval", "invokelatest",
                                "Base.invokelatest", "Core.invokelatest"])
const FIELD_FUNCS = Set{String}(["getfield", "getproperty", "setfield!", "setproperty!",
                                 "getglobal", "setglobal!"])
const SYMBOL_FUNCS = Set{String}(["Symbol", "Base.Symbol"])
# 只做「存在性/缺失性」探测的调用：不取值、不调用，属于删除证据（例如
# @test !isdefined(M, :sta_v_4d_new)），不据此把单元判为 unknown。
const ABSENCE_FUNCS = Set{String}(["isdefined", "hasfield", "hasproperty", "Base.isdefined"])

is_literal_name(x) = (x isa QuoteNode && x.value isa Symbol) || x isa AbstractString

# ---------------------------------------------------------------------------
# 扫描状态与主循环
# ---------------------------------------------------------------------------

mutable struct WalkState
    scan::FileScan
    names::Set{String}
    rel::String
    root::String
    abs_dir::String
    abs_file::String
    module_stack::Vector{String}
    locals::Vector{Set{String}}             # 局部绑定栈（函数/匿名/let/for/推导式作用域）
    fn_depth::Int
    quote_depth::Int
    chunk_line::Int
end

"""按字节位置逐块解析；先做常量预扫（include 路径），再逐块遍历。

解析失败立即停止并记录（全仓校验据此非零退出）。刻意不用 Meta.parseall：
它对面 incomplete 输入是宽容的，会把真正的语法错误吞掉。
"""
function scan_source(src::String, rel::String, names::Set{String};
                     root::AbstractString="", abs_file::Union{Nothing,AbstractString}=nothing)
    startswith(src, "\ufeff") && (src = src[nextind(src, 1):end])
    absfile = abs_file === nothing ? abspath(joinpath(String(root), rel)) : String(abs_file)
    absdir = dirname(absfile)
    chunks = Tuple{Any,Int,Int}[]               # (expr, startbyte, startline)
    pos = 1
    last_pos = 1
    line = 1
    n = sizeof(src)
    guard = 0
    while pos <= n
        guard += 1
        if guard > 1_000_000
            return FileScan(rel, "解析块迭代超过上限，疑似解析器未推进", line, Definition[],
                            Directive[], IncludeEdge[], DynamicSite[], RefSite[], Alias[],
                            Dict{String,String}())
        end
        if pos > last_pos
            line += count(==(0x0a), codeunits(src)[last_pos:(pos - 1)])
            last_pos = pos
        end
        local ex, np
        try
            ex, np = Meta.parse(src, pos; raise=false, filename=rel)
        catch err
            return FileScan(rel, string("解析异常: ", sprint(showerror, err)), line, Definition[],
                            Directive[], IncludeEdge[], DynamicSite[], RefSite[], Alias[],
                            Dict{String,String}())
        end
        if ex isa Expr && (ex.head === :error || ex.head === :incomplete)
            msg, eline = parse_error_info(ex)
            # Meta.parse 从块起点开始解析，诊断里的行号是块内相对行号 → 换算成文件行号
            actual = eline > 0 ? line + eline - 1 : line
            if eline > 0 && line > 1
                msg = replace(msg, ":$eline:" => ":$actual:"; count=1)
            end
            return FileScan(rel, msg, actual, Definition[], Directive[],
                            IncludeEdge[], DynamicSite[], RefSite[], Alias[], Dict{String,String}())
        end
        push!(chunks, (ex, pos, line))
        np === nothing && break
        if np <= pos
            pos += 1
            continue
        end
        pos = np
    end

    scan = empty_scan(rel)
    consts = collect_str_consts(chunks, absdir, absfile)
    merge!(scan.str_consts, consts)             # include 路径求值需要它，必须在遍历前就绪
    st = WalkState(scan, names, rel, String(root), absdir, absfile, String[], Set{String}[], 0, 0, 1)
    for (ex, _, startline) in chunks
        st.chunk_line = startline
        walk!(st, ex, false)
    end
    return st.scan
end

"""预扫：收集模块级字符串绑定（`X = "..."`/`const X = ...`），支持后续 include 求值。"""
function collect_str_consts(chunks, abs_dir::AbstractString, abs_file::AbstractString)
    consts = Dict{String,String}()
    for (ex, _, _) in chunks
        collect_str_consts!(consts, ex, abs_dir, abs_file)
    end
    return consts
end

function collect_str_consts!(consts::Dict{String,String}, ex, abs_dir, abs_file)
    ex isa Expr || return
    if ex.head === :const
        inner = length(ex.args) == 1 ? ex.args[1] : nothing
        inner isa Expr && inner.head === :(=) &&
            add_str_const!(consts, inner.args[1], inner.args[2], abs_dir, abs_file)
    elseif ex.head === :(=)
        length(ex.args) == 2 && add_str_const!(consts, ex.args[1], ex.args[2], abs_dir, abs_file)
    elseif ex.head === :module || ex.head === :baremodule
        length(ex.args) >= 3 && collect_str_consts!(consts, ex.args[3], abs_dir, abs_file)
    elseif ex.head === :block || ex.head === :toplevel
        for a in ex.args
            collect_str_consts!(consts, a, abs_dir, abs_file)
        end
    end
    return
end

function add_str_const!(consts::Dict{String,String}, lhs, rhs, abs_dir, abs_file)
    lhs isa Symbol || return
    v = static_string_value(rhs, abs_dir, abs_file, consts)
    v === nothing && return
    consts[String(lhs)] = v
    return
end

function parse_error_info(ex)
    err = length(ex.args) >= 1 ? ex.args[1] : "解析失败"
    msg = try
        sprint(showerror, err)
    catch
        string(err)
    end
    msg = replace(msg, r"\s+" => " ")
    length(msg) > 240 && (msg = first(msg, 240) * "…")
    m = match(r":(\d+):(\d+)", msg)
    eline = m === nothing ? 0 : (tryparse(Int, m.captures[1]) === nothing ? 0 : parse(Int, m.captures[1]))
    return (msg, eline)
end

"""扫描仓库内某个相对路径的文件。"""
function scan_file(root::AbstractString, rel::AbstractString, names::Set{String})
    path = joinpath(String(root), String(rel))
    src = try
        read(path, String)
    catch err
        return empty_scan(rel; parse_error="读取失败: " * sprint(showerror, err))
    end
    return scan_source(src, String(rel), names; root=String(root), abs_file=abspath(path))
end

# ---------------------------------------------------------------------------
# 遍历
# ---------------------------------------------------------------------------

node_line(st::WalkState, ex) = (l = first_line(ex, 0); l > 0 ? l : st.chunk_line)

function register!(st::WalkState, name, qualifier, kind, ex, docstring::Bool)
    top = st.fn_depth == 0 && st.quote_depth == 0
    push!(st.scan.defs, Definition(String(name), String(qualifier), String(kind), st.rel,
                                   node_line(st, ex), top, st.quote_depth > 0,
                                   copy(st.module_stack), docstring, canonical_hash(ex)))
    return
end

# ---------------------------------------------------------------------------
# 局部绑定（形参 / 解构 / 赋值 / local / 内层函数名 / 循环变量 / let 绑定）
#
# 目的：形参等局部绑定与全局函数**不存在 Julia 命名冲突**，工具不得把它们当
# 全局引用报悬空（t26：rotate_vector(data, rotation_matrix) = rotation_matrix * data
# 的形参 rotation_matrix 曾因别处同名新函数被误报 DANGLING_REFERENCE）。
#
# 建模范围（刻意不做全 Julia 语义穷举）：
#   * 函数/短定义/匿名函数：形参（普通、::T、默认值、kwargs、splat、解构 tuple）
#     与 where 类型参数、体内赋值目标（含解构）、`local` 声明、循环变量、
#     let 绑定、推导式变量、内层函数名 → 视为「本作用域局部」；
#   * 显式 `global x` 声明优先：从局部集合中剔除，引用仍按全局判定（真悬空照报）；
#   * 作用域嵌套（let/for/推导式/匿名函数）各自压栈，互不污染；
#   * 无法静态判定的动态作用域（eval / @eval / 引号内）已由 dynamic_sites 报 unknown。
# ---------------------------------------------------------------------------

const ASSIGN_HEADS = Set{Symbol}(Symbol.(["=", "+=", "-=", "*=", "/=", "\\=", "^=", "%=", "&=",
                                          "|=", "⊻=", "÷=", "<<=", ">>=", ">>>=", "//=", "\$="]))

"""判断名字是否在当前任一局部作用域被绑定（形参/局部变量/内层函数名…）。"""
is_local_binding(st::WalkState, name::AbstractString) =
    any(s -> String(name) in s, st.locals)

"""从「绑定目标」表达式收集名字：Symbol / a::T / a... / kw / tuple 解构 / 内层短定义名。"""
function collect_binding_names!(set::Set{String}, tgt)
    if tgt isa Symbol
        push!(set, String(tgt))
    elseif tgt isa Expr
        h = tgt.head
        if h === :(::) || h === :(...) || h === :kw || h === :where
            collect_binding_names!(set, tgt.args[1])
        elseif h === :tuple || h === :parameters
            for a in tgt.args
                collect_binding_names!(set, a)
            end
        elseif h === :(=)
            collect_binding_names!(set, tgt.args[1])       # 解构里的默认值 a=b
        elseif h === :local || h === :global
            for a in tgt.args
                collect_binding_names!(set, a)
            end
        elseif h === :call
            # 内层短定义 `g(y) = …`：g 绑定在外层作用域（其参数/体是 g 自己的作用域）
            r = head_name(tgt.args[1])
            r === nothing || push!(set, r[1])
        end
        # :curly（类型应用，如匿名参数 ::Type{T}）与 :ref / :. 不是绑定目标，不收集
    end
    return set
end

"""从函数签名收集形参与 where 类型参数（不含类型名，类型引用不算绑定）。"""
function collect_param_bindings!(set::Set{String}, sig)
    if sig isa Symbol
        push!(set, String(sig))                            # function f end
    elseif sig isa Expr
        h = sig.head
        if h === :call
            for a in sig.args[2:end]
                collect_binding_names!(set, a)
            end
        elseif h === :where
            collect_param_bindings!(set, sig.args[1])
            for p in sig.args[2:end]                       # where {T<:Real, S}
                if p isa Symbol
                    push!(set, String(p))
                elseif p isa Expr && (p.head === :<: || p.head === :>:)
                    collect_binding_names!(set, p.args[1])
                elseif p isa Expr && p.head === :curly
                    for a in p.args
                        a isa Symbol && push!(set, String(a))
                    end
                end
            end
        elseif h === :(::) || h === :curly
            collect_param_bindings!(set, sig.args[1])
        end
    end
    return set
end

"""
扫函数体，收集该函数作用域内的局部绑定名（Julia 语义近似：函数体内被赋值的名字
在整函数内都是局部的）。显式 `global` 声明从局部集合剔除。

`descend_functions=false`：遇到内层 function/匿名函数不入内（只取内层函数名），
内层作用域由其自己的压栈处理。
"""
function scan_body_bindings!(set::Set{String}, globals::Set{String}, ex)
    ex isa Expr || return set
    h = ex.head
    if h in ASSIGN_HEADS
        if ex.args[1] isa Expr && ex.args[1].head === :call
            # 内层短定义：只把名字并进外层作用域，函数体归它自己的作用域
            info = definition_info(ex)
            info === nothing || push!(set, info[1])
            return set
        end
        collect_binding_names!(set, ex.args[1])
        scan_body_bindings!(set, globals, ex.args[end])
        return set
    elseif h === :local
        for a in ex.args
            collect_binding_names!(set, a)
        end
        return set
    elseif h === :global
        for a in ex.args
            if a isa Symbol
                push!(globals, String(a))
            elseif a isa Expr && a.head === :(=)
                collect_binding_names!(globals, a.args[1])
            end
        end
        return set
    elseif h === :function || h === :macro
        # 内层函数定义：名字绑定在「外层」作用域；其内部是它自己的作用域（不入内）
        info = definition_info(ex)
        info === nothing || push!(set, info[1])
        return set
    elseif h === :(->) || h === :quote
        return set                                          # 各自的作用域/引号内不并入
    elseif h === :do
        length(ex.args) >= 1 && scan_body_bindings!(set, globals, ex.args[1])
        return set
    else
        for a in ex.args
            scan_body_bindings!(set, globals, a)
        end
        return set
    end
end

"""函数作用域压栈：形参 + where 参数 + 体内绑定（`global` 声明剔除）。"""
function push_function_scope!(st::WalkState, sig, body)
    locals = Set{String}()
    globals = Set{String}()
    collect_param_bindings!(locals, sig)
    body === nothing || scan_body_bindings!(locals, globals, body)
    setdiff!(locals, globals)
    push!(st.locals, locals)
    return
end

function pop_scope!(st::WalkState)
    isempty(st.locals) || pop!(st.locals)
    return
end

"""按一组绑定目标表达式压入一个作用域（let/for/推导式）。"""
function push_binding_scope!(st::WalkState, targets)
    locals = Set{String}()
    for t in targets
        collect_binding_names!(locals, t)
    end
    push!(st.locals, locals)
    return
end

"""收集迭代说明里的绑定目标：支持 `for i in …` 与 `for i in …, j in …`（block 形式）。"""
function collect_iter_targets!(out::Vector{Any}, iter)
    if iter isa Expr && iter.head === :(=)
        push!(out, iter.args[1])
    elseif iter isa Expr && (iter.head === :block || iter.head === :tuple)
        for a in iter.args
            collect_iter_targets!(out, a)
        end
    elseif iter isa Expr && iter.head === :outer
        collect_iter_targets!(out, iter.args[1])
    elseif iter !== nothing
        push!(out, iter)
    end
    return out
end

function add_ref!(st::WalkState, name, role, base, line::Int)
    String(name) in st.names || return
    # 引号 / @eval 内部的引用不是静态调用点：记 role=quoted，由 Checks 报 unknown
    r = st.quote_depth > 0 ? "quoted" : String(role)
    shadowed = is_local_binding(st, String(name))
    # 限定引用 A.n 的基座 A 若是局部绑定（形参/局部变量），整条引用同样不是全局引用
    if !shadowed && !isempty(base) && (r == "qualified" || r == "qualified-call")
        shadowed = is_local_binding(st, first(String.(split(String(base), "."))))
    end
    push!(st.scan.refs, RefSite(String(name), st.rel, line > 0 ? line : st.chunk_line,
                                copy(st.module_stack), r, String(base), shadowed))
    return
end

function add_value_ref!(st::WalkState, x)
    x isa Symbol && return add_ref!(st, String(x), "value", "", 0)
    x isa Expr && return walk!(st, x, false)
    return
end

function push_dynamic!(st::WalkState, kind, ex, line::Int; unknown_name::Bool, hint::AbstractString="")
    push!(st.scan.dynamic_sites,
          DynamicSite(String(kind), st.rel, line > 0 ? line : st.chunk_line,
                      copy(st.module_stack), unknown_name, String(hint), snippet(ex)))
    return
end

function add_alias!(st::WalkState, localname, rhs, line::Int, kind::AbstractString)
    localname === nothing && return
    if rhs isa Symbol
        push!(st.scan.aliases, Alias(String(localname), String(rhs), "", String(kind), st.rel,
                                     line > 0 ? line : st.chunk_line, copy(st.module_stack)))
    elseif rhs isa Expr && rhs.head === :. && length(rhs.args) == 2
        mem = member_text(rhs.args[2])
        mem === nothing && return
        push!(st.scan.aliases, Alias(String(localname), mem, qualifier_text(rhs.args[1]),
                                     String(kind), st.rel, line > 0 ? line : st.chunk_line,
                                     copy(st.module_stack)))
    end
    return
end

function walk!(st::WalkState, ex, docstring::Bool)
    if ex === nothing || ex isa LineNumberNode
        return
    elseif ex isa Symbol
        return add_ref!(st, String(ex), "value", "", 0)
    elseif !(ex isa Expr)
        return
    end
    h = ex.head
    if h === :macrocall
        return walk_macrocall!(st, ex, docstring)
    elseif h === :using || h === :import
        return walk_directive!(st, String(h), ex.args)
    elseif h === :export
        return walk_export!(st, ex.args)
    elseif h === :module || h === :baremodule
        return walk_module!(st, ex, docstring)
    elseif h === :function || h === :macro
        return walk_function!(st, ex, docstring, h === :macro ? "macro" : "function")
    elseif h === :struct || h === :mutable
        return walk_struct!(st, ex, docstring)
    elseif h === :const
        return walk_const!(st, ex, docstring)
    elseif h === :(=)
        return walk_assign!(st, ex, docstring)
    elseif h === :call
        handle_special_call!(st, ex)
        add_callee_ref!(st, ex.args[1], node_line(st, ex))
        for a in ex.args[2:end]
            walk!(st, a, false)
        end
        return
    elseif h === :.
        return walk_dot!(st, ex)
    elseif h === :quote
        st.quote_depth += 1
        for a in ex.args
            walk!(st, a, false)
        end
        st.quote_depth -= 1
        return
    elseif h === :(->)
        # 匿名函数：形参 + 体内绑定进局部作用域；只遍历函数体
        params = length(ex.args) >= 2 ? ex.args[1] : nothing
        body = ex.args[end]
        locals = Set{String}()
        globals = Set{String}()
        params isa Expr && (collect_param_bindings!(locals, params))
        params isa Symbol && push!(locals, String(params))
        length(ex.args) >= 2 && scan_body_bindings!(locals, globals, body)
        setdiff!(locals, globals)
        push!(st.locals, locals)
        st.fn_depth += 1
        walk!(st, body, false)
        st.fn_depth -= 1
        pop_scope!(st)
        return
    elseif h === :let
        targets = Any[]
        for (i, a) in enumerate(ex.args)
            i == length(ex.args) && break
            a isa Expr && a.head === :(=) && push!(targets, a.args[1])
        end
        push_binding_scope!(st, targets)
        st.fn_depth += 1
        for (i, a) in enumerate(ex.args)
            if i == length(ex.args)
                walk!(st, a, false)
            elseif a isa Expr && a.head === :(=)
                walk!(st, a.args[2], false)
            elseif a isa Expr
                walk!(st, a, false)
            end
        end
        st.fn_depth -= 1
        pop_scope!(st)
        return
    elseif h === :kw
        length(ex.args) == 2 || return
        return walk!(st, ex.args[2], false)     # 关键字名不是引用
    elseif h === :parameters
        for a in ex.args
            if a isa Expr && a.head === :kw
                walk!(st, a.args[2], false)
            elseif a isa Expr && a.head === :(...)
                walk!(st, a.args[1], false)
            else
                walk!(st, a, false)
            end
        end
        return
    elseif h === :generator || h === :comprehension || h === :flatten
        targets = Any[]
        for a in ex.args
            (a isa Expr && a.head === :(=)) && collect_iter_targets!(targets, a)
        end
        push_binding_scope!(st, targets)
        st.fn_depth += 1
        for a in ex.args
            walk!(st, a, false)
        end
        st.fn_depth -= 1
        pop_scope!(st)
        return
    elseif h === :for
        length(ex.args) >= 2 || return
        iter = ex.args[1]
        targets = Any[]
        collect_iter_targets!(targets, iter)
        push_binding_scope!(st, targets)
        st.fn_depth += 1
        walk!(st, iter isa Expr && iter.head === :(=) ? iter.args[2] : iter, false)
        walk!(st, ex.args[2], false)
        st.fn_depth -= 1
        pop_scope!(st)
        return
    else
        for a in ex.args
            walk!(st, a, false)
        end
        return
    end
end

function walk_macrocall!(st::WalkState, ex, docstring::Bool)
    mname = macro_name(ex.args[1])
    if mname !== nothing && mname in DOC_MACROS
        for a in ex.args[3:end]
            a isa LineNumberNode && continue
            walk!(st, a, true)
        end
        return
    elseif mname !== nothing && mname == "@eval"
        push_dynamic!(st, "@eval", ex, node_line(st, ex); unknown_name=true, hint=literal_hint(ex))
        st.quote_depth += 1                      # @eval 的代码在动态作用域执行
    elseif mname !== nothing && startswith(mname, "@__")
        return
    end
    for a in ex.args[2:end]
        a isa LineNumberNode && continue
        walk!(st, a, false)
    end
    mname !== nothing && mname == "@eval" && (st.quote_depth -= 1)
    return
end

function walk_module!(st::WalkState, ex, docstring::Bool)
    info = definition_info(ex)
    info === nothing && return
    register!(st, info[1], info[2], info[3], ex, docstring)
    push!(st.module_stack, info[1])
    length(ex.args) >= 3 && walk!(st, ex.args[3], false)
    pop!(st.module_stack)
    return
end

function walk_struct!(st::WalkState, ex, docstring::Bool)
    info = definition_info(ex)
    info === nothing && return
    register!(st, info[1], info[2], info[3], ex, docstring)
    st.fn_depth += 1
    walk!(st, ex.args[end], false)
    st.fn_depth -= 1
    return
end

function walk_function!(st::WalkState, ex, docstring::Bool, kind::String)
    if length(ex.args) == 1
        sig = ex.args[1]
        body = nothing
    else
        sig = ex.args[1]
        body = ex.args[2]
    end
    info = signature_name(sig)
    info === nothing || register!(st, info[1], info[2], kind, ex, docstring)
    push_function_scope!(st, sig, body)                 # 形参/where 参数/体内绑定进局部作用域
    st.fn_depth += 1
    walk_signature!(st, sig)
    body === nothing || walk!(st, body, false)
    st.fn_depth -= 1
    pop_scope!(st)
    return
end

function walk_const!(st::WalkState, ex, docstring::Bool)
    inner = length(ex.args) == 1 ? ex.args[1] : nothing
    if inner isa Expr && inner.head === :(=)
        info = definition_info(ex)
        info === nothing || register!(st, info[1], info[2], info[3], ex, docstring)
        lhs, rhs = inner.args[1], inner.args[2]
        info === nothing || add_alias!(st, info[1], rhs, node_line(st, ex), "const")
        walk!(st, rhs, false)
        walk_lhs_refs!(st, lhs)
    else
        for a in ex.args
            walk!(st, a, false)
        end
    end
    return
end

function walk_assign!(st::WalkState, ex, docstring::Bool)
    length(ex.args) == 2 || return
    lhs, rhs = ex.args[1], ex.args[2]
    info = definition_info(ex)
    top = st.fn_depth == 0 && st.quote_depth == 0
    if info !== nothing && info[3] == "shortdef"
        register!(st, info[1], info[2], "shortdef", ex, docstring)
        push_function_scope!(st, lhs, rhs)              # 短定义同样有局部作用域（形参遮蔽）
        st.fn_depth += 1
        walk_signature!(st, lhs)
        walk!(st, rhs, false)
        st.fn_depth -= 1
        pop_scope!(st)
        return
    end
    if info !== nothing
        # 普通赋值只在模块级登记为定义；函数体内是局部变量，不登记
        (info[3] != "binding" || top) && register!(st, info[1], info[2], info[3], ex, docstring)
    end
    walk!(st, rhs, false)
    walk_lhs_refs!(st, lhs)
    return
end

"""函数签名里的类型/限定名引用；参数名与被定义名不算引用。"""
function walk_signature!(st::WalkState, sig)
    sig isa Symbol && return
    sig isa Expr || return
    h = sig.head
    if h === :call
        for a in sig.args[2:end]
            walk_signature!(st, a)
        end
    elseif h === :where || h === :parameters || h === :tuple || h === :curly ||
           h === :block || h === :vect
        for a in sig.args
            walk_signature!(st, a)
        end
    elseif h === :(::)
        walk_signature!(st, length(sig.args) == 2 ? sig.args[2] : sig.args[1])
    elseif h === :kw || h === :(=)
        walk_signature!(st, sig.args[end])
    elseif h === :<: || h === :>:
        length(sig.args) >= 2 && walk_signature!(st, sig.args[2])
    elseif h === :.
        mem = member_text(sig.args[end])
        mem === nothing || add_ref!(st, mem, "qualified", qualifier_text(sig.args[1]), node_line(st, sig))
    else
        for a in sig.args
            if a isa Symbol
                add_ref!(st, String(a), "type", "", node_line(st, sig))
            elseif a isa Expr
                walk_signature!(st, a)
            end
        end
    end
    return
end

function walk_lhs_refs!(st::WalkState, lhs)
    lhs isa Expr || return
    h = lhs.head
    if h === :. || h === :ref || h === :call
        for a in lhs.args
            a isa QuoteNode && continue
            walk!(st, a, false)
        end
    elseif h === :(::)
        length(lhs.args) == 2 && walk!(st, lhs.args[2], false)
    elseif h === :tuple
        for a in lhs.args
            walk_lhs_refs!(st, a)
        end
    elseif h === :curly
        for a in lhs.args[2:end]
            walk!(st, a, false)
        end
    end
    return
end

function walk_dot!(st::WalkState, ex)
    if length(ex.args) == 2
        base, mem = ex.args
        if mem isa QuoteNode && mem.value isa Symbol
            add_ref!(st, String(mem.value), "qualified", qualifier_text(base), node_line(st, ex))
            add_value_ref!(st, base)
            return
        end
    end
    for a in ex.args
        a isa Symbol && a === Symbol(".") && continue
        walk!(st, a, false)
    end
    return
end

function add_callee_ref!(st::WalkState, f, line::Int)
    if f isa Symbol
        add_ref!(st, String(f), "call", "", line)
    elseif f isa Expr && f.head === :. && length(f.args) == 2 &&
           f.args[2] isa QuoteNode && f.args[2].value isa Symbol
        add_ref!(st, String(f.args[2].value), "qualified-call", qualifier_text(f.args[1]), line)
        add_value_ref!(st, f.args[1])
    elseif f isa Expr && f.head === :curly
        add_callee_ref!(st, f.args[1], line)
    elseif f isa Expr && f.head === :(::)
        add_callee_ref!(st, f.args[1], line)
    end
    return
end

"""include / eval / getfield / Symbol(…) 等特殊调用。返回 true 表示参数已被消费。"""
function handle_special_call!(st::WalkState, ex)
    isempty(ex.args) && return false
    fn = call_plain_name(ex.args[1])
    fn === nothing && return false
    line = node_line(st, ex)
    if fn in INCLUDE_FUNCS || endswith(fn, ".include")
        nargs = length(ex.args) - 1
        path_ex = nargs == 1 ? ex.args[2] : (nargs == 2 ? ex.args[3] : nothing)
        if path_ex === nothing
            push_dynamic!(st, "include-dynamic", ex, line; unknown_name=true, hint=literal_hint(ex))
            return true
        end
        resolved = resolve_include_target(st.root, st.rel, path_ex, st.abs_dir, st.abs_file,
                                          st.scan.str_consts)
        if resolved === nothing
            push_dynamic!(st, "include-dynamic", ex, line; unknown_name=true, hint=literal_hint(ex))
            return true
        end
        push!(st.scan.includes, IncludeEdge(st.rel, resolved, line, copy(st.module_stack)))
        return true
    elseif fn in EVAL_FUNCS
        push_dynamic!(st, "eval", ex, line; unknown_name=true, hint=literal_hint(ex))
        return false
    elseif fn in FIELD_FUNCS
        namearg = length(ex.args) >= 3 ? ex.args[3] : nothing
        literal = namearg !== nothing && is_literal_name(namearg)
        push_dynamic!(st, "field-access", ex, line;
                      unknown_name = !literal,
                      hint = namearg === nothing ? "" : literal_hint(namearg))
        return false
    elseif fn in SYMBOL_FUNCS
        arg = length(ex.args) >= 2 ? ex.args[2] : nothing
        literal = arg !== nothing && is_literal_name(arg)
        push_dynamic!(st, "symbol-construction", ex, line;
                      unknown_name = !literal,
                      hint = arg === nothing ? "" : literal_hint(arg))
        return false
    elseif fn in ABSENCE_FUNCS
        arg = length(ex.args) >= 2 ? ex.args[end] : nothing
        push_dynamic!(st, "absence-probe", ex, line;
                      unknown_name=false,
                      hint = arg === nothing ? "" : literal_hint(arg))
        return false
    end
    return false
end

function walk_directive!(st::WalkState, kind::String, args)
    line = st.chunk_line
    for a in args
        a isa LineNumberNode && continue
        process_directive_item!(st, kind, a, line)
    end
    return
end

function process_directive_item!(st::WalkState, kind::String, a, line::Int)
    if a isa Symbol
        push!(st.scan.directives, Directive(kind, String(a), Pair{String,String}[], st.rel,
                                            line, copy(st.module_stack), "module"))
    elseif a isa Expr && a.head === :as
        tgt = dotted_text(a.args[1])
        loc = name_of_literal(a.args[2])
        loc === nothing && (loc = dotted_text(a.args[2]))
        (tgt == "" || loc === nothing || loc == "") && return
        push!(st.scan.directives, Directive(kind, tgt, [tgt => loc], st.rel, line,
                                            copy(st.module_stack), "as"))
        push!(st.scan.aliases, Alias(loc, tgt, "", kind, st.rel, line, copy(st.module_stack)))
    elseif a isa Expr && a.head === :(:)
        mod = dotted_text(a.args[1])
        names = Pair{String,String}[]
        for n in a.args[2:end]
            if n isa Expr && n.head === :as
                t = name_of_literal(n.args[1])
                t === nothing && (t = dotted_text(n.args[1]))
                l = name_of_literal(n.args[2])
                l === nothing && (l = dotted_text(n.args[2]))
            else
                t = name_of_literal(n)
                t === nothing && (t = dotted_text(n))
                l = t
            end
            (t === nothing || t == "") && continue
            (l === nothing || l == "") && (l = t)
            push!(names, t => l)
            push!(st.scan.aliases, Alias(l, t, mod, kind, st.rel, line, copy(st.module_stack)))
        end
        push!(st.scan.directives, Directive(kind, mod, names, st.rel, line,
                                            copy(st.module_stack), "names"))
    elseif a isa Expr && a.head === :.
        push!(st.scan.directives, Directive(kind, dotted_text(a), Pair{String,String}[], st.rel,
                                            line, copy(st.module_stack), "module"))
    end
    return
end

function walk_export!(st::WalkState, args)
    names = Pair{String,String}[]
    for a in args
        a isa LineNumberNode && continue
        nm = name_of_literal(a)
        nm === nothing && continue
        push!(names, nm => nm)
    end
    isempty(names) && return
    push!(st.scan.directives, Directive("export", "", names, st.rel, st.chunk_line,
                                        copy(st.module_stack), "export"))
    return
end
