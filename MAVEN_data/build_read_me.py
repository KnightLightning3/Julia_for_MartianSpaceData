# 从json文件中建立md的模块列表

import json
import os

project_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(f"{project_path}/MAVEN_data/MAVEN_data_format.json", "r", encoding='utf-8') as file:
    json_data = json.load(file)
data_model = json_data["data_model"]
models = data_model.keys()
strs = []
strs.append(f"|模型名|描述|读取函数|名称格式|")
strs.append(f"|---|---|---|---|")
for model in models:
    var = data_model[model]
    if len(var) >= 5:
        strs.append(f"|{model}|{var[4]}|{var[3]}|{var[1]}|")
    else:
        strs.append(f"|{model}| |{var[3]}|{var[1]}|")

with open(f"{project_path}/MAVEN_data/MAVEN_data_format.md", "r", encoding='utf-8') as file:
    lines = file.readlines()
for i, line in enumerate(lines):
    if 'MAVEN数据模块名列表' in line:
        found = True
        lines_0 = lines[:i+1]
        break
for ii,si in enumerate(strs):
    lines_0.insert(i + 1 + ii, si + '\n')
with open(f"{project_path}/MAVEN_data/MAVEN_data_format.md", "w", encoding='utf-8') as file:
    file.writelines(lines_0)