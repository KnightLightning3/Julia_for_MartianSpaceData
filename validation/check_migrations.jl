#!/usr/bin/env julia
# =============================================================================
# check_migrations.jl —— 迁移清单 AST 校验器入口（仅标准库）
#
# 用法：
#   julia --project=. validation/check_migrations.jl --selftest
#       运行 fixture 自测（嵌套同名 / 短定义 / docstring / 路径 include / alias /
#       漏迁 / 旧定义残留 / 悬空引用 / 动态 unknown / 解析失败 / pending 双份）
#
#   julia --project=. validation/check_migrations.jl
#       全仓校验：扫描仓库 .jl 的 AST，消费 validation/migrations/*.toml
#       逐函数记录，检查目标定义、旧定义移除、悬空引用与动态 unknown
#
#   julia --project=. validation/check_migrations.jl --verbose
#   julia --project=. validation/check_migrations.jl --json
#   julia --project=. validation/check_migrations.jl --root DIR --migrations DIR
#   julia --project=. validation/check_migrations.jl --files a.jl,b.jl
#   julia --project=. validation/check_migrations.jl --print-hash FILE NAME
#
# 退出码：0 通过（pending/unknown 会打印但不算失败）/ 1 有 fail 判定 /
#         2 解析失败 / 3 记录配置错误
# =============================================================================

const HERE = @__DIR__
const REPO_ROOT = dirname(HERE)

include(joinpath(HERE, "ast", "ASTMigrate.jl"))
using .ASTMigrate

const USAGE = """
用法: julia --project=. validation/check_migrations.jl [选项]

  --selftest            运行 fixture 自测（不需要迁移记录）
  --root DIR            校验根目录（默认仓库根）
  --migrations DIR      迁移记录目录（默认 <root>/validation/migrations）
  --files A.jl,B.jl     只扫描指定文件（逗号分隔，仓库相对路径）
  --print-hash FILE NAME 打印指定文件里目标定义的规范化 SHA-256
  --verbose             打印逐文件 AST 明细
  --json                以 JSON 输出报告
  --help                显示帮助
"""

struct CliOptions
    selftest::Bool
    root::String
    migrations::Union{Nothing,String}
    files::Union{Nothing,Vector{String}}
    verbose::Bool
    json::Bool
    print_hash::Union{Nothing,Tuple{String,String}}
    help::Bool
end

function parse_args(argv::Vector{String})
    selftest = false
    root = REPO_ROOT
    migrations = nothing
    files = nothing
    verbose = false
    json = false
    ph = nothing
    help = false
    i = 1
    while i <= length(argv)
        a = argv[i]
        if a == "--selftest"
            selftest = true
        elseif a == "--verbose" || a == "-v"
            verbose = true
        elseif a == "--json"
            json = true
        elseif a == "--help" || a == "-h"
            help = true
        elseif a == "--root"
            i += 1
            i > length(argv) && return nothing
            root = argv[i]
        elseif a == "--migrations"
            i += 1
            i > length(argv) && return nothing
            migrations = argv[i]
        elseif a == "--files"
            i += 1
            i > length(argv) && return nothing
            files = [strip(x) for x in split(argv[i], ",") if !isempty(strip(x))]
        elseif a == "--print-hash"
            i + 2 > length(argv) && return nothing
            ph = (argv[i + 1], argv[i + 2])
            i += 2
        else
            println(stderr, "未知参数: ", a)
            return nothing
        end
        i += 1
    end
    return CliOptions(selftest, abspath(root), migrations, files, verbose, json, ph, help)
end

function run_selftest()
    testfile = joinpath(REPO_ROOT, "test", "ast_migration_test.jl")
    if !isfile(testfile)
        println(stderr, "找不到自测文件: ", testfile)
        return 1
    end
    Base.include(Main, testfile)
    # include 会新定义方法，必须用 invokelatest 绕开当前 world age
    return Base.invokelatest(Main.run_ast_migration_selftest)
end

function main(argv::Vector{String})
    opts = parse_args(argv)
    if opts === nothing
        println(stderr, USAGE)
        return 3
    end
    if opts.help
        print(USAGE)
        return 0
    end
    if opts.selftest
        return run_selftest()
    end
    if opts.print_hash !== nothing
        file_rel, name = opts.print_hash
        h = definition_hash(opts.root, file_rel, name)
        if h === nothing
            println(stderr, "在 ", file_rel, " 中找不到模块级定义: ", name)
            return 1
        end
        println("file     = ", file_rel)
        println("name     = ", name)
        println("sha256   = ", h)
        println("toml 写法 = target_hash = \"", h, "\"   # 目标定义哈希（source_hash 仅旧源溯源，勿混用）")
        return 0
    end

    rep = run_checks(opts.root; files=opts.files, migrations_dir=opts.migrations)
    buf = IOBuffer()
    if opts.json
        render_json(buf, rep)
    else
        render_text(buf, rep; verbose=opts.verbose)
    end
    print(String(take!(buf)))
    return exit_code(rep)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    exit(main(collect(ARGS)))
end
