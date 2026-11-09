using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using UnityEngine;

namespace MiniFire
{
    /// <summary>Client input sampled by the local player and streamed to the host.</summary>
    public struct PlayerInput
    {
        public float moveX;   // -1..1
        public bool jet;      // jetpack held
        public bool fire;     // trigger held
        public float aim;     // aim angle radians
        public bool swap;     // weapon swap pressed (edge)
        public bool reload;   // reload pressed (edge)
        public bool pick;     // pickup gun pressed (edge)
    }

    /// <summary>Host/Client session: lobby management + match transport.
    /// Host is authoritative (same model as the Godot version).</summary>
    public class NetSession
    {
        public static NetSession I { get; private set; }
        public static void Init() { if (I == null) I = new NetSession(); }

        NetSession() { }

        // ---------------- public state ----------------
        public bool IsHost { get; private set; }
        public bool IsClient { get; private set; }
        public bool Online => IsHost || IsClient;
        public int MyId { get; private set; }

        UdpPeer peer;
        readonly Dictionary<int, ClientConn> clients = new Dictionary<int, ClientConn>();
        readonly Dictionary<IPEndPoint, int> byEp = new Dictionary<IPEndPoint, int>();
        int nextId = 1;

        class ClientConn
        {
            public IPEndPoint ep;
            public LobbyPlayer player;
        }

        public List<LobbyPlayer> Lobby = new List<LobbyPlayer>();
        public event Action LobbyUpdated;
        public event Action<int> JoinedAs;         // myId (client)
        public event Action<string> JoinFailed;
        public event Action<MatchStartInfo> MatchStarted;
        public event Action<int> PlayerLeft;       // playerId (host-detected leave / client notified)
        public event Action Disconnected;

        // lobby settings (host-owned, mirrored to clients)
        public int SelMap, SelMode, SelTime = 1, BotLevel = 1, BotCount = 3;

        float heartbeat, joinRetry, joinTimeout;
        IPEndPoint hostEp;
        string pendingJoinName;
        bool joining;

        // LAN discovery (UDP broadcast on DiscoveryPort)
        UdpPeer discoveryPeer;
        public sealed class FoundRoom { public string Name; public string Ip; public int Players; }
        public event Action<FoundRoom> RoomFound;
        float discoveryTimer;

        // ---------------- lifecycle ----------------
        public void HostGame()
        {
            Reset();
            IsHost = true;
            MyId = 0;
            peer = new UdpPeer();
            try
            {
                peer.Bind(GameConfig.NetPort);
                discoveryPeer = new UdpPeer();
                discoveryPeer.Bind(GameConfig.DiscoveryPort);
            }
            catch (Exception e)
            {
                IsHost = false;
                Debug.LogWarning("bind failed: " + e.Message);
                throw;
            }
            var me = App.I.Profile.LobbyInfo();
            Lobby.Add(new LobbyPlayer
            {
                id = 0, name = me.name, color = me.color, charSkin = me.charSkin,
                bot = false, isHost = true, gunLevels = me.gunLevels, gunSkins = me.gunSkins, powers = me.powers,
            });
        }

        public void JoinGame(string host)
        {
            Reset();
            IsClient = true;
            var info = App.I.Profile.LobbyInfo();
            pendingJoinName = info.name;
            peer = new UdpPeer();
            peer.Bind(0);
            IPAddress addr;
            if (!IPAddress.TryParse(host, out addr))
            {
                try
                {
                    var entry = Dns.GetHostEntry(host);
                    addr = entry.AddressList.Length > 0 ? entry.AddressList[0] : null;
                }
                catch { addr = null; }
            }
            if (addr == null) { JoinFailed("Invalid host address"); return; }
            hostEp = new IPEndPoint(addr, GameConfig.NetPort);
            joining = true;
            joinRetry = 0; joinTimeout = 8f;
            LobbyUpdated?.Invoke();
        }

