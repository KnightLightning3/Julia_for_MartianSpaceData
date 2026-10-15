# 文档维护与构建

README 提供上手入口；`docs/src/` 提供当前架构、迁移方式、执行流程和科学专题。Documenter HTML 与 GitLab Wiki 使用同一组正文，**Documenter 不直接生成或发布 GitLab Wiki**。

## 文件职责

| 位置 | 维护方式 |
| --- | --- |
| `../README.md`、`../README_EN.md` | 中英文入口；保留相同的示例和架构事实 |
| `src/index.md` | Documenter 首页 |
| `src/architecture.md`、`src/migration.md` | 当前模块边界、旧入口和名称迁移；手工维护 |
| `src/coordinates.md` | 点坐标接口、仪器球坐标约定与旋转方向专题；手工维护 |
| `src/pipeline.md`、`src/data_reading.md` | 共用 TOML 路径配置、Python 下载/索引/构建与实际读取接口；手工维护 |
| `src/data_format.md` | 产品说明前言手工维护；产品表从 JSON 注册表生成 |
| `src/swia_electron.md` | 科学专题；改版文档时保留公式与假设的含义 |
| `src/api.md` | `tools/generate_api.jl` 静态生成；不要直接编辑生成正文 |
| `pages.toml` | Documenter 导航及 Wiki 页面名称的共同清单 |
| `wiki/home.md`、`wiki/_sidebar.md` | Wiki 专属首页与侧边栏，手工维护 |
| `build/` | Documenter HTML 产物，不入库 |
| `references/` | 仪器手册和参考材料 |
| `reports/` | 历史报告；保留当时的路径与判断，不作为当前接口规范 |

工作树中可能有未跟踪的旧 `doc/` 材料；它不参与本构建，不应因整理当前文档而自动删除。

## 更新与校核顺序

下面命令均在仓库根目录运行。Julia 要求 1.10+，Python 要求 3.11+。

```bash
# 1. 从当前源码生成函数索引；不会include生产模块或运行数据/DLL
julia --startup-file=no tools/generate_api.jl
julia --startup-file=no tools/generate_api.jl --check

# 2. 更新产品表（重建“MAVEN数据模块名列表”标记之后的内容）
python3 MAVEN_data/build_read_me.py

# 3. 文档映射、链接和Wiki预览
python3 tests/test_docs_tooling.py
python3 tools/push_wiki.py --dry-run --out /tmp/marsdata-wiki-preview

# 4. 独立Documenter环境；首次构建先安装依赖
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

HTML 入口为 `docs/build/index.html`。`docs/make.jl` 使用脚本所在目录作为文档根，遇到构建警告或错误会失败；不依赖安装完整科学运行环境。文档构建既不调用 IGRF DLL，也不读取真实科学数据。

API 生成器只做静态分析：收集生产文件中的模块及顶层函数/短定义，从已有 docstring 提取用途，不执行代码。它不承诺列出的每个内部函数都是稳定公开 API，也不验证公式或数据结果。模块 `export` 与装载器 `allow` 是不同概念。

产品表以 `MAVEN_data/MAVEN_data_format.json` 为准；生成器会重写标记后的表格，手工说明应放在标记之前。新增页面时编辑 `pages.toml`，再更新首页/侧边栏的阅读入口，无需分别维护 Julia 和 Python 的页面映射字典。

## 页面映射

| 源文件 | Wiki 页面 |
| --- | --- |
| `src/architecture.md` | `项目架构` |
| `src/migration.md` | `迁移指南` |
| `src/coordinates.md` | `坐标转换` |
| `src/pipeline.md` | `项目执行流程` |
| `src/data_reading.md` | `MAVEN数据读取` |
| `src/data_format.md` | `MAVEN_data_format` |
| `src/swia_electron.md` | `swia_electron_correlated` |
| `src/api.md` | `程序与函数Wiki` |
| `wiki/home.md` | `home` |
| `wiki/_sidebar.md` | `_sidebar` |

Documenter 的 `index.md` 不单独发布到 Wiki；指向它的相对链接在 Wiki 生成时转为 `home`。正文页互链使用相对 Markdown 文件名，例如 `[架构](architecture.md)`；源码和历史报告链接使用仓库的绝对 URL。共用页面避免只支持 Documenter 的专有块语法。数学表达式在源中采用 Julia Markdown 的双反引号行内数学和 fenced `math` 块；Wiki 生成器把行内数学转换为 [GitLab 数学语法](https://docs.gitlab.com/user/markdown/) 的美元符号加反引号形式，代码块不转换。只改公式定界，不改公式内容。

## Wiki 发布

预览命令只在本地输出 Markdown，不连接远端。Wiki 是[独立 Git 仓库](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/wikis/home)，正式发布会产生提交和 push：

```bash
python3 tools/push_wiki.py --push
```

默认 SSH 远端为 `git@git.ustc.edu.cn:KnightLightning/Julia_for_MartianSpaceData.wiki.git`。`--workdir` 指定 Wiki 克隆目录，`--remote` 可改远端；`--prune` 会删除未列入生成集的旧页面，只应在明确需要时使用。发布脚本会重置其专用克隆，不要把含有其他工作的目录传给 `--workdir`。

文档编辑和本地构建不等于远端发布；本轮仅准备可审阅的本地内容。历史报告、参考资料和主代码仓库不会由 Wiki 生成操作改写。

## 逻辑基准与本轮范围

科学逻辑溯源基准为提交 `a09511aa7b88c874cefe8ca966c98aa267db9365`。现有中间基线夹具的通过不等于全仓相对初始提交的证明。真实数据校验暂时挂起，DLL 验证不列为要求；文档同步应准确标注这些边界，而不新增未经证明的等价性结论。
