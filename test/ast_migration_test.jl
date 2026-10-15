# =============================================================================
# test/ast_migration_test.jl —— AST 迁移校验器 fixture 自测
#
# 用法（两种等价入口）：
#   julia --project=. validation/check_migrations.jl --selftest
#   julia --project=. test/ast_migration_test.jl
#
# 覆盖验收要求：嵌套同名、短定义、docstring、路径 include、alias、漏迁、
# 旧定义残留、悬空可静态解析引用、动态引用 unknown、解析失败、pending 双份、
# 改名的 source_name。所有 fixture 都建在系统临时目录，刻意无效的 fixture
# 只要求「校验器能报出来」，不要求本项目故意失败；不写仓库内任何文件。
# =============================================================================

using Test

if !isdefined(Main, :ASTMigrate)
    include(joinpath(@__DIR__, "..", "validation", "ast", "ASTMigrate.jl"))
end
using .ASTMigrate

const AM = ASTMigrate

# ---------------------------------------------------------------------------
# fixture 工具
# ---------------------------------------------------------------------------

function with_fixture(f)
    root = mktempdir()
    mdir = joinpath(root, "validation", "migrations")
    mkpath(mdir)
    try
        return f(root, mdir)
    finally
        rm(root; recursive=true, force=true)
    end
end

write_tree(root, files::Dict{String,String}) = begin
    for (rel, content) in files
        p = joinpath(root, rel)
        mkpath(dirname(p))
        write(p, content)
    end
    sort(collect(keys(files)))
end

function run_fixture(root, mdir, files::Dict{String,String}; extra_names=String[])
    write_tree(root, files)                     # 幂等写出（可重复调用，便于替换 fixture）
    return AM.run_checks(root; files=collect(keys(files)), migrations_dir=mdir,
                         extra_names=extra_names)
end

uverdict(rep, name) = (u = AM.unit_result(rep, name); u === nothing ? "MISSING" : u.verdict)
ucodes(rep, name) = (u = AM.unit_result(rep, name); u === nothing ? String[] : [f.code for f in u.findings])
unote(rep, name, code) = (u = AM.unit_result(rep, name);
                          u === nothing ? nothing : (fs = [f for f in u.findings if f.code == code];
                                                     isempty(fs) ? nothing : fs[1]))
scan_of(rep, rel) = rep.index.scans[rel]
defs_named(rep, rel, name; top_level=true) =
    [d for d in scan_of(rep, rel).defs if d.name == name && d.top_level == top_level]

function record_toml(name, from, to; status="finalized", source_name="", target_hash="",
                     source_hash="", source_hash_kind="", source_revision="", action="", extra="")
    parts = String[]
    push!(parts, "[[moves]]")
    push!(parts, "name = \"$name\"")
    isempty(source_name) || push!(parts, "source_name = \"$source_name\"")
    push!(parts, "from = \"$from\"")
    isempty(to) || push!(parts, "to = \"$to\"")
    isempty(status) || push!(parts, "status = \"$status\"")
    isempty(action) || push!(parts, "action = \"$action\"")
    isempty(target_hash) || push!(parts, "target_hash = \"$target_hash\"")
    isempty(source_hash) || push!(parts, "source_hash = \"$source_hash\"")
    isempty(source_hash_kind) || push!(parts, "source_hash_kind = \"$source_hash_kind\"")
    isempty(source_revision) || push!(parts, "source_revision = \"$source_revision\"")
    isempty(extra) || push!(parts, extra)
    return join(parts, "\n") * "\n"
end

"""
finalized move 记录：默认自动填入目标定义的真实 target_hash（t12 在清单层要补的正是该字段）。

- 目标存在 → 用 `--print-hash` 同源的 definition_hash（64 位十六进制），记录层门禁通过，
  单元级判定可见；
- 目标被刻意做缺/做坏（漏迁、仅嵌套同名）→ 用占位 64 位哈希，让记录层门禁不挡住
  单元级 fail（记录层门禁见 Records.normalize_record：finalized move 必须有可核验 target_hash）。
"""
function record_toml_finalized(root, name, from, to; target_hash=nothing, kwargs...)
    h = target_hash === nothing ? AM.definition_hash(root, to, name) : target_hash
    h === nothing && (h = repeat("0", 64))
    return record_toml(name, from, to; status="finalized", target_hash=h, kwargs...)
end

# ---------------------------------------------------------------------------
# 1. AST 形状：嵌套同名 / 短定义 / docstring / module / 路径 include / alias
# ---------------------------------------------------------------------------

