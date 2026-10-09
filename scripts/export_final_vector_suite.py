import subprocess
import os
import re
import argparse
from optimize_svg import build_refined_svg

parser = argparse.ArgumentParser(description="Export Solstein Vector Suite with configurable ghost offset")
parser.add_argument("--dx", type=float, default=-25.0, help="Ghost translation dx (default: -25.0)")
parser.add_argument("--dy", type=float, default=43.3, help="Ghost translation dy (default: 43.3)")
args = parser.parse_args()

# Ensure target directories exist
os.makedirs("docs/assets/vector-layers", exist_ok=True)
os.makedirs("docs/assets/adaptive", exist_ok=True)

# 1. Generate and write docs/assets/logo.svg (Master Refined Layered SVG)
master_svg = build_refined_svg({"ghost_dx": args.dx, "ghost_dy": args.dy})
with open("docs/assets/logo.svg", "w", encoding="utf-8") as f:
    f.write(master_svg)
print(f"Updated docs/assets/logo.svg (Master Refined Layered SVG with dx={args.dx}, dy={args.dy})")

# Extract defs
defs_match = re.search(r"<defs>(.*?)</defs>", master_svg, re.DOTALL)
defs_content = defs_match.group(1) if defs_match else ""

# Extract layers by group ID
def extract_group(svg, group_id):
    m = re.search(rf'(  <g id="{group_id}"[\s\S]*?\n  </g>)', svg)
    if m:
        return m.group(1)
    return ""

layer_01 = extract_group(master_svg, "layer-01-background")
layer_02 = extract_group(master_svg, "layer-02-ambient-glow")
layer_03 = extract_group(master_svg, "layer-03-ghost-pointer")
layer_04 = extract_group(master_svg, "layer-04-refraction-caustics")
layer_05 = extract_group(master_svg, "layer-05-primary-cursor")
layer_06 = extract_group(master_svg, "layer-06-rune-contours")

# Extract sub-runes from layer 6
rune_cyan_match = re.search(r'<g id="rune-sol-cyan"[\s\S]*?</g>', layer_06)
rune_cyan = rune_cyan_match.group(0) if rune_cyan_match else ""

rune_amber_match = re.search(r'<g id="rune-mirror-amber"[\s\S]*?</g>', layer_06)
rune_amber = rune_amber_match.group(0) if rune_amber_match else ""

# 2. Individual Layers
layers = [
    {
        "filename": "docs/assets/vector-layers/01_background_squircle.svg",
        "title": "Layer 1: Background Canvas & Squircle Tile",
        "body": layer_01
    },
    {
        "filename": "docs/assets/vector-layers/02_ambient_glow.svg",
        "title": "Layer 2: Ambient Optical Bloom",
        "body": layer_02
    },
    {
        "filename": "docs/assets/vector-layers/03_ghost_pointer.svg",
        "title": "Layer 3: Birefringent Ghost Pointer",
        "body": layer_03
    },
    {
        "filename": "docs/assets/vector-layers/04_refraction_caustics.svg",
        "title": "Layer 4: Refraction Caustics & Ambient Shadow",
        "body": layer_04
    },
    {
        "filename": "docs/assets/vector-layers/05_primary_cursor.svg",
        "title": "Layer 5: Primary Translucent Crystal Facets",
        "body": layer_05
    },
    {
        "filename": "docs/assets/vector-layers/06_rune_contours.svg",
        "title": "Layer 6: Runic Neon Contours & Core Rail",
        "body": layer_06
    },
    {
        "filename": "docs/assets/vector-layers/06_rune_contour_cyan.svg",
        "title": "Layer 6A: Younger Futhark Sól (ᛋ) Cyan Contour",
        "body": f'''  <g id="layer-06a-rune-cyan">
    {rune_cyan}
  </g>'''
    },
    {
        "filename": "docs/assets/vector-layers/07_rune_contour_amber.svg",
        "title": "Layer 6B: Mirrored Solar Amber Contour",
        "body": f'''  <g id="layer-06b-rune-amber">
    {rune_amber}
  </g>'''
    }
]

for l in layers:
    isolated_svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" 
     xmlns:xlink="http://www.w3.org/1999/xlink"
     xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
     viewBox="0 0 1024 1024" 
     width="1024" 
     height="1024">
  <defs>
{defs_content}
  </defs>
{l['body']}
</svg>'''
    with open(l['filename'], "w", encoding="utf-8") as f:
        f.write(isolated_svg)
    print(f"Generated {l['filename']}")

# 3. Android Adaptive Icons
adaptive_bg = '''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" width="108" height="108">
  <defs>
    <radialGradient id="ad-bg" cx="40%" cy="35%" r="75%">
      <stop offset="0%" stop-color="#232C3C"/>
      <stop offset="45%" stop-color="#141924"/>
      <stop offset="100%" stop-color="#080C14"/>
    </radialGradient>
  </defs>
  <rect width="108" height="108" fill="url(#ad-bg)"/>
</svg>'''

with open("docs/assets/adaptive/icon-background.svg", "w", encoding="utf-8") as f:
    f.write(adaptive_bg)

adaptive_fg = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" 
     xmlns:xlink="http://www.w3.org/1999/xlink"
     xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
     viewBox="0 0 108 108" 
     width="108" 
     height="108">
  <defs>
{defs_content}
  </defs>
  <g transform="translate(54, 54) scale(0.10) translate(-512, -512)">
    {layer_02}
    {layer_03}
    {layer_04}
    {layer_05}
    {layer_06}
  </g>
</svg>'''

with open("docs/assets/adaptive/icon-foreground.svg", "w", encoding="utf-8") as f:
    f.write(adaptive_fg)
print("Generated docs/assets/adaptive/ assets")

# 4. Full-Bleed App Icon (No outer canvas margin, pad surface expands to 1024x1024)
pad_grad = '''    <!-- Full-Bleed Pad Surface Gradient -->
    <radialGradient id="pad-surface" cx="45%" cy="35%" r="85%">
      <stop offset="0%" stop-color="#232C3C"/>
      <stop offset="35%" stop-color="#18202E"/>
      <stop offset="70%" stop-color="#101520"/>
      <stop offset="100%" stop-color="#080C14"/>
    </radialGradient>
  </defs>'''

svg_fb = master_svg.replace('  </defs>', pad_grad)
layer1_old_match = re.search(r'  <g id="layer-01-background"[\s\S]*?  </g>', svg_fb)
if layer1_old_match:
    layer1_new = '''  <!-- ========================================== -->
  <!-- LAYER 1: FULL-BLEED PAD SURFACE            -->
  <!-- ========================================== -->
  <g id="layer-01-background" inkscape:groupmode="layer" inkscape:label="01 Full-Bleed Pad">
    <rect width="1024" height="1024" fill="url(#pad-surface)" />
  </g>'''
    svg_fb = svg_fb.replace(layer1_old_match.group(0), layer1_new)

with open("docs/assets/icon-fullbleed.svg", "w", encoding="utf-8") as f:
    f.write(svg_fb)
print("Generated docs/assets/icon-fullbleed.svg")

# 5. Update docs/vector-studio.html with the new master SVG
subprocess.run(["uv", "run", "python", "scripts/build_vector_studio.py"], check=True)
print("Updated docs/vector-studio.html")

