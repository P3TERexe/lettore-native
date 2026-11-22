from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from fastapi.testclient import TestClient

from backend.engines.base import BaseTTSEngine
from backend.main import create_app
from backend.models import (
    CLIENT_CHUNK_MAX_CHARS,
    MAX_SENTENCE_CHARS,
    MAX_SENTENCE_CHARS_KO,
    REQUEST_TEXT_MAX_CHARS,
)
from backend.tts_manager import TTSManager


class RecordingEngine(BaseTTSEngine):
    def __init__(self) -> None:
        self.synthesized_texts: list[str] = []
        self.calls: list[tuple[str, str, str, int, float]] = []

    @property
    def sample_rate(self) -> int | None:
        return 24000

    @property
    def voice_names(self) -> list[str]:
        return ["M1", "F1"]

    @property
    def supported_languages(self) -> list[str]:
        return ["it", "en"]

    def load(self) -> None:
        pass

    def unload(self) -> None:
        pass

    def synthesize(
        self, text: str, voice: str, lang: str, steps: int, speed: float
    ) -> tuple[np.ndarray, float]:
        self.synthesized_texts.append(text)
        self.calls.append((text, voice, lang, steps, speed))
        return np.zeros(2400, dtype=np.float32), 0.1

    def discover_custom_voices(self, cache_dir: Path | None = None) -> list[str]:
        return []


