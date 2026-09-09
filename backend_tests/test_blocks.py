from __future__ import annotations

import unittest

from fastapi.testclient import TestClient

from backend.blocks.layout_analyzer import analyze_layout
from backend.blocks.models import BlockType, BoundingBox, DocumentModel, RawElement, TextBlock
from backend.main import create_app


class TestBlocksModule(unittest.TestCase):
    def test_models_instantiation(self):
        bbox = BoundingBox(x=10.0, y=20.0, width=300.0, height=50.0)
        block = TextBlock(
            id="block-1",
            type=BlockType.HEADING,
            text="Titolo Principale",
            clean_text="Titolo Principale",
            level=1,
            bbox=bbox,
            word_count=2,
            confidence=0.98,
            source="accessibility",
        )
        doc = DocumentModel(
            source="accessibility",
            app_name="Safari",
            total_blocks=1,
            blocks=[block],
        )
        self.assertEqual(doc.total_blocks, 1)
        self.assertEqual(doc.blocks[0].type, BlockType.HEADING)
        self.assertEqual(doc.blocks[0].level, 1)
        self.assertEqual(doc.blocks[0].word_count, 2)

    def test_analyze_layout_from_text(self):
        markdown_sample = (
            "# Benvenuti su Lettore\n\n"
            "Questo è il primo paragrafo dell'articolo con un importo di 12.50€ e dott. Rossi.\n\n"
            "• Primo punto della lista\n"
            "• Secondo punto della lista\n\n"
            "> Questa è una citazione importante.\n\n"
            "```\nprint('hello world')\n```"
        )
        doc = analyze_layout(text=markdown_sample, source="manual")
        self.assertGreaterEqual(doc.total_blocks, 4)

        # Blocco 1: Titolo
        self.assertEqual(doc.blocks[0].type, BlockType.HEADING)
        self.assertEqual(doc.blocks[0].text, "Benvenuti su Lettore")

        # Blocco 2: Paragrafo con normalizzazione fonetica
        self.assertEqual(doc.blocks[1].type, BlockType.PARAGRAPH)
        self.assertIn("euro", doc.blocks[1].clean_text)
        self.assertIn("dottore", doc.blocks[1].clean_text)

        # Blocco con citazione
        quote_blocks = [b for b in doc.blocks if b.type == BlockType.QUOTE]
        self.assertTrue(len(quote_blocks) >= 1)
        self.assertIn("Questa è una citazione importante.", quote_blocks[0].text)

    def test_analyze_layout_from_raw_elements(self):
        raw_elements = [
            RawElement(
                role="AXHeading",
                text="Introduzione all'Accessibilità",
                bbox=BoundingBox(x=50.0, y=100.0, width=500.0, height=40.0),
                confidence=1.0,
            ),
            RawElement(
                role="AXStaticText",
                text="Questo è il corpo del testo che spiega come navigare a blocchi.",
                bbox=BoundingBox(x=50.0, y=150.0, width=500.0, height=60.0),
                confidence=0.95,
            ),
            RawElement(
                role="AXStaticText",
                text="Seconda riga dello stesso paragrafo ravvicinata.",
                bbox=BoundingBox(x=50.0, y=215.0, width=500.0, height=20.0),
                confidence=0.96,
            ),
        ]
        doc = analyze_layout(raw_elements=raw_elements, app_name="TextEdit", source="accessibility")
        self.assertEqual(doc.app_name, "TextEdit")
        self.assertEqual(doc.source, "accessibility")
        # I due testi consecutivi ravvicinati devono essere uniti in un unico paragrafo
        self.assertEqual(doc.total_blocks, 2)
        self.assertEqual(doc.blocks[0].type, BlockType.HEADING)
        self.assertEqual(doc.blocks[1].type, BlockType.PARAGRAPH)
        self.assertIn("Seconda riga", doc.blocks[1].text)
        self.assertIsNotNone(doc.blocks[1].bbox)


class TestBlocksAPI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = create_app()
        cls.client = TestClient(app)

    def test_status_endpoint(self):
        resp = self.client.get("/v1/blocks/status")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertTrue(data.get("ok"))
        self.assertIn("ocr_available", data)

    def test_analyze_endpoint(self):
        payload = {
            "text": "# Titolo API\n\nParagrafo inviato via HTTP con 15.00€.",
            "app_name": "TestClient",
            "source": "manual",
        }
        resp = self.client.post("/v1/blocks/analyze", json=payload)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data.get("total_blocks"), 2)
        self.assertEqual(data["blocks"][0]["type"], "heading")
        self.assertIn("15 euro", data["blocks"][1]["clean_text"])


if __name__ == "__main__":
    unittest.main()
