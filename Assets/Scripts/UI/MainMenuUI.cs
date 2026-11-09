using System;
using UnityEngine;
using UnityEngine.UI;

namespace MiniFire
{
    public class MainMenuUI : Screen
    {
        Text mfcLabel, gemLabel, nameLabel;
        float walletRefresh;

        public MainMenuUI(App app, Canvas canvas) : base(app, canvas) { }

        protected override void OnBuild()
        {
            App.EnsureCamera();
            var rt = (RectTransform)root.transform;

            // background
            var bg = UIFactory.Image(rt, "bg", new Color(0.10f, 0.12f, 0.17f));
            bg.rectTransform.StretchFull();
            var art = UIFactory.ImageSprite(rt, "bg_art", "Art/bg_warzone");
            art.rectTransform.StretchFull();
            art.color = new Color(1, 1, 1, 0.35f);

            // ---------- top bar ----------
            var top = UIFactory.Rect(rt, "topbar");
            top.anchorMin = new Vector2(0, 1); top.anchorMax = new Vector2(1, 1);
            top.pivot = new Vector2(0.5f, 1f); top.sizeDelta = new Vector2(0, 72);

            var avatar = UIFactory.ImageSprite(top, "avatar", "Art/Chars/" + app.Profile.D.char_skin + "_idle");
            avatar.rectTransform.sizeDelta = new Vector2(56, 56);
            avatar.rectTransform.anchoredPosition = new Vector2(40, -36);

            nameLabel = UIFactory.Label(top, app.Profile.D.player_name, 24, UIFactory.TextMain,
                TextAnchor.MiddleLeft, FontStyle.Bold);
            nameLabel.rectTransform.anchorMin = new Vector2(0, 1); nameLabel.rectTransform.anchorMax = new Vector2(0, 1);
            nameLabel.rectTransform.anchoredPosition = new Vector2(78, -22);

            var editBtn = UIFactory.Button(top, "Rename", UIFactory.ButtonBg, new Vector2(96, 34), RenameDialog, 16);
            editBtn.transform.localPosition = new Vector3(150, -22, 0);

            var coinIcon = UIFactory.ImageSprite(top, "coin", "Art/icon_coin");
            coinIcon.rectTransform.sizeDelta = new Vector2(34, 34);
            coinIcon.rectTransform.anchorMin = new Vector2(1, 1); coinIcon.rectTransform.anchorMax = new Vector2(1, 1);
            coinIcon.rectTransform.anchoredPosition = new Vector2(-260, -36);
            mfcLabel = UIFactory.Label(top, app.Profile.D.mfc.ToString(), 24, UIFactory.TextMain, TextAnchor.MiddleLeft, FontStyle.Bold);
            mfcLabel.rectTransform.anchorMin = new Vector2(1, 1); mfcLabel.rectTransform.anchorMax = new Vector2(1, 1);
            mfcLabel.rectTransform.anchoredPosition = new Vector2(-120, -36);

            var gemIcon = UIFactory.ImageSprite(top, "gem", "Art/icon_gem");
            gemIcon.rectTransform.sizeDelta = new Vector2(34, 34);
            gemIcon.rectTransform.anchorMin = new Vector2(1, 1); gemIcon.rectTransform.anchorMax = new Vector2(1, 1);
            gemIcon.rectTransform.anchoredPosition = new Vector2(-80, -36);
            gemLabel = UIFactory.Label(top, app.Profile.D.gems.ToString(), 24, UIFactory.TextMain, TextAnchor.MiddleLeft, FontStyle.Bold);
            gemLabel.rectTransform.anchorMin = new Vector2(1, 1); gemLabel.rectTransform.anchorMax = new Vector2(1, 1);
            gemLabel.rectTransform.anchoredPosition = new Vector2(30, -36);

            // ---------- title ----------
            var title = UIFactory.Label(rt, "MINI FIRE", 84, UIFactory.TextMain, TextAnchor.MiddleCenter, FontStyle.Bold);
            title.rectTransform.anchorMin = new Vector2(0.5f, 1f); title.rectTransform.anchorMax = new Vector2(0.5f, 1f);
            title.rectTransform.anchoredPosition = new Vector2(0, -150);
            title.color = new Color(1f, 0.55f, 0.15f);
            var sub = UIFactory.Label(rt, "UNITY EDITION", 22, UIFactory.TextDim, TextAnchor.MiddleCenter, FontStyle.Bold);
            sub.rectTransform.anchorMin = new Vector2(0.5f, 1f); sub.rectTransform.anchorMax = new Vector2(0.5f, 1f);
            sub.rectTransform.anchoredPosition = new Vector2(0, -205);

            // ---------- main buttons ----------
            void MenuButton(string text, string icon, Action onClick, int row)
            {
                var b = UIFactory.Button(rt, text, UIFactory.ButtonBg, new Vector2(420, 76), onClick, 26);
                b.transform.localPosition = new Vector3(row % 2 == 0 ? -230 : 230, 60 - (row / 2) * 96, 0);
                var ic = UIFactory.ImageSprite(b.transform, "ic", "Art/icon_" + icon);
                ic.rectTransform.sizeDelta = new Vector2(40, 40);
                ic.rectTransform.anchoredPosition = new Vector2(-160, 0);
            }
            MenuButton("PRACTICE", "play", () => app.OpenLobbyPractice(), 0);
            MenuButton("ONLINE", "online", () => app.OpenLobbyOnline(), 1);
            MenuButton("SHOP", "cart", () => app.OpenShop(), 2);
            MenuButton("SPIN SHOP", "spin", () => app.OpenSpinShop(), 3);
            MenuButton("ACCOUNT", "profile", () => app.OpenAccount(), 4);
            MenuButton("GEM SHOP", "gem", () =>
            {
                Application.OpenURL(GameConfig.TelegramShopUrl);
                UIFactory.Toast(rt, "Telegram gem shop opened in your browser");
            }, 5);

            // ---------- footer: stats + volume ----------
            var stats = UIFactory.Label(rt,
                $"Kills {app.Profile.D.total_kills}   Deaths {app.Profile.D.total_deaths}   " +
                $"Matches {app.Profile.D.matches_played}   Wins {app.Profile.D.wins}", 18,
                UIFactory.TextDim, TextAnchor.MiddleCenter);
            stats.rectTransform.anchorMin = new Vector2(0.5f, 0); stats.rectTransform.anchorMax = new Vector2(0.5f, 0);
            stats.rectTransform.anchoredPosition = new Vector2(0, 46);

            var volRow = UIFactory.Rect(rt, "vol");
            volRow.anchorMin = new Vector2(0.5f, 0); volRow.anchorMax = new Vector2(0.5f, 0);
            volRow.sizeDelta = new Vector2(340, 30);
            volRow.anchoredPosition = new Vector2(0, 14);
            var volLbl = UIFactory.Label(volRow, "SFX", 18, UIFactory.TextDim, TextAnchor.MiddleLeft);
            volLbl.rectTransform.StretchFull();
            var slider = volRow.gameObject.AddComponent<Slider>();
            var fill = UIFactory.Image(volRow, "fill", UIFactory.Accent);
            fill.rectTransform.StretchFull();
            var handle = UIFactory.Image(volRow, "handle", Color.white);
            handle.rectTransform.sizeDelta = new Vector2(24, 28);
            handle.raycastTarget = true;
            slider.fillRect = fill.rectTransform;
            slider.handleRect = handle.rectTransform;
            slider.targetGraphic = handle;
            slider.direction = Slider.Direction.LeftToRight;
            slider.minValue = 0; slider.maxValue = 1;
            slider.value = app.Profile.D.sfx_volume;
            slider.onValueChanged.AddListener(v =>
            {
                app.Profile.D.sfx_volume = v;
                app.Profile.Save();
                Sfx.SetVolume(v);
            });

            var ver = UIFactory.Label(rt, "v" + GameConfig.GameVersion + ".0", 14, UIFactory.TextDim, TextAnchor.LowerRight);
            ver.rectTransform.anchorMin = Vector2.one; ver.rectTransform.anchorMax = Vector2.one;
            ver.rectTransform.anchoredPosition = new Vector2(-14, 12);
        }

