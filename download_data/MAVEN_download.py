import datetime
import os
import re
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm
import re
from time import sleep
import json
# from dateutil.relativedelta import relativedelta
port=7897
porxies = {
"http": "http://127.0.0.1:"+str(port),
"https": "http://127.0.0.1:"+str(port),
}
timeout = None
sleep_time = 60
step_time= 5 #每个请求之间间隔的时间，以防被ban
data_format_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(f"{data_format_path}\load_data\MAVEN_data_format.json", "r") as file:
    json_data = json.load(file)
data_model = json_data["data_model"]

def test_proxies():
    global porxies
    global timeout
    try:
        response = requests.get("https://lasp.colorado.edu/maven/sdc/public/data/sci/",proxies=porxies,timeout=timeout)
        if response.status_code == 200:
            print("成功连接到代理服务器:"+porxies["http"])
        response.close()
        return True
    except requests.exceptions.RequestException as e:
        print(False)
        print(e)
    return False
def search_url(url,filename):
    global porxies
    global timeout
    sleep(step_time)
    try:
        response = requests.get(url, stream=True,proxies=porxies,timeout=timeout)
        while(response.status_code == 429):
            print(f"超出网站请求上限,休眠{sleep_time}秒")
            sleep(sleep_time)
            response = requests.get(url, stream=True,proxies=porxies,timeout=timeout)
        if response.status_code == 200:
            html_content = response.text

            soup = BeautifulSoup(html_content, 'html.parser')

            file_urls = []
            file_elements = soup.find_all('a', href=True)  # 找到所有带有href属性的<a>元

            for element in file_elements:
                file_url = element['href']
                file_urls.append(file_url)
            urls=[string for string in file_urls if re.match(filename, string)]
            response.close()
            if urls == None:
                return response.status_code,False,0
            return response.status_code,True,urls
    except requests.exceptions.RequestException as e:
        print(f"url error: {e},sleep {sleep_time}s")
        sleep(sleep_time)
        return response.status_code,False,0
    return response.status_code,False,0
def requests_downlaod(url,save_path):
    global porxies
    global timeout
    sleep(step_time)
    try:
        response = requests.get(url, stream=True,proxies=porxies,timeout=timeout)
        while(response.status_code == 429):
            print(f"超出网站请求上限,休眠{sleep_time}秒")
            sleep(sleep_time)
            response = requests.get(url, stream=True,proxies=porxies,timeout=timeout)
        if response.status_code == 200:
            total_size = int(response.headers.get("content-length", 0))
            block_size = 1024
            progress_bar = tqdm(total=total_size, unit="B", unit_scale=True)
            buffer = bytearray()  # 创建字节缓冲区
            for data in response.iter_content(block_size):
                progress_bar.update(len(data))
                buffer.extend(data)  # 将下载的数据添加到缓冲区
            progress_bar.close()
            
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
def downlaod_model(model):
    url_path_0='https://lasp.colorado.edu/maven/sdc/public/data/sci/'
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
      

