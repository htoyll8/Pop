# "Make a friend at a booth." wall poster, 18 x 24 in at 300 dpi.
# Layout follows Tyler's Canva draft (Image Layout with Text Space.png), widened to 3:4.
# Run from this folder: python3 make_friend_18x24.py
from PIL import Image, ImageDraw, ImageFont

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

qr = load("qr-sticker", int(0.66 * W))
qcx, qcy = 0.5 * W, 0.50 * H
put(qr, qcx, qcy)

for name, x, y, w, a in front:
    put(load(name, int(w * W), a), x * W, y * H)

put(load("pop-logo", int(0.24 * W), -4), 0.17 * W, 0.085 * H)

def ctext(y, t, f, fill):
    w = d.textlength(t, font=f); d.text(((W - w) / 2, y), t, font=f, fill=fill)
    return (W - w) / 2

# headline in the gap between the logo row and the QR card, with the accent under "Make a friend"
head = F(330, "Black"); verb, rest = "Make a friend", " at a booth."
vw = d.textlength(verb, font=head); x0 = (W - vw - d.textlength(rest, font=head)) / 2; y0 = 1330
d.text((x0, y0), verb, font=head, fill=INK); d.text((x0 + vw, y0), rest, font=head, fill=INK)
d.rounded_rectangle([x0 - 20, y0 + 440, x0 + vw + 20, y0 + 490], radius=25, fill=ACCENT)

qr_bottom = qcy + qr.height / 2
ctext(qr_bottom - 20, "Scan to enter the mix.", F(170, "Bold"), INK)
ctext(qr_bottom + 210, "htoyll8.github.io/Pop", F(120, "SemiBold"), MUTED)

rgb = im.convert("RGB")
rgb.save("pop-make-a-friend-18x24.png", dpi=(300, 300))
rgb.save("pop-make-a-friend-18x24.pdf", "PDF", resolution=300.0)
print("written", rgb.size)
