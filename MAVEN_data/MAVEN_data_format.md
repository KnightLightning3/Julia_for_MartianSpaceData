# MAVEN 各数据包内容格式

## STA系列：
- swp_ind 从0开始计数，使用julia时需要给数值加一
- Note that [phi, theta] = [0, 0]deg corresponds to $−Y_{MSO}$ and [+90, 0]deg corresponds to $+Z_{MSO}$

STA操作example
```julia
# 取得数据
sta_data  = MAVEN_load.data_get_from_date(DateTime(2015,2,9), model_index = ["STATIC_cf"])["STATIC_cf"];
# 取得给定时间的切片
sta_slip_data = MAVEN_load.static_slip(sta_data,time_ind);
# 旋转坐标到MSO坐标系
sta_slip_data = MAVEN_load.static_rotation(sta_slip_data;frame="MSO");
# 取得离子速度
vel,_,_ = MAVEN_load.sta_v_4d(sta_slip_data; energy_range=[0,1e4],mass_range=[0,2],m_int = 1) 
# 将坐标换成速度分布
V_data = MAVEN_load.static_slip_2_V(sta_slip_data;mass_range=[0,2],m_int = 1);
# 绘制tri图片
ax = MAVEN_plot.STA_2d_slip(ax,V_data;frame="perp_xy",colorrange=(1e-12,1e-4),vbluk=vel)
```

## MAG系列:
- MAG为sts文件保存,为读取更快,修改为二进制存储的文件MAG_xx_l3

## KP:
- 有不同的版本号,不同版本的数据排布有一些区别
- 考虑制作为KP_l3的julia二进制文件
- SCP - SpaceCraft Potential available and used as computed by STATIC, SC0 - SpaceCraft potential not available
- Inbound ('I') is from geometric apoapsis to next geometric periapsis in time, outbound ('O') is the reverse 
文件格式:  
fortan部分
```fortran
版本号: I2,对应v15,v19等
时间维度ntime,对应数据的行数
总变量数n,对应数据的列数
时间量: Float64, unix时间
其余变量:ntime*(n-1)个量,Float64
```

```python
data={
    变量编号:{
        "Varname":变量名
        "Vars":变量内容
    }
}
```

## 数据下载
使用`download_data\MAVEN_download.py`和`download_data\MAVEN_download_from_server.py`程序下载

数据下载为固定的格式  `SAVE_PATH/model/处理程度/年/月/ `   

一次固定下载一个月的数据

下载完成后自动产生list文件以保存下载的文件列表

需要使用`download_data\get_download_files.py`来生成一个本地的filename_lists.json的文件保存所有文件的目录以便程序查询之

以后可能会考虑弃用此方法,改为直接去对于年月文件夹寻找文件

## SPADES问题
2024-7-1的闰秒导致程序出错，暂时修改代码忽略它