if __name__ == '__main__':
    start_date   = datetime.date(2014, 10, 1)
    end_date     = datetime.date(2020, 6, 1)
    
    current_date = start_date

    models=data_model.keys()

    nums_downloaded = 0
    nums_failed = 0
    download_log = open("download.log","a")
    
    logic = test_proxies()
    if(logic == False):
        print('代理服务器连接失败')
        exit(0)

    downloadmodel = "single"
    if downloadmodel == "single": # single model
        model= "STATIC_d1"#"LPW_we12"#"SWEA_pad_svy"#"LPW_bursthf"
        url_path,save_path,filestyle = downlaod_model(model)
        folder = os.path.exists(save_path)
        if not folder:                   #判断是否存在文件夹如果不存在则创建为文件夹
            os.makedirs(save_path) 
        file_names = os.listdir(save_path)
        with open("E:/MAVEN/lists/"+model+'_list.txt', 'w') as file:
            for item in file_names:
                file.write(str(item) + '\n') 
        #get all url:
        while current_date <= end_date:
            date=str(current_date.strftime("%Y%m%d"))
    
            if find_downloaded_file(file_names, date):
                print(date,model,'文件已存在')
                current_date+=datetime.timedelta(days=1)
                continue
            year      = current_date.year
            month     = current_date.month
            yyyymm    = str(current_date.strftime("%Y/%m/"))
            urls_status_code,bool_urls,urls = search_url(url_path+yyyymm,filestyle)
            if bool_urls:
                print(f'{len(urls)} {model} files in '+yyyymm)
                for url in urls:
                    filename = str(url)
                    date=re.findall(r"\d{8}", filename)
                    if find_downloaded_file(file_names, filename):
                        print(date,model,'文件已下载')
                        current_date+=datetime.timedelta(days=1)
                        continue
                    url_status_code,logic = requests_downlaod(url_path+yyyymm+filename,save_path+filename)
                    time_now = datetime.datetime.now()
                    print(f'[{date}]下载状态:{logic}, status_code={url_status_code} 当前时间:{time_now}\n')
            month+=1
            if month == 13:
                month=1
                year+=1
            current_date = datetime.date(year, month, 1)
        file_names = os.listdir(save_path)
        with open("E:/MAVEN/lists/"+model+'_list.txt', 'w') as file:
            for item in file_names:
                file.write(str(item) + '\n')
        exit(0)
## muti model
    models = ["STATIC_c8","STATIC_ca","LPW_we12"]
    for model in models:
        try:
            url_path,save_path,filestyle = downlaod_model(model)
            file_names = os.listdir(save_path)
            with open("E:/MAVEN/lists/"+model+'_list.txt', 'w') as file:
                for item in file_names:
                    file.write(str(item) + '\n') 
            current_date =  start_date
            while current_date <= end_date:
                date=str(current_date.strftime("%Y%m%d"))

                if find_downloaded_file(file_names, date):
                    print(date,model,'文件已存在')
                    current_date+=datetime.timedelta(days=1)
                    continue
                year    = current_date.year
                month   = current_date.month
                yyyymm  = str(current_date.strftime("%Y/%m/"))
                urls_status_code,bool_urls,urls = search_url(url_path+yyyymm,filestyle)
                print(f'{len(urls)} {model} files in '+yyyymm)
                for url in urls:
                    filename = str(url)
                    date=re.findall(r"\d{8}", filename)
                    if find_downloaded_file(file_names, filename):
                        print(date,model,'文件已下载')
                        current_date+=datetime.timedelta(days=1)
                        continue
                    url_status_code,logic = requests_downlaod(url_path+yyyymm+filename,save_path+filename)
                    time_now = datetime.datetime.now()
                    print(f'[{date}]下载状态:{logic}, status_code={url_status_code} 当前时间:{time_now}\n')
                    if logic:
                        nums_downloaded+=1
                    else:
                        nums_failed+=1
                month+=1
                if month == 13:
                    month=1
                    year+=1
                current_date = datetime.date(year, month, 1)
            file_names = os.listdir(save_path)
        except:
            print("停止下载，保存已下载文件列表")
        with open("E:/MAVEN/lists/"+model+'_list.txt', 'w') as file:
            for item in file_names:
                file.write(str(item) + '\n')
        download_log.write(f'{model}下载完成{nums_downloaded}个文件，失败{nums_failed}个文件'+"\n")
    download_log.close
#文件检查
    # for model in models:
    #     if model in ["MAG_ss1s","MAG_pc1s","MAG_ss","MAG_pc","SWEA_spec","LPW_mrgscpot"]:
    #         continue
    #     if model in ["SWEA_pad_arc","SWEA_pad_svy","KP"]:
    #         continue
    #     url_path,save_path,filestyle = downlaod_model(model)
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