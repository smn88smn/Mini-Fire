#!/usr/bin/env python3
"""MiniFire Unity - world art generator: guns, bullets, effects, maps, UI icons."""
import os, math
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "Resources")
ART = os.path.join(ROOT, "Art")
MAPS = os.path.join(ROOT, "Maps")
os.makedirs(ART, exist_ok=True); os.makedirs(MAPS, exist_ok=True)

def clamp(v,a,b): return max(a,min(b,v))
def shade(c,f): return (clamp(int(c[0]*f),0,255),clamp(int(c[1]*f),0,255),clamp(int(c[2]*f),0,255))
def mix(a,b,t): return (int(a[0]+(b[0]-a[0])*t),int(a[1]+(b[1]-a[1])*t),int(a[2]+(b[2]-a[2])*t))

def save(img, folder, name):
    p = os.path.join(ROOT, folder, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)

# ------------------------------------------------ guns (side view, facing right)
def gun(kind):
    L = {"pistol": 46, "smg": 66, "rifle": 88, "shotgun": 78, "sniper": 108, "rpg": 96, "minigun": 90}.get(kind, 70)
    H = 30
    img = Image.new("RGBA", (L, H), (0,0,0,0))
    d = ImageDraw.Draw(img)
    o = (24,22,26)
    metal, metal2, wood = (72,76,84), (96,102,112), (122,84,52)
    if kind == "pistol":
        d.rounded_rectangle([8,10,40,20], 3, fill=metal, outline=o, width=2)          # slide
        d.rounded_rectangle([8,8,40,13], 2, fill=metal2)                               # slide top
        d.polygon([(12,19),(24,19),(20,29),(8,29)], fill=metal2, outline=o)           # grip
        d.rectangle([38,13,44,17], fill=metal)                                        # muzzle
    elif kind == "smg":
        d.rounded_rectangle([6,10,58,20], 3, fill=metal, outline=o, width=2)
        d.rounded_rectangle([6,8,58,13], 2, fill=metal2)
        d.polygon([(10,19),(22,19),(18,30),(6,30)], fill=metal2, outline=o)           # grip
        d.rectangle([24,20,32,30], fill=metal2, outline=o)                            # mag
        d.rectangle([58,12,66,15], fill=(60,62,68))                                   # suppressor
        d.rectangle([16,6,20,10], fill=metal2)                                        # sight
    elif kind == "rifle":
        d.rounded_rectangle([10,10,74,20], 3, fill=metal, outline=o, width=2)
        d.rounded_rectangle([10,8,74,13], 2, fill=metal2)
        d.polygon([(14,19),(26,19),(22,30),(10,30)], fill=metal2, outline=o)          # grip
        d.rectangle([30,20,38,32], fill=metal2, outline=o)                            # mag
        d.rectangle([74,12,84,15], fill=(60,62,68))                                   # barrel
        d.rounded_rectangle([20,4,34,9], 2, fill=(50,52,58), outline=o)               # scope rail
        d.polygon([(66,19),(80,19),(78,28),(66,28)], fill=wood, outline=o)            # stock
    elif kind == "shotgun":
        d.rounded_rectangle([8,9,66,17], 3, fill=metal, outline=o, width=2)
        d.rounded_rectangle([8,15,66,21], 3, fill=(64,68,76), outline=o, width=2)     # tube
        d.polygon([(12,20),(24,20),(20,30),(8,30)], fill=wood, outline=o)             # grip
        d.polygon([(60,8),(84,10),(84,24),(60,26)], fill=wood, outline=o)             # stock
        d.rectangle([40,5,46,9], fill=metal2)
    elif kind == "sniper":
        d.rounded_rectangle([12,11,80,19], 3, fill=metal, outline=o, width=2)
        d.rounded_rectangle([12,9,80,13], 2, fill=metal2)
        d.rectangle([30,20,36,30], fill=metal2, outline=o)
        d.polygon([(16,19),(28,19),(24,30),(12,30)], fill=metal2, outline=o)
        d.rectangle([80,13,104,15], fill=(58,60,66))
        d.rounded_rectangle([26,1,50,7], 3, fill=(40,44,50), outline=o)               # scope
        d.ellipse([26,0,32,6], fill=(140,200,255))
        d.polygon([(70,19),(86,21),(86,27),(70,27)], fill=metal2, outline=o)          # stock
        d.rectangle([36,7,40,11], fill=metal2); d.rectangle([46,7,50,11], fill=metal2)
    elif kind == "rpg":
        d.rounded_rectangle([6,10,80,20], 4, fill=(90,96,70), outline=o, width=2)
        d.polygon([(2,9),(12,9),(12,21),(2,25)], fill=(90,96,70), outline=o)          # flare
        d.polygon([(16,20),(28,20),(24,30),(12,30)], fill=(70,74,58), outline=o)
        d.rounded_rectangle([40,2,54,10], 3, fill=(70,74,58), outline=o)              # sight
        d.rectangle([80,13,92,17], fill=(70,74,58))
        d.ellipse([30,6,44,24], fill=(188,60,50), outline=o, width=2)                 # warhead band
    elif kind == "minigun":
        d.rounded_rectangle([8,8,60,24], 4, fill=metal, outline=o, width=2)
        for i in range(3):
            d.rectangle([60,9+i*5,92,11+i*5], fill=(64,66,72), outline=o)
        d.polygon([(14,24),(26,24),(22,32),(10,32)], fill=metal2, outline=o)
        d.rectangle([24,24,34,34], fill=metal2, outline=o)
    return img

