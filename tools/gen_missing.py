#!/usr/bin/env python3
"""MiniFire Unity - missing art: weapon sprites for all 10 weapon ids, bullets,
gun icons, warzone map theme, extra color swatches."""
import os, math
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "Resources")
ART = os.path.join(ROOT, "Art")
MAPS = os.path.join(ROOT, "Maps")

def save(img, folder, name):
    p = os.path.join(ROOT, folder, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)

def clamp(v,a,b): return max(a,min(b,v))
def shade(c,f): return (clamp(int(c[0]*f),0,255),clamp(int(c[1]*f),0,255),clamp(int(c[2]*f),0,255))
def mix(a,b,t): return (int(a[0]+(b[0]-a[0])*t),int(a[1]+(b[1]-a[1])*t),int(a[2]+(b[2]-a[2])*t))

o = (24,22,26)
metal, metal2, wood = (72,76,84), (96,102,112), (122,84,52)

def gun(kind):
    L = {"mp5":72,"mp40":76,"woodpecker":104,"svd":112,"rocket":96}.get(kind,70)
    H = 34
    img = Image.new("RGBA",(L,H),(0,0,0,0)); d = ImageDraw.Draw(img)
    if kind == "mp5":
        d.rounded_rectangle([6,12,60,22],3,fill=metal,outline=o,width=2)
        d.rounded_rectangle([6,10,60,15],2,fill=metal2)
        d.polygon([(10,21),(22,21),(18,32),(6,32)],fill=metal2,outline=o)
        d.rectangle([26,22,34,33],fill=metal2,outline=o)          # curved mag
        d.rectangle([60,14,68,17],fill=(60,62,68))               # barrel
        d.rectangle([16,7,20,11],fill=metal2)                    # sight
    elif kind == "mp40":
        d.rounded_rectangle([6,12,62,22],3,fill=metal,outline=o,width=2)
        d.rounded_rectangle([6,10,62,15],2,fill=metal2)
        d.polygon([(10,21),(22,21),(18,32),(6,32)],fill=wood,outline=o)   # wooden grip
        d.rectangle([30,22,38,32],fill=metal2,outline=o)
        d.rectangle([62,14,70,17],fill=(60,62,68))
        d.polygon([(52,21),(70,23),(70,29),(52,29)],fill=wood,outline=o) # wooden stock
    elif kind == "woodpecker":   # marksman rifle w/ big scope
        d.rounded_rectangle([10,13,80,21],3,fill=metal,outline=o,width=2)
        d.rounded_rectangle([10,11,80,16],2,fill=metal2)
        d.rectangle([32,22,38,32],fill=metal2,outline=o)
        d.polygon([(16,21),(28,21),(24,32),(12,32)],fill=metal2,outline=o)
        d.rectangle([80,15,100,18],fill=(58,60,66))
        d.rounded_rectangle([28,2,54,9],3,fill=(40,44,50),outline=o)
        d.ellipse([28,1,34,7],fill=(140,200,255))
        d.polygon([(68,21),(86,23),(86,29),(68,29)],fill=metal2,outline=o)
    elif kind == "svd":          # dragunov-style
        d.rounded_rectangle([12,13,84,21],3,fill=(96,88,66),outline=o,width=2)
        d.rounded_rectangle([12,11,84,16],2,fill=(110,102,78))
        d.rectangle([34,22,40,32],fill=(96,88,66),outline=o)
        d.polygon([(16,21),(28,21),(24,32),(12,32)],fill=(96,88,66),outline=o)
        d.rectangle([84,15,104,18],fill=(58,60,66))
        d.rounded_rectangle([26,1,54,8],3,fill=(40,44,50),outline=o)
        d.ellipse([26,0,32,6],fill=(140,200,255))
        d.polygon([(70,21),(90,24),(90,30),(70,30)],fill=wood,outline=o)
        d.rectangle([46,8,52,12],fill=metal2); d.rectangle([58,8,64,12],fill=metal2)
    elif kind == "rocket":       # rpg launcher with rocket tip
        d.rounded_rectangle([6,12,80,22],4,fill=(90,96,70),outline=o,width=2)
        d.polygon([(2,11),(12,11),(12,23),(2,27)],fill=(90,96,70),outline=o)
        d.polygon([(16,22),(28,22),(24,32),(12,32)],fill=(70,74,58),outline=o)
        d.rounded_rectangle([40,4,54,12],3,fill=(70,74,58),outline=o)
        d.rectangle([80,15,92,19],fill=(70,74,58))
        d.ellipse([30,8,44,26],fill=(188,60,50),outline=o,width=2)
        # rocket tip
        d.polygon([(92,13),(104,17),(92,21)],fill=(200,70,50),outline=o)
    return img

