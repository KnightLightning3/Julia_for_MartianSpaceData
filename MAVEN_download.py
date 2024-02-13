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
    try:
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
            return urls
    except requests.exceptions.RequestException as e:
        print(" url error: "+str(e)+',sleep 60s')
        sleep(60)
        return False
def requests_downlaod(url,save_path):
    global porxies
    global timeout
    try:
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
            return True
        response.close()
    except requests.exceptions.RequestException as e:
        print(" url error: "+str(e)+',sleep 60s')
        sleep(60)
        return False
def downlaod_model(model):
    url_path_0='https://lasp.colorado.edu/maven/sdc/public/data/sci/'
    with open("data_format.json", "r") as file:
        data = json.load(file)
    save_dir = data["save_path"]
    data_model = data["data_model"]
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
    # months = get_months_between(start_date, end_date)
    
    current_date = start_date
    with open("data_format.json", "r") as file:
        data = json.load(file)
    data_model = data["data_model"]

    models=data_model.keys()

    nums_downloaded = 0
    nums_failed = 0
    download_log = open("download.log","a")
# single model
    model= "KP"#"SWEA_pad_svy"#"LPW_bursthf"
    url_path,save_path,filestyle = downlaod_model(model)
    file_names = os.listdir(save_path)
    # counter = file_check(file_names,save_path,'kp')
    with open("E:/MAVEN/lists/"+model+'_list.txt', 'w') as file:
        for item in file_names:
            file.write(str(item) + '\n') 
    
    #get all url:
    logic = test_proxies()
    if(logic == False):
        print('代理服务器连接失败')
        exit(0)
    while current_date <= end_date:
        date=str(current_date.strftime("%Y%m%d"))

        if find_downloaded_file(file_names, date):
            print(date,model,'文件已存在')
            current_date+=datetime.timedelta(days=1)
            continue
        year    = current_date.year
        month   = current_date.month
        yyyymm  = str(current_date.strftime("%Y/%m/"))
        urls    = search_url(url_path+yyyymm,filestyle)
        print(len(urls),'files in ', yyyymm)
        for url in urls:
            filename = str(url)
            date=re.findall(r"\d{8}", filename)
            if find_downloaded_file(file_names, filename):
                print(date,model,'文件已下载')
                current_date+=datetime.timedelta(days=1)
                continue
            logic = requests_downlaod(url_path+yyyymm+filename,save_path+filename)
            print('\n',date,model,"下载状态:",logic,end='\n')
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
    logic = test_proxies()
    if(logic == False):
        print('代理服务器连接失败')
        exit(0)
    
    for model in models:
        try:
            if model in ['KP',"LPW_burstmf","SWEA_spec","MAG_ss1s","MAG_pc1s","LPW_mrgscpot","SWEA_pad_svy"]:
                continue
            url_path,save_path,filestyle = downlaod_model(model)
            file_names = os.listdir(save_path)
            with open("E:/MAVEN/lists/"+model+'_list.txt', 'w') as file:
                for item in file_names:
                    file.write(str(item) + '\n') 
            #get all url:
            current_date =  start_date
            while current_date <= end_date:
                date=str(current_date.strftime("%Y%m%d"))

                if find_downloaded_file(file_names, date):
                    print(date,model,'文件已存在')
                    # start_date=current_date
                    current_date+=datetime.timedelta(days=1)
                    continue
                year    = current_date.year
                month   = current_date.month
                yyyymm  = str(current_date.strftime("%Y/%m/"))
                urls    = search_url(url_path+yyyymm,filestyle)
                print(len(urls),'files in ', yyyymm)
                for url in urls:
                    filename = str(url)
                    date=re.findall(r"\d{8}", filename)
                    if find_downloaded_file(file_names, filename):
                        print(date,model,'文件已下载')
                        current_date+=datetime.timedelta(days=1)
                        continue
                    logic = requests_downlaod(url_path+yyyymm+filename,save_path+filename)
                    print('\n',date,model,"下载状态:",logic,end='\n')
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