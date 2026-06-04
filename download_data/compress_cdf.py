
import os
import configparser
from tqdm import tqdm
from spacepy import pycdf
import time

# 1. 基础配置读取
project_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
config_file_path = os.path.join(project_path, "download_data", "MAVEN_download_config.ini")

config_data = configparser.ConfigParser()
config_data.optionxform = str
config_data.read(config_file_path, encoding='utf-8')

save_dir = config_data['DEFAULT']['Save_dir']#"E:/MAVEN/SWEA"#

def check_if_compressed(file_path, gzip_level_threshold):
    """
    检查 CDF 文件是否已经过高强度压缩
    返回 True 表示应跳过，False 表示需要压缩
    """
    try:
        with pycdf.CDF(file_path) as cdf:
            # 遍历文件里的变量，看是否有变量已经开启了高等级的 GZIP
            for var_name in cdf:
                var = cdf[var_name]
                # 获取变量的压缩信息，返回结构形如 (compress_type, compress_param)
                # 例如开启了Gzip 5会返回 (1, 5)；未压缩返回 (0, 0)
                comp_type, comp_param = var.compress()
                
                # 1 代表 const.GZIP_COMPRESSION
                if comp_type == 1 and comp_param >= gzip_level_threshold:
                    return True
                # 只要检查到第一个观测数据变量的压缩状态即可做出判断
                if var.rv(): 
                    break
        return False
    except Exception as e:
        # 如果文件损坏或无法读取，保守起见先跳过，避免误删
        print(f"\n\033[1;33m警告\033[0m: 无法读取文件属性 {os.path.basename(file_path)}: {e}")
        return True
def compress_single_cdf(src_file, gzip_level=5):
    """
    核心压缩逻辑：就地生成临时文件，成功后替换
    """
    tmp_file = src_file[:-4] + "_compressed.cdf"
    print(f"开始压缩[{os.path.basename(src_file)}] ...",end='\r')
    start_time = time.time()
    
    try:
        original_size = os.path.getsize(src_file)
        with pycdf.CDF(src_file) as cdf_old:
            if "IS_COMPRESSED_BY_USER" in cdf_old.attrs:
                print(f"\n\033[1;33m警告\033[0m: 文件已标记为用户压缩过，跳过 {os.path.basename(src_file)}")
                return False
            with pycdf.CDF(tmp_file, '') as cdf_new:
                # 1. 复制全局属性
                cdf_new.attrs = cdf_old.attrs
                
                # 2. 遍历并复制变量
                for var_name in cdf_old:
                    old_var = cdf_old[var_name]
                    
                    # 写入变量并应用指定级别的 GZIP 压缩
                    if not old_var.rv() and old_var.type() == pycdf.const.CDF_CHAR:
                    # 对于非记录变量的字符串类型，直接复制数据和属性，不进行压缩
                        new_var = cdf_new.new(
                            name=var_name,
                            data=old_var[...],
                            type=old_var.type(),
                            recVary=old_var.rv(),
                            dimVarys=old_var.dv(),
                            dims=old_var.shape,
                        )
                        new_var.attrs = old_var.attrs
                        continue
                    new_var = cdf_new.new(
                        name=var_name,
                        data=old_var[...],
                        type=old_var.type(),
                        recVary=old_var.rv(),
                        dimVarys=old_var.dv(), # 明确复制维度变动属性
                        dims=old_var.shape if not old_var.rv() else old_var.shape[1:], 
                        compress=pycdf.const.GZIP_COMPRESSION,
                        compress_param=gzip_level
                    )
                    # 3. 复制变量属性
                    cdf_new[var_name].attrs = old_var.attrs
                cdf_new.attrs['IS_COMPRESSED_BY_USER'] = 1
        
        # 严格验证：确保新文件确实存在且大小大于 0 字节
        time.sleep(0.1)
        if os.path.exists(tmp_file) and os.path.getsize(tmp_file) > 0:
            # 安全替换：删除旧文件并将 tmp_file 改名为 src_file
            new_size = os.path.getsize(tmp_file)
            duration = time.time() - start_time
            if new_size >= original_size:
                os.remove(tmp_file)
                print(f"\n\033[1;33m警告\033[0m: 压缩后文件大小未减少，跳过替换 {os.path.basename(src_file)} 耗时: {duration:.2f}s")
                return False
            os.replace(tmp_file, src_file)
            # ratio = (1 - new_size / original_size) * 100
            print(f"[{os.path.basename(src_file)}]压缩完成，{original_size/1024/1024:.2f}MB -> {new_size/1024/1024:.2f}MB 耗时: {duration:.2f}s")
            return True
        else:
            os.remove(tmp_file)
            raise IOError("生成的临时压缩文件异常或大小为0")
            
    except Exception as e:
        print(f"\n\033[1;31m错误\033[0m: 压缩文件失败 {os.path.basename(src_file)}: {e}")
        raise e
        # 清理可能生成的残余临时文件
        if os.path.exists(tmp_file):
            os.remove(tmp_file)
        return False
def batch_compress_cdf_files(root_directory, min_size_mb=100, gzip_level_threshold=5):
    """
    遍历目录，过滤并对所有符合要求的 CDF 文件进行就地压缩替换
    :param root_directory: 目标根目录
    :param min_size_mb: 触发压缩的文件大小阈值（单位：MB）
    :param gzip_level_threshold: 触发压缩的 GZIP 等级阈值
    """
    if not os.path.exists(root_directory):
        print(f"错误: 路径 '{root_directory}' 不存在。")
        return

    min_size_bytes = min_size_mb * 1024 * 1024
    print(f"开始扫描并压缩数据集...")
    print(f"配置阈值 -> 文件大小 >= {min_size_mb} MB | GZIP 级别限制 < {gzip_level_threshold}\n")

    # 1. 第一步：先收集所有符合基础条件的 .cdf 文件（为了配合 tqdm 优雅显示进度条）
    cdf_tasks = []
    for root, _, files in os.walk(root_directory):
        for filename in files:
            if filename.endswith(".cdf") and not filename.endswith(".compressed.cdf"):
                file_path = os.path.join(root, filename)
                try:
                    # 过滤大小
                    if os.path.getsize(file_path) >= min_size_bytes:
                        cdf_tasks.append(file_path)
                except Exception:
                    continue
    if not cdf_tasks:
        print("未找到符合大小阈值的待处理 CDF 文件。")
        return
    # 2. 第二步：执行带进度条的循环处理
    success_count = 0
    skip_count = 0
    # pbar = tqdm(cdf_tasks, desc="正在处理科学数据集", unit="file")
    for file_path in cdf_tasks:
        # 更新进度条描述信息
        # pbar.set_postfix_str(f"当前: {os.path.basename(file_path)[:30]}")
        
        # 检查压缩状态
        if check_if_compressed(file_path, gzip_level_threshold):
            skip_count += 1
            continue
            
        # 执行就地压缩替换
        if compress_single_cdf(file_path, gzip_level=gzip_level_threshold):
            success_count += 1
        else:
            # 错误信息已在子函数中打印
            pass

    print("\n" + "="*40)
    print("批处理任务执行完毕！")
    print(f"成功压缩并替换: \033[1;32m{success_count}\033[0m 个文件")
    print(f"因条件不符跳过: \033[1;34m{skip_count}\033[0m 个文件")
    print("="*40)

if __name__ == "__main__":
    # 在这里传入你的自定义控制参数
    # 示例：只有大于 100MB 且 GZIP 级别低于 5 的文件才会被处理
    batch_compress_cdf_files(
        root_directory=save_dir, 
        min_size_mb=300,
        gzip_level_threshold=5
    )