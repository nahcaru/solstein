import subprocess
import os
import math

# Primary skeleton vertices (120° version)
V_PRIM = [
    [369.0, 289.0],  # 0: Apex
    [440.5, 708.5],  # 1: Left Wingtip
    [510.7, 564.0],  # 2: Left Notch
    [604.8, 703.0],  # 3: Stem BL
    [666.1, 661.5],  # 4: Stem BR
    [572.2, 522.8],  # 5: Right Notch
    [731.0, 511.5]   # 6: Right Wingtip
]
GHOST_RADII = [20.0, 18.0, 14.0, 18.0, 18.0, 14.0, 18.0]

def compute_ghost(dx=-25.0, dy=43.3):
    V_ghost = [[x + dx, y + dy] for x, y in V_PRIM]
    n = len(V_ghost)
    parts = []
    arc_data = []
    
    for i in range(n):
        v_prev = V_ghost[(i - 1) % n]
        v_curr = V_ghost[i]
        v_next = V_ghost[(i + 1) % n]
        
        e_in = [v_curr[0] - v_prev[0], v_curr[1] - v_prev[1]]
        e_out = [v_next[0] - v_curr[0], v_next[1] - v_curr[1]]
        
        len_in = math.hypot(e_in[0], e_in[1])
        len_out = math.hypot(e_out[0], e_out[1])
        
        u_in = [e_in[0] / len_in, e_in[1] / len_in]
        u_out = [e_out[0] / len_out, e_out[1] / len_out]
        
        cross = u_in[0] * u_out[1] - u_in[1] * u_out[0]
        dot = u_in[0] * u_out[0] + u_in[1] * u_out[1]
        turn = math.atan2(cross, dot)
        
        theta_half = abs(turn) / 2.0
        d = GHOST_RADII[i] * math.tan(theta_half)
        
        p_start = [v_curr[0] - d * u_in[0], v_curr[1] - d * u_in[1]]
        p_end = [v_curr[0] + d * u_out[0], v_curr[1] + d * u_out[1]]
        sweep = 0 if cross < 0 else 1
        
        arc_data.append((p_start, p_end, sweep))
        
        if i == 0:
            parts.append(f"M {p_start[0]:.1f} {p_start[1]:.1f}")
        else:
            parts.append(f"L {p_start[0]:.1f} {p_start[1]:.1f}")
        parts.append(f"A {GHOST_RADII[i]:.1f} {GHOST_RADII[i]:.1f} 0 0 {sweep} {p_end[0]:.1f} {p_end[1]:.1f}")
        
    parts.append("Z")
    
    # Plan B bevel rail: Continuous from Apex arc -> Left edge -> Wingtip arc
    p_ap_s, p_ap_e = arc_data[0][0], arc_data[0][1]
    p_wt_s, p_wt_e = arc_data[1][0], arc_data[1][1]
    plan_b_rail = f"M {p_ap_s[0]:.1f} {p_ap_s[1]:.1f} A {GHOST_RADII[0]:.1f} {GHOST_RADII[0]:.1f} 0 0 {arc_data[0][2]} {p_ap_e[0]:.1f} {p_ap_e[1]:.1f} L {p_wt_s[0]:.1f} {p_wt_s[1]:.1f} A {GHOST_RADII[1]:.1f} {GHOST_RADII[1]:.1f} 0 0 {arc_data[1][2]} {p_wt_e[0]:.1f} {p_wt_e[1]:.1f}"
    plan_b_coords = (p_ap_s[0], p_ap_s[1], p_wt_e[0], p_wt_e[1])
    
    return " ".join(parts), plan_b_rail, plan_b_coords

