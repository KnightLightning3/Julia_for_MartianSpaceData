# 检查本地所有存在的文件,并且将文件名与对应hash值计算后保存到filehash_list.txt中
import os
import re
import json
import runpy
import configparser

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

project_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(f"{project_path}/MAVEN_data/MAVEN_data_format.json", "r", encoding='utf-8') as file:
    json_data = json.load(file)
data_model = json_data["data_model"]

config_file_path = os.path.join(project_path, "download_data", "MAVEN_download_config.ini")
config_data = configparser.ConfigParser()
config_data.optionxform = str
config_data.read(config_file_path, encoding='utf-8')

save_dir = config_data['DEFAULT']['Save_dir']

def download_model(model):
    global save_dir
    global json_data
    data_model = json_data["data_model"]
    model_key = {}
    for key, value in data_model.items():
        model_key[key] = value[:3]
    _,filename,pathname=model_key[model]
    save_path =  save_dir+pathname
    return [save_path,filename]
def search_downloaded_files(save_path,file_style):
    filenames =[]
    if not os.path.exists(save_path):
        return None
    yyyy = os.listdir(save_path)
    for iy in yyyy:
        mm   = os.listdir(save_path+iy+"/")
        for im in mm:
            files = os.listdir(save_path+iy+"/"+im+"/")
            filepaths = [iy+"/"+im+"/"+file for file in files if re.match(file_style,file)]
            for filepath in filepaths:
                filenames.append(filepath)
    return filenames
# def get_filehashs(save_path,file_style):  HASH值计算时长过长，暂时不使用
#       import hashlib
#     # 计算文件hash值
#     filehash_list = []
#     yyyy = os.listdir(save_path)
#     for iy in yyyy:
#         mm   = os.listdir(save_path+iy+"/")
#         for im in mm:
#             files = os.listdir(save_path+iy+"/"+im+"/")
#             filedirs = [save_path+iy+"/"+im+"/"+file for file in files if re.match(file_style,file)]
#             for filedir in filedirs:
#                 filehash = hashlib.new('sha256')
#                 with open(filedir, 'rb') as f:
#                     filehash.update(f.read())
#                 filehash_list.append(filedir+","+filehash.hexdigest())
#     return filehash_list
if __name__ == '__main__':
    os.makedirs(save_dir+"lists/", exist_ok=True)
    for model in json_data["data_model"].keys():
        save_path,file_style = download_model(model)
        print(save_path)
        file_names = search_downloaded_files(save_path,file_style)
        if file_names is None:
            continue
        with open(save_dir+"lists/"+model+'_list.txt', 'w', encoding='utf-8') as file:
            for item in file_names:
                file.write(str(item) + '\n')
    
    runpy.run_path(f'{project_path}/download_data/get_download_files.py')  # run get_download_files.py, update filename_list.txt  
    exit(0) # check download file mode do not download file