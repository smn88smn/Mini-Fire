using System.Collections.Generic;
using UnityEngine;

namespace MiniFire
{
    /// <summary>Sprite-based visual effects with a small pool.</summary>
    public static class Effects
    {
        class Fx
        {
            public SpriteRenderer sr;
            public float life, total;
            public Vector3 vel;
            public bool shrink;
        }

        static readonly List<Fx> active = new List<Fx>();
        static readonly List<Fx> pool = new List<Fx>();
        static GameObject root;

        static Fx Get()
        {
            if (root == null) root = new GameObject("FxRoot");
            Fx f;
            if (pool.Count > 0) { f = pool[pool.Count - 1]; pool.RemoveAt(pool.Count - 1); }
            else
            {
                var go = new GameObject("fx");
                go.transform.SetParent(root.transform, false);
                f = new Fx { sr = go.AddComponent<SpriteRenderer>() };
                f.sr.sortingOrder = 9;
            }
            f.sr.gameObject.SetActive(true);
            return f;
        }

        static void Spawn(string sprite, Vector3 pos, float life, float scale, Color? tint = null)
        {
            var f = Get();
            f.sr.sprite = Resources.Load<Sprite>("Art/" + sprite);
            f.sr.color = tint ?? Color.white;
            f.sr.transform.position = pos;
            f.sr.transform.rotation = Quaternion.identity;
            f.sr.transform.localScale = Vector3.one * scale;
            f.life = f.total = life;
            f.shrink = true;
            f.vel = Vector3.zero;
            active.Add(f);
        }

        public static void Muzzle(Vector3 pos, float aim)
        {
            Spawn("fx_muzzle", pos, 0.06f, 1f);
        }

        public static void Hit(Vector3 pos) => Spawn("fx_hit", pos, 0.15f, 0.8f);

        public static void Explosion(Vector3 pos, float radius)
        {
            Spawn("fx_explosion", pos, 0.4f, radius * 1.6f);
        }

        public static void Blood(Vector3 pos) => Spawn("fx_blood", pos, 0.25f, 0.7f);

        public static void Burn(Vector3 pos) => Spawn("fx_burn", pos, 0.3f, 0.6f);

        public static void SpawnRing(Vector3 pos) => Spawn("fx_spawn", pos, 0.5f, 1.2f, new Color(1, 1, 1, 0.7f));

        public static void Pump()
        {
            if (active.Count == 0) return;
            for (int i = active.Count - 1; i >= 0; i--)
            {
                var f = active[i];
                f.life -= Time.deltaTime;
                if (f.life <= 0)
                {
                    f.sr.gameObject.SetActive(false);
                    active.RemoveAt(i);
                    pool.Add(f);
                    continue;
                }
                float t = f.life / f.total;
                if (f.shrink)
                {
                    var s = f.sr.transform.localScale;
                    f.sr.transform.localScale = new Vector3(s.x * (0.97f), s.y * 0.97f, 1);
                    var c = f.sr.color; c.a = t; f.sr.color = c;
                }
                f.sr.transform.position += f.vel * Time.deltaTime;
            }
        }
    }

    /// <summary>Audio: one-shot clips + looping jetpack.</summary>
    public static class Sfx
    {
        static AudioSource oneShot;
        static AudioSource jetSource;
        static float volume = 0.8f;

        public static void Init()
        {
            if (oneShot == null)
            {
                var go = new GameObject("Sfx");
                UnityEngine.Object.DontDestroyOnLoad(go);
                oneShot = go.AddComponent<AudioSource>();
                oneShot.playOnAwake = false;
                jetSource = go.AddComponent<AudioSource>();
                jetSource.playOnAwake = false;
                jetSource.loop = true;
                var clip = Resources.Load<AudioClip>("Sounds/sfx_jetpack");
                if (clip != null) { jetSource.clip = clip; jetSource.volume = 0; jetSource.Play(); }
            }
        }

        public static void SetVolume(float v) { volume = Mathf.Clamp01(v); if (oneShot) oneShot.volume = volume; }

        public static void Play(string name)
        {
            if (oneShot == null) Init();
            var clip = Resources.Load<AudioClip>("Sounds/" + name);
            if (clip != null) oneShot.PlayOneShot(clip, volume);
        }

        public static void PlayAt(string name, Vector2 worldPos)
        {
            var cam = Camera.main;
            if (cam == null) { Play(name); return; }
            float d = Vector2.Distance(worldPos, cam.transform.position);
            float att = Mathf.Clamp01(1f - d / 30f);
            if (att <= 0.05f) return;
            var clip = Resources.Load<AudioClip>("Sounds/" + name);
            if (clip != null && oneShot != null) oneShot.PlayOneShot(clip, volume * att);
        }

        public static void LoopJet(bool on)
        {
            if (jetSource == null) return;
            float target = on ? volume * 0.5f : 0f;
            jetSource.volume = Mathf.MoveTowards(jetSource.volume, target, Time.deltaTime * 3f);
        }
    }
}
