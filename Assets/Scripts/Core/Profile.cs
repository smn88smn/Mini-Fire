using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using UnityEngine;

namespace MiniFire
{
    /// <summary>JSON-serializable string->int map (JsonUtility can't do Dictionary).</summary>
    [Serializable]
    public class StrIntDict
    {
        public List<string> k = new List<string>();
        public List<int> v = new List<int>();
        public int this[string key]
        {
            get { int i = k.IndexOf(key); return i >= 0 ? v[i] : 0; }
            set { int i = k.IndexOf(key); if (i >= 0) v[i] = value; else { k.Add(key); v.Add(value); } }
        }
        public bool ContainsKey(string key) => k.Contains(key);
        public int Count => k.Count;
    }

    /// <summary>JSON-serializable string->string map.</summary>
    [Serializable]
    public class StrStrDict
    {
        public List<string> k = new List<string>();
        public List<string> v = new List<string>();
        public string this[string key]
        {
            get { int i = k.IndexOf(key); return i >= 0 ? v[i] : null; }
            set { int i = k.IndexOf(key); if (i >= 0) v[i] = value; else { k.Add(key); v.Add(value); } }
        }
        public bool ContainsKey(string key) => k.Contains(key);
    }

    /// <summary>Local player profile — field-for-field port of the Godot profile.gd.</summary>
    [Serializable]
    public class ProfileData
    {
        public string player_name = "";
        public int color_index = 0;
        public string primary_weapon = "smg";
        public int mfc = 0;
        public int gems = 0;
        public List<string> owned_skins = new List<string> { "default" };
        public StrStrDict equipped_skins = new StrStrDict();
        public StrIntDict powers = new StrIntDict();
        public int total_kills, total_deaths, matches_played, wins;
        public float sfx_volume = 0.8f;
        public int touch_controls = 0; // 0 auto, 1 always on, 2 off
        public string last_join_ip = "";
        public string char_skin = "recruit";
        public List<string> owned_chars = new List<string> { "recruit" };
        public int bot_level = 1;
        public StrIntDict gun_levels = new StrIntDict();
        public List<string> redeemed_codes = new List<string>();
        public string cloud_uid = "";
        public string cloud_email = "";
    }

    /// <summary>Owns the profile: persistence (AES-encrypted JSON), wallet, purchases,
    /// gun levels, gem codes, rewards and cloud merging.</summary>
    public class ProfileService
    {
        public ProfileData D { get; private set; }
        public event Action WalletChanged;
        public event Action ProfileChanged;

        public ProfileService() { Load(); EnsureDefaults(); }

        void EnsureDefaults()
        {
            if (string.IsNullOrEmpty(D.player_name))
                D.player_name = "Player" + UnityEngine.Random.Range(1000, 9999);
            foreach (var w in GameConfig.WeaponOrder)
                if (!D.gun_levels.ContainsKey(w)) D.gun_levels[w] = 1;
            if (!D.owned_chars.Contains("recruit")) D.owned_chars.Add("recruit");
            if (!D.owned_skins.Contains("default")) D.owned_skins.Add("default");
            if (!GameConfig.CharOrder.Contains(D.char_skin)) D.char_skin = "recruit";
            Save();
        }

        // ---------------- wallet ----------------
        public void AddCurrency(int addMfc, int addGems)
        {
            D.mfc = Mathf.Max(0, D.mfc + addMfc);
            D.gems = Mathf.Max(0, D.gems + addGems);
            Save(); WalletChanged?.Invoke();
        }

        public bool CanAfford(string currency, int price) =>
            (currency == "mfc" ? D.mfc : D.gems) >= price;

        // ---------------- gun skins ----------------
        public bool OwnsSkin(string id) => D.owned_skins.Contains(id);

        public bool BuySkin(string skinId)
        {
            if (OwnsSkin(skinId)) return true;
            var s = GameConfig.GunSkin(skinId);
            if (s.Id != skinId || !CanAfford(s.Currency, s.Price)) return false;
            if (s.Currency == "mfc") D.mfc -= s.Price; else D.gems -= s.Price;
            D.owned_skins.Add(skinId);
            Save(); WalletChanged?.Invoke(); ProfileChanged?.Invoke();
            return true;
        }

        public void EquipSkin(string weaponId, string skinId)
        {
            if (!OwnsSkin(skinId)) return;
            D.equipped_skins[weaponId] = skinId;
            Save(); ProfileChanged?.Invoke();
        }

