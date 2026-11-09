#!/usr/bin/env python3
"""MiniFire Unity - character sprite generator.
Draws side-view cartoon soldiers (Mini-Militia-inspired, semi-realistic shading)
for every skin set. Output: Assets/Resources/Art/Chars/<skin>_<frame>.png
"""
import os, math
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "Assets", "Resources", "Art", "Chars")
W, H = 150, 190          # canvas
GROUND = 8               # ground padding at bottom

def clamp(v, a, b): return max(a, min(b, v))

def lerp(a, b, t): return int(a + (b - a) * t)

def shade(c, f):
    return (clamp(int(c[0]*f), 0, 255), clamp(int(c[1]*f), 0, 255), clamp(int(c[2]*f), 0, 255))

def mix(c1, c2, t):
    return (lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t))

def limb(draw, pts, width, color, outline=(28, 26, 32)):
    """Draw a tapered limb as thick line segments with outline."""
    n = len(pts)
    for i in range(n - 1):
        w0 = int(width * (1 - 0.15 * i / max(1, n - 2)))
        draw.line([pts[i], pts[i+1]], fill=outline, width=w0 + 6)
    for i in range(n - 1):
        w0 = int(width * (1 - 0.15 * i / max(1, n - 2)))
        draw.line([pts[i], pts[i+1]], fill=color, width=w0)
    for p in pts:
        r = width // 2 + 1
        draw.ellipse([p[0]-r, p[1]-r, p[0]+r, p[1]+r], fill=color)

def rot(px, py, cx, cy, deg):
    a = math.radians(deg)
    dx, dy = px - cx, py - cy
    return (cx + dx*math.cos(a) - dy*math.sin(a), cy + dx*math.sin(a) + dy*math.cos(a))

def seg(x, y, len_, deg, taper=1.0):
    a = math.radians(deg)
    return (x + len_*math.cos(a), y + len_*math.sin(a))

