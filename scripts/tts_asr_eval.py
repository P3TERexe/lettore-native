#!/usr/bin/env python3
"""Valutazione automatica dell'intelligibilità con whisper.cpp.

Legge gli audio salvati da ``scripts/tts_benchmark.py`` (opzione
``--save-audio-dir``), li trascrive con ``whisper-cli`` e calcola WER/CER
rispetto al testo del corpus. È un indicatore di intelligibilità, non una
misura di naturalezza: va sempre accompagnato da un ascolto cieco.

Esempio:
    .venv/bin/python scripts/tts_asr_eval.py \
        --results benchmarks/results/candidate.json \
        --whisper-model ~/models/ggml-large-v3.bin \
        --output benchmarks/results/candidate-asr.json
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
import tempfile
import unicodedata
from collections import defaultdict
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CORPUS = ROOT / "benchmarks" / "tts_corpus_it.jsonl"


@dataclass(frozen=True)
class CorpusItem:
    id: str
    category: str
    text: str
    asr_reference: str | None = None


def load_corpus(path: Path) -> dict[str, CorpusItem]:
    items: dict[str, CorpusItem] = {}
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                raw = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: JSON non valido: {exc}") from exc
            item = CorpusItem(
                id=str(raw["id"]),
                category=str(raw["category"]),
                text=str(raw["text"]),
                asr_reference=raw.get("asr_reference"),
            )
            items[item.id] = item
    return items


def normalize_text(text: str) -> str:
    text = unicodedata.normalize("NFC", text).lower()
    text = text.replace("’", "'").replace("‘", "'")
    text = re.sub(r"[^\w\s]", " ", text, flags=re.UNICODE)
    text = text.replace("_", " ")
    return " ".join(text.split())


def edit_distance(reference: Sequence[str], hypothesis: Sequence[str]) -> int:
    if len(reference) < len(hypothesis):
        reference, hypothesis = hypothesis, reference
    previous = list(range(len(hypothesis) + 1))
    for row, ref_token in enumerate(reference, 1):
        current = [row]
        for column, hyp_token in enumerate(hypothesis, 1):
            insert = current[column - 1] + 1
            delete = previous[column] + 1
            substitute = previous[column - 1] + (ref_token != hyp_token)
            current.append(min(insert, delete, substitute))
        previous = current
    return previous[-1]


def word_error_rate(reference: str, hypothesis: str) -> float:
    ref_words = normalize_text(reference).split()
    hyp_words = normalize_text(hypothesis).split()
    return edit_distance(ref_words, hyp_words) / max(1, len(ref_words))


def char_error_rate(reference: str, hypothesis: str) -> float:
    ref_chars = list(normalize_text(reference).replace(" ", ""))
    hyp_chars = list(normalize_text(hypothesis).replace(" ", ""))
    return edit_distance(ref_chars, hyp_chars) / max(1, len(ref_chars))


def resolve_audio_path(value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    for candidate in (Path.cwd() / path, ROOT / path):
        if candidate.exists():
            return candidate
    return path


def pick_audio_from_results(document: dict, audio_dir: Path | None) -> dict[str, Path]:
    candidates: dict[str, list[tuple[int, int, Path]]] = defaultdict(list)
    for row in document.get("results", []):
        if row.get("error") or not row.get("audio_path"):
            continue
        path = resolve_audio_path(str(row["audio_path"]))
        if not path.is_file():
            continue
        candidates[str(row["text_id"])].append(
            (
                int(row.get("pass_index", 0)),
                int(row.get("run_index", 0)),
                path,
            )
        )

    selected: dict[str, Path] = {}
    for text_id, paths in candidates.items():
        selected[text_id] = sorted(paths, key=lambda item: (item[0], item[1]))[0][2]

    if audio_dir is not None:
        for audio_path in sorted(audio_dir.glob("*.wav")):
            text_id = audio_path.name.split("__", 1)[0]
            selected.setdefault(text_id, audio_path)
    return selected


def transcribe(
    whisper_bin: str,
    whisper_model: Path,
    audio_path: Path,
    lang: str,
    timeout: float,
    work_dir: Path,
) -> str:
    prefix = work_dir / audio_path.stem
    command = [
        whisper_bin,
        "-m",
        str(whisper_model),
        "-l",
        lang,
        "-otxt",
        "-nt",
        "-np",
        "-f",
        str(audio_path),
        "-of",
        str(prefix),
    ]
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(
            f"Eseguibile non trovato: {whisper_bin}. Installa whisper.cpp e passa --whisper-bin."
        ) from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"Timeout whisper su {audio_path.name}") from exc
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()[-500:]
        raise RuntimeError(f"whisper-cli ha fallito su {audio_path.name}: {detail}")

    output_path = Path(str(prefix) + ".txt")
    if not output_path.is_file():
        raise RuntimeError(f"whisper-cli non ha prodotto {output_path.name}")
    return output_path.read_text(encoding="utf-8").strip()


def aggregate(items: list[dict], key: str | None = None) -> dict:
    groups: dict[str, list[dict]] = defaultdict(list)
    for item in items:
        groups[item[key] if key else "tutti"].append(item)

    def summarize(rows: list[dict]) -> dict:
        wer = [row["wer"] for row in rows]
        cer = [row["cer"] for row in rows]
        return {
            "count": len(rows),
            "wer_mean": statistics.mean(wer) if wer else None,
            "wer_median": statistics.median(wer) if wer else None,
            "cer_mean": statistics.mean(cer) if cer else None,
            "cer_median": statistics.median(cer) if cer else None,
        }

    return {name: summarize(rows) for name, rows in sorted(groups.items())}


def cmd_eval(args: argparse.Namespace) -> int:
    whisper_model = Path(args.whisper_model).expanduser()
    if not whisper_model.is_file():
        raise SystemExit(f"Modello whisper non trovato: {whisper_model}")
    corpus = load_corpus(Path(args.corpus))
    audio_dir = Path(args.audio_dir) if args.audio_dir else None

    document: dict = {}
    if args.results:
        with Path(args.results).open(encoding="utf-8") as handle:
            document = json.load(handle)
    audio_by_id = pick_audio_from_results(document, audio_dir)
    if not audio_by_id:
        raise SystemExit(
            "Nessun audio trovato. Esegui il benchmark con --save-audio-dir "
            "oppure passa --audio-dir."
        )

    text_ids = sorted(audio_by_id)
    if args.limit:
        text_ids = text_ids[: args.limit]

    items: list[dict] = []
    errors: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="lettore-asr-") as temp_dir:
        work_dir = Path(temp_dir)
        for index, text_id in enumerate(text_ids, 1):
            corpus_item = corpus.get(text_id)
            if corpus_item is None:
                errors.append({"text_id": text_id, "error": "testo non presente nel corpus"})
                continue
            reference = corpus_item.asr_reference or corpus_item.text
            try:
                hypothesis = transcribe(
                    whisper_bin=args.whisper_bin,
                    whisper_model=whisper_model,
                    audio_path=audio_by_id[text_id],
                    lang=args.lang,
                    timeout=args.timeout,
                    work_dir=work_dir,
                )
            except RuntimeError as exc:
                errors.append({"text_id": text_id, "error": str(exc)})
                print(f"[{index}/{len(text_ids)}] {text_id}: ERRORE: {exc}", file=sys.stderr)
                if args.fail_fast:
                    raise SystemExit(1) from exc
                continue

            row = {
                "text_id": text_id,
                "category": corpus_item.category,
                "audio_path": str(audio_by_id[text_id]),
                "reference": reference,
                "hypothesis": hypothesis,
                "wer": word_error_rate(reference, hypothesis),
                "cer": char_error_rate(reference, hypothesis),
            }
            items.append(row)
            print(
                f"[{index}/{len(text_ids)}] {text_id}: "
                f"WER {row['wer'] * 100:.1f}% | CER {row['cer'] * 100:.1f}%"
            )

    summary = aggregate(items)
    payload = {
        "label": document.get("label", args.label),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "whisper": {
            "bin": args.whisper_bin,
            "model": str(whisper_model),
            "lang": args.lang,
        },
        "summary": summary.get("tutti", {}),
        "by_category": aggregate(items, "category"),
        "errors": errors,
        "items": items,
    }

    output_path = (
        Path(args.output)
        if args.output
        else ROOT / "benchmarks" / "results" / f"{args.label}-asr.json"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    overall = payload["summary"]
    print()
    print(f"Testi valutati: {overall.get('count', 0)} | errori: {len(errors)}")
    print(f"WER medio: {overall.get('wer_mean', 0) * 100:.1f}%")
    print(f"CER medio: {overall.get('cer_mean', 0) * 100:.1f}%")
    print(f"Risultati: {output_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Calcola WER/CER degli audio TTS con whisper.cpp.")
    parser.add_argument("--results", default=None, help="JSON prodotto da tts_benchmark.py run.")
    parser.add_argument("--audio-dir", default=None, help="Directory con file .wav del benchmark.")
    parser.add_argument("--corpus", default=str(DEFAULT_CORPUS))
    parser.add_argument("--whisper-model", required=True)
    parser.add_argument("--whisper-bin", default="whisper-cli")
    parser.add_argument("--lang", default="it")
    parser.add_argument("--label", default="candidate")
    parser.add_argument("--output", default=None)
    parser.add_argument("--timeout", type=float, default=300.0)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--fail-fast", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.results and not args.audio_dir:
        parser.error("specificare --results oppure --audio-dir")
    return cmd_eval(args)


if __name__ == "__main__":
    raise SystemExit(main())
