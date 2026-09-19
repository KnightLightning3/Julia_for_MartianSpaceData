<!-- <div align="center"> -->
<!-- <img src="./docs/images/icon.svg" alt="icon"/> -->

> **火星空间数据处理与科学计算工具包**  
> **Mars Space Data Processing & Scientific Computing Toolkit**

# 索引

- [索引](#索引)
- [介绍](#介绍)
- [下载数据](#下载数据)
- [读取数据](#读取数据)
- [其他模型](#其他模型)
  - [火星磁场模型](#火星磁场模型)
  - [冷等离子体色散关系](#冷等离子体色散关系)
  - [麦克斯韦分布拟合](#麦克斯韦分布拟合)
  - [单粒子轨道追踪](#单粒子轨道追踪)
- [MAVEN数据说明](#maven数据说明)
- [其他](#其他)
  - [闰秒修正](#闰秒修正)
- [ToDo List](#todo-list)

# 介绍

[English](README_EN.md) / 简体中文

火星空间数据处理程序

主要数据处理程序以 Julia 代码为主

下载程序以 Python 为主

个别计算程序使用Fortran

# 下载数据

使用 python 程序, 下载文件的方式与 Julia 相同
如果不想手动下载对应的包, 建议使用虚环境, requirements.txt

```
pip install -r requirements.txt
```

首次下载时,**需要先产生初始化设置文件**:

运行[download_data\initialize_download_parameters.py](download_data\initialize_download_parameters.py)

完成设置文件的初始化后,修改[download_data\MAVEN_download_config.ini](download_data\MAVEN_download_config.ini)调整下载模式, 默认模式为从USTC源下载2014-10 至 2023-02 的全部数据

[download_data\MAVEN_download.py](download_data\MAVEN_download.py)将会下载指定服务器上的数据文件, 建议从科大源下载(Server_ind = 0)

此外,[download_data\磁场重构.jl](download_data\磁场重构.jl)和[download_data\KP 重构.jl](download_data\KP 重构.jl)可以将 MAVEN 官方的磁场和 KP 文件转写为 Fortran 二进制和 JULIA 二进制文件以便读取

可以使用的MAVEN外部服务器(可能需要VPN):

- USTC源,校内速度快,服务器不一定运行,数据不一定完整: http://222.195.76.155:8000/MAVEN/
- UCLA源,服务器稳定,没有NGIMS数据，数据未经压缩，体积过大: https://pds-ppi.igpp.ucla.edu/data/
- LASP源,服务器稳定，数据经过压缩，建议使用此版本: https://lasp.colorado.edu/maven/sdc/public/data/sci/
- berkeley源,格式与LASP类似,SPADES库默认服务器,相当部分的数据需要账户密码,不可直接访问: http://sprg.ssl.berkeley.edu/data/maven/data/sci/

其中'https://pds-ppi.igpp.ucla.edu/data/'的文件树与后两者不同,且没有NGIM数据

每次更新下载数据后，需要执行[download_data/check_exist_files.py](download_data/check_exist_files.py)来更新此文件

# 读取数据

MAVEN 数据读取 MAVEN_load.jl,

```
Data_Dict = MAVEN_load.data_get_from_date(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```

此程序需要特定的读取文件树格式,
与下载部分共用文件树格式

Julia 中的引用方式:

```Julia
include("path/MAVEN_load.jl")
include("path/IGRF_calculate.jl")
import .MAVEN_load
import .IGRF_calculate
```

具体读取方法: [MAVEN_data_format.md](MAVEN_data/MAVEN_data_format.md)

读取介绍：[MAVEN数据读取.md](doc/MAVEN数据读取.md)

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

./models/Maxwellian_distribution.jl
考虑内核改为Fortran以加快计算

# MAVEN数据说明

见[MAVEN数据读取](doc/MAVEN数据读取.md)

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
- [ ] 由于julia的公共变量问题,把所有需要掩码计算的物理量以掩码模式进行
- [X] 闰秒处理：cdflib自带闰秒处理

随作者需求更新