function test_ast_shapes()
    files = Dict{String,String}(
        "shapes/a.jl" => """
module ShapeMod
using TOML: parsefile as pf
import Statistics as St
export pub_f
const alias_const = ShapeMod.pub_f

\"\"\"目标函数文档串\"\"\"
function pub_f(x)
    x
end

short_f(x) = x
typed_short(x)::Int = 1

function outer()
    function pub_f(x)
        x
    end
    inner_short(y) = y
    pub_f(1)
end

include(joinpath(@__DIR__, "sub", "inc.jl"))
include("plain_inc.jl")
include(dynamic_path)
end
""",
        "shapes/sub/inc.jl" => "inc_fn(z) = z\n",
        "shapes/plain_inc.jl" => "plain_fn(z) = z\n",
    )
    return with_fixture() do root, mdir
        rep = run_fixture(root, mdir, files)
        sc = scan_of(rep, "shapes/a.jl")

        # module 记录
        mods = defs_named(rep, "shapes/a.jl", "ShapeMod")
        @test length(mods) == 1 && mods[1].kind == "module"

        # 顶层 vs 嵌套同名：pub_f 一处顶层、一处嵌套
        top_pub = defs_named(rep, "shapes/a.jl", "pub_f"; top_level=true)
        nest_pub = defs_named(rep, "shapes/a.jl", "pub_f"; top_level=false)
        @test length(top_pub) == 1
        @test length(nest_pub) == 1
        @test top_pub[1].kind == "function"
        @test top_pub[1].has_docstring
        @test !nest_pub[1].has_docstring
        @test top_pub[1].module_path == ["ShapeMod"]
        @test top_pub[1].line > 0

        # 短定义识别（含带返回值类型标注的短定义）
        @test defs_named(rep, "shapes/a.jl", "short_f")[1].kind == "shortdef"
        @test defs_named(rep, "shapes/a.jl", "typed_short")[1].kind == "shortdef"
        @test defs_named(rep, "shapes/a.jl", "inner_short"; top_level=false)[1].kind == "shortdef"

        # include 字面量路径解析（joinpath(@__DIR__,...) 与同目录相对路径）
        inc = [e.included for e in sc.includes]
        @test "shapes/sub/inc.jl" in inc
        @test "shapes/plain_inc.jl" in inc
        # 路径 include 进入同一模块作用域（用 module_by_name 解析作用域键）
        mk = first(sort(collect(rep.index.module_by_name["ShapeMod"])))
        @test "inc_fn" in rep.index.module_defs[mk]
        @test "plain_fn" in rep.index.module_defs[mk]
        @test !("inner_short" in rep.index.module_defs[mk])

        # 动态 include（无法静态求值）必须显式记为动态点，而不是静默忽略
        dyn = [d for d in sc.dynamic_sites if d.kind == "include-dynamic"]
        @test length(dyn) == 1
        @test dyn[1].unknown_name

        # alias：using-别名 / import-别名 / const-别名
        al = [(a.name, a.target, a.kind) for a in sc.aliases]
        @test ("pf", "parsefile", "using") in al
        @test ("St", "Statistics", "import") in al
        @test ("alias_const", "pub_f", "const") in al

        # using/import/export 指令记录
        kinds = [d.kind for d in sc.directives]
        @test "using" in kinds && "import" in kinds && "export" in kinds
        @test any(d -> d.kind == "using" && ("parsefile" => "pf") in d.names, sc.directives)
        @test any(d -> d.kind == "export" && ("pub_f" => "pub_f") in d.names, sc.directives)

        # 未被迁移记录引用时不报悬空（只有关注名才收集引用）
        @test AM.exit_code(rep) == 0
        return true
    end
end

# ---------------------------------------------------------------------------
# 2. finalized：目标存在 + 旧定义已删 + target_hash（目标定义哈希）一致 → ok
# ---------------------------------------------------------------------------

function test_finalized_ok_with_hash()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "# 旧定义已迁移删除\nfunction keep()\n    1\nend\n",
            "m/new.jl" => "\"\"\"目标定义文档串\"\"\"\nfunction moved(x)\n    x + 1\nend\n",
        )
        write_tree(root, files)
        h = AM.definition_hash(root, "m/new.jl", "moved")
        @test h isa String && occursin(r"^[0-9a-f]{64}$", h)
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved", "m/old.jl", "m/new.jl"; status="finalized", target_hash=h))
        rep = run_fixture(root, mdir, files)
        @test uverdict(rep, "moved") == "ok"
        @test AM.exit_code(rep) == 0
        @test isempty(AM.unfinished_units(rep))
        # 哈希可复现：同一工具重复计算结果一致
        @test AM.definition_hash(root, "m/new.jl", "moved") == h
        return true
    end
end

# ---------------------------------------------------------------------------
# 3. 旧定义残留（finalized 但 from 仍在定义）
# ---------------------------------------------------------------------------

function test_old_definition_residue()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "function moved(x)\n    x\nend\n",
            "m/new.jl" => "function moved(x)\n    x + 1\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl"))
        rep = run_fixture(root, mdir, files)
        @test uverdict(rep, "moved") == "fail"
        @test "OLD_DEFINITION_RESIDUE" in ucodes(rep, "moved")
        @test AM.exit_code(rep) == 1
        return true
    end
end

# ---------------------------------------------------------------------------
# 4. 目标仅在嵌套作用域同名 → 不满足模块级目标定义（嵌套同名不算）
# ---------------------------------------------------------------------------

function test_target_only_nested()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "# 源已删\n",
            "m/new.jl" => "function holder()\n    function moved(x)\n        x\n    end\n    moved(1)\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl"))
        rep = run_fixture(root, mdir, files)
        @test uverdict(rep, "moved") == "fail"
        @test "TARGET_DEFINITION_MISSING" in ucodes(rep, "moved")
        fd = unote(rep, "moved", "TARGET_DEFINITION_MISSING")
        @test fd !== nothing && occursin("嵌套", fd.message)
        @test AM.exit_code(rep) == 1
        return true
    end
end

# ---------------------------------------------------------------------------
# 5. 短定义作为目标定义
# ---------------------------------------------------------------------------

function test_shortdef_target()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "# 源已删\n",
            "m/new.jl" => "moved(x) = x + 1\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl"))
        rep = run_fixture(root, mdir, files)
        @test uverdict(rep, "moved") == "ok"
        @test AM.exit_code(rep) == 0
        return true
    end
end

# ---------------------------------------------------------------------------
# 6. pending 双份：允许暂双份，但绝不冒称完成
# ---------------------------------------------------------------------------

