# "Make a friend at a booth." wall poster, 18 x 24 in at 300 dpi.
# Layout follows Tyler's Canva draft (Image Layout with Text Space.png), widened to 3:4.
# Run from this folder: python3 make_friend_18x24.py
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 5400, 7200
INK, MUTED, ACCENT = "#2f3b45", "#6b7a86", "#ff6b8a"

def F(size, name):
    f = ImageFont.truetype("Nunito-Black.ttf", size)
    try: f.set_variation_by_name(name)
    except Exception: pass
    return f

def load(name, width, angle=0):
    im = Image.open(f"sticker-pack/{name}.png").convert("RGBA")
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    return im.rotate(angle, resample=Image.BICUBIC, expand=True) if angle else im

im = Image.new("RGBA", (W, H), "white"); d = ImageDraw.Draw(im)

def put(st, cx, cy):
    im.alpha_composite(st, (int(cx - st.width / 2), int(cy - st.height / 2)))

# (sticker, center x, center y as fractions of the page, width as a fraction, tilt in degrees)
behind = [("face-9", 0.06, 0.35, 0.36, -10), ("excited-1", 0.93, 0.52, 0.30, 9)]
front = [("excited-5", 0.80, 0.10, 0.30, 8), ("excited-7", 0.17, 0.885, 0.36, -7), ("excited-8", 0.79, 0.875, 0.30, 6)]

for name, x, y, w, a in behind:
    put(load(name, int(w * W), a), x * W, y * H)

qr = load("qr-sticker", int(0.60 * W))
qcx, qcy = 0.5 * W, 0.52 * H
put(qr, qcx, qcy)

for name, x, y, w, a in front:
    put(load(name, int(w * W), a), x * W, y * H)

put(load("pop-logo", int(0.24 * W), -4), 0.17 * W, 0.085 * H)

def ctext(y, t, f, fill):
    w = d.textlength(t, font=f); d.text(((W - w) / 2, y), t, font=f, fill=fill)
    return (W - w) / 2

# headline as a search bar (modeled on the bar in Tyler's screenshot): "Make a friend" is typed,
# " at a booth." is the gray autocomplete suggestion. "Pop Mode" stands in for the bar's mode button.
def SF(size, weight):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    try: f.set_variation_by_axes([100, 28, 400, weight])  # width, optical size, grade, weight
    except Exception: pass
    return f
BAR_INK, ICON = "#1f1f1f", "#444746"
typed, ghost = "Make a friend", " at a booth."
bw, bh = int(0.90 * W), 470
bx0, by0 = (W - bw) // 2, 1640
cy = by0 + bh / 2
shadow = Image.new("L", (W, H), 0)
ImageDraw.Draw(shadow).rounded_rectangle([bx0, by0 + 22, bx0 + bw, by0 + bh + 22], radius=bh // 2, fill=60)
shade = Image.new("RGBA", (W, H), (20, 24, 60, 0)); shade.putalpha(shadow.filter(ImageFilter.GaussianBlur(36)))
im.alpha_composite(shade); d = ImageDraw.Draw(im)
d.rounded_rectangle([bx0, by0, bx0 + bw, by0 + bh], radius=bh // 2, fill="white", outline="#dadce0", width=9)
# plus
px = bx0 + 230; L = 70
d.line([px - L, cy, px + L, cy], fill=BAR_INK, width=22); d.line([px, cy - L, px, cy + L], fill=BAR_INK, width=22)
# mode pill on the right
pill_t = "Pop Mode"; pf = SF(125, 510); ptw = d.textlength(pill_t, font=pf)
pw, ph = 230 + ptw + 90, 300
pr = bx0 + bw - 85; pl = pr - pw
d.rounded_rectangle([pl, cy - ph / 2, pr, cy + ph / 2], radius=ph // 2, fill="#f0f2f5")
mx, my, r = pl + 135, cy - 8, 42
d.ellipse([mx - r, my - r, mx + r, my + r], outline=BAR_INK, width=17)
d.line([mx + r * 0.7, my + r * 0.7, mx + r * 1.6, my + r * 1.6], fill=BAR_INK, width=19)
sx, sy, k = mx + 62, my - 58, 26   # small sparkle
d.polygon([(sx, sy - k), (sx + k * 0.3, sy - k * 0.3), (sx + k, sy), (sx + k * 0.3, sy + k * 0.3), (sx, sy + k), (sx - k * 0.3, sy + k * 0.3), (sx - k, sy), (sx - k * 0.3, sy - k * 0.3)], fill=BAR_INK)
d.text((pl + 230, cy - 82), pill_t, font=pf, fill=BAR_INK)
# camera
cx = pl - 210; s2 = 72
d.rounded_rectangle([cx - s2, cy - s2, cx + s2, cy + s2], radius=34, outline=ICON, width=18)
d.ellipse([cx - 28, cy - 28, cx + 28, cy + 28], fill=ICON)
# microphone
mx2 = cx - 270
d.rounded_rectangle([mx2 - 30, cy - 85, mx2 + 30, cy + 25], radius=30, fill=ICON)
d.arc([mx2 - 62, cy - 50, mx2 + 62, cy + 62], start=0, end=180, fill=ICON, width=16)
d.line([mx2, cy + 62, mx2, cy + 98], fill=ICON, width=16)

# typed text, cursor, ghost suggestion: largest size that fits between the plus and the mic
tx = bx0 + 400; room = (mx2 - 140) - tx
size = 230
while size > 120:
    head = SF(size, 480)
    if d.textlength(typed + ghost, font=head) + 40 <= room: break
    size -= 5
asc = head.getbbox("Mk")[1]; hgt = head.getbbox("Mk")[3] - asc
ty = cy - hgt / 2 - asc
d.text((tx, ty), typed, font=head, fill=BAR_INK)
cur = tx + d.textlength(typed, font=head) + 14
d.rounded_rectangle([cur, cy - size * 0.55, cur + 14, cy + size * 0.55], radius=7, fill=ACCENT)
d.text((cur + 26, ty), ghost, font=head, fill="#9aa0a6")

qr_bottom = qcy + qr.height / 2
ctext(qr_bottom - 20, "Scan to enter the mix.", F(170, "Bold"), INK)
ctext(qr_bottom + 210, "htoyll8.github.io/Pop", F(120, "SemiBold"), MUTED)

rgb = im.convert("RGB")
rgb.save("pop-make-a-friend-18x24.png", dpi=(300, 300))
rgb.save("pop-make-a-friend-18x24.pdf", "PDF", resolution=300.0)
print("written", rgb.size)
