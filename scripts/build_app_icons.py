#!/usr/bin/env python3
"""Build and deploy all Solstein app icons, iOS asset catalogs, and web favicons."""

import json
import os
import subprocess
from PIL import Image, ImageEnhance, ImageOps


def build_icons():
    print("Building Solstein App Icons...")

    # 1. Render master high-res PNG from docs/assets/icon-fullbleed.svg
    fb_svg = "docs/assets/icon-fullbleed.svg"
    fb_png = "docs/assets/icon.png"
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", fb_svg, "-o", fb_png], check=True)
    print(f"Rendered {fb_png} (1024x1024)")

    base_icon = Image.open(fb_png).convert("RGB")

    # 2. Deploy to app/assets/icon/
    os.makedirs("app/assets/icon", exist_ok=True)
    base_icon.save("app/assets/icon/icon.png")

    # Render adaptive icon layers
    ad_bg_svg = "docs/assets/adaptive/icon-background.svg"
    ad_fg_svg = "docs/assets/adaptive/icon-foreground.svg"
    ad_bg_png = "app/assets/icon/icon_background.png"
    ad_fg_png = "app/assets/icon/icon_foreground.png"
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", ad_bg_svg, "-o", ad_bg_png], check=True)
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", ad_fg_svg, "-o", ad_fg_png], check=True)

    # Generate Android 13+ monochrome icon from foreground alpha channel
    fg_img = Image.open(ad_fg_png).convert("RGBA")
    r, g, b, a = fg_img.split()
    white_img = Image.new("RGBA", (1024, 1024), (255, 255, 255, 255))
    white_img.putalpha(a)
    white_img.save("app/assets/icon/icon_monochrome.png")

    # 3. iOS Master Icons
    base_icon.save("app/assets/icon/icon_ios.png")

    # iOS 18 Dark Mode
    enhancer_contrast = ImageEnhance.Contrast(base_icon)
    dark_icon = enhancer_contrast.enhance(1.15)
    enhancer_brightness = ImageEnhance.Brightness(dark_icon)
    dark_icon = enhancer_brightness.enhance(0.92)
    dark_icon.save("app/assets/icon/icon_ios_dark.png")

    # iOS 18 Tinted Mode (Pure Grayscale)
    gray = ImageOps.grayscale(base_icon)
    lut = []
    for i in range(256):
        if i < 30:
            lut.append(0)
        else:
            val = int(((i - 30) / 225.0) ** 1.2 * 255)
            lut.append(min(255, max(0, val)))
    tinted = gray.point(lut).convert("RGB")
    tinted.save("app/assets/icon/icon_ios_tinted.png")

    # 4. Xcode Asset Catalog (app/assets/icon/ios/AppIcon.appiconset/)
    appiconset_dir = "app/assets/icon/ios/AppIcon.appiconset"
    os.makedirs(appiconset_dir, exist_ok=True)

    entries = [
        {"idiom": "universal", "platform": "ios", "size": "1024x1024", "scale": "1x", "filename": "AppIcon-1024x1024@1x.png", "px": 1024},
        {"idiom": "iphone", "size": "20x20", "scale": "2x", "filename": "Icon-App-20x20@2x.png", "px": 40},
        {"idiom": "iphone", "size": "20x20", "scale": "3x", "filename": "Icon-App-20x20@3x.png", "px": 60},
        {"idiom": "iphone", "size": "29x29", "scale": "1x", "filename": "Icon-App-29x29@1x.png", "px": 29},
        {"idiom": "iphone", "size": "29x29", "scale": "2x", "filename": "Icon-App-29x29@2x.png", "px": 58},
        {"idiom": "iphone", "size": "29x29", "scale": "3x", "filename": "Icon-App-29x29@3x.png", "px": 87},
        {"idiom": "iphone", "size": "40x40", "scale": "2x", "filename": "Icon-App-40x40@2x.png", "px": 80},
        {"idiom": "iphone", "size": "40x40", "scale": "3x", "filename": "Icon-App-40x40@3x.png", "px": 120},
        {"idiom": "iphone", "size": "60x60", "scale": "2x", "filename": "Icon-App-60x60@2x.png", "px": 120},
        {"idiom": "iphone", "size": "60x60", "scale": "3x", "filename": "Icon-App-60x60@3x.png", "px": 180},
        {"idiom": "ipad", "size": "20x20", "scale": "1x", "filename": "Icon-App-20x20@1x.png", "px": 20},
        {"idiom": "ipad", "size": "20x20", "scale": "2x", "filename": "Icon-App-20x20@2x.png", "px": 40},
        {"idiom": "ipad", "size": "29x29", "scale": "1x", "filename": "Icon-App-29x29@1x.png", "px": 29},
        {"idiom": "ipad", "size": "29x29", "scale": "2x", "filename": "Icon-App-29x29@2x.png", "px": 58},
        {"idiom": "ipad", "size": "40x40", "scale": "1x", "filename": "Icon-App-40x40@1x.png", "px": 40},
        {"idiom": "ipad", "size": "40x40", "scale": "2x", "filename": "Icon-App-40x40@2x.png", "px": 80},
        {"idiom": "ipad", "size": "76x76", "scale": "1x", "filename": "Icon-App-76x76@1x.png", "px": 76},
        {"idiom": "ipad", "size": "76x76", "scale": "2x", "filename": "Icon-App-76x76@2x.png", "px": 152},
        {"idiom": "ipad", "size": "83.5x83.5", "scale": "2x", "filename": "Icon-App-83.5x83.5@2x.png", "px": 167},
        {"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "Icon-App-1024x1024@1x.png", "px": 1024},
    ]

    generated_files = set()
    contents_images = []

    for entry in entries:
        fname = entry["filename"]
        px = entry["px"]
        target_path = os.path.join(appiconset_dir, fname)
        if fname not in generated_files:
            resized = base_icon.resize((px, px), Image.Resampling.LANCZOS)
            resized.save(target_path)
            generated_files.add(fname)

        item = {
            "idiom": entry["idiom"],
            "size": entry["size"],
            "scale": entry["scale"],
            "filename": fname,
        }
        if "platform" in entry:
            item["platform"] = entry["platform"]
        contents_images.append(item)

    dark_filename = "AppIcon-Dark-1024x1024@1x.png"
    tinted_filename = "AppIcon-Tinted-1024x1024@1x.png"

    dark_icon.save(os.path.join(appiconset_dir, dark_filename))
    tinted.save(os.path.join(appiconset_dir, tinted_filename))

    contents_images.append({
        "appearances": [{"appearance": "luminosity", "value": "dark"}],
        "idiom": "universal",
        "platform": "ios",
        "size": "1024x1024",
        "scale": "1x",
        "filename": dark_filename,
    })

    contents_images.append({
        "appearances": [{"appearance": "luminosity", "value": "tinted"}],
        "idiom": "universal",
        "platform": "ios",
        "size": "1024x1024",
        "scale": "1x",
        "filename": tinted_filename,
    })

    contents = {
        "images": contents_images,
        "info": {"author": "xcode", "version": 1},
    }

    with open(os.path.join(appiconset_dir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)

    # 5. Web Favicons
    docs_assets_dir = "docs/assets"
    apple_icon = base_icon.resize((180, 180), Image.Resampling.LANCZOS)
    apple_icon.save(os.path.join(docs_assets_dir, "apple-touch-icon.png"))

    fav_32 = base_icon.resize((32, 32), Image.Resampling.LANCZOS)
    fav_32.save(os.path.join(docs_assets_dir, "favicon-32x32.png"))

    fav_16 = base_icon.resize((16, 16), Image.Resampling.LANCZOS)
    fav_16.save(os.path.join(docs_assets_dir, "favicon-16x16.png"))

    fav_32.save(os.path.join(docs_assets_dir, "favicon.ico"), format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
    fav_32.save("docs/favicon.ico", format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])

    # 6. Sync iOS assets to docs/assets/ios/
    os.makedirs("docs/assets/ios", exist_ok=True)
    subprocess.run("cp -r app/assets/icon/ios/* docs/assets/ios/ && cp app/assets/icon/icon_ios* docs/assets/ios/", shell=True, check=True)

    # 7. Run flutter_launcher_icons
    subprocess.run(["fvm", "dart", "run", "flutter_launcher_icons"], cwd="app", check=True)

    print("All app icons built and synchronized successfully.")


if __name__ == "__main__":
    build_icons()