        /// <summary>Offline practice lobby: local player id 0, no sockets bound.</summary>
        public void StartLocal()
        {
            Reset();
            MyId = 0;
            var me = App.I.Profile.LobbyInfo();
            Lobby.Add(new LobbyPlayer
            {
                id = 0, name = me.name, color = me.color, charSkin = me.charSkin,
                bot = false, isHost = true, gunLevels = me.gunLevels, gunSkins = me.gunSkins, powers = me.powers,
            });
            LobbyUpdated?.Invoke();
        }

        public void Leave()
        {
            if (Online)
            {
                try
                {
                    var w = new NetWriter();
                    if (IsClient && hostEp != null) peer.Send(hostEp, MsgType.Leave, w);
                    else Broadcast(MsgType.Leave, w, true);
                }
                catch { }
            }
            Reset();
        }

        void Reset()
        {
            if (peer != null) peer.Close();
            if (discoveryPeer != null) discoveryPeer.Close();
            discoveryPeer = null;
            peer = null;
            clients.Clear(); byEp.Clear();
            Lobby.Clear();
            IsHost = false; IsClient = false; MyId = -1;
            joining = false;
        }

        // ---------------- lobby ops (host) ----------------
        public void SetColor(int colorIndex)
        {
            App.I.Profile.D.color_index = colorIndex;
            App.I.Profile.Save();
            var mine = Lobby.Find(p => p.id == MyId);
            if (mine != null) mine.color = colorIndex;
            if (IsHost) BroadcastLobby();
        }

        public void AddBots(int count)
        {
            if (Online && !IsHost) return;
            for (int i = 0; i < count; i++)
            {
                if (Lobby.Count >= GameConfig.MaxPlayers) break;
                int c = 0;
                while (Lobby.Exists(p => p.color == c)) c = (c + 1) % GameConfig.PlayerColorHex.Length;
                var gl = new Dictionary<string, int>();
                var gs = new Dictionary<string, string>();
                foreach (var w in GameConfig.WeaponOrder) { gl[w] = 1; gs[w] = "default"; }
                Lobby.Add(new LobbyPlayer
                {
                    id = -nextId, name = "Bot " + nextId, color = c, bot = true,
                    charSkin = GameConfig.CharOrder[UnityEngine.Random.Range(0, GameConfig.CharOrder.Length)],
                    gunLevels = gl, gunSkins = gs, powers = new Dictionary<string, int>(),
                });
                nextId++;
            }
            if (IsHost) BroadcastLobby();
            LobbyUpdated?.Invoke();
        }

        public void RemoveBots()
        {
            if (Online && !IsHost) return;
            Lobby.RemoveAll(p => p.bot);
            if (IsHost) BroadcastLobby();
            LobbyUpdated?.Invoke();
        }

        public void StartMatch()
        {
            if (!IsHost) return;
            var info = new MatchStartInfo
            {
                mapIndex = SelMap, mode = SelMode,
                timeLimit = GameConfig.MatchTimes[SelTime],
                killLimit = GameConfig.KillLimits[SelMode],
                botLevel = BotLevel, botCount = 0,
                players = new List<LobbyPlayer>(Lobby),
            };
            // reliable start to everyone
            var w = new NetWriter();
            WriteStartMatch(w, info);
            Broadcast(MsgType.StartMatch, w, true);
            if (MatchStarted != null) MatchStarted(info);
        }

        // ---------------- pump (called every frame) ----------------
        public void Pump()
        {
            if (!Online || peer == null) return;
            float now = Time.realtimeSinceStartup;

            peer.Pump((from, type, r, reliable) => OnMessage(from, type, r), now);
            peer.ResendPending(now);
            if (discoveryPeer != null) PumpDiscovery(now);

            // heartbeat + timeouts
            heartbeat += Time.deltaTime;
            if (heartbeat > GameConfig.HeartbeatInterval)
            {
                heartbeat = 0;
                var hb = new NetWriter();
                if (IsClient && hostEp != null) peer.Send(hostEp, MsgType.Heartbeat, hb);
                else Broadcast(MsgType.Heartbeat, hb);
            }
            if (IsHost)
            {
                var gone = new List<int>();
                foreach (var c in clients.Values)
                    if (now - peer.LastSeen(c.ep) > GameConfig.TimeoutSeconds) gone.Add(c.player.id);
                foreach (var id in gone)
                {
                    RemoveClient(id, "timed out");
                }
            }
            if (IsClient && joining)
            {
                joinRetry -= Time.deltaTime;
                joinTimeout -= Time.deltaTime;
                if (joinRetry <= 0)
                {
                    joinRetry = 0.7f;
                    SendHello();
                }
                if (joinTimeout <= 0)
                {
                    JoinFailed("Host did not respond (check the IP / same network)");
                    Leave();
                }
            }
            if (IsClient && !joining && hostEp != null && now - peer.LastSeen(hostEp) > GameConfig.TimeoutSeconds + 4f)
            {
                if (Disconnected != null) Disconnected();
                Leave();
            }
        }

