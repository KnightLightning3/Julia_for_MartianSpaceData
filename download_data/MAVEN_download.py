# Download data from the MAVEN server. It is recommended to configure vpn to the US node. If not configured, you need to set vpn_proxy=None.
import datetime
import os
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm
import re
from time import sleep
import time
import json
import configparser
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
import math
def get_list_from_ini(input_string):
    if input_string == 'Null':
        return []
    if input_string == 'None':
        return None
    stripped_string = input_string.replace(' ', '')
    items = stripped_string.split(',')
    return items

project_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(f"{project_path}/MAVEN_data/MAVEN_data_format.json", "r", encoding='utf-8') as file:
    json_data = json.load(file)
data_model = json_data["data_model"]

config_file_path = os.path.join(project_path, "download_data", "MAVEN_download_config.ini")
config_data = configparser.ConfigParser()
config_data.optionxform = str
config_data.read(config_file_path, encoding='utf-8')

save_dir = config_data['DEFAULT']['Save_dir']
Server_ind = config_data.getint('Servers','Server_ind')
url_path_0 = config_data['Servers'][Server_ind]
sleep_time = config_data.getint('DEFAULT','sleep_time')
step_time = config_data.getint('DEFAULT','step_time')
timeout = 60

continue_download = config_data['Properties'].getboolean('continue_download')
download_mode = config_data['Properties']['download_mode']
max_threads = config_data.getint('Properties','max_threads')
disable_tqdm_bar = not config_data['Properties'].getboolean('show_tqdm_bar')

start_date = datetime.datetime.strptime(config_data['Settings']['start_date'], '%Y-%m-%d').date()
end_date = datetime.datetime.strptime(config_data['Settings']['end_date'], '%Y-%m-%d').date() 

single_model = config_data['Settings'].get('single_model', [])
muti_models = get_list_from_ini(config_data['Settings']['muti_models'])
single_download = config_data['Settings'].getboolean('single_download')
check_download_file = config_data['Settings'].getboolean('check_download_file')
update_file_version = config_data['Settings'].getboolean('update_file_version')

session = requests.Session()
if Server_ind == 0:  #自建服务器
    vpn_proxy = get_list_from_ini(config_data['VPN_proxy']['USTC_server'])
    user_name = config_data['Servers']['Username']
    password = config_data['Servers']['Password']
    session.auth = (user_name.encode('utf-8'), password.encode('utf-8'))
    models_pass = get_list_from_ini(config_data['Settings']['models_pass'])
    models_skip = ["MAG_ss","MAG_ss1s","MAG_pc1s","MAG_pc","KP"]  #批量下载的时候跳过的模块, 这些模块存在本地自制的体积更小的二进制文件
    step_time = 0
else:       # 外部服务器
    vpn_proxy = get_list_from_ini(config_data['VPN_proxy']['Outer_server'])
    models_pass = get_list_from_ini(config_data['Settings']['models_pass'])
    models_skip = ["MAG_ss_l3","MAG_ss1s_l3","MAG_pc1s_l3","MAG_pc_l3","NGIMS_den_l4","KP_l3","MAG_ss1s_vsc","STATIC_d1_v4d","STATIC_c6_v3d","SWIA_quat","KP_cdf"]  #批量下载的时候跳过的模块, 这些模块为本地自制模块,外部服务器上不存在
print(f"Server: {url_path_0},vpn: {vpn_proxy}")
if vpn_proxy != None:
    vpn_proxy = {
    "http": vpn_proxy[0],
    "https": vpn_proxy[0],
    }
print(f"使用线程数:{max_threads}")
if max_threads == 1:
    string_end = "\r"
else:
    string_end = "\n"
def sleep_local(sleep_time_range):
    for i in range(sleep_time_range):
        print(f"Waiting \033[1;34m {i+1} / {sleep_time_range} \033[0m Seconds\033[K",end="\r",flush=True)
        sleep(1)
    return None