function test_pending_double_definition()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "function moved(x)\n    x\nend\n",
            "m/new.jl" => "function moved(x)\n    x + 1\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml("moved", "m/old.jl", "m/new.jl"; status="pending"))
        rep = run_fixture(root, mdir, files)
        @test uverdict(rep, "moved") == "pending"
        @test uverdict(rep, "moved") != "ok"
        @test "PENDING_DOUBLE_DEFINITION" in ucodes(rep, "moved")
        @test AM.exit_code(rep) == 0                      # 允许（未完成不算失败）
        @test length(AM.unfinished_units(rep)) == 1       # 但必须出现在未完成清单
        return true
    end
end

# ---------------------------------------------------------------------------
# 7. 漏迁：目标定义缺失
# ---------------------------------------------------------------------------

function test_missing_target()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "# 源已删\n",
            "m/new.jl" => "# 目标还没迁进来\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl"))
        rep = run_fixture(root, mdir, files)
        @test uverdict(rep, "moved") == "fail"
        @test "TARGET_DEFINITION_MISSING" in ucodes(rep, "moved")
        @test AM.exit_code(rep) == 1
        return true
    end
end

# ---------------------------------------------------------------------------
# 8. 悬空引用：静态可解析却解析不到 → fail；被 include/import 解析 → 不报
# ---------------------------------------------------------------------------

function test_dangling_reference()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "# 源定义已删，但调用没更新\nfunction user()\n    moved(1)\nend\n",
            "m/new.jl" => "function moved(x)\n    x\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl"))
        rep = run_fixture(root, mdir, files)
        @test uverdict(rep, "moved") == "fail"
        @test "DANGLING_REFERENCE" in ucodes(rep, "moved")
        fd = unote(rep, "moved", "DANGLING_REFERENCE")
        @test fd !== nothing && fd.file == "m/old.jl"
        @test AM.exit_code(rep) == 1
        return true
    end
end

function test_reference_resolved_by_include()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "include(\"new.jl\")\nfunction user()\n    moved(1)\nend\n",
            "m/new.jl" => "function moved(x)\n    x\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl"))
        rep = run_fixture(root, mdir, files)
        @test !("DANGLING_REFERENCE" in ucodes(rep, "moved"))
        @test uverdict(rep, "moved") == "ok"
        return true
    end
end

function test_reference_resolved_by_import_alias()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "include(\"new.jl\")\nimport .NewMod: moved\nfunction user()\n    moved(1)\nend\n",
            "m/new.jl" => "module NewMod\nfunction moved(x)\n    x\nend\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"),
              record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl";
                                    extra="source_name = \"moved\""))
        rep = run_fixture(root, mdir, files)
        @test !("DANGLING_REFERENCE" in ucodes(rep, "moved"))
        # alias 记录确实建立
        al = [(a.name, a.target) for a in scan_of(rep, "m/old.jl").aliases]
        @test ("moved", "moved") in al
        return true
    end
end

# ---------------------------------------------------------------------------
# 9. 动态引用 unknown；isdefined 缺失探测按删除证据处理
# ---------------------------------------------------------------------------

function test_param_shadowing_baseline_expression()
    # t26 复现基线真实表达式（5f225db:common/MarsCommon.jl:145 逐字）：
    #   rotate_vector(data, rotation_matrix) = rotation_matrix * data
    # 形参 rotation_matrix 与别处 finalized 迁入的同名函数不构成 Julia 命名冲突，
    # 修复前会误报 DANGLING_REFERENCE（t13 因该误报把科研代码参数改名）。
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "p/geometry.jl" => "module FunctionCoordinate\n" *
                               "function rotation_matrix(θ, φ)\n" *
                               "    [cos(θ) sin(θ); -sin(θ) cos(θ)]\nend\nend\n",
            "p/calculate_models.jl" => "# rotation_matrix 已迁出\n",
            "p/mars_common.jl" => "module MarsCommonFixture\n" *
                                  "rotate_vector(data, rotation_matrix) = rotation_matrix * data\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"),
              record_toml_finalized(root, "rotation_matrix", "p/calculate_models.jl", "p/geometry.jl"))
        rep = run_fixture(root, mdir, files)
        @test isempty(rep.parse_errors)                       # 夹具本身必须真能解析
        @test !("DANGLING_REFERENCE" in ucodes(rep, "rotation_matrix"))
        @test uverdict(rep, "rotation_matrix") == "ok"
        @test AM.exit_code(rep) == 0
        # 引用点确实被采集，且被判为局部绑定（证明不是“没扫到所以没报”）
        refs = [r for r in scan_of(rep, "p/mars_common.jl").refs if r.name == "rotation_matrix"]
        @test length(refs) == 1
        @test refs[1].shadowed
        return true
    end
end