        void OnMessage(IPEndPoint from, MsgType type, NetReader r)
        {
            switch (type)
            {
                case MsgType.Hello:
                    if (!IsHost || joining) break;
                    if (!TryGetPlayer(from, out _))
                    {
                        if (Lobby.Count >= GameConfig.MaxPlayers)
                        {
                            var w0 = new NetWriter(); w0.W(-1);
                            peer.Send(from, MsgType.Welcome, w0);
                            break;
                        }
                        int proto = r.RInt();
                        if (proto != GameConfig.ProtocolVersion)
                        {
                            var wv = new NetWriter(); wv.W(-2);
                            peer.Send(from, MsgType.Welcome, wv);
                            break;
                        }
                        var p = ReadPlayerRest(r);
                        p.id = nextId++;
                        var conn = new ClientConn { ep = from, player = p };
                        clients[p.id] = conn;
                        byEp[from] = p.id;
                        Lobby.Add(p);
                        var w = new NetWriter();
                        w.W(p.id);
                        WriteLobby(w);
                        peer.Send(from, MsgType.Welcome, w);
                        BroadcastLobby();
                    }
                    break;

                case MsgType.Welcome:
                    if (!IsClient) break;
                    int id = r.RInt();
                    if (id == -1) { JoinFailed("Room is full"); Leave(); break; }
                    if (id == -2) { JoinFailed("Game version mismatch"); Leave(); break; }
                    MyId = id;
                    joining = false;
                    ReadLobby(r);
                    if (JoinedAs != null) JoinedAs(id);
                    break;

                case MsgType.LobbyState:
                    if (IsClient) { ReadLobby(r); LobbyUpdated?.Invoke(); }
                    break;

                case MsgType.StartMatch:
                    if (IsClient)
                    {
                        var info = ReadStartMatch(r);
                        if (MatchStarted != null) MatchStarted(info);
                    }
                    break;

                case MsgType.Leave:
                    {
                        int pid;
                        if (IsHost && byEp.TryGetValue(from, out pid)) RemoveClient(pid, "left");
                        else if (IsClient && from.Equals(hostEp))
                        {
                            if (Disconnected != null) Disconnected();
                            Leave();
                        }
                        break;
                    }

                case MsgType.GameEvent:
                    if (App.I.Match != null) App.I.Match.OnNetEvent(r);
                    break;

                case MsgType.Snapshot:
                    if (IsClient && App.I.Match != null) App.I.Match.ApplySnapshot(r);
                    break;

                case MsgType.Input:
                    if (IsHost && App.I.Match != null)
                    {
                        int pid;
                        if (byEp.TryGetValue(from, out pid))
                        {
                            peer.SetSeen(from, Time.realtimeSinceStartup);
                            App.I.Match.OnNetInput(pid, ReadInput(r));
                        }
                    }
                    break;
            }
        }

        // ---------------- LAN discovery ----------------
        // NOTE: must stay < 0x7F (wire header packs the type into 7 bits)
        const byte MsgDiscover = 60, MsgDiscoverReply = 61;

