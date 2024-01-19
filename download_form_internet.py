import datetime
import os
import re
import cdflib
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm
import re
from time import sleep
import json


port=7897
porxies = {
"http": "http://127.0.0.1:"+str(port),
"https": "http://127.0.0.1:"+str(port),
}
def test_proxies():
    global porxies
    try:
        response = requests.get("https://lasp.colorado.edu/maven/sdc/public/data/sci/",proxies=porxies,timeout=5)
        if response.status_code == 200:
            print("成功连接到服务器")
        response.close()
    except requests.exceptions.RequestException as e:
        print(False)
        print(e)
def search_url(url,filename):
    global porxies
    try:
        response = requests.get(url, stream=True,proxies=porxies,timeout=5)
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
    try:
        response = requests.get(url, stream=True,proxies=porxies)
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
def file_check(file_names,save_path,model):
        if model == 'cdf':
            for f in file_names:
                try :
                    data=cdflib.cdfread.CDF(save_path+f)
                    print(data)
                    print(f,'true')
                    continue
                except Exception as e:
                    os.remove(os.path.join(save_path,f))
                    print('delete:' ,f,e)

if __name__ == '__main__':
    test_proxies()

    start_date   = datetime.date(2014, 11, 1)
    end_date     = datetime.date(2020, 6, 1)

    current_date = start_date
    with open("data_format.json", "r") as file:
        data = json.load(file)
    data_model = data["data_model"]

    models=data_model.keys()
    model="LPW_burstmf"

    url_path,save_path,filestyle = downlaod_model(model)
    file_names = os.listdir(save_path)
    #file_check(file_names,save_path,'cdf')
    with open("E:/MAVEN/lists/"+model+'_list.txt', 'w') as file:
        for item in file_names:
            file.write(str(item) + '\n') 
    #get all url:
    while current_date <= end_date:
        date=str(current_date.strftime("%Y%m%d"))

        if find_downloaded_file(file_names, date):
            print(date,model,'skip')
            start_date=current_date
            current_date+=datetime.timedelta(days=1)
            continue
        year=current_date.year
        month=current_date.month
        yyyymm=str(current_date.strftime("%Y/%m/"))
        urls    = search_url(url_path+yyyymm,filestyle)
        print(len(urls),'urls in ', yyyymm)
        for url in urls:
            filename = str(url)
            date=re.findall(r"\d{8}", filename)
            if find_downloaded_file(file_names, filename):
                print(date,model,'exist')
                continue
            logic = requests_downlaod(url_path+yyyymm+filename,save_path+filename)
            if logic == False: 
                os.remove(os.path.join(save_path,filename))
                print('remove',date)
            print('\n',date,model,logic,end='\n')
        month+=1
        if month == 13:
            month=1
            year+=1
        current_date = datetime.date(year, month, 1)
    file_names = os.listdir(save_path)
    with open("E:/MAVEN/lists/"+model+'_list.txt', 'w') as file:
        for item in file_names:
            file.write(str(item) + '\n')