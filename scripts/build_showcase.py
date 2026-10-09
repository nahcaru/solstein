import json
import os
import sys

sys.path.append(os.path.dirname(__file__))
import build_showcase_data as data

# Update Concept #02 in base_concepts to reflect its official status
for c in data.base_concepts:
    if c['id'] == 2:
        c['is_official'] = True
        c['name'] = "The Double-Refraction Cursor (Official Brandmark)"
        c['subtitle'] = "The Birefringent Pointer & Inherent ᛋ Rune"
        c['series'] = "Series 1: Sunstone & Touch (Selected Official)"
        c['file'] = "./assets/logo.jpg"
        c['archetype'] = "Software Metaphor & Optical Physics"
        c['desc'] = "【公式採用ブランドマーク】33案の探索を経て確定。標準カーソル矢印の左輪郭線にYounger FutharkのSól（ᛋ）ルーンの3画ジグザグが完全に宿り、アイスランド方解石（太陽石）の複屈折によるツインゴースト影を従えた至高のアイデンティティ。16〜32pxの極小OSドックでも抜群の視認性を誇る。"
        c['metaphor'] = "The double image of Iceland spar merging into single focus once aligned with true north / true sun. The cursor contour inherently forms the Sól rune."

all_concepts = data.refined_concepts + data.base_concepts

