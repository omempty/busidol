"""리터칭 비교 뷰어 생성기 - assets/gen/viewers/retouch_compare.html 출력.

기존 뷰어(character_bible.html / tile_viewer.html)와 동일한 자체완결 단일 파일
규약(base64 내장)을 따른다. samples/ 의 *_original.png / *_retouched.png 쌍을
스캔해 A/B 토글 + 나란히 보기 + 스와이프 슬라이더 뷰를 내장한다.

사용: python tools/convert/gen_compare_viewer.py
"""
from __future__ import annotations
import base64
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SAMPLES = os.path.join(ROOT, "assets", "gen", "viewers", "samples")
OUT = os.path.join(ROOT, "assets", "gen", "viewers", "retouch_compare.html")


def b64(path: str) -> str:
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def main() -> None:
    names = sorted(f[:-len("_original.png")]
                   for f in os.listdir(SAMPLES)
                   if f.endswith("_original.png"))
    items = []
    for n in names:
        items.append({
            "name": n,
            "original": b64(os.path.join(SAMPLES, f"{n}_original.png")),
            "retouched": b64(os.path.join(SAMPLES, f"{n}_retouched.png")),
        })
    import json
    payload = json.dumps(items, ensure_ascii=False)

    html = TEMPLATE.replace("__PAYLOAD__", payload)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(html)
    print(f"ok: {OUT} ({len(items)} pairs)")


