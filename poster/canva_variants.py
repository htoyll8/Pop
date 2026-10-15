# Search-bar variants of Tyler's white Canva layout.
# For each headline: render the bar (same style as make_friend_18x24.py), save it to sticker-pack/,
# swap it into the Canva export in place of the "Make a friend" bar, move the pigtails sticker down,
# and add the scan line. Run from this folder: python3 canva_variants.py
from PIL import Image, ImageDraw, ImageFont, ImageChops

SRC = "/Users/ritaholloway/Downloads/Image Layout with Text Space (2).png"
HEADLINES = {"network": "Network", "vibe": "Vibe"}

def bar_png(typed):
    s = open("make_friend_18x24.py").read()
    g = {}; exec(s[:s.index("im = Image.new")], g)
    g["im"] = Image.new("RGBA", (g["W"], g["H"]), (0, 0, 0, 0)); g["d"] = ImageDraw.Draw(g["im"])
    block = s[s.index("# headline as a search bar"):s.index("qr_bottom = ")]
    block = block.replace('typed, ghost = "Make a friend", " at a booth."', f'typed, ghost = {typed!r}, " at a booth."')
    exec(block, g)
    return g["im"].crop(g["im"].getbbox())

def F(size, name):
    f = ImageFont.truetype("Nunito-Black.ttf", size); f.set_variation_by_name(name); return f

base = Image.open(SRC).convert("RGB"); W, H = base.size
white = lambda im: Image.new("RGB", im.size, "white")
# where the old bar (with its shadow) sits
R = (560, 1120, 3600, 1640)
reg = base.crop(R)
bx0, by0, bx1, by1 = ImageChops.difference(reg, white(reg)).getbbox()
bx0, by0, bx1, by1 = bx0 + R[0], by0 + R[1], bx1 + R[0], by1 + R[1]

for slug, typed in HEADLINES.items():
    bar = bar_png(typed); bar.save(f"sticker-pack/search-bar-{slug}.png", dpi=(300, 300))
    im = base.copy()
    im.paste((255, 255, 255), (bx0 - 10, by0 - 10, bx1 + 10, by1 + 10))
    b = bar.resize((bx1 - bx0, round(bar.height * (bx1 - bx0) / bar.width)), Image.LANCZOS)
    im.paste(b, (bx0, by0), b)
    # pigtails sticker down 100 px (Tyler's tweak)
    P = (0, 4560, 1700, H); crop = im.crop(P)
    mask = ImageChops.difference(crop, white(crop)).convert("L").point(lambda v: 255 if v > 0 else 0)
    im.paste((255, 255, 255), P); im.paste(crop, (0, P[1] + 100), mask)
    d = ImageDraw.Draw(im)
    def ctext(y, t, f, fill):
        w = d.textlength(t, font=f); d.text(((W - w) / 2, y), t, font=f, fill=fill)
    ctext(4680, "Scan to find your match.", F(150, "Bold"), "#1f1f1f")
    ctext(4890, "htoyll8.github.io/Pop", F(100, "SemiBold"), "#6b7a86")
    im.save(f"pop-{slug}-canva.png", dpi=(300, 300))
    print("wrote", slug)
