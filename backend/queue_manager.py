"""QueueManager: coda FIFO thread-safe per la lettura continua."""

import threading
import uuid

from .chunking import smart_chunk_text
from .models import Job, QueueState


class QueueManager:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.jobs: list[Job] = []
        self.current: Job | None = None
        self.state: str = "idle"

    def add(
        self,
        text: str,
        lang: str,
        voice: str,
        steps: int,
        speed: float,
        split_paragraphs: bool = False,
    ) -> list[str]:
        chunks = smart_chunk_text(
            text=text,
            lang=lang,
            split_paragraphs=split_paragraphs,
        )
        chunks = [c for c in chunks if c]

        ids: list[str] = []
        with self._lock:
            for chunk in chunks:
                job = Job(
                    id=uuid.uuid4().hex[:8],
                    text=chunk,
                    lang=lang,
                    voice=voice,
                    steps=steps,
                    speed=speed,
                )
                self.jobs.append(job)
                ids.append(job.id)
        return ids

    def play(self) -> Job | None:
        with self._lock:
            self.state = "playing"
            return self._advance_locked()

    def pause(self) -> None:
        with self._lock:
            self.state = "paused"

    def stop(self) -> None:
        with self._lock:
            self.state = "stopped"
            self.jobs = []
            self.current = None

    def done(self) -> Job | None:
        """Segna il job corrente come completato e avanza."""
        with self._lock:
            if self.current is not None:
                self.current = self.current.model_copy(update={"status": "done"})
            if self.state == "playing":
                return self._advance_locked()
            self._reconcile_locked()
            return None

    def remove(self, job_id: str) -> bool:
        with self._lock:
            before = len(self.jobs)
            self.jobs = [j for j in self.jobs if j.id != job_id]
            if self.current is not None and self.current.id == job_id:
                self.current = None
            if len(self.jobs) != before or self.current is None:
                self._reconcile_locked()
            return len(self.jobs) != before or self.current is not None

    def clear(self) -> None:
        with self._lock:
            self.jobs = []
            if self.current is None:
                self.state = "idle"
            else:
                self._reconcile_locked()

    def snapshot(self) -> QueueState:
        with self._lock:
            return QueueState(
                state=self.state,
                current=self.current.model_copy() if self.current else None,
                jobs=[j.model_copy() for j in self.jobs],
            )

    def _advance_locked(self) -> Job | None:
        if self.current is not None and self.current.status == "playing":
            return self.current
        if self.jobs:
            self.current = self.jobs.pop(0)
            self.current.status = "playing"
            return self.current
        if self.current is not None and self.current.status == "done":
            self.current = None
        if self.current is None:
            self.state = "idle"
        return None

    def _reconcile_locked(self) -> None:
        if self.current is None and not self.jobs:
            if self.state in ("playing", "paused"):
                self.state = "idle"
