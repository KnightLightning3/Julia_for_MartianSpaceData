"""Small offline checks for the shared Documenter/Wiki page manifest."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
import tomllib


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "docs" / "pages.toml"
with MANIFEST_PATH.open("rb") as manifest_file:
    MANIFEST = tomllib.load(manifest_file)

SPEC = importlib.util.spec_from_file_location(
    "push_wiki", ROOT / "tools" / "push_wiki.py"
)
assert SPEC and SPEC.loader
push_wiki = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(push_wiki)


class DocsToolingTests(unittest.TestCase):
    def test_manifest_sources_and_unique_wiki_slugs(self) -> None:
        pages = MANIFEST["pages"]
        sources = [page["source"] for page in pages]
        slugs = [page["wiki"] for page in pages if page["wiki"]]
        self.assertEqual(len(sources), len(set(sources)))
        self.assertEqual(len(slugs), len(set(slugs)))
        for source in sources:
            with self.subTest(source=source):
                self.assertTrue((ROOT / "docs" / "src" / source).is_file())

    def test_manifest_matches_documenter_sources_and_wiki_mapping(self) -> None:
        pages = MANIFEST["pages"]
        manifest_sources = {page["source"] for page in pages}
        actual_sources = {path.name for path in (ROOT / "docs" / "src").glob("*.md")}
        self.assertEqual(actual_sources, manifest_sources)

        titles = [page["title"] for page in pages]
        self.assertTrue(all(title.strip() for title in titles))
        self.assertEqual(len(titles), len(set(titles)))

        self.assertEqual(set(push_wiki.PAGE_MAP), manifest_sources)
        for page in pages:
            expected_slug = page["wiki"] or "home"
            with self.subTest(source=page["source"]):
                self.assertEqual(push_wiki.PAGE_MAP[page["source"]], expected_slug)
        generated_slugs = {page["wiki"] for page in pages if page["wiki"]}
        self.assertEqual(
            {slug for slug in push_wiki.PAGE_MAP.values() if slug != "home"},
            generated_slugs,
        )

    def test_existing_wiki_slugs_are_preserved(self) -> None:
        expected = {
            "pipeline.md": "项目执行流程",
            "data_reading.md": "MAVEN数据读取",
            "data_format.md": "MAVEN_data_format",
            "swia_electron.md": "swia_electron_correlated",
            "api.md": "程序与函数Wiki",
        }
        self.assertEqual(
            {source: push_wiki.PAGE_MAP[source] for source in expected}, expected
        )

    def test_rewrite_new_pages_anchors_and_index_home(self) -> None:
        text = (
            "[架构](architecture.md#目录) [迁移](migration.md#步骤) "
            "[首页](index.md#概览)"
        )
        rewritten, changes = push_wiki.rewrite_page_links(text)
        self.assertEqual(
            rewritten,
            "[架构](项目架构#目录) [迁移](迁移指南#步骤) [首页](home#概览)",
        )
        self.assertEqual(len(changes), 3)

    def test_rewrite_inline_math_preserves_math_and_code(self) -> None:
        source = (
            "Terms ``E = mc^2`` and ``\\alpha + β``; "
            "keep `literal ``ticks`` here` and ``x_i``.\n"
        )
        expected = (
            "Terms $`E = mc^2`$ and $`\\alpha + β`$; "
            "keep `literal ``ticks`` here` and $`x_i`$.\n"
        )
        self.assertEqual(push_wiki.rewrite_inline_math(source), expected)

    def test_rewrite_inline_math_leaves_fenced_examples_unchanged(self) -> None:
        source = (
            "```julia\n"
            "value = ``not math``\n"
            "```\n"
            "~~~text\n"
            "example ``also unchanged``\n"
            "~~~\n"
            "Outside ``converted``.\n"
        )
        expected = source.replace("Outside ``converted``.", "Outside $`converted`$.")
        self.assertEqual(push_wiki.rewrite_inline_math(source), expected)

    def test_generate_checks_all_cross_page_links(self) -> None:
        pages = push_wiki.generate()
        self.assertEqual(push_wiki.check_links(pages), [])

    def test_dry_run_preserves_unrelated_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            out = Path(temporary) / "preview"
            out.mkdir()
            unrelated = out / "keep.txt"
            unrelated.write_text("user data", encoding="utf-8")
            push_wiki.run_dry(
                {
                    "sample.md": {
                        "text": "# Sample\n",
                        "source": "test",
                        "rewrites": [],
                    }
                },
                str(out),
            )
            self.assertEqual(unrelated.read_text(encoding="utf-8"), "user data")
            self.assertEqual((out / "sample.md").read_text(encoding="utf-8"), "# Sample\n")


if __name__ == "__main__":
    unittest.main()
