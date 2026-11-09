using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace MiniFire
{
    /// <summary>Spin Shop: pay 400 MFC or 20 gems per spin, win prizes (incl. gun levels).
    /// Also has the Telegram gem-code redemption.</summary>
    public class SpinShopUI : Screen
    {
        RectTransform wheel;
        Image wheelImg;
        Text resultLabel, mfcLabel, gemLabel, weaponLabel;
        InputField codeInput;
        float spinTime, spinDur, spinFrom, spinTo;
        bool spinning;
        int selWeapon;
        float refresh;

        public SpinShopUI(App app, Canvas canvas) : base(app, canvas) { }

        protected override void OnBuild()
        {
            var rt = (RectTransform)root.transform;
            var win = UIFactory.Rect(rt, "spinshop");
            win.StretchFull();
            UIFactory.Image(win, "bg", new Color(0.08f, 0.10f, 0.14f)).rectTransform.StretchFull();

            // header
            var header = UIFactory.Rect(win, "header");
            header.anchorMin = new Vector2(0, 1); header.anchorMax = new Vector2(1, 1);
            header.sizeDelta = new Vector2(0, 70);
            var title = UIFactory.Title(header, "SPIN SHOP", 34);
            title.rectTransform.anchoredPosition = new Vector2(0, -35);
            var back = UIFactory.Button(header, "<", UIFactory.ButtonBgRed, new Vector2(56, 48), app.ShowMenu, 28);
            back.transform.localPosition = new Vector3(-600, -35, 0);
            mfcLabel = UIFactory.Label(header, "", 22, UIFactory.TextMain, TextAnchor.MiddleRight, FontStyle.Bold);
            mfcLabel.rectTransform.anchorMin = Vector2.one; mfcLabel.rectTransform.anchorMax = Vector2.one;
            mfcLabel.rectTransform.anchoredPosition = new Vector2(-140, -35);
            gemLabel = UIFactory.Label(header, "", 22, UIFactory.TextMain, TextAnchor.MiddleRight, FontStyle.Bold);
            gemLabel.rectTransform.anchorMin = Vector2.one; gemLabel.rectTransform.anchorMax = Vector2.one;
            gemLabel.rectTransform.anchoredPosition = new Vector2(-30, -35);

            // left: wheel
            var left = UIFactory.Rect(win, "left");
            left.anchorMin = new Vector2(0, 0.5f); left.anchorMax = new Vector2(0.5f, 1f);
            left.offsetMin = new Vector2(60, -130); left.offsetMax = new Vector2(-20, -90);

            wheel = UIFactory.Rect(left, "wheel");
            wheel.anchorMin = new Vector2(0.5f, 0.5f); wheel.anchorMax = new Vector2(0.5f, 0.5f);
            wheel.sizeDelta = new Vector2(340, 340);
            wheelImg = wheel.gameObject.AddComponent<Image>();
            wheelImg.sprite = Resources.Load<Sprite>("Art/icon_spin");
            wheelImg.raycastTarget = false;
            var hub = UIFactory.Image(wheel, "hub", new Color(0.10f, 0.11f, 0.15f));
            hub.rectTransform.sizeDelta = new Vector2(90, 90);
            var hubTxt = UIFactory.Label(hub.rectTransform, "SPIN", 22, UIFactory.TextMain, TextAnchor.MiddleCenter, FontStyle.Bold);
            hubTxt.rectTransform.StretchFull();
            // pointer
            var ptr = UIFactory.Image(left, "ptr", Color.white);
            ptr.rectTransform.sizeDelta = new Vector2(36, 18);
            ptr.rectTransform.anchorMin = new Vector2(0.5f, 1f); ptr.rectTransform.anchorMax = new Vector2(0.5f, 1f);
            ptr.rectTransform.anchoredPosition = new Vector2(0, -10);
            var ptrImg = ptr;
            var tri = new GameObject("tri", typeof(RectTransform));
            tri.transform.SetParent(ptr.rectTransform, false);
            var triImg = tri.AddComponent<Image>();
            triImg.color = Color.white;
            triImg.raycastTarget = false;

            resultLabel = UIFactory.Label(left, "", 26, UIFactory.Accent, TextAnchor.MiddleCenter, FontStyle.Bold);
            resultLabel.rectTransform.anchorMin = new Vector2(0.5f, 0); resultLabel.rectTransform.anchorMax = new Vector2(0.5f, 0);
            resultLabel.rectTransform.anchoredPosition = new Vector2(0, 130);

            var spinMfc = UIFactory.Button(left, "SPIN  (400 MFC)", UIFactory.ButtonBgGold, new Vector2(220, 56), () => DoSpin("mfc"), 22);
            spinMfc.transform.localPosition = new Vector3(0, 70, 0);
            var spinGem = UIFactory.Button(left, "SPIN  (20 Gems)", UIFactory.ButtonBgBlue, new Vector2(220, 56), () => DoSpin("gem"), 22);
            spinGem.transform.localPosition = new Vector3(0, 8, 0);

            // weapon selector (prize applies to this gun's level)
            var wsel = UIFactory.Rect(left, "wsel");
            wsel.sizeDelta = new Vector2(420, 50);
            wsel.transform.localPosition = new Vector3(0, -54, 0);
            weaponLabel = UIFactory.Label(wsel, "", 20, UIFactory.TextMain, TextAnchor.MiddleCenter);
            weaponLabel.rectTransform.StretchFull();
            weaponLabel.text = "Gun: " + GameConfig.Weapon(GameConfig.WeaponOrder[selWeapon]).Name;
            var prev = UIFactory.Button(wsel, "<", UIFactory.ButtonBg, new Vector2(50, 44), () => CycleWeapon(-1), 24);
            prev.transform.localPosition = new Vector3(-230, 0, 0);
            var next = UIFactory.Button(wsel, ">", UIFactory.ButtonBg, new Vector2(50, 44), () => CycleWeapon(1), 24);
            next.transform.localPosition = new Vector3(230, 0, 0);

            // right: prizes + redeem
            var right = UIFactory.Rect(win, "right");
            right.anchorMin = new Vector2(0.5f, 0); right.anchorMax = new Vector2(1, 1);
            right.offsetMin = new Vector2(20, 40); right.offsetMax = new Vector2(-60, -90);

            var prizesTitle = UIFactory.Title(right, "PRIZES", 26);
            prizesTitle.rectTransform.anchorMin = new Vector2(0.5f, 1f); prizesTitle.rectTransform.anchorMax = new Vector2(0.5f, 1f);
            prizesTitle.rectTransform.anchoredPosition = new Vector2(0, -20);
            var scroll = UIFactory.ScrollV(right);
            scroll.rect.transform.SetParent(right, false);
            ((RectTransform)scroll.rect.transform).StretchFull();
            ((RectTransform)scroll.rect.transform).offsetMax = new Vector2(0, -60);
            foreach (var p in GameConfig.SpinPrizes)
            {
                string desc;
                switch ((int)p[1])
                {
                    case GameConfig.SpinKindMfc: desc = "+" + (int)p[2] + " MFC"; break;
                    case GameConfig.SpinKindGems: desc = "+" + (int)p[2] + " Gems"; break;
                    case GameConfig.SpinKindGunLvl: desc = "+1 level for selected gun"; break;
                    case GameConfig.SpinKindGunLvl2: desc = "+2 levels for selected gun"; break;
                    default: desc = "?"; break;
                }
                int weight = Mathf.RoundToInt(p[0]);
                var row = UIFactory.Row(scroll.content, 52);
                var l = UIFactory.Label(row, desc, 20, UIFactory.TextMain, TextAnchor.MiddleLeft);
                l.rectTransform.StretchFull(); l.rectTransform.offsetMin = new Vector2(10, 0);
                var w = UIFactory.Label(row, weight + "%", 18, UIFactory.TextDim, TextAnchor.MiddleRight);
                w.rectTransform.sizeDelta = new Vector2(80, 40);
            }

            // redeem code
            var redeem = UIFactory.Rect(right, "redeem");
            redeem.anchorMin = new Vector2(0, 0); redeem.anchorMax = new Vector2(1, 0);
            redeem.sizeDelta = new Vector2(0, 90);
            redeem.anchoredPosition = Vector2.zero;
            var rTitle = UIFactory.Label(redeem, "Redeem gem code (Telegram shop)", 18, UIFactory.TextDim, TextAnchor.MiddleLeft);
            rTitle.rectTransform.StretchFull(); rTitle.rectTransform.offsetMin = new Vector2(4, 46);
            codeInput = UIFactory.Input(redeem, "MF-XXXXXX-XXXXX-100");
            codeInput.transform.localPosition = new Vector3(-70, 14, 0);
            var redeemBtn = UIFactory.Button(redeem, "REDEEM", UIFactory.ButtonBgGreen, new Vector2(120, 46), DoRedeem, 18);
            redeemBtn.transform.localPosition = new Vector3(140, 14, 0);

            RefreshWallet();
        }

        void RefreshWallet()
        {
            mfcLabel.text = app.Profile.D.mfc + " MFC";
            gemLabel.text = app.Profile.D.gems + " Gems";
        }

        void CycleWeapon(int dir)
        {
            selWeapon = (selWeapon + dir + GameConfig.WeaponOrder.Length) % GameConfig.WeaponOrder.Length;
            weaponLabel.text = "Gun: " + GameConfig.Weapon(GameConfig.WeaponOrder[selWeapon]).Name;
        }

        void DoSpin(string currency)
        {
            if (spinning) return;
            int price = currency == "mfc" ? GameConfig.SpinCostMfc : GameConfig.SpinCostGem;
            if (!app.Profile.CanAfford(currency, price))
            {
                UIFactory.Toast(root.transform, "Not enough " + (currency == "mfc" ? "MFC" : "gems") + "!");
                return;
            }
            if (currency == "mfc") app.Profile.D.mfc -= price; else app.Profile.D.gems -= price;
            app.Profile.Save();
            RefreshWallet();

            // pick prize by weight
            float total = 0;
            foreach (var p in GameConfig.SpinPrizes) total += p[0];
            float roll = UnityEngine.Random.value * total;
            int hit = 0;
            for (int i = 0; i < GameConfig.SpinPrizes.Length; i++)
            {
                roll -= GameConfig.SpinPrizes[i][0];
                if (roll <= 0) { hit = i; break; }
            }
            // 6 slices of 60deg, pointer at top
            spinFrom = wheel.eulerAngles.z;
            spinTo = spinFrom + 360f * 4 + UnityEngine.Random.value * 360f;
            // nudge so the winning slice lands under the pointer
            float sliceCenter = 90f - (hit + 0.5f) * 60f; // slice i spans [i*60, (i+1)*60) from top going clockwise? art starts at 3 o'clock
            spinTo = Mathf.Round(spinTo / 60f) * 60f + (sliceCenter - spinFrom) % 60f + UnityEngine.Random.Range(-20f, 20f);
            spinDur = 3.2f;
            spinTime = 0;
            spinning = true;
            pendingPrize = hit;
            resultLabel.text = "";
        }

        int pendingPrize;

        void GrantPrize(int hit)
        {
            var p = GameConfig.SpinPrizes[hit];
            string wid = GameConfig.WeaponOrder[selWeapon];
            switch ((int)p[1])
            {
                case GameConfig.SpinKindMfc:
                    app.Profile.AddCurrency((int)p[2], 0);
                    resultLabel.text = "+" + (int)p[2] + " MFC!";
                    break;
                case GameConfig.SpinKindGems:
                    app.Profile.AddCurrency(0, (int)p[2]);
                    resultLabel.text = "+" + (int)p[2] + " Gems!";
                    Sfx.Play("sfx_gem");
                    break;
                case GameConfig.SpinKindGunLvl:
                {
                    int nl = app.Profile.AddGunLevels(wid, 1);
                    resultLabel.text = GameConfig.Weapon(wid).Name + " -> Lv " + nl;
                    Sfx.Play("sfx_levelup");
                    break;
                }
                case GameConfig.SpinKindGunLvl2:
                {
                    int nl = app.Profile.AddGunLevels(wid, 2);
                    resultLabel.text = GameConfig.Weapon(wid).Name + " -> Lv " + nl;
                    Sfx.Play("sfx_levelup");
                    break;
                }
            }
            RefreshWallet();
        }

        void DoRedeem()
        {
            string code = codeInput != null ? codeInput.text : "";
            int gems = app.Profile.RedeemCode(code);
            if (gems > 0)
            {
                UIFactory.Toast(root.transform, "+" + gems + " gems redeemed!");
                Sfx.Play("sfx_redeem");
                codeInput.text = "";
                RefreshWallet();
            }
            else if (gems == -2) UIFactory.Toast(root.transform, "Code already used");
            else UIFactory.Toast(root.transform, "Invalid code");
        }

        public override void Pump()
        {
            refresh += Time.unscaledDeltaTime;
            if (refresh > 0.5f && !spinning) { refresh = 0; RefreshWallet(); }

            if (spinning)
            {
                spinTime += Time.unscaledDeltaTime;
                float t = Mathf.Clamp01(spinTime / spinDur);
                float e = 1f - Mathf.Pow(1f - t, 3); // ease out cubic
                float z = Mathf.Lerp(spinFrom, spinTo, e);
                wheel.rotation = Quaternion.Euler(0, 0, z);
                if (Time.frameCount % 6 == 0) Sfx.Play("sfx_spin_tick");
                if (t >= 1f)
                {
                    spinning = false;
                    GrantPrize(pendingPrize);
                }
            }
        }
    }
}