def test_proxies():
    global vpn_proxy
    global url_path_0
    global timeout
    try:
        response = requests.get(url_path_0,proxies=vpn_proxy,timeout=timeout)
        if response.status_code == 200:
            print("\033[1;32m Connection Succeed\033[0m:"+vpn_proxy["http"])
        response.close()
        return True
    except requests.exceptions.RequestException as e:
        print('\033[1;31m Connection Failed \033[0m')
        print(e)
    try:
        response = requests.get("https://www.google.com/",proxies=vpn_proxy,timeout=timeout)
        if response.status_code == 200:
            print("\033[1;32m The Proxy Server Connection Succeed \033[0m:"+vpn_proxy["http"])
        response.close()
        return True
    except requests.exceptions.RequestException as e:
        print('\033[1;31m The Proxy Server Connection Failed \033[0m')
        print(e)
    return False
def search_url(url,file_style):
    global vpn_proxy
    global session
    global timeout
    sleep_local(step_time)
    try:
        print(f"Requesting:{url}...\033[K",flush=True,end='\r')
        response = session.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        while(response.status_code == 429):
            print(f"超出网站请求上限,休眠\033[1;34m{sleep_time}\033[0m秒")
            sleep_local(sleep_time)
            print(f"Requesting:{url}...\033[K",flush=True,end='\r')
            response = session.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        if response.status_code == 200:
            html_content = response.text
            soup = BeautifulSoup(html_content, 'html.parser')
            file_urls = []
            file_elements = soup.find_all('a', href=True)  # 找到所有带有href属性的<a>元
            for element in file_elements:
                file_url = element['href']
                file_urls.append(file_url)
            urls=[string for string in file_urls if re.match(file_style, string)]
            response.close()
            if urls == None:
                return response.status_code,False,0
            return response.status_code,True,urls
    except requests.exceptions.RequestException as e:
        print(f"url error: {e},sleep \033[1;34m{sleep_time}\033[0m Seconds")
        sleep_local(sleep_time)
        return "error",False,0
    return "error",False,0
def download_unit_convert(total_bits):
    size_units = ["b", "Kb", "Mb", "Gb", "Tb", "Pb"]
    unit_idx = min(len(size_units) - 1, max(0, int(math.log(total_bits, 1024))))
    divisor = 1024 ** unit_idx
    size_value = round(total_bits / divisor,ndigits=2)
    size_unit = size_units[unit_idx]
    return f"{size_value} {size_unit}"
def requests_download(url, save_path):
    global vpn_proxy, session, timeout, disable_tqdm_bar
    sleep_local(step_time)
    temp_save_path = save_path + ".pydownload"
    if os.path.exists(temp_save_path):
            os.remove(temp_save_path) # 清理未上次完成的残余文件
    
    try:
        print(f"\033[1;32mRequesting\033[0m: {url}...\033[K", flush=True, end=string_end)

        response = session.get(url, stream=True, proxies=vpn_proxy, timeout=timeout)

        while response.status_code == 429:
            response.close()
            print(f"超出网站请求上限,休眠\033[1;34m{sleep_time}\033[0m秒")
            sleep_local(sleep_time)
            response = session.get(url, stream=True, proxies=vpn_proxy, timeout=timeout)

        with response:
            if response.status_code == 200:
                total_size = int(response.headers.get("content-length", 0))
                block_size = 1024
                progress_bar = tqdm(total=total_size, unit="B", unit_scale=True, leave=False, 
                                    colour='green', dynamic_ncols=True, disable=disable_tqdm_bar)
                time_start = time.time()

                if disable_tqdm_bar:
                    print(f"\033[1;32mLoading from\033[0m: {url}...\033[K", flush=True, end=string_end)

                dir_save_path = os.path.dirname(save_path)
                if dir_save_path and not os.path.exists(dir_save_path):
                    os.makedirs(dir_save_path)

                with open(temp_save_path, "wb") as file:
                    for data in response.iter_content(block_size):
                        if data:
                            file.write(data)
                            progress_bar.update(len(data))
                
                progress_bar.close()

                os.rename(temp_save_path, save_path)

                elapsed = time.time() - time_start
                speed = total_size / elapsed if elapsed > 0 else 0
                loading_data = (download_unit_convert(total_size), f"{round(elapsed, 2)} s", download_unit_convert(speed)+'/s')

                return response.status_code, True, loading_data
                
    except requests.exceptions.RequestException as e:
        print(f"url error: {e}, sleep \033[1;34m{sleep_time}\033[0m Seconds")
        if os.path.exists(temp_save_path):
            os.remove(temp_save_path) # 清理未完成的残余文件
        sleep_local(sleep_time)
        return "error", False, ("error", "error", "error")
        
    return "error", False, ("error", "error", "error")
