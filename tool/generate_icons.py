#!/usr/bin/env python3
import os
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

def create_pie_icon(size=1024, maskable=False, is_favicon=False):
    # Render at 2x super-sampling for pristine antialiasing
    scale = 2
    canvas_size = size * scale
    
    img = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    bg_dark = (9, 10, 14, 255) # PieColors.canvas #090A0E
    
    if maskable:
        # Full bleed background for adaptive / maskable icons
        draw.rectangle([0, 0, canvas_size, canvas_size], fill=bg_dark)
        badge_pad = int(canvas_size * 0.16)
    elif is_favicon:
        badge_pad = int(canvas_size * 0.04)
    else:
        badge_pad = int(canvas_size * 0.08)
        
    badge_rect = [badge_pad, badge_pad, canvas_size - badge_pad, canvas_size - badge_pad]
    badge_w = badge_rect[2] - badge_rect[0]
    badge_h = badge_rect[3] - badge_rect[1]
    corner_radius = int(badge_w * 0.25)
    
    # Outer Glow for non-maskable icons (when size >= 48)
    if not maskable and size >= 48:
        glow_size = int(canvas_size)
        glow = Image.new('RGBA', (glow_size, glow_size), (0, 0, 0, 0))
        glow_draw = ImageDraw.Draw(glow)
        glow_draw.rounded_rectangle(badge_rect, radius=corner_radius, fill=(245, 158, 11, 75))
        glow = glow.filter(ImageFilter.GaussianBlur(radius=int(28 * scale)))
        img = Image.alpha_composite(img, glow)
        draw = ImageDraw.Draw(img)
    
    # Gradient badge container
    badge_mask = Image.new('L', (canvas_size, canvas_size), 0)
    ImageDraw.Draw(badge_mask).rounded_rectangle(badge_rect, radius=corner_radius, fill=255)
    
    badge_surf = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    b_draw = ImageDraw.Draw(badge_surf)
    for y in range(badge_rect[1], badge_rect[3] + 1):
        ratio = (y - badge_rect[1]) / float(badge_h)
        # Deep tonal surface gradient from #202430 to #11131A
        r = int(32 * (1 - ratio) + 17 * ratio)
        g = int(36 * (1 - ratio) + 19 * ratio)
        b = int(48 * (1 - ratio) + 26 * ratio)
        b_draw.line([(badge_rect[0], y), (badge_rect[2], y)], fill=(r, g, b, 255))
        
    img.paste(badge_surf, (0, 0), badge_mask)
    draw = ImageDraw.Draw(img)
    
    # Border
    border_width = max(1, int((6 if not is_favicon else 8) * scale * (size / 1024.0)))
    if is_favicon:
        border_width = max(1, int(1.5 * scale))
        
    draw.rounded_rectangle(
        badge_rect,
        radius=corner_radius,
        outline=(245, 158, 11, 240), # PieColors.cashierAccent
        width=border_width
    )
    
    # Inner rim highlight (only for sizes >= 64)
    if size >= 64:
        inner_pad = border_width
        inner_rect = [
            badge_rect[0] + inner_pad,
            badge_rect[1] + inner_pad,
            badge_rect[2] - inner_pad,
            badge_rect[3] - inner_pad
        ]
        draw.rounded_rectangle(
            inner_rect,
            radius=max(0, corner_radius - inner_pad),
            outline=(251, 191, 36, 65),
            width=max(1, int(2 * scale))
        )
    
    # Draw Greek Letter π
    font_size = int(badge_w * (0.64 if not is_favicon else 0.70))
    font = ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans-Bold.ttf', font_size)
    bbox = font.getbbox('π')
    glyph_w = bbox[2] - bbox[0]
    glyph_h = bbox[3] - bbox[1]
    
    cx = (badge_rect[0] + badge_rect[2]) // 2
    cy = (badge_rect[1] + badge_rect[3]) // 2
    
    target_x = cx - glyph_w // 2 - bbox[0]
    target_y = cy - glyph_h // 2 - bbox[1] + int(canvas_size * 0.012)
    
    # Shadow for π (for sizes >= 48)
    if size >= 48:
        shadow_offset = max(2, int(6 * scale * (size / 1024.0)))
        shadow_img = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
        s_draw = ImageDraw.Draw(shadow_img)
        s_draw.text((target_x, target_y + shadow_offset), 'π', font=font, fill=(0, 0, 0, 190))
        shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(radius=max(1, int(5 * scale * (size / 1024.0)))))
        img = Image.alpha_composite(img, shadow_img)
        draw = ImageDraw.Draw(img)
    
    # Gradient on π
    pi_mask = Image.new('L', (canvas_size, canvas_size), 0)
    ImageDraw.Draw(pi_mask).text((target_x, target_y), 'π', font=font, fill=255)
    
    pi_color = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    pi_draw = ImageDraw.Draw(pi_color)
    top_y = target_y + bbox[1]
    bottom_y = target_y + bbox[3]
    h_pi = max(1, bottom_y - top_y)
    
    for y in range(top_y, bottom_y + 1):
        ratio = (y - top_y) / float(h_pi)
        if ratio < 0.5:
            sub = ratio / 0.5
            r = int(253 * (1 - sub) + 245 * sub) # #FDE047 -> #F59E0B
            g = int(224 * (1 - sub) + 158 * sub)
            b = int(71 * (1 - sub) + 11 * sub)
        else:
            sub = (ratio - 0.5) / 0.5
            r = int(245 * (1 - sub) + 217 * sub) # #F59E0B -> #D97706
            g = int(158 * (1 - sub) + 119 * sub)
            b = int(11 * (1 - sub) + 6 * sub)
        pi_draw.line([(0, y), (canvas_size, y)], fill=(r, g, b, 255))
        
    img.paste(pi_color, (0, 0), pi_mask)
    
    # Downsample with Lanczos filter for maximum sharpness
    final_img = img.resize((size, size), Image.Resampling.LANCZOS)
    return final_img

