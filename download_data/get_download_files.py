# 获取目录中所有下载的文件，将其写为json

import os
import json

list_dict={}

data_format_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(f"{data_format_path}/MAVEN_data/MAVEN_data_format.json", "r") as file:
    json_data = json.load(file)
path = json_data["save_path"]+"lists/"
listnames = os.listdir(path)
listnames = [x for x in listnames if x[-4:] == ".txt"]

for listname in listnames:
    model = listname[:-9]
    with open(path+listname,'r') as f:
        lines = [line.rstrip() for line in f]
    list_dict[model] = lines
# 如果不存在filename_lists.json文件，则创建
if not os.path.exists("MAVEN_data/filename_lists.json"):
    from pathlib import Path
    Path("MAVEN_data/filename_lists.json").touch()
with open("MAVEN_data/filename_lists.json", 'w') as json_file:
    json.dump(list_dict, json_file, indent=4)

print("\033[1;32m成功录入以下数据模块目录:\033[0m") 
for ls in listnames:
    print("    "+ls)