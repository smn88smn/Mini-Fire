using System.Collections.Generic;
using UnityEngine;

namespace MiniFire
{
    /// <summary>Renders a player: animated character sprite (skin set), team-color tint,
    /// gun that rotates with aim, jet flame, name tag and HP bar.</summary>
    public class AvatarRender
    {
        static readonly Dictionary<string, Sprite[]> Frames = new Dictionary<string, Sprite[]>();

        public static Sprite[] GetFrames(string skin)
        {
            Sprite[] s;
            if (Frames.TryGetValue(skin, out s)) return s;
            var names = new[] { "idle", "run0", "run1", "run2", "run3", "fly0", "fly1", "jump", "crouch", "hurt", "dead" };
            var arr = new Sprite[names.Length];
            for (int i = 0; i < names.Length; i++)
                arr[i] = Resources.Load<Sprite>("Art/Chars/" + skin + "_" + names[i]);
            if (arr[0] == null) arr = GetFrames("recruit"); // fallback
            Frames[skin] = arr;
            return arr;
        }

        public const int Idle = 0, Run0 = 1, Run1 = 2, Run2 = 3, Run3 = 4, Fly0 = 5, Fly1 = 6,
                          Jump = 7, Crouch = 8, Hurt = 9, Dead = 10;

        public GameObject root;
        SpriteRenderer body, jet;
        SpriteRenderer gunSprite;
        Transform gunPivot;
        TextMesh nameTag;
        GameObject hpBarRoot;
        SpriteRenderer hpFill;
        readonly float animT = 0f;
        int animFrame;

        Color teamColor = Color.white;

        public static AvatarRender Create(string skin, string name, Color color)
        {
            var r = new AvatarRender();
            r.root = new GameObject("avatar_" + name);
            r.body = NewSprite(r.root.transform, "body");
            r.jet = NewSprite(r.root.transform, "jet");
            r.jet.sprite = Resources.Load<Sprite>("Art/fx_burn");
            r.jet.transform.localPosition = new Vector3(0, -0.15f, 0);
            r.jet.transform.localScale = new Vector3(0.6f, 0.6f, 1);
            r.jet.sortingOrder = 2;
            r.jet.enabled = false;
            r.gunPivot = new GameObject("gunPivot").transform;
            r.gunPivot.SetParent(r.root.transform, false);
            r.gunSprite = NewSprite(r.gunPivot, "gun");
            r.gunSprite.sortingOrder = 5;

            // name tag
            var tagGo = new GameObject("tag");
            tagGo.transform.SetParent(r.root.transform, false);
            tagGo.transform.localPosition = new Vector3(0, 1.5f, 0);
            r.nameTag = tagGo.AddComponent<TextMesh>();
            r.nameTag.text = name;
            r.nameTag.fontSize = 26;
            r.nameTag.anchor = TextAnchor.MiddleCenter;
            r.nameTag.alignment = TextAlignment.Center;
            r.nameTag.characterSize = 0.6f;
            r.nameTag.color = color;
            var mr = tagGo.GetComponent<MeshRenderer>();
            mr.sortingOrder = 20;

            // hp bar
            var barGo = new GameObject("hpbar");
            barGo.transform.SetParent(r.root.transform, false);
            barGo.transform.localPosition = new Vector3(0, 1.25f, 0);
            var bg = barGo.AddComponent<SpriteRenderer>();
            bg.sprite = MakeBarSprite();
            bg.color = Color.black; bg.transform.localScale = new Vector3(1.6f, 0.16f, 1);
            bg.sortingOrder = 19;
            var fillGo = new GameObject("fill");
            fillGo.transform.SetParent(barGo.transform, false);
            r.hpFill = fillGo.AddComponent<SpriteRenderer>();
            r.hpFill.sprite = MakeBarSprite();
            r.hpFill.color = color; r.hpFill.transform.localScale = new Vector3(1.5f, 0.1f, 1);
            r.hpFill.sortingOrder = 20;
            r.hpBarRoot = barGo;

            r.SetSkin(skin);
            r.teamColor = color;
            return r;
        }

