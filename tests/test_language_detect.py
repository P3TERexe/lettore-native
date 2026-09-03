import unittest

from backend.language_detect import detect


class TestLanguageDetect(unittest.TestCase):
    def test_latin_languages(self):
        self.assertEqual(detect("Ciao a tutti, questo è un testo in italiano."), "it")
        self.assertEqual(detect("The quick brown fox jumps over the lazy dog."), "en")
        self.assertEqual(detect("El perro corre por el parque con una pelota."), "es")
        self.assertEqual(
            detect("Bonjour le monde, ceci est un test dans la langue française."), "fr"
        )
        self.assertEqual(detect("Guten Tag, das ist ein Test mit der deutschen Sprache."), "de")
        self.assertEqual(detect("Olá a todos, este é um teste em português."), "pt")

    def test_non_latin_scripts(self):
        self.assertEqual(detect("Привет мир, это тест на русском языке."), "ru")
        self.assertEqual(detect("こんにちは世界"), "ja")
        self.assertEqual(detect("안녕하세요 세계"), "ko")
        self.assertEqual(detect("مرحبا بالعالم"), "ar")
        self.assertEqual(detect("Γειά σου κόσμε"), "el")

    def test_short_or_empty_text(self):
        self.assertIsNone(detect(""))
        self.assertIsNone(detect("abc"))
        self.assertIsNone(detect("1234"))


if __name__ == "__main__":
    unittest.main()
