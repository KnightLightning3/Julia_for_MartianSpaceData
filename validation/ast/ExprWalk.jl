# =============================================================================
# ExprWalk.jl —— Julia 表达式层工具（仅依赖 Base / SHA）
#
# 本文件不是独立模块，由 validation/ast/ASTMigrate.jl 以 include 方式组装。
#
# 职责：
#   * 去掉 LineNumberNode，生成与行号/空白无关的规范化源码文本与 SHA-256；
#   * 从定义表达式抽取名称、限定名与定义种类（function / 短定义 / module /
#     struct / const / 普通绑定）；
#   * 解析 using / import / export 指令项与限定名（Expr(:.)）结构；
#   * 解析 include 的字面量路径（含 joinpath / @__DIR__ / @__FILE__）。
#
# 说明：本校验器只做「可静态解析」的判断，任何无法静态解析的动态写法都
# 必须显式报告为 unknown，绝不默认安全（见 Scanner/Checks）。
# =============================================================================

"""递归去除 LineNumberNode，得到与行号无关的 AST。"""
function strip_linenums(ex)
    ex isa Expr || return ex
    args = Any[]
    for a in ex.args
        a isa LineNumberNode && continue
        push!(args, strip_linenums(a))
    end
    return Expr(ex.head, args...)
end

"""规范化源码文本：结构化序列化（去行号、不依赖打印器）。

该文本用于 source_hash —— 与行号、缩进、换行无关，但语义变化（增删改
语句、改名、改默认值等）必然改变哈希。刻意不使用 Base 的源码打印器：
个别表达式会让 show_unquoted 抛错，而哈希必须对所有可解析输入都稳定。
"""
function canonical_text(ex)
    io = IOBuffer()
    write_canonical!(io, ex)
    return String(take!(io))
end

function write_canonical!(io::IO, x)
    if x isa Expr
        print(io, "(", x.head)
        for a in x.args
            a isa LineNumberNode && continue
            print(io, " ")
            write_canonical!(io, a)
        end
        print(io, ")")
    elseif x isa LineNumberNode
        print(io, "lnn")
    elseif x isa QuoteNode
        print(io, "':")
        write_canonical!(io, x.value)
    elseif x isa Symbol
        print(io, x)
    elseif x isa AbstractString
        print(io, repr(String(x)))
    else
        print(io, repr(x))
    end
    return
end

"""目标定义的规范化 SHA-256（小写十六进制，不带前缀）。"""
canonical_hash(ex) = bytes2hex(sha256(canonical_text(ex)))

"""去掉 `sha256:` 前缀并小写；空/无值返回 \"\" 。"""
function normalize_hash(h)
    h === nothing && return ""
    s = strip(String(h))
    s = lowercase(s)
    startswith(s, "sha256:") && (s = strip(s[8:end]))
    return s
end

"""表达式内第一个 LineNumberNode 的行号；没有则返回 fallback。"""
function first_line(ex, fallback::Int=0)
    ex isa LineNumberNode && return ex.line
    ex isa Expr || return fallback
    for a in ex.args
        a isa LineNumberNode && return a.line
    end
    for a in ex.args
        l = first_line(a, 0)
        l > 0 && return l
    end
    return fallback
end

"""宏名（Symbol / GlobalRef / A.name 形式）→ String；否则 nothing。"""
function macro_name(x)
    x isa Symbol && return String(x)
    x isa GlobalRef && return String(x.name)
    if x isa Expr && x.head === :. && length(x.args) == 2
        k = x.args[2]
        k isa QuoteNode && (k = k.value)
        k isa Symbol && return String(k)
    end
    return nothing
end

const DOC_MACROS = Set{String}(["@doc", "@__doc__"])

is_doc_macro(x) = (n = macro_name(x); n !== nothing && n in DOC_MACROS)

"""QuoteNode / Symbol / 字符串 → 名称字符串；否则 nothing。"""
function name_of_literal(x)
    x isa QuoteNode && (x = x.value)
    x isa Symbol && return String(x)
    x isa AbstractString && return String(x)
    return nothing
end

"""限定名 A.B.c 的基名文本（用于 base.module 形式的限定引用）。"""
function qualifier_text(base)
    if base isa Symbol
        return String(base)
    elseif base isa GlobalRef
        return string(base.mod, ".", base.name)
    elseif base isa Expr
        if base.head === :.
            length(base.args) == 1 && return qualifier_text(base.args[1])
            # 多段限定（A.B.f）必须逐段拼出，否则会退化成 "A."（t27 修复）
            return qualifier_text(base.args[1]) * "." * something(member_text(base.args[end]), "")
        elseif base.head === :curly
            return qualifier_text(base.args[1])
        elseif base.head === :$
            return ""
        end
    end
    return ""