def idm_add_download_links(url,save_path,filename):
    global step_time
    if not os.path.exists(save_path):
        os.makedirs(save_path)
    # command = f'"{config_data["Properties"]["IDM_program_path"]}" /a /d "{url}" /p "{save_path}" /f "{filename}"'
    command = [
        config_data["Properties"]["IDM_program_path"],
        "/a" ,
        "/d", url,
        "/p", save_path,
        "/f", filename,
        ]
    # os.system(command)
    result = subprocess.run(command, check=False, capture_output=True, text=True, encoding='utf-8')
    # print(command)
    return result.returncode == 0
def aria2_download(url, save_path):
    global vpn_proxy, timeout, disable_tqdm_bar, step_time, sleep_time
    
    sleep_local(step_time)

    # 路径与临时文件处理
    temp_save_path = save_path + ".aria2download"
    dir_save_path = os.path.dirname(temp_save_path)
    file_name = os.path.basename(temp_save_path)
    if dir_save_path and not os.path.exists(dir_save_path):
        os.makedirs(dir_save_path)

    # 构建命令
    cmd = [
        config_data["Properties"]["Aria2c_program_path"],
        url,
        "--dir", dir_save_path,
        "--out", file_name,
        "--continue=true",              # 开启断点续传
        "--max-connection-per-server", str(max_threads),
        "--split", str(max_threads),
        "--connect-timeout", str(timeout),
        "--timeout", str(timeout),

        "--max-tries", "5",             # 设置单次进程运行时的最大重试次数
        "--retry-wait", "10",           # 每次重试之间等待 10 秒

        "--disk-cache", "64M",          # RAID5 保护：内存缓存
        "--file-allocation", "falloc",  # RAID5 保护：预分配空间
        "--console-log-level=warn",
        "--summary-interval=0",
    ]
    # 代理处理
    if vpn_proxy and 'http' in vpn_proxy:
        cmd.append(f"--all-proxy={vpn_proxy['http']}")

    # 如果需要静默模式
    if disable_tqdm_bar:
        cmd.append("--quiet=true")

    try:
        print(f"\033[1;32mAria2 Loading\033[0m: {url}...\033[K", flush=True, end='\r')
        time_start = time.time()

        # 执行下载
        process = subprocess.run(cmd, capture_output=True, text=True)

        if process.returncode == 0:
            if os.path.exists(temp_save_path):
                if os.path.exists(save_path):# 如果最终目标已存在，先清理
                    os.remove(save_path)
                os.rename(temp_save_path, save_path)

                total_size = os.path.getsize(save_path)
                elapsed = time.time() - time_start
                speed = total_size / elapsed if elapsed > 0 else 0
                
                return 200, True, (
                    download_unit_convert(total_size), 
                    f"{round(elapsed, 2)} s", 
                    f"{download_unit_convert(speed)}/s"
                )
        else:
            error_output = process.stdout + process.stderr
            print(f"Aria2 Failed (Code {process.returncode}): {error_output}")

    except Exception as e:
        print(f"Aria2 execution failed: {e}")

    return "error", False, ("error", "error", "error")
def download_model(model):
    global Server_ind
    global url_path_0
    global save_dir
    global json_data
    data_model = json_data["data_model"]
    model_key = {}
    for key, value in data_model.items():
        model_key[key] = value[:3]
    model_url0,filename,pathname=model_key[model]
    model_url = model_url0[Server_ind]
    if model_url == "None":
        return None,None,None
    url = url_path_0+model_url
    save_path =  save_dir+pathname
    return [url,save_path,filename]
def find_downloaded_file(file_names, element):
    if file_names is None:
        print("第一次下载")
        return False
    for file_name in file_names:
        if element in file_name:
            return True
    return False