for k in ["pistol","smg","rifle","shotgun","sniper","rpg","minigun"]:
    save(gun(k), "Art", f"gun_{k}.png")
    # large icon version
    g = gun(k); save(g.resize((g.width*2, g.height*2), Image.NEAREST), "Art", f"gunicon_{k}.png")

# ------------------------------------------------ bullets & effects
def bullet(kind):
    if kind == "fire":
        img = Image.new("RGBA",(28,12),(0,0,0,0)); d=ImageDraw.Draw(img)
        d.ellipse([2,2,12,10], fill=(255,240,140)); d.ellipse([4,3,9,9], fill=(255,255,220))
        d.polygon([(10,6),(26,1),(26,11)], fill=(255,150,30))
        return img
    img = Image.new("RGBA",(22,8),(0,0,0,0)); d=ImageDraw.Draw(img)
    col = {"pistol":(255,235,120),"smg":(255,210,80),"rifle":(255,190,60),"shotgun":(255,170,50),
           "sniper":(180,230,255),"rpg":(255,120,40),"minigun":(255,200,70)}.get(kind,(255,220,90))
    d.rounded_rectangle([0,1,14,7],3, fill=col)
    d.polygon([(12,0),(22,4),(12,8)], fill=shade(col,.8))
    return img
for k in ["pistol","smg","rifle","shotgun","sniper","rpg","minigun","fire"]:
    save(bullet(k), "Art", f"bullet_{k}.png")

def effect(name):
    if name == "muzzle":
        img = Image.new("RGBA",(48,48),(0,0,0,0)); d=ImageDraw.Draw(img)
        for r,c in [(22,(255,200,60,220)),(15,(255,235,150,230)),(8,(255,255,230,255))]:
            d.polygon([(24,24-r),(24+r*0.9,24),(24,24+r),(24-r*0.6,24)], fill=c)
        return img
    if name == "explosion":
        img = Image.new("RGBA",(160,160),(0,0,0,0)); d=ImageDraw.Draw(img)
        for r,c,a in [(70,(255,120,20),255),(52,(255,180,40),255),(34,(255,230,120),255),(18,(255,255,240),255)]:
            pts=[]
            import random as _r; _r.seed(r)
            for i in range(14):
                ang=i/14*2*math.pi; rr=r*(0.75+0.35*_r.random())
                pts.append((80+rr*math.cos(ang),80+rr*math.sin(ang)))
            d.polygon(pts, fill=c+(a,))
        return img
    if name == "hit":
        img = Image.new("RGBA",(40,40),(0,0,0,0)); d=ImageDraw.Draw(img)
        for i in range(8):
            a=i/8*2*math.pi
            d.line([(20,20),(20+16*math.cos(a),20+16*math.sin(a))], fill=(255,240,180), width=3)
        d.ellipse([12,12,28,28], fill=(255,255,255))
        return img
    if name == "burn":
        img = Image.new("RGBA",(36,48),(0,0,0,0)); d=ImageDraw.Draw(img)
        d.polygon([(6,46),(12,26),(18,34),(18,14),(26,30),(30,46)], fill=(255,120,20))
        d.polygon([(12,46),(16,32),(22,40),(22,22),(27,44)], fill=(255,200,50))
        return img
    if name == "blood":
        img = Image.new("RGBA",(36,36),(0,0,0,0)); d=ImageDraw.Draw(img)
        for i,(x,y,r) in enumerate([(10,20,6),(18,12,5),(24,22,4),(16,26,3)]):
            d.ellipse([x-r,y-r,x+r,y+r], fill=(200,30,30))
        return img
    if name == "spawn":
        img = Image.new("RGBA",(80,80),(0,0,0,0)); d=ImageDraw.Draw(img)
        d.ellipse([10,10,70,70], outline=(120,220,255), width=4)
        d.ellipse([24,24,56,56], outline=(180,240,255), width=3)
        return img
