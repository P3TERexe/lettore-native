#!/usr/bin/env python3
"""Benchmark riproducibile della sintesi vocale locale.

Il comando ``run`` interroga un backend HTTP e salva latenza, RTF, CPU/RSS del
server (quando il PID è disponibile) e metriche audio di base. Il comando
``compare`` confronta due esecuzioni e produce un report Markdown.

Esempi:
    .venv/bin/python scripts/tts_benchmark.py run \
        --label baseline --base-url http://127.0.0.1:7788 \
        --output benchmarks/results/baseline.json

    .venv/bin/python scripts/tts_benchmark.py compare \
        --baseline benchmarks/results/baseline.json \
        --candidate benchmarks/results/candidate.json \
        --output benchmarks/results/confronto.md
"""

from __future__ import annotations

import argparse
import io
import json
import math
import os
import platform
import shlex
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import wave
from collections import defaultdict
from collections.abc import Iterable
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CORPUS = ROOT / "benchmarks" / "tts_corpus_it.jsonl"
DEFAULT_RESULTS_DIR = ROOT / "benchmarks" / "results"
DEFAULT_WARMUP_TEXT = "Ciao, questa è una prova di riscaldamento."

METRICS = (
    "wall_ms",
    "rtf",
    "server_cpu_ms",
    "server_peak_rss_mb",
    "rms_dbfs",
    "peak_dbfs",
    "clipping_pct",
    "silence_pct",
)

# Il backend è locale: ignora eventuali HTTP_PROXY/HTTPS_PROXY dell'ambiente.
LOCAL_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


@dataclass(frozen=True)
class CorpusItem:
    id: str
    category: str
    text: str
    notes: str = ""
    asr_reference: str | None = None


@dataclass(frozen=True)
class RunConfig:
    voice: str
    lang: str
    steps: int
    speed: float


class BenchmarkError(RuntimeError):
    """Errore HTTP o di rete durante una richiesta TTS."""


def slugify(value: str) -> str:
    safe = "".join(char if char.isalnum() or char in "-_" else "-" for char in value)
    return safe.strip("-") or "run"


def load_corpus(path: Path) -> list[CorpusItem]:
    items: list[CorpusItem] = []
    seen: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                raw = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: JSON non valido: {exc}") from exc
            missing = [field for field in ("id", "category", "text") if not raw.get(field)]
            if missing:
                raise ValueError(f"{path}:{line_number}: campi mancanti: {', '.join(missing)}")
            if raw["id"] in seen:
                raise ValueError(f"{path}:{line_number}: id duplicato: {raw['id']}")
            seen.add(raw["id"])
            items.append(
                CorpusItem(
                    id=str(raw["id"]),
                    category=str(raw["category"]),
                    text=str(raw["text"]),
                    notes=str(raw.get("notes", "")),
                    asr_reference=raw.get("asr_reference"),
                )
            )
    if not items:
        raise ValueError(f"Corpus vuoto: {path}")
    return items


