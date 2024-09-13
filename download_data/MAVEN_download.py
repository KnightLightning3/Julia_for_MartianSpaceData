# Download data from the LASP server. It is recommended to configure vpn to the US node. If not configured, you need to set vpn_proxy=None.
import datetime
import os
import re
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm
import re
from time import sleep
import json
import configparser

def get_list_from_ini(input_string):
    if input_string == 'Null':
        return []
    if input_string == 'None':
        return None
    stripped_string = input_string.replace(' ', '')
    items = stripped_string.split(',')
    return items

data_format_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
config_file_path = os.path.join(data_format_path, "download_data", "MAVEN_download_config.ini")
config_data = configparser.ConfigParser()
config_data.optionxform = str
config_data.read(config_file_path,encoding='utf-8')

url_path_0 = config_data['DEFAULT']['MAVEN_Server_url']
sleep_time = config_data.getint('DEFAULT','sleep_time')
step_time = config_data.getint('DEFAULT','step_time')
vpn_proxy1 = get_list_from_ini(config_data['VPN_proxy']['MAVEN_server'])
if vpn_proxy1 == None:
    vpn_proxy = None
else:
    vpn_proxy = {
    "http": vpn_proxy1[0],
    "https": vpn_proxy1[0],
    }

start_date = datetime.datetime.strptime(config_data['Settings']['start_date'], '%Y-%m-%d').date()
end_date = datetime.datetime.strptime(config_data['Settings']['end_date'], '%Y-%m-%d').date() 

single_model = config_data['Settings'].get('single_model', [])
muti_models = get_list_from_ini(config_data['Settings']['muti_models'])
models_pass = get_list_from_ini(config_data['Settings']['models_pass_MAVEN_server'])
single_download = config_data['Settings'].getboolean('single_download')
check_download_file = config_data['Settings'].getboolean('check_download_file')

with open(f"{data_format_path}/MAVEN_data/MAVEN_data_format.json", "r", encoding='utf-8') as file:
    json_data = json.load(file)
data_model = json_data["data_model"]

timeout = None
step_time= 5 #每个请求之间间隔的时间，以防被ban

models_skip = ["MAG_ss_l3","MAG_ss1s_l3","MAG_pc1s_l3","MAG_pc_l3","NGIMS_den_l4","KP_l3"]  #批量下载的时候跳过的模块，这些模块为本地自制模块,LASP服务器上不存在

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
    global timeout
    for i in range(step_time):
        print(f"Waiting {i+1} / {step_time} Seconds",end="\r")
        sleep(1)
    try:
        response = requests.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        while(response.status_code == 429):
            for i in range(sleep_time):
                print(f"超出网站请求上限,休眠{sleep_time}秒")
                print(f"Waiting {i+1} / {sleep_time} Seconds",end="\r")
                sleep(1)
            response = requests.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
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
        for i in range(sleep_time):
            print(f"url error: {e},sleep {sleep_time}s")
            print(f"Waiting {i+1} / {sleep_time} Seconds",end="\r")
            sleep(1)
        return response.status_code,False,0
    return response.status_code,False,0
def requests_download(url,save_path):
    global vpn_proxy
    global timeout
    for i in range(step_time):
        print(f"Waiting {i+1} / {step_time} Seconds",end="\r")
        sleep(1)
    try:
        response = requests.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        while(response.status_code == 429):
            for i in range(sleep_time):
                print(f"超出网站请求上限,休眠{sleep_time}秒")
                print(f"Waiting {i+1} / {sleep_time} Seconds",end="\r")
                sleep(1)
            response = requests.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        if response.status_code == 200:
            total_size = int(response.headers.get("content-length", 0))
            block_size = 1024
            progress_bar = tqdm(total=total_size, unit="B", unit_scale=True)
            buffer = bytearray()  # 创建字节缓冲区
            for data in response.iter_content(block_size):
                progress_bar.update(len(data))
                buffer.extend(data)  # 将下载的数据添加到缓冲区
            progress_bar.close()
            
            # 如果路径不存在,创建路径
            if not os.path.exists(os.path.dirname(save_path)):
                os.makedirs(save_path)
                print(f"创建路径:{save_path}")
            # 将缓冲区中的数据写入文件
            with open(save_path, "wb") as file:
                file.write(buffer)
            return response.status_code,True
        response.close()
    except requests.exceptions.RequestException as e:
        for i in range(sleep_time):
            print(f"url error: {e},sleep {sleep_time}s")
            print(f"Waiting {i+1} / {sleep_time} Seconds",end="\r")
            sleep(1)
        return response.status_code,False
    return response.status_code,False
def download_model(model):
    global url_path_0
    save_dir = json_data["save_path"]
    data_model = json_data["data_model"]
    model_key = {}
    for key, value in data_model.items():
        model_key[key] = value[:3]

    model_url,filename,pathname=model_key[model]
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
def search_downloaded_files(save_path,file_style):
    filenames =[]
    yyyy = os.listdir(save_path)
    for iy in yyyy:
        mm   = os.listdir(save_path+iy+"/")
        for im in mm:
            files = os.listdir(save_path+iy+"/"+im+"/")
            filepaths = [iy+"/"+im+"/"+file for file in files if re.match(file_style,file)]
            for filepath in filepaths:
                filenames.append(filepath)
    return filenames