class Soldier:
    def __init__(self, pal):
        self.p = pal  # palette dict

    # ---------------- body helpers ----------------
    def draw_boot(self, d, x, y, dir_=1):
        c, o = self.p["boots"], (25, 23, 28)
        d.rounded_rectangle([x-11, y-9, x+11, y+6], 5, fill=c, outline=o, width=2)
        d.rounded_rectangle([x-11+dir_*2, y+1, x+13+dir_*4, y+6], 3, fill=shade(c, .7), outline=o, width=2)

    def draw_head(self, d, hx, hy, lean=0):
        p = self.p
        # head base (facing right) - chibi size, chin overlaps collar
        d.ellipse([hx-16, hy-17, hx+16, hy+17], fill=p["skin"], outline=(30, 26, 30), width=2)
        # jaw / chin shade
        d.pieslice([hx-16, hy-17, hx+16, hy+17], -50, 60, fill=shade(p["skin"], .88))
        # headset earcup (intentional tactical look)
        d.rounded_rectangle([hx-13, hy-4, hx-5, hy+8], 3, fill=(40,44,52), outline=(25,23,28), width=1)
        d.ellipse([hx-11, hy-1, hx-7, hy+3], fill=p["accent"])
        # eye + brow (small, semi-realistic)
        d.ellipse([hx+4, hy-5, hx+9, hy+0], fill=(255, 255, 255), outline=(30, 26, 30), width=1)
        d.ellipse([hx+6, hy-4, hx+9, hy-1], fill=(24, 22, 28))
        d.line([(hx+3, hy-8), (hx+11, hy-7)], fill=(45, 35, 32), width=2)
        # nose hint
        d.line([(hx+12, hy-2), (hx+14, hy+2)], fill=shade(p["skin"], .75), width=2)
        # mouth
        d.line([(hx+6, hy+9), (hx+11, hy+9)], fill=shade(p["skin"], .6), width=2)

    def draw_helmet(self, d, hx, hy, style):
        p = self.p
        o = (25, 23, 28)
        c, hi = p["helmet"], p["helmet_hi"]
        if style == "standard":
            d.pieslice([hx-17, hy-23, hx+17, hy+9], 180, 360, fill=c, outline=o, width=2)
            d.pieslice([hx-17, hy-23, hx+17, hy+9], 200, 340, fill=hi)
            d.line([(hx-14, hy-6), (hx-12, hy+4)], fill=shade(c,.7), width=3)
            d.line([(hx+14, hy-6), (hx+12, hy+4)], fill=shade(c,.7), width=3)
        elif style == "visor":
            d.pieslice([hx-17, hy-23, hx+17, hy+9], 180, 360, fill=c, outline=o, width=2)
            d.pieslice([hx-17, hy-23, hx+17, hy+9], 205, 335, fill=hi)
            d.rounded_rectangle([hx+1, hy-8, hx+17, hy+4], 4, fill=p["accent"], outline=o, width=2)
            d.line([(hx+3, hy-6), (hx+8, hy-6)], fill=(255,255,255), width=2)
        elif style == "cap":
            d.pieslice([hx-14, hy-18, hx+15, hy+2], 180, 360, fill=c, outline=o, width=2)
            d.rectangle([hx-16, hy-2, hx+16, hy+2], fill=shade(c,.85), outline=o, width=1)
            d.rectangle([hx+10, hy-4, hx+24, hy+1], fill=shade(c,.75), outline=o, width=1)
        elif style == "gas":
            d.ellipse([hx-16, hy-18, hx+16, hy+13], fill=c, outline=o, width=2)
            d.ellipse([hx-10, hy-12, hx+13, hy+2], fill=(52, 58, 66), outline=o, width=2)
            d.ellipse([hx+1, hy-9, hx+11, hy+0], fill=p["accent"], outline=o, width=1)
            d.ellipse([hx-9, hy-9, hx+1, hy+0], fill=p["accent"], outline=o, width=1)
            d.rounded_rectangle([hx+8, hy+3, hx+18, hy+12], 3, fill=(70,72,76), outline=o, width=2)
        elif style == "beret":
            d.pieslice([hx-16, hy-17, hx+17, hy+5], 180, 375, fill=c, outline=o, width=2)
            d.ellipse([hx-18, hy-10, hx-8, hy-2], fill=shade(c,.85), outline=o, width=1)
            d.line([(hx-14, hy-14), (hx-10, hy-18)], fill=shade(c,.8), width=3)
        elif style == "hood":
            d.pieslice([hx-18, hy-21, hx+18, hy+11], 190, 380, fill=c, outline=o, width=2)
            d.polygon([(hx-14, hy+2), (hx-2, hy+16), (hx+10, hy+10), (hx+12, hy+2)], fill=shade(c,.8), outline=o, width=1)
        elif style == "bandana":
            d.arc([hx-15, hy-19, hx+15, hy+7], 180, 360, fill=c, width=8)
            d.line([(hx-13, hy-9), (hx-22, hy-4)], fill=shade(c,.8), width=5)
            d.line([(hx-13, hy-9), (hx-21, hy-12)], fill=shade(c,.8), width=5)
        elif style == "officer":
            d.pieslice([hx-16, hy-19, hx+16, hy+4], 185, 355, fill=c, outline=o, width=2)
            d.rectangle([hx-17, hy-4, hx+17, hy+1], fill=shade(c,.55), outline=o, width=1)
            d.ellipse([hx+6, hy-9, hx+12, hy-3], fill=p["accent"], outline=o, width=1)
            d.ellipse([hx-13, hy-12, hx-7, hy-6], fill=shade(c,1.25))

    def draw_jetpack(self, d, sx, sy, flame=0):
        p = self.p
        o = (25, 23, 28)
        c, hi = p["jetpack"], p["jetpack_hi"]
        d.rounded_rectangle([sx-14, sy-26, sx+8, sy+18], 7, fill=c, outline=o, width=2)
        d.rounded_rectangle([sx-12, sy-22, sx+6, sy-14], 3, fill=hi)
        d.rounded_rectangle([sx-12, sy-8, sx+6, sy+2], 3, fill=shade(c,.8))
        d.rounded_rectangle([sx-11, sy+14, sx+5, sy+26], 4, fill=shade(c,.7), outline=o, width=2)
        if flame > 0:
            f = flame
            for i, (fw, col) in enumerate([(10, (255, 120, 20)), (7, (255, 190, 40)), (4, (255, 245, 160))]):
                fh = int((18 + 26*f) - i*4)
                d.polygon([(sx-10+i*4, sy+27), (sx-2+i*4, sy+27), (sx-6+i*4, sy+27+fh)], fill=col)

    def draw_gun_arm(self, d, sx, sy, ang):
        """front arm pointing forward-down holding invisible gun; gun drawn separately in-game"""
        p = self.p
        hand = seg(sx, sy, 26, ang)
        limb(d, [(sx, sy), (hand[0], hand[1])], 11, p["shirt"])
        d.ellipse([hand[0]-6, hand[1]-6, hand[0]+6, hand[1]+6], fill=p["gloves"], outline=(25,23,28), width=2)

    # ---------------- frame ----------------
    def frame(self, pose):
        p = self.p
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        o = (25, 23, 28)
        cx = 78
        hip_y = H - 62 - GROUND
        lean, arm_ang = 0, 0
        legs = [(0, 8), (0, 8)]  # (thigh angle, knee angle) offsets per leg
        jet = 0
        if pose == "idle":
            legs = [(16, 8), (-16, -10)]
            lean = 2
            arm_ang = 10
        elif pose == "run0":
            legs = [(38, 10), (-30, 30)]; lean = 8; arm_ang = 6
        elif pose == "run1":
            legs = [(10, 55), (-8, 8)]; lean = 9; arm_ang = 4
        elif pose == "run2":
            legs = [(-30, 30), (38, 10)]; lean = 8; arm_ang = 6
        elif pose == "run3":
            legs = [(-8, 8), (10, 55)]; lean = 9; arm_ang = 4
        elif pose == "fly0":
            legs = [(52, 70), (18, 45)]; lean = -6; arm_ang = -8; jet = .6
        elif pose == "fly1":
            legs = [(46, 62), (24, 52)]; lean = -4; arm_ang = -6; jet = 1.0
        elif pose == "jump":
            legs = [(25, 40), (-18, 35)]; lean = 4
        elif pose == "hurt":
            legs = [(4, 6), (-4, -6)]; lean = -14; arm_ang = 30
        elif pose == "dead":
            return self.dead()
        elif pose == "crouch":
            legs = [(40, 60), (-40, -55)]; lean = 14; arm_ang = 10

        # ---- torso ----
        sx, sy = cx - 2, hip_y - 34  # shoulder pivot
        torso_top = (sx + lean, sy - 16)
        limb(d, [(cx, hip_y), ((cx+sx)/2 + lean*.5, (hip_y+sy)/2 - 4), (torso_top[0], torso_top[1]+2)], 24, p["shirt"])
        # vest
        vest = [(cx + lean*.3 - 12, hip_y - 8), (torso_top[0] - 9, torso_top[1] + 6),
                (torso_top[0] + 12, torso_top[1] + 6), (cx + lean*.3 + 13, hip_y - 10)]
        d.polygon(vest, fill=p["vest"], outline=o, width=2)
        d.polygon([vest[0], (vest[1][0]+4, vest[1][1]+6), (vest[2][0]-2, vest[2][1]+6), vest[3]], fill=shade(p["vest"], 1.15))
        # shoulder straps
        d.line([(torso_top[0]-6, torso_top[1]+7), (cx-8+lean*.3, hip_y-6)], fill=shade(p["vest"],1.25), width=4)
        d.line([(torso_top[0]+9, torso_top[1]+7), (cx+10+lean*.3, hip_y-6)], fill=shade(p["vest"],1.25), width=4)
        # pouches
        for i in range(2):
            d.rounded_rectangle([cx + lean*.3 - 8 + i*11, hip_y - 16, cx + lean*.3 + i*11, hip_y - 8], 2,
                                fill=shade(p["vest"], .75), outline=o, width=1)
        # belt
        d.rectangle([cx-11, hip_y-6, cx+12, hip_y-1], fill=shade(p["pants"], .6), outline=o, width=1)
        d.rectangle([cx-2, hip_y-7, cx+4, hip_y], fill=(200, 170, 70), outline=o, width=1)

        # ---- jetpack behind ----
        self.draw_jetpack(d, sx - 16, sy + 12, jet)

        # ---- legs ----
        for i, (ta, ka) in enumerate(legs):
            back = (i == 0)
            col = shade(p["pants"], .8 if back else 1.0)
            knee = seg(cx, hip_y, 26, 90 + ta)
            foot = seg(knee[0], knee[1], 26, 90 + ta + ka)
            limb(d, [(cx, hip_y), knee, foot], 13 if back else 15, col)
            self.draw_boot(d, foot[0], foot[1] + 4)

        # ---- head ----
        hx, hy = int(torso_top[0] + 5), int(torso_top[1] - 7)
        self.draw_head(d, hx, hy, lean)
        self.draw_helmet(d, hx, hy, p["helmet_style"])

        # ---- arms ----
        # back arm (bent, holding gun support)
        elbow = seg(sx, sy + 2, 16, 40 + lean)
        hand2 = seg(elbow[0], elbow[1], 16, -30 + lean)
        limb(d, [(sx, sy + 2), elbow, (hand2[0] + 14, hand2[1] - 2)], 10, shade(p["shirt"], .75))
        d.ellipse([hand2[0]+8, hand2[1]-6, hand2[0]+20, hand2[1]+6], fill=p["gloves"], outline=o, width=2)
        # front arm
        self.draw_gun_arm(d, sx + 4, sy + 8, arm_ang)

        # hurt flash
        if pose == "hurt":
            overlay = Image.new("RGBA", (W, H), (255, 60, 40, 70))
            img = Image.alpha_composite(img, overlay)
        return img

    def dead(self):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        p, o = self.p, (25, 23, 28)
        y = H - 26
        # body lying on back, head to left
        d.rounded_rectangle([24, y-16, 104, y+4], 10, fill=p["shirt"], outline=o, width=2)
        d.polygon([(30, y-14), (44, y-18), (46, y+2), (32, y+2)], fill=p["vest"], outline=o, width=1)
        for i, dx in enumerate([96, 78]):
            d.line([(dx, y), (dx+16, y+12)], fill=shade(p["pants"], .9 if i else .75), width=12)
            self.draw_boot(d, dx+20, y+16)
        d.ellipse([8, y-16, 34, y+8], fill=p["skin"], outline=o, width=2)
        d.arc([10, y-12, 32, y+6], 200, 340, fill=(30,26,30), width=3)  # closed eyes hint
        if p["helmet_style"] in ("standard", "visor", "officer"):
            d.ellipse([52, y-30, 88, y-6], fill=p["helmet"], outline=o, width=2)
        d.line([(40, y-8), (60, y-2)], fill=(150, 30, 30), width=3)
        return img

