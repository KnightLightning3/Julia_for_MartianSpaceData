import os
import io
import re
from datetime import datetime, timedelta
import numpy as np
import pandas as pd
from spacepy import pycdf
import configparser
import json
from collections import defaultdict


# ==================================================
# 1. 基础配置与路径动态解析（你提供的代码段）
# ==================================================
def get_list_from_ini(input_string):
    if input_string == "Null":
        return []
    if input_string == "None":
        return None
    stripped_string = input_string.replace(" ", "")
    items = stripped_string.split(",")
    return items


# 获取项目根目录
project_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
print(project_path)
# 读取数据格式 JSON 文件
with open(os.path.join(project_path, "MAVEN_data", "MAVEN_data_format.json"), "r", encoding="utf-8") as file:
    json_data = json.load(file)
# 读取目录文件
with open(os.path.join(project_path, "MAVEN_data", "filename_lists.json"), "r", encoding="utf-8") as file:
    json_list_data = json.load(file)
# 1. 加载 KP_vars.json 配置文件
with open(os.path.join(project_path, "MAVEN_data", "KP_vars.json"), 'r', encoding='utf-8') as f:
    kp_vars_all = json.load(f)
# 读取下载配置文件 INI
config_file_path = os.path.join(
    project_path, "download_data", "MAVEN_download_config.ini"
)
config_data = configparser.ConfigParser()
config_data.optionxform = str
config_data.read(config_file_path, encoding="utf-8")

save_dir = config_data["DEFAULT"]["Save_dir"]
def download_model(model):
    global save_dir
    global json_data
    data_model = json_data["data_model"]
    model_key = {}
    for key, value in data_model.items():
        model_key[key] = value[:3]
    _, filename, pathname = model_key[model]
    save_path = save_dir + pathname
    return [save_path, filename]
def parse_kp_version(filename):
    """
    从 KP 文件名解析版本号字符串 (如 mvn_kp_insitu_20140318_v13_r03.tab -> '13')
    对应 Julia 中 file_in[end-9:end-8]
    """
    version_match = re.search(r'_v(\d+)_', filename)
    if version_match:
        return f"{int(version_match.group(1)):02d}"
    return "01"


def build_kp_colspecs(total_cols=235):
    """
    构建 235 列的固定宽度字符切片坐标区间 [start, end)
    """
    colspecs = [(0, 19)]  # 第 1 列: 时间列 (19 字符)
    for k in range(1, total_cols):
        start = 16 * k + 3
        end = 16 * k + 19
        colspecs.append((start, end))
    return colspecs