def build_refined_svg(p=None):
    if p is None:
        p = {}
    tw = p.get("tw", 22.0)
    cw = p.get("cw", 12.0)
    b_op = p.get("b_op", 0.72)
    b_sw = p.get("b_sw", 76.0)
    b_dev = p.get("b_dev", 38.0)
    ghost_dx = p.get("ghost_dx", -25.0)
    ghost_dy = p.get("ghost_dy", 43.3)
    ghost_highlight = p.get("ghost_highlight", "none")  # "none" (Plan A, recommended) or "faded" (Plan B)
    
    # Strictly symmetric and parallel 120° isometric geometry:
    # Barbs (返し・くびれ) and stem bottom bevels are mutually parallel at 120° (60° from centerline)
    primary_contour = "M 369 289 L 440.5 708.5 L 510.7 564.0 L 598.1 693.0 Q 604.8 703.0 614.8 696.2 L 656.2 668.2 Q 666.1 661.5 659.4 651.5 L 572.2 522.8 L 731.0 511.5 Z"
    rune_cyan = "M 369 289 L 440.5 708.5 L 510.7 564.0 L 598.1 693.0 Q 604.8 703.0 614.8 696.2 L 635.5 682.2"
    rune_amber = "M 369 289 L 731.0 511.5 L 572.2 522.8 L 659.4 651.5 Q 666.1 661.5 656.2 668.2 L 635.5 682.2"

    # Compute congruent translated ghost cursor with rounded corners:
    ghost_d, plan_b_rail, plan_b_coords = compute_ghost(ghost_dx, ghost_dy)

    plan_b_def = ""
    plan_b_elem = ""
    if ghost_highlight == "faded":
        plan_b_def = f'''
    <!-- Plan B: Faded Glass Bevel Reflection Highlight Gradient -->
    <linearGradient id="ghost-bevel-fade-grad" x1="{plan_b_coords[0]:.1f}" y1="{plan_b_coords[1]:.1f}" x2="{plan_b_coords[2]:.1f}" y2="{plan_b_coords[3]:.1f}" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.90"/>
      <stop offset="15%" stop-color="#FFFFFF" stop-opacity="0.80"/>
      <stop offset="40%" stop-color="#BAE6FD" stop-opacity="0.55"/>
      <stop offset="70%" stop-color="#38BDF8" stop-opacity="0.25"/>
      <stop offset="100%" stop-color="#38BDF8" stop-opacity="0.0"/>
    </linearGradient>'''
        plan_b_elem = f'''
    <!-- Integrated Glass Bevel Reflection (Apex to Wingtip with natural fade) -->
    <path id="ghost-bevel-highlight" d="{plan_b_rail}" 
          stroke="url(#ghost-bevel-fade-grad)" stroke-width="2.5" fill="none" 
          stroke-linecap="round" stroke-linejoin="round" />'''

    svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" 
     xmlns:xlink="http://www.w3.org/1999/xlink"
     xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
     viewBox="0 0 1024 1024" 
     width="1024" 
     height="1024">
  <defs>
    <!-- Background Canvas -->
    <radialGradient id="canvas-bg" cx="50%" cy="50%" r="70%">
      <stop offset="0%" stop-color="#101520"/>
      <stop offset="55%" stop-color="#0A0D14"/>
      <stop offset="100%" stop-color="#06080D"/>
    </radialGradient>

    <!-- Squircle Tile Surface -->
    <linearGradient id="squircle-surface" x1="50%" y1="0%" x2="50%" y2="100%">
      <stop offset="0%" stop-color="#232C3C"/>
      <stop offset="25%" stop-color="#1B2332"/>
      <stop offset="70%" stop-color="#111622"/>
      <stop offset="100%" stop-color="#0A0E16"/>
    </linearGradient>

    <!-- Squircle Top Bevel Stroke -->
    <linearGradient id="squircle-bevel-grad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#708299" stop-opacity="0.6"/>
      <stop offset="15%" stop-color="#3A485B" stop-opacity="0.3"/>
      <stop offset="60%" stop-color="#1A222E" stop-opacity="0.1"/>
      <stop offset="100%" stop-color="#0E141C" stop-opacity="0"/>
    </linearGradient>

    <!-- Ghost Cursor Calcite Glass Fill (Perpendicular to Centerline, Zero Orange on Left) -->
    <linearGradient id="ghost-glass-grad" x1="371" y1="643" x2="719" y2="407" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.65"/>
      <stop offset="30%" stop-color="#BAE6FD" stop-opacity="0.55"/>
      <stop offset="47%" stop-color="#E2E8F0" stop-opacity="0.42"/>
      <stop offset="53%" stop-color="#FEF3C7" stop-opacity="0.45"/>
      <stop offset="100%" stop-color="#F59E0B" stop-opacity="0.35"/>
    </linearGradient>

    <!-- Ghost Cursor Rim Glow (Strict Cyan Left, Strict Amber Right) -->
    <linearGradient id="ghost-rim-grad" x1="371" y1="643" x2="719" y2="407" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#E0F8FF" stop-opacity="0.95"/>
      <stop offset="35%" stop-color="#38BDF8" stop-opacity="0.92"/>
      <stop offset="47%" stop-color="#BAE6FD" stop-opacity="0.80"/>
      <stop offset="53%" stop-color="#FDE68A" stop-opacity="0.80"/>
      <stop offset="70%" stop-color="#F59E0B" stop-opacity="0.90"/>
      <stop offset="100%" stop-color="#FCD34D" stop-opacity="0.80"/>
    </linearGradient>

    <!-- Primary Cursor Facet Gradients (Harmonious Pure Optical Calcite) -->
    <!-- Left Facet: Frosted crystal with soft cyan backlight transmission -->
    <linearGradient id="facet-left-grad" x1="15%" y1="15%" x2="85%" y2="85%">
      <stop offset="0%" stop-color="#F8FAFC" stop-opacity="0.58"/>
      <stop offset="25%" stop-color="#DCE7F2" stop-opacity="0.45"/>
      <stop offset="65%" stop-color="#A5BDD2" stop-opacity="0.32"/>
      <stop offset="100%" stop-color="#708B9F" stop-opacity="0.22"/>
    </linearGradient>

    <!-- Right Facet: Frosted crystal with soft solar amber warmth -->
    <linearGradient id="facet-right-grad" x1="40%" y1="0%" x2="60%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.72"/>
      <stop offset="25%" stop-color="#FAF1E4" stop-opacity="0.58"/>
      <stop offset="55%" stop-color="#F2DCC2" stop-opacity="0.44"/>
      <stop offset="80%" stop-color="#DFCAB5" stop-opacity="0.32"/>
      <stop offset="100%" stop-color="#A99580" stop-opacity="0.22"/>
    </linearGradient>

    <!-- Stem Bottom Beveled End Facet (Crystal cut end face) -->
    <linearGradient id="facet-stem-end" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.82"/>
      <stop offset="45%" stop-color="#E2E8F0" stop-opacity="0.68"/>
      <stop offset="100%" stop-color="#94A3B8" stop-opacity="0.50"/>
    </linearGradient>


    <!-- Filters -->
    <filter id="squircle-shadow" x="-20%" y="-20%" width="150%" height="150%">
      <feDropShadow dx="0" dy="38" stdDeviation="46" flood-color="#000000" flood-opacity="0.88"/>
    </filter>

    <filter id="ghost-soft-shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="16" result="blur"/>
      <feDropShadow dx="-6" dy="16" stdDeviation="24" flood-color="#0284C7" flood-opacity="0.35"/>
    </filter>

    <filter id="bloom-cyan" x="-70%" y="-70%" width="240%" height="240%">
      <feGaussianBlur stdDeviation="{b_dev}"/>
    </filter>

    <filter id="bloom-amber" x="-70%" y="-70%" width="240%" height="240%">
      <feGaussianBlur stdDeviation="{b_dev}"/>
    </filter>

    <filter id="tube-glow" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur stdDeviation="8.5"/>
    </filter>

    <!-- Neon Tube Gradients (White Apex -> Nordic Cyan / Solar Amber -> Seamless Stem Bevel Opal) -->
    <!-- Left Neon Glow Tube (Apex White -> Nordic Cyan -> Stem Bevel Opal) -->
    <linearGradient id="neon-cyan-glow-grad" x1="369" y1="289" x2="700.9" y2="355.4" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.95"/>
      <stop offset="8%" stop-color="#FFFFFF" stop-opacity="0.95"/>
      <stop offset="18%" stop-color="#7DD3FC" stop-opacity="0.92"/>
      <stop offset="35%" stop-color="#38BDF8" stop-opacity="0.90"/>
      <stop offset="85%" stop-color="#38BDF8" stop-opacity="0.90"/>
      <stop offset="93%" stop-color="#BAE6FD" stop-opacity="0.92"/>
      <stop offset="100%" stop-color="#E0F8FF" stop-opacity="0.95"/>
    </linearGradient>

    <!-- Left Neon Tube Body (Apex White -> Nordic Cyan -> Stem Bevel Opal) -->
    <linearGradient id="neon-cyan-body-grad" x1="369" y1="289" x2="700.9" y2="355.4" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="1.0"/>
      <stop offset="10%" stop-color="#FFFFFF" stop-opacity="1.0"/>
      <stop offset="20%" stop-color="#BAE6FD" stop-opacity="1.0"/>
      <stop offset="35%" stop-color="#38BDF8" stop-opacity="1.0"/>
      <stop offset="85%" stop-color="#38BDF8" stop-opacity="1.0"/>
      <stop offset="93%" stop-color="#7DD3FC" stop-opacity="1.0"/>
      <stop offset="100%" stop-color="#E0F8FF" stop-opacity="1.0"/>
    </linearGradient>

    <!-- Right Neon Glow Tube (Apex White -> Solar Amber -> Stem Bevel Opal) -->
    <linearGradient id="neon-amber-glow-grad" x1="369" y1="289" x2="454.9" y2="718.3" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.95"/>
      <stop offset="8%" stop-color="#FFFFFF" stop-opacity="0.95"/>
      <stop offset="18%" stop-color="#FCD34D" stop-opacity="0.92"/>
      <stop offset="35%" stop-color="#F59E0B" stop-opacity="0.90"/>
      <stop offset="88%" stop-color="#F59E0B" stop-opacity="0.90"/>
      <stop offset="95%" stop-color="#FDE68A" stop-opacity="0.92"/>
      <stop offset="100%" stop-color="#FEF3C7" stop-opacity="0.95"/>
    </linearGradient>

    <!-- Right Neon Tube Body (Apex White -> Solar Amber -> Stem Bevel Opal) -->
    <linearGradient id="neon-amber-body-grad" x1="369" y1="289" x2="454.9" y2="718.3" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="1.0"/>
      <stop offset="10%" stop-color="#FFFFFF" stop-opacity="1.0"/>
      <stop offset="20%" stop-color="#FEF08A" stop-opacity="1.0"/>
      <stop offset="35%" stop-color="#F59E0B" stop-opacity="1.0"/>
      <stop offset="88%" stop-color="#F59E0B" stop-opacity="1.0"/>
      <stop offset="95%" stop-color="#FCD34D" stop-opacity="1.0"/>
      <stop offset="100%" stop-color="#FEF3C7" stop-opacity="1.0"/>
    </linearGradient>

    <!-- Primary Crystal Interior Clip Path -->
    <clipPath id="primary-crystal-clip">
      <path d="{primary_contour}" />
    </clipPath>

    <!-- Prismatic Rainbow Dispersion Spectrum (Axial Traversal) -->
    <!-- Violet -> Cyan -> Mint -> Emerald -> Solar Gold -> Amber -> Coral -> Magenta -> Violet -->
    <linearGradient id="prism-axial-grad" x1="365" y1="295" x2="625" y2="675" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#818CF8" stop-opacity="0.95"/>
      <stop offset="12%" stop-color="#38BDF8" stop-opacity="0.95"/>
      <stop offset="24%" stop-color="#2DD4BF" stop-opacity="0.95"/>
      <stop offset="36%" stop-color="#34D399" stop-opacity="0.95"/>
      <stop offset="48%" stop-color="#A3E635" stop-opacity="0.95"/>
      <stop offset="58%" stop-color="#FDE047" stop-opacity="0.95"/>
      <stop offset="70%" stop-color="#FB923C" stop-opacity="0.95"/>
      <stop offset="82%" stop-color="#F43F5E" stop-opacity="0.95"/>
      <stop offset="92%" stop-color="#E879F9" stop-opacity="0.95"/>
      <stop offset="100%" stop-color="#818CF8" stop-opacity="0.95"/>
    </linearGradient>

    <!-- Prismatic Cross-Dispersion Spectrum (Transverse Aberration) -->
    <linearGradient id="prism-cross-grad" x1="410" y1="440" x2="570" y2="540" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#A855F7" stop-opacity="0.90"/>
      <stop offset="18%" stop-color="#EC4899" stop-opacity="0.92"/>
      <stop offset="36%" stop-color="#F59E0B" stop-opacity="0.95"/>
      <stop offset="54%" stop-color="#10B981" stop-opacity="0.95"/>
      <stop offset="72%" stop-color="#06B6D4" stop-opacity="0.95"/>
      <stop offset="88%" stop-color="#6366F1" stop-opacity="0.92"/>
      <stop offset="100%" stop-color="#A855F7" stop-opacity="0.90"/>
    </linearGradient>

    <!-- Prismatic Haze Filters (Optical Caustics & Volumetric Mist) -->
    <filter id="prism-blur-deep" x="-60%" y="-60%" width="220%" height="220%">
      <feGaussianBlur stdDeviation="26"/>
    </filter>
    <filter id="prism-blur-mid" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur stdDeviation="11"/>
    </filter>
    <filter id="prism-blur-core" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="3.6"/>
    </filter>{plan_b_def}
  </defs>

  <!-- ========================================== -->
  <!-- LAYER 1: BACKGROUND & SQUIRCLE TILE        -->
  <!-- ========================================== -->
  <g id="layer-01-background" inkscape:groupmode="layer" inkscape:label="01 Background Squircle">
    <rect width="1024" height="1024" fill="url(#canvas-bg)" />

    <!-- Outer Squircle Drop Shadow -->
    <rect x="182" y="175" width="660" height="672" rx="172" ry="172" 
          fill="#000000" filter="url(#squircle-shadow)" opacity="0.95" />

    <!-- Squircle Tile Surface -->
    <rect x="182" y="175" width="660" height="672" rx="172" ry="172" 
          fill="url(#squircle-surface)" 
          stroke="url(#squircle-bevel-grad)" 
          stroke-width="1.8" />

    <!-- Top Bevel Highlight Arc Line -->
    <path d="M 320 176 L 704 176" 
          stroke="#94A3B8" stroke-opacity="0.25" stroke-width="1.6" stroke-linecap="round" />
  </g>

  <!-- ========================================== -->
  <!-- LAYER 2: VOLUMETRIC OPTICAL BLOOM          -->
  <!-- ========================================== -->
  <g id="layer-02-ambient-glow" inkscape:groupmode="layer" inkscape:label="02 Ambient Optical Halos">
    <!-- Left Cyan Bloom (Volumetric Optical Halo) -->
    <path d="M 369 289 L 440.5 708.5 L 510.7 564.0 L 604.8 703.0" 
          fill="none" 
          stroke="#0284C7" stroke-width="{b_sw}" stroke-opacity="{b_op}" 
          stroke-linecap="round" stroke-linejoin="round" 
          filter="url(#bloom-cyan)" />

    <!-- Right Amber Bloom (Volumetric Optical Halo) -->
    <path d="M 369 289 L 731.0 511.5 L 572.2 522.8 L 666.1 661.5" 
          fill="none" 
          stroke="#D97706" stroke-width="{b_sw}" stroke-opacity="{b_op}" 
          stroke-linecap="round" stroke-linejoin="round" 
          filter="url(#bloom-amber)" />
  </g>

  <!-- ========================================== -->
  <!-- LAYER 3: BIREFRINGENT GHOST POINTER        -->
  <!-- Perfect Geometric Calcite Secondary Ray    -->
  <!-- ========================================== -->
  <g id="layer-03-ghost-pointer" inkscape:groupmode="layer" inkscape:label="03 Birefringent Ghost Pointer">
    <!-- Ghost Body with clean geometric contours & soft shadow -->
    <path id="ghost-body-shadow" d="{ghost_d}" 
          fill="url(#ghost-glass-grad)" 
          stroke="url(#ghost-rim-grad)" 
          stroke-width="12" 
          stroke-linejoin="round" stroke-linecap="round" 
          filter="url(#ghost-soft-shadow)" />

    <!-- Ghost Inner Core Fill -->
    <path id="ghost-body-core" d="{ghost_d}" 
          fill="url(#ghost-glass-grad)" 
          stroke="url(#ghost-rim-grad)" 
          stroke-width="5" 
          stroke-linejoin="round" stroke-linecap="round" />{plan_b_elem}
  </g>

  <!-- ========================================== -->
  <!-- LAYER 4: REFRACTION CAUSTICS & PRISM HAZE  -->
  <!-- Ghost outline prismatic dispersion inside crystal -->
  <!-- ========================================== -->
  <g id="layer-04-refraction-caustics" inkscape:groupmode="layer" inkscape:label="04 Refraction Caustics" clip-path="url(#primary-crystal-clip)">
    <!-- 1. Deep Volumetric Rainbow Haze (広域の虹色モヤ: 54px blur 26px) -->
    <path id="prism-haze-deep" class="ghost-prism-path" d="{ghost_d}" fill="none" 
          stroke="url(#prism-axial-grad)" stroke-width="54" stroke-opacity="0.60" 
          stroke-linecap="round" stroke-linejoin="round" 
          filter="url(#prism-blur-deep)" style="mix-blend-mode: screen;" />

    <!-- 2. Transverse Chromatic Dispersion Fringe (横断スペクトル帯: 24px blur 11px) -->
    <path id="prism-haze-mid" class="ghost-prism-path" d="{ghost_d}" fill="none" 
          stroke="url(#prism-cross-grad)" stroke-width="24" stroke-opacity="0.70" 
          stroke-linecap="round" stroke-linejoin="round" 
          filter="url(#prism-blur-mid)" style="mix-blend-mode: screen;" />

    <!-- 3. Focused Spectral Prism Line (集光スペクトル光条: 8.5px blur 3.6px) -->
    <path id="prism-haze-line" class="ghost-prism-path" d="{ghost_d}" fill="none" 
          stroke="url(#prism-axial-grad)" stroke-width="8.5" stroke-opacity="0.85" 
          stroke-linecap="round" stroke-linejoin="round" 
          filter="url(#prism-blur-core)" style="mix-blend-mode: screen;" />

    <!-- 4. Luminous Internal Refractive Core Filament (屈折白色核ハイライト: 2.2px) -->
    <path id="prism-haze-core" class="ghost-prism-path" d="{ghost_d}" fill="none" 
          stroke="#FFFFFF" stroke-width="2.2" stroke-opacity="0.75" 
          stroke-linecap="round" stroke-linejoin="round" 
          filter="url(#prism-blur-core)" />
  </g>

  <!-- ========================================== -->
  <!-- LAYER 5: PRIMARY CURSOR - TRANSLUCENT FACETS-->
  <!-- Pure Iceland Spar Calcite with 3D Creases  -->
  <!-- ========================================== -->
  <g id="layer-05-primary-cursor" inkscape:groupmode="layer" inkscape:label="05 Primary Crystal Facets">
    <!-- 1. Left Unified Crystal Facet (Seamless Arrowhead + Stem, 120° Barb) -->
    <path d="M 369 289 L 440.5 708.5 L 510.7 564.0 L 604.8 703.0 L 623.5 664.6 Z" 
          fill="url(#facet-left-grad)" />

    <!-- 2. Right Unified Crystal Facet (Seamless Arrowhead + Stem, 120° Barb) -->
    <path d="M 369 289 L 731.0 511.5 L 572.2 522.8 L 666.1 661.5 L 623.5 664.6 Z" 
          fill="url(#facet-right-grad)" />

    <!-- 3. Stem Bottom Triangular End Facet (120° Wide-Angle Isosceles Bevel) -->
    <path d="M 623.5 664.6 L 604.8 703.0 L 666.1 661.5 Z" 
          fill="url(#facet-stem-end)" />

    <!-- 3D Internal Crease Ridge Lines -->
    <!-- Continuous Unbroken Central Ridge: Apex to Stem End (120° apex) -->
    <line x1="369" y1="289" x2="623.5" y2="664.6" 
          stroke="#FFFFFF" stroke-width="2.5" stroke-opacity="0.85" stroke-linecap="round" />

    <!-- Stem Bottom-Left Facet Crease: Stem Center to Bottom-Left Corner (Parallel to Barb) -->
    <line x1="623.5" y1="664.6" x2="604.8" y2="703.0" 
          stroke="#FFFFFF" stroke-width="1.8" stroke-opacity="0.75" stroke-linecap="round" />

    <!-- Stem Bottom-Right Facet Crease: Stem Center to Bottom-Right Corner (Parallel to Barb) -->
    <line x1="623.5" y1="664.6" x2="666.1" y2="661.5" 
          stroke="#FFFFFF" stroke-width="1.8" stroke-opacity="0.75" stroke-linecap="round" />
  </g>

  <!-- ========================================== -->
  <!-- LAYER 6: RUNIC CONTOUR ACCENTS             -->
  <!-- ========================================== -->
  <g id="layer-06-rune-contours" inkscape:groupmode="layer" inkscape:label="06 Runic Sól (ᛋ) Contours">
    <!-- LEFT CONTOUR: YOUNGER FUTHARK SÓL (ᛋ) IN NORDIC CYAN (WHITE AT APEX) -->
    <g id="rune-sol-cyan">
      <!-- Glow Tube Mid Layer -->
      <path d="{rune_cyan}" 
            fill="none" 
            stroke="url(#neon-cyan-glow-grad)" stroke-width="{tw}" stroke-opacity="0.88" 
            stroke-linecap="round" stroke-linejoin="round" 
            filter="url(#tube-glow)" />

      <!-- Glowing Tube Body -->
      <path d="{rune_cyan}" 
            fill="none" 
            stroke="url(#neon-cyan-body-grad)" stroke-width="{tw * 0.68}" stroke-opacity="1.0" 
            stroke-linecap="round" stroke-linejoin="round" />
    </g>

    <!-- RIGHT CONTOUR: SYMMETRICAL SOLAR AMBER (WHITE AT APEX) -->
    <g id="rune-mirror-amber">
      <!-- Glow Tube Mid Layer -->
      <path d="{rune_amber}" 
            fill="none" 
            stroke="url(#neon-amber-glow-grad)" stroke-width="{tw}" stroke-opacity="0.88" 
            stroke-linecap="round" stroke-linejoin="round" 
            filter="url(#tube-glow)" />

      <!-- Glowing Tube Body -->
      <path d="{rune_amber}" 
            fill="none" 
            stroke="url(#neon-amber-body-grad)" stroke-width="{tw * 0.68}" stroke-opacity="1.0" 
            stroke-linecap="round" stroke-linejoin="round" />
    </g>

    <!-- CONTINUOUS UNIFIED WHITE-HOT CORE RAIL -->
    <path d="{primary_contour}" 
          fill="none" 
          stroke="#FFFFFF" 
          stroke-width="{cw}" 
          stroke-linejoin="round" 
          stroke-linecap="round" 
          stroke-opacity="1.0" />
  </g>