if __name__ == '__main__':
    if check_download_file:
        for model in json_data["data_model"].keys():
            url_path,save_path,file_style = download_model(model)
            file_names = search_downloaded_files(save_path,file_style)
            if file_names is None:
                continue
            with open(json_data["save_path"]+"lists/"+model+'_list.txt', 'w', encoding='utf-8') as file:
                for item in file_names:
                    file.write(str(item) + '\n')
        import runpy
        runpy.run_path('download_data/get_download_files.py')  # run get_download_files.py, update filename_list.txt    
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
        models=muti_models

    for model in models:
        nums_downloaded = 0
        nums_failed = 0
        current_date = start_date
        url_path,save_path,file_style = download_model(model)
        if not os.path.exists(save_path):                   #判断是否存在文件夹如果不存在则创建为文件夹
            os.makedirs(save_path)
        file_names = search_downloaded_files(save_path,file_style)
        if not (file_names is None):
            with open(json_data["save_path"]+"lists/"+model+'_list.txt', 'w', encoding='utf-8') as file:
                for item in file_names:
                    file.write(str(item) + '\n') 
        #get all url:
        while current_date <= end_date:
            date=str(current_date.strftime("%Y%m%d"))
            
            if find_downloaded_file(file_names, date):
                print(date,model,'\033[1;32mThe File Already Exists\033[0m')
                current_date+=datetime.timedelta(days=1)
                continue
            year      = current_date.year
            month     = current_date.month
            yyyymm    = str(current_date.strftime("%Y/%m/"))
            urls_status_code,bool_urls,urls = search_url(url_path+yyyymm,file_style)
            if bool_urls:
                print(f'\033[0;32m {len(urls)} {model} files in '+yyyymm+'\033[0m')
                for url in urls:
                    filename = str(url)
                    date=re.findall(r"\d{8}", filename)[0]
                    if start_date.strftime("%Y%m%d") > date > end_date.strftime("%Y%m%d"):  #Skip the part that is out of date
                        continue
                    if find_downloaded_file(file_names, date):
                        print(date,model,'\033[1;32mThe File Already Exists\033[0m')
                        current_date += datetime.timedelta(days=1)
                        continue
                    if not os.path.exists(save_path+yyyymm):
                        os.makedirs(save_path+yyyymm)
                    url_status_code,logic = requests_download(url_path+yyyymm+filename,save_path+yyyymm+filename)
                    time_now = datetime.datetime.now()
                    if logic:
                        print(f'{model}_{date} Status: \033[0;32m{logic}\033[0m, Responses: \033[0;32m{url_status_code}\033[0m Time: \033[1;34m{time_now.strftime("%Y-%m-%d %H:%M:%S")}\033[0m\n')
                        nums_downloaded = nums_downloaded+1
                    else:
                        print(f'{model}_{date} Status: \033[0;31m{logic}\033[0m, Responses: \033[0;32m{url_status_code}\033[0m Time: \033[1;34m{time_now.strftime("%Y-%m-%d %H:%M:%S")}\033[0m\n')
                        nums_failed = nums_failed+1
            month+=1
            if month == 13:
                month=1
                year+=1
            current_date = datetime.date(year, month, 1)
        file_names = search_downloaded_files(save_path,file_style)
        with open(json_data["save_path"]+"lists/"+model+'_list.txt', 'w', encoding='utf-8') as file:
            for item in file_names:
                file.write(str(item) + '\n')
        with open("download_data/download.log","a", encoding='utf-8') as download_log:
            download_log.write(f'[{datetime.datetime.now()}]  {nums_downloaded} Files Downloaded, {nums_failed} Files Failed [{model}] [MAVEN server]'+"\n")
    
    import runpy
    runpy.run_path('download_data/get_download_files.py')  # run get_download_files.py, update filename_list.txt
    exit(0)
#文件检查
    # for model in models:
    #     if model in ["MAG_ss1s","MAG_pc1s","MAG_ss","MAG_pc","SWEA_spec","LPW_mrgscpot"]:
    #         continue
    #     if model in ["SWEA_pad_arc","SWEA_pad_svy","KP"]:
    #         continue
    #     url_path,save_path,file_style = download_model(model)
    #     file_names = os.listdir(save_path)
    #     if model == 'KP':
    #         counter = file_check(file_names,save_path,'kp')
    #     else:
    #         counter = file_check(file_names,save_path,'cdf')

    #     file_names = os.listdir(save_path)
    #     with open("E:/MAVEN/lists/"+model+'_list.txt', 'w') as file:
    #         for item in file_names:
    #             file.write(str(item) + '\n')
    #     with open("download.log","a") as file:
    #         file.write( f"{model}中{counter}个文件被删除"+"\n" )
    #         print( f"{model}中{counter}个文件被删除"+"\n" )
    # exit(0)