class TestTTSChunkContract(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.engine = RecordingEngine()
        mock_tts = TTSManager(model="test", engine="supertonic")
        mock_tts._engine = self.engine
        mock_tts.ready = True
        self.app.state.tts = mock_tts
        self.client = TestClient(self.app)

    def test_client_sized_chunk_reaches_engine_unchanged(self):
        text = "parola " * 33 + "fine"
        self.assertLessEqual(len(text), CLIENT_CHUNK_MAX_CHARS)
        self.assertGreater(len(text), 150)

        resp = self.client.post(
            "/v1/tts",
            json={
                "text": text,
                "lang": "it",
                "voice": "M1",
                "normalize_text": False,
            },
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, [text])

    def test_external_client_keeps_backend_normalization_by_default(self):
        resp = self.client.post(
            "/v1/tts",
            json={"text": "Il prezzo è 15€.", "lang": "it", "voice": "M1"},
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, ["Il prezzo è 15 euro."])

    def test_removed_routes_are_not_exposed(self):
        self.assertEqual(self.client.get("/v1/queue").status_code, 404)
        self.assertEqual(self.client.get("/v1/blocks/status").status_code, 404)
        self.assertEqual(self.client.post("/v1/tts/export", json={"text": "ciao"}).status_code, 404)

    def test_runtime_config_applies_to_omitted_tts_fields(self):
        cfg = self.client.put(
            "/v1/config",
            json={
                "voice": "F1",
                "lang": "en",
                "speed": 1.5,
                "steps": 5,
                "normalize_text": False,
            },
        )
        self.assertEqual(cfg.status_code, 200)

        resp = self.client.post("/v1/tts", json={"text": "Il prezzo è 15€."})

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.calls, [("Il prezzo è 15€.", "F1", "en", 5, 1.5)])

    def test_speed_outside_engine_range_is_rejected(self):
        resp = self.client.post(
            "/v1/tts",
            json={"text": "ciao", "speed": 4.0},
        )

        self.assertEqual(resp.status_code, 422)

    def test_text_at_request_limit_is_accepted(self):
        text = ("Questa è una frase italiana di prova. " * 30)[:REQUEST_TEXT_MAX_CHARS]
        self.assertEqual(len(text), REQUEST_TEXT_MAX_CHARS)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "it", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, [text])

    def test_email_expansion_at_request_limit_is_rejected_before_engine(self):
        text = ("mario.rossi@example.com " * 42)[:REQUEST_TEXT_MAX_CHARS]
        self.assertEqual(len(text), REQUEST_TEXT_MAX_CHARS)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "it", "voice": "M1"},
        )

        self.assertEqual(resp.status_code, 422)
        self.assertIn("normalizzato troppo lungo", resp.json()["detail"])
        self.assertEqual(self.engine.calls, [])

    def test_unpunctuated_text_over_safe_sentence_is_rejected_before_engine(self):
        text = "parola " * 130
        self.assertLessEqual(len(text), REQUEST_TEXT_MAX_CHARS)
        self.assertGreater(len(text), MAX_SENTENCE_CHARS)
        self.assertNotIn(".", text)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "it", "voice": "M1"},
        )

        self.assertEqual(resp.status_code, 422)
        self.assertIn("frase troppo lunga", resp.json()["detail"])
        self.assertEqual(self.engine.calls, [])

    def test_single_sentence_at_safe_threshold_is_synthesized(self):
        text = "a" * MAX_SENTENCE_CHARS
        self.assertEqual(len(text), MAX_SENTENCE_CHARS)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "it", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, [text])

    def test_single_sentence_over_safe_threshold_is_rejected(self):
        text = "a" * (MAX_SENTENCE_CHARS + 1)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "it", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 422)
        self.assertIn("frase troppo lunga", resp.json()["detail"])
        self.assertEqual(self.engine.calls, [])

    def test_single_sentences_between_old_and_new_threshold_are_synthesized(self):
        for length in (301, 500):
            with self.subTest(length=length):
                self.engine.synthesized_texts.clear()
                self.engine.calls.clear()
                text = ("parola " * (length // 7 + 2))[:length]
                self.assertEqual(len(text), length)

                resp = self.client.post(
                    "/v1/tts",
                    json={
                        "text": text,
                        "lang": "it",
                        "voice": "M1",
                        "normalize_text": False,
                    },
                )

                self.assertEqual(resp.status_code, 200)
                self.assertEqual(self.engine.synthesized_texts, [text])

    def test_korean_sentence_over_language_threshold_is_rejected_before_engine(self):
        # Misura reale: una frase coreana da 500 caratteri fallisce nell'ONNX.
        text = "가" * 500
        self.assertGreater(len(text), MAX_SENTENCE_CHARS_KO)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "ko", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 422)
        self.assertIn("frase troppo lunga", resp.json()["detail"])
        self.assertEqual(self.engine.calls, [])

    def test_korean_sentence_at_language_threshold_is_synthesized(self):
        text = "가" * MAX_SENTENCE_CHARS_KO
        self.assertEqual(len(text), MAX_SENTENCE_CHARS_KO)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "ko", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, [text])

    def test_auto_lang_resolves_korean_text_before_guard(self):
        text = "가" * 500

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "auto", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 422)
        self.assertIn("frase troppo lunga", resp.json()["detail"])
        self.assertIn("'ko'", resp.json()["detail"])
        self.assertEqual(self.engine.calls, [])

    def test_na_lang_resolves_korean_text_before_guard(self):
        # `na` è il codice Auto pubblicato dal catalogo: non deve bypassare il
        # guard come faceva la sola risoluzione di `"auto"`.
        text = "가" * 500

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "na", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 422)
        self.assertIn("frase troppo lunga", resp.json()["detail"])
        self.assertIn("'ko'", resp.json()["detail"])
        self.assertEqual(self.engine.calls, [])

    def test_na_lang_korean_at_threshold_is_synthesized(self):
        text = "가" * MAX_SENTENCE_CHARS_KO
        self.assertEqual(len(text), MAX_SENTENCE_CHARS_KO)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "na", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, [text])
        # Il fix riguarda solo il guard: al motore arriva il `lang` originale.
        self.assertEqual(self.engine.calls[0][2], "na")

    def test_korean_lang_aliases_over_threshold_are_rejected(self):
        text = "가" * 500

        for lang in ("KO", "ko-KR"):
            with self.subTest(lang=lang):
                self.engine.calls.clear()
                self.engine.synthesized_texts.clear()

                resp = self.client.post(
                    "/v1/tts",
                    json={
                        "text": text,
                        "lang": lang,
                        "voice": "M1",
                        "normalize_text": False,
                    },
                )

                self.assertEqual(resp.status_code, 422)
                self.assertIn("frase troppo lunga", resp.json()["detail"])
                self.assertIn("'ko'", resp.json()["detail"])
                self.assertEqual(self.engine.calls, [])

    def test_italian_sentence_above_korean_threshold_is_synthesized(self):
        text = ("parola " * 100)[:500]
        self.assertEqual(len(text), 500)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "it", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, [text])

    def test_abbreviation_joined_text_over_safe_sentence_is_rejected(self):
        # `M.` è escluso dalle divisioni di supertonic: il testo resta un unico
        # chunk da 1000 caratteri e il motore ONNX fallirebbe.
        text = ("M. Rossi ha detto " * 60)[:REQUEST_TEXT_MAX_CHARS]
        self.assertEqual(len(text), REQUEST_TEXT_MAX_CHARS)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "it", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 422)
        self.assertIn("frase troppo lunga", resp.json()["detail"])
        self.assertEqual(self.engine.calls, [])

    def test_abbreviation_joined_text_under_safe_sentence_is_synthesized(self):
        text = ("M. Rossi ha detto " * 30)[:500]
        self.assertEqual(len(text), 500)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "it", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, [text])

    def test_short_email_is_normalized_and_synthesized(self):
        resp = self.client.post(
            "/v1/tts",
            json={
                "text": "Scrivici a mario.rossi@example.com per info.",
                "lang": "it",
                "voice": "M1",
            },
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(
            self.engine.synthesized_texts,
            ["Scrivici a mario punto rossi chiocciola example punto com per info."],
        )

    def test_engine_onnx_failure_maps_to_503(self):
        import onnxruntime as ort

        failure = ort.capi.onnxruntime_pybind11_state.Fail(
            "Non-zero status code returned while running Mul node"
        )

        with patch.object(self.engine, "synthesize", side_effect=failure):
            resp = self.client.post(
                "/v1/tts",
                json={"text": "ciao", "lang": "it", "voice": "M1"},
            )

        self.assertEqual(resp.status_code, 503)
        detail = resp.json()["detail"]
        self.assertIn("non disponibile", detail)
        self.assertNotIn("Non-zero status", detail)
        self.assertNotIn("ciao", detail)

    def test_engine_input_value_error_maps_to_400(self):
        with patch.object(self.engine, "synthesize", side_effect=ValueError("voce sconosciuta")):
            resp = self.client.post(
                "/v1/tts",
                json={"text": "ciao", "lang": "it", "voice": "M1"},
            )

        self.assertEqual(resp.status_code, 400)
        self.assertIn("voce sconosciuta", resp.json()["detail"])

    def test_wav_conversion_failure_maps_to_503(self):
        with patch(
            "backend.tts_manager.numpy_to_wav_bytes",
            side_effect=ValueError("forma non valida"),
        ):
            resp = self.client.post(
                "/v1/tts",
                json={"text": "ciao", "lang": "it", "voice": "M1"},
            )

        self.assertEqual(resp.status_code, 503)
        self.assertIn("non disponibile", resp.json()["detail"])
        self.assertNotIn("forma non valida", resp.json()["detail"])

    def test_text_over_request_limit_is_rejected_with_string_detail(self):
        resp = self.client.post(
            "/v1/tts",
            json={"text": "a" * (REQUEST_TEXT_MAX_CHARS + 1)},
        )

        self.assertEqual(resp.status_code, 422)
        detail = resp.json()["detail"]
        self.assertIsInstance(detail, str)
        self.assertIn("testo troppo lungo", detail)
        self.assertIn(str(REQUEST_TEXT_MAX_CHARS), detail)
        self.assertEqual(self.engine.calls, [])

    def test_multi_sentence_text_beyond_client_chunk_reaches_engine_unchanged(self):
        sentences = [
            "Questa è la prima frase di prova: serve solo a spingere il testo oltre il limite dei chunk prodotti dal client nativo.",
            "La seconda frase continua il discorso e aggiunge altri caratteri utili a verificare che il backend non riscriva il testo ricevuto.",
            "La terza frase insiste sullo stesso punto: nessun richunking, nessuna normalizzazione quando il client chiede di saltarla.",
            "La quarta frase allunga ancora il campione per avvicinarsi ai seicento caratteri richiesti dal contratto multi-frase.",
            "La quinta e ultima frase chiude il testo: il motore deve riceverlo intero e invariato, in una sola chiamata.",
        ]
        text = " ".join(sentences)
        self.assertGreater(len(text), 300)
        self.assertGreater(len(text), CLIENT_CHUNK_MAX_CHARS)
        self.assertLessEqual(len(text), REQUEST_TEXT_MAX_CHARS)

        resp = self.client.post(
            "/v1/tts",
            json={"text": text, "lang": "it", "voice": "M1", "normalize_text": False},
        )

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.engine.synthesized_texts, [text])


