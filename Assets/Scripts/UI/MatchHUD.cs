using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace MiniFire
{
    /// <summary>In-match HUD: HP/fuel bars, ammo, weapon slots, timer, killfeed,
    /// touch controls, pause menu and the results screen.</summary>
    public class MatchHUD : Screen
    {
        Text hpText, ammoText, timerText, slotText, deadText;
        Image hpFill, fuelFill;
        RectTransform killfeed, deadOverlay, pauseOverlay, resultsOverlay;
        readonly List<Text> feedEntries = new List<Text>();
        float refresh;

        public MatchHUD(App app, Canvas canvas) : base(app, canvas) { }

        protected override void OnBuild()
        {
            var rt = (RectTransform)root.transform;
            var m = MatchRunner.I;

            // ---------- top bar: timer ----------
            var timerBg = UIFactory.Image(rt, "timerBg", new Color(0, 0, 0, 0.5f));
            timerBg.rectTransform.anchorMin = new Vector2(0.5f, 1); timerBg.rectTransform.anchorMax = new Vector2(0.5f, 1);
            timerBg.rectTransform.anchoredPosition = new Vector2(0, -30);
            timerBg.rectTransform.sizeDelta = new Vector2(140, 44);
            timerText = UIFactory.Label(timerBg.rectTransform, "3:00", 26, UIFactory.TextMain, TextAnchor.MiddleCenter, FontStyle.Bold);
            timerText.rectTransform.StretchFull();

            // killfeed (top-left)
            killfeed = UIFactory.Rect(rt, "killfeed");
            killfeed.anchorMin = new Vector2(0, 1); killfeed.anchorMax = new Vector2(0, 1);
            killfeed.sizeDelta = new Vector2(520, 200);
            killfeed.anchoredPosition = new Vector2(280, -30);

            // ---------- bottom-left: HP + fuel ----------
            var bars = UIFactory.Rect(rt, "bars");
            bars.anchorMin = new Vector2(0, 0); bars.anchorMax = new Vector2(0, 0);
            bars.sizeDelta = new Vector2(320, 90);
            bars.anchoredPosition = new Vector2(30, 60);

            var hpBg = UIFactory.Image(bars, "hpBg", new Color(0, 0, 0, 0.55f));
            hpBg.rectTransform.sizeDelta = new Vector2(300, 26); hpBg.rectTransform.anchoredPosition = new Vector2(150, 70);
            hpFill = UIFactory.Image(hpBg.rectTransform, "hpFill", Color.green);
            hpFill.rectTransform.StretchFull();
            hpFill.rectTransform.offsetMin = new Vector2(3, 3); hpFill.rectTransform.offsetMax = new Vector2(-3, -3);
            hpText = UIFactory.Label(hpBg.rectTransform, "300", 17, UIFactory.TextMain, TextAnchor.MiddleCenter, FontStyle.Bold);
            hpText.rectTransform.StretchFull();

            var fuelBg = UIFactory.Image(bars, "fuelBg", new Color(0, 0, 0, 0.55f));
            fuelBg.rectTransform.sizeDelta = new Vector2(300, 16); fuelBg.rectTransform.anchoredPosition = new Vector2(150, 46);
            fuelFill = UIFactory.Image(fuelBg.rectTransform, "fuelFill", new Color(0.4f, 0.8f, 1f));
            fuelFill.rectTransform.StretchFull();
            fuelFill.rectTransform.offsetMin = new Vector2(2, 2); fuelFill.rectTransform.offsetMax = new Vector2(-2, -2);
            var fuelLbl = UIFactory.Label(bars, "JET", 14, UIFactory.TextDim, TextAnchor.LowerLeft);
            fuelLbl.rectTransform.anchoredPosition = new Vector2(4, 26);

            // ---------- bottom-right: ammo + weapon ----------
            var ammoBox = UIFactory.Rect(rt, "ammo");
            ammoBox.anchorMin = new Vector2(1, 0); ammoBox.anchorMax = new Vector2(1, 0);
            ammoBox.sizeDelta = new Vector2(300, 90);
            ammoBox.anchoredPosition = new Vector2(-190, 130);
            ammoText = UIFactory.Label(ammoBox, "32 / 32", 34, UIFactory.TextMain, TextAnchor.MiddleRight, FontStyle.Bold);
            ammoText.rectTransform.StretchFull();
            slotText = UIFactory.Label(ammoBox, "", 18, UIFactory.TextDim, TextAnchor.LowerRight);
            slotText.rectTransform.StretchFull();
            slotText.rectTransform.offsetMax = new Vector2(0, 6);

            // ---------- dead overlay ----------
            deadOverlay = UIFactory.Rect(rt, "dead");
            deadOverlay.StretchFull();
            UIFactory.Image(deadOverlay, "bg", new Color(0.4f, 0, 0, 0.35f)).rectTransform.StretchFull();
            deadText = UIFactory.Label(deadOverlay, "RESPAWNING...", 40, UIFactory.TextMain, TextAnchor.MiddleCenter, FontStyle.Bold);
            deadText.rectTransform.StretchFull();
            deadOverlay.gameObject.SetActive(false);

            // ---------- pause overlay ----------
            pauseOverlay = UIFactory.Rect(rt, "pause");
            pauseOverlay.StretchFull();
            UIFactory.Image(pauseOverlay, "bg", new Color(0, 0, 0, 0.7f)).rectTransform.StretchFull();
            var pTitle = UIFactory.Title(pauseOverlay, "PAUSED", 48);
            pTitle.rectTransform.anchoredPosition = new Vector2(0, 120);
            var resume = UIFactory.Button(pauseOverlay, "RESUME", UIFactory.ButtonBgGreen, new Vector2(280, 64), HidePause, 26);
            resume.transform.localPosition = new Vector3(0, 20, 0);
            var leave = UIFactory.Button(pauseOverlay, "LEAVE MATCH", UIFactory.ButtonBgRed, new Vector2(280, 64),
                () => app.Match.LeaveMatch(), 26);
            leave.transform.localPosition = new Vector3(0, -60, 0);
            pauseOverlay.gameObject.SetActive(false);

            // ---------- results overlay ----------
            resultsOverlay = UIFactory.Rect(rt, "results");
            resultsOverlay.StretchFull();
            UIFactory.Image(resultsOverlay, "bg", new Color(0, 0, 0, 0.8f)).rectTransform.StretchFull();
            resultsOverlay.gameObject.SetActive(false);

            // touch controls on top
            TouchInput.Create(canvas, this);

            // events
            if (m != null)
            {
                m.KillFeed -= OnKillFeed;
                m.KillFeed += OnKillFeed;
                m.MatchEnded -= OnMatchEnded;
                m.MatchEnded += OnMatchEnded;
                m.LocalDied -= OnLocalDied;
                m.LocalDied += OnLocalDied;
                m.LocalRespawned -= OnLocalRespawned;
                m.LocalRespawned += OnLocalRespawned;
            }
        }

        protected override void OnClose()
        {
            TouchInput.Destroy();
            var m = MatchRunner.I;
            if (m != null)
            {
                m.KillFeed -= OnKillFeed;
                m.MatchEnded -= OnMatchEnded;
                m.LocalDied -= OnLocalDied;
                m.LocalRespawned -= OnLocalRespawned;
            }
        }

        public void ShowPause() { if (pauseOverlay != null) pauseOverlay.gameObject.SetActive(true); }
        void HidePause() { if (pauseOverlay != null) pauseOverlay.gameObject.SetActive(false); }

        void OnKillFeed(string msg)
        {
            var t = UIFactory.Label(killfeed, msg, 18, UIFactory.TextDim, TextAnchor.UpperLeft);
            t.rectTransform.anchorMin = new Vector2(0, 1); t.rectTransform.anchorMax = new Vector2(0, 1);
            t.rectTransform.anchoredPosition = new Vector2(0, -feedEntries.Count * 26);
            t.name = "feed_" + Time.frameCount;
            feedEntries.Add(t);
            if (feedEntries.Count > 5)
            {
                var old = feedEntries[0];
                feedEntries.RemoveAt(0);
                if (old != null) UnityEngine.Object.Destroy(old.gameObject);
            }
            // shift up
            for (int i = 0; i < feedEntries.Count; i++)
                if (feedEntries[i] != null)
                    feedEntries[i].rectTransform.anchoredPosition = new Vector2(0, -i * 26);
        }

        void OnLocalDied() { deadOverlay.gameObject.SetActive(true); }
        void OnLocalRespawned() { deadOverlay.gameObject.SetActive(false); }

        void OnMatchEnded(List<PlayerEntity> ordered)
        {
            deadOverlay.gameObject.SetActive(false);
            pauseOverlay.gameObject.SetActive(false);
            TouchInput.Destroy();
            resultsOverlay.gameObject.SetActive(true);
            UIFactory.Clear(resultsOverlay);

            var local = app.Match != null ? app.Match.LocalPlayer : null;
            bool won = local != null && ordered.Count > 0 && ordered[0].id == local.id;
            var title = UIFactory.Title(resultsOverlay, won ? "VICTORY" : "MATCH OVER", 52,
                won ? new Color(0.5f, 1f, 0.5f) : UIFactory.TextMain);
            title.rectTransform.anchorMin = new Vector2(0.5f, 1); title.rectTransform.anchorMax = new Vector2(0.5f, 1);
            title.rectTransform.anchoredPosition = new Vector2(0, -80);

            // scoreboard
            var board = UIFactory.Rect(resultsOverlay, "board");
            board.sizeDelta = new Vector2(560, 330);
            int rank = 1;
            foreach (var p in ordered.Take(10))
            {
                var row = UIFactory.Row(board, 34);
                var l = UIFactory.Label(row,
                    $"{rank++}.  {p.info.name}{(p.isBot ? " [BOT]" : "")}   {p.kills} kills / {p.deaths} deaths",
                    18, p.id == (local != null ? local.id : -1) ? UIFactory.Accent : UIFactory.TextMain,
                    TextAnchor.MiddleLeft, p.id == (local != null ? local.id : -1) ? FontStyle.Bold : FontStyle.Normal);
                l.rectTransform.StretchFull(); l.rectTransform.offsetMin = new Vector2(10, 0);
            }

            // rewards
            int mfc = GameConfig.RewardMfcMatch + app.Match.LocalKills * GameConfig.RewardMfcPerKill;
            int gems = GameConfig.RewardGemMatch + app.Match.LocalKills / GameConfig.RewardGemPerKills;
            if (won) { mfc += GameConfig.RewardMfcWin; gems += GameConfig.RewardGemWin; }
            var rewards = UIFactory.Label(resultsOverlay,
                $"Kills {app.Match.LocalKills}    Deaths {app.Match.LocalDeaths}\n+{mfc} MFC    +{gems} Gems",
                24, UIFactory.Accent, TextAnchor.MiddleCenter, FontStyle.Bold);
            rewards.rectTransform.anchorMin = new Vector2(0.5f, 0); rewards.rectTransform.anchorMax = new Vector2(0.5f, 0);
            rewards.rectTransform.anchoredPosition = new Vector2(0, 150);

            var back = UIFactory.Button(resultsOverlay, "BACK TO MENU", UIFactory.ButtonBgGreen, new Vector2(300, 64),
                () => { CloudService.AutoSync(); app.ShowMenu(); }, 26);
            back.transform.localPosition = new Vector3(0, 60, 0);

            CloudService.AutoSync();
        }

        public override void Pump()
        {
            var m = app.Match;
            if (m == null) return;
            TouchInput.Pump();
            refresh += Time.unscaledDeltaTime;
            if (refresh < 0.1f) return;
            refresh = 0;

            var p = m.LocalPlayer;
            if (p != null)
            {
                float frac = Mathf.Clamp01(p.hp / p.maxHp);
                hpFill.rectTransform.anchorMax = new Vector2(frac, 1);
                hpFill.color = frac > 0.5f ? Color.green : frac > 0.25f ? Color.yellow : Color.red;
                hpText.text = Mathf.CeilToInt(Mathf.Max(0, p.hp)) + " / " + Mathf.CeilToInt(p.maxHp);
                float fuel = Mathf.Clamp01(p.fuel);
                fuelFill.rectTransform.anchorMax = new Vector2(fuel, 1);
                var w = GameConfig.Weapon(p.Weapon);
                int mag = p.MagSize(p.slot, null);
                ammoText.text = p.reloading > 0 ? "RELOADING" : p.ammo[p.slot] + " / " + mag;
                int lvl = p.GunLevel;
                slotText.text = w.Name + "  Lv" + lvl + (lvl >= GameConfig.GunLevelMax ? "  FIRE!" : "")
                    + (p.dual[p.slot] ? "  x2" : "") + "   [slot " + (p.slot + 1) + "]";
            }

            float t = m.MatchTimeLeft;
            timerText.text = Mathf.FloorToInt(t / 60) + ":" + Mathf.FloorToInt(t % 60).ToString("00");
            if (t < 30) timerText.color = Color.red; else timerText.color = UIFactory.TextMain;

            if (deadOverlay.gameObject.activeSelf && p != null && !p.alive)
                deadText.text = "RESPAWNING IN " + Mathf.CeilToInt(p.respawnT) + "...";
        }
    }
}