function test_param_shadowing_matrix()
    # 形参/局部绑定的各种形态遮蔽同名全局函数：普通/typed/默认/kwargs/kwargs-splat/
    # 位置 splat/解构（位置与关键字）/where 类型参数/匿名函数参数/内层函数名/
    # 局部赋值/let/for/推导式/限定引用基座。
    return with_fixture() do root, mdir
        users = """
module ParamUsers
rotate_vector(data, rotation_matrix) = rotation_matrix * data
function plain_param(shadowed_fn)
    return shadowed_fn + 1
end
function typed_param(shadowed_fn::Int)
    return shadowed_fn + 1
end
function default_param(shadowed_fn = 1)
    return shadowed_fn + 1
end
function kwargs_param(; shadowed_fn = 1)
    return shadowed_fn + 1
end
function kw_splat_param(x; shadowed_fn = 1, rest...)
    return shadowed_fn + x
end
function splat_param(shadowed_fn...)
    return sum(shadowed_fn)
end
function destructured_param((shadowed_fn, b))
    return shadowed_fn * b
end
function destructured_kw(; (shadowed_fn, b) = (1, 2))
    return shadowed_fn + b
end
function where_param(::Type{shadowed_fn}) where {shadowed_fn}
    return shadowed_fn
end
function anon_param()
    f = shadowed_fn -> shadowed_fn + 1
    return f(1)
end
function inner_named()
    function shadowed_fn(x)
        x
    end
    return shadowed_fn(1)
end
function inner_shortdef()
    shadowed_fn(y) = y + 1
    return shadowed_fn(1)
end
function local_binding()
    shadowed_fn = 3
    return shadowed_fn + 1
end
function let_binding()
    let shadowed_fn = 2
        return shadowed_fn + 1
    end
end
function for_binding(xs)
    s = 0
    for shadowed_fn in xs
        s += shadowed_fn
    end
    return s
end
function for_multi_binding(xs, ys)
    s = 0
    for shadowed_fn in xs, other in ys
        s += shadowed_fn + other
    end
    return s
end
function comprehension_binding(xs)
    return sum([shadowed_fn^2 for shadowed_fn in xs])
end
function comprehension_multi_binding(xs, ys)
    return sum([shadowed_fn * other for shadowed_fn in xs, other in ys])
end
function qualified_base(M)
    return M.shadowed_fn
end
end
"""
        files = Dict{String,String}(
            "p/geometry.jl" => "module Geo\nfunction shadowed_fn(a)\n    a\nend\nend\n",
            "p/old.jl" => "# shadowed_fn 已迁出\n",
            "p/users.jl" => users,
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"),
              record_toml_finalized(root, "shadowed_fn", "p/old.jl", "p/geometry.jl"))
        rep = run_fixture(root, mdir, files)
        @test isempty(rep.parse_errors)                       # 夹具语法必须有效
        @test !("DANGLING_REFERENCE" in ucodes(rep, "shadowed_fn"))
        @test uverdict(rep, "shadowed_fn") == "ok"
        refs = [r for r in scan_of(rep, "p/users.jl").refs if r.name == "shadowed_fn"]
        @test length(refs) >= 15                              # 各形态都产生了引用点
        @test all(r -> r.shadowed, refs)                      # 且全部判为局部绑定
        # 限定引用基座是形参（M.shadowed_fn）同样不算全局引用
        @test !("NON_MODULE_BASE" in ucodes(rep, "shadowed_fn"))

        # 负向对照：真悬空（无任何局部绑定）必须仍然检出
        files2 = copy(files)
        files2["p/real_dangling.jl"] =
            "module RealDangling\nfunction use_it()\n    return shadowed_fn(1)\nend\nend\n"
        rep2 = run_fixture(root, mdir, files2)
        @test uverdict(rep2, "shadowed_fn") == "fail"
        @test "DANGLING_REFERENCE" in ucodes(rep2, "shadowed_fn")
        fd = unote(rep2, "shadowed_fn", "DANGLING_REFERENCE")
        @test fd !== nothing && fd.file == "p/real_dangling.jl"
        refs2 = [r for r in scan_of(rep2, "p/real_dangling.jl").refs if r.name == "shadowed_fn"]
        @test length(refs2) == 1 && !refs2[1].shadowed        # 真全局引用未被误判为局部
        @test AM.exit_code(rep2) == 1
        return true
    end
end

# ---------------------------------------------------------------------------
# t27：合法源文件删除（source_revision 旧对象取证）与 字符串/插值 引用语义
# ---------------------------------------------------------------------------

"""把夹具目录做成临时 git 仓库并提交一个旧源文件，返回 revision（随后从工作区删除该文件）。

只在系统临时目录里 git init/commit（不动项目仓库、不做联网）。
"""
function make_old_source_repo(root, rel, content)
    p = joinpath(root, rel)
    mkpath(dirname(p))
    write(p, content)
    run(pipeline(`git init -q $root`; stdout=devnull, stderr=devnull))
    run(pipeline(`git -C $root -c user.name=t -c user.email=t@t add $rel`; stdout=devnull))
    run(pipeline(`git -C $root -c user.name=t -c user.email=t@t commit -qm seed`; stdout=devnull))
    rev = strip(read(`git -C $root rev-parse HEAD`, String))
    rm(p)
    return rev
end

function test_deleted_source_authorization()
    return with_fixture() do root, mdir
        rev = make_old_source_repo(root, "src/old.jl",
                                   "module Old\nfunction moved_fn(x)\n    x + 1\nend\nend\n")
        files = Dict{String,String}(
            "src/new.jl" => "module New\nfunction moved_fn(x)\n    x + 1\nend\nend\n",
        )
        write_tree(root, files)
        h = AM.definition_hash(root, "src/new.jl", "moved_fn")

        # A) 已授权：source_revision 的旧对象确有该定义的顶层定义 → 允许源定义移除（不再要求空壳）
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved_fn", "src/old.jl", "src/new.jl";
                          target_hash=h, source_hash="ABC123",
                          source_hash_kind="sha256-source-block-first16",
                          source_revision=rev))
        repA = run_fixture(root, mdir, files)
        @test uverdict(repA, "moved_fn") == "ok"
        @test "SOURCE_FILE_DELETED_VERIFIED" in ucodes(repA, "moved_fn")
        @test !("FROM_FILE_MISSING" in ucodes(repA, "moved_fn"))
        @test AM.exit_code(repA) == 0

        # B) 未授权：缺 source_revision → 依旧 fail（真正缺源未授权）
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved_fn", "src/old.jl", "src/new.jl"; target_hash=h))
        repB = run_fixture(root, mdir, files)
        @test uverdict(repB, "moved_fn") == "fail"
        @test "SOURCE_FILE_DELETED_UNAUTHORIZED" in ucodes(repB, "moved_fn")
        @test AM.exit_code(repB) == 1

        # C) 不可核对：source_revision 指向不存在的对象 → unknown（不得伪 pass）
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved_fn", "src/old.jl", "src/new.jl";
                          target_hash=h, source_revision="deadbeefdeadbeef"))
        repC = run_fixture(root, mdir, files)
        @test uverdict(repC, "moved_fn") == "unknown"
        @test "SOURCE_FILE_DELETED_UNVERIFIABLE" in ucodes(repC, "moved_fn")
        @test AM.exit_code(repC) == 0

        # D) 旧对象里没有该名字（source_name 指向不存在的名）→ unknown
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved_fn", "src/old.jl", "src/new.jl";
                          target_hash=h, source_revision=rev, source_name="other_name"))
        repD = run_fixture(root, mdir, files)
        @test uverdict(repD, "moved_fn") == "unknown"
        @test "SOURCE_FILE_DELETED_UNVERIFIABLE" in ucodes(repD, "moved_fn")

        # E) 错 target_hash（即便源已授权）→ 依旧 fail
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved_fn", "src/old.jl", "src/new.jl";
                          target_hash=repeat("0", 64), source_revision=rev))
        repE = run_fixture(root, mdir, files)
        @test uverdict(repE, "moved_fn") == "fail"
        @test "HASH_MISMATCH" in ucodes(repE, "moved_fn")
        @test AM.exit_code(repE) == 1
        return true
    end
