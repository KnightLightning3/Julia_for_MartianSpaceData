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
def parse_pds_header_and_data(txt_file_path):
    """
    使用计数器平衡法解析头部的 KEY=VALUE 键值对，
    并使用 pandas 极速读取尾部固定宽度(FWF)的观测数据。
    """
    header_kv = {}
    obj_counter = 0
    data_start_byte_pos = 0
    
    # print(f"🔍 正在通过计数器检索元数据边界: {os.path.basename(txt_file_path)}...")
    
    # 阶段一：流式扫描文本，利用计数器提取 HEADER 里的参数，并定位数据区起点
    with open(txt_file_path, "r", encoding="utf-8") as f:
        out_of_header = False
        while True:
            line = f.readline()
            if not line:
                break
                
            # 遇到 OBJECT 计数器递增
            if "OBJECT" in line and "END_OBJECT" not in line:
                obj_counter += 1
                
            # 遇到 END_OBJECT 计数器递减
            elif "END_OBJECT" in line:
                obj_counter -= 1
                # 🌟 核心硬卡点：当最外层的 OBJECT = FILE 被闭合，计数器归零，说明头文件结束
                if obj_counter == 0:
                    data_start_byte_pos = f.tell() # 记录当前文件指针的字节位置
                    break
            
            # 如果在 HEADER 块内部，且包含等号，解析出参数名和参数值
            elif obj_counter > 0 and "=" in line:
                # 过滤掉无意义的嵌套标识（如 OBJECT = VECTOR）
                if "OBJECT" in line:
                    continue
                if out_of_header:
                    continue
                key, val = [x.strip() for x in line.split("=", 1)]
                header_kv[key.strip()] = val.strip().strip('"')
                if key == 'TITLE':
                    out_of_header = True  # 标题通常在头部末尾，作为一个辅助标志

    # print(f"📑 成功提取 HEADER 参数，包含: {list(header_kv.keys())}")
    print(f"⚡ 数据区起点字节偏移量: {data_start_byte_pos}。正在启动 pandas 批量加载明码...",end="\r")

    # =================================================================
    # 阶段二：计算严格对应的固定宽度切片 (colspecs)
    # 根据 ODL 定义的 FORMAT 计算出的 Python (0-based, 左闭右开) 索引映射表：
    # =================================================================
    # TIME (YEAR, DOY, HOUR, MIN, SEC, MSEC)
    # 1X,I4 -> 占5字符 [0:5]   | 1X,I3 -> 占4字符 [5:9]   | 1X,I2 -> 占3字符 [9:12]
    # 1X,I2 -> 占3字符 [12:15] | 1X,I2 -> 占3字符 [15:18] | 1X,I3 -> 占4字符 [18:22]
    # DDAY (F13.9) -> 占13字符 [22:35]
    # OB_B (X, Y, Z, RANGE) 均为 1X,F9.2 / 1X,F3.0
    # POSN (X, Y, Z) 均为 1X,F14.3
    # OB_BDPL (X, Y, Z, RANGE) 均为 1X,F7.3 / 1X,F4.0
    # =================================================================
    
    colspecs = [
        (0+1, 5+1),    # 0: YEAR
        (5+1, 9+1),    # 1: DOY
        (9+1, 12+1),   # 2: HOUR
        (12+1, 15+1),  # 3: MIN
        (15+1, 18+1),  # 4: SEC
        (18+1, 22+1),  # 5: MSEC
        (22+1, 35+1),  # 6: DDAY
        (35+3, 45+3),  # 7: OB_B_X (1X,F9.2)
        (45+3, 55+3),  # 8: OB_B_Y (1X,F9.2)
        (55+3, 65+3),  # 9: OB_B_Z (1X,F9.2)
        (65+3, 69+3),  # 10: ob_b_range (1X,F3.0)
        (69+4, 84+4),  # 11: POSN_X (1X,F14.3)
        (84+4, 99+4),  # 12: POSN_Y (1X,F14.3)
        (99+4, 114+4), # 13: POSN_Z (1X,F14.3)
        (114+5, 122+5),# 14: OB_BDPL_X (1X,F7.3)
        (122+5, 130+5),# 15: OB_BDPL_Y (1X,F7.3)
        (130+5, 138+5),# 16: OB_BDPL_Z (1X,F7.3)
        (138+5, 143+5) # 17: OB_BDPL_RANGE (1X,F4.0)
    ]
    
    col_names = [
        'YEAR', 'DOY', 'HOUR', 'MIN', 'SEC', 'MSEC', 'DDAY',
        'BX', 'BY', 'BZ', 'B_RANGE',
        'POS_X', 'POS_Y', 'POS_Z',
        'BDPL_X', 'BDPL_Y', 'BDPL_Z', 'BDPL_RANGE'
    ]

    # 将指针移回数据起点，利用 pandas 批量读取
    with open(txt_file_path, "r", encoding="utf-8") as f:
        f.seek(data_start_byte_pos)
        df = pd.read_fwf(f, colspecs=colspecs, names=col_names, header=None)

    print(f"📊 数据读取完毕，共有 {len(df)} 行记录。开始批量重构高维物理矢量...",end="\r")

    # =================================================================
    # 阶段三：矢量合并与高精度 Epoch 时间换算
    # =================================================================
    # 1. 批量合并时间戳
    # 考虑到大规模 DataFrame 逐行处理极慢，用向量化或通过 apply 构建时间戳
    def row_to_datetime(row):
        base = datetime(int(row['YEAR']), 1, 1, int(row['HOUR']), int(row['MIN']), int(row['SEC']), int(row['MSEC']) * 1000)
        return base + timedelta(days=int(row['DOY']) - 1)
        
    epochs = df.apply(row_to_datetime, axis=1).tolist()

    # 2. 从 DataFrame 中提取高维科学矢量矩阵（转为单精度 Float32）
    dday = df['DDAY'].astype(np.float32).values
    ob_b = df[['BX', 'BY', 'BZ']].astype(np.float32).values
    ob_b_range = df['B_RANGE'].astype(np.float32).values
    sc_position = df[['POS_X', 'POS_Y', 'POS_Z']].astype(np.float32).values
    ob_bdpl = df[['BDPL_X', 'BDPL_Y', 'BDPL_Z']].astype(np.float32).values
    ob_bdpl_range = df['BDPL_RANGE'].astype(np.float32).values

    return epochs, dday, ob_b,ob_b_range, sc_position, ob_bdpl, ob_bdpl_range, header_kv
