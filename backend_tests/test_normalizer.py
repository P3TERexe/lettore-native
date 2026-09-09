import unittest

from backend.textnorm import TextNormalizer


class TestTextNormalizer(unittest.TestCase):
    def test_filter_exclusions(self):
        text = "Ciao a tutti. Inviato da iPhone. Saluti cordiali."
        cleaned = TextNormalizer.filter_exclusions(text, ["Inviato da iPhone"])
        self.assertEqual(cleaned, "Ciao a tutti. Saluti cordiali.")

    def test_filter_exclusions_case_insensitive(self):
        text = "Documento importante.\n\nNOTE DI RISERVATEZZA: non divulgare.\nFine."
        cleaned = TextNormalizer.filter_exclusions(text, ["Note di riservatezza: non divulgare."])
        self.assertEqual(cleaned, "Documento importante.\n\nFine.")

    def test_abbreviations_italian(self):
        text = "Il Dott. Rossi e la Dott.ssa Bianchi con il Prof. Verdi e l'Avv. Neri."
        norm = TextNormalizer.normalize_italian(text)
        self.assertIn("Dottore", norm)
        self.assertIn("Dottoressa", norm)
        self.assertIn("Professore", norm)
        self.assertIn("Avvocato", norm)

    def test_currencies(self):
        text = "Il totale ammonta a 12.50€ oppure $ 10 o £ 5."
        norm = TextNormalizer.normalize_italian(text)
        self.assertIn("12 euro e 50 centesimi", norm)
        self.assertIn("10 dollari", norm)
        self.assertIn("5 sterline", norm)

    def test_urls_and_emails(self):
        text = "Visita http://example.com oppure scrivi a mario.rossi@azienda.it per info."
        norm = TextNormalizer.normalize_italian(text)
        self.assertIn("link example punto com", norm)
        self.assertIn("mario punto rossi chiocciola azienda punto it", norm)

    def test_times_and_ordinals(self):
        text = "La riunione è al 1° piano alle 14:30."
        norm = TextNormalizer.normalize_italian(text)
        self.assertIn("primo piano", norm)
        self.assertIn("14 e mezza", norm)

    def test_percentages_and_units(self):
        text = "Sconto del 20% su una distanza di 10 km e 5 kg."
        norm = TextNormalizer.normalize_italian(text)
        self.assertIn("20 percento", norm)
        self.assertIn("10 chilometri", norm)
        self.assertIn("5 chilogrammi", norm)

    def test_full_pipeline_with_exclusion(self):
        text = "Il Dott. Rossi pagò 12.50€ su http://example.com alle 14:30. Inviato da iPhone"
        res = TextNormalizer.normalize(
            text, lang="it", enabled=True, exclusions=["Inviato da iPhone"]
        )
        self.assertNotIn("Inviato da iPhone", res)
        self.assertIn("Dottore", res)
        self.assertIn("12 euro e 50 centesimi", res)
        self.assertIn("link example punto com", res)


if __name__ == "__main__":
    unittest.main()
