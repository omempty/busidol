"""조합형(Johab/KSSM) 한국어 인코딩 유틸 — 원본 소스·대사 공통 처리.

원본 자산(BSD/BOMB/BOMB95)의 한국어 텍스트는 전부 조합형 인코딩이다.
검증 이력: docs/01_analysis/01_project_overview.md §4
"""
from __future__ import annotations

from pathlib import Path

REPLACEMENT = "\ufffd"


def decode(data: bytes, *, replace: bool = True) -> str:
    """바이트를 Johab으로 디코딩. replace=True면 오류 바이트를 U+FFFD로 치환."""
    return data.decode("johab", errors="replace" if replace else "strict")


def load_text(path: str | Path) -> str:
    """파일을 읽어 Johab 디코딩(replace 모드)."""
    return decode(Path(path).read_bytes())


def contaminated_lines(text: str) -> list[int]:
    """U+FFFD가 남은 줄 번호(1-based) 목록 — 원문 복원 대상(SE1 단계 입력)."""
    return [i for i, line in enumerate(text.splitlines(), 1) if REPLACEMENT in line]