html = f'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Solstein — Official Brand Identity & 33 AI Concept Archive</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    :root {{
      --bg: #070A12;
      --card-bg: rgba(14, 20, 33, 0.75);
      --card-border: rgba(255, 255, 255, 0.08);
      --card-hover-border: rgba(245, 158, 11, 0.45);
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
      padding-bottom: 80px;
      line-height: 1.5;
      background-image: 
        radial-gradient(ellipse at 15% 0%, rgba(245, 158, 11, 0.12) 0%, transparent 60%),
        radial-gradient(ellipse at 85% 10%, rgba(56, 189, 248, 0.1) 0%, transparent 50%),
        radial-gradient(circle at 50% 100%, rgba(15, 23, 42, 0.95) 0%, transparent 80%);
    }}

    header {{
      max-width: 1400px;
      margin: 0 auto;
      padding: 56px 32px 28px;
      border-bottom: 1px solid var(--card-border);
    }}

    .brand-eyebrow {{
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 14px;
      border-radius: 999px;
      background: rgba(245, 158, 11, 0.1);
      border: 1px solid rgba(245, 158, 11, 0.25);
      color: var(--amber);
      font-size: 13px;
      font-weight: 600;
      letter-spacing: 0.5px;
      text-transform: uppercase;
      margin-bottom: 16px;
    }}

    .brand-eyebrow .rune {{
      font-size: 18px;
      font-weight: 700;
    }}

    h1 {{
      font-size: clamp(32px, 5vw, 52px);
      font-weight: 800;
      letter-spacing: -1px;
      background: linear-gradient(135deg, #FFFFFF 0%, #E2E8F0 50%, #94A3B8 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 12px;
    }}

    .tagline {{
      font-size: clamp(15px, 2vw, 19px);
      color: var(--text-muted);
      max-width: 880px;
      margin-bottom: 24px;
    }}

    .meta-pills {{
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 16px;
    }}

    .meta-pill {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 6px 14px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      font-size: 13px;
      color: var(--text-muted);
      font-family: 'JetBrains Mono', monospace;
    }}

    .meta-pill strong {{
      color: #FFFFFF;
    }}

    .meta-pill.highlight {{
      border-color: rgba(245, 158, 11, 0.4);
      background: rgba(245, 158, 11, 0.1);
      color: var(--amber);
    }}

    .meta-pill.cyan-highlight {{
      border-color: rgba(56, 189, 248, 0.4);
      background: rgba(56, 189, 248, 0.08);
      color: var(--cyan);
    }}

    /* Official Brand Spotlight Section */
    .official-spotlight {{
      max-width: 1400px;
      margin: 36px auto 0;
      padding: 0 32px;
    }}

    .spotlight-card {{
      background: linear-gradient(145deg, rgba(16, 24, 40, 0.95) 0%, rgba(10, 15, 28, 0.95) 100%);
      border: 1px solid rgba(245, 158, 11, 0.35);
      border-radius: 28px;
      padding: 40px;
      box-shadow: 0 24px 64px rgba(0, 0, 0, 0.8), 0 0 48px rgba(245, 158, 11, 0.12);
      display: grid;
      grid-template-columns: 360px 1fr;
      gap: 40px;
      align-items: center;
      position: relative;
      overflow: hidden;
    }}

    .spotlight-card::before {{
      content: '';
      position: absolute;
      top: -120px;
      right: -120px;
      width: 320px;
      height: 320px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(56, 189, 248, 0.15) 0%, transparent 70%);
      pointer-events: none;
    }}

    .spotlight-card::after {{
      content: '';
      position: absolute;
      bottom: -120px;
      left: -120px;
      width: 320px;
      height: 320px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(245, 158, 11, 0.15) 0%, transparent 70%);
      pointer-events: none;
    }}

    @media (max-width: 980px) {{
      .spotlight-card {{
        grid-template-columns: 1fr;
        padding: 28px;
        gap: 32px;
      }}
    }}

    .spotlight-media {{
      display: flex;
      flex-direction: column;
      gap: 16px;
      position: relative;
      z-index: 2;
    }}

    .spotlight-img-frame {{
      position: relative;
      width: 100%;
      aspect-ratio: 1 / 1;
      border-radius: 24px;
      overflow: hidden;
      background: #05080E;
      border: 1px solid rgba(255, 255, 255, 0.12);
      box-shadow: 0 16px 40px rgba(0, 0, 0, 0.7);
    }}

    .spotlight-img-frame img {{
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
      transition: transform 0.5s ease;
    }}

    .spotlight-img-frame:hover img {{
      transform: scale(1.02);
    }}

    .spotlight-floating-badge {{
      position: absolute;
      top: 14px;
      left: 14px;
      background: linear-gradient(135deg, #F59E0B, #D97706);
      color: #000000;
      font-size: 11px;
      font-weight: 800;
      text-transform: uppercase;
      padding: 5px 12px;
      border-radius: 999px;
      letter-spacing: 0.8px;
      box-shadow: 0 4px 14px rgba(245, 158, 11, 0.4);
    }}

    .spotlight-file-bar {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 12px;
      padding: 8px 14px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 12px;
      color: var(--text-dim);
    }}

    .spotlight-file-bar code {{
      color: var(--text-muted);
    }}

    .spotlight-body {{
      display: flex;
      flex-direction: column;
      position: relative;
      z-index: 2;
    }}

    .spotlight-status-pill {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 12px;
      font-weight: 700;
      color: var(--amber);
      text-transform: uppercase;
      letter-spacing: 0.8px;
      margin-bottom: 8px;
    }}

    .spotlight-title {{
      font-size: clamp(24px, 3.2vw, 36px);
      font-weight: 800;
      color: #FFFFFF;
      letter-spacing: -0.5px;
      margin-bottom: 4px;
    }}

    .spotlight-sub {{
      font-size: 16px;
      color: var(--cyan);
      font-weight: 600;
      margin-bottom: 16px;
    }}

    .spotlight-lead {{
      font-size: 14.5px;
      color: var(--text-muted);
      line-height: 1.65;
      margin-bottom: 24px;
    }}

    .spotlight-reasons {{
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 14px;
      margin-bottom: 24px;
    }}

    @media (max-width: 640px) {{
      .spotlight-reasons {{
        grid-template-columns: 1fr;
      }}
    }}

    .reason-box {{
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.06);
      border-radius: 14px;
      padding: 14px 16px;
      transition: all 0.2s ease;
    }}

    .reason-box:hover {{
      background: rgba(255, 255, 255, 0.05);
      border-color: rgba(245, 158, 11, 0.3);
    }}

    .reason-head {{
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 13.5px;
      font-weight: 700;
      color: #FFFFFF;
      margin-bottom: 6px;
    }}

    .reason-head span.icon {{
      font-size: 16px;
    }}

    .reason-text {{
      font-size: 12.5px;
      color: var(--text-muted);
      line-height: 1.5;
    }}

    .spotlight-footer-bar {{
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
      padding-top: 20px;
      border-top: 1px solid rgba(255, 255, 255, 0.08);
    }}

    .spotlight-palette {{
      display: flex;
      align-items: center;
      gap: 14px;
      flex-wrap: wrap;
    }}

    .palette-item {{
      display: flex;
      align-items: center;
      gap: 8px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      color: var(--text-dim);
    }}

    .palette-circle {{
      width: 22px;
      height: 22px;
      border-radius: 50%;
      border: 1px solid rgba(255, 255, 255, 0.2);
    }}

    .spotlight-actions {{
      display: flex;
      gap: 10px;
      align-items: center;
    }}

    .btn-secondary {{
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid var(--card-border);
      color: var(--text);
      font-size: 13px;
      font-weight: 600;
      padding: 8px 16px;
      border-radius: 10px;
      cursor: pointer;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.2s;
    }}

    .btn-secondary:hover {{
      background: rgba(255, 255, 255, 0.1);
      border-color: rgba(255, 255, 255, 0.2);
    }}

    .btn-primary {{
      background: linear-gradient(135deg, rgba(245, 158, 11, 0.2), rgba(56, 189, 248, 0.2));
      border: 1px solid var(--amber);
      color: #FFFFFF;
      font-size: 13px;
      font-weight: 600;
      padding: 8px 16px;
      border-radius: 10px;
      cursor: pointer;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.2s;
    }}

    .btn-primary:hover {{
      background: linear-gradient(135deg, rgba(245, 158, 11, 0.35), rgba(56, 189, 248, 0.35));
      box-shadow: 0 0 16px var(--amber-glow);
    }}

    /* Controls Bar */
    .controls {{
      max-width: 1400px;
      margin: 40px auto 0;
      padding: 0 32px;
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
    }}

    .filter-tabs {{
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }}

    .filter-btn {{
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid var(--card-border);
      color: var(--text-muted);
      padding: 8px 16px;
      border-radius: 10px;
      font-size: 14px;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s ease;
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }}

    .filter-btn:hover {{
      background: rgba(255, 255, 255, 0.08);
      color: var(--text);
    }}

    .filter-btn.active {{
      background: var(--amber);
      color: #000000;
      font-weight: 700;
      border-color: var(--amber);
      box-shadow: 0 0 20px var(--amber-glow);
    }}

    .filter-btn.filter-official.active {{
      background: linear-gradient(135deg, #F59E0B, #38BDF8);
      color: #000000;
    }}

    .search-box {{
      position: relative;
      min-width: 280px;
    }}

    .search-input {{
      width: 100%;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--card-border);
      border-radius: 10px;
      padding: 9px 14px 9px 36px;
      color: var(--text);
      font-size: 14px;
      outline: none;
      transition: all 0.2s;
    }}

    .search-input:focus {{
      border-color: var(--cyan);
      box-shadow: 0 0 16px var(--cyan-glow);
    }}

    .search-icon {{
      position: absolute;
      left: 12px;
      top: 50%;
      transform: translateY(-50%);
      color: var(--text-dim);
      font-size: 14px;
      pointer-events: none;
    }}

    /* Gallery Grid */
    .gallery {{
      max-width: 1400px;
      margin: 32px auto 0;
      padding: 0 32px;
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(310px, 1fr));
      gap: 28px;
    }}

    .card {{
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 20px;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      backdrop-filter: blur(16px);
      transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
      cursor: pointer;
      position: relative;
    }}

    .card.featured-card {{
      border-color: rgba(245, 158, 11, 0.35);
      background: rgba(20, 27, 45, 0.88);
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
    }}

    /* Official Card Special Styling */
    .card.official-card {{
      border: 2px solid rgba(245, 158, 11, 0.7);
      background: linear-gradient(180deg, rgba(22, 32, 54, 0.95) 0%, rgba(12, 18, 30, 0.95) 100%);
      box-shadow: 0 12px 32px rgba(0, 0, 0, 0.7), 0 0 24px rgba(245, 158, 11, 0.25);
    }}

    .card.official-card:hover {{
      border-color: var(--amber);
      box-shadow: 0 16px 40px rgba(0, 0, 0, 0.8), 0 0 36px var(--amber-glow);
    }}

    @keyframes officialPulse {{
      0% {{ transform: scale(1); box-shadow: 0 0 0 0 rgba(245, 158, 11, 0.7); }}
      50% {{ transform: scale(1.03); box-shadow: 0 0 36px 12px rgba(245, 158, 11, 0.5); }}
      100% {{ transform: scale(1); box-shadow: 0 12px 32px rgba(0, 0, 0, 0.7), 0 0 24px rgba(245, 158, 11, 0.25); }}
    }}

    .card.card-pulse {{
      animation: officialPulse 1.2s ease-in-out;
    }}

    .card:hover {{
      transform: translateY(-4px);
      border-color: var(--card-hover-border);
      box-shadow: 0 16px 36px rgba(0, 0, 0, 0.6), 0 0 24px var(--amber-glow);
    }}

    .card-media {{
      position: relative;
      width: 100%;
      padding-top: 100%;
      background: #080C14;
      overflow: hidden;
    }}

    .card-media img {{
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      object-fit: cover;
      transition: transform 0.4s ease;
    }}

    .card:hover .card-media img {{
      transform: scale(1.03);
    }}

    .badge-bar {{
      position: absolute;
      top: 12px;
      left: 12px;
      right: 12px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      z-index: 2;
    }}

    .id-badge {{
      background: rgba(11, 15, 23, 0.88);
      border: 1px solid rgba(255, 255, 255, 0.14);
      backdrop-filter: blur(8px);
      color: #FFFFFF;
      font-size: 13px;
      font-weight: 700;
      padding: 4px 10px;
      border-radius: 8px;
      font-family: 'JetBrains Mono', monospace;
    }}

    .id-badge.official-badge {{
      background: linear-gradient(135deg, #F59E0B, #D97706);
      color: #000000;
      font-weight: 800;
      border: none;
    }}

    .type-pill {{
      background: rgba(11, 15, 23, 0.88);
      border: 1px solid rgba(255, 255, 255, 0.14);
      backdrop-filter: blur(8px);
      color: var(--amber);
      font-size: 11px;
      font-weight: 700;
      padding: 4px 10px;
      border-radius: 6px;
      letter-spacing: 0.3px;
    }}

    .type-pill.official-pill {{
      background: rgba(56, 189, 248, 0.2);
      border-color: rgba(56, 189, 248, 0.5);
      color: var(--cyan);
    }}

    .card-body {{
      padding: 20px 22px 24px;
      display: flex;
      flex-direction: column;
      flex: 1;
    }}

    .card-series {{
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.6px;
      color: var(--amber);
      margin-bottom: 6px;
    }}

    .card-title {{
      font-size: 19px;
      font-weight: 700;
      color: #FFFFFF;
      margin-bottom: 2px;
    }}

    .card-subtitle {{
      font-size: 13px;
      color: var(--cyan);
      margin-bottom: 12px;
      font-weight: 500;
    }}

    .card-desc {{
      font-size: 13px;
      color: var(--text-muted);
      line-height: 1.55;
      margin-bottom: 16px;
      flex: 1;
    }}

    .card-footer {{
      border-top: 1px solid rgba(255, 255, 255, 0.06);
      padding-top: 14px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }}

    .swatches {{
      display: flex;
      gap: 6px;
    }}

    .swatch {{
      width: 18px;
      height: 18px;
      border-radius: 50%;
      border: 1px solid rgba(255, 255, 255, 0.2);
    }}

    .archetype-tag {{
      font-size: 11px;
      color: var(--text-dim);
      font-family: 'JetBrains Mono', monospace;
    }}

    /* Lightbox Modal */
    .modal-backdrop {{
      position: fixed;
      inset: 0;
      background: rgba(3, 7, 18, 0.92);
      backdrop-filter: blur(18px);
      z-index: 1000;
      display: none;
      align-items: center;
      justify-content: center;
      padding: 32px;
    }}

    .modal-backdrop.open {{
      display: flex;
    }}

    .modal-content {{
      background: #0C121E;
      border: 1px solid rgba(255, 255, 255, 0.14);
      border-radius: 24px;
      max-width: 980px;
      width: 100%;
      max-height: 90vh;
      overflow-y: auto;
      display: grid;
      grid-template-columns: 1fr 1fr;
      box-shadow: 0 32px 64px rgba(0, 0, 0, 0.85);
      position: relative;
    }}

    @media (max-width: 768px) {{
      .modal-content {{
        grid-template-columns: 1fr;
      }}
    }}

    .modal-media {{
      background: #05080E;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 28px;
      border-right: 1px solid rgba(255, 255, 255, 0.08);
    }}

    .modal-media img {{
      max-width: 100%;
      max-height: 480px;
      border-radius: 18px;
      box-shadow: 0 16px 36px rgba(0, 0, 0, 0.6);
    }}

    .modal-details {{
      padding: 36px 32px;
      display: flex;
      flex-direction: column;
    }}

    .close-btn {{
      position: absolute;
      top: 18px;
      right: 18px;
      background: rgba(255, 255, 255, 0.06);
      border: 1px solid rgba(255, 255, 255, 0.1);
      color: var(--text-muted);
      width: 36px;
      height: 36px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      font-size: 18px;
      transition: all 0.2s;
    }}

    .close-btn:hover {{
      background: rgba(255, 255, 255, 0.15);
      color: #FFFFFF;
    }}

    .modal-official-badge {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: linear-gradient(135deg, #F59E0B, #D97706);
      color: #000;
      font-size: 11px;
      font-weight: 800;
      padding: 4px 10px;
      border-radius: 6px;
      text-transform: uppercase;
      letter-spacing: 0.6px;
      margin-bottom: 8px;
      width: fit-content;
    }}

    .modal-id {{
      font-family: 'JetBrains Mono', monospace;
      color: var(--amber);
      font-size: 14px;
      font-weight: 700;
      margin-bottom: 4px;
    }}

    .modal-title {{
      font-size: 26px;
      font-weight: 800;
      color: #FFFFFF;
      margin-bottom: 4px;
    }}

    .modal-sub {{
      font-size: 15px;
      color: var(--cyan);
      margin-bottom: 20px;
    }}

    .modal-section-title {{
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.8px;
      color: var(--text-dim);
      font-weight: 700;
      margin-top: 18px;
      margin-bottom: 6px;
    }}

    .modal-text {{
      font-size: 14px;
      color: var(--text-muted);
      line-height: 1.6;
    }}

    .copy-pill {{
      margin-top: 24px;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--card-border);
      padding: 8px 14px;
      border-radius: 10px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 12px;
      color: var(--text-muted);
      cursor: pointer;
      transition: all 0.2s;
    }}

    .copy-pill:hover {{
      background: rgba(255, 255, 255, 0.08);
      color: #FFFFFF;
    }}
  </style>