        public string SkinFor(string weaponId)
        {
            string s;
            if (D.equipped_skins.TryGetValue(weaponId, out s) && OwnsSkin(s)) return s;
            return "default";
        }

        // ---------------- characters ----------------
        public bool OwnsChar(string id) => D.owned_chars.Contains(id);

        public bool BuyChar(string id)
        {
            if (OwnsChar(id)) return true;
            var c = GameConfig.CharSkin(id);
            if (c.Id != id || !CanAfford(c.Currency, c.Price)) return false;
            if (c.Currency == "mfc") D.mfc -= c.Price; else D.gems -= c.Price;
            D.owned_chars.Add(id);
            Save(); WalletChanged?.Invoke(); ProfileChanged?.Invoke();
            return true;
        }

        public void EquipChar(string id)
        {
            if (OwnsChar(id)) { D.char_skin = id; Save(); ProfileChanged?.Invoke(); }
        }

        // ---------------- powers ----------------
        public int PowerLevel(string id) =>
            D.powers.ContainsKey(id) ? Mathf.Clamp(D.powers[id], 0, GameConfig.PowerMax) : 0;
        // (StrIntDict indexer returns 0 for missing keys)

        /// <summary>Next level cost or null when maxed.</summary>
        public Tuple<string, int> NextPowerCost(string id)
        {
            int lvl = PowerLevel(id);
            var def = GameConfig.Powers.FirstOrDefault(p => p.Id == id);
            if (def == null || lvl >= GameConfig.PowerMax) return null;
            return Tuple.Create(def.Currency[lvl], def.Prices[lvl]);
        }

        public bool BuyPower(string id)
        {
            var cost = NextPowerCost(id);
            if (cost == null || !CanAfford(cost.Item1, cost.Item2)) return false;
            if (cost.Item1 == "mfc") D.mfc -= cost.Item2; else D.gems -= cost.Item2;
            D.powers[id] = PowerLevel(id) + 1;
            Save(); WalletChanged?.Invoke(); ProfileChanged?.Invoke();
            return true;
        }

        public int MaxHealth => (int)(GameConfig.MaxHealth + 15 * PowerLevel("armor"));
        public float FuelFactor => 1f + 0.2f * PowerLevel("jet");
        public int MagFor(string weaponId) =>
            Mathf.RoundToInt(GameConfig.Weapon(weaponId).Mag * (1f + 0.2f * PowerLevel("ammo")));
        public float ReloadFor(string weaponId) =>
            GameConfig.Weapon(weaponId).Reload * (1f - 0.12f * PowerLevel("reload"));

        // ---------------- gun levels ----------------
        public int GunLevel(string weaponId) => Mathf.Clamp(D.gun_levels[weaponId], 1, GameConfig.GunLevelMax);

        public int AddGunLevels(string weaponId, int add)
        {
            int nl = Mathf.Clamp(GunLevel(weaponId) + add, 1, GameConfig.GunLevelMax);
            D.gun_levels[weaponId] = nl;
            Save(); ProfileChanged?.Invoke();
            return nl;
        }

        // ---------------- gem codes (Telegram shop) ----------------
        /// <summary>Returns gems granted, or -1 invalid, -2 already used.</summary>
        public int RedeemCode(string code)
        {
            string clean = (code ?? "").Trim().ToUpperInvariant();
            if (D.redeemed_codes.Contains(clean)) return -2;
            int gems = CodeGems(clean);
            if (gems <= 0) return -1;
            D.redeemed_codes.Add(clean);
            AddCurrency(0, gems);
            return gems;
        }

        public static int CodeGems(string code)
        {
            var parts = code.Split('-');
            if (parts.Length != 4 || parts[0] != "MF") return 0;
            string payload = parts[1], checksum = parts[2];
            if (!ChecksumOk(payload, checksum)) return 0;
            int gems;
            if (!int.TryParse(parts[3], out gems)) return 0;
            if (gems <= 0 || gems > 100000) return 0;
            return gems;
        }

        static bool ChecksumOk(string payload, string checksum)
        {
            using (var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(GameConfig.CodeSecret)))
            {
                var mac = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
                var want = new StringBuilder();
                for (int i = 0; i < 5; i++)
                    want.Append(i % 2 == 0
                        ? GameConfig.CodeAlphabet[(mac[i] >> 3) & 31]
                        : GameConfig.CodeAlphabet[mac[i] & 31]);
                return want.ToString() == checksum;
            }
        }