end

"""Expr(:.) 末端成员名（如 Base.show 中的 show）或 Symbol 的文本。"""
member_text(x) = x isa Symbol ? String(x) : (x isa QuoteNode ? name_of_literal(x) : nothing)

"""调用头 / 签名头 → (name, qualifier)；无法识别返回 nothing。"""
function head_name(f)
    f isa Symbol && return (String(f), "")
    if f isa Expr
        if f.head === :. && length(f.args) == 2
            mem = member_text(f.args[2])
            mem === nothing && return nothing
            return (mem, qualifier_text(f.args[1]))
        elseif f.head === :curly
            return head_name(f.args[1])
        elseif f.head === :(::)
            return head_name(f.args[1])
        end
    end
    return nothing
end

"""定义签名 → (name, qualifier)：支持 Symbol、call、where、::、curly、A.b.f。"""
function signature_name(sig)
    sig isa Symbol && return (String(sig), "")
    sig isa Expr || return nothing
    h = sig.head
    if h === :call
        return head_name(sig.args[1])
    elseif h === :where
        return signature_name(sig.args[1])
    elseif h === :(::)
        return signature_name(sig.args[1])
    elseif h === :curly
        return signature_name(sig.args[1])
    elseif h === :.
        return head_name(sig)
    end
    return nothing
end

"""普通绑定左侧 → 绑定名；元组/索引/字段赋值返回 nothing。"""
function binding_name(lhs)
    lhs isa Symbol && return String(lhs)
    lhs isa Expr || return nothing
    if lhs.head === :(::)
        return binding_name(lhs.args[1])
    elseif lhs.head === :curly
        return binding_name(lhs.args[1])
    end
    return nothing
end

"""
    definition_info(ex) -> (name, qualifier, kind) 或 nothing

kind ∈ function | shortdef | macro | struct | mutable-struct | module | baremodule
       | const | binding | abstract | primitive
"""
function definition_info(ex)
    ex isa Expr || return nothing
    h = ex.head
    if h === :function
        r = signature_name(ex.args[1])
        r === nothing && return nothing
        return (r[1], r[2], "function")
    elseif h === :macro
        r = signature_name(ex.args[1])
        r === nothing && return nothing
        return (r[1], r[2], "macro")
    elseif h === :(=)
        length(ex.args) == 2 || return nothing
        lhs = ex.args[1]
        if lhs isa Expr && lhs.head in (:call, :where, :(::), :curly)
            r = signature_name(lhs)
            r === nothing && return nothing
            return (r[1], r[2], "shortdef")
        end
        sym = binding_name(lhs)
        sym === nothing && return nothing
        return (sym, "", "binding")
    elseif h === :const
        inner = length(ex.args) == 1 ? ex.args[1] : nothing
        inner isa Expr && inner.head === :(=) || return nothing
        sym = binding_name(inner.args[1])
        sym === nothing && return nothing
        return (sym, "", "const")
    elseif h === :struct || h === :mutable
        mutable_flag = h === :mutable
        name = nothing
        for a in ex.args
            a isa Bool && (mutable_flag = a)
            if a isa Symbol && name === nothing
                name = a
            elseif a isa Expr && a.head === :<: && a.args[1] isa Symbol && name === nothing
                name = a.args[1]
            end
        end
        name === nothing && return nothing
        return (String(name), "", mutable_flag ? "mutable-struct" : "struct")
    elseif h === :module || h === :baremodule
        length(ex.args) >= 2 || return nothing
        name = ex.args[2]
        name isa Symbol || return nothing
        return (String(name), "", h === :module ? "module" : "baremodule")
    elseif h === :abstract || h === :primitive
        name = ex.args[1]
        name isa Expr && name.head === :<: && (name = name.args[1])
        name isa Symbol || return nothing
        return (String(name), "", h === :abstract ? "abstract" : "primitive")
    end
    return nothing
end

"""
    dotted_path(ex) -> (dots, parts) 或 nothing

解析 `Expr(:.)` 形式的模块路径：`A.B` → (0, ["A","B"])，`.A` → (1,["A"])，
`..A` → (2,["A"])。单元素 `Expr(:., :b)` 是 Julia 指令项里的成员包装。
"""
function dotted_path(ex)
    ex isa Symbol && return (0, String[String(ex)])
    ex isa Expr && ex.head === :. || return nothing
    dots = 0
    parts = String[]
    for a in ex.args
        if a isa Symbol && a === Symbol(".")
            dots += 1
        elseif a isa Symbol
            push!(parts, String(a))
        else
            nm = name_of_literal(a)
            nm === nothing && return nothing
            push!(parts, nm)
        end
    end
    return (dots, parts)
