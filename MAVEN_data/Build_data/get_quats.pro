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
t_day = strarr(nday,3) ; 定义一个空字符串矩阵
t_day_range = fltarr(nday,2) ; 定义一个2D空矩阵
t_day1 = string(10)
path1 = string(8)
fname1 = string(8)
for i=0,nday-1 do begin
  readf,lun1,t_day1,ut1,ut2,path1,fname1,format="(A10,1X,I10,1X,I10,1X,A8,1X,A8)"
  t_day[i,*] = [strtrim(t_day1, 2),strtrim(path1, 2),strtrim(fname1, 2)] ; 确保 t_day1 是字符串
  t_day_range[i,*] = [ut1,ut2]
endfor

close,lun1
free_lun,lun1
time_day_range = ['2017-11-01','2024-12-31']
;time_day_range = ['2014-12-20','2022-05-01']
t_range = [t_day_range[0,0],t_day_range[3000,1]]
;mvn_spice_load,trange=t_range,/quaternion,/no_download,/load ;每次重新执行时将其注释掉
t_bool = 0
for i =0,nday-1 do begin
  if t_day[i] ne time_day_range[0] and t_bool eq 0 then begin
    continue
  endif else begin
    t_bool = 1
  endelse
  if t_day[i] eq time_day_range[1] then begin
     t_bool = 0
     continue
  endif
  file_name = "E:\MAVEN\SPICE\swia\"+t_day[i,1]+"mvn_spice_swia_qu_"+t_day[i,2]+".csv"
  if file_test(file_name) then begin
    continue
  endif
  print,"Doing",t_day[i]
  t_range=[t_day_range[i,0],t_day_range[i,1]]
  seconds = round(t_range[1] - t_range[0])
  nt = 0L
  for j = 0,seconds,2 do begin
    nt = nt+1
  endfor
  msorotmat_all = dblarr(nt,4)
  ut_all = dblarr(nt)
  it=0
  for j = 0,seconds,2 do begin
      ut = j + round(t_range[0])   
;      scrotmat = spice_body_att('MAVEN_SWIA','IAU_MARS',ut,/quaternion)
      msorotmat = spice_body_att('MAVEN_SWIA','MAVEN_MSO',ut,/quaternion)
      msorotmat_all[it,0:3] = msorotmat[0:3]
      ut_all[it] = ut
      it = it+1
  endfor
  openw,lun,file_name,/get_lun
  for j = 0,nt-1 do begin
    printf,lun,ut_all[j],msorotmat_all[j,*],format="(I10,1x,4(f14.10,1x))
  endfor
  close,lun
  free_lun,lun
  print,"---------done-------",i
endfor
;;
;SC IAU MSO SWIA SWEA
end