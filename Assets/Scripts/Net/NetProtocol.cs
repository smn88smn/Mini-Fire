using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using UnityEngine;

namespace MiniFire
{
    // ============================================================ protocol
    public enum MsgType : byte
    {
        Hello = 1,        // C->H: name, color, charSkin, gunLevels, powers, gunSkins, protoVer
        Welcome = 2,      // H->C: yourId, lobbyState
        LobbyState = 3,   // H->C (reliable): full lobby
        StartMatch = 4,   // H->C (reliable)
        Input = 5,        // C->H @30Hz
        Snapshot = 6,     // H->C @20Hz
        GameEvent = 7,    // reliable, both ways (mostly H->C)
        Ack = 8,
        Heartbeat = 9,
        Leave = 10,
        Chat = 11,        // reliable
    }

    public class NetWriter
    {
        MemoryStream ms; BinaryWriter w;
        public NetWriter() { ms = new MemoryStream(256); w = new BinaryWriter(ms); }
        public void W(byte v) => w.Write(v);
        public void W(int v) => w.Write(v);
        public void W(float v) => w.Write(v);
        public void W(bool v) => w.Write(v);
        public void W(string v) { w.Write(v == null ? (ushort)0 : (ushort)v.Length); if (v != null && v.Length > 0) w.Write(v.ToCharArray()); }
        public byte[] ToArray() { w.Flush(); return ms.ToArray(); }
    }

    public class NetReader
    {
        BinaryReader r;
        public NetReader(byte[] data) { r = new BinaryReader(new MemoryStream(data)); }
        public byte RByte() => r.ReadByte();
        public int RInt() => r.ReadInt32();
        public float RFloat() => r.ReadSingle();
        public bool RBool() => r.ReadBoolean();
        public string RString() { int n = r.ReadUInt16(); return n == 0 ? "" : new string(r.ReadChars(n)); }
    }

    public sealed class PlayerNetState
    {
        public int id;
        public float x, y, vx, vy, hp, aim;
        public bool alive, burn;
        public byte anim;         // 0 idle 1 run 2 fly 3 jump 4 crouch 5 hurt
        public string weapon;     // current weapon id (for remote render)
        public bool dual;
        public int mag;           // for HUD (local player)
    }

    public sealed class LobbyPlayer
    {
        public int id;
        public string name;
        public int color;
        public string charSkin;
        public bool bot;
        public bool isHost;
        // match start payload:
        public Dictionary<string, int> gunLevels;
        public Dictionary<string, string> gunSkins;
        public Dictionary<string, int> powers;
    }

    public sealed class MatchStartInfo
    {
        public int mapIndex, mode, timeLimit, killLimit;
        public int botLevel, botCount;
        public List<LobbyPlayer> players = new List<LobbyPlayer>();
    }

    /// <summary>A UDP peer with an optional reliable-message layer.</summary>
    public class UdpPeer
    {
        UdpClient udp;
        readonly Dictionary<IPEndPoint, Remote> remotes = new Dictionary<IPEndPoint, Remote>();

        class Remote
        {
            public IPEndPoint ep;
            public int lastReliableId;
            public readonly Dictionary<int, byte[]> pending = new Dictionary<int, byte[]>();
            public readonly HashSet<int> received = new HashSet<int>();
            public float lastSeen;
            public float resendTimer;
        }

        public bool IsBound => udp != null;

        public void Bind(int port)
        {
            Close();
            udp = new UdpClient(port) { Client = { ReceiveBufferSize = 1 << 19, SendBufferSize = 1 << 19 } };
        }

        public void Close()
        {
            if (udp != null) { try { udp.Close(); } catch { } udp = null; }
            remotes.Clear();
        }

        /// <summary>Pump incoming packets. Reliable ones are auto-acked; duplicates dropped.
        /// Returns true when raw (unreliable) data was delivered.</summary>
        public bool Pump(Action<IPEndPoint, MsgType, NetReader, bool /*reliable*/> onMessage, float now)
        {
            bool any = false;
            while (udp != null && udp.Available > 0)
            {
                IPEndPoint from = new IPEndPoint(IPAddress.Any, 0);
                byte[] data;
                try { data = udp.Receive(ref from); }
                catch { break; }
                if (data == null || data.Length < 2) continue;
                var r = new NetReader(data);
                MsgType type;
                bool reliable;
                int reliableId = 0;
                byte head = r.RByte();
                type = (MsgType)(head & 0x7F);
                reliable = (head & 0x80) != 0;
                if (reliable) reliableId = r.RInt();

                Remote rem = GetRemote(from);
                rem.lastSeen = now;

                if (type == MsgType.Ack)
                {
                    int ackId = r.RInt();
                    rem.pending.Remove(ackId);
                    continue;
                }
                if (reliable)
                {
                    if (!rem.received.Add(reliableId)) continue; // duplicate
                    SendAck(from, reliableId);
                }
                any = true;
                onMessage(from, type, r, reliable);
            }
            return any;
        }

        public void ResendPending(float now, float interval = 0.12f)
        {
            foreach (var rem in remotes.Values)
            {
                if (rem.pending.Count == 0) continue;
                rem.resendTimer += Time.deltaTime;
                if (rem.resendTimer < interval) continue;
                rem.resendTimer = 0;
                foreach (var kv in rem.pending) RawSend(kv.Value, rem.ep);
            }
        }

        void SendAck(IPEndPoint to, int id)
        {
            var w = new NetWriter();
            w.W((byte)((byte)MsgType.Ack | 0x80));
            w.W(id);
            RawSend(w.ToArray(), to);
        }

        public void Send(IPEndPoint to, MsgType type, NetWriter body, bool reliable = false)
        {
            var w = new NetWriter();
            Remote rem = GetRemote(to);
            int relId = 0;
            if (reliable) { relId = ++rem.lastReliableId; }
            w.W((byte)((byte)type | (reliable ? 0x80 : 0)));
            if (reliable) w.W(relId);
            byte[] head = w.ToArray();
            byte[] bodyData = body == null ? new byte[0] : body.ToArray();
            byte[] packet = new byte[head.Length + bodyData.Length];
            Buffer.BlockCopy(head, 0, packet, 0, head.Length);
            Buffer.BlockCopy(bodyData, 0, packet, head.Length, bodyData.Length);
            RawSend(packet, to);
            if (reliable) rem.pending[relId] = packet;
        }

        void RawSend(byte[] data, IPEndPoint to)
        {
            if (udp == null) return;
            try { udp.Send(data, data.Length, to); } catch { }
        }

        Remote GetRemote(IPEndPoint ep)
        {
            Remote r;
            if (!remotes.TryGetValue(ep, out r)) { r = new Remote { ep = ep }; remotes[ep] = r; }
            return r;
        }

        public void DropRemote(IPEndPoint ep) => remotes.Remove(ep);

        public IPEndPoint[] RemoteEndpoints
        {
            get { var a = new IPEndPoint[remotes.Count]; remotes.Keys.CopyTo(a, 0); return a; }
        }

        public float LastSeen(IPEndPoint ep)
        {
            Remote r;
            return remotes.TryGetValue(ep, out r) ? r.lastSeen : -999f;
        }

        public void SetSeen(IPEndPoint ep, float now) { GetRemote(ep).lastSeen = now; }
    }
}
