; 取得3D quat值, 对于以下三种仪器起效. 必须包含SPEDAS_6_1版本的包
; spedas_6_1\projects\maven\eph\mvn_pfp_cotrans.pro
; "%s,%010.0f,%010.0f\n"
;time = unix_time
;mk = mvn_spice_kernels(/load, /all, trange='2015-10-29/11:30:00', verbose=verbose)
;spice_body_att("MAVEN_SWIA","MAVEN_MSO",'2015-10-29/11:30:00',/quaternion)
;spice_body_att("MAVEN_SWEA","MAVEN_MSO",'2015-10-29/11:30:00',/quaternion)

openr,lun1,"D:\CODE\Package_for_Julia\MAVEN_data\Build_data\dateunix.csv",/get_lun
readf,lun1,nday,format="(I10)"
t_day = strarr(nday) ; 定义一个空字符串矩阵
t_day_range = fltarr(nday,2) ; 定义一个2D空矩阵
t_day1 = string(10)
for i=0,nday-1 do begin
  readf,lun1,t_day1,ut1,ut2,format="(A10,1X,I10,1X,I10)"
  t_day[i] = strtrim(t_day1, 2) ; 确保 t_day1 是字符串
  t_day_range[i,*] = [ut1,ut2]
endfor
close,lun1
mvn_spice_load,/no_download
for i =0,nday-1 do begin
  t_range=[t_day_range[i,0],t_day_range[i,1]]
;  mvn_spice_load,trange=t_range,/download_only,/quaternion
  openw,lun,"E:\MAVEN\SPICE\"+t_day[i]+"_swia_qu.csv",/get_lun
  for j = t_range[0],t_range[1] do begin
    ut = j
;    mk = mvn_spice_kernels(/load, /all, trange=ut)
    scrotmat = spice_body_att('MAVEN_SWIA','IAU_MARS',ut,verbose=-1,/quaternion)
    msorotmat = spice_body_att('MAVEN_SWIA','MAVEN_MSO',ut,verbose=-1,/quaternion)
    printf,lun,ut,scrotmat,msorotmat,format="(f20.7,1x,4(f14.10,1x),4(f14.10,1x))"
   end
  close,lun
endfor
;;
;SC IAU MSO SWIA SWEA
end