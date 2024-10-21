# 给予网址,下载其下指定文件名格式的所有文件
import datetime
import os
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm
import re
from time import sleep
import argparse

def get_args():
    parser = argparse.ArgumentParser(
            description="这是一个下载程序，从指定url中下载指定名字的文件。"
        )
    parser.add_argument(
        "-u","--url_path", 
        type=str, 
        default="", 
        help="要访问的 URL 路径（默认为空）"
    )
    parser.add_argument(
        "-s","--save_path", 
        type=str, 
        default="E:/下载/", 
        help="要保存文件的地址,默认为下载文件夹"
    )
    parser.add_argument(
        "-f","--file_style", 
        type=str, 
        default="csv",
        help="指定要下载的文件格式"
    )
    parser.add_argument(
        "-VPN","--use_VPN", 
        action="store_true", 
        help="是否使用VPN（默认不使用）"
    )
    parser.add_argument(
        "--proxy", 
        type=str,
        default="7897",
        help="VPN端口(默认7897端口)"
    )
    args = parser.parse_args()
    if args.use_VPN:
        vpn_proxy = {
        "http": f"http://127.0.0.1:{args.proxy}",
        "https":f"http://127.0.0.1:{args.proxy}",
        }
    else:
        vpn_proxy =  None
    print(f"URL路径: {args.url_path}")
    print(f"保存路径: {args.save_path}")
    print(f"文件格式: {args.file_style}")
    print(f"是否使用VPN: {'是' if args.use_VPN else '否'}")
    return args.url_path, args.save_path, args.file_style, vpn_proxy
url_path,save_path,file_style,vpn_proxy = get_args()
# http://atmos.nmsu.edu/PDS/data/PDS4/MAVEN/ngims_derivedL3_2024.tar.gz
if url_path == "":
    print("no url path")
    exit(0)
sleep_time = 60
step_time = 3
timeout = None

session = requests.Session()

def sleep_local(sleep_time_range):
    for i in range(sleep_time_range):
        print(f"Waiting \033[1;34m {i+1} / {sleep_time_range} \033[0m Seconds\033[K",end="\r")
        sleep(1)
    return None
def test_proxies():
    global vpn_proxy
    global url_path
    global timeout
    try:
        response = requests.get(url_path,proxies=vpn_proxy,timeout=timeout)
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
        print(f"Requesting:{url}...\033[K",end='\r')
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
                os.makedirs(save_path)
            # 将缓冲区中的数据写入文件
            with open(save_path, "wb") as file:
                print(f"\033[FWriting into: {save_path}",end='\r')
                file.write(buffer)
            return response.status_code,True,progress_bar_data
        response.close()
    except requests.exceptions.RequestException as e:
        print(f"url error: {e},sleep \033[1;34m{sleep_time}\033[0m Seconds")
        sleep_local(sleep_time)
        return response.status_code,False,None
    return response.status_code,False,None

if __name__ == '__main__':
    nums_downloaded = 0
    nums_failed = 0
    if vpn_proxy == None:
        print("\033[1;32m No VPN \033[0m")
    else:
        logic = test_proxies()
        if(logic == False):
            print('\033[1;31m Connection Failed, Exit Program \033[0m')
            exit(0)
    try:
        urls_status_code,bool_urls,urls = search_url(url_path,file_style)
    except requests.exceptions.RequestException as e:
        print(f"failed_connect {url_path}, error:{e}")
        urls = []
        exit(0)
    for url in urls:
        filename = str(url)
        if os.path.isfile(save_path+filename):
            print(f"SKIP:{filename}")
            continue
        try:
            url_status_code,logic,progress_data = requests_download(url_path+filename,save_path+filename)
        except:
            logic = False
        time_now = datetime.datetime.now()
        if logic:
            try:
                download_speed = str(round(progress_data["rate"]/1024/1024,2))
                download_time = str(round(progress_data["elapsed"],2))
            except:
                download_speed = "ERROR"
                download_time = "ERROR"
            print(f'{filename}: ' +
                    f'Status: \033[0;32m{logic}\033[0m ' +
                    f'Responses: \033[0;32m{url_status_code}\033[0m '+
                    f'Time: \033[1;34m{time_now.strftime("%Y-%m-%d %H:%M:%S")}\033[0m '+
                    f'Time spend: \033[1;34m{download_time}\033[0m s '+
                    f'Speed: \033[1;34m{download_speed}\033[0m Mb/s')
            nums_downloaded = nums_downloaded+1
        else:
            try:
                print(f'{filename}: ' +
                        f'Status: \033[0;31m{logic}\033[0m ' +
                        f'Responses: \033[0;32m{url_status_code}\033[0m '+
                        f'Time: \033[1;34m{time_now.strftime("%Y-%m-%d %H:%M:%S")}\033[0m ')
            except:
                print(f'{filename}: ' +
                        f'Status: \033[0;31m{logic}\033[0m ' +
                        f'Responses: \033[0;32munknow_error\033[0m '+
                        f'Time: \033[1;34m{time_now.strftime("%Y-%m-%d %H:%M:%S")}\033[0m ')
            nums_failed = nums_failed+1
    print(f"download done, succeed {nums_downloaded}, failed {nums_failed}")