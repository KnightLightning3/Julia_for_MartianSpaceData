# =============================================================================
# ASTMigrate.jl —— AST 迁移清单校验器（模块入口，仅依赖 Base / TOML / SHA）
#
# 由 validation/check_migrations.jl 与 test/ast_migration_test.jl 调用。
# 只做「可静态解析」的校验：任何无法静态解析的动态写法都显式报告 unknown。
# =============================================================================

module ASTMigrate

using SHA
using TOML

include("ExprWalk.jl")
include("Scanner.jl")
include("Index.jl")
include("Records.jl")
include("Checks.jl")
include("Report.jl")

export run_checks, Report, UnitResult, Finding, exit_code, render_text, render_json,
       load_records, definition_hash

end # module ASTMigrate