        /// <summary>Client: start listening for rooms on the local network (broadcast).</summary>
        public void StartDiscovery()
        {
            if (discoveryPeer == null)
            {
                discoveryPeer = new UdpPeer();
                try { discoveryPeer.Bind(0); } catch { discoveryPeer = null; return; }
            }
            var w = new NetWriter();
            w.W(MsgDiscover);
            try
            {
                var bc = new IPEndPoint(IPAddress.Broadcast, GameConfig.DiscoveryPort);
                discoveryPeer.Send(bc, (MsgType)MsgDiscover, w);
            }
            catch { }
            discoveryTimer = 0;
        }

        void PumpDiscovery(float now)
        {
            discoveryPeer.Pump((from, type, r, reliable) =>
            {
                if (type == (MsgType)MsgDiscover && IsHost)
                {
                    var w = new NetWriter();
                    w.W(NetSessionName ?? "Mini Fire");
                    w.W(Lobby.Count);
                    discoveryPeer.Send(from, (MsgType)MsgDiscoverReply, w);
                }
                else if (type == (MsgType)MsgDiscoverReply && IsClient == false && !Online)
                {
                    var room = new FoundRoom { Name = r.RString(), Players = r.RInt(), Ip = from.Address.ToString() };
                    if (RoomFound != null) RoomFound(room);
                }
            }, now);
        }

        public string NetSessionName;

        // ---------------- helpers ----------------
        void SendHello()
        {
            var info = App.I.Profile.LobbyInfo();
            var w = new NetWriter();
            w.W(GameConfig.ProtocolVersion);
            w.W(info.name); w.W(info.color); w.W(info.charSkin);
            foreach (var wp in GameConfig.WeaponOrder)
            { w.W(info.gunLevels.ContainsKey(wp) ? info.gunLevels[wp] : 1); w.W(info.gunSkins.ContainsKey(wp) ? info.gunSkins[wp] : "default"); }
            foreach (var p in GameConfig.Powers) w.W(info.powers.ContainsKey(p.Id) ? info.powers[p.Id] : 0);
            peer.Send(hostEp, MsgType.Hello, w);
        }

        bool TryGetPlayer(IPEndPoint ep, out LobbyPlayer p)
        {
            int id;
            p = null;
            if (!byEp.TryGetValue(ep, out id)) return false;
            ClientConn c;
            if (!clients.TryGetValue(id, out c)) return false;
            p = c.player;
            return true;
        }

        void RemoveClient(int id, string why)
        {
            ClientConn c;
            if (!clients.TryGetValue(id, out c)) return;
            clients.Remove(id);
            byEp.Remove(c.ep);
            peer.DropRemote(c.ep);
            Lobby.RemoveAll(p => p.id == id);
            BroadcastLobby();
            if (PlayerLeft != null) PlayerLeft(id);
            Debug.Log("client " + id + " " + why);
        }

        void BroadcastLobby()
        {
            if (!IsHost) return;
            var w = new NetWriter();
            WriteLobby(w);
            Broadcast(MsgType.LobbyState, w, true);
            LobbyUpdated?.Invoke();
        }

        public void Broadcast(MsgType type, NetWriter body, bool reliable = false)
        {
            if (peer == null) return;
            if (IsClient) { if (hostEp != null) peer.Send(hostEp, type, body, reliable); return; }
            foreach (var c in clients.Values) peer.Send(c.ep, type, body, reliable);
        }

        // ---------------- serialization ----------------
        LobbyPlayer ReadPlayerRest(NetReader r)
        {
            var p = new LobbyPlayer
            {
                name = r.RString(), color = r.RInt(), charSkin = r.RString(),
                gunLevels = new Dictionary<string, int>(), gunSkins = new Dictionary<string, string>(),
                powers = new Dictionary<string, int>(),
            };
            foreach (var w in GameConfig.WeaponOrder)
            { p.gunLevels[w] = r.RInt(); p.gunSkins[w] = r.RString(); }
            foreach (var pw in GameConfig.Powers) p.powers[pw.Id] = r.RInt();
            return p;
        }