# ---------------- skins ----------------
def P(skin, helmet, helmet_hi, vest, shirt, pants, boots, gloves, jetpack, jetpack_hi, accent, style, rarity):
    return dict(skin=skin, helmet=helmet, helmet_hi=helmet_hi, vest=vest, shirt=shirt, pants=pants,
                boots=boots, gloves=gloves, jetpack=jetpack, jetpack_hi=jetpack_hi, accent=accent,
                helmet_style=style, rarity=rarity)

SKINS = {
    "recruit":     P((232,190,159),(74,84,74),(96,108,94),(72,84,68),(96,112,88),(64,72,60),(40,42,40),(60,64,60),(88,94,88),(108,116,104),(200,60,60),"standard","common"),
    "desert":     P((224,177,132),(196,168,116),(214,190,142),(168,140,92),(196,172,120),(150,128,86),(92,78,54),(168,148,104),(186,158,108),(230,150,60),(255,150,50),"standard","common"),
    "nightops":     P((198,158,124),(38,42,52),(54,60,72),(30,34,42),(44,50,60),(26,30,36),(22,24,28),(40,44,54),(58,64,76),(120,220,255),(120,220,255),"visor","common"),
    "arctic":     P((226,192,160),(222,228,234),(240,246,250),(160,178,192),(208,220,230),(178,192,204),(120,130,140),(210,220,230),(232,240,246),(90,160,255),(90,160,255),"standard","common"),
    "forest":     P((220,180,140),(64,92,58),(86,118,76),(52,80,48),(74,102,62),(48,72,44),(38,52,34),(60,88,52),(80,110,70),(140,220,90),(140,220,90),"hood","common"),
    "urban":     P((228,188,152),(120,124,130),(142,146,152),(96,100,108),(128,132,140),(88,92,100),(60,62,66),(110,114,120),(140,144,152),(255,170,60),(255,170,60),"cap","common"),
    "navy":     P((226,184,148),(34,52,78),(48,68,100),(28,44,66),(52,72,100),(30,46,68),(24,36,54),(44,62,92),(60,82,116),(90,180,255),(90,180,255),"beret","common"),
    "sunfire":     P((230,186,144),(240,150,50),(255,180,90),(220,120,40),(250,170,80),(210,110,45),(120,60,25),(240,160,70),(255,190,100),(255,230,120),(255,230,120),"cap","rare"),
    "toxic":     P((220,182,146),(90,180,60),(120,220,84),(60,130,44),(96,180,70),(54,120,40),(36,80,28),(84,170,60),(110,200,80),(180,255,40),(180,255,40),"gas","rare"),
    "crimson":     P((228,186,150),(150,36,44),(186,54,62),(110,26,34),(170,44,54),(100,22,30),(60,14,20),(140,36,44),(176,52,60),(255,80,90),(255,80,90),"visor","rare"),
    "emerald":     P((222,182,146),(24,120,84),(40,160,110),(18,96,66),(34,140,96),(16,88,60),(12,64,44),(30,128,90),(44,152,104),(60,255,180),(60,255,180),"standard","rare"),
    "steel":     P((226,184,148),(130,138,150),(158,166,180),(96,104,118),(132,140,154),(88,96,110),(58,64,74),(122,130,144),(150,158,172),(220,230,255),(220,230,255),"officer","rare"),
    "bloodmoon":     P((230,188,152),(60,20,28),(84,32,40),(96,18,26),(120,26,36),(70,14,20),(40,10,14),(90,20,28),(110,28,38),(255,40,60),(255,40,60),"bandana","epic"),
    "cyber":     P((215,178,150),(30,36,54),(50,60,90),(22,28,46),(40,50,80),(20,26,42),(16,20,34),(34,44,72),(52,64,100),(0,240,255),(0,240,255),"visor","epic"),
    "goldlegion":     P((232,192,156),(190,150,50),(220,180,70),(160,120,36),(200,160,56),(140,104,30),(90,66,20),(190,150,60),(220,182,80),(255,220,120),(255,220,120),"officer","epic"),
    "void":     P((228,186,150),(24,20,36),(40,34,60),(16,14,28),(30,26,48),(14,12,24),(10,8,18),(26,22,44),(38,32,66),(150,90,255),(150,90,255),"hood","epic"),
    "lavafist":     P((226,182,144),(120,44,26),(160,66,34),(90,30,18),(130,52,26),(80,26,16),(50,16,10),(120,48,24),(150,62,30),(255,120,30),(255,120,30),"bandana","epic"),
    "frostbite":     P((224,186,156),(150,200,230),(190,230,250),(110,160,200),(170,214,244),(100,148,190),(70,110,150),(160,208,240),(200,236,255),(160,230,255),(160,230,255),"gas","epic"),
    "rose":     P((230,190,158),(210,120,150),(240,160,190),(180,90,125),(225,140,170),(160,80,112),(110,55,80),(210,130,165),(240,165,195),(255,140,200),(255,140,200),"beret","rare"),
    "mint":     P((226,186,152),(120,200,180),(160,235,215),(84,170,150),(140,220,198),(76,156,138),(54,110,96),(130,210,190),(170,244,226),(120,255,220),(120,255,220),"cap","rare"),
    "sandstorm":     P((224,178,134),(170,140,96),(198,168,120),(140,112,74),(180,148,102),(126,100,66),(78,62,42),(160,132,90),(188,156,110),(255,200,90),(255,200,90),"hood","common"),
    "jungle":     P((222,180,142),(52,110,60),(76,140,84),(40,92,50),(64,120,72),(36,84,46),(28,64,34),(56,118,64),(80,146,88),(255,230,80),(255,230,80),"bandana","common"),
    "midnight":     P((226,184,148),(20,26,46),(34,44,72),(16,20,38),(28,36,60),(14,18,34),(10,13,26),(24,32,54),(40,50,84),(130,110,255),(130,110,255),"beret","rare"),
    "polarbear":     P((228,190,158),(236,240,244),(255,255,255),(190,198,206),(240,246,250),(206,214,222),(150,158,166),(232,238,244),(250,252,254),(120,200,255),(120,200,255),"standard","common"),
    "copperhead":     P((222,178,138),(160,90,50),(196,120,70),(130,70,38),(170,100,58),(118,62,32),(80,42,22),(150,84,46),(186,112,64),(255,150,60),(255,150,60),"gas","rare"),
    "phantom":     P((224,182,146),(44,44,58),(62,62,80),(32,32,44),(52,52,68),(28,28,40),(20,20,30),(40,40,56),(58,58,76),(200,200,255),(200,200,255),"hood","legendary"),
    "dragonfire":     P((228,188,152),(180,50,30),(220,80,45),(150,36,20),(200,64,36),(130,30,18),(80,18,10),(170,52,30),(210,72,40),(255,90,20),(255,90,20),"visor","legendary"),
    "whitegold":     P((234,196,162),(240,236,220),(255,252,240),(220,210,180),(245,240,225),(200,192,166),(150,144,124),(235,228,205),(250,246,232),(255,215,0),(255,215,0),"officer","legendary"),
}

FRAMES = ["idle", "run0", "run1", "run2", "run3", "fly0", "fly1", "jump", "crouch", "hurt", "dead"]

def main():
    os.makedirs(OUT, exist_ok=True)
    for name, pal in SKINS.items():
        s = Soldier(pal)
        for f in FRAMES:
            img = s.frame(f)
            img.save(os.path.join(OUT, f"{name}_{f}.png"))
    # contact sheet preview
    sel = ["recruit", "nightops", "cyber", "dragonfire", "goldlegion", "toxic"]
    sheet = Image.new("RGBA", (len(sel) * (W + 10), H + 20), (40, 44, 52, 255))
    for i, name in enumerate(sel):
        s = Soldier(SKINS[name])
        sheet.paste(s.frame("idle"), (i * (W + 10) + 5, 10), s.frame("idle"))
    sheet.save(os.path.join(os.path.dirname(__file__), "preview_chars.png"))

if __name__ == "__main__":
    main()