end

"""模块路径文本：`..A.B`。"""
function dotted_text(ex)
    dp = dotted_path(ex)
    dp === nothing && return ""
    dots, parts = dp
    return repeat(".", dots) * join(parts, ".")
end

"""调用目标的可判定纯名：`include`、`Base.include`、`Core.eval`…；否则 nothing。"""
function call_plain_name(f)
    f isa Symbol && return String(f)
    if f isa Expr && f.head === :. && length(f.args) == 2
        mem = member_text(f.args[2])
        mem === nothing && return nothing
        q = qualifier_text(f.args[1])
        return isempty(q) ? mem : q * "." * mem
    end
    return nothing
end

"""表达式里出现的第一个字符串字面量（用于动态点的名称提示）。"""
function literal_hint(ex)
    ex isa AbstractString && return String(ex)
    ex isa QuoteNode && return (s = name_of_literal(ex); s === nothing ? "" : s)
    ex isa Expr || return ""
    for a in ex.args
        h = literal_hint(a)
        isempty(h) || return h
    end
    return ""
end

"""短小单行片段，用于报告里的证据行（打印器失败时退回结构化文本）。"""
function snippet(ex; maxlen::Int=120)
    t = try
        sprint(Base.show_unquoted, strip_linenums(ex), 0, 0)
    catch
        canonical_text(ex)
    end
    t = replace(t, r"\s+" => " ")
    t = strip(t)
    length(t) > maxlen && (t = first(t, maxlen) * "…")
    return t
end

"""字面量/joinpath/normpath/字符串拼接/@__DIR__/@__FILE__ 的静态字符串求值。

只接受纯静态表达式；出现变量（非常量表内）一律返回 nothing → 调用方记为
「动态引用，名称不可判定」。@__DIR__/@__FILE__ 以绝对路径参与求值。
"""
function static_string_value(ex, abs_dir::AbstractString, abs_file::AbstractString,
                             consts::AbstractDict{String,String})
    if ex isa AbstractString
        return String(ex)
    elseif ex isa Symbol
        return get(consts, String(ex), nothing)
    elseif !(ex isa Expr)
        return nothing
    end
    if ex.head === :macrocall
        mn = macro_name(ex.args[1])
        mn == "@__DIR__" && return String(abs_dir)
        mn == "@__FILE__" && return String(abs_file)
        return nothing
    elseif ex.head === :call
        fn = call_plain_name(ex.args[1])
        fn === nothing && return nothing
        if fn in ("joinpath", "Base.joinpath")
            parts = String[]
            for a in ex.args[2:end]
                v = static_string_value(a, abs_dir, abs_file, consts)
                v === nothing && return nothing
                push!(parts, v)
            end
            isempty(parts) && return nothing
            return joinpath(parts...)
        elseif (fn in ("normpath", "Base.normpath") || fn in ("dirname", "Base.dirname") ||
                fn in ("abspath", "Base.abspath") || fn in ("realpath", "Base.realpath"))
            length(ex.args) == 2 || return nothing
            v = static_string_value(ex.args[2], abs_dir, abs_file, consts)
            v === nothing && return nothing
            r = getfield(Base, Symbol(last(split(fn, "."))))(v)
            return String(r)
        elseif fn == "*" || fn == "string"
            io = IOBuffer()
            for a in ex.args[2:end]
                v = static_string_value(a, abs_dir, abs_file, consts)
                v === nothing && return nothing
                print(io, v)
            end
            return String(take!(io))
        end
    end
    return nothing
end

"""解析 include 的目标为仓库相对 POSIX 路径；无法静态求值返回 nothing。"""
function resolve_include_target(root::AbstractString, file_rel::AbstractString, ex,
                                abs_dir::AbstractString, abs_file::AbstractString,
                                consts::AbstractDict{String,String})
    v = static_string_value(ex, abs_dir, abs_file, consts)
    v === nothing && return nothing
    p = isabspath(v) ? String(v) : joinpath(String(abs_dir), String(v))
    rel = try
        relpath(p, String(root))
    catch
        return nothing
    end
    rel = clean_rel(rel)
    (isempty(rel) || startswith(rel, "..")) && return nothing
    return rel
end

"""统一为 POSIX 风格、去掉 `./` 前缀的相对路径。"""
function clean_rel(p::AbstractString)
    s = replace(String(p), "\\" => "/")
    while startswith(s, "./")
        s = s[3:end]
    end
    return normpath(s) |> x -> replace(x, "\\" => "/")
end

"""模块路径 → 稳定字符串键。"""
mkey(path::AbstractVector{<:AbstractString}) = join(String[String(p) for p in path], "/")
mkey(path::AbstractString) = String(path)
