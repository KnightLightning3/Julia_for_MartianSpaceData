# MarsData.jl 文档构建脚本（Documenter）。
#
# 用法：
#     julia --project=docs docs/make.jl      # 生成 HTML 到 docs/build/
using Documenter
using TOML

const DOCS_ROOT = @__DIR__
const PAGE_MANIFEST = TOML.parsefile(joinpath(DOCS_ROOT, "pages.toml"))
const NAVIGATION = [
    page["title"] => page["source"] for page in PAGE_MANIFEST["pages"]
]

makedocs(
    root = DOCS_ROOT,
    sitename = "MarsData.jl 文档",
    authors = "Cheng Sanwei",
    format = Documenter.HTML(
        prettyurls = false,
        edit_link = nothing,
        repolink = "https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData",
    ),
    pages = NAVIGATION,
    warnonly = false,
    checkdocs = :none,
    modules = Module[],
    remotes = nothing,
)

println("DOCS_BUILD_OK: docs/build/index.html")
