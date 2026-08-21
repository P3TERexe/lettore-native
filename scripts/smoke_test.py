"""Smoke test: sintetizza una frase e salva un WAV.

Uso: python scripts/smoke_test.py "Testo..." [-l it] [-v M1] [-o out.wav]
Il primo run scarica il modello (~400MB) da Hugging Face.
"""

import argparse
import sys
import time

sys.path.insert(0, str(__file__).rsplit("/", 2)[0])

from backend.tts_manager import TTSManager  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Smoke test backend TTS")
    parser.add_argument("text", nargs="?", default="Ciao, questa è la prova di lettura con Supertonic.")
    parser.add_argument("-l", "--lang", default="it")
    parser.add_argument("-v", "--voice", default="M1")
    parser.add_argument("-s", "--steps", type=int, default=8)
    parser.add_argument("--speed", type=float, default=1.05)
    parser.add_argument("-o", "--output", default="/tmp/lettore_smoke.wav")
    args = parser.parse_args()

    t0 = time.monotonic()
    manager = TTSManager(model="supertonic-3")
    manager.start()
    manager.wait_ready(timeout=1200)
    wav, duration_ms = manager.synthesize(args.text, args.lang, args.voice, args.steps, args.speed)
    with open(args.output, "wb") as fh:
        fh.write(wav)
    builtin, custom = manager.voices()
    print(f"OK  [{args.voice} / {args.lang}] durata={duration_ms}ms "
          f"tempo_totale={(time.monotonic()-t0):.1f}s file={args.output}")
    print(f"Voci builtin: {builtin}  custom: {custom}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
