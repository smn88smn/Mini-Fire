using System;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace MiniFire
{
    /// <summary>Shop with three tabs: gun skins, character sets, powers.
    /// Weapons themselves are picked up in matches (Mini Militia style).</summary>
    public class ShopUI : Screen
    {
        RectTransform tabs, content;
        int tab; // 0 skins 1 chars 2 powers
        Text mfcLabel, gemLabel;
        float refresh;

        public ShopUI(App app, Canvas canvas) : base(app, canvas) { }

        protected override void OnBuild()
        {
            var rt = (RectTransform)root.transform;
            var win = UIFactory.Rect(rt, "shop");
            win.StretchFull();
            UIFactory.Image(win, "bg", new Color(0.08f, 0.10f, 0.14f)).rectTransform.StretchFull();

            // header
            var header = UIFactory.Rect(win, "header");
            header.anchorMin = new Vector2(0, 1); header.anchorMax = new Vector2(1, 1);
            header.sizeDelta = new Vector2(0, 70);
            var title = UIFactory.Title(header, "SHOP", 34);
            title.rectTransform.anchoredPosition = new Vector2(0, -35);
            var back = UIFactory.Button(header, "<", UIFactory.ButtonBgRed, new Vector2(56, 48), app.ShowMenu, 28);
            back.transform.localPosition = new Vector3(-600, -35, 0);
            mfcLabel = UIFactory.Label(header, "", 22, UIFactory.TextMain, TextAnchor.MiddleRight, FontStyle.Bold);
            mfcLabel.rectTransform.anchorMin = Vector2.one; mfcLabel.rectTransform.anchorMax = Vector2.one;
            mfcLabel.rectTransform.anchoredPosition = new Vector2(-140, -35);
            gemLabel = UIFactory.Label(header, "", 22, UIFactory.TextMain, TextAnchor.MiddleRight, FontStyle.Bold);
            gemLabel.rectTransform.anchorMin = Vector2.one; gemLabel.rectTransform.anchorMax = Vector2.one;
            gemLabel.rectTransform.anchoredPosition = new Vector2(-30, -35);

            // tabs
            tabs = UIFactory.Rect(win, "tabs");
            tabs.anchorMin = new Vector2(0, 1); tabs.anchorMax = new Vector2(1, 1);
            tabs.sizeDelta = new Vector2(0, 56);
            tabs.anchoredPosition = new Vector2(0, -70);
            string[] names = { "GUN SKINS", "CHARACTERS", "POWERS" };
            for (int i = 0; i < 3; i++)
            {
                int idx = i;
                var b = UIFactory.Button(tabs, names[i], UIFactory.ButtonBg, new Vector2(220, 46), () => { tab = idx; Rebuild(); }, 20);
                b.transform.localPosition = new Vector3(-460 + i * 240, 0, 0);
            }

            // content scroll
            var scrollRoot = UIFactory.Rect(win, "scrollRoot");
            scrollRoot.anchorMin = new Vector2(0, 0); scrollRoot.anchorMax = new Vector2(1, 1);
            scrollRoot.offsetMin = new Vector2(40, 24); scrollRoot.offsetMax = new Vector2(-40, -140);
            var scroll = UIFactory.ScrollV(scrollRoot);
            content = scroll.content;

            Rebuild();
        }

        void Rebuild()
        {
            UIFactory.Clear(content);
            RefreshWallet();
            if (tab == 0) BuildSkins();
            else if (tab == 1) BuildChars();
            else BuildPowers();
        }

        void RefreshWallet()
        {
            mfcLabel.text = app.Profile.D.mfc + " MFC";
            gemLabel.text = app.Profile.D.gems + " Gems";
        }

        static string PriceText(string currency, int price) =>
            price <= 0 ? "FREE" : price + (currency == "mfc" ? " MFC" : " Gems");

        Color RarityColor(string r)
        {
            ColorUtility.TryParseHtmlString(GameConfig.RarityColors.TryGetValue(r, out var hex) ? hex : "#a0aabb", out var c);
            return c;
        }

        // ---------------- gun skins ----------------
        void BuildSkins()
        {
            foreach (var s in GameConfig.GunSkins)
            {
                bool owned = app.Profile.OwnsSkin(s.Id);
                string equippedOn = null;
                foreach (var w in GameConfig.WeaponOrder)
                    if (app.Profile.SkinFor(w) == s.Id) { equippedOn = w; break; }
                var row = UIFactory.Row(content, 74);
                // color chip
                ColorUtility.TryParseHtmlString(s.BaseHex, out var baseC);
                var chip = UIFactory.Image(row, "chip", baseC);
                chip.rectTransform.sizeDelta = new Vector2(56, 40);
                // name + rarity
                var nameCol = UIFactory.Rect(row, "names");
                nameCol.sizeDelta = new Vector2(330, 60);
                var n = UIFactory.Label(nameCol, s.Name, 22, RarityColor(s.Rarity), TextAnchor.MiddleLeft, FontStyle.Bold);
                n.rectTransform.StretchFull();
                n.rectTransform.offsetMin = new Vector2(6, 16);
                var r = UIFactory.Label(nameCol, s.Rarity.ToUpperInvariant(), 14, UIFactory.TextDim, TextAnchor.MiddleLeft);
                r.rectTransform.StretchFull();
                r.rectTransform.offsetMin = new Vector2(6, -4);
                // price / status
                var price = UIFactory.Label(row, owned ? "OWNED" : PriceText(s.Currency, s.Price), 20,
                    owned ? UIFactory.TextDim : s.Currency == "gem" ? Color.cyan : Color.yellow,
                    TextAnchor.MiddleRight, FontStyle.Bold);
                price.rectTransform.sizeDelta = new Vector2(150, 40);
                if (!owned)
                {
                    var buy = UIFactory.Button(row, "BUY", UIFactory.ButtonBgGreen, new Vector2(110, 46), () =>
                    {
                        if (app.Profile.BuySkin(s.Id))
                        { UIFactory.Toast(root.transform, "Bought " + s.Name + "!"); Rebuild(); }
                        else UIFactory.Toast(root.transform, "Not enough currency");
                    }, 20);
                }
                else if (equippedOn != null)
                {
                    var l = UIFactory.Label(row, "EQUIPPED", 16, UIFactory.Accent, TextAnchor.MiddleCenter, FontStyle.Bold);
                    l.rectTransform.sizeDelta = new Vector2(110, 40);
                }
                else
                {
                    var eq = UIFactory.Button(row, "EQUIP", UIFactory.ButtonBgBlue, new Vector2(110, 46), () =>
                    {
                        EquipSkinDialog(s.Id);
                    }, 18);
                }
            }
        }

        void EquipSkinDialog(string skinId)
        {
            var overlay = UIFactory.Panel(root.transform, "equip");
            var win = UIFactory.Rect(overlay, "win");
            win.sizeDelta = new Vector2(420, 480);
            var t = UIFactory.Title(win, "Equip on weapon", 26);
            t.rectTransform.anchoredPosition = new Vector2(0, -32);
            foreach (var w in GameConfig.WeaponOrder)
            {
                var wid = w;
                var b = UIFactory.Button(win, GameConfig.Weapon(w).Name, UIFactory.ButtonBg, new Vector2(300, 52), () =>
                {
                    app.Profile.EquipSkin(wid, skinId);
                    UnityEngine.Object.Destroy(overlay.gameObject);
                    Rebuild();
                }, 20);
                b.transform.localPosition = new Vector3(0, 60 - Array.IndexOf(GameConfig.WeaponOrder, wid) * 58, 0);
            }
        }

        // ---------------- characters ----------------
        void BuildChars()
        {
            foreach (var c in GameConfig.CharSkins)
            {
                bool owned = app.Profile.OwnsChar(c.Id);
                bool equipped = app.Profile.D.char_skin == c.Id;
                var row = UIFactory.Row(content, 84);
                var preview = UIFactory.ImageSprite(row, "preview", "Art/Chars/" + c.Id + "_idle");
                preview.rectTransform.sizeDelta = new Vector2(56, 64);
                var nameCol = UIFactory.Rect(row, "names");
                nameCol.sizeDelta = new Vector2(340, 70);
                var n = UIFactory.Label(nameCol, c.Name, 22, RarityColor(c.Rarity), TextAnchor.MiddleLeft, FontStyle.Bold);
                n.rectTransform.StretchFull(); n.rectTransform.offsetMin = new Vector2(6, 18);
                var r = UIFactory.Label(nameCol, c.Rarity.ToUpperInvariant(), 14, UIFactory.TextDim, TextAnchor.MiddleLeft);
                r.rectTransform.StretchFull(); r.rectTransform.offsetMin = new Vector2(6, -6);
                var price = UIFactory.Label(row, owned ? "OWNED" : PriceText(c.Currency, c.Price), 20,
                    owned ? UIFactory.TextDim : c.Currency == "gem" ? Color.cyan : Color.yellow,
                    TextAnchor.MiddleRight, FontStyle.Bold);
                price.rectTransform.sizeDelta = new Vector2(150, 40);
                if (!owned)
                {
                    UIFactory.Button(row, "BUY", UIFactory.ButtonBgGreen, new Vector2(110, 46), () =>
                    {
                        if (app.Profile.BuyChar(c.Id))
                        { UIFactory.Toast(root.transform, "Bought " + c.Name + "!"); Rebuild(); }
                        else UIFactory.Toast(root.transform, "Not enough currency");
                    }, 20);
                }
                else if (equipped)
                {
                    var l = UIFactory.Label(row, "EQUIPPED", 16, UIFactory.Accent, TextAnchor.MiddleCenter, FontStyle.Bold);
                    l.rectTransform.sizeDelta = new Vector2(110, 40);
                }
                else
                {
                    UIFactory.Button(row, "EQUIP", UIFactory.ButtonBgBlue, new Vector2(110, 46), () =>
                    {
                        app.Profile.EquipChar(c.Id);
                        Rebuild();
                    }, 18);
                }
            }
        }

        // ---------------- powers ----------------
        void BuildPowers()
        {
            foreach (var p in GameConfig.Powers)
            {
                int lvl = app.Profile.PowerLevel(p.Id);
                var cost = app.Profile.NextPowerCost(p.Id);
                var row = UIFactory.Row(content, 84);
                var nameCol = UIFactory.Rect(row, "names");
                nameCol.sizeDelta = new Vector2(460, 70);
                var n = UIFactory.Label(nameCol, p.Name, 22, UIFactory.TextMain, TextAnchor.MiddleLeft, FontStyle.Bold);
                n.rectTransform.StretchFull(); n.rectTransform.offsetMin = new Vector2(6, 22);
                var d = UIFactory.Label(nameCol, p.Desc, 15, UIFactory.TextDim, TextAnchor.MiddleLeft);
                d.rectTransform.StretchFull(); d.rectTransform.offsetMin = new Vector2(6, -10);
                // level pips
                var pips = UIFactory.Rect(row, "pips");
                pips.sizeDelta = new Vector2(150, 40);
                for (int i = 0; i < GameConfig.PowerMax; i++)
                {
                    var pip = UIFactory.Image(pips, "pip", i < lvl ? UIFactory.Accent : new Color(1, 1, 1, 0.15f));
                    pip.rectTransform.sizeDelta = new Vector2(22, 22);
                    pip.rectTransform.anchoredPosition = new Vector2(-50 + i * 30, 0);
                }
                if (cost != null)
                {
                    var price = UIFactory.Label(row, PriceText(cost.Item1, cost.Item2), 18,
                        cost.Item1 == "gem" ? Color.cyan : Color.yellow, TextAnchor.MiddleRight, FontStyle.Bold);
                    price.rectTransform.sizeDelta = new Vector2(140, 40);
                    UIFactory.Button(row, "UPGRADE", UIFactory.ButtonBgGreen, new Vector2(130, 46), () =>
                    {
                        if (app.Profile.BuyPower(p.Id))
                        { UIFactory.Toast(root.transform, p.Name + " level " + app.Profile.PowerLevel(p.Id) + "!"); Rebuild(); }
                        else UIFactory.Toast(root.transform, "Not enough currency");
                    }, 18);
                }
                else
                {
                    var l = UIFactory.Label(row, "MAXED", 20, UIFactory.Accent, TextAnchor.MiddleCenter, FontStyle.Bold);
                    l.rectTransform.sizeDelta = new Vector2(130, 40);
                }
            }
        }

        public override void Pump()
        {
            refresh += Time.unscaledDeltaTime;
            if (refresh > 0.5f) { refresh = 0; RefreshWallet(); }
        }
    }
}