</head>
<body>

  <header>
    <div class="brand-eyebrow">
      <span class="rune">ᛋ</span> Solstein Design Exploration &amp; Official Identity
    </div>
    <h1>Solstein Brand Identity &amp; 33 AI Concept Archive</h1>
    <p class="tagline">
      Turn your phone into a Bluetooth HID trackpad. Featuring <strong>Concept #02 (The Double-Refraction Cursor)</strong> as the selected official brand identity, alongside the complete archive of 33 explorations across Norse sunstone optics (<em>sólarsteinn</em>), birefringence physics, and the Younger Futhark Sól rune (<strong>ᛋ</strong>).
    </p>
    <div class="meta-pills">
      <div class="meta-pill highlight"><span>🏆 Selected Brandmark:</span> <strong>Concept #02 (Double-Refraction Cursor)</strong></div>
      <div class="meta-pill cyan-highlight"><span>Inherent Geometry:</span> <strong>Runic 'ᛋ' Contour + Birefringent Shadow</strong></div>
      <div class="meta-pill"><span>Total Archive:</span> <strong>All 33 concepts generated with Nano Banana Pro</strong></div>
      <div class="meta-pill"><span>Master Asset:</span> <strong>docs/assets/logo.jpg</strong></div>
    </div>
  </header>

  <!-- Official Selected Brand Identity Spotlight -->
  <section class="official-spotlight" id="officialSpotlight">
    <div class="spotlight-card">
      <div class="spotlight-media">
        <div class="spotlight-img-frame">
          <img src="./assets/logo.jpg" alt="Solstein Official Logo - Concept #02">
          <div class="spotlight-floating-badge">🏆 OFFICIAL BRAND IDENTITY</div>
        </div>
        <div class="spotlight-file-bar">
          <span>Master: <code>docs/assets/logo.jpg</code></span>
          <button class="btn-secondary" style="padding: 4px 10px; font-size: 11px;" onclick="copyOfficialPath(event)">📋 Copy</button>
        </div>
      </div>

      <div class="spotlight-body">
        <div class="spotlight-status-pill">
          <span>👑</span> Official Brandmark Selection
        </div>
        <h2 class="spotlight-title">Concept #02: The Double-Refraction Cursor</h2>
        <div class="spotlight-sub">The Birefringent Pointer &amp; The Inherent Younger Futhark Sól (ᛋ)</div>
        
        <p class="spotlight-lead">
          33案にわたる探索の末、Solsteinの公式ブランドアイデンティティとして決定。
          人為的にルーン文字を無理矢理ロゴに彫り込むのではなく、<strong>標準的なマウスカーソルの輪郭線そのものに Younger Futhark の Sól（ᛋ）が宿っている</strong>という幾何学的必然性と、アイスランド方解石（太陽石）の<strong>複屈折（二重像）によるツインゴースト影</strong>を融合させた、機能的かつ神秘的なマスターピース。
        </p>

        <div class="spotlight-reasons">
          <div class="reason-box">
            <div class="reason-head">
              <span class="icon">📐</span>
              <span>1. 圧倒的なスケーラビリティ（16〜32px）</span>
            </div>
            <p class="reason-text">
              複雑な石板彫刻と異なり、OSドック（macOS/Android/Windows）の極小サイズでも即座に「トラックパッド／カーソル操作」と認識可能な標準的シルエットを維持。
            </p>
          </div>

          <div class="reason-box">
            <div class="reason-head">
              <span class="icon">ᛋ</span>
              <span>2. 輪郭に宿る真の Sól（ᛋ）ルーン</span>
            </div>
            <p class="reason-text">
              カーソル左縁（先端→左翼バーブ→切れ込み→ステム）がYounger Futharkの3画ジグザグ『ᛋ』を美しくトレース（Nordic Cyanで発光）。右縁はSolar Amberで対称反転。
            </p>
          </div>

          <div class="reason-box">
            <div class="reason-head">
              <span class="icon">💎</span>
              <span>3. 太陽石の複屈折（Birefringence）物理</span>
            </div>
            <p class="reason-text">
              背後に浮かぶ半透明のツインゴースト影。バイキングが曇天で二重像の明暗を揃えて真北を測ったように、スマホとPCが見えない無線で見事に同期するメタファー。
            </p>
          </div>

          <div class="reason-box">
            <div class="reason-head">
              <span class="icon">🎨</span>
              <span>4. ノルディック・サイアン × ソーラー・アンバー</span>
            </div>
            <p class="reason-text">
              Bluetooth無線通信とホスト画面を示す冷たいサイアン（#38BDF8）と、導きの太陽を示す温かいアンバー（#F59E0B）の二重偏光が漆黒の黒曜石上で輝く。
            </p>
          </div>
        </div>

        <div class="spotlight-footer-bar">
          <div class="spotlight-palette">
            <div class="palette-item">
              <span class="palette-circle" style="background: #0B0F17; border-color: rgba(255,255,255,0.3);"></span>
              <span>Obsidian<br>#0B0F17</span>
            </div>
            <div class="palette-item">
              <span class="palette-circle" style="background: #F8FAFC;"></span>
              <span>Calcite<br>#F8FAFC</span>
            </div>
            <div class="palette-item">
              <span class="palette-circle" style="background: #F59E0B; box-shadow: 0 0 10px rgba(245,158,11,0.5);"></span>
              <span>Amber<br>#F59E0B</span>
            </div>
            <div class="palette-item">
              <span class="palette-circle" style="background: #38BDF8; box-shadow: 0 0 10px rgba(56,189,248,0.5);"></span>
              <span>Cyan<br>#38BDF8</span>
            </div>
          </div>

          <div class="spotlight-actions">
            <a href="vector-studio.html" class="btn-primary" style="background: linear-gradient(135deg, rgba(56, 189, 248, 0.25), rgba(245, 158, 11, 0.25)); border-color: var(--cyan);">📐 Vector Studio (レイヤー分解)</a>
            <a href="./assets/logo.svg" download="solstein-logo.svg" class="btn-secondary">⬇️ SVG (ベクター)</a>
            <button class="btn-secondary" onclick="copyOfficialPath(event)">📋 Copy Path</button>
            <a href="#card-2" class="btn-primary" onclick="jumpToConcept2(event)">🔍 ギャラリー内の#02を見る</a>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- Controls Bar -->
  <div class="controls">
    <div class="filter-tabs">
      <button class="filter-btn active" data-filter="all">All Concepts (33)</button>
      <button class="filter-btn filter-official" data-filter="official">🏆 Official Selected (#02)</button>
      <button class="filter-btn" data-filter="refined">Refined Hybrids (13)</button>
      <button class="filter-btn" data-filter="series1">Series 1: Sunstone &amp; Touch (1–10)</button>
      <button class="filter-btn" data-filter="series2">Series 2: Younger Futhark ᛋ (11–20)</button>
    </div>
    <div class="search-box">
      <span class="search-icon">🔍</span>
      <input type="text" id="searchInput" class="search-input" placeholder="Filter by keyword (e.g. cursor, reticle, slab)...">
    </div>
  </div>

  <main class="gallery" id="gallery">
'''

for c in all_concepts:
    swatches_html = "".join([f'<span class="swatch" style="background-color: {color};" title="{color}"></span>' for color in c["colors"]])
    is_official = (c['id'] == 2)
    is_ref = c["series_id"] == "refined"
    
    if is_official:
        badge_label = "🏆 #02 OFFICIAL"
        type_label = "Selected Mark"
        card_cls = "card official-card"
        card_id_attr = 'id="card-2"'
    elif is_ref:
        badge_label = f"Option {c.get('ref')}"
        type_label = "Nano Banana Pro"
        card_cls = "card featured-card"
        card_id_attr = f'id="card-{c["id"]}"'
    else:
        badge_label = f"#{c['id']:02d}"
        type_label = "Gemini Pro"
        card_cls = "card"
        card_id_attr = f'id="card-{c["id"]}"'
    
    badge_cls = "id-badge official-badge" if is_official else "id-badge"
    type_cls = "type-pill official-pill" if is_official else "type-pill"

    html += f'''
    <div class="{card_cls}" 
         {card_id_attr}
         data-id="{c['id']}" 
         data-series="{c['series_id']}" 
         data-title="{c['name'].lower()} {c['subtitle'].lower()} {c['archetype'].lower()} {c['desc'].lower()}">
      <div class="card-media">
        <div class="badge-bar">
          <span class="{badge_cls}">{badge_label}</span>
          <span class="{type_cls}">{type_label}</span>
        </div>
        <img src="{c['file']}" alt="{c['name']}" loading="lazy">
      </div>
      <div class="card-body">
        <div class="card-series">{c['series']}</div>
        <h3 class="card-title">{c['name']}</h3>
        <div class="card-subtitle">{c['subtitle']}</div>
        <p class="card-desc">{c['desc']}</p>
        <div class="card-footer">
          <div class="swatches">{swatches_html}</div>
          <span class="archetype-tag">{c['archetype']}</span>
        </div>
      </div>
    </div>
    '''

html += f'''
  </main>

  <div class="modal-backdrop" id="modalBackdrop">
    <div class="modal-content" id="modalContent">
      <button class="close-btn" id="closeBtn">&times;</button>
      <div class="modal-media">
        <img id="modalImg" src="" alt="">
      </div>
      <div class="modal-details">
        <div id="modalOfficialBadge"></div>
        <div class="modal-id" id="modalId">#01</div>
        <h2 class="modal-title" id="modalTitle">Title</h2>
        <div class="modal-sub" id="modalSub">Subtitle</div>
        
        <div class="modal-section-title">Design Concept</div>
        <p class="modal-text" id="modalDesc"></p>

        <div class="modal-section-title">Core Metaphor</div>
        <p class="modal-text" id="modalMetaphor"></p>

        <div class="modal-section-title">Archetype &amp; Model</div>
        <p class="modal-text" id="modalMeta"></p>

        <div class="copy-pill" id="copyPathBtn">
          📋 Click to copy asset path
        </div>
      </div>
    </div>
  </div>

  <script>
    const concepts = {json.dumps(all_concepts)};

    // Filter Buttons
    const filterBtns = document.querySelectorAll('.filter-btn');
    const cards = document.querySelectorAll('.card');
    const searchInput = document.getElementById('searchInput');

    let currentFilter = 'all';
    let searchQuery = '';

    function applyFilters() {{
      cards.forEach(card => {{
        const series = card.getAttribute('data-series');
        const id = card.getAttribute('data-id');
        const text = card.getAttribute('data-title');

        let matchesFilter = true;
        if (currentFilter === 'official') {{
          matchesFilter = (id === '2');
        }} else if (currentFilter === 'refined') {{
          matchesFilter = (series === 'refined');
        }} else if (currentFilter === 'series1') {{
          matchesFilter = (series === 'series1');
        }} else if (currentFilter === 'series2') {{
          matchesFilter = (series === 'series2');
        }}

        let matchesSearch = true;
        if (searchQuery) {{
          matchesSearch = text.includes(searchQuery);
        }}

        card.style.display = (matchesFilter && matchesSearch) ? 'flex' : 'none';
      }});
    }}

    filterBtns.forEach(btn => {{
      btn.addEventListener('click', () => {{
        filterBtns.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        currentFilter = btn.getAttribute('data-filter');
        applyFilters();
      }});
    }});

    searchInput.addEventListener('input', (e) => {{
      searchQuery = e.target.value.toLowerCase().trim();
      applyFilters();
    }});

    // Modal Lightbox
    const modalBackdrop = document.getElementById('modalBackdrop');
    const closeBtn = document.getElementById('closeBtn');
    const modalImg = document.getElementById('modalImg');
    const modalOfficialBadge = document.getElementById('modalOfficialBadge');
    const modalId = document.getElementById('modalId');
    const modalTitle = document.getElementById('modalTitle');
    const modalSub = document.getElementById('modalSub');
    const modalDesc = document.getElementById('modalDesc');
    const modalMetaphor = document.getElementById('modalMetaphor');
    const modalMeta = document.getElementById('modalMeta');
    const copyPathBtn = document.getElementById('copyPathBtn');

    let currentConcept = null;

    cards.forEach(card => {{
      card.addEventListener('click', () => {{
        const id = parseInt(card.getAttribute('data-id'), 10);
        const data = concepts.find(c => c.id === id);
        if (!data) return;
        currentConcept = data;

        modalImg.src = data.file;
        modalId.textContent = `#${{String(data.id).padStart(2, '0')}} • ${{data.series}}`;
        modalTitle.textContent = data.name;
        modalSub.textContent = data.subtitle;
        modalDesc.textContent = data.desc;
        modalMetaphor.textContent = data.metaphor;
        modalMeta.textContent = `${{data.archetype}} — Nano Banana Pro Render`;
        copyPathBtn.textContent = `📋 Copy: ${{data.file}}`;

        if (data.id === 2) {{
          modalOfficialBadge.innerHTML = '<span class="modal-official-badge">🏆 Official Selected Brandmark</span>';
        }} else {{
          modalOfficialBadge.innerHTML = '';
        }}

        modalBackdrop.classList.add('open');
      }});
    }});

    function closeModal() {{
      modalBackdrop.classList.remove('open');
    }}

    closeBtn.addEventListener('click', closeModal);
    modalBackdrop.addEventListener('click', (e) => {{
      if (e.target === modalBackdrop) closeModal();
    }});

    document.addEventListener('keydown', (e) => {{
      if (e.key === 'Escape') closeModal();
    }});

    copyPathBtn.addEventListener('click', () => {{
      if (currentConcept) {{
        navigator.clipboard.writeText(currentConcept.file);
        copyPathBtn.textContent = '✅ Copied to clipboard!';
        setTimeout(() => {{
          copyPathBtn.textContent = `📋 Copy: ${{currentConcept.file}}`;
        }}, 2000);
      }}
    }});

    // Helper functions for Official Spotlight
    function copyOfficialPath(e) {{
      if (e) e.stopPropagation();
      navigator.clipboard.writeText('docs/assets/logo.jpg');
      const target = e ? e.target : null;
      if (target) {{
        const oldText = target.textContent;
        target.textContent = '✅ Copied!';
        setTimeout(() => {{
          target.textContent = oldText;
        }}, 2000);
      }}
    }}

    function jumpToConcept2(e) {{
      if (e) e.preventDefault();
      // Reset filter to all
      filterBtns.forEach(b => {{
        if (b.getAttribute('data-filter') === 'all') b.classList.add('active');
        else b.classList.remove('active');
      }});
      currentFilter = 'all';
      searchQuery = '';
      searchInput.value = '';
      applyFilters();

      const card2 = document.getElementById('card-2');
      if (card2) {{
        card2.scrollIntoView({{ behavior: 'smooth', block: 'center' }});
        card2.classList.add('card-pulse');
        setTimeout(() => {{
          card2.classList.remove('card-pulse');
        }}, 1400);
      }}
    }}
  </script>
</body>
</html>
'''

output_path = "docs/logo-showcase.html"
with open(output_path, "w", encoding="utf-8") as f:
    f.write(html)
print(f"Successfully generated {output_path} ({len(html)} bytes)")
