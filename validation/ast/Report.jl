# =============================================================================
# Report.jl —— 文本 / JSON 报告渲染（仅依赖 Base）
# =============================================================================

const VERDICT_TAG = Dict{String,String}("ok" => "[OK]", "pending" => "[PENDING]",
                                        "unknown" => "[UNKNOWN]", "fail" => "[FAIL]")

"""记录的旧源溯源信息（source_hash 只作溯源展示，绝不参与目标核验）。"""
function record_for(rep::Report, name::AbstractString)
    i = findfirst(r -> r.name == String(name), rep.record_set.records)
    return i === nothing ? nothing : rep.record_set.records[i]
end

function provenance_text(rep::Report, u::UnitResult)
    r = record_for(rep, u.name)
    r === nothing && return ""
    isempty(r.source_hash) && return ""
    txt = "  旧源 source_hash=" * r.source_hash
    isempty(r.source_hash_kind) || (txt *= " (" * r.source_hash_kind * ")")
    isempty(r.source_revision) || (txt *= " @" * r.source_revision)
    return txt
end

const KIND_LABELS = [("function", "def_function"), ("shortdef", "def_shortdef"),
                     ("module", "def_module"), ("baremodule", "def_baremodule"),
                     ("const", "def_const"), ("binding", "def_binding"),
                     ("struct", "def_struct"), ("mutable-struct", "def_mutable_struct"),
                     ("macro", "def_macro"), ("abstract", "def_abstract"),
                     ("primitive", "def_primitive")]

