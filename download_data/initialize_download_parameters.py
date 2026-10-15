"""生成完整的 TOML 配置模板；不会覆盖已有配置，也不读取 INI。"""
from __future__ import annotations

import argparse
from copy import deepcopy
from pathlib import Path
import sys

_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from config.config import DEFAULTS, EXAMPLE_PATH, TOML_PATH, load_config

DEFAULT_CONFIG_PATH = TOML_PATH


def build_config():
    """Return a fresh dictionary containing every supported configuration key."""
    return deepcopy(DEFAULTS)


def generate_config(output_path=None):
    """Create a TOML file exclusively; never replace existing local settings."""
    output_path = Path(output_path) if output_path is not None else DEFAULT_CONFIG_PATH
    if output_path.suffix.lower() != ".toml":
        raise ValueError("Configuration output must be a .toml file")
    text = EXAMPLE_PATH.read_text(encoding="utf-8")
    # Validate the authoritative template before writing it.
    load_config(EXAMPLE_PATH)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("x", encoding="utf-8") as file:
        file.write(text)
    return str(output_path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", help="输出 TOML 路径；默认为 config/settings.toml")
    args = parser.parse_args(argv)
    try:
        output = generate_config(args.output)
    except FileExistsError:
        parser.exit(1, "配置已存在，未覆盖；请直接编辑已有 TOML 文件。\n")
    print(f"已创建配置模板：{output}；请按本机环境修改路径和下载设置。")


if __name__ == "__main__":
    main()
