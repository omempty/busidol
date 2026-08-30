"""원작 VOC(Creative Voice File) → WAV 변환.

04_uiux §5가 정한 항목: **원작 VOC 보이스는 재생성이 아니라 변환해서 그대로 쓴다**
(원작 정체성). 2026-08-30까지 `assets/audio/voice/`가 아예 없었고 `play_voice()`
호출부도 0곳이었다 — 버스와 API만 있고 소리가 없는 상태.

원본은 `originals/1995_sidol_bsd_dos/*.VOC` 6종인데 **꼴이 셋으로 갈린다**(실측):
  Creative Voice File  D1 · DEAD · DOMANG · WIN - 표준 헤더 26바이트 + 블록 타입 1
  Saintcom Voice File  SMILE3 - 국산 사운드카드 변종. 서명만 다르고 배치는 같다
  헤더 없음            DOOR - 생 8비트 PCM. 레이트를 파일이 아니라 호출부가 알았다
  공통: 코덱 0 = 8비트 무부호 PCM · 레이트 = 1000000 / (256 - sr_code)
  실측 D1 8,620Hz · DEAD/DOMANG/WIN 8,403Hz · DOOR 8,050Hz · SMILE3 10,989Hz

**DEAD·DOMANG·WIN은 바이트 단위로 같은 파일이다**(sha256 c4f6afcc…). 원작에서
승리·패배·도망이 한 소리였다는 뜻이다 - 고증이므로 셋 다 그대로 둔다
(obj 173, ATT 185/186과 같은 처리).

블록 타입 9(확장 포맷)도 읽어 둔다 — 지금 6종에는 없지만, 나중에 다른 원작에서
같은 도구를 쓸 때 조용히 틀린 소리를 내는 것보다 낫다.

실행:
  python tools/convert/voc_convert.py                 # 기본 경로로 전량 변환
  python tools/convert/voc_convert.py --check         # 변환 없이 대상만 보고
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC_DIR = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos"
OUT_DIR = ROOT / "assets" / "audio" / "voice"

# 원본 6종은 **세 가지 꼴이 섞여 있다**(2026-08-30 실측):
#   Creative Voice File  - D1 · DEAD · DOMANG · WIN (표준)
#   Saintcom Voice File  - SMILE3 (국산 사운드카드 변종. 헤더 배치는 같다)
#   헤더 없음            - DOOR (생 8비트 PCM). 원작이 재생 직전 VoiceStart(8050)으로
#                          샘플레이트를 넘겼다(GOODITEM.C:1402) - 파일이 아니라 **호출부가**
#                          레이트를 알고 있었다. 그래서 아래 RAW_RATES에 그 값을 적어 둔다.
MAGICS = (b"Creative Voice File\x1a", b"Saintcom Voice File\x1a")
## 헤더 없는 생 PCM의 샘플레이트 - 근거는 원작 소스의 VoiceStart() 인자.
RAW_RATES = {"door": 8050}
DEFAULT_RAW_RATE = 8000


class VocError(Exception):
    pass


def parse_voc(data: bytes, stem: str = "") -> tuple[int, int, bytes]:
    """VOC 바이트 → (샘플레이트, 채널, 8비트 무부호 PCM). 블록 여러 개면 이어 붙인다."""
    if not data.startswith(MAGICS):
        # 헤더 없는 생 PCM - 원작이 실제로 그렇게 넣어 뒀다(DOOR).
        return RAW_RATES.get(stem.lower(), DEFAULT_RAW_RATE), 1, data
    hdr_size = struct.unpack("<H", data[20:22])[0]
    pos = hdr_size
    rate = 0
    channels = 1
    chunks: list[bytes] = []
    while pos < len(data):
        btype = data[pos]
        if btype == 0:  # terminator
            break
        if pos + 4 > len(data):
            raise VocError("블록 헤더가 잘렸다")
        blen = int.from_bytes(data[pos + 1 : pos + 4], "little")
        body = data[pos + 4 : pos + 4 + blen]
        if btype == 1:  # 사운드 데이터
            sr_code = body[0]
            codec = body[1]
            if codec != 0:
                raise VocError(f"지원하지 않는 코덱 {codec}(8비트 PCM만)")
            rate = rate or int(1000000 / (256 - sr_code))
            chunks.append(body[2:])
        elif btype == 2:  # 이어지는 사운드 데이터(헤더 없음)
            chunks.append(body)
        elif btype == 9:  # 확장 사운드 데이터
            rate = rate or struct.unpack("<I", body[0:4])[0]
            bits = body[4]
            channels = body[5] + 1
            if bits != 8:
                raise VocError(f"지원하지 않는 비트수 {bits}")
            chunks.append(body[12:])
        # 그 밖(무음·표식·반복)은 건너뛴다 — 6종에 없고, 있으면 길이만 달라진다.
        pos += 4 + blen
    if not chunks or rate <= 0:
        raise VocError("사운드 블록이 없다")
    return rate, channels, b"".join(chunks)


def write_wav(path: Path, rate: int, channels: int, pcm8: bytes) -> None:
    """8비트 무부호 PCM WAV. 원본 그대로 — 리샘플·정규화하지 않는다(정체성 보존)."""
    block_align = channels
    header = b"RIFF" + struct.pack("<I", 36 + len(pcm8)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, channels, rate, rate * block_align, block_align, 8)
    header += b"data" + struct.pack("<I", len(pcm8))
    path.write_bytes(header + pcm8)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, default=SRC_DIR)
    ap.add_argument("--out", type=Path, default=OUT_DIR)
    ap.add_argument("--check", action="store_true", help="변환하지 않고 대상만 본다")
    args = ap.parse_args()

    if not args.src.is_dir():
        print(f"[voc] 원본 폴더 없음 — SKIP: {args.src}")
        return 0  # 원본은 저장소 밖이다. 없는 PC에서도 실패로 만들지 않는다.

    # Windows의 glob은 대소문자를 안 가려 *.VOC와 *.voc가 같은 파일을 두 번 준다.
    files = sorted({f.resolve() for f in args.src.glob("*.[Vv][Oo][Cc]")})
    if not files:
        print(f"[voc] VOC 없음 — SKIP: {args.src}")
        return 0

    if not args.check:
        args.out.mkdir(parents=True, exist_ok=True)

    total = 0
    for f in files:
        try:
            rate, ch, pcm = parse_voc(f.read_bytes(), f.stem)
        except VocError as e:
            print(f"[voc] FAIL {f.name}: {e}")
            return 1
        secs = len(pcm) / float(rate * ch)
        out = args.out / (f.stem.lower() + ".wav")
        print(f"[voc] {f.name:12s} {rate:6d}Hz ch{ch} {len(pcm):7d}B {secs:5.2f}s -> {out.name}")
        if not args.check:
            write_wav(out, rate, ch, pcm)
        total += 1
    print(f"[voc] {'검사' if args.check else '변환'} {total}종 완료")
    return 0


if __name__ == "__main__":
    sys.exit(main())