for k in ["mp5","mp40","woodpecker","svd","rocket"]:
    save(gun(k),"Art",f"gun_{k}.png")
    g = gun(k); save(g.resize((g.width*2,g.height*2),Image.NEAREST),"Art",f"gunicon_{k}.png")

def bullet(kind):
    img = Image.new("RGBA",(22,8),(0,0,0,0)); d=ImageDraw.Draw(img)
    col = {"mp5":(255,210,80),"mp40":(255,205,70),"woodpecker":(200,235,255),
           "svd":(190,225,255),"rocket":(255,120,40)}.get(kind,(255,220,90))
    d.rounded_rectangle([0,1,14,7],3,fill=col)
    d.polygon([(12,0),(22,4),(12,8)],fill=shade(col,.8))
    return img
for k in ["mp5","mp40","woodpecker","svd","rocket"]:
    save(bullet(k),"Art",f"bullet_{k}.png")

# ------------------------------------------------ warzone theme (night city ruins)
def sky_gradient(w,h,top,bot):
    img = Image.new("RGB",(w,h))
    for y in range(h):
        t=y/h; img.paste(mix(top,bot,t),(0,y,w,y+1))
    return img.convert("RGBA")

def buildings(w,h,color,seed,base=0.8, lit=True):
    import random as r; r.seed(seed)
    img = Image.new("RGBA",(w,h),(0,0,0,0)); d=ImageDraw.Draw(img)
    x=0
    while x < w:
        bw = r.randint(40,110); bh = int(h*base - r.uniform(0,h*0.3))
        d.rectangle([x,h-bh,x+bw,h],fill=color)
        if lit:
            for wy in range(h-bh+8,h-6,14):
                for wx in range(x+6,x+bw-8,12):
                    if r.random()<0.35:
                        c = (255,220,120) if r.random()<0.7 else (150,220,255)
                        d.rectangle([wx,wy,wx+5,wy+7],fill=c+(200,))
        x += bw + r.randint(4,18)
    return img

W,H = 1024,576
img = sky_gradient(W,H,(16,20,40),(44,38,66))
# moon + stars
d = ImageDraw.Draw(img)
import random as sr; sr.seed(7)
for _ in range(90):
    x,y = sr.randint(0,W),sr.randint(0,int(H*0.6))
    d.ellipse([x,y,x+2,y+2],fill=(255,255,255,150))
d.ellipse([W-160,60,W-90,130],fill=(235,235,220,255))
far = buildings(W,H,(30,34,52),11,base=0.85)
near = buildings(W,H,(20,23,36),12,base=0.7)
img.alpha_composite(far,(0,0)); img.alpha_composite(near,(0,0))
save(img,"Maps","bg_warzone.png")

# warzone ground tile (dark rubble concrete)
g = Image.new("RGBA",(256,128),(0,0,0,0)); dg = ImageDraw.Draw(g)
gc = (56,58,66)
dg.rectangle([0,0,256,128],fill=gc)
for i in range(28):
    x,y = sr.randint(0,248),sr.randint(0,120)
    dg.ellipse([x,y,x+sr.randint(3,10),y+sr.randint(2,7)],fill=shade(gc,sr.uniform(0.75,1.2)))
dg.rectangle([0,0,256,8],fill=shade(gc,1.3))
save(g,"Maps","tile_ground_warzone.png")
p = Image.new("RGBA",(256,48),(0,0,0,0)); dp = ImageDraw.Draw(p)
pc = (74,78,92)
dp.rounded_rectangle([0,0,256,44],6,fill=pc)
dp.rounded_rectangle([0,0,256,12],6,fill=shade(pc,1.3))
for bx in (10,120,210): dp.rectangle([bx,26,bx+30,36],fill=shade(pc,.75))
save(p,"Maps","tile_plat_warzone.png")

# ------------------------------------------------ remaining team color swatches
EXTRA = {"white":(242,242,242),"gray":(140,140,140),"lime":(159,255,77),
         "indigo":(77,107,255),"rose":(255,107,158),"mint":(77,255,179),
         "aqua":(77,255,200),"sand":(212,212,77)}
for name,(r,g,b) in EXTRA.items():
    sw = Image.new("RGBA",(96,96),(0,0,0,0)); d2 = ImageDraw.Draw(sw)
    d2.ellipse([6,6,90,90],fill=(r,g,b,255),outline=(255,255,255,230),width=4)
    save(sw,"Art",f"color_{name}.png")

print("missing art done")
