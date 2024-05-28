# MAVEN 各数据包内容格式

STA系列：
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