TEMPLATE = """<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<title>Sidol Remake - Retouch Compare (A/B)</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', sans-serif; background: #12141a; color: #d0d5e0;
         display: flex; height: 100vh; overflow: hidden; }
  #sidebar { width: 300px; background: #1a1d26; border-right: 1px solid #2a2f3d;
             padding: 16px; overflow-y: auto; }
  #main { flex: 1; padding: 20px; display: flex; flex-direction: column;
          align-items: center; gap: 12px; overflow: auto; }
  h2 { color: #64b5f6; font-size: 15px; margin-bottom: 10px; }
  .item { padding: 7px 10px; cursor: pointer; border-bottom: 1px solid #232733;
          font-family: monospace; font-size: 13px; }
  .item:hover { background: #232936; }
  .item.sel { background: #2c3550; color: #ffd54f; }
  .bar { display: flex; gap: 10px; align-items: center; flex-wrap: wrap;
         justify-content: center; }
  button { background: #2a3040; color: #d0d5e0; border: 1px solid #3a4256;
           padding: 6px 14px; border-radius: 6px; cursor: pointer; }
  button.on { background: #40518f; color: #fff; }
  input[type=range] { width: 220px; }
  .stage { position: relative; background:
           repeating-conic-gradient(#20242f 0% 25%, #171a23 0% 50%) 50% / 16px 16px;
           border: 2px solid #333a4d; border-radius: 8px; overflow: hidden; }
  .stage canvas { image-rendering: pixelated; display: block; position: absolute; top: 0; left: 0; }
  .lbl { position: absolute; top: 6px; font: bold 12px monospace; padding: 2px 8px;
         border-radius: 4px; background: rgba(0,0,0,.55); }
  #note { color: #90a4ae; font-size: 12px; max-width: 720px; line-height: 1.5; }
</style>
</head>
<body>
<div id="sidebar">
  <h2>리터칭 시범 - 원본 vs 리터치</h2>
  <div id="list"></div>
  <p style="margin-top:12px;font-size:11px;color:#78909c;line-height:1.6">
    파이프라인: 배경 제거 &rarr; 마스터 팔레트 잠금(256색) &rarr; 5단 명암 밴딩<br>
    + 남보라 색조 그림자/웜 하이라이트 &rarr; 남색 1px 아웃라인 &rarr; 4x nearest.<br>
    스타일 바이블 준수(블랙 외곽선·순수 확대 금지).<br><br>
    단축키: <b>A</b>/원본 · <b>D</b>/리터치 · <b>Q</b> 나란히 · <b>W</b> 스와이프
  </p>
</div>
<div id="main">
  <div class="bar">
    <button id="bA">원본 (A)</button>
    <button id="bB" class="on">리터치 (D)</button>
    <button id="bSide">나란히 (Q)</button>
    <button id="bSwipe">스와이프 (W)</button>
    <label>확대 <input id="zoom" type="range" min="0.2" max="2" step="0.05" value="0.55"></label>
    <span id="pct" style="font-family:monospace;color:#ffb74d"></span>
  </div>
  <div class="bar" id="swipeBar" style="display:none">
    <input id="split" type="range" min="0" max="100" value="50">
    <span style="font-family:monospace">스와이프 위치</span>
  </div>
  <div class="stage" id="stage"></div>
  <div id="note">팔레트 잠금 상태에서의 실루엣·명암 5단·색조 그림자 적용 결과를 확인하세요.
  채택/반려는 각 항목 옆 판정 메모로 남겨주세요(에셋 에이전트 경계 규칙).</div>
</div>
<script>
const ITEMS = __PAYLOAD__;
let cur = 0, mode = "B", zoom = 0.55, split = 50;
const stage = document.getElementById('stage');
const listEl = document.getElementById('list');

ITEMS.forEach((it, i) => {
  const d = document.createElement('div');
  d.className = 'item' + (i === 0 ? ' sel' : '');
  d.textContent = it.name;
  d.onclick = () => { cur = i;
    document.querySelectorAll('.item').forEach((e,j)=>e.classList.toggle('sel', j===i));
    render(); };
  listEl.appendChild(d);
});

const imgs = {};
function img(key) {
  if (!imgs[key]) { const im = new Image(); im.src = ITEMS[cur][key]; imgs[key] = im; }
  return imgs[key];
}
let origImg = null, retImg = null;

function render() {
  const it = ITEMS[cur];
  if (!origImg || origImg.dataset.name !== it.name) {
    origImg = new Image(); origImg.src = it.original; origImg.dataset.name = it.name;
    retImg = new Image(); retImg.src = it.retouched; retImg.dataset.name = it.name;
    Promise.all([new Promise(r=>origImg.onload=r), new Promise(r=>retImg.onload=r)])
      .then(draw);
  }
  draw();
}

function draw() {
  if (!origImg || !origImg.complete || !retImg.complete) return;
  const iw = Math.max(origImg.naturalWidth, retImg.naturalWidth) * zoom;
  const ih = Math.max(origImg.naturalHeight, retImg.naturalHeight) * zoom;
  stage.style.width = iw + 'px'; stage.style.height = ih + 'px';
  stage.innerHTML = '';
  document.querySelectorAll('.lbl').forEach(e=>e.remove());

  function addCanvas(src, sx) {
    const cv = document.createElement('canvas');
    cv.width = iw; cv.height = ih;
    cv.style.left = (sx||0) + 'px';
    const ctx = cv.getContext('2d');
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(src, 0, 0, src.naturalWidth * zoom, src.naturalHeight * zoom);
    stage.appendChild(cv);
    return cv;
  }

  if (mode === 'side') {
    stage.style.width = (iw * 2 + 8) + 'px';
    addCanvas(origImg, 0);
    addCanvas(retImg, iw + 8);
    addLabel('ORIGINAL', 6); addLabel('RETOUCHED', iw + 14);
  } else if (mode === 'swipe') {
    addCanvas(origImg, 0);
    const cv = addCanvas(retImg, 0);
    cv.style.clipPath = 'inset(0 0 0 ' + split + '%)';
    const line = document.createElement('div');
    line.style.cssText = 'position:absolute;top:0;bottom:0;left:' + split +
      '%;width:2px;background:#ffd54f';
    stage.appendChild(line);
    addLabel('ORIGINAL', 6); 
    const l2 = addLabel('RETOUCHED', iw - 110); l2.style.left = 'auto';
    l2.style.right = '6px';
  } else {
    addCanvas(mode === 'A' ? origImg : retImg, 0);
    addLabel(mode === 'A' ? 'ORIGINAL' : 'RETOUCHED', 6);
  }
}

function addLabel(text, left) {
  const l = document.createElement('div');
  l.className = 'lbl'; l.textContent = text; l.style.left = left + 'px';
  stage.appendChild(l);
  return l;
}

function setMode(m) {
  mode = m;
  [['bA','A'],['bB','B'],['bSide','side'],['bSwipe','swipe']].forEach(([id,v]) =>
    document.getElementById(id).classList.toggle('on',
      v === m || (v === 'B' && m === 'B')));
  document.getElementById('swipeBar').style.display =
    m === 'swipe' ? 'flex' : 'none';
  render();
}
document.getElementById('bA').onclick = () => setMode('A');
document.getElementById('bB').onclick = () => setMode('B');
document.getElementById('bSide').onclick = () => setMode('side');
document.getElementById('bSwipe').onclick = () => setMode('swipe');
document.getElementById('zoom').oninput = e => {
  zoom = parseFloat(e.target.value);
  document.getElementById('pct').textContent = Math.round(zoom*100) + '%';
  render();
};
document.getElementById('split').oninput = e => { split = +e.target.value; render(); };
document.addEventListener('keydown', e => {
  if (e.key === 'a' || e.key === 'A') setMode('A');
  if (e.key === 'd' || e.key === 'D') setMode('B');
  if (e.key === 'q' || e.key === 'Q') setMode('side');
  if (e.key === 'w' || e.key === 'W') setMode('swipe');
});

render();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