end

function test_string_literal_vs_interpolation_reference()
    literal_only = "module LiteralOnly\n" *
                   "function plain_literal_use()\n" *
                   "    txt = \"MarsData.MarsCommon.get_angle(v)\"\n" *
                   "    return occursin(\"get_angle(\", txt) || occursin(Regex(\"get_angle\\\\()\"), txt)\n" *
                   "end\nend\n"
    interp_local = "module InterpLocal\n" *
                   "function interp_local(get_angle)\n" *
                   "    return \"value=\$(get_angle)\"\n" *
                   "end\nend\n"
    interp_global = "module InterpGlobal\n" *
                    "function interp_global()\n" *
                    "    return \"value=\$(get_angle)\"\n" *
                    "end\nend\n"
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "s/target.jl" => "module Geometry\nfunction get_angle(v1, v2)\n    90.0\nend\nend\n",
            "s/literal_only.jl" => literal_only,
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"),
              record_toml_finalized(root, "get_angle", "s/target.jl", "s/target.jl"))
        rep1 = run_fixture(root, mdir, files)
        @test isempty(rep1.parse_errors)
        # 普通字符串 literal 不作符号：该文件不产生任何对 get_angle 的引用
        @test isempty([r for r in scan_of(rep1, "s/literal_only.jl").refs if r.name == "get_angle"])
        @test !("DANGLING_REFERENCE" in ucodes(rep1, "get_angle"))
        @test uverdict(rep1, "get_angle") == "ok"

        # 字符串插值是真实 expression：形参遮蔽 → 按局部规则，不算全局引用
        files2 = copy(files)
        files2["s/interp_local.jl"] = interp_local
        rep2 = run_fixture(root, mdir, files2)
        refs2 = [r for r in scan_of(rep2, "s/interp_local.jl").refs if r.name == "get_angle"]
        @test length(refs2) == 1 && refs2[1].shadowed
        @test !("DANGLING_REFERENCE" in ucodes(rep2, "get_angle"))
        @test uverdict(rep2, "get_angle") == "ok"

        # 插值且无局部绑定 → 真全局引用未被放过（负向对照）
        files3 = copy(files2)
        files3["s/interp_global.jl"] = interp_global
        rep3 = run_fixture(root, mdir, files3)
        refs3 = [r for r in scan_of(rep3, "s/interp_global.jl").refs if r.name == "get_angle"]
        @test length(refs3) == 1 && !refs3[1].shadowed
        @test "DANGLING_REFERENCE" in ucodes(rep3, "get_angle")
        @test uverdict(rep3, "get_angle") == "fail"
        fd = unote(rep3, "get_angle", "DANGLING_REFERENCE")
        @test fd !== nothing && fd.file == "s/interp_global.jl"
        return true
    end
end

function test_multi_segment_qualified_base()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "q/marsdata.jl" => "module MarsData\ninclude(joinpath(@__DIR__, \"marscommon.jl\"))\nend\n",
            "q/marscommon.jl" => "module MarsCommon\nfunction get_angle(v1, v2)\n    90.0\nend\nend\n",
            # 多段限定基座（t27：MarsData.MarsCommon.get_angle）
            "q/user.jl" => "module User\nfunction use_it(a, b)\n    return MarsData.MarsCommon.get_angle(a, b)\nend\nend\n",
            "q/old.jl" => "# get_angle 已迁出\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"),
              record_toml_finalized(root, "get_angle", "q/old.jl", "q/marscommon.jl"))
        rep = run_fixture(root, mdir, files)
        @test isempty(rep.parse_errors)
        refs = [r for r in scan_of(rep, "q/user.jl").refs if r.name == "get_angle"]
        @test length(refs) == 1
        @test refs[1].base == "MarsData.MarsCommon"     # 修复前会退化成 "MarsData."
        @test !("DANGLING_REFERENCE" in ucodes(rep, "get_angle"))
        @test uverdict(rep, "get_angle") == "ok"

        # 负向对照：多段基座可判定但成员确实不存在 → 仍判悬空
        files2 = copy(files)
        files2["q/user_missing.jl"] =
            "module UserMissing\nfunction use_it(a, b)\n    return MarsData.MarsCommon.missing_fn(a, b)\nend\nend\n"
        write(joinpath(mdir, "moves.toml"),
              record_toml("missing_fn", "q/old.jl", "q/marscommon.jl";
                          target_hash=repeat("0", 64)))
        rep2 = run_fixture(root, mdir, files2)
        @test "DANGLING_REFERENCE" in ucodes(rep2, "missing_fn")
        @test uverdict(rep2, "missing_fn") == "fail"
        return true
    end