for e in ["muzzle","explosion","hit","burn","blood","spawn"]:
    save(effect(e), "Art", f"fx_{e}.png")

# ------------------------------------------------ maps (backgrounds + tiles)
def sky_gradient(w,h,top,bot):
    img = Image.new("RGB",(w,h))
    for y in range(h):
        t=y/h; img.paste(mix(top,bot,t),(0,y,w,y+1))
    return img.convert("RGBA")

def mountains(w,h,color,seed,jag=40,base=0.75):
    import random as r; r.seed(seed)
    img = Image.new("RGBA",(w,h),(0,0,0,0)); d=ImageDraw.Draw(img)
    pts=[(0,h)]
    x=0; y=h*base
    while x<w:
        pts.append((x,y)); x+=r.randint(40,90); y=h*base - r.uniform(0,h*0.22)
        pts.append((x,y)); x+=r.randint(30,70); y=h*base - r.uniform(0.1,0.16)*h
    pts += [(w,h)]
    d.polygon(pts, fill=color)
    return img

def make_map_theme(name, sky_top, sky_bot, far, near, ground_col, plat_col):
    W,H = 1024, 576
    img = sky_gradient(W,H,sky_top,sky_bot)
    far_m = mountains(W,H,far,1,base=0.62)
    near_m = mountains(W,H,near,2,base=0.78)
    img.alpha_composite(far_m,(0,0)); img.alpha_composite(near_m,(0,0))
    save(img, "Maps", f"bg_{name}.png")
    # ground tile
    g = Image.new("RGBA",(256,128),(0,0,0,0)); d=ImageDraw.Draw(g)
    d.rectangle([0,0,256,128], fill=ground_col)
    for i in range(24):
        import random as r; r.seed(i+hash(name)%100)
        x,y=r.randint(0,248),r.randint(0,120)
        d.ellipse([x,y,x+r.randint(3,9),y+r.randint(2,6)], fill=shade(ground_col, r.uniform(0.8,1.15)))
    d.rectangle([0,0,256,8], fill=shade(ground_col,1.25))
    save(g, "Maps", f"tile_ground_{name}.png")
    # platform tile
    p = Image.new("RGBA",(256,48),(0,0,0,0)); d=ImageDraw.Draw(p)
    d.rounded_rectangle([0,0,256,44],6, fill=plat_col)
    d.rounded_rectangle([0,0,256,12],6, fill=shade(plat_col,1.3))
    d.rectangle([10,26,40,36], fill=shade(plat_col,.75))
    d.rectangle([120,26,160,36], fill=shade(plat_col,.75))
    d.rectangle([210,26,240,36], fill=shade(plat_col,.75))
    save(p, "Maps", f"tile_plat_{name}.png")

make_map_theme("outpost", (110,150,205),(205,225,240),(140,155,175),(95,110,128),(88,96,74),(110,118,92))
make_map_theme("bunker", (60,66,90),(120,110,130),(80,80,100),(55,58,74),(70,70,80),(88,90,100))
make_map_theme("canyon", (250,180,110),(255,225,170),(215,150,95),(180,120,75),(150,95,60),(170,115,72))