def read_last_line_large_file(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        f.seek(0, 2)  # 移动到文件末尾
        file_size = f.tell()
        block = 10240  # 每次读取的块大小
        last_line = ''
        # 从文件末尾开始逐块向前读取
        for pos in range(file_size, 0, -block):
            if pos < block:
                f.seek(0)
            else:
                f.seek(pos - block)
            data = f.read(min(block, pos))
            if '\n' in data:
                last_line = data.splitlines()[-1]
                break
        else:  # 如果文件没有换行符，整个文件就是最后一行
            f.seek(0)
            last_line = f.read()
    return last_line
def file_check(file_names,save_path,model):
        counter = 0
        if model == 'cdf':
            from cdflib import cdfread 
            for f in file_names:
                try :
                    cdfread.CDF(save_path+f)
                    # print(f,'True')
                    continue
                except Exception as e:
                    print(e)
                os.remove(os.path.join(save_path,f))
                print(f,"False")
                counter+=1
            return counter
        if model == 'kp':
            for f in file_names:
                last_line = read_last_line_large_file(save_path+f)
                # file=open(save_path+f,'r')
                # lines = file.readlines()
                # last_line = lines[-1]
                bool_1 = (len(last_line) >= 3360)
                bool_2 = (int(last_line[14:16]) >= 59)
                if bool_1 & bool_2:
                    # print(f,'True')
                    bool_1 = True
                else:
                    os.remove(os.path.join(save_path,f))
                    print(f,"False")
                    counter+=1
            return counter
def get_element_from_filename(filename): # 取得文件名对应的版本等信息
    try:
        v_data = int(re.findall(r"_v\d{2}", filename)[0][2:4])
    except:
        v_data = 0
    try:
        r_data = int(re.findall(r"_r\d{2}", filename)[0][2:4])
    except:
        r_data = 0 
    date_str = re.findall(r"\d{8}", filename)[0]
    return (date_str,v_data,r_data,filename)
def search_downloaded_files(save_path,file_style):
    filename_data =[]
    yyyy = os.listdir(save_path)
    for iy in yyyy:
        mm   = os.listdir(save_path+iy+"/")
        for im in mm:
            files = os.listdir(save_path+iy+"/"+im+"/")
            filepaths = [iy+"/"+im+"/"+file for file in files if re.match(file_style,file)]
            for filepath in filepaths:
                filename_data.append(get_element_from_filename(filepath))
    return filename_data
def month_delta(datetime_current): # 向前前进到下个月月初
    current_month = datetime_current.month
    current_year = datetime_current.year
    current_month += 1
    if current_month > 12:
        current_month = 1
        current_year += 1
    return  datetime.date(current_year, current_month, 1)
def download_from_head(head,num_links_added,num_links):
    model,date,url_path,filename,save_path,v_new,r_new = head
    if os.path.exists(save_path+filename):
        return f"\033[1;32m{model} {date} {filename} already exists, skip downloading.\033[0m {num_links_added}/{num_links}"
    if download_mode == 'win.idm':
        cmd_status_code=idm_add_download_links(url_path,save_path,filename)
        if cmd_status_code:
            # print(f'\033[1;32mIDM link added {num_links_added}/{num_links}\033[0m',end='\r')
            return f'\033[1;32mIDM link added {num_links_added}/{num_links}\033[0m'
    elif download_mode == "Aria2c":
        url_status_code,logic,progress_data = aria2_download(url_path,save_path+filename)
        time_now = datetime.datetime.now()
    elif download_mode == 'python.request':
        url_status_code,logic,progress_data = requests_download(url_path,save_path+filename)
        time_now = datetime.datetime.now()
    if logic:
        download_speed = progress_data[2]
        download_elapsed = progress_data[1]
        download_size = progress_data[0]
        return f'{model}: \033[1;34m{date} v: {v_new} r:{r_new} \033[0m '+f'Status: \033[0;32m{logic}\033[0m ' +f'Responses: \033[0;32m{url_status_code}\033[0m '+f'Time: \033[1;34m{time_now.strftime("%Y-%m-%d %H:%M:%S")}\033[0m '+f'Time spend: \033[1;34m{download_elapsed}\033[0m '+f'Total size: \033[1;34m{download_size}\033[0m '+f'Speed: \033[1;34m{download_speed}\033[0m {num_links_added}/{num_links}'
    else:
        return f'{model}: \033[1;34m{date} v: {v_new} r:{r_new} \033[0m ' +f'Status: \033[0;31m{logic}\033[0m ' +f'Responses: \033[0;32m{url_status_code}\033[0m '+f'Time: \033[1;34m{time_now.strftime("%Y-%m-%d %H:%M:%S")}\033[0m  {num_links_added}/{num_links}'

if __name__ == '__main__':
    os.makedirs(save_dir+"lists/", exist_ok=True)
    if vpn_proxy == None:
        print("\033[1;32m No VPN \033[0m")
    else:
        logic = test_proxies()
        if(logic == False):
            print('\033[1;31m Connection Failed, Exit Program \033[0m')
            exit(0)

    models=[]
    if single_download:
        models = [single_model]
    elif muti_models == []:
        for item in data_model.keys():
            if item in models_pass:
                continue
            if item in models_skip:
                continue
            models.append(item)
    else:
        models = muti_models

    # 导入上次保存的链接表
    download_heads_file = f"{project_path}/download_data/download_heads.json"
    if continue_download and os.path.exists(download_heads_file):
        print("\033[1;32m 继续之前的下载 \033[0m")
        with open(download_heads_file, 'r', encoding='utf-8') as f:
            download_heads = json.load(f)
    else:
        download_heads = []
        continue_download = False
    # 遍历网站,取得所有文件的下载链接
    time_start = datetime.datetime.now()
    print(f"\033[1;32mStart get all download link from {start_date} to {end_date}\033[0m")
    for model in models:
        if continue_download:
            break
        current_date = start_date
        url_path,save_path,file_style = download_model(model)
        if url_path is None:
            print(f"\033[1;31m{model} is not available on this server\033[0m")
            continue
        if not os.path.exists(save_path):                   #判断是否存在文件夹如果不存在则创建为文件夹
            os.makedirs(save_path)
        file_names = search_downloaded_files(save_path,file_style)

        all_date = [f[1] for f in file_names]

        # 取得需要查询的所有日期参数
        all_planed_file_dates = []
        if update_file_version:
            while current_date <= end_date:
                date=str(current_date.strftime("%Y%m%d"))
                all_planed_file_dates.append(date)
                current_date+=datetime.timedelta(days=1)
        else: 
            while current_date <= end_date:
                date=str(current_date.strftime("%Y%m%d"))
                if date in all_date:
                    continue
                all_planed_file_dates.append(date)
                current_date+=datetime.timedelta(days=1)
                
        if all_planed_file_dates == []:
            print(f"\033[1;32m{model} 计划内已经全部下载\033[0m")
            continue
        else:
            print(f"\033[1;32m{model} 计划查找{len(all_planed_file_dates)}个日期\033[0m")
        # 日期参数对应的年月集合
        all_yyyymm_set={d[:4] + "/" + d[4:6] + "/" for d in all_planed_file_dates}
        all_years_set = {d[:5] for d in all_yyyymm_set}
        # 取得服务器的所有年
        urls_status_code,bool_urls,urls_years = search_url(url_path,r'\d{4}/')
        if not bool_urls:
            print("\033[1;31m连接失败\033[0m")
            continue
        years_need_to_access = set(urls_years) & all_years_set
        # 取得服务器的所有月
        server_yyyymm = []
        for yyyy in years_need_to_access:
            urls_status_code,bool_urls,urls_months = search_url(url_path+yyyy,r'\d{2}/')
            if not bool_urls:
                continue
            server_yyyymm.extend([yyyy+m for m in urls_months])
        yyyymm_need_to_access = set(server_yyyymm) & all_yyyymm_set

        download_heads_model = []
        # 取得服务器的所有日
        for yyyymm in yyyymm_need_to_access:
            urls_status_code,bool_urls,urls = search_url(url_path+yyyymm,file_style)
            if not bool_urls:
                continue
            if not os.path.exists(save_path+yyyymm):
                os.makedirs(save_path+yyyymm)
            if len(urls) != 0:
                print(f'Found \033[0;32m {len(urls)} \033[1;34m{model}\033[0m files in '+yyyymm+'\033[0m\033[K',end='\n')
            for url in urls:
                filename = str(url)
                date_str,v_data,r_data, _ = get_element_from_filename(filename)
                if date_str in all_planed_file_dates:
                    download_heads_model.append((model,date_str,url_path+yyyymm+filename,filename,save_path+yyyymm,v_data,r_data))
        print(f"\033[1;32m{model} 完成查找{len(download_heads_model)}个日期\033[0m")
        download_heads.extend(download_heads_model)
            
    time_now = datetime.datetime.now()
    print(f"\033[1;32m{len(download_heads)}\033[0m links loaded, \033[1;34mTotal time spent: {time_now-time_start}\033[0m")

    # 如果continue_download为false,将download_heads保存为json文件:
    if not continue_download:
        with open(download_heads_file, 'w', encoding='utf-8') as f:
            json.dump(download_heads, f, ensure_ascii=False, indent=4)
    # 清理已经存在的文件
    skip_num = 0
    download_heads_cleaned = []
    print("\033[1;33m正在校验本地文件并同步版本状态...\033[0m")
    
    for head in download_heads:
        model, date, url_full, filename, save_path, new_v, new_r = head
        target_file_path = os.path.join(save_path, filename)

        if os.path.exists(target_file_path):# 目标文件已经存在 (且版本完全一致)
            skip_num += 1
            continue

        # 情况 B: 目标文件不存在，或者需要更新版本
        # 1. 扫描当前目录下同日期、同 model 的旧文件
        if os.path.exists(save_path):
            _, _, file_style = download_model(model)
            try:
                # 获取该目录下所有符合命名规则的文件名
                existing_files = [f for f in os.listdir(save_path) if re.match(file_style, f)]
                
                is_newer_than_local = True
                for old_f in existing_files:
                    try:
                        old_date, old_v, old_r, _ = get_element_from_filename(old_f)
                        
                        # 仅当日期匹配时进行版本比对
                        if old_date == date:
                            # 核心逻辑：元组比对 (v, r)
                            if (old_v, old_r) < (new_v, new_r):
                                os.remove(os.path.join(save_path, old_f))
                                print(f"检测到新版本，已删除旧版: \033[1;31m{old_f}\033[0m")
                            elif (old_v, old_r) > (new_v, new_r):
                                is_newer_than_local = False
                                print(f"本地版本更高({old_f})，跳过服务器低版本: {filename}")
                    except:
                        continue
                
                # 2. 如果服务器文件是更新的（或本地无同日期文件），加入下载列表
                if is_newer_than_local:
                    download_heads_cleaned.append(head)
                else:
                    skip_num += 1
            except Exception as e:
                print(f"处理目录 {save_path} 时出错: {e}")
                download_heads_cleaned.append(head)
        else:
            # 目录不存在，直接加入下载列表
            download_heads_cleaned.append(head)
    if skip_num > 0:
        print(f"\033[1;32m{skip_num}\033[0m files already exist, skip downloading.", flush=True,end='\n')
    num_links = len(download_heads_cleaned)
    num_links_added = 0

    # 启动下载记录
    io_download_log = open('download_data/download.log', 'w', encoding='utf-8')
    # 多线程下载
    print(f"download_mode = {download_mode}")
    if download_mode == "python.request" or download_mode == "win.idm":
        print(f"\033[1;32mStart downloading with {download_mode} using {max_threads} threads...\033[0m")
        with ThreadPoolExecutor(max_workers=max_threads) as executor:
            future_to_task_info = {
                executor.submit(download_from_head, head, i + 1, num_links): (head, i + 1)
                for i, head in enumerate(download_heads_cleaned)
                }
            print("\n--- 正在等待下载任务完成，并实时打印结果... ---\n")
            for future in as_completed(future_to_task_info):
                original_head, task_id = future_to_task_info[future]
                try:
                    # 获取任务函数的实际返回值
                    result_string = future.result()
                    result_string_0 = result_string
                except Exception as exc:
                    result_string_0 = f"\033[1;31m错误\033[0m 任务:{task_id} (处理 '{original_head}') 执行出错: {exc}"
                print(result_string_0, flush=True,end='\n') # 实时打印完成结果
                io_download_log.write(result_string_0+'\n')
                io_download_log.flush()
    elif download_mode == "Aria2c":
        for i, head in enumerate(download_heads_cleaned):
            try:
                result_string = download_from_head(head, i+1, num_links)
                result_string_0 = result_string
            except Exception as exc:
                result_string_0 = f"\033[1;31m错误\033[0m '{head[2]}' 出错: {exc}"
            print(result_string_0, flush=True,end='\n') # 实时打印完成结果
            io_download_log.write(result_string_0+'\n')
            io_download_log.flush()

    io_download_log.close()

    import runpy
    runpy.run_path(f"{project_path}/download_data/get_download_files.py")  # run get_download_files.py, update filename_list.txt