end

function test_dynamic_reference_unknown()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "# 源已删；调用通过动态方式，无法静态判定\n" *
                          "function user(mod)\n    Core.eval(mod, :(moved(1)))\nend\n",
            "m/new.jl" => "function moved(x)\n    x\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl"))
        rep = run_fixture(root, mdir, files)
        @test uverdict(rep, "moved") == "unknown"
        @test "DYNAMIC_REFERENCE_UNKNOWN" in ucodes(rep, "moved")
        @test AM.exit_code(rep) == 0                 # unknown 显式报告，不冒称安全也不阻塞
        @test length(AM.unfinished_units(rep)) == 1
        return true
    end
end

function test_isdefined_is_deletion_evidence()
    return with_fixture() do root, mdir
        # 负断言（@test !isdefined(M, :moved)）是删除证据，不是旧调用
        files = Dict{String,String}(
            "m/old.jl" => "# 源已删\n",
            "m/new.jl" => "function moved(x)\n    x\nend\n",
            "m/test_neg.jl" => "using Test\nmodule M\nend\n@test !isdefined(M, :moved)\n" *
                               "@test !isdefined(M, :moved)\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl"))
        rep = run_fixture(root, mdir, files)
        @test uverdict(rep, "moved") == "ok"
        @test !("DYNAMIC_REFERENCE_UNKNOWN" in ucodes(rep, "moved"))
        @test AM.exit_code(rep) == 0
        return true
    end
end

function test_dynamic_symbol_hint_marks_unit_unknown()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "function user(mod, key)\n    getfield(mod, :moved)\n    Symbol(key)\nend\n",
            "m/new.jl" => "function moved(x)\n    x\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl"))
        rep = run_fixture(root, mdir, files)
        @test uverdict(rep, "moved") == "unknown"
        @test "DYNAMIC_REFERENCE_UNKNOWN" in ucodes(rep, "moved")
        return true
    end
end

# ---------------------------------------------------------------------------
# 10. 解析失败 → 非零退出（退出码 2）
# ---------------------------------------------------------------------------

function test_parse_failure()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "# 源已删\n",
            "m/new.jl" => "function moved(x)\n    x\nend\n",
            "m/broken.jl" => "x = 1\nfunction broken(\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml_finalized(root, "moved", "m/old.jl", "m/new.jl"))
        rep = run_fixture(root, mdir, files)
        @test AM.has_parse_errors(rep)
        @test any(p -> p.file == "m/broken.jl", rep.parse_errors)
        pe = first(rep.parse_errors)
        @test pe.line == 2                       # 行号按文件行号报告（块内相对行号已换算）
        @test AM.exit_code(rep) == 2
        return true
    end
end

# ---------------------------------------------------------------------------
# 11. 记录兼容：未知字段只告警；未知 status 按未完成；缺 name 才是记录错误
# ---------------------------------------------------------------------------

function test_record_compat_unknown_fields_and_status()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "function moved(x)\n    x\nend\n",
            "m/new.jl" => "function moved(x)\n    x + 1\nend\n",
        )
        write_tree(root, files)
        toml = """
        [[moves]]
        name = "moved"
        from = "m/old.jl"
        to = "m/new.jl"
        status = "migrating"
        stauts = "finalized"
        owner = "ustc"
        task = "t9"
        """
        write(joinpath(mdir, "moves.toml"), toml)
        rep = run_fixture(root, mdir, files)
        @test isempty(rep.record_errors)
        @test any(w -> w.code == "REC_UNKNOWN_STATUS", rep.record_warnings)
        @test any(w -> w.code == "REC_UNKNOWN_KEY", rep.record_warnings)   # stauts 拼写错误只告警
        @test uverdict(rep, "moved") == "pending"                          # 绝不冒称完成
        @test "UNFINISHED_UNKNOWN_STATUS" in ucodes(rep, "moved")
        @test AM.exit_code(rep) == 0
        return true
    end
end

function test_record_missing_from_is_unresolved()
    return with_fixture() do root, mdir
        # 非严格兼容：缺 from 不当作记录错误（按未完成处理），且绝不判完成。
        # 这里给足 target_hash，把判定焦点保持在「缺 from」这条路径上。
        files = Dict{String,String}("m/new.jl" => "function moved(x)\n    x\nend\n")
        write_tree(root, files)
        h = AM.definition_hash(root, "m/new.jl", "moved")
        write(joinpath(mdir, "moves.toml"),
              "[[moves]]\nname = \"moved\"\nstatus = \"finalized\"\nto = \"m/new.jl\"\ntarget_hash = \"$h\"\n")
        rep = run_fixture(root, mdir, files)
        @test isempty(rep.record_errors)
        @test any(w -> w.code == "REC_NO_FROM", rep.record_warnings)
        @test uverdict(rep, "moved") == "pending"
        @test "UNFINISHED_NO_FROM" in ucodes(rep, "moved")
        @test AM.exit_code(rep) == 0
        return true
    end
end

function test_record_missing_name_is_error()
    return with_fixture() do root, mdir
        files = Dict{String,String}("m/old.jl" => "# 空\n")
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), "[[moves]]\nfrom = \"m/old.jl\"\nstatus = \"finalized\"\n")
        rep = run_fixture(root, mdir, files)
        @test !isempty(rep.record_errors)
        @test any(e -> e.code == "REC_MISSING_NAME", rep.record_errors)
        @test AM.exit_code(rep) == 3
        return true
    end
end

