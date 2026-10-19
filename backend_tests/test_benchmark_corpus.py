import importlib.util
import json
import sys
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "benchmarks" / "tts_corpus_it.jsonl"


def load_script(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class TestTTSCorpus(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.items = []
        with CORPUS.open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                line = line.strip()
                if not line:
                    continue
                item = json.loads(line)
                item["_line"] = line_number
                cls.items.append(item)

    def test_ids_are_unique_and_well_formed(self) -> None:
        ids = [item["id"] for item in self.items]
        self.assertEqual(len(ids), len(set(ids)))
        for item in self.items:
            self.assertRegex(item["id"], r"^[a-z]+-\d{2}$")

    def test_every_item_has_content(self) -> None:
        for item in self.items:
            self.assertTrue(item["text"].strip(), item["id"])
            self.assertTrue(item["category"].strip(), item["id"])
            self.assertNotRegex(item["text"], r"[\x00-\x08\x0b\x0c\x0e-\x1f]")

    def test_corpus_covers_expected_categories(self) -> None:
        counts = Counter(item["category"] for item in self.items)
        self.assertEqual(len(self.items), 28)
        for category in (
            "short",
            "medium",
            "long",
            "numbers",
            "abbreviations",
            "punctuation",
            "multilingual",
            "stress",
            "dialogue",
        ):
            self.assertGreaterEqual(counts[category], 2, category)

    def test_numeric_and_abbreviation_items_have_spoken_reference(self) -> None:
        for item in self.items:
            if item["category"] in {"numbers", "abbreviations"}:
                self.assertTrue(item.get("asr_reference"), item["id"])

    def test_markdown_view_contains_every_id(self) -> None:
        markdown = (ROOT / "benchmarks" / "tts_corpus_it.md").read_text(encoding="utf-8")
        for item in self.items:
            self.assertIn(f"`{item['id']}`", markdown)

    def test_benchmark_loader_reads_the_same_ids(self) -> None:
        module = load_script("tts_benchmark_fixture", ROOT / "scripts" / "tts_benchmark.py")
        loaded_ids = [item.id for item in module.load_corpus(CORPUS)]
        self.assertEqual(loaded_ids, [item["id"] for item in self.items])

    def test_texts_fit_backend_limit(self) -> None:
        for item in self.items:
            self.assertIsInstance(item["text"], str)
            self.assertLessEqual(len(item["text"]), 20000, item["id"])


if __name__ == "__main__":
    unittest.main()
