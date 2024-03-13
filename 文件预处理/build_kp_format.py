# 获取KP不同版本的vars对应的值
import json
root_path="E:/MAVEN/KP/"
files = {
    19:root_path+"mvn_kp_insitu_20140921_v19_r01.tab",
    17:root_path+"mvn_kp_insitu_20190801_v17_r02.tab",
    15:root_path+"mvn_kp_insitu_20140925_v15_r03.tab",
    13:root_path+"mvn_kp_insitu_20140319_v13_r03.tab",
    }
files_contian = {}

key = 13
for key,var in files.items():
    Var_indexs = []
    Var_dict = {}
    file =  open(files[key],"r")
    lines = [line.rstrip() for line in file]
    bool_meet_parameter =False
    bool_skip_one_line = True
    bool_is_quality = False
    for line in lines:
        if line[:11] == '# PARAMETER':
            bool_meet_parameter = True
            continue
        elif(not bool_meet_parameter):
            continue
        if (len(line) == 1 and bool_skip_one_line):
            bool_skip_one_line = False
            continue
        elif (len(line) == 1 and not bool_skip_one_line):
            break
        Var_name = line[2:60]
        Var_name =Var_name.strip()
        Var_number = int(line[90:98])

        if Var_name == "Quality" or Var_name == 'Precision':
            bool_is_quality = True
        else:
            bool_is_quality = False

        if bool_is_quality and Var_name != Var_name_now:
            Var_name = Var_name_now+'_'+Var_name
        elif(bool_is_quality and Var_name == Var_name_now):
            Var_name = Var_name_now+'_2'
        Var_indexs.append([Var_name,Var_number])
        Var_dict[Var_name] = Var_number
        Var_name_now = Var_name
    files_contian[key] = Var_dict
with open("E:/MAVEN/lists/KP_vars.json", 'w') as json_file:
# with open("KP_vars.json", 'w') as json_file:    
    json.dump(files_contian, json_file, indent=4)

# E:\MAVEN\lists\KP_vars.json