        // ---------------- match rewards ----------------
        public Tuple<int, int> GrantMatchRewards(int kills, int deaths, bool won, bool botsOnly)
        {
            int rMfc = GameConfig.RewardMfcMatch + kills * GameConfig.RewardMfcPerKill;
            int rGems = GameConfig.RewardGemMatch + kills / GameConfig.RewardGemPerKills;
            if (won) { rMfc += GameConfig.RewardMfcWin; rGems += GameConfig.RewardGemWin; }
            if (botsOnly)
            {
                rMfc = (int)(rMfc * GameConfig.BotRewardFactor);
                rGems = (int)(rGems * GameConfig.BotRewardFactor);
            }
            D.total_kills += kills; D.total_deaths += deaths;
            D.matches_played++; if (won) D.wins++;
            AddCurrency(rMfc, rGems);
            return Tuple.Create(rMfc, rGems);
        }

        // ---------------- lobby info ----------------
        public LobbyPlayerInfo LobbyInfo()
        {
            var info = new LobbyPlayerInfo
            {
                name = D.player_name.Length > 16 ? D.player_name.Substring(0, 16) : D.player_name,
                color = Mathf.Clamp(D.color_index, 0, GameConfig.PlayerColorHex.Length - 1),
                charSkin = OwnsChar(D.char_skin) ? D.char_skin : "recruit",
                powers = DictFromPower(),
                gunLevels = new Dictionary<string, int>(),
                gunSkins = new Dictionary<string, string>(),
                bot = false,
            };
            foreach (var w in GameConfig.WeaponOrder)
            {
                info.gunLevels[w] = GunLevel(w);
                info.gunSkins[w] = SkinFor(w);
            }
            return info;
        }

        Dictionary<string, int> DictFromPower()
        {
            var d = new Dictionary<string, int>();
            foreach (var p in GameConfig.Powers) d[p.Id] = PowerLevel(p.Id);
            return d;
        }

        // ---------------- persistence ----------------
        static readonly string SavePath = System.IO.Path.Combine(
            Application.persistentDataPath, "profile.save");
        const string SaveKey = "MiniFire::v1::673eec6d1c4a09e814693a1654a36c82a2983d6b40cbea01";

        public void Save()
        {
            try
            {
                string json = JsonUtility.ToJson(D);
                File.WriteAllText(SavePath, Encrypt(json));
            }
            catch (Exception e) { Debug.LogWarning("Profile save failed: " + e.Message); }
        }

        void Load()
        {
            try
            {
                if (!File.Exists(SavePath)) { D = new ProfileData(); return; }
                string json = Decrypt(File.ReadAllText(SavePath));
                D = JsonUtility.FromJson<ProfileData>(json) ?? new ProfileData();
            }
            catch { D = new ProfileData(); Debug.LogWarning("Profile corrupted, starting fresh"); }
        }

        // simple AES-ECB-style encryption (deterministic, no IV juggling)
        static string Encrypt(string plain)
        {
            byte[] key;
            using (var sha = SHA256.Create()) key = sha.ComputeHash(Encoding.UTF8.GetBytes(SaveKey));
            using (var aes = Aes.Create())
            {
                aes.Key = key; aes.Mode = CipherMode.ECB; aes.Padding = PaddingMode.PKCS7;
                var enc = aes.CreateEncryptor().TransformFinalBlock(
                    Encoding.UTF8.GetBytes(plain), 0, Encoding.UTF8.GetBytes(plain).Length);
                return Convert.ToBase64String(enc);
            }
        }

        static string Decrypt(string b64)
        {
            byte[] key;
            using (var sha = SHA256.Create()) key = sha.ComputeHash(Encoding.UTF8.GetBytes(SaveKey));
            using (var aes = Aes.Create())
            {
                aes.Key = key; aes.Mode = CipherMode.ECB; aes.Padding = PaddingMode.PKCS7;
                var buf = Convert.FromBase64String(b64);
                var dec = aes.CreateDecryptor().TransformFinalBlock(buf, 0, buf.Length);
                return Encoding.UTF8.GetString(dec);
            }
        }