function render_text(io::IO, rep::Report; verbose::Bool=false)
    inv = rep.inventory
    println(io, "== AST 迁移校验器 ==")
    println(io, "根目录      : ", rep.root)
    if rep.record_set.dir_missing
        println(io, "迁移记录    : ", rep.migrations_dir, "（目录不存在：本次未校验任何单元）")
    else
        println(io, "迁移记录    : ", rep.migrations_dir, "（", length(rep.record_files), " 个 toml / ",
                length(rep.record_set.records), " 条单元记录）")
    end
    println(io, "扫描文件    : ", get(inv, "files", 0), " 个 .jl（解析失败 ",
            length(rep.parse_errors), "）")
    if !isempty(rep.skipped_dirs)
        println(io, "已跳过目录  : ", join(sort(rep.skipped_dirs), ", "),
                "（临时/探针/团队状态目录，不当作生产源码；可用 --files 显式扫描）")
    end
    println(io)
    println(io, "--- AST 清单 ---")
    kinds = [(k, get(inv, key, 0)) for (k, key) in KIND_LABELS if get(inv, key, 0) > 0]
    println(io, "顶层定义    : ", get(inv, "defs_top", 0), "  (",
            join(["$(k) $(n)" for (k, n) in kinds], " / "), ")")
    println(io, "嵌套定义    : ", get(inv, "defs_nested", 0), "  (出现同名的名字数 ",
            get(inv, "defs_nested_names", 0), ")")
    println(io, "docstring   : ", get(inv, "docstrings", 0), " 个定义带文档串")
    println(io, "指令        : using ", get(inv, "using", 0), " / import ", get(inv, "import", 0),
            " / export ", get(inv, "export", 0), " / include 字面量 ",
            get(inv, "include_literal", 0), " 动态 ", get(inv, "include_dynamic", 0))
    println(io, "别名        : using ", get(inv, "alias_using", 0), " / import ",
            get(inv, "alias_import", 0), " / const ", get(inv, "alias_const", 0))
    println(io, "动态引用    : ", get(inv, "dynamic_total", 0), " 处（eval ",
            get(inv, "dynamic_eval", 0), " / @eval ", get(inv, "dynamic_at_eval", 0),
            " / field-access ", get(inv, "dynamic_field", 0), " / Symbol ",
            get(inv, "dynamic_symbol", 0), " / 动态 include ", get(inv, "include_dynamic", 0),
            " / 缺失探测 ", get(inv, "dynamic_absence", 0), "）")
    println(io, "模块作用域数: ", get(inv, "scopes", 0))

    if verbose && !isempty(rep.index.order)
        println(io)
        println(io, "--- 逐文件定义（verbose）---")
        for rel in rep.index.order
            s = rep.index.scans[rel]
            topl = [d.name for d in s.defs if d.top_level]
            nest = [d.name for d in s.defs if !d.top_level]
            println(io, rel, "  顶层 ", length(topl), " 嵌套 ", length(nest), " include ",
                    length(s.includes), " 指令 ", length(s.directives), " 动态 ", length(s.dynamic_sites))
            isempty(topl) || println(io, "    top: ", join(topl, ", "))
            isempty(nest) || println(io, "    nested: ", join(nest, ", "))
        end
    end

    if verbose && !isempty(rep.index.dynamic_sites)
        println(io)
        println(io, "--- 动态引用点（verbose）---")
        for d in rep.index.dynamic_sites
            println(io, "  ", d.file, ":", d.line, " ", d.kind, " 名称=", isempty(d.hint) ? "?" : d.hint,
                    " ", d.unknown_name ? "（名称不可判定）" : "", "  ", d.snippet)
        end
    end

    println(io)
    println(io, "--- 单元结果（", length(rep.units), "）---")
    if isempty(rep.units)
        println(io, "（无迁移记录：本次没有可校验单元）")
    end
    for u in rep.units
        rename = u.source_name == u.name ? "" : ("  ← " * u.source_name)
        println(io, get(VERDICT_TAG, u.verdict, "[?]"), " ", u.name, rename, "  [",
                isempty(u.status) ? "status?" : u.status, "/", u.action, "]")
        hashline = isempty(u.hash_expected) ? "" :
                   (lowercase(u.hash_actual) == u.hash_expected ? " target_hash=✓" :
                    " target_hash=$(u.hash_expected) 实际=$(isempty(u.hash_actual) ? "-" : u.hash_actual)")
        prov = provenance_text(rep, u)
        println(io, "        from=", u.from, isempty(u.to) ? "" : ("  to=" * u.to), hashline, prov)
        for fd in u.findings
            loc = isempty(fd.file) ? "" : (" " * fd.file * (fd.line > 0 ? ":" * string(fd.line) : ""))
            println(io, "        - ", uppercase(fd.severity), " ", fd.code, loc, " ", fd.message)
        end
    end

    unf = unfinished_units(rep)
    println(io)
    println(io, "--- 未完成清单（", length(unf), "）---")
    if isempty(unf)
        println(io, "（无：未发现 pending/unknown 单元）")
    else
        for u in unf
            cands = [x for x in u.findings if x.severity in ("pending", "unknown")]
            fd = isempty(cands) ? (isempty(u.findings) ? nothing : u.findings[1]) : cands[1]
            reason = fd === nothing ? "" : (fd.code * " " * fd.message)
            println(io, "  - ", u.name, " [", u.verdict, "] ", reason)
        end
    end

    if !isempty(rep.record_errors)
        println(io)
        println(io, "--- 记录错误（阻塞，退出码 3）---")
        for e in rep.record_errors
            println(io, "  - ", e.code, " ", e.file, " ", e.message)
        end
    end
    if !isempty(rep.record_warnings)
        println(io)
        println(io, "--- 记录告警（不阻塞）---")
        for e in rep.record_warnings
            println(io, "  - ", e.code, " ", e.file, " ", e.message)
        end
    end
    if !isempty(rep.parse_errors)
        println(io)
        println(io, "--- 解析失败（阻塞，退出码 2）---")
        for p in rep.parse_errors
            println(io, "  - ", p.file, ":", p.line, " ", p.message)
        end
    end
    if !isempty(rep.index.include_missing)
        println(io)
        println(io, "--- include 目标缺失（告警）---")
        for (f, inc, ln) in rep.index.include_missing
            println(io, "  - ", f, ":", ln, " include(", inc, ") 不在扫描集合内")
        end
    end

    nfail = length(units_with_verdict(rep, "fail"))
    npend = length(units_with_verdict(rep, "pending"))
    nunk = length(units_with_verdict(rep, "unknown"))
    nok = length(units_with_verdict(rep, "ok"))
    println(io)
    println(io, "退出码: ", exit_code(rep), "  (ok ", nok, " / fail ", nfail, " / pending ", npend,
            " / unknown ", nunk, ")")
    return
