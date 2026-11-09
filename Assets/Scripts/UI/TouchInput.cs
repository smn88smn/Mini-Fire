using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace MiniFire
{
    /// <summary>Player input: floating dual virtual joysticks (Mini-Militia style).
    /// Left half: move (push up = jetpack). Right half: aim + fire.
    /// Keyboard/mouse fallback for editor testing.</summary>
    public static class TouchInput
    {
        public static float moveX, aim;
        public static bool jet, fire;
        public static bool swapPressed, reloadPressed, pickPressed;

        class Stick
        {
            public RectTransform baseRt, knobRt;
            public int touchId = -1;
            public Vector2 center;      // screen px
            public Vector2 value;
            public float radiusPx = 160f;
        }

        static Stick left, right;
        static Canvas canvas;
        static RectTransform swapBtn, pickBtn, reloadBtn, pauseBtn;
        static MatchHUD hud;

        public static bool TouchUi => Application.isMobilePlatform ||
            (Input.touchSupported && SystemInfo.deviceType == DeviceType.Handheld);

        public static void Create(Canvas parent, MatchHUD owner)
        {
            Destroy();
            canvas = parent;
            hud = owner;
            left = MakeStick("left");
            right = MakeStick("right");
            swapBtn = MakeButton("btn_swap", new Vector2(-320, 120), "SWAP", () => swapPressed = true);
            pickBtn = MakeButton("btn_pick", new Vector2(-320, 10), "PICK", () => pickPressed = true);
            reloadBtn = MakeButton("btn_reload", new Vector2(-320, 230), "RELOAD", () => reloadPressed = true);
            pauseBtn = MakeButton("btn_pause", new Vector2(-600, 330), "II", OnPause);
        }

        static bool pauseOpen;
        static void OnPause()
        {
            if (pauseOpen) return;
            pauseOpen = true;
            if (hud != null) hud.ShowPause();
            pauseOpen = false;
        }

        static Stick MakeStick(string side)
        {
            var s = new Stick();
            var baseGo = new GameObject("joy_" + side, typeof(RectTransform));
            baseGo.transform.SetParent(canvas.transform, false);
            s.baseRt = (RectTransform)baseGo.transform;
            s.baseRt.sizeDelta = new Vector2(280, 280);
            s.baseRt.anchoredPosition = side == "left"
                ? new Vector2(200, 160) : new Vector2(-200, 160);
            var baseImg = baseGo.AddComponent<Image>();
            baseImg.sprite = Resources.Load<Sprite>("Art/joy_base");
            baseImg.color = new Color(1, 1, 1, 0.22f);
            baseImg.raycastTarget = false;
            var knobGo = new GameObject("knob", typeof(RectTransform));
            knobGo.transform.SetParent(baseGo.transform, false);
            s.knobRt = (RectTransform)knobGo.transform;
            s.knobRt.sizeDelta = new Vector2(120, 120);
            var knobImg = knobGo.AddComponent<Image>();
            knobImg.sprite = Resources.Load<Sprite>("Art/joy_knob");
            knobImg.color = new Color(1, 1, 1, 0.55f);
            knobImg.raycastTarget = false;
            s.baseRt.gameObject.SetActive(false);
            return s;
        }

        static RectTransform MakeButton(string name, Vector2 pos, string label, System.Action action)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(canvas.transform, false);
            var rt = (RectTransform)go.transform;
            rt.sizeDelta = new Vector2(110, 64);
            rt.anchoredPosition = pos;
            var img = go.AddComponent<Image>();
            img.color = new Color(0.12f, 0.14f, 0.18f, 0.75f);
            var btn = go.AddComponent<Button>();
            btn.targetGraphic = img;
            btn.onClick.AddListener(() => action());
            var t = UIFactory.Label(rt, label, 18, Color.white, TextAnchor.MiddleCenter, FontStyle.Bold);
            t.rectTransform.StretchFull();
            return rt;
        }

        public static void Destroy()
        {
            if (left != null && left.baseRt != null) Object.Destroy(left.baseRt.gameObject);
            if (right != null && right.baseRt != null) Object.Destroy(right.baseRt.gameObject);
            if (swapBtn != null) Object.Destroy(swapBtn.gameObject);
            if (pickBtn != null) Object.Destroy(pickBtn.gameObject);
            if (reloadBtn != null) Object.Destroy(reloadBtn.gameObject);
            if (pauseBtn != null) Object.Destroy(pauseBtn.gameObject);
            left = right = null;
            swapBtn = pickBtn = reloadBtn = pauseBtn = null;
            moveX = 0; jet = false; fire = false; aim = 0;
        }

        public static void Pump()
        {
            if (left == null || right == null) return;
            bool anyTouch = false;

            for (int i = 0; i < Input.touchCount; i++)
            {
                var t = Input.GetTouch(i);
                anyTouch = true;
                if (t.phase == TouchPhase.Began)
                {
                    // ignore touches that started on UI buttons
                    if (EventSystem.current != null && EventSystem.current.IsPointerOverGameObject(t.fingerId))
                        continue;
                    if (t.position.x < Screen.width * 0.45f && left.touchId < 0)
                    {
                        left.touchId = t.fingerId;
                        left.center = t.position;
                        left.baseRt.gameObject.SetActive(true);
                        MoveStickBase(left, t.position);
                    }
                    else if (t.position.x >= Screen.width * 0.45f && right.touchId < 0)
                    {
                        right.touchId = t.fingerId;
                        right.center = t.position;
                        right.baseRt.gameObject.SetActive(true);
                        MoveStickBase(right, t.position);
                    }
                }
                if (t.fingerId == left.touchId)
                {
                    if (t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled)
                    { left.touchId = -1; left.value = Vector2.zero; left.baseRt.gameObject.SetActive(false); }
                    else left.value = Clamp((t.position - left.center) / left.radiusPx);
                }
                else if (t.fingerId == right.touchId)
                {
                    if (t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled)
                    { right.touchId = -1; right.value = Vector2.zero; right.baseRt.gameObject.SetActive(false); }
                    else right.value = Clamp((t.position - right.center) / right.radiusPx);
                }
            }

            left.knobRt.anchoredPosition = left.value * 70f;
            right.knobRt.anchoredPosition = right.value * 70f;

            moveX = Mathf.Clamp(left.value.x * 1.35f, -1f, 1f);
            jet = left.value.y > 0.4f;
            if (right.value.magnitude > 0.35f)
            {
                aim = Mathf.Atan2(right.value.y, right.value.x);
                fire = true;
            }
            else if (!anyTouch) fire = false;

            // keyboard/mouse fallback
            float kx = (Input.GetKey(KeyCode.D) || Input.GetKey(KeyCode.RightArrow) ? 1 : 0)
                     - (Input.GetKey(KeyCode.A) || Input.GetKey(KeyCode.LeftArrow) ? 1 : 0);
            if (Mathf.Abs(kx) > 0.01f) moveX = kx;
            if (Input.GetKey(KeyCode.W) || Input.GetKey(KeyCode.Space)) jet = true;
            if (Input.GetMouseButton(0) && !AnyUiAt(Input.mousePosition))
            {
                var cam = Camera.main;
                var lp = MatchRunner.I != null ? MatchRunner.I.LocalPlayer : null;
                if (cam != null && lp != null)
                {
                    var world = cam.ScreenToWorldPoint(Input.mousePosition);
                    Vector2 d = new Vector2(world.x - lp.body.x, world.y - (lp.body.y + 0.5f));
                    if (d.sqrMagnitude > 0.04f) aim = Mathf.Atan2(d.y, d.x);
                }
                fire = true;
            }
            else if (!anyTouch && !Input.GetMouseButton(0)) fire = false;
            if (Input.GetKeyDown(KeyCode.Q)) swapPressed = true;
            if (Input.GetKeyDown(KeyCode.R)) reloadPressed = true;
            if (Input.GetKeyDown(KeyCode.E)) pickPressed = true;
        }

        static bool AnyUiAt(Vector2 screenPos)
        {
            if (EventSystem.current == null) return false;
            var ped = new PointerEventData(EventSystem.current) { position = screenPos };
            var results = new List<RaycastResult>();
            EventSystem.current.RaycastAll(ped, results);
            return results.Count > 0;
        }

        static void MoveStickBase(Stick s, Vector2 screenPos)
        {
            // overlay canvas: canvas units -> screen px via scaleFactor
            float sf = canvas.scaleFactor;
            var rt = (RectTransform)canvas.transform;
            Vector2 local;
            RectTransformUtility.ScreenPointToLocalPointInRectangle(rt, screenPos, null, out local);
            s.baseRt.anchoredPosition = local;
        }

        static Vector2 Clamp(Vector2 v)
        {
            if (v.magnitude > 1f) return v.normalized;
            return v;
        }
    }
}
