# MarsData.jl 文档构建脚本（Documenter）。
#
# 用法：
#     julia --project=docs docs/make.jl      # 生成 HTML 到 docs/build/
using Documenter

makedocs(
    sitename = "MarsData.jl 文档",
    authors = "Cheng Sanwei",
    format = Documenter.HTML(
        prettyurls = false,
        edit_link = nothing,
        repolink = "https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData",
    ),
    pages = [
        "首页" => "index.md",
        "项目执行流程" => "pipeline.md",
        "MAVEN 数据读取" => "data_reading.md",
        "MAVEN 数据格式" => "data_format.md",
        "SWIA 电子修正" => "swia_electron.md",
        "程序与函数索引" => "api.md",
    ],
    warnonly = true,
    checkdocs = :none,
    modules = Module[],
    remotes = nothing,
)

println("DOCS_BUILD_OK: docs/build/index.html")
