# Builds the five entrance posters (PNG + PDF, letter size at 300 dpi).
# Faces are die-cut stickers: transparent avatar, white border, soft shadow, slight tilt.
# Run from this folder: python3 make_posters.py
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 2550, 3300
INK, MUTED, ACCENT = "#2f3b45", "#6b7a86", "#ff6b8a"

def F(size, name):
    f = ImageFont.truetype("Nunito-Black.ttf", size)
    try: f.set_variation_by_name(name)
    except Exception: pass
    return f

head, mid, sm, tm = F(150, "Black"), F(84, "Bold"), F(60, "SemiBold"), F(44, "ExtraBold")

def sticker(path, size, angle, border=26, blur=18, offset=(10, 18)):
    face = Image.open(path).convert("RGBA")
    face = face.crop(face.getbbox())
    face.thumbnail((size, size), Image.LANCZOS)
    pad = border + blur * 3
    canvas = Image.new("RGBA", (face.width + 2 * pad, face.height + 2 * pad), (0, 0, 0, 0))
    canvas.paste(face, (pad, pad), face)
    alpha = canvas.split()[3]
    # grow the silhouette outward for the white die-cut edge, then soften it slightly
    cut = alpha.filter(ImageFilter.GaussianBlur(border / 2)).point(lambda v: 255 if v > 6 else 0)
    cut = cut.filter(ImageFilter.GaussianBlur(1.5))
    shadow = Image.new("RGBA", canvas.size, (20, 24, 60, 0))
    shadow.putalpha(cut.point(lambda v: v * 0.32).filter(ImageFilter.GaussianBlur(blur)))
    out = Image.new("RGBA", (canvas.width + offset[0], canvas.height + offset[1]), (0, 0, 0, 0))
    out.paste(shadow, offset, shadow)
    white = Image.new("RGBA", canvas.size, (255, 255, 255, 255)); white.putalpha(cut)
    out.alpha_composite(white)
    out.alpha_composite(canvas)
    return out.rotate(angle, resample=Image.BICUBIC, expand=True)

logo = Image.open("../media/pop-logo-header.png").convert("RGBA")
LW = 500; logo = logo.resize((LW, round(logo.height * LW / logo.width)), Image.LANCZOS)

qr = Image.open("qr.png").convert("RGB"); Q = 1300; qr = qr.resize((Q, Q), Image.NEAREST); qx, qy = (W - Q) // 2, 1060

S = 520
angles = [-9, 7, -5, 10, -7, 6, -11, 8, 5, -6]
faces = [f"stickers/face{i+1}.png" for i in range(10)]
# (center x, center y, behind the QR card?, size)
# side stickers are smaller so they stay clear of the QR's white margin
spots = [(330, 360, False, S), (265, 1330, False, 430), (2285, 1250, False, 430), (265, 2280, False, 430), (2285, 2430, False, 430),
         (qx + Q - 40, qy + 80, True, S), (640, 3020, False, S), (1910, 3020, False, S)]

for n, verb in enumerate(["Network", "Laugh", "Sing", "Trade stories", "Make a friend"], 1):
    im = Image.new("RGBA", (W, H), "white"); d = ImageDraw.Draw(im)

    def place(i, x, y, size):
        k = (i + n) % 10
        st = sticker(faces[k], size, angles[(i + 2 * n) % 10])
        im.alpha_composite(st, (int(x - st.width / 2), int(y - st.height / 2)))

    for i, (x, y, behind, size) in enumerate(spots):
        if behind: place(i, x, y, size)
    d.rounded_rectangle([qx - 60, qy - 60, qx + Q + 60, qy + Q + 60], radius=70, fill="white", outline="#e6ebef", width=8)
    im.paste(qr, (qx, qy))
    for i, (x, y, behind, size) in enumerate(spots):
        if not behind: place(i, x, y, size)

    # logo top right, with the trademark mark as in the app
    lx, ly = W - LW - 110, 70
    im.alpha_composite(logo, (lx, ly))
    d.text((lx + LW + 6, ly + 40), "™", font=tm, fill=MUTED)

    rest = " at a booth."; vw = d.textlength(verb, font=head); rw = d.textlength(rest, font=head)
    x0, y0 = (W - vw - rw) / 2, 620
    d.text((x0, y0), verb, font=head, fill=INK); d.text((x0 + vw, y0), rest, font=head, fill=INK)
    d.rounded_rectangle([x0 - 10, y0 + 200, x0 + vw + 10, y0 + 224], radius=12, fill=ACCENT)

    def ctext(y, t, f, fill):
        w = d.textlength(t, font=f); d.text(((W - w) / 2, y), t, font=f, fill=fill)
    ctext(2520, "Scan to enter the mix.", mid, INK); ctext(2640, "htoyll8.github.io/Pop", sm, MUTED)

    slug = verb.lower().replace(" ", "-"); rgb = im.convert("RGB")
    rgb.save(f"pop-poster-{n}-{slug}.png", dpi=(300, 300)); rgb.save(f"pop-poster-{n}-{slug}.pdf", "PDF", resolution=300.0)
print("5 posters written")
