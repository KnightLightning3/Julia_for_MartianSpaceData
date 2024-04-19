; 取得3D quat值, 对于以下三种仪器起效. 必须包含SPEDAS_6_1版本的包
; spedas_6_1\projects\maven\eph\mvn_pfp_cotrans.pro
; "%s,%010.0f,%010.0f\n"
;time = 1.655062798252e9
;mk = mvn_spice_kernels(/load, /all, trange=time, verbose=verbose)
;rot = spice_body_att("MAVEN_SWIA","MAVEN_MSO",time,/quaternion)
;rot = spice_body_att("MAVEN_SWEA","MAVEN_MSO",time,/quaternion)
;
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
free_lun,lun1
t_range = [t_day_range[0,0],t_day_range[3000,1]]
mvn_spice_load,trange=t_range,/quaternion,/no_download,/load
t_bool = 0
for i =102,nday-1 do begin
  print,"Doing",t_day[i]
  if t_day[i] ne '2015-01-01' and t_bool eq 0 then begin
    continue
  endif else begin
    t_bool = 1
  endelse
  if t_day[i] eq '2015-10-01' then begin
     t_bool = 0
     continue
  endif
  
  t_range=[t_day_range[i,0],t_day_range[i,1]]
;  mvn_spice_load,trange=t_range,/download_only,/quaternion
;  mk = mvn_spice_kernels(trange=t_range,/load,/all,/valid_only)
  seconds = round(t_range[1] - t_range[0])
  openw,lun,"E:\MAVEN\SPICE\"+t_day[i]+"_swia_qu.csv",/get_lun

  for j = 0,seconds,2 do begin
    ut = j + round(t_range[0])   
;      scrotmat = spice_body_att('MAVEN_SWIA','IAU_MARS',ut,/quaternion)
      msorotmat = spice_body_att('MAVEN_SWIA','MAVEN_MSO',ut,/quaternion)
    printf,lun,ut,msorotmat,format="(I10,1x,4(f14.10,1x))
  endfor
;  ON_ERROR, old_error_setting
  close,lun
  free_lun,lun
  print,"---------done-------",i
endfor
;;
;SC IAU MSO SWIA SWEA
end