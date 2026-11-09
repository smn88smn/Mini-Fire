using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace MiniFire
{
    /// <summary>Lobby: practice mode (offline + bots) or online (host/join, up to 16 players).
    /// Host owns map/mode/time/bot settings; everyone picks a color and sees the player list.</summary>
    public class LobbyUI : Screen
    {
        readonly bool online;
        RectTransform entryCard, lobbyCard, playerList, colorRow, hostSettings;
        Text lobbyStatus, countText;
        InputField ipInput;
        readonly List<GameObject> foundRooms = new List<GameObject>();
        RectTransform foundRoomsList;
        float refresh;

        public LobbyUI(App app, Canvas canvas, bool online) : base(app, canvas)
        {
            this.online = online;
        }

        protected override void OnBuild()
        {
            var rt = (RectTransform)root.transform;
            var win = UIFactory.Rect(rt, "lobby");
            win.StretchFull();
            UIFactory.Image(win, "bg", new Color(0.08f, 0.10f, 0.14f)).rectTransform.StretchFull();

            var header = UIFactory.Rect(win, "header");
            header.anchorMin = new Vector2(0, 1); header.anchorMax = new Vector2(1, 1);
            header.sizeDelta = new Vector2(0, 70);
            var title = UIFactory.Title(header, online ? "ONLINE MULTIPLAYER" : "PRACTICE VS BOTS", 32);
            title.rectTransform.anchoredPosition = new Vector2(0, -35);
            var back = UIFactory.Button(header, "<", UIFactory.ButtonBgRed, new Vector2(56, 48), OnBack, 28);
            back.transform.localPosition = new Vector3(-600, -35, 0);

            // ---------- entry card (online only): host / join ----------
            entryCard = UIFactory.Rect(win, "entry");
            entryCard.sizeDelta = new Vector2(760, 460);
            var hostBtn = UIFactory.Button(entryCard, "CREATE ROOM", UIFactory.ButtonBgGreen, new Vector2(340, 70),
                () => { try { NetSession.I.HostGame(); OnEnteredLobby(); } catch { UIFactory.Toast(root.transform, "Could not bind port 7777"); } }, 26);
            hostBtn.transform.localPosition = new Vector3(0, 140, 0);
            ipInput = UIFactory.Input(entryCard, "Host IP address (e.g. 192.168.1.5)");
            ipInput.transform.localPosition = new Vector3(0, 40, 0);
            ipInput.text = app.Profile.D.last_join_ip;
            var joinBtn = UIFactory.Button(entryCard, "JOIN ROOM", UIFactory.ButtonBgBlue, new Vector2(340, 70), () =>
            {
                var ip = ipInput.text.Trim();
                if (ip.Length == 0) { UIFactory.Toast(root.transform, "Enter the host IP"); return; }
                app.Profile.D.last_join_ip = ip;
                app.Profile.Save();
                NetSession.I.JoinGame(ip);
            }, 26);
            joinBtn.transform.localPosition = new Vector3(0, -40, 0);
            lobbyStatus = UIFactory.Label(entryCard, "", 20, UIFactory.Accent, TextAnchor.MiddleCenter);
            lobbyStatus.rectTransform.anchorMin = new Vector2(0.5f, 0); lobbyStatus.rectTransform.anchorMax = new Vector2(0.5f, 0);
            lobbyStatus.rectTransform.anchoredPosition = new Vector2(0, -140);
            var scanBtn = UIFactory.Button(entryCard, "SCAN LOCAL NETWORK", UIFactory.ButtonBg, new Vector2(340, 56),
                () => { NetSession.I.StartDiscovery(); UIFactory.Toast(root.transform, "Scanning..."); }, 20);
            scanBtn.transform.localPosition = new Vector3(0, -100, 0);
            var scanHint = UIFactory.Label(entryCard,
                "Play on the same Wi-Fi / hotspot. Scan finds rooms automatically.", 16,
                UIFactory.TextDim, TextAnchor.MiddleCenter);
            scanHint.rectTransform.StretchFull();
            scanHint.rectTransform.offsetMin = new Vector2(30, -190);
            scanHint.rectTransform.offsetMax = new Vector2(-30, -160);

            foundRoomsList = UIFactory.Rect(entryCard, "found");
            foundRoomsList.anchorMin = new Vector2(0.5f, 0); foundRoomsList.anchorMax = new Vector2(0.5f, 0);
            foundRoomsList.sizeDelta = new Vector2(560, 160);
            foundRoomsList.anchoredPosition = new Vector2(0, 10);

            // ---------- lobby card ----------
            lobbyCard = UIFactory.Rect(win, "lobbyCard");
            lobbyCard.sizeDelta = new Vector2(1120, 560);
            lobbyCard.gameObject.SetActive(false);

            // player list (left)
            var listTitle = UIFactory.Title(lobbyCard, "PLAYERS", 24);
            listTitle.rectTransform.anchorMin = new Vector2(0, 1); listTitle.rectTransform.anchorMax = new Vector2(0, 1);
            listTitle.rectTransform.anchoredPosition = new Vector2(220, -30);
            var scrollRoot = UIFactory.Rect(lobbyCard, "listRoot");
            scrollRoot.anchorMin = new Vector2(0, 0); scrollRoot.anchorMax = new Vector2(0.5f, 1);
            scrollRoot.offsetMin = new Vector2(20, 60); scrollRoot.offsetMax = new Vector2(-10, -60);
            var scroll = UIFactory.ScrollV(scrollRoot);
            playerList = scroll.content;
            countText = UIFactory.Label(lobbyCard, "", 18, UIFactory.TextDim, TextAnchor.LowerLeft);
            countText.rectTransform.anchorMin = new Vector2(0, 0); countText.rectTransform.anchorMax = new Vector2(0.5f, 0);
            countText.rectTransform.anchoredPosition = new Vector2(40, 34);

            // color swatches (16)
            var colorTitle = UIFactory.Label(lobbyCard, "YOUR COLOR", 20, UIFactory.TextMain, TextAnchor.MiddleLeft, FontStyle.Bold);
            colorTitle.rectTransform.anchorMin = new Vector2(0, 1); colorTitle.rectTransform.anchorMax = new Vector2(1, 1);
            colorTitle.rectTransform.anchoredPosition = new Vector2(-320, -96);
            colorRow = UIFactory.Rect(lobbyCard, "colors");
            colorRow.anchorMin = new Vector2(1, 1); colorRow.anchorMax = new Vector2(1, 1);
            colorRow.pivot = new Vector2(1, 1);
            colorRow.sizeDelta = new Vector2(560, 120);
            colorRow.anchoredPosition = new Vector2(-40, -120);
            BuildColorSwatches();

            // host settings (right, host only / offline)
            hostSettings = UIFactory.Rect(lobbyCard, "settings");
            hostSettings.anchorMin = new Vector2(0.5f, 0); hostSettings.anchorMax = new Vector2(1, 1);
            hostSettings.offsetMin = new Vector2(10, 150); hostSettings.offsetMax = new Vector2(-40, -250);
            if (online) BuildHostSettings();
            else BuildPracticeSettings();

            // bottom buttons
            var startBtn = UIFactory.Button(lobbyCard, online ? "START MATCH" : "START PRACTICE",
                UIFactory.ButtonBgGreen, new Vector2(300, 70), () =>
                {
                    if (!online) StartPractice();
                    else if (NetSession.I.IsHost) NetSession.I.StartMatch();
                }, 26);
            startBtn.transform.localPosition = new Vector3(0, -230, 0);
            startBtn.name = "startBtn";
            var leaveBtn = UIFactory.Button(lobbyCard, "LEAVE", UIFactory.ButtonBgRed, new Vector2(200, 56),
                () => { NetSession.I.Leave(); app.ShowMenu(); }, 22);
            leaveBtn.transform.localPosition = new Vector3(-440, -230, 0);

            // net events
            NetSession.I.LobbyUpdated -= RebuildPlayerList;
            NetSession.I.LobbyUpdated += RebuildPlayerList;
            NetSession.I.JoinedAs -= OnJoined;
            NetSession.I.JoinedAs += OnJoined;
            NetSession.I.JoinFailed -= OnJoinFailed;
            NetSession.I.JoinFailed += OnJoinFailed;
            NetSession.I.MatchStarted -= OnMatchStarted;
            NetSession.I.MatchStarted += OnMatchStarted;
            NetSession.I.RoomFound -= OnRoomFound;
            NetSession.I.RoomFound += OnRoomFound;

            if (!online)
            {
                // practice: local lobby with me + bots
                NetSession.I.StartLocal();
                entryCard.gameObject.SetActive(false);
                OnEnteredLobby();
                NetSession.I.AddBots(3);
            }
        }

        protected override void OnClose()
        {
            if (NetSession.I != null)
            {
                NetSession.I.LobbyUpdated -= RebuildPlayerList;
                NetSession.I.JoinedAs -= OnJoined;
                NetSession.I.JoinFailed -= OnJoinFailed;
                NetSession.I.MatchStarted -= OnMatchStarted;
                NetSession.I.RoomFound -= OnRoomFound;
            }
        }

        void OnBack()
        {
            if (NetSession.I.Online) NetSession.I.Leave();
            app.ShowMenu();
        }

        void OnEnteredLobby()
        {
            entryCard.gameObject.SetActive(false);
            lobbyCard.gameObject.SetActive(true);
            RebuildPlayerList();
        }

        void OnJoined(int id)
        {
            lobbyStatus.text = "";
            OnEnteredLobby();
            Sfx.Play("sfx_join");
        }

        void OnJoinFailed(string why)
        {
            lobbyStatus.text = why;
        }

        void OnMatchStarted(MatchStartInfo info)
        {
            app.BeginMatch(info, true, false);
        }

        void OnRoomFound(NetSession.FoundRoom room)
        {
            if (foundRooms.Any(g => g == null)) foundRooms.RemoveAll(g => g == null);
            if (foundRooms.Count >= 4) return;
            var row = UIFactory.Row(foundRoomsList, 56);
            var l = UIFactory.Label(row, room.Name + "  (" + room.Players + " players)", 20,
                UIFactory.TextMain, TextAnchor.MiddleLeft);
            l.rectTransform.StretchFull(); l.rectTransform.offsetMin = new Vector2(10, 0);
            var b = UIFactory.Button(row, "JOIN", UIFactory.ButtonBgGreen, new Vector2(100, 44), () =>
            {
                ipInput.text = room.Ip;
                app.Profile.D.last_join_ip = room.Ip;
                app.Profile.Save();
                NetSession.I.JoinGame(room.Ip);
            }, 18);
            foundRooms.Add(row.gameObject);
        }

        // ---------------- player list ----------------

        void RebuildPlayerList()
        {
            if (playerList == null) return;
            UIFactory.Clear(playerList);
            var lobby = NetSession.I.Lobby;
            foreach (var p in lobby)
            {
                var row = UIFactory.Row(playerList, 56);
                // color dot
                ColorUtility.TryParseHtmlString(GameConfig.PlayerColorHex[p.color % GameConfig.PlayerColorHex.Length], out var c);
                var dot = UIFactory.Image(row, "dot", c);
                dot.rectTransform.sizeDelta = new Vector2(30, 30);
                var l = UIFactory.Label(row,
                    p.name + (p.bot ? "  [BOT]" : "") + (p.isHost ? "  [HOST]" : ""),
                    20, p.id == NetSession.I.MyId ? UIFactory.Accent : UIFactory.TextMain,
                    TextAnchor.MiddleLeft, p.id == NetSession.I.MyId ? FontStyle.Bold : FontStyle.Normal);
                l.rectTransform.StretchFull(); l.rectTransform.offsetMin = new Vector2(8, 0);
            }
            countText.text = lobby.Count + " / " + GameConfig.MaxPlayers + " players";
            bool amHost = !online || NetSession.I.IsHost;
            hostSettings.gameObject.SetActive(amHost);
            var start = lobbyCard.Find("startBtn");
            if (start != null)
            {
                var btn = start.GetComponent<Button>();
                bool canStart = !online || NetSession.I.IsHost;
                btn.interactable = canStart;
                btn.GetComponent<Image>().color = canStart ? UIFactory.ButtonBgGreen : new Color(0.3f, 0.32f, 0.36f);
            }
            if (online && !NetSession.I.IsHost && NetSession.I.MyId >= 0)
                countText.text += "   (waiting for host to start)";
        }

        void BuildColorSwatches()
        {
            var lobby = NetSession.I.Online ? NetSession.I.Lobby : null;
            for (int i = 0; i < GameConfig.PlayerColorHex.Length; i++)
            {
                int idx = i;
                ColorUtility.TryParseHtmlString(GameConfig.PlayerColorHex[i], out var c);
                var sw = UIFactory.Image(colorRow, "sw_" + i, c);
                sw.rectTransform.sizeDelta = new Vector2(48, 48);
                sw.rectTransform.anchoredPosition = new Vector2(-24 + (i % 8) * 64 - 256, -24 - (i / 8) * 64);
                sw.raycastTarget = true;
                var btn = sw.gameObject.AddComponent<Button>();
                btn.targetGraphic = sw;
                btn.onClick.AddListener(() =>
                {
                    NetSession.I.SetColor(idx);
                    HighlightSwatches();
                });
            }
            HighlightSwatches();
        }

        void HighlightSwatches()
        {
            int mine = app.Profile.D.color_index;
            var taken = new HashSet<int>();
            if (NetSession.I.Online)
                foreach (var p in NetSession.I.Lobby) if (p.id != NetSession.I.MyId) taken.Add(p.color);
            for (int i = 0; i < GameConfig.PlayerColorHex.Length; i++)
            {
                var sw = colorRow.Find("sw_" + i);
                if (sw == null) continue;
                var img = sw.GetComponent<Image>();
                bool isMine = i == mine;
                bool isTaken = taken.Contains(i);
                var outline = sw.GetComponent<Outline>();
                if (outline == null) { outline = sw.gameObject.AddComponent<Outline>(); outline.effectDistance = new Vector2(3, -3); }
                outline.effectColor = isMine ? Color.white : Color.clear;
                img.color = isTaken && !isMine ? new Color(0.25f, 0.25f, 0.28f) : UIFactory.FromHex(0xFFFFFF);
                // tint the raw color back in
                ColorUtility.TryParseHtmlString(GameConfig.PlayerColorHex[i], out var c);
                if (!(isTaken && !isMine)) img.color = c;
            }
        }

        // ---------------- settings ----------------

        void Selector(RectTransform parent, string label, string[] options, int current, Action<int> set, float y)
        {
            var rowRt = UIFactory.Rect(parent, "sel_" + label);
            rowRt.anchorMin = new Vector2(0, 1); rowRt.anchorMax = new Vector2(1, 1);
            rowRt.anchoredPosition = new Vector2(0, y); rowRt.sizeDelta = new Vector2(0, 46);
            var l = UIFactory.Label(rowRt, label, 18, UIFactory.TextDim, TextAnchor.MiddleLeft);
            l.rectTransform.StretchFull(); l.rectTransform.offsetMax = new Vector2(-150, 0);
            var val = UIFactory.Label(rowRt, options[Mathf.Clamp(current, 0, options.Length - 1)], 20,
                UIFactory.TextMain, TextAnchor.MiddleRight, FontStyle.Bold);
            val.rectTransform.StretchFull(); val.rectTransform.offsetMin = new Vector2(150, 0);
            var prev = UIFactory.Button(rowRt, "<", UIFactory.ButtonBg, new Vector2(44, 40),
                () => set(-1), 20);
            prev.transform.localPosition = new Vector3(-160, 0, 0);
            var next = UIFactory.Button(rowRt, ">", UIFactory.ButtonBg, new Vector2(44, 40),
                () => set(1), 20);
            next.transform.localPosition = new Vector3(160, 0, 0);
        }

        void BuildHostSettings()
        {
            UIFactory.Clear(hostSettings);
            var s = NetSession.I;
            Selector(hostSettings, "MAP",
                MapData.All.Select(m => m.name).ToArray(), s.SelMap,
                d => { s.SelMap = (s.SelMap + d + MapData.All.Length) % MapData.All.Length; BuildHostSettings(); }, -20);
            Selector(hostSettings, "MODE", GameConfig.ModeNames, s.SelMode,
                d => { s.SelMode = 1 - s.SelMode; BuildHostSettings(); }, -70);
            Selector(hostSettings, "TIME", new[] { "3 min", "5 min", "8 min", "10 min" }, s.SelTime,
                d => { s.SelTime = (s.SelTime + d + 4) % 4; BuildHostSettings(); }, -120);
            Selector(hostSettings, "BOT LEVEL",
                GameConfig.BotLevels.Select(b => b.Name).ToArray(), s.BotLevel,
                d => { s.BotLevel = Mathf.Clamp(s.BotLevel + d, 0, GameConfig.BotLevels.Length - 1); BuildHostSettings(); }, -170);
            var addBot = UIFactory.Button(hostSettings, "+ BOT", UIFactory.ButtonBg, new Vector2(120, 46),
                () => { NetSession.I.AddBots(1); }, 20);
            addBot.transform.localPosition = new Vector3(-160, -230, 0);
            var rmBot = UIFactory.Button(hostSettings, "- BOTS", UIFactory.ButtonBg, new Vector2(120, 46),
                () => { NetSession.I.RemoveBots(); }, 20);
            rmBot.transform.localPosition = new Vector3(-20, -230, 0);
        }

        void BuildPracticeSettings()
        {
            UIFactory.Clear(hostSettings);
            var s = NetSession.I;
            Selector(hostSettings, "MAP",
                MapData.All.Select(m => m.name).ToArray(), s.SelMap,
                d => { s.SelMap = (s.SelMap + d + MapData.All.Length) % MapData.All.Length; BuildPracticeSettings(); }, -20);
            Selector(hostSettings, "MODE", GameConfig.ModeNames, s.SelMode,
                d => { s.SelMode = 1 - s.SelMode; BuildPracticeSettings(); }, -70);
            Selector(hostSettings, "TIME", new[] { "3 min", "5 min", "8 min", "10 min" }, s.SelTime,
                d => { s.SelTime = (s.SelTime + d + 4) % 4; BuildPracticeSettings(); }, -120);
            Selector(hostSettings, "BOT LEVEL",
                GameConfig.BotLevels.Select(b => b.Name).ToArray(), s.BotLevel,
                d => { s.BotLevel = Mathf.Clamp(s.BotLevel + d, 0, GameConfig.BotLevels.Length - 1); BuildPracticeSettings(); }, -170);
            var addBot = UIFactory.Button(hostSettings, "+ BOT", UIFactory.ButtonBg, new Vector2(120, 46),
                () => { NetSession.I.AddBots(1); }, 20);
            addBot.transform.localPosition = new Vector3(-160, -230, 0);
            var rmBot = UIFactory.Button(hostSettings, "- BOTS", UIFactory.ButtonBg, new Vector2(120, 46),
                () => { NetSession.I.RemoveBots(); NetSession.I.AddBots(1); }, 20);
            rmBot.transform.localPosition = new Vector3(-20, -230, 0);
        }

        void StartPractice()
        {
            var info = new MatchStartInfo
            {
                mapIndex = NetSession.I.SelMap,
                mode = NetSession.I.SelMode,
                timeLimit = GameConfig.MatchTimes[NetSession.I.SelTime],
                killLimit = GameConfig.KillLimits[NetSession.I.SelMode],
                botLevel = NetSession.I.BotLevel,
                players = new List<LobbyPlayer>(NetSession.I.Lobby),
            };
            app.BeginMatch(info, false, true);
        }

        public override void Pump()
        {
            refresh += Time.unscaledDeltaTime;
            if (refresh > 1f)
            {
                refresh = 0;
                if (entryCard.gameObject.activeSelf && NetSession.I.Online && NetSession.I.MyId >= 0)
                    OnJoined(NetSession.I.MyId);
                HighlightSwatches();
            }
        }
    }
}