        // ---------------- cloud snapshot ----------------
        public Dictionary<string, object> Snapshot()
        {
            return new Dictionary<string, object>
            {
                { "name", D.player_name }, { "mfc", D.mfc }, { "gems", D.gems },
                { "owned_skins", new List<string>(D.owned_skins) },
                { "powers", DictFromPower() },
                { "gun_levels", DictFromGunLevels() },
                { "owned_chars", D.owned_chars }, { "char_skin", D.char_skin },
                { "redeemed_codes", D.redeemed_codes },
                { "total_kills", D.total_kills }, { "total_deaths", D.total_deaths },
                { "matches_played", D.matches_played }, { "wins", D.wins },
                { "color_index", D.color_index },
                { "updated", DateTimeOffset.UtcNow.ToUnixTimeSeconds() },
            };
        }

        Dictionary<string, int> DictFromGunLevels()
        {
            var d = new Dictionary<string, int>();
            foreach (var w in GameConfig.WeaponOrder) d[w] = GunLevel(w);
            return d;
        }

        /// <summary>Merge a cloud snapshot: keep the best of both (same as Godot version).</summary>
        public void ApplyCloud(Dictionary<string, object> data)
        {
            if (data == null || data.Count == 0) return;
            D.mfc = Mathf.Max(D.mfc, AsInt(data, "mfc"));
            D.gems = Mathf.Max(D.gems, AsInt(data, "gems"));
            D.total_kills = Mathf.Max(D.total_kills, AsInt(data, "total_kills"));
            D.total_deaths = Mathf.Max(D.total_deaths, AsInt(data, "total_deaths"));
            D.matches_played = Mathf.Max(D.matches_played, AsInt(data, "matches_played"));
            D.wins = Mathf.Max(D.wins, AsInt(data, "wins"));
            MergeList(D.owned_skins, data, "owned_skins");
            MergeList(D.owned_chars, data, "owned_chars");
            MergeList(D.redeemed_codes, data, "redeemed_codes");
            var eq = AsDict(data, "equipped_skins");
            if (eq != null)
                foreach (var k in eq.Keys)
                    if (OwnsSkin(eq[k])) D.equipped_skins[k] = eq[k];
            var pw = AsDict(data, "powers");
            foreach (var p in GameConfig.Powers)
            {
                int lvl = pw != null && pw.ContainsKey(p.Id) ? AsInt(pw, p.Id) : 0;
                D.powers[p.Id] = Mathf.Max(PowerLevel(p.Id), Mathf.Clamp(lvl, 0, GameConfig.PowerMax));
            }
            var gl = AsDict(data, "gun_levels");
            foreach (var w in GameConfig.WeaponOrder)
            {
                int lvl = gl != null && gl.ContainsKey(w) ? AsInt(gl, w) : 1;
                D.gun_levels[w] = Mathf.Max(GunLevel(w), Mathf.Clamp(lvl, 1, GameConfig.GunLevelMax));
            }
            string ch = AsString(data, "char_skin");
            if (!string.IsNullOrEmpty(ch) && OwnsChar(ch)) D.char_skin = ch;
            int ci = AsInt(data, "color_index");
            if (ci >= 0 && ci < GameConfig.PlayerColorHex.Length) D.color_index = ci;
            Save(); WalletChanged?.Invoke(); ProfileChanged?.Invoke();
        }

        static void MergeList(List<string> into, Dictionary<string, object> data, string key)
        {
            var from = data.ContainsKey(key) ? data[key] as List<object> : null;
            if (from == null) return;
            foreach (var v in from)
            {
                string s = v == null ? "" : v.ToString();
                if (!into.Contains(s)) into.Add(s);
            }
        }

        static int AsInt(Dictionary<string, object> d, string k) =>
            d.ContainsKey(k) && d[k] != null ? Convert.ToInt32(d[k]) : 0;
        static string AsString(Dictionary<string, object> d, string k) =>
            d.ContainsKey(k) ? (d[k] == null ? "" : d[k].ToString()) : "";
        static Dictionary<string, string> AsDict(Dictionary<string, object> d, string k)
        {
            var src = d.ContainsKey(k) ? d[k] as Dictionary<string, object> : null;
            if (src == null) return null;
            var r = new Dictionary<string, string>();
            foreach (var kv in src) r[kv.Key] = kv.Value == null ? "" : kv.Value.ToString();
            return r;
        }
    }

    /// <summary>Info sent to the host when joining a lobby.</summary>
    [Serializable]
    public class LobbyPlayerInfo
    {
        public string name;
        public int color;
        public string charSkin;
        public Dictionary<string, int> powers;
        public Dictionary<string, int> gunLevels;
        public Dictionary<string, string> gunSkins;
        public bool bot;
    }
}
