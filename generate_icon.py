#!/usr/bin/env python3
"""
Generate FullDuplex app icon - purple background with bold "FD" text.
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_icon(size=1024):
    """Create the FullDuplex app icon at specified size."""

    # Create base image with transparency
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))

    # iOS icon corner radius (approximately 22.37% of size for iOS)
    corner_radius = int(size * 0.2237)

    # Create gradient background - deep purple to vibrant purple
    gradient = Image.new('RGBA', (size, size), (0, 0, 0, 0))

    # Purple gradient colors (deep violet to bright purple)
    color_top = (88, 28, 135)      # Deep purple (#581C87)
    color_bottom = (147, 51, 234)  # Vibrant purple (#9333EA)

    for y in range(size):
        ratio = y / size
        # Ease the gradient for smoother transition
        ratio = ratio * ratio * (3 - 2 * ratio)  # Smoothstep
        r = int(color_top[0] + (color_bottom[0] - color_top[0]) * ratio)
        g = int(color_top[1] + (color_bottom[1] - color_top[1]) * ratio)
        b = int(color_top[2] + (color_bottom[2] - color_top[2]) * ratio)
        for x in range(size):
            gradient.putpixel((x, y), (r, g, b, 255))

    # Create rounded rectangle mask
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(
        [(0, 0), (size - 1, size - 1)],
        radius=corner_radius,
        fill=255
    )

    # Apply mask to gradient
    img = Image.composite(gradient, img, mask)
    draw = ImageDraw.Draw(img)

    # Calculate center
    cx, cy = size // 2, size // 2

    # Load a bold font - try system fonts
    font_size = int(size * 0.42)
    font = None

    # Try various bold fonts - prefer heavy/black weights
    font_paths = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Impact.ttf",
        "/Library/Fonts/SF-Pro-Display-Black.otf",
        "/Library/Fonts/SF-Pro-Display-Heavy.otf",
        "/Library/Fonts/SF-Pro-Display-Bold.otf",
        "/System/Library/Fonts/SFNS.ttf",
    ]

    for font_path in font_paths:
        if os.path.exists(font_path):
            try:
                font = ImageFont.truetype(font_path, font_size)
                break
            except:
                continue

    if font is None:
        # Fallback to default
        font = ImageFont.load_default()

    # Draw "FD" text centered
    text = "FD"

    # Get text bounding box for centering
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]

    # Calculate position to center text
    text_x = cx - text_width // 2 - bbox[0]
    text_y = cy - text_height // 2 - bbox[1]

    # Draw white text
    draw.text((text_x, text_y), text, font=font, fill=(255, 255, 255, 255))

    return img


def main():
    """Generate icons at various sizes needed for iOS."""

    # Standard iOS app icon sizes
    sizes = {
        'AppIcon-1024': 1024,  # App Store
        'AppIcon-180': 180,    # iPhone @3x
        'AppIcon-120': 120,    # iPhone @2x
        'AppIcon-167': 167,    # iPad Pro @2x
        'AppIcon-152': 152,    # iPad @2x
        'AppIcon-76': 76,      # iPad @1x
        'AppIcon-60': 60,      # iPhone @1x (older)
        'AppIcon-40': 40,      # Spotlight @2x
        'AppIcon-29': 29,      # Settings @1x
        'AppIcon-20': 20,      # Notification @1x
    }

    # Generate master at 1024
    print("Generating master icon at 1024x1024...")
    master = create_icon(1024)

    # Save master
    master.save('FullDuplex-AppIcon.png', 'PNG')
    print("Saved: FullDuplex-AppIcon.png")

    # Generate all sizes from master using high-quality downscaling
    for name, size in sizes.items():
        if size != 1024:
            resized = master.resize((size, size), Image.Resampling.LANCZOS)
            filename = f'{name}.png'
            resized.save(filename, 'PNG')
            print(f"Saved: {filename}")

    print("\nDone! Main icon: FullDuplex-AppIcon.png")


if __name__ == '__main__':
    main()
