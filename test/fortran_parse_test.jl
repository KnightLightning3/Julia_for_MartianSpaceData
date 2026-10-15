# ============================================================================
# test/fortran_parse_test.jl
#
# `call_fortran_dll.jl` 字符串插值修复的解析回归（t18）。
#
# 背景：`@warn "… $p3；…"` 中 `$p3` 后面紧跟全角分号 `；`（U+FF1B，不是合法标识符字符），
# Julia 会报 "interpolated variable ends with invalid character; use `$(...)` instead." 而**整块解析失败**；
# 修复为 `$(p3)` 后语法歧义消失，告警文本与所有路径逻辑保持不变。
#
# 口径：
#   · 只用 `Meta.parse` 做解析级验证，**不加载任何 DLL**（不调用 `_*_dll_path` / `cold_plasma_linear_growth` / 任何 ccall）；
#   · 旧（非法）文本由 `git show 5f225db:call_fortran_dll.jl` 取得，用于独立例证“原非法输入被检出”；
#   · 失败即非零退出。
# 运行：julia --project=. test/fortran_parse_test.jl
# ============================================================================

using Test

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
const TARGET = joinpath(REPO_ROOT, "call_fortran_dll.jl")
const BASE_REV = "5f225db"   # 修复前修订（该文件在本批之前未被改动，故等于修复前工作区文本）

module FortranLoadSandbox end
module FortranMsgSandbox end

# ---------------------------------------------------------------------------
# 解析工具（逐块 Meta.parse；非法块会抛 Base.Meta.ParseError）
# ---------------------------------------------------------------------------
"""
    parse_top_blocks(src) -> Vector{Any}

把整份源码按**顶层块**逐个交给 `Meta.parse`：任一顶层块非法即抛 `Base.Meta.ParseError`。
注意 `Meta.parseall` 对同一错误**不抛异常**，而是内嵌 `Expr(:error, …)` 节点，
故不能用它单独作为合法性判据（见 `has_error_node`）。
"""
function parse_top_blocks(src::AbstractString)
    blocks = Any[]
    pos = firstindex(src)
    n = lastindex(src)
    while pos <= n
        ex, newpos = Meta.parse(src, pos)
        ex === nothing && break
        newpos > pos || error("Meta.parse 未推进解析位置（pos = $pos）")
        pos = newpos
        push!(blocks, ex)
    end
    return blocks
end

has_error_node(e) = e isa Expr ? ((e.head === :error || e.head === :incomplete) || any(has_error_node, e.args)) : false

"""
    module_statements(src) -> Vector{Any}

取文件中的 `module` 顶层块，对其体内每条语句再用 `Meta.parse(string(stmt))` 复解析（逐语句验证）。
"""
function module_statements(src::AbstractString)
    blocks = parse_top_blocks(src)
    mi = findlast(b -> b isa Expr && b.head === :module, blocks)
    mi === nothing && error("未找到 module 顶层块")
    body = blocks[mi].args[end]
    raw = (body isa Expr && body.head === :block) ? body.args : [body]
    out = Any[]
    for s in raw
        s isa LineNumberNode && continue
        push!(out, Meta.parse(string(s)))
    end
    return out
end

const SRC = read(TARGET, String)
const BASELINE = String(read(`git -C $(REPO_ROOT) show $(BASE_REV):call_fortran_dll.jl`))
# 工作区文件为 CRLF，而 git 对象按 core.autocrlf 归一为 LF；行级比对前统一到 LF。
const SRC_LF = replace(SRC, "\r\n" => "\n")
const BASE_LF = replace(BASELINE, "\r\n" => "\n")

@testset "call_fortran_dll.jl 解析回归（t18）" begin
    @testset "修复后：整文件逐块可解析" begin
        blocks = parse_top_blocks(SRC)
        @test length(blocks) >= 2
        @test any(b -> b isa Expr && b.head === :module, blocks)
        @test !has_error_node(Meta.parseall(SRC))          # 补充判据：无内嵌 :error/:incomplete 节点
        stmts = module_statements(SRC)                      # 逐语句复解析
        @test length(stmts) >= 6
        @test all(s -> s isa Expr || s isa Symbol || s isa LineNumberNode, stmts)
    end

    @testset "独立例证：原非法片段被检出、新合法片段通过" begin
        # 最小片段层面
        @test Base.is_id_char('；') == false                # 全角分号不是标识符字符（歧义根因）
        @test_throws Base.Meta.ParseError Meta.parse("\"\$p3；x\"")
        good = Meta.parse("\"\$(p3)；x\"")
        @test good isa Expr && good.head === :string
        # 文件层面：修复前的 5f225db 文本逐块解析必须失败
        @test_throws Base.Meta.ParseError parse_top_blocks(BASELINE)
        # 修复后的工作区文本（上面 testset 已断言可解析）
        @test length(parse_top_blocks(SRC)) >= 2
    end

    @testset "变更面：恰一行，且仅为 \$(p3) 插值修正" begin
        base_lines = split(BASE_LF, '\n')
        new_lines = split(SRC_LF, '\n')
        @test length(base_lines) == length(new_lines)
        diffs = findall(i -> base_lines[i] != new_lines[i], eachindex(base_lines))
        @test length(diffs) == 1
        i = only(diffs)
        @test occursin("\$p3；", base_lines[i])
        @test occursin("\$(p3)；", new_lines[i])
        # 把新行按“逆向替换”还原即得旧行 ⇒ 除该处插值外一字未改
        @test replace(new_lines[i], "\$(p3)；" => "\$p3；") == base_lines[i]
        @test occursin("@warn", new_lines[i])
        @test occursin("使用旧硬编码 DLL 路径 ", new_lines[i])
    end

    @testset "告警消息内容与渲染结果不变" begin
        base_lines = split(BASE_LF, '\n')
        new_lines = split(SRC_LF, '\n')
        i = only(findall(k -> base_lines[k] != new_lines[k], eachindex(base_lines)))
        line = String(new_lines[i])
        m = match(r"\"(.*)\"", strip(line))
        @test m !== nothing
        lit = m.captures[1]
        expr = Meta.parse("\"" * lit * "\"")                # 用文件自身的字符串字面量还原表达式
        @test expr isa Expr && expr.head === :string
        p3 = "X:/legacy/linear_growth_rate.dll"
        got = Core.eval(FortranMsgSandbox, :(let p3 = $p3; $expr; end))
        @test got == "使用旧硬编码 DLL 路径 " * p3 *
                     "；建议在 config/settings.toml 配置 paths.fortran_dll_dir 或将 DLL 放到仓库根目录。"
        # 中文分号仍是紧随插值后的第一个字符（消息分句未变）
        @test occursin("路径 " * p3 * "；建议在", got)
    end

    @testset "装载冒烟：不触发任何 DLL 调用" begin
        Base.include_string(FortranLoadSandbox, SRC, TARGET)
        @test isdefined(FortranLoadSandbox, :Call_fortran_dll)
        CD = FortranLoadSandbox.Call_fortran_dll
        @test isdefined(CD, :_linear_growth_rate_dll_path)
        @test isdefined(CD, :_bspline_dll_path)
        @test isdefined(CD, :cold_plasma_linear_growth)
        @test isdefined(CD, :Bspline_db1ink)
        @test isdefined(CD, :Bspline_db1var)
        @test CD.LEGACY_FORTRAN_DLL_DIR == "D:/CODE/Package_for_Julia/"
        # 仅解析/装载，未调用 _*_dll_path 或任何 ccall ⇒ 缺失的 DLL 不会被加载
    end
end
