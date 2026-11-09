#!/usr/bin/env python3
"""MiniFire Unity - sound effect synthesizer (WAV files)."""
import os, wave, numpy as np

OUT = os.path.join(os.path.dirname(__file__), "..", "Assets", "Resources", "Sounds")
os.makedirs(OUT, exist_ok=True)
SR = 22050

def save(name, data, stereo=False):
    data = np.clip(data, -1, 1)
    pcm = (data * 32767).astype(np.int16)
    if stereo:
        pcm = np.stack([pcm, pcm], axis=1).reshape(-1)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(2 if stereo else 1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())

def t(dur): return np.arange(int(SR*dur))/SR

def env_exp(dur, k=8): return np.exp(-k*t(dur))
def noise(dur): return np.random.uniform(-1,1,int(SR*dur))

def lowpass(x, a):
    y = np.empty_like(x); acc=0.0
    for i,v in enumerate(x):
        acc += a*(v-acc); y[i]=acc
    return y

def shot(freq=900, dur=0.16, boom=0.5):
    n = noise(dur)*env_exp(dur,10)
    s = lowpass(n, 0.25)
    click = np.sin(2*np.pi*freq*t(dur))*env_exp(dur,22)*0.7
    return s*1.4 + click + noise(dur)*env_exp(dur,30)*boom*0.5

# weapons
save("sfx_pistol.wav", shot(700, .12))
save("sfx_smg.wav", shot(1000, .09))
save("sfx_rifle.wav", shot(800, .14))
save("sfx_shotgun.wav", shot(300, .3, .9)*0.9)
save("sfx_sniper.wav", shot(1300, .35, 1.0)*1.1)
save("sfx_rpg.wav", lowpass(noise(.5),0.08)*env_exp(.5,4)*1.6)
save("sfx_minigun.wav", shot(1100, .08, .3))

# explosion
d = .9
ex = lowpass(noise(d), 0.05)*env_exp(d,3)*2.2 + np.sin(2*np.pi*60*t(d))*env_exp(d,3)*1.4
save("sfx_explosion.wav", ex)

# hit / hurt
save("sfx_hit.wav", lowpass(noise(.1),0.3)*env_exp(.1,18)*1.5 + np.sin(2*np.pi*200*t(.1))*env_exp(.1,15))
save("sfx_hurt.wav", np.sin(2*np.pi*160*t(.25))*env_exp(.25,9)*0.9 + noise(.25)*env_exp(.25,12)*.4)
d = np.concatenate([np.sin(2*np.pi*440*t(.12))*env_exp(.12,6), np.sin(2*np.pi*330*t(.2))*env_exp(.2,6)*.8])
save("sfx_death.wav", d*0.9)

# burn (loop-ish crackle)
b = lowpass(noise(.6),0.5)
crackle = (np.random.uniform(-1,1,int(SR*.6)) > 0.995).astype(float)
b = b*.5 + np.convolve(crackle, np.ones(80)/80, "same")*6
save("sfx_burn.wav", b*env_exp(.6,1.2)*.8)

# jetpack loop (1s, loopable)
jt = .25*np.sin(2*np.pi*95*t(1)) + .18*np.sin(2*np.pi*190*t(1)) + lowpass(noise(1),0.35)*.7
fade = np.ones_like(jt); f=int(SR*.05)
fade[:f]=np.linspace(0,1,f); fade[-f:]=np.linspace(1,0,f)
save("sfx_jetpack.wav", jt*fade*.7)

# pickups / economy
def blip(f, dur=.09, k=6): return np.sin(2*np.pi*f*t(dur))*env_exp(dur,k)
save("sfx_coin.wav", np.concatenate([blip(880), blip(1320,.14)]))
save("sfx_gem.wav", np.concatenate([blip(1200), blip(1600), blip(2000,.18)]))
save("sfx_spin_tick.wav", blip(1500,.04,20)*.7)
save("sfx_win.wav", np.concatenate([blip(523,.15,3), blip(659,.15,3), blip(784,.3,3)])*1.1)
save("sfx_lose.wav", np.concatenate([blip(400,.15,3), blip(300,.15,3), blip(200,.3,3)]))
save("sfx_ui.wav", blip(700,.06,10)*.6)
save("sfx_purchase.wav", np.concatenate([blip(600), blip(900,.2)]))
save("sfx_levelup.wav", np.concatenate([blip(500,.1,3), blip(750,.1,3), blip(1000,.25,3)])*1.2)
save("sfx_redeem.wav", np.concatenate([blip(800), blip(1000), blip(1300,.3)]))
save("sfx_join.wav", blip(500,.15,4)*.8)
save("sfx_start.wav", np.concatenate([blip(440,.12,4), blip(554,.12,4), blip(659,.3,4)])*1.1)
save("sfx_respawn.wav", np.concatenate([blip(300,.1,4), blip(500,.25,4)])*.9)
save("sfx_burnhit.wav", lowpass(noise(.12),0.6)*env_exp(.12,10))

print("sounds done:", len(os.listdir(OUT)))