# ---------------------------------------------------------------------------
# 12. 纯删除单元：action 由 to 缺省推断；残留则 fail
# ---------------------------------------------------------------------------

function test_remove_unit()
    return with_fixture() do root, mdir
        files = Dict{String,String}("m/old.jl" => "# 删除完成\nfunction keep()\n    1\nend\n")
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"), record_toml("gone_fn", "m/old.jl", ""))
        rep = run_fixture(root, mdir, files)
        u = AM.unit_result(rep, "gone_fn")
        @test u !== nothing && u.action == "remove"        # to 缺省 → 推断为删除
        @test uverdict(rep, "gone_fn") == "ok"
        @test AM.exit_code(rep) == 0

        # 残留变体
        files2 = Dict{String,String}("m/old.jl" => "function gone_fn(x)\n    x\nend\n")
        write_tree(root, files2)
        rep2 = run_fixture(root, mdir, files2)
        @test uverdict(rep2, "gone_fn") == "fail"
        @test "OLD_DEFINITION_RESIDUE" in ucodes(rep2, "gone_fn")
        return true
    end
end

# ---------------------------------------------------------------------------
# 13. 改名迁移：source_name 控制「旧定义是否已删」与旧名悬空检测
# ---------------------------------------------------------------------------

function test_rename_with_source_name()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "r/old.jl" => "# 旧名定义已删\n",
            "r/new.jl" => "function new_name(x)\n    x\nend\n",
            "r/user_ok.jl" => "include(\"new.jl\")\nfunction use_it()\n    new_name(1)\nend\n",
            "r/user_bad.jl" => "function use_old()\n    old_name(1)\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"),
              record_toml_finalized(root, "new_name", "r/old.jl", "r/new.jl";
                                    source_name="old_name"))
        rep = run_fixture(root, mdir, files)
        u = AM.unit_result(rep, "new_name")
        @test u !== nothing && u.source_name == "old_name"
        @test !("OLD_DEFINITION_RESIDUE" in ucodes(rep, "new_name"))   # 旧名已删 → 不报残留
        @test "DANGLING_REFERENCE" in ucodes(rep, "new_name")       # 旧名调用没更新
        fd = unote(rep, "new_name", "DANGLING_REFERENCE")
        @test fd !== nothing && fd.file == "r/user_bad.jl" && fd.unit == "old_name"
        @test uverdict(rep, "new_name") == "fail"
        return true
    end
end

function test_rename_old_name_still_present_fails()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "r/old.jl" => "function old_name(x)\n    x\nend\n",
            "r/new.jl" => "function new_name(x)\n    x\nend\n",
        )
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"),
              record_toml_finalized(root, "new_name", "r/old.jl", "r/new.jl"; source_name="old_name"))
        rep = run_fixture(root, mdir, files)
        @test "OLD_DEFINITION_RESIDUE" in ucodes(rep, "new_name")
        @test uverdict(rep, "new_name") == "fail"
        return true
    end
end

# ---------------------------------------------------------------------------
# 14. 哈希：错误哈希 fail；非 64 位哈希只告警不核验
# ---------------------------------------------------------------------------

function test_hash_mismatch_and_unverifiable()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "# 源已删\n",
            "m/new.jl" => "function moved(x)\n    x\nend\n",
        )
        write_tree(root, files)
        # 目标哈希 64 位十六进制但不符 → fail（哈希比对针对目标定义）
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved", "m/old.jl", "m/new.jl";
                          target_hash=repeat("0", 64)))
        rep = run_fixture(root, mdir, files)
        @test "HASH_MISMATCH" in ucodes(rep, "moved")
        @test uverdict(rep, "moved") == "fail"
        @test AM.exit_code(rep) == 1

        # 目标哈希不是 64 位十六进制 → 无法核验：单元判 fail（不得判 ok），记录层同时阻塞 exit 3
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved", "m/old.jl", "m/new.jl"; target_hash="372b280da64669f1"))
        rep2 = run_fixture(root, mdir, files)
        @test "TARGET_HASH_UNVERIFIABLE" in ucodes(rep2, "moved")
        @test uverdict(rep2, "moved") == "fail"
        @test any(e -> e.code == "REC_FINALIZED_WITHOUT_VERIFIABLE_TARGET_HASH", rep2.record_errors)
        @test AM.exit_code(rep2) == 3
        return true
    end
end

