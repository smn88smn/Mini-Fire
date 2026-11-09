using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace MiniFire
{
    /// <summary>Procedural UGUI construction helpers. All menus are built in code.</summary>
    public static class UIFactory
    {
        public static Font Font
        {
            get
            {
                if (_font == null) _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
                return _font;
            }
        }
        static Font _font;

        // ---------------- colors ----------------
        public static readonly Color PanelBg = FromHex(0x22262E, 0.94f);
        public static readonly Color PanelBgDark = FromHex(0x181B21, 0.97f);
        public static readonly Color ButtonBg = FromHex(0x3A4150);
        public static readonly Color ButtonBgGreen = FromHex(0x3E8E4A);
        public static readonly Color ButtonBgBlue = FromHex(0x3672C9);
        public static readonly Color ButtonBgRed = FromHex(0xB33B38);
        public static readonly Color ButtonBgGold = FromHex(0xB08424);
        public static readonly Color TextMain = Color.white;
        public static readonly Color TextDim = FromHex(0xAAB2C0);
        public static readonly Color Accent = FromHex(0x4FC3F7);

        public static Color FromHex(int hex, float a = 1f)
        {
            float r = ((hex >> 16) & 0xFF) / 255f, g = ((hex >> 8) & 0xFF) / 255f, b = (hex & 0xFF) / 255f;
            return new Color(r, g, b, a);
        }

        // ---------------- root canvas ----------------
        public static Canvas CreateRootCanvas(string name, int sortOrder = 100)
        {
            var go = new GameObject(name, typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            var canvas = go.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = sortOrder;
            var scaler = go.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1280, 720);
            scaler.matchWidthOrHeight = 0.5f;
            UnityEngine.Object.DontDestroyOnLoad(go);
            return canvas;
        }

        public static void EnsureEventSystem()
        {
            if (UnityEngine.EventSystems.EventSystem.current == null)
                new GameObject("EventSystem", typeof(UnityEngine.EventSystems.EventSystem),
                               typeof(UnityEngine.EventSystems.StandaloneInputModule));
        }

        // ---------------- basics ----------------
        public static RectTransform Rect(Transform parent, string name)
        {
            var go = new GameObject(name, typeof(RectTransform));
            var rt = (RectTransform)go.transform;
            rt.SetParent(parent, false);
            return rt;
        }

        public static Image Image(Transform parent, string name, Color color, Sprite sprite = null)
        {
            var rt = Rect(parent, name);
            var img = rt.gameObject.AddComponent<Image>();
            img.color = color;
            if (sprite != null) img.sprite = sprite;
            img.raycastTarget = false;
            return img;
        }

        public static Image ImageSprite(Transform parent, string name, string resourcePath)
        {
            var sp = Resources.Load<Sprite>(resourcePath);
            var rt = Rect(parent, name);
            var img = rt.gameObject.AddComponent<Image>();
            img.sprite = sp;
            img.raycastTarget = false;
            img.preserveAspect = true;
            return img;
        }

        public static Text Label(Transform parent, string text, int size = 22, Color? color = null,
            TextAnchor align = TextAnchor.MiddleLeft, FontStyle style = FontStyle.Normal)
        {
            var rt = Rect(parent, "label");
            var t = rt.gameObject.AddComponent<Text>();
            t.font = Font;
            t.text = text;
            t.fontSize = size;
            t.color = color ?? TextMain;
            t.alignment = align;
            t.fontStyle = style;
            t.horizontalOverflow = HorizontalWrapMode.Wrap;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            t.raycastTarget = false;
            t.resizeTextForBestFit = false;
            return t;
        }

        public static Text Title(Transform parent, string text, int size = 40)
            => Label(parent, text, size, TextMain, TextAnchor.MiddleCenter, FontStyle.Bold);

        public static Button Button(Transform parent, string text, Color bg, Vector2 size, Action onClick,
            int fontSize = 24)
        {
            var rt = Rect(parent, "btn_" + text);
            rt.sizeDelta = size;
            var img = rt.gameObject.AddComponent<Image>();
            img.color = bg;
            var btn = rt.gameObject.AddComponent<Button>();
            btn.targetGraphic = img;
            var lbl = Label(rt, text, fontSize, TextMain, TextAnchor.MiddleCenter, FontStyle.Bold);
            lbl.rectTransform.StretchFull();
            btn.onClick.AddListener(() => { Sfx.Play("sfx_ui"); onClick?.Invoke(); });
            return btn;
        }

        public static void StretchFull(this RectTransform rt)
        {
            rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one;
            rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;
        }

        public static void SetAnchors(this RectTransform rt, Vector2 min, Vector2 max)
        {
            rt.anchorMin = min; rt.anchorMax = max;
            rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;
        }

        // ---------------- panels ----------------
        public static RectTransform Panel(Transform parent, string name, Color? bg = null, bool darken = true)
        {
            var overlay = Rect(parent, name + "_overlay");
            overlay.StretchFull();
            var ovImg = overlay.gameObject.AddComponent<Image>();
            ovImg.color = darken ? new Color(0, 0, 0, 0.55f) : Color.clear;
            var panel = Rect(overlay, name);
            var img = panel.gameObject.AddComponent<Image>();
            img.color = bg ?? PanelBg;
            return panel;
        }

        public static RectTransform Window(Transform parent, string title, out RectTransform content, out RectTransform header)
        {
            var panel = Panel(parent, "win_" + title);
            panel.sizeDelta = new Vector2(0, 0);
            panel.SetAnchors(new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f));
            panel.sizeDelta = new Vector2(900, 560);
            // header
            header = Rect(panel, "header");
            header.SetAnchors(new Vector2(0, 1), new Vector2(1, 1));
            header.sizeDelta = new Vector2(0, 64);
            header.anchoredPosition = Vector2.zero;
            var hbg = header.gameObject.AddComponent<Image>();
            hbg.color = PanelBgDark;
            var t = Title(header, title, 30);
            t.rectTransform.StretchFull();
            // content
            content = Rect(panel, "content");
            content.SetAnchors(new Vector2(0, 0), new Vector2(1, 1));
            content.offsetMax = new Vector2(-16, -76);
            content.offsetMin = new Vector2(16, 16);
            return panel;
        }

        // ---------------- scroll view ----------------
        public sealed class Scroll
        {
            public RectTransform viewport, content;
            public ScrollRect rect;
        }

        public static Scroll ScrollV(Transform parent)
        {
            var root = Rect(parent, "scroll");
            root.StretchFull();
            var img = root.gameObject.AddComponent<Image>();
            img.color = Color.clear;
            var sr = root.gameObject.AddComponent<ScrollRect>();
            var viewport = Rect(root, "viewport");
            viewport.StretchFull();
            var mask = viewport.gameObject.AddComponent<Image>();
            mask.color = Color.clear;
            viewport.gameObject.AddComponent<RectMask2D>();
            var content = Rect(viewport, "content");
            content.anchorMin = new Vector2(0, 1); content.anchorMax = new Vector2(1, 1);
            content.pivot = new Vector2(0.5f, 1f);
            content.sizeDelta = new Vector2(0, 0);
            var layout = content.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.childControlWidth = true; layout.childControlHeight = true;
            layout.childForceExpandWidth = true; layout.childForceExpandHeight = false;
            layout.spacing = 8;
            var fitter = content.gameObject.AddComponent<ContentSizeFitter>();
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            sr.viewport = viewport;
            sr.content = content;
            sr.horizontal = false; sr.vertical = true;
            sr.scrollSensitivity = 30;
            return new Scroll { viewport = viewport, content = content, rect = sr };
        }

        // row helper for lists
        public static RectTransform Row(Transform contentParent, float height = 84)
        {
            var rt = Rect(contentParent, "row");
            var le = rt.gameObject.AddComponent<LayoutElement>();
            le.minHeight = height; le.preferredHeight = height;
            var bg = rt.gameObject.AddComponent<Image>();
            bg.color = FromHex(0x2B303A);
            var hl = rt.gameObject.AddComponent<HorizontalLayoutGroup>();
            hl.childControlWidth = true; hl.childControlHeight = true;
            hl.childForceExpandWidth = false; hl.childForceExpandHeight = true;
            hl.padding = new RectOffset(12, 12, 8, 8);
            hl.spacing = 12;
            return rt;
        }

        // ---------------- misc ----------------
        public static InputField Input(Transform parent, string placeholder, int fontSize = 22)
        {
            var rt = Rect(parent, "input");
            rt.sizeDelta = new Vector2(360, 48);
            var img = rt.gameObject.AddComponent<Image>();
            img.color = FromHex(0x14171C);
            var inf = rt.gameObject.AddComponent<InputField>();
            var txt = Label(rt, "", fontSize, TextMain, TextAnchor.MiddleLeft);
            txt.rectTransform.StretchFull();
            txt.rectTransform.offsetMin = new Vector2(10, 2);
            txt.rectTransform.offsetMax = new Vector2(-10, -2);
            inf.textComponent = txt;
            var ph = Label(rt, placeholder, fontSize, TextDim, TextAnchor.MiddleLeft);
            ph.rectTransform.StretchFull();
            ph.rectTransform.offsetMin = new Vector2(10, 2);
            ph.rectTransform.offsetMax = new Vector2(-10, -2);
            ph.raycastTarget = false;
            inf.placeholder = ph;
            return inf;
        }

        public static void Clear(Transform t)
        {
            for (int i = t.childCount - 1; i >= 0; i--)
                UnityEngine.Object.Destroy(t.GetChild(i).gameObject);
        }

        public static GameObject Toast(Transform parent, string message, float seconds = 2.5f)
        {
            var rt = Rect(parent, "toast");
            rt.SetAnchors(new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f));
            rt.sizeDelta = new Vector2(700, 60);
            var img = rt.gameObject.AddComponent<Image>();
            img.color = FromHex(0x101318, 0.95f);
            var t = Label(rt, message, 24, TextMain, TextAnchor.MiddleCenter);
            t.rectTransform.StretchFull();
            var fader = rt.gameObject.AddComponent<ToastFader>();
            fader.life = seconds;
            return rt.gameObject;
        }
    }

    /// <summary>Fades out and destroys the toast.</summary>
    public class ToastFader : MonoBehaviour
    {
        public float life = 2.5f;
        float t;
        void Update()
        {
            t += Time.unscaledDeltaTime;
            if (t > life) { Destroy(gameObject); return; }
            if (t > life - 0.5f)
            {
                var img = GetComponent<Image>();
                var txt = GetComponentInChildren<Text>();
                float a = Mathf.Lerp(1, 0, (t - (life - 0.5f)) / 0.5f);
                if (img) { var c = img.color; c.a = 0.95f * a; img.color = c; }
                if (txt) { var c = txt.color; c.a = a; txt.color = c; }
            }
        }
    }
}