def post_tts(
    base_url: str,
    text: str,
    config: RunConfig,
    timeout: float,
) -> tuple[bytes, int | None]:
    payload = {
        "text": text,
        "voice": config.voice,
        "lang": config.lang,
        "steps": config.steps,
        "speed": config.speed,
    }
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/v1/tts",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with LOCAL_OPENER.open(request, timeout=timeout) as response:
            body = response.read()
            duration_header = response.headers.get("X-Duration-Ms")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:500]
        raise BenchmarkError(f"HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise BenchmarkError(f"connessione fallita: {exc.reason}") from exc
    duration_ms = int(duration_header) if duration_header else None
    return body, duration_ms


def parse_ps_time(value: str) -> float:
    parts = value.strip().split(":")
    if len(parts) == 2:
        minutes, seconds = parts
        return int(minutes) * 60.0 + float(seconds)
    if len(parts) == 3:
        hours, minutes, seconds = parts
        return int(hours) * 3600.0 + int(minutes) * 60.0 + float(seconds)
    return float(value)


class ResourceSampler:
    """Campiona RSS e tempo CPU cumulativo del processo server tramite ``ps``."""

    def __init__(self, pid: int | None, interval: float = 0.05) -> None:
        self.pid = pid
        self.interval = interval
        self.peak_rss_mb: float | None = None
        self.cpu_ms: float | None = None
        self._cpu_start_s: float | None = None
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def _sample(self) -> tuple[float | None, float | None]:
        if self.pid is None:
            return None, None
        try:
            output = subprocess.check_output(
                ["ps", "-o", "rss=,time=", "-p", str(self.pid)],
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2,
            ).strip()
        except (OSError, subprocess.SubprocessError):
            return None, None
        if not output:
            return None, None
        fields = output.split()
        if len(fields) < 2:
            return None, None
        try:
            rss_mb = float(fields[0]) / 1024.0
            cpu_s = parse_ps_time(fields[1])
        except ValueError:
            return None, None
        return rss_mb, cpu_s

    def _loop(self) -> None:
        while not self._stop.wait(self.interval):
            rss_mb, _ = self._sample()
            if rss_mb is not None:
                self.peak_rss_mb = max(self.peak_rss_mb or 0.0, rss_mb)

    def __enter__(self) -> ResourceSampler:
        if self.pid is not None:
            rss_mb, cpu_s = self._sample()
            if rss_mb is not None:
                self.peak_rss_mb = rss_mb
            self._cpu_start_s = cpu_s
            self._thread = threading.Thread(
                target=self._loop, name="tts-bench-resource", daemon=True
            )
            self._thread.start()
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> bool:
        if self.pid is not None:
            self._stop.set()
            if self._thread is not None:
                self._thread.join(timeout=2)
            rss_mb, cpu_s = self._sample()
            if rss_mb is not None:
                self.peak_rss_mb = max(self.peak_rss_mb or 0.0, rss_mb)
            if cpu_s is not None and self._cpu_start_s is not None:
                self.cpu_ms = max(0.0, (cpu_s - self._cpu_start_s) * 1000.0)
        return False


def analyze_wav(data: bytes) -> dict[str, float | int]:
    try:
        with wave.open(io.BytesIO(data), "rb") as wav_file:
            channels = wav_file.getnchannels()
            sample_width = wav_file.getsampwidth()
            sample_rate = wav_file.getframerate()
            frame_count = wav_file.getnframes()
            raw = wav_file.readframes(frame_count)
    except (wave.Error, EOFError, ValueError):
        return {}

    stats: dict[str, float | int] = {
        "wav_channels": channels,
        "wav_sample_rate": sample_rate,
        "wav_duration_s": frame_count / sample_rate if sample_rate else 0.0,
    }
    if sample_width != 2 or not raw:
        return stats

    samples = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if channels > 1:
        usable = len(samples) - (len(samples) % channels)
        samples = samples[:usable].reshape(-1, channels).mean(axis=1)
    if samples.size == 0:
        return stats

    rms = float(np.sqrt(np.mean(np.square(samples))))
    peak = float(np.max(np.abs(samples)))
    threshold = 10 ** (-50.0 / 20.0)
    stats.update(
        {
            "rms_dbfs": 20.0 * math.log10(max(rms, 1e-9)),
            "peak_dbfs": 20.0 * math.log10(max(peak, 1e-9)),
            "clipping_pct": float(np.mean(np.abs(samples) >= 0.999) * 100.0),
            "silence_pct": float(np.mean(np.abs(samples) < threshold) * 100.0),
        }
    )
    return stats


class ServerProcess:
    """Avvia e arresta un backend locale per le misure cold."""

    def __init__(
        self,
        command: str,
        cwd: Path,
        base_url: str,
        env: dict[str, str],
        startup_timeout: float,
        log_path: Path | None,
    ) -> None:
        self.command = shlex.split(command)
        self.cwd = cwd
        self.base_url = base_url.rstrip("/")
        self.env = env
        self.startup_timeout = startup_timeout
        self.log_path = log_path
        self.proc: subprocess.Popen[Any] | None = None
        self.pid: int | None = None
        self._log_handle: Any = None

    def start(self) -> None:
        if self.proc is not None and self.proc.poll() is None:
            return
        env = os.environ.copy()
        env.update(self.env)
        if self.log_path is not None:
            self.log_path.parent.mkdir(parents=True, exist_ok=True)
            self._log_handle = self.log_path.open("a", encoding="utf-8")
            stdout: Any = self._log_handle
        else:
            stdout = subprocess.DEVNULL
        self.proc = subprocess.Popen(
            self.command,
            cwd=str(self.cwd),
            env=env,
            stdout=stdout,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        self.pid = self.proc.pid
        try:
            self._wait_ready()
        except Exception:
            self.stop()
            raise

    def _wait_ready(self) -> None:
        deadline = time.monotonic() + self.startup_timeout
        status_url = f"{self.base_url}/v1/status"
        last_error: str | None = None
        while time.monotonic() < deadline:
            if self.proc is not None and self.proc.poll() is not None:
                raise RuntimeError(
                    f"Il server è terminato con codice {self.proc.returncode}. "
                    "Controlla --server-log per i dettagli."
                )
            try:
                with LOCAL_OPENER.open(status_url, timeout=2) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                if payload.get("ready"):
                    return
                last_error = "modello non ancora pronto"
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
                last_error = str(exc)
            time.sleep(0.5)
        raise TimeoutError(
            f"Server non pronto dopo {self.startup_timeout:.0f}s ({last_error}). "
            "Controlla --server-log e la porta indicata da --base-url."
        )

    def stop(self) -> None:
        if self.proc is not None and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=5)
        self.proc = None
        self.pid = None
        if self._log_handle is not None:
            self._log_handle.close()
            self._log_handle = None


def _audio_path(
    audio_root: Path | None,
    label: str,
    item: CorpusItem,
    pass_index: int,
    run_index: int,
) -> Path | None:
    if audio_root is None:
        return None
    target = audio_root / slugify(label) / f"{item.id}__p{pass_index:02d}__r{run_index:02d}.wav"
    target.parent.mkdir(parents=True, exist_ok=True)
    return target


def run_single(
    base_url: str,
    item: CorpusItem,
    config: RunConfig,
    timeout: float,
    server_pid: int | None,
    pass_index: int,
    run_index: int,
    audio_root: Path | None,
    label: str,
) -> dict[str, Any]:
    sampler = ResourceSampler(server_pid)
    started = time.perf_counter()
    body = b""
    duration_ms: int | None = None
    error: str | None = None
    try:
        with sampler:
            body, duration_ms = post_tts(base_url, item.text, config, timeout)
    except Exception as exc:  # noqa: BLE001 - il benchmark registra anche errori imprevisti
        error = f"{type(exc).__name__}: {exc}"
    wall_ms = (time.perf_counter() - started) * 1000.0

    stats = analyze_wav(body) if body and not error else {}
    if duration_ms is None and stats.get("wav_duration_s"):
        duration_ms = int(round(float(stats["wav_duration_s"]) * 1000.0))
    rtf = (duration_ms / wall_ms) if duration_ms and wall_ms > 0 else None

    saved_path: Path | None = None
    if body and not error and body[:4] == b"RIFF":
        saved_path = _audio_path(audio_root, label, item, pass_index, run_index)
        if saved_path is not None:
            saved_path.write_bytes(body)

    def rounded(value: Any, digits: int = 2) -> float | None:
        return round(float(value), digits) if value is not None else None

    return {
        "text_id": item.id,
        "category": item.category,
        "notes": item.notes,
        "pass_index": pass_index,
        "run_index": run_index,
        "text_chars": len(item.text),
        "wall_ms": round(wall_ms, 2),
        "audio_ms": duration_ms,
        "rtf": rounded(rtf, 3),
        "bytes": len(body),
        "server_cpu_ms": rounded(sampler.cpu_ms, 2),
        "server_peak_rss_mb": rounded(sampler.peak_rss_mb, 1),
        "rms_dbfs": rounded(stats.get("rms_dbfs"), 2),
        "peak_dbfs": rounded(stats.get("peak_dbfs"), 2),
        "clipping_pct": rounded(stats.get("clipping_pct"), 4),
        "silence_pct": rounded(stats.get("silence_pct"), 2),
        "wav_duration_s": rounded(stats.get("wav_duration_s"), 3),
        "wav_sample_rate": stats.get("wav_sample_rate"),
        "audio_path": str(saved_path) if saved_path is not None else None,
        "error": error,
    }


def environment_info() -> dict[str, str]:
    return {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "python": platform.python_version(),
    }


def _median(values: Iterable[float | None]) -> float | None:
    clean = [float(value) for value in values if value is not None]
    return statistics.median(clean) if clean else None


def _max_value(values: Iterable[float | None]) -> float | None:
    clean = [float(value) for value in values if value is not None]
    return max(clean) if clean else None


def summarize_results(results: list[dict[str, Any]]) -> dict[str, Any]:
    errors = [row for row in results if row.get("error")]
    ok = [row for row in results if not row.get("error")]
    cold = [row for row in ok if row.get("run_index") == 0]
    warm = [row for row in ok if (row.get("run_index") or 0) > 0]
    return {
        "requests": len(results),
        "errors": len(errors),
        "cold_count": len(cold),
        "warm_count": len(warm),
        "cold_wall_ms_median": _median(row.get("wall_ms") for row in cold),
        "cold_rtf_median": _median(row.get("rtf") for row in cold),
        "cold_server_cpu_ms_median": _median(row.get("server_cpu_ms") for row in cold),
        "server_peak_rss_mb_max": _max_value(row.get("server_peak_rss_mb") for row in ok),
        "warm_wall_ms_median": _median(row.get("wall_ms") for row in warm),
    }


def cmd_run(args: argparse.Namespace) -> int:
    corpus_path = Path(args.corpus)
    corpus = load_corpus(corpus_path)
    if args.limit:
        corpus = corpus[: args.limit]
    config = RunConfig(
        voice=args.voice,
        lang=args.lang,
        steps=args.steps,
        speed=args.speed,
    )
    base_url = args.base_url.rstrip("/")
    passes = max(1, args.passes)
    runs = max(1, args.runs)

    server_env: dict[str, str] = {}
    for entry in args.server_env:
        if "=" not in entry:
            raise SystemExit(f"--server-env richiede KEY=VALUE, ricevuto: {entry}")
        key, value = entry.split("=", 1)
        server_env[key] = value

    server = None
    if args.server_cmd:
        server = ServerProcess(
            command=args.server_cmd,
            cwd=Path(args.server_cwd),
            base_url=base_url,
            env=server_env,
            startup_timeout=args.startup_timeout,
            log_path=Path(args.server_log) if args.server_log else None,
        )

    audio_root = Path(args.save_audio_dir) if args.save_audio_dir else None
    output_path = (
        Path(args.output) if args.output else DEFAULT_RESULTS_DIR / f"{slugify(args.label)}.json"
    )
    results: list[dict[str, Any]] = []
    total_requests = passes * runs * len(corpus)

    try:
        for pass_index in range(passes):
            if server is not None:
                if pass_index > 0 and args.restart_between_passes:
                    server.stop()
                server.start()
            server_pid = server.pid if server is not None else args.server_pid

            if args.warmup:
                try:
                    post_tts(base_url, args.warmup_text, config, args.timeout)
                except Exception as exc:  # noqa: BLE001
                    print(f"Warmup fallito: {exc}", file=sys.stderr)

            for item in corpus:
                for run_index in range(runs):
                    result = run_single(
                        base_url=base_url,
                        item=item,
                        config=config,
                        timeout=args.timeout,
                        server_pid=server_pid,
                        pass_index=pass_index,
                        run_index=run_index,
                        audio_root=audio_root,
                        label=args.label,
                    )
                    results.append(result)
                    status = (
                        f"{result['wall_ms']:.0f} ms"
                        if not result["error"]
                        else f"ERRORE: {result['error']}"
                    )
                    print(
                        f"[{len(results)}/{total_requests}] "
                        f"{item.id} p{pass_index} r{run_index}: {status}"
                    )
                    if result["error"] and args.fail_fast:
                        raise SystemExit(1)
    finally:
        if server is not None:
            server.stop()

    summary = summarize_results(results)
    payload = {
        "schema_version": 1,
        "label": args.label,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "environment": environment_info(),
        "config": {
            **asdict(config),
            "base_url": base_url,
            "timeout_s": args.timeout,
            "passes": passes,
            "runs": runs,
            "warmup": args.warmup,
            "warmup_text": args.warmup_text,
            "corpus": str(corpus_path),
            "corpus_count": len(corpus),
            "save_audio_dir": str(audio_root) if audio_root else None,
        },
        "summary": summary,
        "results": results,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print()
    print(f"Etichetta: {args.label}")
    print(f"Richieste: {summary['requests']} | errori: {summary['errors']}")
    print(f"Cold: {summary['cold_count']} richieste")
    print(f"Latenza cold mediana: {fmt_number(summary['cold_wall_ms_median'], 0)} ms")
    print(f"RTF cold mediano: {fmt_number(summary['cold_rtf_median'], 2)}x")
    print(f"CPU server cold mediana: {fmt_number(summary['cold_server_cpu_ms_median'], 0)} ms")
    print(f"RAM server picco: {fmt_number(summary['server_peak_rss_mb_max'], 1)} MB")
    print(
        f"Warm/cache: {summary['warm_count']} richieste, "
        f"{fmt_number(summary['warm_wall_ms_median'], 0)} ms mediani"
    )
    print(f"Risultati: {output_path}")
    return 0


def load_results(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict) or "results" not in data:
        raise ValueError(f"{path}: file di risultati non valido")
    return data


def selected_rows(document: dict[str, Any], mode: str) -> list[dict[str, Any]]:
    rows = [row for row in document.get("results", []) if not row.get("error")]
    if mode == "cold":
        return [row for row in rows if row.get("run_index") == 0]
    if mode == "warm":
        return [row for row in rows if (row.get("run_index") or 0) > 0]
    return rows


def metric_median(rows: list[dict[str, Any]], metric: str) -> float | None:
    return _median(row.get(metric) for row in rows)


def per_text_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[str(row.get("text_id", "sconosciuto"))].append(row)
    output = []
    for text_id, items in grouped.items():
        output.append(
            {
                "text_id": text_id,
                "category": items[0].get("category", ""),
                **{metric: metric_median(items, metric) for metric in METRICS},
            }
        )
    return sorted(output, key=lambda row: row["text_id"])


def aggregate_rows(rows: list[dict[str, Any]], key_fn: Any) -> dict[str, dict[str, float | None]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[str(key_fn(row))].append(row)
    return {
        key: {metric: metric_median(items, metric) for metric in METRICS}
        for key, items in grouped.items()
    }


def fmt_number(value: float | None, digits: int = 1) -> str:
    if value is None:
        return "n/d"
    text = f"{value:,.{digits}f}"
    return text.replace(",", "\u00a7").replace(".", ",").replace("\u00a7", ".")


def fmt_metric(value: float | None, digits: int, unit: str) -> str:
    if value is None:
        return "n/d"
    return f"{fmt_number(value, digits)}{unit}"


def fmt_delta_pct(base: float | None, candidate: float | None) -> str:
    if base is None or candidate is None or base == 0:
        return "n/d"
    delta = (candidate - base) / base * 100.0
    sign = "+" if delta > 0 else ""
    return f"{sign}{fmt_number(delta, 1)}%"


def fmt_delta_abs(base: float | None, candidate: float | None, unit: str) -> str:
    if base is None or candidate is None:
        return "n/d"
    delta = candidate - base
    sign = "+" if delta > 0 else ""
    return f"{sign}{fmt_number(delta, 2)}{unit}"


def _all_metrics(rows: list[dict[str, Any]]) -> dict[str, float | None]:
    return {metric: metric_median(rows, metric) for metric in METRICS}


def quality_warnings(
    baseline: dict[str, float | None],
    candidate: dict[str, float | None],
    base_errors: int,
    candidate_errors: int,
) -> list[str]:
    warnings: list[str] = []
    if base_errors or candidate_errors:
        warnings.append(f"Richieste fallite: baseline {base_errors}, candidato {candidate_errors}.")
    base_rms = baseline.get("rms_dbfs")
    cand_rms = candidate.get("rms_dbfs")
    if base_rms is not None and cand_rms is not None and abs(cand_rms - base_rms) >= 3.0:
        warnings.append(
            "Il livello RMS medio differisce di almeno 3 dB: verificare volume e normalizzazione."
        )
    base_peak = baseline.get("peak_dbfs")
    cand_peak = candidate.get("peak_dbfs")
    if base_peak is not None and cand_peak is not None and abs(cand_peak - base_peak) >= 2.0:
        warnings.append(
            "Il picco audio differisce di almeno 2 dB: possibile clipping o gain diverso."
        )
    cand_clipping = candidate.get("clipping_pct")
    if cand_clipping is not None and cand_clipping > 0.1:
        warnings.append(f"Clipping nel candidato: {fmt_number(cand_clipping, 3)}% dei campioni.")
    base_silence = baseline.get("silence_pct")
    cand_silence = candidate.get("silence_pct")
    if (
        base_silence is not None
        and cand_silence is not None
        and abs(cand_silence - base_silence) >= 10.0
    ):
        warnings.append(
            "La percentuale di silenzio differisce di almeno 10 punti: possibili pause diverse."
        )
    return warnings


def build_report(
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    mode: str,
) -> str:
    base_rows = selected_rows(baseline, mode)
    cand_rows = selected_rows(candidate, mode)
    base_text = per_text_rows(base_rows)
    cand_text = per_text_rows(cand_rows)
    base_all = aggregate_rows(base_text, lambda _: "all").get("all", _all_metrics([]))
    cand_all = aggregate_rows(cand_text, lambda _: "all").get("all", _all_metrics([]))
    base_all["server_peak_rss_mb"] = _max_value(row.get("server_peak_rss_mb") for row in base_rows)
    cand_all["server_peak_rss_mb"] = _max_value(row.get("server_peak_rss_mb") for row in cand_rows)

    base_cat = aggregate_rows(base_text, lambda row: row["category"])
    cand_cat = aggregate_rows(cand_text, lambda row: row["category"])
    base_by_id = {row["text_id"]: row for row in base_text}
    cand_by_id = {row["text_id"]: row for row in cand_text}
    all_ids = sorted(set(base_by_id) | set(cand_by_id))

    base_errors = len([row for row in baseline.get("results", []) if row.get("error")])
    cand_errors = len([row for row in candidate.get("results", []) if row.get("error")])
    warnings = quality_warnings(base_all, cand_all, base_errors, cand_errors)

    mode_label = {
        "cold": "cold (prima richiesta di ogni passata)",
        "warm": "warm (richieste successive, possibile cache)",
        "all": "tutte le richieste",
    }[mode]
    base_label = baseline.get("label", "baseline")
    cand_label = candidate.get("label", "candidate")

    lines = [
        "# Confronto benchmark TTS",
        "",
        f"- **Baseline:** `{base_label}`",
        f"- **Candidato:** `{cand_label}`",
        f"- **Modalità:** {mode_label}",
        f"- **Testi:** {len(all_ids)}",
        f"- **Generato:** {datetime.now(timezone.utc).isoformat(timespec='seconds')}",
        "",
        "## Configurazione",
        "",
        "| Parametro | Baseline | Candidato |",
        "| --- | ---: | ---: |",
    ]
    base_config = baseline.get("config", {})
    cand_config = candidate.get("config", {})
    for key in ("voice", "lang", "steps", "speed", "passes", "runs"):
        lines.append(f"| {key} | {base_config.get(key, 'n/d')} | {cand_config.get(key, 'n/d')} |")

    lines.extend(
        [
            "",
            "## Sintesi",
            "",
            "| Metrica | Baseline | Candidato | Δ |",
            "| --- | ---: | ---: | ---: |",
            (
                "| Latenza mediana | "
                f"{fmt_metric(base_all.get('wall_ms'), 0, ' ms')} | "
                f"{fmt_metric(cand_all.get('wall_ms'), 0, ' ms')} | "
                f"{fmt_delta_pct(base_all.get('wall_ms'), cand_all.get('wall_ms'))} |"
            ),
            (
                "| RTF mediano | "
                f"{fmt_metric(base_all.get('rtf'), 2, 'x')} | "
                f"{fmt_metric(cand_all.get('rtf'), 2, 'x')} | "
                f"{fmt_delta_pct(base_all.get('rtf'), cand_all.get('rtf'))} |"
            ),
            (
                "| CPU server mediana | "
                f"{fmt_metric(base_all.get('server_cpu_ms'), 0, ' ms')} | "
                f"{fmt_metric(cand_all.get('server_cpu_ms'), 0, ' ms')} | "
                f"{fmt_delta_pct(base_all.get('server_cpu_ms'), cand_all.get('server_cpu_ms'))} |"
            ),
            (
                "| RAM server picco | "
                f"{fmt_metric(base_all.get('server_peak_rss_mb'), 1, ' MB')} | "
                f"{fmt_metric(cand_all.get('server_peak_rss_mb'), 1, ' MB')} | "
                f"{fmt_delta_pct(base_all.get('server_peak_rss_mb'), cand_all.get('server_peak_rss_mb'))} |"
            ),
            (
                "| RMS medio | "
                f"{fmt_metric(base_all.get('rms_dbfs'), 1, ' dBFS')} | "
                f"{fmt_metric(cand_all.get('rms_dbfs'), 1, ' dBFS')} | "
                f"{fmt_delta_abs(base_all.get('rms_dbfs'), cand_all.get('rms_dbfs'), ' dB')} |"
            ),
            (
                "| Picco | "
                f"{fmt_metric(base_all.get('peak_dbfs'), 1, ' dBFS')} | "
                f"{fmt_metric(cand_all.get('peak_dbfs'), 1, ' dBFS')} | "
                f"{fmt_delta_abs(base_all.get('peak_dbfs'), cand_all.get('peak_dbfs'), ' dB')} |"
            ),
            (
                "| Clipping | "
                f"{fmt_metric(base_all.get('clipping_pct'), 3, '%')} | "
                f"{fmt_metric(cand_all.get('clipping_pct'), 3, '%')} | "
                f"{fmt_delta_abs(base_all.get('clipping_pct'), cand_all.get('clipping_pct'), ' pp')} |"
            ),
            (
                "| Silenzio | "
                f"{fmt_metric(base_all.get('silence_pct'), 1, '%')} | "
                f"{fmt_metric(cand_all.get('silence_pct'), 1, '%')} | "
                f"{fmt_delta_abs(base_all.get('silence_pct'), cand_all.get('silence_pct'), ' pp')} |"
            ),
            "",
            "> Latenza, CPU e RAM: valori più bassi sono migliori. RTF: valori più alti sono "
            "migliori. Le metriche audio sono proxy oggettivi, non un giudizio di qualità.",
            "",
            "## Per categoria",
            "",
            "| Categoria | Latenza baseline | Latenza candidato | Δ | RTF baseline | RTF candidato |",
            "| --- | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for category in sorted(set(base_cat) | set(cand_cat)):
        base_cat_row = base_cat.get(category, {})
        cand_cat_row = cand_cat.get(category, {})
        lines.append(
            f"| {category} | "
            f"{fmt_metric(base_cat_row.get('wall_ms'), 0, ' ms')} | "
            f"{fmt_metric(cand_cat_row.get('wall_ms'), 0, ' ms')} | "
            f"{fmt_delta_pct(base_cat_row.get('wall_ms'), cand_cat_row.get('wall_ms'))} | "
            f"{fmt_metric(base_cat_row.get('rtf'), 2, 'x')} | "
            f"{fmt_metric(cand_cat_row.get('rtf'), 2, 'x')} |"
        )

    lines.extend(
        [
            "",
            "## Per testo",
            "",
            "| Testo | Categoria | Baseline | Candidato | Δ |",
            "| --- | --- | ---: | ---: | ---: |",
        ]
    )
    for text_id in all_ids:
        base_row = base_by_id.get(text_id, {})
        cand_row = cand_by_id.get(text_id, {})
        lines.append(
            f"| {text_id} | {base_row.get('category') or cand_row.get('category') or ''} | "
            f"{fmt_metric(base_row.get('wall_ms'), 0, ' ms')} | "
            f"{fmt_metric(cand_row.get('wall_ms'), 0, ' ms')} | "
            f"{fmt_delta_pct(base_row.get('wall_ms'), cand_row.get('wall_ms'))} |"
        )

    lines.extend(["", "## Segnali da verificare", ""])
    if warnings:
        lines.extend(f"- {warning}" for warning in warnings)
    else:
        lines.append("- Nessun segnale automatico oltre i limiti configurati.")
    lines.extend(
        [
            "",
            "La qualità percepita non è deducibile da queste misure. Eseguire anche "
            "`scripts/tts_asr_eval.py` e la scheda di ascolto cieco descritta in "
            "`benchmarks/README.md`.",
            "",
        ]
    )
    return "\n".join(lines)


def cmd_compare(args: argparse.Namespace) -> int:
    baseline = load_results(Path(args.baseline))
    candidate = load_results(Path(args.candidate))
    report = build_report(baseline, candidate, args.mode)
    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(report, encoding="utf-8")
        print(f"Report: {output_path}")
    else:
        print(report)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Benchmark qualità e velocità della pipeline TTS locale."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    run = subparsers.add_parser("run", help="Esegue il corpus contro un backend.")
    run.add_argument("--label", default="run", help="Etichetta dell'esecuzione.")
    run.add_argument("--base-url", default="http://127.0.0.1:7788")
    run.add_argument("--corpus", default=str(DEFAULT_CORPUS))
    run.add_argument("--output", default=None, help="File JSON di destinazione.")
    run.add_argument("--voice", default="M1")
    run.add_argument("--lang", default="it")
    run.add_argument("--steps", type=int, default=8)
    run.add_argument("--speed", type=float, default=1.0)
    run.add_argument("--passes", type=int, default=1, help="Passate sul corpus.")
    run.add_argument(
        "--runs",
        type=int,
        default=3,
        help="Richieste per testo in ogni passata; la prima è cold, le altre warm.",
    )
    run.add_argument("--limit", type=int, default=0, help="Limita il numero di testi.")
    run.add_argument("--timeout", type=float, default=120.0)
    run.add_argument("--warmup", action=argparse.BooleanOptionalAction, default=True)
    run.add_argument("--warmup-text", default=DEFAULT_WARMUP_TEXT)
    run.add_argument("--save-audio-dir", default=None)
    run.add_argument("--fail-fast", action="store_true")
    run.add_argument("--server-pid", type=int, default=None)
    run.add_argument(
        "--server-cmd",
        default=None,
        help="Comando per avviare il backend (es. '.venv/bin/python -m backend.main').",
    )
    run.add_argument("--server-cwd", default=str(ROOT))
    run.add_argument(
        "--server-env",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="Variabile d'ambiente per il server avviato con --server-cmd.",
    )
    run.add_argument("--server-log", default=None)
    run.add_argument("--startup-timeout", type=float, default=300.0)
    run.add_argument(
        "--restart-between-passes",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Riavvia il server tra le passate per misure cold reali.",
    )

    compare = subparsers.add_parser("compare", help="Confronta due file di risultati.")
    compare.add_argument("--baseline", required=True)
    compare.add_argument("--candidate", required=True)
    compare.add_argument("--output", default=None, help="Report Markdown di destinazione.")
    compare.add_argument("--mode", choices=("cold", "warm", "all"), default="cold")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "run":
        return cmd_run(args)
    if args.command == "compare":
        return cmd_compare(args)
    parser.error("comando sconosciuto")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
