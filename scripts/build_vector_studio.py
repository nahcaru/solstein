import json

with open("docs/assets/logo.svg", "r", encoding="utf-8") as f:
    master_svg_content = f.read()

html = f'''<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Solstein — Layered Vector Studio &amp; SVG Inspector</title>
  <link rel="icon" type="image/x-icon" href="assets/favicon.ico">
  <link rel="icon" type="image/png" sizes="32x32" href="assets/favicon-32x32.png">
  <link rel="icon" type="image/png" sizes="16x16" href="assets/favicon-16x16.png">
  <link rel="apple-touch-icon" sizes="180x180" href="assets/apple-touch-icon.png">
  <link rel="icon" type="image/png" href="assets/icon.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    :root {{
      --bg: #070A12;
      --panel-bg: rgba(14, 20, 33, 0.85);
      --border: rgba(255, 255, 255, 0.08);
      --amber: #F59E0B;
      --amber-glow: rgba(245, 158, 11, 0.28);
      --cyan: #38BDF8;
      --cyan-glow: rgba(56, 189, 248, 0.22);
      --text: #F8FAFC;
      --text-muted: #94A3B8;
      --text-dim: #64748B;
    }}

    * {{
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }}

    body {{
      background-color: var(--bg);
      color: var(--text);
      font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      background-image: 
        radial-gradient(ellipse at 15% 0%, rgba(245, 158, 11, 0.12) 0%, transparent 60%),
        radial-gradient(ellipse at 85% 10%, rgba(56, 189, 248, 0.1) 0%, transparent 50%),
        radial-gradient(circle at 50% 100%, rgba(15, 23, 42, 0.95) 0%, transparent 80%);
    }}

    header {{
      padding: 24px 32px;
      border-bottom: 1px solid var(--border);
      display: flex;
      justify-content: space-between;
      align-items: center;
      background: rgba(7, 10, 18, 0.8);
      backdrop-filter: blur(16px);
      position: sticky;
      top: 0;
      z-index: 100;
    }}

    .header-left {{
      display: flex;
      align-items: center;
      gap: 16px;
    }}

    .nav-back {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      color: var(--text-muted);
      text-decoration: none;
      font-size: 13px;
      font-weight: 600;
      padding: 6px 12px;
      border-radius: 8px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--border);
      transition: all 0.2s;
    }}

    .nav-back:hover {{
      color: #FFFFFF;
      background: rgba(255, 255, 255, 0.08);
    }}

    .header-title-box h1 {{
      font-size: 18px;
      font-weight: 800;
      letter-spacing: -0.3px;
    }}

    .header-title-box p {{
      font-size: 12px;
      color: var(--text-muted);
    }}

    .header-badges {{
      display: flex;
      gap: 8px;
    }}

    .badge {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 5px 12px;
      border-radius: 6px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      font-weight: 700;
      border: 1px solid var(--border);
      background: rgba(255, 255, 255, 0.04);
    }}

    .badge.official {{
      background: linear-gradient(135deg, #F59E0B, #D97706);
      color: #000;
      border: none;
    }}

    .studio-container {{
      max-width: 1440px;
      width: 100%;
      margin: 0 auto;
      padding: 32px;
      display: grid;
      grid-template-columns: 1fr 480px;
      gap: 32px;
      flex: 1;
    }}

    @media (max-width: 1080px) {{
      .studio-container {{
        grid-template-columns: 1fr;
      }}
    }}

    /* Left Column: Canvas Preview */
    .preview-panel {{
      display: flex;
      flex-direction: column;
      gap: 20px;
    }}

    .canvas-card {{
      background: var(--panel-bg);
      border: 1px solid var(--border);
      border-radius: 24px;
      padding: 32px;
      display: flex;
      flex-direction: column;
      align-items: center;
      position: relative;
      box-shadow: 0 24px 64px rgba(0, 0, 0, 0.6);
      backdrop-filter: blur(16px);
    }}

    .canvas-toolbar {{
      width: 100%;
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 24px;
      padding-bottom: 16px;
      border-bottom: 1px solid var(--border);
    }}

    .canvas-modes {{
      display: flex;
      gap: 6px;
      background: rgba(0, 0, 0, 0.3);
      padding: 4px;
      border-radius: 10px;
      border: 1px solid var(--border);
    }}

    .mode-btn {{
      background: none;
      border: none;
      color: var(--text-muted);
      font-size: 12px;
      font-weight: 600;
      padding: 6px 12px;
      border-radius: 6px;
      cursor: pointer;
      transition: all 0.2s;
    }}

    .mode-btn:hover {{
      color: #FFFFFF;
    }}

    .mode-btn.active {{
      background: rgba(255, 255, 255, 0.12);
      color: #FFFFFF;
      box-shadow: 0 2px 8px rgba(0,0,0,0.4);
    }}

    .svg-viewport-wrapper {{
      width: 100%;
      max-width: 540px;
      aspect-ratio: 1 / 1;
      border-radius: 28px;
      overflow: hidden;
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.8);
      position: relative;
      background-image: 
        linear-gradient(45deg, #121824 25%, transparent 25%), 
        linear-gradient(-45deg, #121824 25%, transparent 25%), 
        linear-gradient(45deg, transparent 75%, #121824 75%), 
        linear-gradient(-45deg, transparent 75%, #121824 75%);
      background-size: 24px 24px;
      background-position: 0 0, 0 12px, 12px -12px, -12px 0px;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: all 0.3s ease;
    }}

    .svg-viewport-wrapper.mask-circle {{
      border-radius: 50%;
    }}

    .svg-viewport-wrapper.mask-squircle {{
      border-radius: 28%;
    }}

    .svg-viewport-wrapper.mask-teardrop {{
      border-radius: 50% 50% 50% 0%;
    }}

    #svgHost {{
      width: 100%;
      height: 100%;
    }}

    #svgHost svg {{
      width: 100%;
      height: 100%;
      display: block;
    }}

    .canvas-actions {{
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 24px;
      width: 100%;
      justify-content: center;
    }}

    .btn {{
      padding: 10px 18px;
      border-radius: 10px;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      text-decoration: none;
      transition: all 0.2s;
    }}

    .btn-primary {{
      background: linear-gradient(135deg, #F59E0B, #D97706);
      color: #000000;
      border: none;
    }}

    .btn-primary:hover {{
      box-shadow: 0 0 20px var(--amber-glow);
      transform: translateY(-1px);
    }}

    .btn-secondary {{
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid var(--border);
      color: var(--text);
    }}

    .btn-secondary:hover {{
      background: rgba(255, 255, 255, 0.1);
      border-color: rgba(255, 255, 255, 0.2);
    }}

    /* Right Column: Layer Inspector */
    .inspector-panel {{
      display: flex;
      flex-direction: column;
      gap: 20px;
    }}

    .panel-card {{
      background: var(--panel-bg);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 24px;
      backdrop-filter: blur(16px);
      box-shadow: 0 16px 40px rgba(0, 0, 0, 0.5);
    }}

    .panel-header {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 16px;
      padding-bottom: 12px;
      border-bottom: 1px solid var(--border);
    }}

    .panel-title {{
      font-size: 15px;
      font-weight: 700;
      display: flex;
      align-items: center;
      gap: 8px;
    }}

    .layer-controls-bar {{
      display: flex;
      gap: 8px;
    }}

    .action-chip {{
      font-size: 11px;
      padding: 4px 10px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--border);
      color: var(--text-muted);
      cursor: pointer;
      transition: all 0.2s;
    }}

    .action-chip:hover {{
      background: rgba(255, 255, 255, 0.08);
      color: #FFFFFF;
    }}

    .layer-list {{
      display: flex;
      flex-direction: column;
      gap: 8px;
    }}

    .layer-item {{
      background: rgba(255, 255, 255, 0.02);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 12px 14px;
      display: flex;
      flex-direction: column;
      gap: 10px;
      transition: all 0.2s ease;
    }}

    .layer-item:hover {{
      background: rgba(255, 255, 255, 0.04);
      border-color: rgba(255, 255, 255, 0.15);
    }}

    .layer-item.active {{
      border-color: rgba(245, 158, 11, 0.35);
      background: rgba(245, 158, 11, 0.03);
    }}

    .layer-item.muted {{
      opacity: 0.45;
    }}

    .layer-row {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }}

    .layer-meta {{
      display: flex;
      align-items: center;
      gap: 10px;
      flex: 1;
    }}

    .layer-toggle {{
      cursor: pointer;
      width: 20px;
      height: 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 14px;
      user-select: none;
    }}

    .layer-name-box {{
      display: flex;
      flex-direction: column;
    }}

    .layer-name {{
      font-size: 13px;
      font-weight: 700;
      color: #FFFFFF;
    }}

    .layer-id {{
      font-family: 'JetBrains Mono', monospace;
      font-size: 10px;
      color: var(--text-dim);
    }}

    .layer-actions {{
      display: flex;
      align-items: center;
      gap: 6px;
    }}

    .btn-solo {{
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid var(--border);
      color: var(--text-dim);
      font-family: 'JetBrains Mono', monospace;
      font-size: 10px;
      font-weight: 700;
      padding: 3px 7px;
      border-radius: 4px;
      cursor: pointer;
      transition: all 0.2s;
    }}

    .btn-solo:hover {{
      color: var(--amber);
      border-color: var(--amber);
    }}

    .btn-solo.active {{
      background: var(--amber);
      color: #000;
      border-color: var(--amber);
    }}

    .btn-dl-layer {{
      background: none;
      border: none;
      color: var(--text-dim);
      cursor: pointer;
      font-size: 13px;
      padding: 2px 6px;
      transition: color 0.2s;
    }}

    .btn-dl-layer:hover {{
      color: #FFFFFF;
    }}

    .layer-slider-row {{
      display: flex;
      align-items: center;
      gap: 10px;
      padding-top: 4px;
      border-top: 1px solid rgba(255, 255, 255, 0.04);
    }}

    .slider-label {{
      font-size: 10px;
      font-family: 'JetBrains Mono', monospace;
      color: var(--text-dim);
      width: 45px;
    }}

    .layer-opacity-slider {{
      flex: 1;
      height: 4px;
      accent-color: var(--amber);
      cursor: pointer;
    }}

    .opacity-val {{
      font-size: 10px;
      font-family: 'JetBrains Mono', monospace;
      color: var(--text-muted);
      width: 30px;
      text-align: right;
    }}

    /* Specs & Design System Card */
    .specs-grid {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
      margin-top: 12px;
    }}

    .spec-item {{
      background: rgba(255, 255, 255, 0.02);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 10px 12px;
    }}

    .spec-key {{
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: 0.6px;
      color: var(--text-dim);
      font-family: 'JetBrains Mono', monospace;
      margin-bottom: 2px;
    }}

    .spec-val {{
      font-size: 12px;
      font-weight: 700;
      color: #FFFFFF;
      font-family: 'JetBrains Mono', monospace;
    }}

    .code-box {{
      background: rgba(0, 0, 0, 0.4);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 12px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      color: var(--text-muted);
      overflow-x: auto;
      white-space: pre;
      margin-top: 12px;
      max-height: 180px;
    }}
  </style>
</head>
<body>

  <header>
    <div class="header-left">
      <a href="logo-showcase.html" class="nav-back">← Back to Showcase</a>
      <div class="header-title-box">
        <h1>Solstein Layered Vector Studio</h1>
        <p>Master Multi-Layer Vector Architecture • Concept #02</p>
      </div>
    </div>
    <div class="header-badges">
      <span class="badge official">🏆 Master SVG</span>
      <span class="badge">1024×1024</span>
      <span class="badge">Figma / Illustrator Ready</span>
    </div>
  </header>

  <div class="studio-container">
    
    <!-- LEFT: PREVIEW & VIEWPORT -->
    <div class="preview-panel">
      <div class="canvas-card">
        <div class="canvas-toolbar">
          <div class="canvas-modes">
            <button class="mode-btn active" data-mode="default">Standard</button>
            <button class="mode-btn" data-mode="circle">Adaptive Circle</button>
            <button class="mode-btn" data-mode="squircle">Squircle Mask</button>
            <button class="mode-btn" data-mode="teardrop">Teardrop Mask</button>
          </div>
          <div style="font-family: 'JetBrains Mono', monospace; font-size: 12px; color: var(--text-dim);">
            Scale: 100% (1024px)
          </div>
        </div>

        <div class="svg-viewport-wrapper" id="viewportWrapper">
          <div id="svgHost">
            {master_svg_content}
          </div>
        </div>

        <div class="canvas-actions">
          <a href="./assets/logo.svg" download="solstein-logo-master.svg" class="btn btn-primary">
            ⬇️ Download Master Layered SVG
          </a>
          <button class="btn btn-secondary" onclick="copySvgCode()">
            📋 Copy SVG Code
          </button>
          <a href="./assets/adaptive/icon-foreground.svg" download="solstein-adaptive-foreground.svg" class="btn btn-secondary">
            📱 Adaptive FG
          </a>
          <a href="./assets/adaptive/icon-background.svg" download="solstein-adaptive-background.svg" class="btn btn-secondary">
            📱 Adaptive BG
          </a>
        </div>
      </div>

      <!-- SPECS & EXPORT NOTES -->
      <div class="panel-card">
        <div class="panel-header">
          <div class="panel-title">📐 Vector Architecture &amp; Runic Geometry</div>
          <span style="font-size: 11px; color: var(--amber); font-weight: 700;">Younger Futhark Sól (ᛋ)</span>
        </div>
        <p style="font-size: 13px; color: var(--text-muted); line-height: 1.6;">
          本ベクターデータは、Adobe Illustrator・Figma・Inkscapeでレイヤー構造が保持されるように <code>inkscape:groupmode="layer"</code> およびセマンティックIDでグループ化されています。
          左輪郭（Tip → Left Barb → Notch → Stem）は文字としての破綻なく純粋なYounger Futharkの3画ジグザグ『ᛋ』を形成しています。
        </p>

        <div class="specs-grid">
          <div class="spec-item">
            <div class="spec-key">Left Sól Contour (ᛋ)</div>
            <div class="spec-val">#38BDF8 (Nordic Cyan)</div>
          </div>
          <div class="spec-item">
            <div class="spec-key">Right Mirrored Edge</div>
            <div class="spec-val">#F59E0B (Solar Amber)</div>
          </div>
          <div class="spec-item">
            <div class="spec-key">Apex &amp; Stem Neon</div>
            <div class="spec-val">Pure White Tip &amp; Seamless Chromatic Bevel</div>
          </div>
          <div class="spec-item">
            <div class="spec-key">White Core Rail</div>
            <div class="spec-val">#FFFFFF (12.0px, ~3× Clean Grid)</div>
          </div>
          <div class="spec-item">
            <div class="spec-key">Ghost Pointer Offset</div>
            <div class="spec-val" id="specGhostOffset">dx: -25.0px, dy: +43.3px (120.0°)</div>
          </div>
          <div class="spec-item">
            <div class="spec-key">Primary Facets</div>
            <div class="spec-val">3D Calcite Cleavage (120°)</div>
          </div>
        </div>

        <div class="code-box" id="codeBox">&lt;!-- 12.0px Unified White-Hot Core Rail --&gt;
&lt;path d="M 369 289 L 440.5 708.5 L 510.7 564.0 L 598.1 693.0 Q 604.8 703.0 614.8 696.2 L 656.2 668.2 Q 666.1 661.5 659.4 651.5 L 572.2 522.8 L 731.0 511.5 Z" 
      fill="none" stroke="#FFFFFF" stroke-width="12.0" stroke-linejoin="round" stroke-linecap="round" /&gt;</div>
      </div>
    </div>

    <!-- RIGHT: LAYER TREE & INSPECTOR -->
    <div class="inspector-panel">

      <!-- LAYER TREE & INSPECTOR -->
      <div class="panel-card">
        <div class="panel-header">
          <div class="panel-title">🗂️ Layer Inspector (6 レイヤー)</div>
          <div class="layer-controls-bar">
            <button class="action-chip" onclick="resetAllLayers()">Show All</button>
            <button class="action-chip" onclick="hideAllLayers()">Hide All</button>
          </div>
        </div>

        <div class="layer-list" id="layerList">
          <!-- Dynamically populated / interactive layers -->
        </div>
      </div>

      <!-- LAYER EXPORTS CARD -->
      <div class="panel-card">
        <div class="panel-header">
          <div class="panel-title">📦 個別レイヤーSVG書き出し</div>
        </div>
        <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 12px;">
          プロジェクトやデザインツールですぐに使える独立したレイヤーSVGファイル群：
        </p>
        <div style="display: flex; flex-direction: column; gap: 6px;">
          <a href="./assets/vector-layers/01_background_squircle.svg" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px;">
            ⬇️ 01_background_squircle.svg
          </a>
          <a href="./assets/vector-layers/02_ambient_glow.svg" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px;">
            ⬇️ 02_ambient_glow.svg (強力光学散乱光・ブルーム)
          </a>
          <a href="./assets/vector-layers/03_ghost_pointer.svg" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px;">
            ⬇️ 03_ghost_pointer.svg (複屈折ゴースト影)
          </a>
          <a href="./assets/vector-layers/04_refraction_caustics.svg" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px;">
            ⬇️ 04_refraction_caustics.svg (虹色プリズム分光・屈折コースティクス)
          </a>
          <a href="./assets/vector-layers/05_primary_cursor.svg" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px;">
            ⬇️ 05_primary_cursor.svg (結晶ファセット)
          </a>
          <a href="./assets/vector-layers/06_rune_contours.svg" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px;">
            ⬇️ 06_rune_contours.svg (統合ネオン輪郭 &amp; 12px白レール)
          </a>
          <a href="./assets/vector-layers/06_rune_contour_cyan.svg" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px;">
            ⬇️ 06_rune_contour_cyan.svg (Sól ᛋ ルーン)
          </a>
          <a href="./assets/vector-layers/07_rune_contour_amber.svg" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px;">
            ⬇️ 07_rune_contour_amber.svg (アンバー反転)
          </a>
        </div>

        <div style="margin-top: 18px; padding-top: 14px; border-top: 1px solid var(--border);">
          <div class="panel-title" style="margin-bottom: 8px;">📱 アプリアイコン・本番アセット</div>
          <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 10px;">
            iOS / Android / Web 向けフルブリード本番アセット：
          </p>
          <div style="display: flex; flex-direction: column; gap: 6px;">
            <a href="./assets/icon-fullbleed.svg" download class="btn-primary btn" style="font-size: 12px; padding: 6px 12px; text-decoration: none;">
              ⬇️ icon-fullbleed.svg (フルブリード原版)
            </a>
            <a href="./assets/icon.png" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px; text-decoration: none;">
              ⬇️ icon.png (1024×1024 マスターPNG)
            </a>
            <a href="./assets/adaptive/icon-foreground.svg" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px; text-decoration: none;">
              ⬇️ Android 前景 (icon-foreground.svg)
            </a>
            <a href="./assets/adaptive/icon-background.svg" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px; text-decoration: none;">
              ⬇️ Android 背景 (icon-background.svg)
            </a>
            <a href="./assets/favicon.ico" download class="btn-secondary btn" style="font-size: 12px; padding: 6px 12px; text-decoration: none;">
              ⬇️ favicon.ico (16/32/48px マルチ)
            </a>
          </div>
        </div>
      </div>
    </div>

  </div>

  <script>
    const layerDefs = [
      {{ id: 'layer-01-background', name: '01. Background Squircle', desc: '黒曜石キャンバス & 外枠タイル', file: './assets/vector-layers/01_background_squircle.svg' }},
      {{ id: 'layer-02-ambient-glow', name: '02. Ambient Optical Halos', desc: '強化されたシアン & アンバーの光学散乱光 (76px / σ=38)', file: './assets/vector-layers/02_ambient_glow.svg' }},
      {{ id: 'layer-03-ghost-pointer', name: '03. Birefringent Ghost Pointer', desc: '方解石の複屈折（二重像）ツイン影', file: './assets/vector-layers/03_ghost_pointer.svg' }},
      {{ id: 'layer-04-refraction-caustics', name: '04. Refraction Caustics', desc: '主結晶越しに透けるゴースト輪郭の虹色プリズム分光（モヤ・色収差）', file: './assets/vector-layers/04_refraction_caustics.svg' }},
      {{ id: 'layer-05-primary-cursor', name: '05. Primary Crystal Facets', desc: '3D方解石カーソル本体 & 虹色分散', file: './assets/vector-layers/05_primary_cursor.svg' }},
      {{ id: 'layer-06-rune-contours', name: '06. Runic Contours (ᛋ)', desc: 'Sól (ᛋ) ルーン & 白先端・柄下シームレスグラデーション & 12px白レール', file: './assets/vector-layers/06_rune_contours.svg' }},
    ];

    const layerListEl = document.getElementById('layerList');
    const svgRoot = document.querySelector('#svgHost svg');

    let layerStates = {{}};
    layerDefs.forEach(l => {{
      layerStates[l.id] = {{ visible: true, opacity: 1, solo: false }};
    }});

    function renderLayerList() {{
      layerListEl.innerHTML = '';
      layerDefs.forEach(l => {{
        const state = layerStates[l.id];
        const item = document.createElement('div');
        item.className = `layer-item ${{state.visible ? 'active' : 'muted'}}`;
        item.id = `item-${{l.id}}`;

        item.innerHTML = `
          <div class="layer-row">
            <div class="layer-meta">
              <span class="layer-toggle" onclick="toggleLayer('${{l.id}}')">
                ${{state.visible ? '👁️' : '👁️‍🗨️'}}
              </span>
              <div class="layer-name-box">
                <span class="layer-name">${{l.name}}</span>
                <span class="layer-id">${{l.desc}}</span>
              </div>
            </div>
            <div class="layer-actions">
              <button class="btn-solo ${{state.solo ? 'active' : ''}}" onclick="soloLayer('${{l.id}}')">SOLO</button>
              <a href="${{l.file}}" download class="btn-dl-layer" title="Download Layer SVG">⬇️</a>
            </div>
          </div>
          <div class="layer-slider-row">
            <span class="slider-label">Opacity</span>
            <input type="range" class="layer-opacity-slider" min="0" max="100" value="${{Math.round(state.opacity * 100)}}" 
                   oninput="setLayerOpacity('${{l.id}}', this.value)">
            <span class="opacity-val" id="val-${{l.id}}">${{Math.round(state.opacity * 100)}}%</span>
          </div>
        `;
        layerListEl.appendChild(item);
      }});
    }}

    function applyLayerStyles() {{
      layerDefs.forEach(l => {{
        const el = svgRoot.querySelector(`#${{l.id}}`);
        if (el) {{
          const state = layerStates[l.id];
          el.style.display = state.visible ? '' : 'none';
          el.style.opacity = state.opacity;
        }}
      }});
    }}

    function toggleLayer(id) {{
      layerStates[id].visible = !layerStates[id].visible;
      applyLayerStyles();
      renderLayerList();
    }}

    function soloLayer(id) {{
      const currentSolo = layerStates[id].solo;
      if (currentSolo) {{
        // Un-solo: restore all
        layerDefs.forEach(l => {{
          layerStates[l.id].visible = true;
          layerStates[l.id].solo = false;
        }});
      }} else {{
        // Solo this layer
        layerDefs.forEach(l => {{
          layerStates[l.id].visible = (l.id === id);
          layerStates[l.id].solo = (l.id === id);
        }});
      }}
      applyLayerStyles();
      renderLayerList();
    }}

    function setLayerOpacity(id, val) {{
      const op = parseInt(val, 10) / 100;
      layerStates[id].opacity = op;
      const el = svgRoot.querySelector(`#${{id}}`);
      if (el) el.style.opacity = op;
      const valEl = document.getElementById(`val-${{id}}`);
      if (valEl) valEl.textContent = `${{val}}%`;
    }}

    function resetAllLayers() {{
      layerDefs.forEach(l => {{
        layerStates[l.id].visible = true;
        layerStates[l.id].solo = false;
      }});
      applyLayerStyles();
      renderLayerList();
    }}

    function hideAllLayers() {{
      layerDefs.forEach(l => {{
        layerStates[l.id].visible = false;
        layerStates[l.id].solo = false;
      }});
      applyLayerStyles();
      renderLayerList();
    }}

    // Mask mode switcher
    const modeBtns = document.querySelectorAll('.mode-btn');
    const viewportWrapper = document.getElementById('viewportWrapper');

    modeBtns.forEach(btn => {{
      btn.addEventListener('click', () => {{
        modeBtns.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        const mode = btn.getAttribute('data-mode');

        viewportWrapper.classList.remove('mask-circle', 'mask-squircle', 'mask-teardrop');
        if (mode === 'circle') viewportWrapper.classList.add('mask-circle');
        else if (mode === 'squircle') viewportWrapper.classList.add('mask-squircle');
        else if (mode === 'teardrop') viewportWrapper.classList.add('mask-teardrop');
      }});
    }});

    function copySvgCode() {{
      const svgText = document.getElementById('svgHost').innerHTML;
      navigator.clipboard.writeText(svgText);
      alert('✅ Master SVGコードをクリップボードにコピーしました！');
    }}

    // Initial render
    renderLayerList();
    applyLayerStyles();
  </script>
</body>
</html>
'''

with open("docs/vector-studio.html", "w", encoding="utf-8") as f:
    f.write(html)
print("Generated docs/vector-studio.html (Layer Studio & Inspector)")