        void WritePlayer(NetWriter w, LobbyPlayer p)
        {
            w.W(p.name); w.W(p.color); w.W(p.charSkin);
            foreach (var wp in GameConfig.WeaponOrder)
            { w.W(p.gunLevels != null && p.gunLevels.ContainsKey(wp) ? p.gunLevels[wp] : 1);
              w.W(p.gunSkins != null && p.gunSkins.ContainsKey(wp) ? p.gunSkins[wp] : "default"); }
            foreach (var pw in GameConfig.Powers) w.W(p.powers != null && p.powers.ContainsKey(pw.Id) ? p.powers[pw.Id] : 0);
        }

        void WriteLobby(NetWriter w)
        {
            w.W(Lobby.Count);
            foreach (var p in Lobby)
            {
                w.W(p.id); WritePlayer(w, p); w.W(p.bot); w.W(p.isHost);
            }
            w.W(SelMap); w.W(SelMode); w.W(SelTime); w.W(BotLevel);
        }

        void ReadLobby(NetReader r)
        {
            Lobby.Clear();
            int n = r.RInt();
            for (int i = 0; i < n; i++)
            {
                var p = new LobbyPlayer { id = r.RInt() };
                // same order as WritePlayer but with proto skip
                p.name = r.RString(); p.color = r.RInt(); p.charSkin = r.RString();
                p.gunLevels = new Dictionary<string, int>(); p.gunSkins = new Dictionary<string, string>();
                foreach (var w in GameConfig.WeaponOrder) { p.gunLevels[w] = r.RInt(); p.gunSkins[w] = r.RString(); }
                p.powers = new Dictionary<string, int>();
                foreach (var pw in GameConfig.Powers) p.powers[pw.Id] = r.RInt();
                p.bot = r.RBool(); p.isHost = r.RBool();
                Lobby.Add(p);
            }
            SelMap = r.RInt(); SelMode = r.RInt(); SelTime = r.RInt(); BotLevel = r.RInt();
        }

        void WriteStartMatch(NetWriter w, MatchStartInfo info)
        {
            w.W(info.mapIndex); w.W(info.mode); w.W(info.timeLimit); w.W(info.killLimit);
            w.W(info.botLevel);
            w.W(info.players.Count);
            foreach (var p in info.players)
            {
                w.W(p.id); WritePlayer(w, p); w.W(p.bot); w.W(p.isHost);
            }
        }

        MatchStartInfo ReadStartMatch(NetReader r)
        {
            var info = new MatchStartInfo
            {
                mapIndex = r.RInt(), mode = r.RInt(), timeLimit = r.RInt(), killLimit = r.RInt(),
                botLevel = r.RInt(),
            };
            int n = r.RInt();
            for (int i = 0; i < n; i++)
            {
                var p = new LobbyPlayer { id = r.RInt() };
                p.name = r.RString(); p.color = r.RInt(); p.charSkin = r.RString();
                p.gunLevels = new Dictionary<string, int>(); p.gunSkins = new Dictionary<string, string>();
                foreach (var w in GameConfig.WeaponOrder) { p.gunLevels[w] = r.RInt(); p.gunSkins[w] = r.RString(); }
                p.powers = new Dictionary<string, int>();
                foreach (var pw in GameConfig.Powers) p.powers[pw.Id] = r.RInt();
                p.bot = r.RBool(); p.isHost = r.RBool();
                info.players.Add(p);
            }
            return info;
        }

        public static void WriteInput(NetWriter w, PlayerInput i)
        {
            w.W(i.moveX); w.W(i.jet); w.W(i.fire); w.W(i.aim); w.W(i.swap); w.W(i.reload); w.W(i.pick);
        }

        public static PlayerInput ReadInput(NetReader r)
        {
            return new PlayerInput
            {
                moveX = r.RFloat(), jet = r.RBool(), fire = r.RBool(), aim = r.RFloat(),
                swap = r.RBool(), reload = r.RBool(), pick = r.RBool(),
            };
        }

        public void SendInput(PlayerInput i)
        {
            if (!IsClient || joining) return;
            var w = new NetWriter();
            WriteInput(w, i);
            peer.Send(hostEp, MsgType.Input, w);
        }
    }
}
