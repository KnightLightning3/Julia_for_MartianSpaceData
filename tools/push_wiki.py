#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 docs/src/*.md 发布为 GitLab Wiki 页面。

背景：GitLab Wiki 是一个**独立的 Git 仓库**（``<project>.wiki.git``），
所以"更新 Wiki 网页"等价于向该仓库推送提交。本脚本以 ``docs/src/`` 为唯一文档源，
生成 Wiki 页面（自动把 ``[文本](page.md)`` 形式的跨页链接改写为 Wiki 页面名），
再推送到 Wiki 仓库；Wiki 专属的首页与侧边栏取自 ``docs/wiki/``。

用法::

    python tools/push_wiki.py --dry-run          # 生成到临时目录、自检链接，不推送
    python tools/push_wiki.py --push             # 生成、提交并推送
    python tools/push_wiki.py --push -m "..."    # 自定义提交信息
    python tools/push_wiki.py --dry-run --out DIR

输出目录/克隆目录可用 ``--out`` / ``--workdir`` 指定；默认都在系统临时目录下。
推送默认使用 SSH 远端（``git@git.ustc.edu.cn:…wiki.git``）；改用 HTTPS 需 ``--remote``
指定，此时依赖 Git Credential Manager 或访问令牌等交互式凭据。
退出码：0 成功；1 链接自检失败或 git 操作失败。
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path
import tomllib

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "docs" / "src"
WIKI_DIR = ROOT / "docs" / "wiki"
PAGES_FILE = ROOT / "docs" / "pages.toml"

# 默认走 SSH（与主仓库的 `ustc` remote 同源，无需交互式凭据）。
# 需要 HTTPS 时用：--remote https://git.ustc.edu.cn/KnightLightning/Julia_for_MartianSpaceData.wiki.git
DEFAULT_REMOTE = (
    "git@git.ustc.edu.cn:KnightLightning/Julia_for_MartianSpaceData.wiki.git"
)
BRANCH = "main"
DEFAULT_MESSAGE = "docs: 从 docs/src 同步 Wiki 页面"

# Compatibility map: docs/src 文件名 -> Wiki 页面名。首页留空的页面仍
# 映射为 Wiki 的 home 链接，但不会从 src/index.md 生成重复页面。
with PAGES_FILE.open("rb") as _pages_file:
    PAGE_ENTRIES = tomllib.load(_pages_file)["pages"]
PAGE_MAP = {
    entry["source"]: (entry["wiki"] or "home") for entry in PAGE_ENTRIES
}
GENERATED_PAGE_ENTRIES = [entry for entry in PAGE_ENTRIES if entry["wiki"]]

# docs/wiki 下手工维护的 Wiki 专属页
MANUAL_MAP = {
    "home.md": "home",
    "_sidebar.md": "_sidebar",
}

BANNER = (
    "> 本页由仓库 `{source}` 生成（`python tools/push_wiki.py --push`）；"
    "请修改源文件，不要直接在 Wiki 界面编辑。\n"
)

# 只改写指向 docs/src 页面的相对链接；带锚点时保留锚点
PAGE_LINK_RE = re.compile(r"\]\(([^)\s]+?)\.md((?:#[^)\s]*)?)\)")
ANY_LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)\)")
WIKI_SUFFIXES = {".md", ".markdown", ".mkd", ".mkdn", ".mdown"}
FENCE_OPEN_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
FENCE_CLOSE_RE = re.compile(r"^ {0,3}(`+|~+)[ \t]*$")


