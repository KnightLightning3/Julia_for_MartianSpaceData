# 文档目录说明

本仓库只有一处文档根目录 **`docs/`**（此前的 `doc/` 已并入此处，不再单独存在）。
`docs/src/*.md` 是唯一权威文档源，Documenter 站点与 GitLab Wiki 都由它产出。

## 目录分工

| 路径 | 角色 | 维护方式 |
| --- | --- | --- |
| `src/` | **唯一权威文档源**：首页、项目执行流程、MAVEN 数据读取、MAVEN 数据格式、SWIA 电子修正、程序与函数索引 | 手工编辑；页面互链使用相对文件名（如 `data_reading.md`） |
| `build/` | Documenter 构建产物（HTML + 搜索索引） | `julia --project=docs docs/make.jl`；**不入库**（见 `.gitignore`） |
| `wiki/` | GitLab Wiki 专属页：`home.md`（首页）、`_sidebar.md`（侧边栏） | 手工编辑；其余 Wiki 页面由 `tools/push_wiki.py` 从 `src/` 生成 |
| `references/` | 参考资料：MAVEN 各仪器 SIS 手册 PDF（12 份）、《MAVEN 卫星电势揭秘》HTML | 只增不改 |
| `reports/` | 重构诊断 / 审计 / 性能校验报告**历史快照** | 只读；保留当时的函数名与路径，不随重命名更新 |
| `make.jl`、`Project.toml`、`Manifest.toml` | Documenter 工程（独立环境，Documenter v1.19） | 增删页面时编辑 `make.jl` 的 `pages` |

## 三条命令

| 产出 | 命令 | 位置 |
| --- | --- | --- |
| Documenter HTML 站点 | `julia --project=docs docs/make.jl` | `docs/build/index.html` |
| GitLab Wiki（预览） | `python tools/push_wiki.py --dry-run` | 临时目录；逐页打印来源与跨页链接改写数并进行链接自检 |
| GitLab Wiki（发布） | `python tools/push_wiki.py --push` | https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/wikis/home |

## Wiki 页面映射

`tools/push_wiki.py` 按下表把 `src/` 页面映射为 Wiki 页面，并把正文中 `](xxx.md)` 形式的跨页链接改写为
Wiki 页面名（GitLab 的相对链接使用页面 **slug**，见 [Wiki-specific Markdown](https://docs.gitlab.com/user/project/wiki/markdown/)）：

| 文档源 | Wiki 页面 |
| --- | --- |
| `src/pipeline.md` | `项目执行流程` |
| `src/data_reading.md` | `MAVEN数据读取` |
| `src/data_format.md` | `MAVEN_data_format` |
| `src/swia_electron.md` | `swia_electron_correlated` |
| `src/api.md` | `程序与函数Wiki` |
| `wiki/home.md`（手工） | `home` |
| `wiki/_sidebar.md`（手工） | `_sidebar` |

`src/index.md` 不发布为 Wiki 页面：Wiki 首页由 `wiki/home.md` 承担。

## 发布机制

GitLab Wiki **是一个独立的 Git 仓库**：

```
https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData.wiki.git
```

因此"更新 Wiki 网页"等价于向该仓库推送提交（也可以在网页界面编辑，但会被下次生成覆盖）。
`tools/push_wiki.py --push` 会：克隆或更新本地克隆 → 写入生成的页面 → 提交 → `git push origin main`。
默认克隆位置为系统临时目录，可用 `--workdir` 指定；`--prune` 才会删除远端不在生成集中的页面。

推送默认使用 SSH 远端（`git@git.ustc.edu.cn:KnightLightning/Julia_for_MartianSpaceData.wiki.git`，与主仓库 remote 同源，
无需交互式凭据）；改用 HTTPS 时加 `--remote https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData.wiki.git`，
此时需要 Git Credential Manager 或访问令牌。

## 维护约定

- 新增或重命名页面时同步三处：`docs/src/` 文件名、`docs/make.jl` 的 `pages`、`tools/push_wiki.py` 的 `PAGE_MAP`，以及其它页面中的相对链接。
- 仓库内文件链接统一使用 GitLab 规范形式 `https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/<path>`（无 `/-/` 的旧形式会 302 跳转，仍然可用）。
- 页面标题与正文中不要使用只有 Documenter 认识的语法（如 `!!! warning` 提示块），否则 Wiki 会按字面渲染；`src/index.md` 中的提示块不影响 Wiki，因为该页不发布。
- `references/` 与 `reports/` 不参与 Wiki 发布，Wiki 首页以仓库链接指向它们。
- `MAVEN_data/build_read_me.py` 会把产品表写回 `docs/src/data_format.md`（在 `MAVEN数据模块名列表` 标记之后重建表格）。
