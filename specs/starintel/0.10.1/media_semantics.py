"""SL05 0.10.1 media-time and evidence-integrity semantic rules.

Run this AFTER generated-schema validation. Media offsets are relative to the
source asset, not Unix timestamps. These checks never authenticate an artifact,
resolve an identity, or turn a model output into a verified claim.
"""

from __future__ import annotations

from decimal import Decimal, InvalidOperation
from typing import Mapping


INTERVAL_DTYPES = frozenset(
    {"audio-segment", "speech-segment", "speaker-observation", "speaker-turn"}
)
AFFECTED_DTYPES = INTERVAL_DTYPES | {
    "video-frame", "picture", "transcript", "audio", "video", "image", "media",
    "source", "evidence-record",
}


def _nonnegative_integer(value: object, name: str) -> int:
    if type(value) is not int or value < 0:
        raise ValueError(f"{name} must be a nonnegative integer")
    return value


def _positive_integer(value: object, name: str) -> int:
    result = _nonnegative_integer(value, name)
    if result == 0:
        raise ValueError(f"{name} must be positive")
    return result


def _decimal(value: object, name: str, *, positive: bool = False) -> None:
    # Wire decimals are canonical strings; do not round-trip through float.
    if not isinstance(value, str):
        raise ValueError(f"{name} must be a decimal string")
    try:
        parsed = Decimal(value)
    except InvalidOperation as exc:
        raise ValueError(f"{name} must be a decimal string") from exc
    if not parsed.is_finite() or parsed < 0 or (positive and parsed == 0):
        raise ValueError(f"{name} is outside the permitted range")


def _interval(record: Mapping[str, object], prefix: str) -> None:
    start = _nonnegative_integer(record.get("startMs"), f"{prefix}.startMs")
    end = _nonnegative_integer(record.get("endMs"), f"{prefix}.endMs")
    if end <= start:
        raise ValueError(f"{prefix}.endMs must be greater than startMs")


def _payload_hash_pair(record: Mapping[str, object], dtype: str) -> None:
    digest = record.get("payloadContentHash")
    algorithm = record.get("payloadHashAlgorithm")
    if digest is None and algorithm is None:
        return
    if not (isinstance(digest, str) and digest.strip()
            and isinstance(algorithm, str) and algorithm.strip()):
        raise ValueError(f"{dtype} must pair payloadContentHash and payloadHashAlgorithm")
    # Algorithm spelling and digest bytes belong to the source artifact. This
    # validator does not claim cryptographic verification of stored content.


def validate_media_evidence_semantics(document: Mapping[str, object]) -> None:
    """Reject impossible temporal evidence and unidentifiable payload hashes.

    Unknown dtypes are deliberately outside this domain gate; call the
    generated validator first so unknown wire types cannot evade validation.
    """
    if not isinstance(document, Mapping):
        raise ValueError("StarIntel document must be an object")
    dtype = document.get("dtype")
    if dtype not in AFFECTED_DTYPES:
        return
    if document.get("schemaVersion") != "0.10.1":
        raise ValueError("media evidence gate requires canonical 0.10.1 input")

    if dtype == "video-frame":
        _nonnegative_integer(document.get("frameIndex"), "video-frame.frameIndex")
        _nonnegative_integer(document.get("timestampMs"), "video-frame.timestampMs")

    if dtype in INTERVAL_DTYPES:
        _interval(document, str(dtype))
        if dtype == "speaker-turn":
            _nonnegative_integer(document.get("turnIndex"), "speaker-turn.turnIndex")

    if dtype == "transcript":
        for index, timing in enumerate(document.get("wordTimings", [])):
            if not isinstance(timing, Mapping):
                raise ValueError(f"transcript.wordTimings[{index}] must be an object")
            # Older provider timing maps may use opaque keys. Preserve those
            # intact; validate canonical startMs/endMs only when asserted.
            if "startMs" in timing or "endMs" in timing:
                _interval(timing, f"transcript.wordTimings[{index}]")
        start = document.get("startedAt")
        end = document.get("completedAt")
        if start is not None and end is not None and end < start:
            raise ValueError("transcript.completedAt precedes startedAt")

    positive_fields = {
        "media": ("width", "height"),
        "image": ("width", "height"),
        "picture": ("width", "height"),
        "video-frame": ("width", "height"),
        "video": ("width", "height"),
        "audio": ("sampleRateHz", "channels", "bitDepth"),
    }
    for field in positive_fields.get(str(dtype), ()):
        if field in document:
            _positive_integer(document[field], f"{dtype}.{field}")
    if dtype == "video":
        for field in ("frameCount", "bitrate"):
            if field in document:
                _nonnegative_integer(document[field], f"video.{field}")
        if "frameRate" in document:
            _decimal(document["frameRate"], "video.frameRate", positive=True)
    if dtype in {"media", "audio", "video"} and "durationSeconds" in document:
        _decimal(document["durationSeconds"], f"{dtype}.durationSeconds")

    if dtype in {"source", "evidence-record"}:
        _payload_hash_pair(document, str(dtype))