def convert_pds_to_cdf(txt_file_path, output_cdf_path):
    """
    将所有高维时间依赖数据导出并写入带内置 GZIP 压缩的标准 CDF 文件
    """
    # 读取和转换数据
    epochs, dday, ob_b,ob_b_range, sc_position, ob_bdpl, ob_bdpl_range, header_kv = parse_pds_header_and_data(txt_file_path)

    if os.path.exists(output_cdf_path):
        os.remove(output_cdf_path)

    print(f"🛠️  正在创建物理 CDF 存储器，开始注入全局属性和参数...",end="\r")

    with pycdf.CDF(output_cdf_path, "") as cdf:
        # ==================================================
        # 1. 动态注入 HEADER 中的键值对作为全局属性
        # ==================================================
        for key, value in header_kv.items():
            cdf.attrs[key] = value  # 例如 cdf.attrs['CMD_LINE'] = "-odl -mars ..."

        # 🌟 刻入你的专属防伪与防重复压缩标识 [CDF_BYTE]
        cdf.attrs["IS_COMPRESSED_BY_USER"] = np.int8(1)
        cdf.attrs["CREATED_BY"] = "CDF version is created by Cheng Sanwei abcda@ustc.edu.mail.cn"
        cdf.attrs["CREATED_TIME"] = datetime.now().isoformat() + "Z"

        match = re.search(r'(?P<frame>pc|ss)(?P<res>\d+s)?_', txt_file_path)
        if match:
            frame_code = match.group('frame')
            res_code = match.group('res')
            # 映射为标准的明文描述
            if frame_code == "pc":
                coordinate_system = "Planetocentric (PC)" 
            elif frame_code == "ss":
                coordinate_system = "Mars Scientific Orbital (MSO)"
            time_resolution = "1 Hz" if res_code else "32Hz"
            cdf.attrs["COORDINATE_SYSTEM"] = coordinate_system
            cdf.attrs["TIME_RESOLUTION"] = time_resolution
        else:
            raise NotImplementedError(f"{match}请根据你的实际文件命名规则调整正则表达式，以正确提取坐标系和时间分辨率信息")
        # 依赖变量: 绝对时间轴 Epoch (不压缩以确保检索性能)
        cdf["epoch"] = epochs
        cdf["epoch"].attrs["FIELDNAM"] = "Time line"
        cdf["epoch"].attrs["UNITS"] = "ms"

        cdf['compno_3'] = np.array([0, 1, 2], dtype=np.int8)  # 组件编号数组，标识空间维度
        cdf["compno_3"].attrs["FIELDNAM"] = "compno_3"
        cdf["compno_3"].attrs["DICT_KEY"] = "number"

        cdf.new(
            name="magf_labl",
            data=["Bx", "By", "Bz"],
            type=pycdf.const.CDF_CHAR,
            recVary=False,  # 🌟 关键：声明为 NRV 变量
            dims=[3]
        )
        # 给标签变量本身也挂上它应有的属性（对应你给的元数据）
        cdf["magf_labl"].attrs["CATDESC"] = "magf_labl"
        cdf["magf_labl"].attrs["DICT_KEY"] = "label"
        cdf["magf_labl"].attrs["FIELDNAM"] = "magf_labl"
        cdf["magf_labl"].attrs["FORMAT"] = "A2"
        cdf["magf_labl"].attrs["VAR_TYPE"] = "metadata"

        cdf.new(
            name="pos_labl",
            data=["X", "Y", "Z"],
            type=pycdf.const.CDF_CHAR,
            recVary=False,  # 🌟 关键：声明为 NRV 变量
            dims=[3]
        )
        # 给标签变量本身也挂上它应有的属性（对应你给的元数据）
        cdf["pos_labl"].attrs["CATDESC"] = "pos_labl"
        cdf["pos_labl"].attrs["DICT_KEY"] = "label"
        cdf["pos_labl"].attrs["FIELDNAM"] = "pos_labl"
        cdf["pos_labl"].attrs["FORMAT"] = "A1"
        cdf["pos_labl"].attrs["VAR_TYPE"] = "metadata"

        # 设置统一的压缩级别
        gzip_level = 6

        # unix时间戳（秒级）也可以作为一个独立变量存储，方便某些应用直接使用数值时间进行计算
        # 一句话转换并直接在创建时开启高精度双精度(CDF_DOUBLE)与GZIP压缩
        unix_timestamps = [dt.timestamp() for dt in epochs]
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
        cdf["time_unix"].attrs["DEPEND_0"] = "epoch"

        # ==================================================
        # 3. 注入高维时间依赖数据 (开启二进制流式压缩)
        # ==================================================

        # 时间依赖变量: DECIMAL_DAY (一维，默认dims为零维)
        cdf.new(
            name="decimal_day", 
            data=dday, 
            type=pycdf.const.CDF_FLOAT,
            recVary=True,
            compress=pycdf.const.GZIP_COMPRESSION,
            compress_param=gzip_level
        )
        cdf["decimal_day"].attrs["FIELDNAM"] = "Decimal Day"
        cdf["decimal_day"].attrs["DEPEND_0"] = "epoch"

        # 时间依赖变量: OB_B 磁场矢量 (N x 3 二维矩阵)
        # 修正：dims去除前导记录维，只保留空间维度[3]，dimVarys保持默认全为True
        cdf.new(
            name="B",
            data=ob_b,
            type=pycdf.const.CDF_FLOAT,
            recVary=True,
            dims=[3],
            compress=pycdf.const.GZIP_COMPRESSION,
            compress_param=gzip_level
        )
        cdf["B"].attrs["FIELDNAM"] = "Outboard B Field Vector (J2000)"
        cdf["B"].attrs["UNITS"] = "nT"
        cdf["B"].attrs["DEPEND_0"] = "epoch"
        cdf["B"].attrs["DEPEND_1"] = "compno_3"
        cdf["B"].attrs["LABL_PTR_1"] = "magf_labl"

        # 时间依赖变量：ob_b_range，磁场范围（一维）
        cdf.new(
            name="ob_b_range", 
            data=ob_b_range, 
            type=pycdf.const.CDF_FLOAT,
            recVary=True,
            compress=pycdf.const.GZIP_COMPRESSION,
            compress_param=gzip_level
        )
        cdf["ob_b_range"].attrs["FIELDNAM"] = "Outboard B Field Range"
        cdf["ob_b_range"].attrs["DEPEND_0"] = "epoch"

        # 时间依赖变量: position 飞船坐标矢量 (N x 3 二维矩阵)
        # 精简：移除了冗余的 dimVarys=[True]
        cdf.new(
            name="position",
            data=sc_position,
            type=pycdf.const.CDF_FLOAT,
            recVary=True,
            dims=[3],
            compress=pycdf.const.GZIP_COMPRESSION,
            compress_param=gzip_level
        )
        cdf["position"].attrs["FIELDNAM"] = "Spacecraft Position Vector"
        cdf["position"].attrs["UNITS"] = "km"
        cdf["position"].attrs["DEPEND_0"] = "epoch"
        cdf["position"].attrs["DEPEND_1"] = "compno_3"
        cdf["position"].attrs["LABL_PTR_1"] = "pos_labl"

        # 时间依赖变量: OB_BDPL 载荷动力场矢量 (N x 3 二维矩阵)
        cdf.new(
            name="OB_BDPL",
            data=ob_bdpl,
            type=pycdf.const.CDF_FLOAT,
            recVary=True,
            dims=[3],
            compress=pycdf.const.GZIP_COMPRESSION,
            compress_param=gzip_level
        )
        cdf["OB_BDPL"].attrs["FIELDNAM"] = "Outboard dynamic correction in payload coordinates"
        cdf["OB_BDPL"].attrs["UNITS"] = "nT"
        cdf["OB_BDPL"].attrs["DEPEND_0"] = "epoch"
        cdf["OB_BDPL"].attrs["DEPEND_1"] = "compno_3"
        cdf["OB_BDPL"].attrs["LABL_PTR_1"] = "magf_labl"


        # 时间依赖变量：ob_bdpl_range，载荷动力场范围（一维）
        cdf.new(
            name="OB_BDPL_range", 
            data=ob_bdpl_range, 
            type=pycdf.const.CDF_FLOAT,
            recVary=True,
            compress=pycdf.const.GZIP_COMPRESSION,
            compress_param=gzip_level
        )
        cdf["OB_BDPL_range"].attrs["FIELDNAM"] = "Outboard dynamic correction Range"
        cdf["OB_BDPL_range"].attrs["DEPEND_0"] = "epoch"


if __name__ == "__main__":

    for key in ["MAG_ss1s", "MAG_pc1s","MAG_ss","MAG_pc"]:
        if key in json_list_data:
            print(f"\n=====正在处理数据类别: {key}，共 {len(json_list_data[key])} 个文件=====")
            mode_save_dir,_ = download_model(key)
            count = 0
            for txt_file in json_list_data[key]:
                count += 1
                print(f"处理文件{os.path.basename(txt_file)} {count}/{len(json_list_data[key])}...")
                txt_file_path = os.path.join(mode_save_dir, txt_file)
                output_cdf_path = os.path.join(mode_save_dir[:-2]+"3", txt_file[:-4] + "_compressed.cdf")
                new_file_path = os.path.join(mode_save_dir[:-2]+"3", txt_file[:-4] + ".cdf")
                if os.path.exists(new_file_path):
                    continue
                if not os.path.exists(os.path.dirname(new_file_path)):
                    os.makedirs(os.path.dirname(new_file_path))
                convert_pds_to_cdf(txt_file_path, output_cdf_path)
                #修改临时文件结尾
                os.rename(output_cdf_path, new_file_path)