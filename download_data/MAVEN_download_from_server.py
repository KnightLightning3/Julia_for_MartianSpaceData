import os
import requests
from bs4 import BeautifulSoup

save_dir = '/media/ExtHDD/data/maven/kp/'
url = 'http://222.195.76.155:8000/MAVEN/KP/insitu'
user_name = '待定用户007'
password = '待定用户007的密码是待定用户007'

year_list = [2022]

def download(url, save_dir, year_list, user_name, password):
    session = requests.Session()
    session.auth = (user_name.encode('utf-8'), password.encode('utf-8'))

    for year in year_list:
        os.makedirs(os.path.join(save_dir, str(year)), exist_ok=True)
        for month in range(1, 13, 1):
            url_0 = f'{url}/{year:4d}/{month:02d}'
            res = session.get(url_0)
            if res.status_code != 200:
                print(f"{year}-{month:02d} response error, error code: {res.status_code}")
                continue
            soup = BeautifulSoup(res.text, 'lxml')  
            # create dir is not exist
            month_dir = os.path.join(save_dir, str(year), '%02d' %month)
            os.makedirs(month_dir, exist_ok=True)
            for li in soup.find_all('li'):
                file_name = li.a.text
                url_file = url_0+'/'+file_name
                buffer = session.get(url_file, stream=True)
                with open(os.path.join(month_dir, file_name), 'wb') as f:
                    for stream in buffer:
                        f.write(stream)

if __name__ == "__main__":
    download(url, save_dir, year_list, user_name=user_name, password=password)