class TestTTSEngineUnavailable(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.tts = TTSManager(model="test", engine="supertonic")
        self.app.state.tts = self.tts
        self.client = TestClient(self.app)

    def test_tts_returns_503_when_model_is_not_loaded(self):
        resp = self.client.post("/v1/tts", json={"text": "ciao", "lang": "it"})

        self.assertEqual(resp.status_code, 503)
        self.assertIn("non disponibile", resp.json()["detail"])

    def test_preview_returns_503_when_model_is_not_loaded(self):
        resp = self.client.get("/v1/tts/preview")

        self.assertEqual(resp.status_code, 503)
        self.assertIn("non disponibile", resp.json()["detail"])


class TestStatusContract(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.engine = RecordingEngine()
        self.tts = TTSManager(model="test", engine="supertonic")
        self.tts.loading = True
        self.app.state.tts = self.tts
        self.client = TestClient(self.app)

    def test_status_reports_loading_then_ready(self):
        loading = self.client.get("/v1/status")
        self.assertEqual(loading.status_code, 200)
        self.assertEqual(
            loading.json(),
            {
                "ready": False,
                "model_loading": True,
                "model": "test",
                "sample_rate": None,
            },
        )

        with patch("backend.tts_manager.create_engine", return_value=self.engine):
            self.tts._load()

        ready = self.client.get("/v1/status")
        self.assertEqual(ready.status_code, 200)
        body = ready.json()
        self.assertTrue(body["ready"])
        self.assertFalse(body["model_loading"])
        self.assertEqual(body["sample_rate"], self.engine.sample_rate)
        self.assertEqual(body["sample_rate"], 24000)


if __name__ == "__main__":
    unittest.main()