        static SpriteRenderer NewSprite(Transform parent, string n)
        {
            var go = new GameObject(n);
            go.transform.SetParent(parent, false);
            var sr = go.AddComponent<SpriteRenderer>();
            return sr;
        }

        static Sprite MakeBarSprite()
        {
            var tex = new Texture2D(8, 8, TextureFormat.RGBA32, false);
            var cols = new Color32[64];
            for (int i = 0; i < 64; i++) cols[i] = new Color32(255, 255, 255, 255);
            tex.SetPixels32(cols); tex.Apply();
            return Sprite.Create(tex, new Rect(0, 0, 8, 8), new Vector2(0.5f, 0.5f), 8f);
        }

        public void SetSkin(string skin)
        {
            var frames = GetFrames(skin);
            body.sprite = frames[Idle];
            // jet flame drawn by SetJet below
        }

        public void SetGun(string weaponId, Color tint)
        {
            var sp = Resources.Load<Sprite>("Art/gun_" + weaponId);
            gunSprite.sprite = sp;
            gunSprite.color = tint;
            if (sp != null)
            {
                float scale = 0.9f;
                gunSprite.transform.localScale = new Vector3(scale, scale, 1);
                gunSprite.transform.localPosition = new Vector3(sp.bounds.size.x * 0.45f, 0, 0);
            }
        }

        public void SetJet(bool on) => jet.enabled = on;

        public void SetVisible(bool v)
        {
            root.SetActive(v);
        }

        /// <summary>position (feet), facing, anim, aim, hp fraction, burn</summary>
        public void UpdateView(float x, float y, int anim, float aim, bool facingRight,
            float hpFrac, bool burn, bool dead, float dt)
        {
            root.transform.position = new Vector3(x, y, 0);

            var frames = GetFrames(CurrentSkin);
            int frame;
            if (dead) frame = Dead;
            else if (anim == 1) // run cycle
            {
                animFrame = (int)(Time.time * 10) % 4;
                frame = Run0 + animFrame;
            }
            else if (anim == 2) frame = (Time.time * 8) % 2 < 1 ? Fly0 : Fly1;
            else if (anim == 3) frame = Jump;
            else if (anim == 4) frame = Crouch;
            else if (anim == 5) frame = Hurt;
            else frame = Idle;
            body.sprite = frames[frame];

            float sx = facingRight ? 1 : -1;
            body.transform.localScale = new Vector3(sx, 1, 1);
            nameTag.transform.localScale = Vector3.one; // never mirror the text
            hpBarRoot.transform.localScale = new Vector3(1, 1, 1);

            // gun pivot at shoulder, rotates with aim
            gunPivot.localPosition = new Vector3(0, 0.72f, 0);
            float ang = aim * Mathf.Rad2Deg;
            if (!facingRight) ang = 180f - ang;
            gunPivot.localRotation = Quaternion.Euler(0, 0, ang);
            gunSprite.transform.localScale = new Vector3(0.9f * sx, 0.9f, 1);
            gunSprite.transform.localPosition = new Vector3(
                gunSprite.sprite != null ? gunSprite.sprite.bounds.size.x * 0.45f * sx : 0.3f, 0, 0);

            hpFill.transform.localScale = new Vector3(1.5f * Mathf.Clamp01(hpFrac), 0.1f, 1);
            hpFill.color = hpFrac > 0.5f ? Color.green : hpFrac > 0.25f ? Color.yellow : Color.red;

            // burn overlay: flicker red
            if (burn) body.color = Color.Lerp(Color.white, new Color(1f, 0.35f, 0.2f), Mathf.PingPong(Time.time * 6, 1));
            else if (!dead) body.color = Color.white;
            if (dead) body.color = new Color(1, 1, 1, 0.85f);
        }

        public string CurrentSkin = "recruit";

        public void Destroy() => Object.Destroy(root);
    }
}