def convert_kp_to_cdf(kp_file_path, output_cdf_path, gzip_level=1):
    """
    读取 KP_vars.json 格式配置表，精准匹配转换列类型并导出为 CDF 文件
    """
    filename = os.path.basename(kp_file_path)
    version_str = parse_kp_version(filename)

    # 获取当前版本对应的配置项，找不到则使用默认版本配置
    if version_str in kp_vars_all:
        kp_vars_local = kp_vars_all[version_str]
    else:
        first_key = list(kp_vars_all.keys())[0]
        print(f"⚠️  未找到版本 v{version_str} 配置，回退使用 v{first_key} 配置")
        kp_vars_local = kp_vars_all[first_key]

    print(f"⚡ 正在解析 KP 文件 (版本 v{version_str}): {filename} ...",end="\r")

    # 2. 定长切片读取文本数据
    colspecs = build_kp_colspecs(total_cols=235)
    df = pd.read_fwf(
        kp_file_path, 
        colspecs=colspecs, 
        comment='#', 
        header=None, 
        dtype=str
    )

    # 3. 提取时间轴
    raw_time_series = pd.to_datetime(df[0].str.strip(), errors='coerce')
    time_series = [t.to_pydatetime() for t in raw_time_series]
    ntime = len(time_series)

    if os.path.exists(output_cdf_path):
        os.remove(output_cdf_path)

    print(f"🛠️  写入 CDF (GZIP Level {gzip_level}): {os.path.basename(output_cdf_path)} ...",end="\r")

    with pycdf.CDF(output_cdf_path, "") as cdf:
        # 全局属性写入
        cdf.attrs["TITLE"] = "MAVEN Key Parameters (KP) Data"
        cdf.attrs["SOURCE_FILE"] = filename
        cdf.attrs["KP_VERSION"] = version_str
        cdf.attrs["CREATED_TIME"] = datetime.now().isoformat() + "Z"

        # 时间主轴 Epoch
        cdf["epoch"] = time_series
        cdf["epoch"].attrs["FIELDNAM"] = "Time line"
        cdf["epoch"].attrs["UNITS"] = "ms"

        # Unix 时间戳
        unix_timestamps = np.array([dt.timestamp() for dt in time_series], dtype=np.float64)
        cdf.new(
            name="time_unix",
            data=unix_timestamps,
            type=pycdf.const.CDF_DOUBLE,
            recVary=True,
            compress=pycdf.const.GZIP_COMPRESSION,
            compress_param=gzip_level
        )
        cdf["time_unix"].attrs["FIELDNAM"] = "Unix Timestamp"
        cdf["time_unix"].attrs["UNITS"] = "s"

        # 3x3 矩阵 Component 索引
        cdf['compno_3'] = np.array([0, 1, 2], dtype=np.int8)

        # 4. 遍历列 2 到 217（对应 Python DataFrame 索引 1 到 216）
        for i in range(2, 218):
            col_idx = i - 1
            var_name = f"var_{i}"
            raw_col = df[col_idx].str.strip()

            # 从 JSON 匹配格式 (Julia 的 KP_vars_local["$i"][2] 在 Python 列表中索引为 1)
            var_info = kp_vars_local.get(str(i), [var_name, "F16.3"])
            fmt = var_info[1].upper() if len(var_info) > 1 else var_info[0].upper()
            fmt_type = fmt[0] if fmt else 'F'

            # 对应 Julia 的格式判断逻辑
            if fmt_type in ('F', 'E'):
                num_col = pd.to_numeric(raw_col, errors='coerce')
                
                # 如果是 F16.8 或高精度格式，使用 Float64 避免丢失小数位
                if "16.8" in fmt or "16.7" in fmt:
                    data_arr = num_col.fillna(np.nan).values.astype(np.float64)
                    cdf_type = pycdf.const.CDF_DOUBLE
                else:
                    data_arr = num_col.fillna(np.nan).values.astype(np.float32)
                    cdf_type = pycdf.const.CDF_FLOAT

            elif fmt_type == 'I':
                # 整数解析 -> Int32
                num_col = pd.to_numeric(raw_col, errors='coerce')
                data_arr = num_col.fillna(-9999).values.astype(np.int32)
                cdf_type = pycdf.const.CDF_INT4

            elif fmt_type == 'A':
                # 字符串保持原样 -> String List
                data_arr = raw_col.fillna("").tolist()
                cdf_type = pycdf.const.CDF_CHAR

            else:
                # 默认回退 Float32
                num_col = pd.to_numeric(raw_col, errors='coerce')
                data_arr = num_col.fillna(np.nan).values.astype(np.float32)
                cdf_type = pycdf.const.CDF_FLOAT

            # 写入 CDF 变量
            cdf.new(
                name=var_name,
                data=data_arr,
                type=cdf_type,
                recVary=True,
                compress=pycdf.const.GZIP_COMPRESSION,
                compress_param=gzip_level
            )
            cdf[var_name].attrs["FIELDNAM"] = var_name
            cdf[var_name].attrs["DEPEND_0"] = "epoch"

        # 5. 提取 218:226 列重构 pc2ss_Matrix (N, 3, 3)
        # Julia 的 div 与 rem 展开逻辑为行主序 (Row-Major)，与 NumPy 默认 reshape 顺序一致
        pc2ss_raw = df.iloc[:, 217:226].apply(pd.to_numeric, errors='coerce').values.astype(np.float32)
        pc2ss_matrix = pc2ss_raw.reshape(ntime, 3, 3)

        cdf.new(
            name="pc2ss_Matrix",
            data=pc2ss_matrix,
            type=pycdf.const.CDF_FLOAT,
            recVary=True,
            dims=[3, 3],
            compress=pycdf.const.GZIP_COMPRESSION,
            compress_param=gzip_level
        )
        cdf["pc2ss_Matrix"].attrs["FIELDNAM"] = "Planetocentric to MSO Matrix"
        cdf["pc2ss_Matrix"].attrs["DEPEND_0"] = "epoch"
        cdf["pc2ss_Matrix"].attrs["DEPEND_1"] = "compno_3"
        cdf["pc2ss_Matrix"].attrs["DEPEND_2"] = "compno_3"

        # 6. 提取 227:235 列重构 sc2ss_Matrix (N, 3, 3)
        sc2ss_raw = df.iloc[:, 226:235].apply(pd.to_numeric, errors='coerce').values.astype(np.float32)
        sc2ss_matrix = sc2ss_raw.reshape(ntime, 3, 3)

        cdf.new(
            name="sc2ss_Matrix",
            data=sc2ss_matrix,
            type=pycdf.const.CDF_FLOAT,
            recVary=True,
            dims=[3, 3],
            compress=pycdf.const.GZIP_COMPRESSION,
            compress_param=gzip_level
        )
        cdf["sc2ss_Matrix"].attrs["FIELDNAM"] = "Spacecraft to MSO Matrix"
        cdf["sc2ss_Matrix"].attrs["DEPEND_0"] = "epoch"
        cdf["sc2ss_Matrix"].attrs["DEPEND_1"] = "compno_3"
        cdf["sc2ss_Matrix"].attrs["DEPEND_2"] = "compno_3"

    print(f"✅ 完成转换: {os.path.basename(output_cdf_path)}")
if __name__ == "__main__":

    key = "KP"
    if key in json_list_data:
        print(f"\n=====正在处理数据类别: {key}，共 {len(json_list_data[key])} 个文件=====",end="\r")
        mode_save_dir,_ = download_model(key)
        
        count = 0
        for txt_file in json_list_data[key]:
            count += 1
            print(f"处理文件{os.path.basename(txt_file)} {count}/{len(json_list_data[key])}...",end="\r")
            txt_file_path = os.path.join(mode_save_dir, txt_file)
            output_cdf_path = os.path.join(mode_save_dir[:-7]+"cdf", txt_file[:-4] + "_compressed.cdf")
            new_file_path = os.path.join(mode_save_dir[:-7]+"cdf", txt_file[:-4] + ".cdf")
            # break

            if os.path.exists(new_file_path):
                continue
            if not os.path.exists(os.path.dirname(new_file_path)):
                os.makedirs(os.path.dirname(new_file_path))
            convert_kp_to_cdf(txt_file_path, output_cdf_path,gzip_level=6)
            #修改临时文件结尾
            os.rename(output_cdf_path, new_file_path)
            # break