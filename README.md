# 介绍

火星数据处理程序打包

主要数据处理程序以Julia代码为主

下载程序以Python为主

# 读取数据  
MAVEN 数据读取 MAVEN_data_load.jl,  

```
Datas = MAVEN_data_load.data_get_from_date(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```

此程序需要特定的读取文件树格式,  
与下载部分共用文件树格式  

Julia中的引用方式:  
```
include("path/MAVEN_data_load.jl")  
include("path/IGRF_carculate.jl")  
import .MAVEN_data_load  
import .IGRF_carculate  
```


# 下载数据  
使用python程序, 下载文件的方式与Julia相同  
如果不想手动下载对应的包, 建议使用虚环境, requirements.txt  
```
pip install -r requirements.txt
```
首次下载时,**需要先产生初始化设置文件**: 

运行'download_data\初始化下载参数.py'

完成设置文件的初始化后,修改'download_data\MAVEN_download_config.ini'调整下载模式,  

'download_data\MAVEN_download_from_server.py'将会下载科大服务器上的数据文件,  

'download_data\MAVEN_download.py'将会下载MAVEN官方服务器上的数据文件,  

此外,'download_data\磁场重构.jl'和'download_data\KP重构.jl'可以将MAVEN官方的磁场和KP文件转写为Fortran二进制和JULIA二进制文件以便读取  

# 火星磁场模型
IGRF_carculate.jl
利用IGRF模型计算火星模拟磁场

模型来源: [A Spherical Harmonic Martian Crustal Magnetic Field Model Combining Data Sets of MAVEN and MGS](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2021EA001860)  


# ToDo list
- [X]  云MAVEN数据  
- [ ]  全仪器读取  
- [ ]  overview事件绘制example
- [ ]  优化CDF读取为针对仪器的模式(为每个数据包写需要的变量列表，去除不用的量的读取和PyObject的判定)
- [ ]  修改下载程序，让download_data\get_download_files.py可以自动读取文件目录来生成列表文件
- [X]  简易Julia绘图包  
- [X]  外接读取文件树  
- [ ]  更多磁场模型  
- [X]  天问数据  
- [X]  磁力线追踪  
- [X]  文件树去适配SPEDAS的结构  
- [X]   MAVEN STATIC
- [ ] 增加项目初始化和文件处理流程的流程图
- [ ] STATIC的处理函数目前只能对4维数据（时间，质量，方位角，能量）起效，可能需要更新它们，但是加入额外的判断或函数可能会影响可读性，需要想更好的方法
随缘更新

# MAVEN数据Tips

## STATIC数据:
- STATIC 会返回每个时刻的(方位角,能量,离子质量数)的三维矩阵数据, 对应其中的energy,phi,theta,mass_arr矩阵
- 扫描模式: STATIC有多个不同的扫描模式,对应不同的能量范围,由swd_ind参数[0-26]决定,对应energy,phi,theta,mass_arr矩阵中的最后一个维度. 在julia这种以1开始计数的语言中,要将swd_ind参数加一
- 衰减器 衰减器attenuator会根据具体情况对小于15eV的低能量段STA数据乘以(1., 1/10, 1/100, 1/1000)以防止过饱和，官方宣称其更换时间不会小于5min，然而某些数据似乎可以用临时的过饱和解释
- STATIC返回的theta和phi,对应球坐标系的90-theta和phi,处于仪器参考系下. 文件中的quat_mso和quat_sc为四元数,可以用于将仪器参考系投影到mso和sc参考系.