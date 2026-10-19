#!/usr/bin/env python3
"""Genera una scheda di ascolto cieco A/B dai risultati del benchmark.

Copia un campione cold per ogni testo in una cartella con nomi neutri
(``01_A.wav``, ``01_B.wav``), randomizza l'ordine e produce un CSV da compilare.
La chiave A/B viene salvata a parte: aprirla solo dopo aver finito l'ascolto.

Esempio:
    .venv/bin/python scripts/tts_listening_sheet.py \
        --baseline benchmarks/results/baseline.json \
        --candidate benchmarks/results/candidate.json
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import shutil
from collections import defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "benchmarks" / "results" / "listening_sheet.csv"
DEFAULT_AUDIO_DIR = ROOT / "benchmarks" / "results" / "listening_audio"


def load_results(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict) or "results" not in data:
        raise ValueError(f"{path}: file di risultati non valido")
    return data


def resolve_audio_path(value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    for candidate in (Path.cwd() / path, ROOT / path):
        if candidate.is_file():
            return candidate
    return path


def first_audio_by_text(document: dict[str, Any]) -> dict[str, Path]:
    candidates: dict[str, list[tuple[int, int, Path]]] = defaultdict(list)
    for row in document.get("results", []):
        if row.get("error") or not row.get("audio_path"):
            continue
        path = resolve_audio_path(str(row["audio_path"]))
        if not path.is_file():
            continue
        candidates[str(row["text_id"])].append(
            (int(row.get("pass_index", 0)), int(row.get("run_index", 0)), path)
        )
    return {
        text_id: sorted(paths, key=lambda item: (item[0], item[1]))[0][2]
        for text_id, paths in candidates.items()
    }


def copy_audio(source: Path, target: Path) -> None:
    if source.resolve() == target.resolve():
        return
    shutil.copy2(source, target)


def cmd_sheet(args: argparse.Namespace) -> int:
    baseline = load_results(Path(args.baseline))
    candidate = load_results(Path(args.candidate))
    base_audio = first_audio_by_text(baseline)
    cand_audio = first_audio_by_text(candidate)
    text_ids = sorted(set(base_audio) & set(cand_audio))
    if not text_ids:
        raise SystemExit(
            "Nessun testo con audio in entrambi i risultati. "
            "Esegui il benchmark con --save-audio-dir."
        )
    if args.limit:
        text_ids = text_ids[: args.limit]

    rng = random.Random(args.seed)
    rng.shuffle(text_ids)
    base_is_a_flags = [True, False] * ((len(text_ids) + 1) // 2)
    base_is_a_flags = base_is_a_flags[: len(text_ids)]
    rng.shuffle(base_is_a_flags)
    audio_dir = Path(args.audio_dir)
    audio_dir.mkdir(parents=True, exist_ok=True)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    key_path = Path(args.key_output)
    key_path.parent.mkdir(parents=True, exist_ok=True)

    rows = []
    key_rows = []
    for index, (text_id, base_is_a) in enumerate(zip(text_ids, base_is_a_flags, strict=True), 1):
        category = next(
            (
                str(row.get("category", ""))
                for row in baseline.get("results", [])
                if row.get("text_id") == text_id
            ),
            "",
        )
        a_source, b_source = (
            (base_audio[text_id], cand_audio[text_id])
            if base_is_a
            else (cand_audio[text_id], base_audio[text_id])
        )
        a_target = audio_dir / f"{index:02d}_A.wav"
        b_target = audio_dir / f"{index:02d}_B.wav"
        copy_audio(a_source, a_target)
        copy_audio(b_source, b_target)
        rows.append(
            {
                "ordine": index,
                "text_id": text_id,
                "category": category,
                "A_file": str(a_target),
                "B_file": str(b_target),
                "naturalezza_A": "",
                "naturalezza_B": "",
                "intelligibilita_A": "",
                "intelligibilita_B": "",
                "prosodia_A": "",
                "prosodia_B": "",
                "artefatti_A": "",
                "artefatti_B": "",
                "preferenza": "",
                "note": "",
            }
        )
        key_rows.append(
            {
                "text_id": text_id,
                "A_label": baseline.get("label", "baseline")
                if base_is_a
                else candidate.get("label", "candidate"),
                "B_label": candidate.get("label", "candidate")
                if base_is_a
                else baseline.get("label", "baseline"),
            }
        )

    fieldnames = list(rows[0].keys())
    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    with key_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["text_id", "A_label", "B_label"])
        writer.writeheader()
        writer.writerows(key_rows)

    print(f"Scheda: {output_path}")
    print(f"Audio cieco: {audio_dir}")
    print(f"Chiave (non aprire prima dell'ascolto): {key_path}")
    print(f"Testi: {len(rows)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Crea una scheda di ascolto cieco A/B dai risultati del benchmark."
    )
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--audio-dir", default=str(DEFAULT_AUDIO_DIR))
    parser.add_argument(
        "--key-output",
        default=str(ROOT / "benchmarks" / "results" / "listening_key.csv"),
    )
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--limit", type=int, default=0)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return cmd_sheet(args)


if __name__ == "__main__":
    raise SystemExit(main())