def main():
    print("Generating official PIE project icons across all targets...")
    
    # 1. Master Icons
    os.makedirs('assets/icons', exist_ok=True)
    master = create_pie_icon(1024)
    master.save('assets/icons/app_icon.png')
    print(" -> assets/icons/app_icon.png (1024x1024)")
    
    master_maskable = create_pie_icon(1024, maskable=True)
    master_maskable.save('assets/icons/app_icon_maskable.png')
    print(" -> assets/icons/app_icon_maskable.png (1024x1024)")
    
    # 2. Web & PWA
    os.makedirs('web/icons', exist_ok=True)
    favicon = create_pie_icon(64, is_favicon=True)
    favicon.save('web/favicon.png')
    print(" -> web/favicon.png (64x64 high-res favicon)")
    
    icon_192 = create_pie_icon(192)
    icon_192.save('web/icons/Icon-192.png')
    print(" -> web/icons/Icon-192.png")
    
    icon_512 = create_pie_icon(512)
    icon_512.save('web/icons/Icon-512.png')
    print(" -> web/icons/Icon-512.png")
    
    icon_mask_192 = create_pie_icon(192, maskable=True)
    icon_mask_192.save('web/icons/Icon-maskable-192.png')
    print(" -> web/icons/Icon-maskable-192.png")
    
    icon_mask_512 = create_pie_icon(512, maskable=True)
    icon_mask_512.save('web/icons/Icon-maskable-512.png')
    print(" -> web/icons/Icon-maskable-512.png")
    
    # 3. Android Mipmaps
    android_targets = [
        ('android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48),
        ('android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72),
        ('android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', 96),
        ('android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 144),
        ('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 192),
    ]
    for path, sz in android_targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img = create_pie_icon(sz)
        img.save(path)
        print(f" -> {path} ({sz}x{sz})")
        
    # 4. macOS AppIcon
    macos_dir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    if os.path.exists(macos_dir):
        macos_targets = [
            ('app_icon_16.png', 16),
            ('app_icon_32.png', 32),
            ('app_icon_64.png', 64),
            ('app_icon_128.png', 128),
            ('app_icon_256.png', 256),
            ('app_icon_512.png', 512),
            ('app_icon_1024.png', 1024),
        ]
        for fname, sz in macos_targets:
            p = os.path.join(macos_dir, fname)
            img = create_pie_icon(sz)
            img.save(p)
            print(f" -> {p} ({sz}x{sz})")
            
    # 5. Windows ICO
    win_dir = 'windows/runner/resources'
    if os.path.exists(win_dir):
        ico_path = os.path.join(win_dir, 'app_icon.ico')
        master.save(ico_path, format='ICO', sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
        print(f" -> {ico_path} (Multi-res ICO 16-256)")
        
    # 6. Linux icon
    linux_assets = 'linux/assets'
    os.makedirs(linux_assets, exist_ok=True)
    linux_icon = create_pie_icon(256)
    linux_icon.save(os.path.join(linux_assets, 'icon.png'))
    print(" -> linux/assets/icon.png (256x256)")
    
    print("\nAll default project icons generated successfully!")

if __name__ == '__main__':
    main()