"""
t8 HASH_SOURCE_TARGET_CONFLATION 回归：source_hash 只作旧源溯源，绝不充当目标哈希。
覆盖 shadow 场景（两者并存 → 必须读 target_hash）、只有 source_hash → 不得判 ok、
原值保留与口径标注字段。
"""
function test_hash_source_target_separation()
    return with_fixture() do root, mdir
        files = Dict{String,String}(
            "m/old.jl" => "# 源已删\n",
            "m/new.jl" => "function moved(x)\n    x\nend\n",
        )
        write_tree(root, files)
        h_target = AM.definition_hash(root, "m/new.jl", "moved")
        @test h_target isa String && occursin(r"^[0-9a-f]{64}$", h_target)
        old_source_hash = "372b280da64669f1"          # 迁移成员口径：旧源块 SHA-256 前 16

        # A) shadow：source_hash + target_hash 并存 → 目标核验必须读 target_hash（t8 决定性证据）
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved", "m/old.jl", "m/new.jl";
                          target_hash=h_target, source_hash=old_source_hash))
        repA = run_fixture(root, mdir, files)
        uA = AM.unit_result(repA, "moved")
        @test uA !== nothing
        @test uA.hash_expected == h_target        # 不是 source_hash
        @test uA.hash_expected != old_source_hash
        @test uverdict(repA, "moved") == "ok"
        @test AM.exit_code(repA) == 0
        @test isempty(repA.record_errors)

        # B) 只有 source_hash（即便像 64 位十六进制）→ 不得充当目标哈希，且不得判 ok
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved", "m/old.jl", "m/new.jl";
                          source_hash=repeat("a", 64)))
        repB = run_fixture(root, mdir, files)
        uB = AM.unit_result(repB, "moved")
        @test uB !== nothing && isempty(uB.hash_expected)       # source_hash 未被当目标哈希
        @test !("HASH_MISMATCH" in ucodes(repB, "moved"))
        @test "TARGET_HASH_MISSING" in ucodes(repB, "moved")    # 单元判决：fail（不是 [OK]，也不只是 warn）
        @test uverdict(repB, "moved") == "fail"
        @test any(e -> e.code == "REC_FINALIZED_WITHOUT_VERIFIABLE_TARGET_HASH", repB.record_errors)
        @test AM.exit_code(repB) == 3                            # 记录层阻塞，与单元 fail 一致不矛盾
        rB = repB.record_set.records[1]
        @test rB.source_hash == repeat("a", 64) && rB.source_hash_field == "source_hash"
        @test rB.hash_field == "" && !rB.target_hash_verifiable

        # C) source_hash 原值保留（含大小写/前缀不动）+ 可选口径标注
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved", "m/old.jl", "m/new.jl"; status="pending",
                          source_hash="372B280DA64669F1",
                          source_hash_kind="sha256-source-block",
                          source_revision="5f225db"))
        repC = run_fixture(root, mdir, files)
        rC = repC.record_set.records[1]
        @test rC.source_hash == "372B280DA64669F1"               # 原值保留，不归一化
        @test rC.source_hash_kind == "sha256-source-block"
        @test rC.source_revision == "5f225db"
        @test uverdict(repC, "moved") == "pending"
        @test AM.exit_code(repC) == 0                            # pending 不阻塞，但绝不判 ok

        # D) 裸 legacy hash 字段：兼容但告警（推荐显式 target_hash）
        write(joinpath(mdir, "moves.toml"),
              record_toml("moved", "m/old.jl", "m/new.jl"; extra="hash = \"$h_target\""))
        repD = run_fixture(root, mdir, files)
        @test uverdict(repD, "moved") == "ok"
        @test any(w -> w.code == "REC_LEGACY_HASH_FIELD", repD.record_warnings)
        return true
    end
end

"""纯删除单元没有目标定义，不应被 target_hash 门禁误伤。"""
function test_remove_unit_needs_no_target_hash()
    return with_fixture() do root, mdir
        files = Dict{String,String}("m/old.jl" => "# 删除完成\nfunction keep()\n    1\nend\n")
        write_tree(root, files)
        write(joinpath(mdir, "moves.toml"),
              record_toml("gone_fn", "m/old.jl", ""; source_hash="372b280da64669f1"))
        rep = run_fixture(root, mdir, files)
        @test isempty(rep.record_errors)
        @test uverdict(rep, "gone_fn") == "ok"
        @test AM.exit_code(rep) == 0
        return true
    end
end

# ---------------------------------------------------------------------------
# 自测入口
# ---------------------------------------------------------------------------

function run_ast_migration_selftest(; verbose::Bool=true)
    try
        @testset "AST 迁移校验器自测" begin
            @testset "AST 形状（嵌套同名/短定义/docstring/module/路径include/alias）" begin
                @test test_ast_shapes()
            end
            @testset "finalized + target_hash 一致" begin
                @test test_finalized_ok_with_hash()
            end
            @testset "旧定义残留" begin
                @test test_old_definition_residue()
            end
            @testset "目标仅嵌套同名" begin
                @test test_target_only_nested()
            end
            @testset "短定义目标" begin
                @test test_shortdef_target()
            end
            @testset "pending 双份不算完成" begin
                @test test_pending_double_definition()
            end
            @testset "漏迁（目标缺失）" begin
                @test test_missing_target()
            end
            @testset "悬空引用与 include/import 解析" begin
                @test test_dangling_reference()
                @test test_reference_resolved_by_include()
                @test test_reference_resolved_by_import_alias()
            end
            @testset "形参局部绑定不误报悬空（t26）" begin
                @test test_param_shadowing_baseline_expression()
                @test test_param_shadowing_matrix()
            end
            @testset "合法源文件删除与字符串/插值语义（t27）" begin
                @test test_deleted_source_authorization()
                @test test_string_literal_vs_interpolation_reference()
                @test test_multi_segment_qualified_base()
            end
            @testset "动态引用 unknown 与 isdefined 删除证据" begin
                @test test_dynamic_reference_unknown()
                @test test_dynamic_symbol_hint_marks_unit_unknown()
                @test test_isdefined_is_deletion_evidence()
            end
            @testset "解析失败非零退出" begin
                @test test_parse_failure()
            end
            @testset "记录兼容与记录错误" begin
                @test test_record_compat_unknown_fields_and_status()
                @test test_record_missing_from_is_unresolved()
                @test test_record_missing_name_is_error()
            end
            @testset "纯删除单元" begin
                @test test_remove_unit()
            end
            @testset "改名 source_name" begin
                @test test_rename_with_source_name()
                @test test_rename_old_name_still_present_fails()
            end
            @testset "哈希语义分离与比对" begin
                @test test_hash_mismatch_and_unverifiable()
                @test test_hash_source_target_separation()
                @test test_remove_unit_needs_no_target_hash()
            end
        end
        return 0
    catch e
        e isa Test.TestSetException || rethrow()
        fails = try
            e.fail + e.error
        catch
            1
        end
        println(stderr, "自测失败：", fails, " 项")
        return max(1, fails)
    end
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    exit(run_ast_migration_selftest())
end
