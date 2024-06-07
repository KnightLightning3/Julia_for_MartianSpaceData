# 获取目录中所有下载的文件，将其写为json

import os
import json

list_dict={}
listnames = os.listdir("E:/MAVEN/lists/")
listnames = [x for x in listnames if x[-4:] == ".txt"]

print(listnames)
for listname in listnames:
    model = listname[:-9]
    with open("E:/MAVEN/lists/"+listname,'r') as f:
        lines = [line.rstrip() for line in f]
    list_dict[model] = lines
with open("MAVEN_data/filename_lists.json", 'w') as json_file:
    json.dump(list_dict, json_file, indent=4)