def norm_newlines(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _rewrite_inline_math_line(line: str) -> str:
    """Convert double-backtick math spans, preserving single-backtick code spans."""
    result: list[str] = []
    index = 0
    while index < len(line):
        if line[index] != "`":
            result.append(line[index])
            index += 1
            continue

        run_end = index + 1
        while run_end < len(line) and line[run_end] == "`":
            run_end += 1
        run_length = run_end - index
        if run_length not in (1, 2):
            result.append(line[index:run_end])
            index = run_end
            continue

        closing = run_end
        close_start = close_end = -1
        while closing < len(line):
            next_tick = line.find("`", closing)
            if next_tick < 0:
                break
            next_end = next_tick + 1
            while next_end < len(line) and line[next_end] == "`":
                next_end += 1
            if next_end - next_tick == run_length:
                close_start, close_end = next_tick, next_end
                break
            closing = next_end

        if close_start < 0:
            result.append(line[index:])
            break

        if run_length == 1:
            result.append(line[index:close_end])
        else:
            result.extend(("$`", line[run_end:close_start], "`$"))
        index = close_end

    return "".join(result)


def rewrite_inline_math(text: str) -> str:
    """Convert Documenter ``inline math`` to GitLab math outside fenced blocks.

    Fenced code blocks opened by at least three backticks or tildes are copied
    verbatim. Within prose, only paired double-backtick spans are converted;
    single-backtick code spans and other backtick runs remain unchanged.
    """
    output: list[str] = []
    fence_char: str | None = None
    fence_length = 0

    for line in text.splitlines(keepends=True):
        body = line.rstrip("\r\n")
        ending = line[len(body):]
        if fence_char is not None:
            output.append(line)
            closing = FENCE_CLOSE_RE.match(body)
            if (
                closing
                and closing.group(1)[0] == fence_char
                and len(closing.group(1)) >= fence_length
            ):
                fence_char = None
                fence_length = 0
            continue

        opening = FENCE_OPEN_RE.match(body)
        if opening:
            marker = opening.group(1)
            fence_char, fence_length = marker[0], len(marker)
            output.append(line)
            continue

        output.append(_rewrite_inline_math_line(body) + ending)

    return "".join(output)


def rewrite_page_links(text: str) -> tuple[str, list[str]]:
    """把文档相对链接改写为 Wiki 页面名，保留锚点。"""
    rewrites: list[str] = []

    def _sub(match: re.Match[str]) -> str:
        target, anchor = match.group(1), match.group(2) or ""
        page = PAGE_MAP.get(f"{target}.md")
        if page is None:
            return match.group(0)
        rewrites.append(f"{target}.md -> {page}{anchor}")
        return f"]({page}{anchor})"

    return PAGE_LINK_RE.sub(_sub, text), rewrites


def add_banner(text: str, source: str) -> str:
    """在首个一级标题之后插入“本页为生成产物”的说明。"""
    banner = BANNER.format(source=source)
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.startswith("# "):
            return "".join(lines[: index + 1]) + "\n" + banner + "".join(lines[index + 1 :])
    return banner + "\n" + text


def generate() -> dict[str, dict]:
    """生成 ``{文件名: {text, source, rewrites}}``。"""
    pages: dict[str, dict] = {}

    for entry in GENERATED_PAGE_ENTRIES:
        source_name = entry["source"]
        page_name = entry["wiki"]
        source = SRC_DIR / source_name
        if not source.is_file():
            raise SystemExit(f"[error] 缺少文档源：{source}")
        text = norm_newlines(source.read_text(encoding="utf-8"))
        text = rewrite_inline_math(text)
        text, rewrites = rewrite_page_links(text)
        text = add_banner(text, f"docs/src/{source_name}")
        if not text.endswith("\n"):
            text += "\n"
        pages[f"{page_name}.md"] = {
            "text": text,
            "source": f"docs/src/{source_name}",
            "rewrites": rewrites,
        }

    for source_name, page_name in MANUAL_MAP.items():
        source = WIKI_DIR / source_name
        if not source.is_file():
            raise SystemExit(f"[error] 缺少 Wiki 专属页：{source}")
        text = norm_newlines(source.read_text(encoding="utf-8"))
        if not text.endswith("\n"):
            text += "\n"
        pages[f"{page_name}.md"] = {
            "text": text,
            "source": f"docs/wiki/{source_name}",
            "rewrites": [],
        }

    return pages


def check_links(pages: dict[str, dict]) -> list[str]:
    """确认所有站内相对链接都指向已生成的 Wiki 页面。"""
    known = {Path(name).stem for name in pages}
    problems: list[str] = []
    for name in sorted(pages):
        for target in ANY_LINK_RE.findall(pages[name]["text"]):
            if target.startswith(("http://", "https://", "mailto:", "#", "/")):
                continue
            slug = target.split("#", 1)[0]
            # Relative source/assets (for example ``../../src/module.jl``) are
            # not Wiki pages. Validate Markdown pages and extensionless Wiki
            # slugs, which are the targets produced by rewrite_page_links.
            suffix = Path(slug).suffix.lower()
            if suffix and suffix not in WIKI_SUFFIXES:
                continue
            if slug not in known:
                problems.append(f"{name}: 链接目标 “{target}” 不是已生成的 Wiki 页面")
    return problems


def git(args: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(
        ["git", *args],
        cwd=str(cwd),
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    if check and result.returncode != 0:
        raise SystemExit(
            f"[error] git {' '.join(args)} 失败（exit {result.returncode}）：\n"
            f"{result.stdout}{result.stderr}"
        )
    return result


def run_dry(pages: dict[str, dict], out_dir: str | None) -> Path:
    out = Path(out_dir).expanduser().resolve() if out_dir else Path(
        tempfile.mkdtemp(prefix="mvn-wiki-preview-")
    )
    out.mkdir(parents=True, exist_ok=True)
    for name, page in pages.items():
        (out / name).write_text(page["text"], encoding="utf-8", newline="\n")

    print(f"[dry-run] 生成 {len(pages)} 个 Wiki 文件 -> {out}")
    for name in sorted(pages):
        page = pages[name]
        note = f"，改写跨页链接 {len(page['rewrites'])} 处" if page["rewrites"] else ""
        size = len(page["text"].encode("utf-8"))
        print(f"  {name:<30} <- {page['source']} ({size} B{note})")
        for item in page["rewrites"]:
            print(f"      link: {item}")
    return out


def push(
    pages: dict[str, dict],
    remote: str,
    workdir: str | None,
    message: str,
    prune: bool,
) -> Path:
    work = (
        Path(workdir).expanduser().resolve()
        if workdir
        else Path(tempfile.gettempdir()) / "Julia_for_MartianSpaceData.wiki"
    )

    if (work / ".git").is_dir():
        print(f"[push] 更新本地克隆：{work}")
        git(["fetch", "--quiet", "origin", BRANCH], work)
        git(["reset", "--hard", "--quiet", f"origin/{BRANCH}"], work)
        git(["clean", "-fdq"], work)
    else:
        print(f"[push] 克隆 {remote}")
        work.parent.mkdir(parents=True, exist_ok=True)
        git(["clone", "--quiet", remote, str(work)], work.parent)

    known = set(pages)
    existing = {
        item.name
        for item in work.iterdir()
        if item.is_file() and item.suffix.lower() in WIKI_SUFFIXES
    }
    extras = sorted(existing - known)
    if extras:
        if prune:
            for name in extras:
                (work / name).unlink()
            print(f"[push] 已删除远端多余页面：{', '.join(extras)}")
        else:
            print(f"[push] 提示：远端另有页面（未删除，如需清理请加 --prune）：{', '.join(extras)}")

    for name, page in pages.items():
        (work / name).write_text(page["text"], encoding="utf-8", newline="\n")

    git(["add", "-A"], work)
    staged = git(["diff", "--cached", "--name-only"], work).stdout.strip()
    if not staged:
        print("[push] 远端内容已与生成结果一致，无需提交。")
        return work
    print("[push] 变更文件：" + "、".join(staged.splitlines()))
    git(["commit", "--quiet", "-m", message], work)
    git(["push", "--quiet", "origin", BRANCH], work)
    print(f"[push] 推送完成 -> {remote} ({BRANCH})")
    return work


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="从 docs/src 生成 GitLab Wiki 页面并（可选）推送"
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--dry-run", action="store_true", help="只生成到临时目录并自检链接，不推送（默认）"
    )
    mode.add_argument("--push", action="store_true", help="生成、提交并推送到 Wiki 仓库")
    parser.add_argument("--out", help="--dry-run 的输出目录（默认系统临时目录）")
    parser.add_argument("--workdir", help="Wiki 仓库本地克隆目录（默认系统临时目录）")
    parser.add_argument("--remote", default=DEFAULT_REMOTE, help="Wiki 仓库地址")
    parser.add_argument("-m", "--message", default=DEFAULT_MESSAGE, help="提交信息")
    parser.add_argument(
        "--prune", action="store_true", help="删除远端不在生成集中的 Wiki 页面"
    )
    args = parser.parse_args(argv)

    pages = generate()
    problems = check_links(pages)
    for problem in problems:
        print(f"[warn] {problem}")
    if problems:
        print("[error] 链接自检失败，已中止。")
        return 1
    print(f"[ok] {len(pages)} 个 Wiki 页面生成完毕，站内链接自检通过。")

    if args.push:
        push(pages, args.remote, args.workdir, args.message, args.prune)
    else:
        run_dry(pages, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