</svg>
'''
    return svg

def evaluate(p=None):
    import numpy as np
    from PIL import Image
    from skimage.metrics import structural_similarity as ssim
    from skimage.metrics import peak_signal_noise_ratio as psnr

    svg = build_refined_svg(p)
    svg_tmp = "/tmp/opt_logo.svg"
    png_tmp = "/tmp/opt_logo.png"
    with open(svg_tmp, "w", encoding="utf-8") as f:
        f.write(svg)
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", svg_tmp, "-o", png_tmp], check=True)
    
    target_img = Image.open("docs/assets/logo.jpg").convert("RGB")
    render_img = Image.open(png_tmp).convert("RGB")
    t_arr = np.array(target_img, dtype=np.float32)
    r_arr = np.array(render_img, dtype=np.float32)
    
    diff = np.abs(t_arr - r_arr)
    mae = float(np.mean(diff))
    p_val = float(psnr(t_arr.astype(np.uint8), r_arr.astype(np.uint8), data_range=255))
    s_val = float(ssim(t_arr.astype(np.uint8), r_arr.astype(np.uint8), channel_axis=2, data_range=255))
    
    diff_vis = np.clip(diff * 3.5, 0, 255).astype(np.uint8)
    Image.fromarray(diff_vis).save("/tmp/opt_diff.png")
    
    print(f"MAE: {mae:.2f} | PSNR: {p_val:.2f} dB | SSIM: {s_val:.4f}")
    return mae, p_val, s_val

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Optimize Solstein SVG Vector Identity")
    parser.add_argument("--dx", type=float, default=-25.0, help="Ghost translation dx (default: -25.0)")
    parser.add_argument("--dy", type=float, default=43.3, help="Ghost translation dy (default: 43.3)")
    parser.add_argument("--tw", type=float, default=22.0, help="Tube stroke width")
    parser.add_argument("--cw", type=float, default=12.0, help="Core rail stroke width")
    parser.add_argument("--b_op", type=float, default=0.72, help="Bloom opacity")
    parser.add_argument("--b_sw", type=float, default=76.0, help="Bloom stroke width")
    parser.add_argument("--b_dev", type=float, default=38.0, help="Bloom blur stdDeviation")
    args = parser.parse_args()
    
    params = {
        "ghost_dx": args.dx,
        "ghost_dy": args.dy,
        "tw": args.tw,
        "cw": args.cw,
        "b_op": args.b_op,
        "b_sw": args.b_sw,
        "b_dev": args.b_dev
    }
    evaluate(params)