# ------------------------------------------------ UI icons
def icon(name):
    d_ = ImageDraw.Draw
    if name == "gem":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        pts=[(32,4),(56,24),(44,60),(20,60),(8,24)]
        d.polygon(pts, fill=(60,200,255), outline=(20,120,180), width=3)
        d.polygon([(32,4),(56,24),(32,20),(8,24)], fill=(140,240,255))
        d.polygon([(32,20),(44,60),(32,60)], fill=(30,160,220))
        return img
    if name == "coin":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        d.ellipse([4,4,60,60], fill=(255,200,60), outline=(180,130,20), width=3)
        d.ellipse([12,12,52,52], outline=(255,230,140), width=3)
        d.text((22,18),"$",(0,0,0,0))
        d.text((22,16),"$",fill=(180,130,20))
        return img
    if name == "spin":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        cols=[(255,80,80),(255,200,60),(120,220,90),(80,170,255),(190,110,255),(255,140,200)]
        for i,c in enumerate(cols):
            a0=i*60; a1=a0+60
            d.pieslice([4,4,60,60],a0,a1,fill=c)
        d.ellipse([22,22,42,42], fill=(40,44,52), outline=(25,23,28), width=2)
        return img
    if name == "play":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        d.polygon([(18,10),(54,32),(18,54)], fill=(110,220,110))
        return img
    if name == "cart":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        d.polygon([(8,14),(16,14),(24,44),(50,44),(56,20),(20,20)], fill=(240,240,245), outline=(60,60,70))
        d.ellipse([20,46,30,56], fill=(60,60,70)); d.ellipse([44,46,54,56], fill=(60,60,70))
        return img
    if name == "online":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        d.ellipse([8,10,56,58], outline=(110,220,255), width=4)
        d.arc([14,40,26,52],180,360,fill=(110,220,255),width=4)
        d.line([(20,46),(20,30)],fill=(110,220,255),width=4)
        d.line([(26,46),(26,26)],fill=(110,220,255),width=4)
        return img
    if name == "login":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        d.rounded_rectangle([6,10,58,54],6, outline=(255,255,255), width=4)
        d.ellipse([20,16,32,28], fill=(255,255,255))
        d.pieslice([14,30,38,54],180,360,fill=(255,255,255))
        d.ellipse([38,26,56,44], fill=(255,255,255))
        d.polygon([(50,34),(44,28),(44,31),(38,31),(38,37),(44,37),(44,40)], fill=(60,130,240))
        return img
    if name == "back":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        d.polygon([(40,12),(20,32),(40,52)], fill=(255,255,255))
        d.rectangle([24,28,50,36], fill=(255,255,255))
        return img
    if name == "crown":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        d.polygon([(10,48),(8,18),(24,32),(32,12),(40,32),(56,18),(54,48)], fill=(255,210,60), outline=(180,140,20), width=2)
        return img
    if name == "skull":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        d.ellipse([10,8,54,46], fill=(235,235,240), outline=(90,90,100), width=2)
        d.ellipse([18,22,28,32], fill=(60,60,70)); d.ellipse([36,22,46,32], fill=(60,60,70))
        d.polygon([(26,38),(38,38),(32,50)], fill=(60,60,70))
        return img
    if name == "lock":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        d.arc([18,8,46,40],180,360,fill=(220,160,50),width=7)
        d.rounded_rectangle([12,32,52,58],6,fill=(220,160,50), outline=(160,110,30), width=2)
        d.ellipse([29,40,35,46], fill=(90,60,20))
        return img
    if name == "profile":
        img = Image.new("RGBA",(64,64),(0,0,0,0)); d=d_(img)
        d.ellipse([18,8,46,36], fill=(255,255,255))
        d.pieslice([8,38,56,88],180,360,fill=(255,255,255))
        return img
for i in ["gem","coin","spin","play","cart","online","login","back","crown","skull","lock","profile"]:
    save(icon(i), "Art", f"icon_{i}.png")

# joystick bases
jb = Image.new("RGBA",(256,256),(0,0,0,0)); d=ImageDraw.Draw(jb)
d.ellipse([8,8,248,248], fill=(255,255,255,40), outline=(255,255,255,120), width=4)
save(jb, "Art", "joy_base.png")
jk = Image.new("RGBA",(120,120),(0,0,0,0)); d=ImageDraw.Draw(jk)
d.ellipse([10,10,110,110], fill=(255,255,255,150), outline=(255,255,255,220), width=4)
save(jk, "Art", "joy_knob.png")

# fire button
fb = Image.new("RGBA",(140,140),(0,0,0,0)); d=ImageDraw.Draw(fb)
d.ellipse([6,6,134,134], fill=(230,70,60,230), outline=(255,255,255,180), width=5)
d.polygon([(52,38),(104,70),(52,102)], fill=(255,255,255,230))
save(fb, "Art", "btn_fire.png")
# jump button
jbn = Image.new("RGBA",(140,140),(0,0,0,0)); d=ImageDraw.Draw(jbn)
d.ellipse([6,6,134,134], fill=(80,150,240,230), outline=(255,255,255,180), width=5)
d.polygon([(70,34),(102,70),(82,70),(82,102),(58,102),(58,70),(38,70)], fill=(255,255,255,230))
save(jbn, "Art", "btn_jump.png")

# color swatches for team colors
TEAM_COLORS = {"red":(229,57,53),"yellow":(253,216,53),"blue":(66,139,247),"green":(67,160,71),
               "purple":(156,80,182),"orange":(255,152,0),"cyan":(38,198,218),"pink":(240,98,146)}
for name,(r,g,b) in TEAM_COLORS.items():
    sw = Image.new("RGBA",(96,96),(0,0,0,0)); d=ImageDraw.Draw(sw)
    d.ellipse([6,6,90,90], fill=(r,g,b,255), outline=(255,255,255,230), width=4)
    save(sw, "Art", f"color_{name}.png")

print("world art done")
