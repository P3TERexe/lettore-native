"""Schemi Pydantic del backend."""

from typing import Literal

from pydantic import BaseModel, Field


class TTSRequest(BaseModel):
    text: str = Field(min_length=1, max_length=20000)
    lang: str = "auto"
    voice: str = "M1"
    steps: int = Field(default=8, ge=5, le=12)
    speed: float = Field(default=1.05, ge=0.7, le=2.0)


class BatchItem(BaseModel):
    text: str = Field(min_length=1, max_length=20000)
    lang: str = "auto"
    voice: str = "M1"
    speed: float = Field(default=1.05, ge=0.7, le=2.0)


class BatchRequest(BaseModel):
    items: list[BatchItem] = Field(min_length=1, max_length=64)
    defaults: dict | None = None
    response_format: Literal["wav"] = "wav"


class BatchResult(BaseModel):
    wav_base64: str
    duration_ms: int


class BatchResponse(BaseModel):
    results: list[BatchResult]


class ExportRequest(BaseModel):
    text: str = Field(min_length=1, max_length=50000)
    lang: str = "auto"
    voice: str = "M1"
    steps: int = Field(default=8, ge=5, le=12)
    speed: float = Field(default=1.05, ge=0.7, le=2.0)


class Job(BaseModel):
    id: str
    text: str
    lang: str = "auto"
    voice: str = "M1"
    steps: int = 8
    speed: float = 1.05
    status: Literal["pending", "playing", "done", "cancelled"] = "pending"
    duration_ms: int | None = None


class QueueAddRequest(BaseModel):
    text: str = Field(min_length=1, max_length=50000)
    lang: str = "auto"
    voice: str = "M1"
    steps: int = Field(default=8, ge=5, le=12)
    speed: float = Field(default=1.05, ge=0.7, le=2.0)
    split_paragraphs: bool = False


class QueueAddResponse(BaseModel):
    job_ids: list[str]
    split_into: int


class QueueState(BaseModel):
    state: Literal["idle", "playing", "paused", "stopped"]
    current: Job | None = None
    jobs: list[Job]


class VoiceEntry(BaseModel):
    id: str
    name: str
    langs: list[str]
    group: Literal["builtin", "custom"]


class VoiceList(BaseModel):
    builtin: list[VoiceEntry]
    custom: list[VoiceEntry]


class VoiceUpdate(BaseModel):
    name: str | None = None
    langs: list[str] | None = None


class LanguageEntry(BaseModel):
    code: str
    label: str


class StatusResponse(BaseModel):
    ready: bool
    model_loading: bool
    model: str
    sample_rate: int | None = None
    capture_enabled: bool
    capture_available: bool
    capture_permission: bool = False
    queue: QueueState


class CaptureRequest(BaseModel):
    auto_copy: bool = False


class AppConfig(BaseModel):
    voice: str = "M1"
    lang: str = "auto"
    speed: float = Field(default=1.05, ge=0.7, le=2.0)
    steps: int = Field(default=8, ge=5, le=12)
    capture_auto: bool = False


class CaptureResponse(BaseModel):
    text: str
    source: str
    error: str | None = None
