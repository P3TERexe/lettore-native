import unittest

from backend.chunking import smart_chunk_text, split_into_paragraphs, split_into_sentences


class TestChunking(unittest.TestCase):
    def test_abbreviation_preservation_italian(self):
        text = "Il Dott. Rossi ha pagato 12.50 euro per il consulto. Questo è un test."
        sentences = split_into_sentences(text, lang="it")
        self.assertEqual(len(sentences), 2)
        self.assertEqual(sentences[0], "Il Dott. Rossi ha pagato 12.50 euro per il consulto.")
        self.assertEqual(sentences[1], "Questo è un test.")

    def test_abbreviation_preservation_english(self):
        text = "Mr. Smith arrived at 9:30 a.m. today. He visited p. 55 of the manual."
        sentences = split_into_sentences(text, lang="en")
        self.assertEqual(len(sentences), 2)
        self.assertEqual(sentences[0], "Mr. Smith arrived at 9:30 a.m. today.")
        self.assertEqual(sentences[1], "He visited p. 55 of the manual.")

    def test_split_into_paragraphs(self):
        text = "Primo paragrafo.\n\nSecondo paragrafo.\n\nTerzo paragrafo."
        paras = split_into_paragraphs(text)
        self.assertEqual(len(paras), 3)
        self.assertEqual(paras[0], "Primo paragrafo.")
        self.assertEqual(paras[1], "Secondo paragrafo.")
        self.assertEqual(paras[2], "Terzo paragrafo.")

    def test_smart_chunk_text_with_split_paragraphs(self):
        text = "Primo paragrafo.\n\nSecondo paragrafo con più testo."
        chunks = smart_chunk_text(text, lang="it", split_paragraphs=True)
        self.assertEqual(len(chunks), 2)
        self.assertEqual(chunks[0], "Primo paragrafo.")
        self.assertEqual(chunks[1], "Secondo paragrafo con più testo.")

    def test_smart_chunk_text_long_paragraph_subsplit(self):
        para = "Prima frase del lungo testo. Seconda frase del lungo testo. Terza frase del lungo testo."
        chunks = smart_chunk_text(para, lang="it", split_paragraphs=True, max_chunk_chars=40)
        self.assertGreater(len(chunks), 1)


if __name__ == "__main__":
    unittest.main()
