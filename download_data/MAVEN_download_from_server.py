#从自建服务器下载数据,校内访问不需要vpn，校外访问需要配置相应的vpn端口. 服务器不一定在运行
import datetime
import os
import re
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm
import re
from time import sleep
import json

url_path_0='http://222.195.76.155:8000/MAVEN/'   #MAVEN服务器数据下载地址
user_name = '待定用户007'
password = '待定用户007的密码是待定用户007'
start_date   = datetime.date(2015, 10, 1)        #下载数据的起始日期
end_date     = datetime.date(2015, 10, 30)       #下载数据的终止日期，  由于算法本身，一次会下载一个月的量
sleep_time = 60
step_time= 0 #每个请求之间间隔的时间，以防被ban
models_pass = ["MAG_ss","MAG_ss1s","MAG_pc1s","MAG_pc"]  #批量下载的时候跳过的模块，MAG数据的l3为占用更小的二进制格式，所以不需要下载l2的数据
single_model= "LPW_lpiv"
muti_models = []                                        #填入想要批量下载的仪器模块，如果为空，则下载所有模块
single_download = True                                 #为true时下载single_model，为false时下载muti_models
vpn_proxy = None                                        #vpn设置,校外访问时可以忽略

session = requests.Session()
session.auth = (user_name.encode('utf-8'), password.encode('utf-8'))
timeout = None
data_format_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

with open(f"{data_format_path}\MAVEN_data\MAVEN_data_format.json", "r") as file:
    json_data = json.load(file)
data_model = json_data["data_model"]

def search_url(url,filestyle):
    global vpn_proxy
    global session
    global timeout
    sleep(step_time)
    try:
        response = session.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        while(response.status_code == 429):
            print(f"超出网站请求上限,休眠{sleep_time}秒")
            sleep(sleep_time)
            response = session.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        if response.status_code == 200:
            html_content = response.text

            soup = BeautifulSoup(html_content, 'html.parser')

            file_urls = []
            file_elements = soup.find_all('a', href=True)  # 找到所有带有href属性的<a>元

            for element in file_elements:
                file_url = element['href']
                file_urls.append(file_url)
            urls=[string for string in file_urls if re.match(filestyle, string)]
            response.close()
            if urls == None:
                return response.status_code,False,0
            return response.status_code,True,urls
    except requests.exceptions.RequestException as e:
        print(f"url error: {e},sleep {sleep_time}s")
        sleep(sleep_time)
        return response.status_code,False,0
    return response.status_code,False,0
def requests_download(url,save_path):
    global vpn_proxy
    global session
    global timeout
    sleep(step_time)
    try:
        response = session.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
        while(response.status_code == 429):
            print(f"超出网站请求上限,休眠{sleep_time}秒")
            sleep(sleep_time)
            response = session.get(url, stream=True,proxies=vpn_proxy,timeout=timeout)
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
        print(f"url error: {e},sleep {sleep_time}s")
        sleep(sleep_time)
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
    url = url_path_0+pathname
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
def search_downloaded_files(save_path,filestyle):
    filenames =[]
    yyyy = os.listdir(save_path)
    for iy in yyyy:
        mm   = os.listdir(save_path+iy+"/")
        for im in mm:
            files = os.listdir(save_path+iy+"/"+im+"/")
            filepaths = [iy+"/"+im+"/"+file for file in files if re.match(filestyle,file)]
            for filepath in filepaths:
                filenames.append(filepath)
    return filenames

if __name__ == '__main__':
    models=[]
    if single_download:
        models = [single_model]
    elif muti_models == []:
        for item in data_model.keys():
            if item in models_pass:
                continue
            models.append(item)
    else:
        models=muti_models
    download_log = open("download_data/download.log","a")
    download_log.write(f'{datetime.datetime.now()}下载开始'+"\n")
    for model in models:
        current_date = start_date

        nums_downloaded = 0
        nums_failed = 0
        
        url_path,save_path,filestyle = download_model(model)
        if not os.path.exists(save_path):                   #判断是否存在文件夹如果不存在则创建为文件夹
            os.makedirs(save_path)
        file_names = search_downloaded_files(save_path,filestyle)
        if not (file_names is None):
            os.makedirs(json_data["save_path"]+"lists", exist_ok=True)
            with open(json_data["save_path"]+"lists/"+model+'_list.txt', 'w') as file:
                for item in file_names:
                    file.write(str(item) + '\n') 
        #get all url:
        while current_date <= end_date:
            date=str(current_date.strftime("%Y%m%d"))
            
            if find_downloaded_file(file_names, date):
                print(date,model,'\033[1;32m文件已存在\033[0m')
                current_date+=datetime.timedelta(days=1)
                continue
            year      = current_date.year
            month     = current_date.month
            yyyymm    = str(current_date.strftime("%Y/%m/"))
            urls_status_code,bool_urls,urls = search_url(url_path+yyyymm,filestyle)
            if bool_urls:
                print(f'\033[0;32m {len(urls)} {model} files in '+yyyymm+'\033[0m')
                for url in urls:
                    filename = str(url)
                    date=re.findall(r"\d{8}", filename)[0]
                    if find_downloaded_file(file_names, date):
                        print(date,model,'\033[1;32m文件已下载\033[0m')
                        current_date+=datetime.timedelta(days=1)
                        continue
                    if not os.path.exists(save_path+yyyymm):
                        os.makedirs(save_path+yyyymm)
                    url_status_code,logic = requests_download(url_path+yyyymm+filename,save_path+yyyymm+filename)
                    time_now = datetime.datetime.now()
                    print(f'{model}_{date} 下载状态:\033[0;32m{logic}\033[0m, status = \033[0;32m{url_status_code}\033[0m 当前时间:\033[1;34m{time_now}\033[0m\n')
                    if logic:
                        nums_downloaded = nums_downloaded+1
                    else:
                        nums_failed = nums_failed+1
            month+=1
            if month == 13:
                month=1
                year+=1
            current_date = datetime.date(year, month, 1)
        file_names = search_downloaded_files(save_path,filestyle)
        with open(json_data["save_path"]+"lists/"+model+'_list.txt', 'w') as file:
            for item in file_names:
                file.write(str(item) + '\n')
        download_log.write(f'{model}下载完成{nums_downloaded}个文件，失败{nums_failed}个文件'+"\n")
    download_log.close()