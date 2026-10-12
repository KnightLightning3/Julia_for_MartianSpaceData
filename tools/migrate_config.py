"""一次性迁移工具（P1）：将旧 INI 配置转换为 TOML 格式。

用法示例::

    # dry-run：只打印将要生成的 TOML，不写文件
    python tools/migrate_config.py

    # 实际写入（目标不存在时）
    python tools/migrate_config.py --apply

    # 覆盖已有目标
    python tools/migrate_config.py --apply --force
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Ensure the project root is on sys.path so `config` package is importable
# regardless of CWD.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from config.config import (  # noqa: E402
    DEFAULTS,
    _read_legacy_ini,
    load_config,
)


def _dump_toml(cfg: dict) -> str:
    """Serialize a normalized config dict to TOML text.

    Produces output structurally identical to settings.example.toml.
    Only uses stdlib (no tomli_w dependency). The result is guaranteed
    to round-trip through ``tomllib.loads``.
    """
    lines: list[str] = []

    # --- [paths] ---
    lines.append("# MAVEN/TW/MGS 数据根路径（决策 D2：三任务分别配置根目录）")
    lines.append("[paths]")
    p = cfg["paths"]
    lines.append(f'maven_data_root = "{p["maven_data_root"]}"')
    lines.append(f'tw_data_root = "{p["tw_data_root"]}"')
    lines.append(f'mgs_data_root = "{p["mgs_data_root"]}"')
    lines.append("")

    # --- [server] ---
    lines.append("[server]")
    s = cfg["server"]
    lines.append(f"index = {int(s['index'])}")
    urls = s["urls"]
    if len(urls) == 0:
        lines.append("urls = []")
    else:
        lines.append("urls = [")
        for u in urls:
            lines.append(f'  "{u}",')
        lines.append("]")
    lines.append("")

    # --- [download] ---
    lines.append("[download]")
    dl = cfg["download"]
    lines.append(f'mode = "{dl["mode"]}"')
    lines.append(f"threads = {int(dl['threads'])}")
    cont = "true" if dl["continue"] else "false"
    lines.append(f"continue = {cont}")
    lines.append("")

    # --- [window] ---
    lines.append("[window]")
    w = cfg["window"]
    lines.append(f'start = "{w["start"]}"')
    lines.append(f'end = "{w["end"]}"')
    lines.append("")  # trailing newline

    return "\n".join(lines)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Migrate legacy MAVEN_download_config.ini to TOML format.",
    )
    parser.add_argument(
        "--input",
        default=str(_PROJECT_ROOT / "download_data" / "MAVEN_download_config.ini"),
        help="Path to legacy INI file (default: download_data/MAVEN_download_config.ini)",
    )
    parser.add_argument(
        "--output",
        default=str(_PROJECT_ROOT / "config" / "settings.toml"),
        help="Path to output TOML file (default: config/settings.toml)",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually write the output file (default: dry-run, print only)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Allow overwriting an existing output file (only with --apply)",
    )
    args = parser.parse_args(argv)

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.exists():
        print(f"ERROR: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    # Read and normalize from legacy INI
    cfg_dict = _read_legacy_ini(input_path)
    toml_text = _dump_toml(cfg_dict)

    if not args.apply:
        # Dry-run: print what would be written
        print(f"[dry-run] Would write to: {output_path}")
        print("--- BEGIN TOML ---")
        print(toml_text, end="")
        print("--- END TOML ---")
        return

    # --apply mode
    if output_path.exists() and not args.force:
        print(
            f"ERROR: output file already exists: {output_path}\n"
            "Use --force to overwrite.",
            file=sys.stderr,
        )
        sys.exit(1)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(toml_text, encoding="utf-8")
    print(f"SUCCESS: wrote {output_path}")


if __name__ == "__main__":
    main()
