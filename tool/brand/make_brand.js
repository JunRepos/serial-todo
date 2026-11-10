// 할일이많아 브랜드 에셋 생성기
//   node tool/brand/make_brand.js
// 아이콘(계단 + 체크) SVG를 만들고, Chrome 헤드리스로 PNG(안드로이드·웹·Play 스토어)를 그린다.
// 안드로이드 적응형 아이콘 전경/모노크롬은 VectorDrawable XML로 따로 쓴다(해상도 무관).
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '../..');
const OUT_TMP = path.join(ROOT, 'build', 'brand');
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';

const BRAND = '#2E5B4E';
const BRAND_DEEP = '#234A3F';
const STEP = '#FFFFFF';
const CHECK = '#A6E3CB';

// 108×108 적응형 아이콘 좌표계. 안전 영역(지름 66) 안에 들어가게 배치.
const STAIRS = 'M30,80 V68 H46 V56 H62 V44 H78 V80 Z';
const CHECK_PATH = 'M58.5,31.5 L65,38 L78.5,24.5';

function fg(colorStep = STEP, colorCheck = CHECK) {
  return `
  <path d="${STAIRS}" fill="${colorStep}" stroke="${colorStep}" stroke-width="4" stroke-linejoin="round"/>
  <path d="${CHECK_PATH}" fill="none" stroke="${colorCheck}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>`;
}

/** 꽉 찬 정사각형 (maskable·Play 스토어용, 모서리는 플랫폼이 깎는다) */
function svgSquare() {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${BRAND}"/><stop offset="1" stop-color="${BRAND_DEEP}"/></linearGradient></defs>
  <rect width="108" height="108" fill="url(#g)"/>${fg()}
</svg>`;
}

/** 둥근 사각형 (구형 안드로이드 런처·파비콘용). 전경을 조금 키워 작은 크기에서도 잘 보이게. */
function svgRounded() {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${BRAND}"/><stop offset="1" stop-color="${BRAND_DEEP}"/></linearGradient></defs>
  <rect x="4" y="4" width="100" height="100" rx="24" fill="url(#g)"/>
  <g transform="translate(54 52) scale(1.18) translate(-54 -52)">${fg()}</g>
</svg>`;
}

function featureGraphic() {
  const font = path.join(ROOT, 'assets/fonts/Pretendard-Bold.otf').replace(/\\/g, '/');
  const fontR = path.join(ROOT, 'assets/fonts/Pretendard-Regular.otf').replace(/\\/g, '/');
  return `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:P;src:url("file:///${font}");font-weight:700}
@font-face{font-family:P;src:url("file:///${fontR}");font-weight:400}
html,body{margin:0;width:1024px;height:500px;overflow:hidden}
body{background:linear-gradient(135deg,${BRAND} 0%,${BRAND_DEEP} 100%);font-family:P,sans-serif;color:#fff;display:flex;align-items:center}
.icon{width:220px;height:220px;margin-left:96px;flex:none}
.t{margin-left:56px}
h1{font-size:84px;font-weight:700;margin:0;letter-spacing:-2px}
p{font-size:32px;margin:14px 0 0;color:${CHECK};font-weight:400}
</style></head><body>
<svg class="icon" viewBox="0 0 108 108"><rect x="4" y="4" width="100" height="100" rx="26" fill="rgba(255,255,255,.08)"/>${fg()}</svg>
<div class="t"><h1>할일이많아</h1><p>큰 목표를 쪼개고, 순서대로 하나씩</p></div>
</body></html>`;
}

function shot(htmlFile, pngFile, w, h) {
  fs.mkdirSync(path.dirname(pngFile), { recursive: true });
  execFileSync(CHROME, [
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
    '--default-background-color=00000000', `--window-size=${w},${h}`,
    `--screenshot=${pngFile}`, 'file:///' + htmlFile.replace(/\\/g, '/'),
  ], { stdio: 'ignore' });
  if (!fs.existsSync(pngFile)) throw new Error('screenshot failed: ' + pngFile);
}

function svgPng(svg, pngFile, size) {
  fs.mkdirSync(OUT_TMP, { recursive: true });
  const html = path.join(OUT_TMP, `tmp_${size}_${path.basename(pngFile)}.html`);
  fs.writeFileSync(html, `<!doctype html><html><body style="margin:0;background:transparent">
<div style="width:${size}px;height:${size}px">${svg.replace('<svg ', `<svg width="${size}" height="${size}" `)}</div></body></html>`);
  shot(html, pngFile, size, size);
}

// ---- 원본 SVG 보관
const brandDir = path.join(ROOT, 'assets', 'brand');
fs.mkdirSync(brandDir, { recursive: true });
fs.writeFileSync(path.join(brandDir, 'icon-square.svg'), svgSquare());
fs.writeFileSync(path.join(brandDir, 'icon-rounded.svg'), svgRounded());

// ---- 안드로이드: 구형 런처용 PNG
const dens = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
for (const [d, s] of Object.entries(dens)) {
  svgPng(svgRounded(), path.join(ROOT, `android/app/src/main/res/mipmap-${d}/ic_launcher.png`), s);
}

// ---- 안드로이드: 적응형 아이콘 (API 26+), 테마 아이콘(API 33+)
const res = path.join(ROOT, 'android/app/src/main/res');
const vec = (body) => `<?xml version="1.0" encoding="utf-8"?>
<!-- tool/brand/make_brand.js 가 생성 -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
${body}
</vector>
`;
const stairsVec = (c) => `    <path android:pathData="${STAIRS}" android:fillColor="${c}"
        android:strokeColor="${c}" android:strokeWidth="4" android:strokeLineJoin="round" />`;
const checkVec = (c) => `    <path android:pathData="${CHECK_PATH}" android:fillColor="#00000000"
        android:strokeColor="${c}" android:strokeWidth="6" android:strokeLineCap="round" android:strokeLineJoin="round" />`;
fs.writeFileSync(path.join(res, 'drawable/ic_launcher_foreground.xml'), vec(stairsVec(STEP) + '\n' + checkVec(CHECK)));
fs.writeFileSync(path.join(res, 'drawable/ic_launcher_monochrome.xml'), vec(stairsVec('#FFFFFFFF') + '\n' + checkVec('#FFFFFFFF')));
fs.mkdirSync(path.join(res, 'mipmap-anydpi-v26'), { recursive: true });
fs.writeFileSync(path.join(res, 'mipmap-anydpi-v26/ic_launcher.xml'), `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
`);
fs.writeFileSync(path.join(res, 'values/ic_launcher_colors.xml'), `<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">${BRAND}</color>
    <color name="splash_background">${BRAND}</color>
</resources>
`);

// ---- 웹
svgPng(svgRounded(), path.join(ROOT, 'web/favicon.png'), 64);
svgPng(svgRounded(), path.join(ROOT, 'web/icons/Icon-192.png'), 192);
svgPng(svgRounded(), path.join(ROOT, 'web/icons/Icon-512.png'), 512);
svgPng(svgSquare(), path.join(ROOT, 'web/icons/Icon-maskable-192.png'), 192);
svgPng(svgSquare(), path.join(ROOT, 'web/icons/Icon-maskable-512.png'), 512);

// ---- Play 스토어
const store = path.join(ROOT, 'store');
svgPng(svgSquare(), path.join(store, 'icon-512.png'), 512);
const fgHtml = path.join(OUT_TMP, 'feature.html');
fs.writeFileSync(fgHtml, featureGraphic());
shot(fgHtml, path.join(store, 'feature-graphic-1024x500.png'), 1024, 500);

console.log('brand assets written');
