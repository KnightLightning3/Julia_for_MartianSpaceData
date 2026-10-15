# MarsData.jl 文档

本项目使用 Julia 读取、处理和绘制火星空间科学数据，使用 Python 管理配置、下载、库存与文件索引，并提供环境、磁场和粒子计算工具。

当前代码已经完成多项模块拆分与文件迁移。旧的 `common/head.jl`、`calculate/calculate_models.jl` 已删除；首次使用请从架构和迁移指南开始，而不是直接运行历史脚本。

## 从这里开始

| 页面 | 解决的问题 |
| --- | --- |
| [项目架构](architecture.md) | 包初始化、模块装载、白名单、通用能力、模型、分析脚本与 Extras 的边界 |
| [迁移指南](migration.md) | 旧路径、已删除入口、改名、质量基准与非等价函数的适配 |
| [坐标转换](coordinates.md) | 三套球坐标约定、三维点接口、旋转方向与批处理示例 |
| [项目执行流程](pipeline.md) | 准备环境、配置、下载、扫描索引、构建派生产品与读取 |
| [MAVEN 数据读取](data_reading.md) | 单日接口、错误收集、加载标志和索引惰性读取 |
| [MAVEN 数据格式](data_format.md) | 产品注册表、STATIC 使用顺序、维度与单位注意事项 |
| [SWIA 电子修正](swia_electron.md) | 电子修正专题的理论与代码位置 |
| [程序与函数索引](api.md) | 从当前 Julia 源码静态生成的定义索引 |

## 先确认环境，再读取数据

在仓库根目录启动 Julia：

```bash
julia --project=.
```

```julia
using Pkg
Pkg.instantiate()  # 只安装根项目声明的依赖
using MarsData

MarsData.project_root()
MarsData.data_model()       # 产品注册表，不读取科学数据
MarsData.module_info(:MAVEN_load)
```

`using MarsData` 会载入绘图栈及预装通用模块，但不会自动装载 MAVEN 科学读取器。读取器、ODE 和实验算法所需的额外包必须能由相应环境解析；详细边界见架构页。配置、索引和目标日期的数据文件也需要单独准备。

## 文档来源与生成

`docs/src/` 保存专题正文；`docs/pages.toml` 是 Documenter 页面导航和 Wiki 页面映射的共同清单。两种发布形式使用同一组正文：Documenter 生成 HTML，Python 脚本转换并输出 GitLab Wiki 页面。Wiki 首页与侧边栏另在 `docs/wiki/` 维护。

```bash
julia --startup-file=no tools/generate_api.jl  # 更新源码定义索引
julia --project=docs docs/make.jl              # HTML -> docs/build/
python3 tools/push_wiki.py --dry-run           # 本地生成 Wiki 并检查跨页链接
```

生成器不会运行科学模块或分析脚本。文档环境首次使用时，运行 `julia --project=docs -e 'using Pkg; Pkg.instantiate()'` 安装 Documenter。文档维护和发布步骤见仓库内 `docs/README.md`。

## 使用边界与历史资料

当前逻辑溯源基准为提交 `a09511aa7b88c874cefe8ca966c98aa267db9365`；本轮文档同步不构成全仓相对该基准的科学一致性证明。真实数据校验暂挂，DLL 验证不在本轮范围内。

[历史报告](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/tree/main/docs/reports)与 [CHANGELOG](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/blob/main/CHANGELOG.md) 保留当时的路径与结论。当前入口以本组页面和源码为准；仪器手册位于[参考资料](https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData/-/tree/main/docs/references)。
