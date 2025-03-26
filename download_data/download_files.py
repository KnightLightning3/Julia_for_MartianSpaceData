# 下载任意目录下的文件,可以遍历深度
import datetime
import os
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm
import re
from time import sleep
import json
import configparser
from pathlib import Path
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
timeout = None
Server_ind = 1
session = requests.Session()
if Server_ind == 0:  #自建服务器
    vpn_proxy = get_list_from_ini(config_data['VPN_proxy']['USTC_server'])
    user_name = config_data['Servers']['Username']
    password = config_data['Servers']['Password']
    session.auth = (user_name.encode('utf-8'), password.encode('utf-8'))
    step_time = 0
else:       # 外部服务器
    vpn_proxy = get_list_from_ini(config_data['VPN_proxy']['Outer_server'])
print(f"vpn: {vpn_proxy}")
if vpn_proxy != None:
    vpn_proxy = {
    "http": vpn_proxy[0],
    "https": vpn_proxy[0],
    }

# 设置区
url_path_root = "https://naif.jpl.nasa.gov/pub/naif/MAVEN/kernels/ck/"
file_style = "^mvn"
save_path = r"C:\data\misc\spice\naif\MAVEN\kernels\ck/"
max_depth = 1
# session = requests.Session()

def sleep_local(sleep_time_range):
    for i in range(sleep_time_range):
        print(f"Waiting \033[1;34m {i+1} / {sleep_time_range} \033[0m Seconds\033[K",end="\r")
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
        # print(f"Requesting:{url}...\033[K",end='\r')
        response = session.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        while(response.status_code == 429):
            print(f"超出网站请求上限,休眠\033[1;34m{sleep_time}\033[0m秒")
            sleep_local(sleep_time)
            print(f"Requesting:{url}...\033[K",end='\r')
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
        return response.status_code,False,0
    return response.status_code,False,0
def requests_download(url,save_path):
    global vpn_proxy
    global session
    global timeout
    sleep_local(step_time)
    try:
        print(f"\033[1;32mRequesting\033[0m: {url}...\033[K")
        response = session.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        while(response.status_code == 429):
            print(f"超出网站请求上限,休眠\033[1;34m{sleep_time}\033[0m秒")
            sleep_local(sleep_time)
            print(f"Requesting:{url}...\033[K")
            response = session.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        if response.status_code == 200:
            total_size = int(response.headers.get("content-length", 0))
            block_size = 1024
            progress_bar = tqdm(total=total_size, unit="B", unit_scale=True, leave=False,colour = 'green',dynamic_ncols=True)
            buffer = bytearray()  # 创建字节缓冲区
            for data in response.iter_content(block_size):
                progress_bar.update(len(data))
                buffer.extend(data)  # 将下载的数据添加到缓冲区
            progress_bar.close()
            progress_bar_data = progress_bar.format_dict
            # 如果路径不存在,创建路径
            if not os.path.exists(os.path.dirname(save_path)):
                os.makedirs(os.path.dirname(save_path))
            # 将缓冲区中的数据写入文件
            with open(save_path, "wb") as file:
                print(f"\033[F\033[FWriting into: {save_path}",end='\r')
                file.write(buffer)
            return response.status_code,True,progress_bar_data
        response.close()
    except requests.exceptions.RequestException as e:
        print(f"url error: {e},sleep \033[1;34m{sleep_time}\033[0m Seconds")
        sleep_local(sleep_time)
        return response.status_code,False,None
    return response.status_code,False,None
def find_downloaded_file(file_names, element):
    if file_names is None:
        print("第一次下载")
        return False
    for file_name in file_names:
        if element in file_name:
            return True
    return False
def print_download_statue(url_status_code,logic,progress_data,filename):
    time_now = datetime.datetime.now()
    if logic:
        try:
            download_speed = str(round(progress_data["rate"]/1024/1024,2))
            download_time = str(round(progress_data["elapsed"],2))
        except:
            download_speed = "ERROR"
            download_time = "ERROR"
        print(f'\033[1;34m{filename}\033[0m ' +
                f'Status: \033[0;32m{logic}\033[0m ' +
                f'Responses: \033[0;32m{url_status_code}\033[0m '+
                f'Time: \033[1;34m{time_now.strftime("%Y-%m-%d %H:%M:%S")}\033[0m '+
                f'Time spend: \033[1;34m{download_time}\033[0m s '+
                f'Speed: \033[1;34m{download_speed}\033[0m Mb/s',end='\n\n')
    else:
        print(f'\033[1;34m{filename}\033[0m ' +
                f'Status: \033[0;31m{logic}\033[0m ' +
                f'Responses: \033[0;32m{url_status_code}\033[0m '+
                f'Time: \033[1;34m{time_now.strftime("%Y-%m-%d %H:%M:%S")}\033[0m ',end='\n\n')
def add_urls(urls_path,urls):
    urls_return = []
    for i in urls:
        if "?" in i:
            continue
        if i[0] == "/":
            continue
        urls_return.append(url_path + i)
    return urls_return
if __name__ == '__main__':
    if vpn_proxy == None:
        print("\033[1;32m No VPN \033[0m")
    else:
        logic = test_proxies()
        if(logic == False):
            print('\033[1;31m Connection Failed, Exit Program \033[0m')
            exit(0)
    model = []
    
    nums_downloaded = 0
    nums_failed = 0

    # 递归获取urls
    url_paths = [url_path_root]
    depth = max_depth
    while depth > 0:
        if depth != 0:
            file_style_url = ""
        else:
            file_style_url = file_style
        url_paths0 = []
        print("当前深度:",depth)
        for url_path in tqdm(url_paths):
            urls_status_code,bool_urls,urls0 = search_url(url_path,file_style)
            if bool_urls:
                url_paths0.extend(add_urls(url_path,urls0))
            else:
                print(urls_status_code)
                break
        depth = depth - 1
        url_paths = url_paths0
    print("URLs获取完毕,共计",len(url_paths),"个URLs")
    #下载内容
    if not os.path.exists(save_path):                   #判断是否存在文件夹如果不存在则创建为文件夹
        os.makedirs(save_path)
    for url in url_paths:
        path = Path(url)
        filename = str(Path(*path.parts[-max_depth:]))
        filename = filename.replace("\\", "/")
        if os.path.exists(save_path+filename):
            print(f"文件{filename}已存在")
            continue
        url_status_code,logic,progress_data = requests_download(url,save_path+filename)
        print_download_statue(url_status_code,logic,progress_data,filename)
        if logic:
            nums_downloaded = nums_downloaded+1
        else:
            nums_failed = nums_failed+1