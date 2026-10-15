"""通用辅助函数（P2）：供 download_data 各脚本共享的纯函数。"""


def read_last_line_large_file(filename):
    """从文件末尾分块读取最后一行，避免载入整个大文件。"""
    with open(filename, 'r', encoding='utf-8') as f:
        f.seek(0, 2)
        file_size = f.tell()
        block = 10240
        last_line = ''
        for pos in range(file_size, 0, -block):
            if pos < block:
                f.seek(0)
            else:
                f.seek(pos - block)
            data = f.read(min(block, pos))
            if '\n' in data:
                last_line = data.splitlines()[-1]
                break
        else:
            f.seek(0)
            last_line = f.read()
    return last_line
