<!-- <div align="center"> -->
<!-- <img src="./docs/images/icon.svg" alt="icon"/> -->

<h1 align="center">Julia Pkg for Mars</h1>

# 介绍

[English](README_EN.md) / 简体中文

火星数据处理程序打包

主要数据处理程序以 Julia 代码为主

下载程序以 Python 为主

# 读取数据

MAVEN 数据读取 MAVEN_data_load.jl,

```
Data_Dict = MAVEN_data_load.data_get_from_date(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```

此程序需要特定的读取文件树格式,  
与下载部分共用文件树格式

Julia 中的引用方式:

```
include("path/MAVEN_data_load.jl")
include("path/IGRF_calculate.jl")
import .MAVEN_data_load
import .IGRF_calculate
```

# 下载数据

使用 python 程序, 下载文件的方式与 Julia 相同  
如果不想手动下载对应的包, 建议使用虚环境, requirements.txt

```
pip install -r requirements.txt
```

首次下载时,**需要先产生初始化设置文件**:

运行'download_data\initialize_download_parameters.py'

完成设置文件的初始化后,修改'download_data\MAVEN_download_config.ini'调整下载模式, 默认模式为从USTC源下载2014-10 至 2023-02 的全部数据

'download_data\MAVEN_download.py'将会下载指定服务器上的数据文件, 建议从科大源下载(Server_ind = 0)

此外,'download_data\磁场重构.jl'和'download_data\KP 重构.jl'可以将 MAVEN 官方的磁场和 KP 文件转写为 Fortran 二进制和 JULIA 二进制文件以便读取

可以使用的MAVEN外部服务器(可能需要VPN):
- USTC源,校内速度快,服务器不一定运行,数据不一定完整: http://222.195.76.155:8000/MAVEN/
- UCLA源,服务器稳定,没有NGIMS数据: https://pds-ppi.igpp.ucla.edu/data/
- LASP源,服务器稳定: https://lasp.colorado.edu/maven/sdc/public/data/sci/
- berkeley源,格式与LASP类似,SPADES库默认服务器,相当部分的数据需要账户密码,不可直接访问: http://sprg.ssl.berkeley.edu/data/maven/data/sci/

其中https://pds-ppi.igpp.ucla.edu/data/的文件树与后两者不同,且没有NGIM数据

# 火星磁场模型

IGRF_calculate.jl
利用 IGRF 模型计算火星模拟磁场

模型来源: [A Spherical Harmonic Martian Crustal Magnetic Field Model Combining Data Sets of MAVEN and MGS](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2021EA001860)

# ToDo list

- [x] 云 MAVEN 数据
- [ ] 利用SPEDAS包的spice核计算各个仪器的坐标变换矩阵并保存为文件
- [ ] 利用SPEDAS包的spice核计算飞行器的速度, 加速度, 轨道参数等并保存为文件
- [ ] 全仪器读取
- [ ] 计算shape parameter/ projects\maven\swea\mvn_swe_calc_shape_arr.pro
- [X] overview 事件绘制 example
- [ ] 优化 CDF 读取为针对仪器的模式(为每个数据包写需要的变量列表,去除不用的量的读取和 PyObject 的判定)
- [X] 修改下载程序,让 download_data\get_download_files.py 可以自动读取文件目录来生成列表文件
- [X] 下载程序可以检查数据版本
- [x] 简易 Julia 绘图包
- [x] 外接读取文件树
- [ ] 更多磁场模型
- [x] 天问数据
- [x] 磁力线追踪
- [x] 文件树去适配 SPEDAS 的结构
- [x] MAVEN STATIC
- [X] 增加项目初始化和文件处理流程的流程图
- [ ] STATIC 的处理函数目前只能对 4 维数据(时间,质量,方位角,能量)起效,更新为将所有值reshape为最高维数组后进行数组运算
      随缘更新

# MAVEN 数据 Tips

## STATIC 数据:

- STATIC 会返回每个时刻的(方位角,能量,离子质量数)的三维矩阵数据, 对应其中的 energy,phi,theta,mass_arr 矩阵
- 扫描模式: STATIC 有多个不同的扫描模式,对应不同的能量范围,由 swd_ind 参数[0-26]决定,对应 energy,phi,theta,mass_arr 矩阵中的最后一个维度. 在 julia 这种以 1 开始计数的语言中,要将 swd_ind 参数加一
- 衰减器 衰减器 attenuator 会根据具体情况对小于 15eV 的低能量段 STA 数据乘以(1., 1/10, 1/100, 1/1000)以防止过饱和,官方宣称其更换时间不会小于 5min,然而一些数据可以用临时的过饱和解释,而且有切换 attenuator
- STATIC 返回的 theta 和 phi,对应球坐标系的 90-theta 和 phi,处于仪器参考系下. 文件中的 quat_mso 和 quat_sc 为四元数,可以用于将仪器参考系投影到 mso 和 sc 参考系.
- STATIC, SWEA, SWIA 使用的参考系为对应球坐标系的 90-theta 和 phi, ref:spedas_6_1\general\science\sphere_to_cart.pro

## VSC 数据:

vsc数据本身可以由spice程序包计算. 但是其存在学习门槛. 此程序包中包含直接使用mag中以1秒为精度的位置数据通过计算二次函数拟合取得的vsc数据, 保存于MAG/vsc/