end

# ---------------------------------------------------------------------------
# JSON（手写最小序列化，避免额外依赖）
# ---------------------------------------------------------------------------

function json_string(io::IO, s::AbstractString)
    print(io, '"')
    for c in s
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        elseif c == '\t'
            print(io, "\\t")
        elseif Int(c) < 0x20
            print(io, "\\u", lpad(string(Int(c); base=16), 4, '0'))
        else
            print(io, c)
        end
    end
    print(io, '"')
    return
end

function json_write(io::IO, x, indent::Int)
    pad = " " ^ indent
    pad2 = " " ^ (indent + 2)
    if x === nothing
        print(io, "null")
    elseif x isa Bool
        print(io, x ? "true" : "false")
    elseif x isa Integer
        print(io, x)
    elseif x isa AbstractFloat
        print(io, isfinite(x) ? x : "null")
    elseif x isa AbstractString
        json_string(io, x)
    elseif x isa AbstractDict
        isempty(x) && return print(io, "{}")
        ks = sort(collect(keys(x)); by=string)
        print(io, "{\n")
        for (i, k) in enumerate(ks)
            print(io, pad2)
            json_string(io, string(k))
            print(io, ": ")
            json_write(io, x[k], indent + 2)
            i == length(ks) || print(io, ",")
            print(io, "\n")
        end
        print(io, pad, "}")
    elseif x isa AbstractVector || x isa Tuple
        isempty(x) && return print(io, "[]")
        print(io, "[\n")
        for (i, v) in enumerate(x)
            print(io, pad2)
            json_write(io, v, indent + 2)
            i == length(x) || print(io, ",")
            print(io, "\n")
        end
        print(io, pad, "]")
    else
        json_string(io, string(x))
    end
    return
end

finding_json(f::Finding) = Dict{String,Any}("severity" => f.severity, "code" => f.code,
                                            "file" => f.file, "line" => f.line, "message" => f.message)

function render_json(io::IO, rep::Report)
    obj = Dict{String,Any}(
        "root" => rep.root,
        "migrations_dir" => rep.migrations_dir,
        "migrations_dir_missing" => rep.record_set.dir_missing,
        "record_files" => rep.record_files,
        "record_count" => length(rep.record_set.records),
        "files_scanned" => get(rep.inventory, "files", 0),
        "inventory" => rep.inventory,
        "record_errors" => [Dict("code" => e.code, "file" => e.file, "message" => e.message)
                            for e in rep.record_errors],
        "record_warnings" => [Dict("code" => e.code, "file" => e.file, "message" => e.message)
                              for e in rep.record_warnings],
        "parse_errors" => [Dict("file" => p.file, "line" => p.line, "message" => p.message)
                           for p in rep.parse_errors],
        "dynamic_sites" => [Dict("kind" => d.kind, "file" => d.file, "line" => d.line,
                                 "hint" => d.hint, "unknown_name" => d.unknown_name,
                                 "snippet" => d.snippet) for d in rep.index.dynamic_sites],
        "unfinished" => [u.name for u in unfinished_units(rep)],
        "units" => [unit_json(rep, u) for u in rep.units],
        "exit_code" => exit_code(rep),
    )
    json_write(io, obj, 0)
    println(io)
    return
end

"""单元 JSON：target 哈希（核验用）与 source_hash（旧源溯源）分列，语义不混用。"""
function unit_json(rep::Report, u::UnitResult)
    r = record_for(rep, u.name)
    return Dict{String,Any}("name" => u.name, "status" => u.status, "action" => u.action,
                            "from" => u.from, "to" => u.to,
                            "target_hash_expected" => u.hash_expected,
                            "target_hash_actual" => u.hash_actual, "verdict" => u.verdict,
                            "target_hash_verifiable" => r === nothing ? false : r.target_hash_verifiable,
                            "target_hash_field" => r === nothing ? "" : r.hash_field,
                            "source_hash" => r === nothing ? "" : r.source_hash,
                            "source_hash_kind" => r === nothing ? "" : r.source_hash_kind,
                            "source_revision" => r === nothing ? "" : r.source_revision,
                            "findings" => [finding_json(f) for f in u.findings])
end
