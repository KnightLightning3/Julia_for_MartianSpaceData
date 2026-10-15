using Test

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
const IGRF_SOURCE = joinpath(REPO_ROOT, "models", "IGRF_calculate.jl")
const REGISTRY_SOURCE = joinpath(REPO_ROOT, "src", "modules.jl")
const BASELINE = "a09511aa7b88c874cefe8ca966c98aa267db9365"

function parse_file(path)
    Meta.parseall(read(path, String))
end

function walk_ast(f, x)
    f(x)
    if x isa Expr
        foreach(child -> walk_ast(f, child), x.args)
    end
    nothing
end

function igrf_exports(ast)
    names = Symbol[]
    walk_ast(ast) do node
        if node isa Expr && node.head === :export
            append!(names, filter(x -> x isa Symbol, node.args))
        end
    end
    names
end

function registered_allow(ast)
    allow = nothing
    walk_ast(ast) do node
        if node isa Expr && node.head === :call && !isempty(node.args) && node.args[1] === :_spec &&
           any(arg -> arg isa QuoteNode && arg.value === :IGRF_calculate, node.args)
            for arg in node.args
                if arg isa Expr && arg.head === :parameters
                    for kw in arg.args
                        if kw isa Expr && kw.head === :kw && kw.args[1] === :allow
                            allow = kw.args[2]
                        end
                    end
                end
            end
        end
    end
    allow === nothing && error("Could not find IGRF_calculate _spec allow in modules.jl")
    map(x -> x isa QuoteNode ? x.value : x, allow.args)
end

function function_ast(ast, name::Symbol)
    found = Any[]
    walk_ast(ast) do node
        if node isa Expr && node.head === :function && !isempty(node.args)
            signature = node.args[1]
            if signature isa Expr && signature.head === :call && signature.args[1] === name
                push!(found, node)
            end
        end
    end
    length(found) == 1 || error("Expected exactly one definition for $name, found $(length(found))")
    found[1]
end

function without_line_numbers(x)
    x isa LineNumberNode && return nothing
    x isa Expr || return x
    Expr(x.head, filter(!isnothing, map(without_line_numbers, x.args)))
end

@testset "IGRF namespace and internal coordinate functions" begin
    current_ast = parse_file(IGRF_SOURCE)
    exports = igrf_exports(current_ast)
    allow = registered_allow(parse_file(REGISTRY_SOURCE))

    @test :pc2sphere ∉ exports
    @test :sphere2pc ∉ exports
    @test :pc2sphere ∉ allow
    @test :sphere2pc ∉ allow
    @test :IGRF_pc ∈ exports
    @test :IGRF_pc ∈ allow

    baseline_text = read(`git -C $REPO_ROOT show $BASELINE:Magnetic_Model/IGRF_calculate.jl`, String)
    baseline_ast = Meta.parseall(baseline_text)
    for name in (:pc2sphere, :sphere2pc)
        @test without_line_numbers(function_ast(current_ast, name)) ==
              without_line_numbers(function_ast(baseline_ast, name))
    end
end
