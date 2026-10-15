"""P2 utils 单元测试（纯 assert + 手工 runner，与 test_p0.py 风格一致）。"""
import os
import sys
import shutil
import tempfile

# 确保项目根在 sys.path 中，以便导入 config.utils
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from config.utils import read_last_line_large_file


def test_read_last_line_large_file():
    tmpdir = tempfile.mkdtemp(prefix='p2_utils_test_')
    try:
        # 3 行临时文件，断言返回末行
        three_lines = os.path.join(tmpdir, 'three_lines.txt')
        with open(three_lines, 'w', encoding='utf-8') as f:
            f.write('line1\nline2\nline3\n')
        assert read_last_line_large_file(three_lines) == 'line3', \
            "Expected 'line3' as last line"

        # 无换行符的单行文件，断言返回整行
        single_line = os.path.join(tmpdir, 'single_line.txt')
        with open(single_line, 'w', encoding='utf-8') as f:
            f.write('only_one_line')
        assert read_last_line_large_file(single_line) == 'only_one_line', \
            "Expected full content for single-line file without newline"

        # 空文件，断言返回 ''
        empty_file = os.path.join(tmpdir, 'empty.txt')
        with open(empty_file, 'w', encoding='utf-8') as f:
            pass
        assert read_last_line_large_file(empty_file) == '', \
            "Expected empty string for empty file"
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == '__main__':
    tests = [
        ('test_read_last_line_large_file', test_read_last_line_large_file),
    ]
    passed = 0
    failed = 0
    for name, func in tests:
        try:
            func()
            print(f'PASS: {name}')
            passed += 1
        except Exception as e:
            print(f'FAIL: {name} -> {e}')
            failed += 1

    print(f'\nSummary: {passed} passed, {failed} failed')
    if failed > 0:
        sys.exit(1)