        void RenameDialog()
        {
            var overlay = UIFactory.Panel(root.transform, "rename");
            var win = UIFactory.Rect(overlay, "win");
            win.sizeDelta = new Vector2(480, 200);
            var t = UIFactory.Title(win, "Player name", 28);
            t.rectTransform.anchoredPosition = new Vector2(0, -34);
            var input = UIFactory.Input(win, "Enter name...");
            input.transform.localPosition = new Vector3(0, 10, 0);
            input.text = app.Profile.D.player_name;
            input.characterLimit = 16;
            var ok = UIFactory.Button(win, "SAVE", UIFactory.ButtonBgGreen, new Vector2(160, 48), () =>
            {
                if (!string.IsNullOrEmpty(input.text))
                {
                    app.Profile.D.player_name = input.text.Trim();
                    app.Profile.Save();
                    nameLabel.text = app.Profile.D.player_name;
                }
                UnityEngine.Object.Destroy(overlay.gameObject);
            });
            ok.transform.localPosition = new Vector3(0, -68, 0);
        }

        public override void Pump()
        {
            walletRefresh += Time.unscaledDeltaTime;
            if (walletRefresh > 0.5f)
            {
                walletRefresh = 0;
                mfcLabel.text = app.Profile.D.mfc.ToString();
                gemLabel.text = app.Profile.D.gems.ToString();
            }
        }
    }
}
