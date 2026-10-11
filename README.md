<table>
  <tr>
    <td width="20%" align="center" style="border: none;">
      <img src="logo.jpg" alt="icon" width="120px"/>
    </td>
    <td width="80%" style="border: none; vertical-align: middle;">
      <h2>火星空间数据处理与科学计算工具包</h2>
      <p><b>Mars Space Data Processing & Scientific Computing Toolkit</b></p>
    </td>
  </tr>
</table>

# 索引

- [索引](#索引)
- [介绍](#介绍)
- [项目结构](#项目结构)
- [下载数据](#下载数据)
- [读取数据](#读取数据)
- [其他模型](#其他模型)
  - [火星磁场模型](#火星磁场模型)
  - [冷等离子体色散关系](#冷等离子体色散关系)
  - [麦克斯韦分布拟合](#麦克斯韦分布拟合)
  - [单粒子轨道追踪](#单粒子轨道追踪)
- [MAVEN数据说明](#maven数据说明)
- [程序与函数 Wiki](#程序与函数-wiki)
- [其他](#其他)
  - [闰秒修正](#闰秒修正)
- [ToDo List](#todo-list)

# 介绍

[English](README_EN.md) / 简体中文

本项目提供火星空间科学数据的下载、读取、处理、可视化与物理模型计算工具。主要数据处理和科学计算使用 Julia，数据下载与文件整理主要使用 Python，部分磁场计算通过 Fortran 动态库加速。

## 项目结构

| 目录/文件 | 用途 |
| --- | --- |
| `MAVEN_data/` | MAVEN 数据读取、仪器数据处理、绘图及数据格式定义 |
| `MGS_data/`、`TW_data/` | MGS 与天问数据读取和仪器处理 |
| `download_data/` | MAVEN 数据下载、下载文件检查、压缩及清理工具 |
| `models/`、`Magnetic_Model/` | 等离子体、粒子轨道、磁场等模型与计算 |
| `common/`、`support_data/` | 通用坐标/物理计算函数和外部支持数据读取 |
| `calculate/` | 模型计算流程与组合入口 |
| `example/` | 绘图和数据分析示例 |
| `doc/wiki/` | 数据读取指南、数据格式、仪器专题与[程序/函数 Wiki](doc/wiki/程序与函数Wiki.md) |
| `requirements.txt`、`requirement.jl` | Python 与 Julia 环境依赖参考 |

各程序文件职责及函数说明见[程序与函数 Wiki](doc/wiki/程序与函数Wiki.md)。

# 下载数据

使用 Python 程序下载和整理 MAVEN 数据。建议创建虚拟环境并安装 `requirements.txt` 中的依赖：

```
pip install -r requirements.txt
```

首次下载时,**需要先产生初始化设置文件**:

运行 [download_data/initialize_download_parameters.py](download_data/initialize_download_parameters.py)。

初始化后，根据本机的下载配置调整服务器、保存目录、日期范围和数据产品；下载脚本从 `download_data/MAVEN_download_config.ini` 读取设置。该配置属于本地运行配置，不一定包含在仓库中。

[download_data/MAVEN_download.py](download_data/MAVEN_download.py)负责从配置的服务器下载数据。

下载后可使用 `download_data/check_exist_files.py` 检查本地文件，使用 `download_data/compress_cdf.py` 压缩 CDF 文件，或使用 `download_data/clean_files.py` 清理未完成的下载文件。

可以使用的MAVEN外部服务器(可能需要VPN):

- USTC源,校内速度快,服务器不一定运行,数据不一定完整: http://222.195.76.155:8000/MAVEN/
- UCLA源,服务器稳定,没有NGIMS数据，数据未经压缩，体积过大: https://pds-ppi.igpp.ucla.edu/data/
- LASP源,服务器稳定，数据经过压缩，建议使用此版本: https://lasp.colorado.edu/maven/sdc/public/data/sci/
- berkeley源,格式与LASP类似,SPADES库默认服务器,相当部分的数据需要账户密码,不可直接访问: http://sprg.ssl.berkeley.edu/data/maven/data/sci/

其中'https://pds-ppi.igpp.ucla.edu/data/'的文件树与后两者不同,且没有NGIM数据

每次更新下载数据后，可重新运行 `download_data/check_exist_files.py` 检查文件清单与数据完整性。

# 读取数据

MAVEN 数据的统一读取入口为 `MAVEN_data/MAVEN_load.jl`：

```
Data_Dict = MAVEN_load.data_get_from_date(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```

此程序需要特定的读取文件树格式,
与下载部分共用文件树格式

Julia 中的引用方式:

```Julia
include("path/MAVEN_data/MAVEN_load.jl")
include("path/Magnetic_Model/IGRF_calculate.jl")
import .MAVEN_load
import .IGRF_calculate
```

具体读取方法: [MAVEN_data_format.md](doc/wiki/MAVEN_data_format.md)

读取介绍：[MAVEN数据读取.md](doc/wiki/MAVEN数据读取.md)

# 其他模型

## 火星磁场模型

./Magnetic_Model/IGRF_calculate.jl
利用 IGRF 模型计算火星模拟磁场, 含有Fortran导出的dll库, 因此需要电脑存在对应的C++和Fortran环境.

模型来源: [A Spherical Harmonic Martian Crustal Magnetic Field Model Combining Data Sets of MAVEN and MGS](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2021EA001860)

## 冷等离子体色散关系

./models/Cold_Plasma_Dispersion_Relation.jl

## 麦克斯韦分布拟合

./models/Maxwellian_distribution.jl

## 单粒子轨道追踪

./models/Single_Particle_Orbit.jl

# MAVEN数据说明

见[MAVEN数据读取](doc/wiki/MAVEN数据读取.md)，以及 [SWIA 电子修正专题](doc/wiki/swia_electron_correlated.md)。

## 程序与函数 Wiki

按目录查看程序职责、主要入口和函数说明：[程序与函数 Wiki](doc/wiki/程序与函数Wiki.md)。

# 其他

## 闰秒修正

  MAVEN的CDF文件普遍使用**CDF_TIME_TT2000**, 等价于**J2000**,该时间由**TAI** (国际原子时 - International Atomic Time)得到.

$$
$$\text{TT} = \text{TAI} + 32.184 \text{ s}
$$

  与此同时, 由于地球自转的不均匀性, **UTC** (协调世界时 - Coordinated Universal Time) 会在**TAI**的基础上, 定期加入闰秒修正来匹配地球的自然自转, 根据闰秒表, 可以得到每段时间的闰秒差异.

$$
$$\text{TAI} = \text{UTC} + (\text{累积闰秒数})
$$

  由此, 当我们将MAVEN中的J2000时间戳与**UTC**相匹配时, 需要考虑闰秒问题:

$$
$$\text{TT} = \text{UTC} + (\text{累积闰秒数}) + 32.184 \text{ s}
$$

  预计可以使用一个函数来将原始的**CDF_TIME_TT2000**时间戳改为**UTC**时间戳. 只是使用MAVEN数据时不用考虑闰秒问题.

  目前, 程序读取CDF文件epoch使用的cdflib方法,会自动处理闰秒问题. SPEDAS和spacepy同理. IDL中直接使用公式转换**CDF_TIME_TT2000**的方法可能存在闰秒修正的潜在问题.

```julia
  unix2datetime.(cdflib.cdfepoch.unixtime(get(data, "epoch")))
```

  潜在问题: 计算通常以unix时间戳为主, julia是否在处理unix时间戳和UTC时间的关系时考虑闰秒

# ToDo List

- [X] 云 MAVEN 数据
  - [ ] 支持从刘佳佳老师的LINUX服务器上以ssh-scp方式下载数据
- [ ] 利用SPEDAS包的spice核计算各个仪器的坐标变换矩阵并保存为文件
  - [X] SWIA
  - [ ] SEP
  - [ ] SWEA
- [ ] 全仪器读取
- [X] 计算shape parameter/ projects\maven\swea\mvn_swe_calc_shape_arr.pro
- [X] overview 事件绘制 example
- [ ] 优化 CDF 读取为针对仪器的模式(为每个数据包写需要的变量列表,去除不用的量的读取和 PyObject 的判定)
- [X] 优化KP_l3的读取，写一个数字->变量名的程序来处理之
- [X] 让所有的数据在读取后包含UNIX时间戳的结果(数据本身就自带了unix时间戳)
- [X] 修改下载程序,让 download_data\get_download_files.py 可以自动读取文件目录来生成列表文件
- [X] 下载程序可以检查数据版本
- [X] 简易 Julia 绘图包
- [X] 外接读取文件树
- [ ] 更多磁场模型
- [ ] Aria2的下载用户凭证
- [X] 天问数据
- [X] 磁力线追踪
- [X] 文件树去适配 SPEDAS 的结构
- [X] MAVEN STATIC
- [X] 增加项目初始化和文件处理流程的流程图
- [ ] STATIC 的处理函数目前只能对 4 维数据(时间,质量,方位角,能量)起效,更新为将所有值reshape为最高维数组后进行数组运算
- [X] 使用直接读取链接的方式, 优化下载程序: 直接读取yyyy和mm级别的路径,减去请求不存在月份的步骤
- [X] 由于julia的公共变量问题,把所有需要掩码计算的物理量以掩码模式进行
- [X] 闰秒处理：cdflib自带闰秒处理
- [ ] SWIA仪器为固定安装，理论上SWIA pl坐标系转sc坐标将为常数，因此可以先以固定值旋转pl坐标系的结果到SC坐标系，再以kp中携带的SC转MSO矩阵旋转之。同样的操作可以用于SWEA

随作者需求更新
