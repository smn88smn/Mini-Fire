using System;
using System.Collections.Generic;
using System.Linq;

namespace MiniFire
{
    /// <summary>All static game data, ported 1:1 from the Godot version's catalog.gd.
    /// Economy numbers are unchanged by design.</summary>
    public static class GameConfig
    {
        public const int GameVersion = 4;

        // ---------------- weapons ----------------
        public sealed class WeaponDef
        {
            public string Id, Name, Sound;
            public int Damage, Mag, Tier;
            public float FireDelay, Reload, Speed, Life, Spread, Recoil, Length;
            public int Pellets;
            public float Splash;
            public bool Auto, Dual;
            public int[] Scopes;
        }

        static WeaponDef W(string id, string name, int dmg, float delay, int mag, float reload,
            float speed, float life, float spread, int pellets, float splash, bool auto,
            float length, float recoil, string sound, int[] scopes, bool dual, int tier)
            => new WeaponDef { Id = id, Name = name, Damage = dmg, FireDelay = delay, Mag = mag,
                Reload = reload, Speed = speed, Life = life, Spread = spread, Pellets = pellets,
                Splash = splash, Auto = auto, Length = length, Recoil = recoil, Sound = sound,
                Scopes = scopes, Dual = dual, Tier = tier };

        public static readonly WeaponDef[] WeaponList = new WeaponDef[]
        {
            W("pistol","Desert Eagle",26,0.30f, 8,1.2f,34f,0.62f,0.03f,1,0,false,0.52f,0.80f,"pistol",new[]{1,2},true,1),
            W("smg","Uzi",           9,0.07f,32,1.4f,28f,0.50f,0.10f,1,0,true, 0.68f,0.32f,"smg",   new[]{1,2},true,1),
            W("mp5","MP5",          12,0.08f,30,1.6f,32f,0.60f,0.06f,1,0,true, 0.80f,0.32f,"smg",   new[]{1,2,3},false,2),
            W("mp40","MP40",        14,0.10f,32,1.8f,32f,0.62f,0.07f,1,0,true, 0.84f,0.40f,"smg",  new[]{1,2,3},false,2),
            W("rifle","AK-47",      17,0.11f,30,1.9f,38f,0.80f,0.045f,1,0,true,0.92f,0.56f,"rifle", new[]{1,2,3,4},false,3),
            W("woodpecker","Woodpecker",42,0.40f,12,2.2f,54f,0.85f,0.008f,1,0,false,1.12f,1.20f,"sniper",new[]{1,2,3,5},false,3),
            W("shotgun","Shotgun",  12,0.75f, 6,2.2f,26f,0.32f,0.22f,7,0,false,0.84f,1.80f,"shotgun",new[]{1,2},false,3),
            W("svd","SVD",          62,0.60f,10,2.4f,66f,1.00f,0.004f,1,0,false,1.20f,1.80f,"sniper",new[]{1,2,4,7},false,4),
            W("sniper","Sniper",    95,1.25f, 5,2.5f,72f,1.00f,0.0f,1,0,false, 1.16f,2.40f,"sniper",new[]{1,2,4,7},false,4),
            W("rocket","Rocket",    75,1.40f, 2,2.8f,15.6f,2.0f,0.0f,1,2.6f,false,1.00f,2.80f,"rocket",new[]{1,2,3},false,5),
        };

        public static readonly string[] WeaponOrder = { "pistol","smg","mp5","mp40","rifle","woodpecker","shotgun","svd","sniper","rocket" };
        public static readonly string[] StartWeapons = { "smg", "pistol" };
        public const float DualFireFactor = 0.55f;
        public const float GroundGunLifetime = 30f;
        public const float GunSpotRespawn = 20f;
        public const float PickRadius = 1.2f;

        static readonly Dictionary<string, WeaponDef> WeaponMap =
            WeaponList.ToDictionary(w => w.Id, w => w);

        public static WeaponDef Weapon(string id)
        {
            WeaponDef w; return WeaponMap.TryGetValue(id, out w) ? w : WeaponMap["pistol"];
        }

        // ---------------- gun leveling ----------------
        public const int GunLevelMax = 6;
        public static readonly float[] GunLevelMult = { 1.0f, 1.12f, 1.25f, 1.4f, 1.6f, 2.0f };
        public const float BurnDps = 5f;
        public const float BurnTime = 2f;
        public const float BurnTick = 0.5f;

        public static float GunLevelMultAt(int level) =>
            GunLevelMult[Math.Max(1, Math.Min(GunLevelMax, level)) - 1];

        public static int GunLevelDamage(string weaponId, int level)
        {
            float baseDmg = Weapon(weaponId).Damage;
            return Math.Max(1, (int)Math.Round(baseDmg * GunLevelMultAt(level)));
        }

        // ---------------- bots ----------------
        public sealed class BotLevel
        {
            public string Name;
            public float Aim, Lead, Burst, Dmg, Dodge, Loot;
            public float ReactMin, ReactMax;
        }
        public static readonly BotLevel[] BotLevels = new BotLevel[]
        {
            new BotLevel{Name="Easy",  Aim=0.30f,ReactMin=0.75f,ReactMax=1.15f,Lead=0.0f,Burst=0.45f,Dmg=0.7f,Dodge=0.0f,Loot=0.2f},
            new BotLevel{Name="Normal",Aim=0.14f,ReactMin=0.40f,ReactMax=0.70f,Lead=0.4f,Burst=0.75f,Dmg=0.9f,Dodge=0.25f,Loot=0.5f},
            new BotLevel{Name="Hard",  Aim=0.06f,ReactMin=0.22f,ReactMax=0.40f,Lead=0.8f,Burst=0.92f,Dmg=1.0f,Dodge=0.55f,Loot=0.8f},
            new BotLevel{Name="Legend",Aim=0.02f,ReactMin=0.12f,ReactMax=0.22f,Lead=1.0f,Burst=1.0f,Dmg=1.1f,Dodge=0.85f,Loot=1.0f},
        };

        // ---------------- character skins (28 sets, Unity art) ----------------
        public sealed class CharSkinDef
        {
            public string Id, Name, Currency; // "mfc" | "gem"
            public int Price;
            public string Rarity; // common | rare | epic | legend
        }
        static CharSkinDef C(string id, string name, string cur, int price, string rarity)
            => new CharSkinDef { Id = id, Name = name, Currency = cur, Price = price, Rarity = rarity };

        public static readonly CharSkinDef[] CharSkins = new CharSkinDef[]
        {
            C("recruit","Recruit","mfc",0,"common"),
            C("desert","Desert Ops","mfc",400,"common"),
            C("nightops","Night Ops","mfc",400,"common"),
            C("arctic","Arctic","mfc",500,"common"),
            C("forest","Forest Ghost","mfc",500,"common"),
            C("urban","Urban","mfc",600,"common"),
            C("navy","Navy Seal","mfc",700,"common"),
            C("sandstorm","Sandstorm","mfc",700,"common"),
            C("jungle","Jungle","mfc",800,"common"),
            C("polarbear","Polar Bear","mfc",800,"common"),
            C("sunfire","Sunfire","mfc",1200,"rare"),
            C("toxic","Toxic","mfc",1400,"rare"),
            C("crimson","Crimson Elite","mfc",1600,"rare"),
            C("emerald","Emerald","mfc",1600,"rare"),
            C("steel","Steel","mfc",1800,"rare"),
            C("rose","Rose","mfc",1800,"rare"),
            C("mint","Mint","mfc",2000,"rare"),
            C("midnight","Midnight","mfc",2000,"rare"),
            C("copperhead","Copperhead","mfc",2200,"rare"),
            C("bloodmoon","Blood Moon","gem",40,"epic"),
            C("cyber","Cyber","gem",50,"epic"),
            C("goldlegion","Gold Legion","gem",60,"epic"),
            C("void","Void","gem",70,"epic"),
            C("lavafist","Lava Fist","gem",80,"epic"),
            C("frostbite","Frostbite","gem",80,"epic"),
            C("phantom","Phantom","gem",120,"legend"),
            C("dragonfire","Dragonfire","gem",150,"legend"),
            C("whitegold","White Gold","gem",180,"legend"),
        };
        public static readonly string[] CharOrder = CharSkins.Select(c => c.Id).ToArray();
        public static CharSkinDef CharSkin(string id) =>
            CharSkins.FirstOrDefault(c => c.Id == id) ?? CharSkins[0];

        // ---------------- gun skins ----------------
        public sealed class GunSkinDef
        {
            public string Id, Name, Currency;
            public int Price, Pattern;
            public string Rarity, BaseHex, AccentHex, Accent2Hex;
        }
        static GunSkinDef G(string id, string name, string cur, int price, string rarity, int pattern,
            string b, string a, string a2)
            => new GunSkinDef { Id = id, Name = name, Currency = cur, Price = price, Pattern = pattern,
                Rarity = rarity, BaseHex = b, AccentHex = a, Accent2Hex = a2 };

        public static readonly GunSkinDef[] GunSkins = new GunSkinDef[]
        {
            G("default","Factory","mfc",0,"common",0,"8a8f99","2a2d33","b0b4bc"),
            G("desert","Desert","mfc",400,"common",1,"d9bf86","9a7442","6e5330"),
            G("forest","Forest","mfc",400,"common",1,"6f8f4a","3a5226","2a2f1c"),
            G("tiger","Tiger","mfc",900,"rare",2,"ff9a1f","1a1410","ffd28a"),
            G("arctic","Arctic","mfc",1400,"rare",10,"e8f0f8","8aa4bf","c4d3e2"),
            G("carbon","Carbon","gem",25,"rare",3,"1e2126","4a505c","2e323a"),
            G("ice","Ice","gem",40,"epic",4,"7fd8ff","e8fbff","3aa0e0"),
            G("neon","Neon","gem",60,"epic",5,"16161f","39ff6a","00e5ff"),
            G("blood","Blood Moon","gem",80,"epic",6,"3a060c","ff2a3d","ff7a5a"),
            G("gold","Gold","gem",150,"legend",7,"ffe27a","b07a10","fff3c0"),
            G("galaxy","Galaxy","gem",220,"legend",8,"120a3a","7a3cff","ff4fd8"),
            G("dragon","Dragon","gem",300,"legend",9,"2a0804","ff5a10","ffd23a"),
        };
        public static readonly string[] GunSkinOrder = GunSkins.Select(g => g.Id).ToArray();
        public static GunSkinDef GunSkin(string id) =>
            GunSkins.FirstOrDefault(g => g.Id == id) ?? GunSkins[0];

        public static readonly Dictionary<string, string> RarityColors = new Dictionary<string, string>
        { {"common","#a0aabb"}, {"rare","#46a0ff"}, {"epic","#be5aff"}, {"legend","#ffbe28"} };

        // ---------------- powers ----------------
        public sealed class PowerDef
        {
            public string Id, Name, Desc;
            public string[] Currency; public int[] Prices;
        }
        public static readonly PowerDef[] Powers = new PowerDef[]
        {
            new PowerDef{Id="armor", Name="Armor", Desc="+15 max health per level", Currency=new[]{"mfc","mfc","gem"}, Prices=new[]{500,1200,60}},
            new PowerDef{Id="jet",   Name="Jet Fuel", Desc="+20% jetpack fuel per level", Currency=new[]{"mfc","mfc","gem"}, Prices=new[]{400,1000,50}},
            new PowerDef{Id="ammo",  Name="Big Mags", Desc="+20% magazine size per level", Currency=new[]{"mfc","mfc","gem"}, Prices=new[]{450,1100,50}},
            new PowerDef{Id="reload",Name="Fast Hands", Desc="-12% reload time per level", Currency=new[]{"mfc","mfc","gem"}, Prices=new[]{450,1100,50}},
        };
        public const int PowerMax = 3;

        // ---------------- pickups ----------------
        public const int PickupHeal = 50;
        public const float PickupRespawn = 15f;

        // ---------------- players / colors ----------------
        public static readonly string[] PlayerColorHex =
        {
            "#ff4d4d","#ffd24d","#4da6ff","#4dff88","#c44dff","#ff8f4d","#4dffff","#ff4dc4",
            "#f2f2f2","#8c8c8c","#9fff4d","#4d6bff","#ff6b9e","#b9ff4d","#4dffb3","#d4d44d",
        };
        public static readonly string[] ColorNames =
        {
            "Red","Yellow","Blue","Green","Purple","Orange","Cyan","Pink",
            "White","Gray","Lime","Indigo","Rose","Mint","Aqua","Sand",
        };

        // ---------------- modes ----------------
        public const int ModeFFA = 0, ModeTDM = 1;
        public static readonly string[] ModeNames = { "Free For All", "Team Deathmatch" };
        public static readonly int[] KillLimits = { 20, 30 };
        public static readonly int[] MatchTimes = { 180, 300, 480, 600 };
        public const int MaxPlayers = 16;
        public const float RespawnTime = 3f;
        public const float MaxHealth = 300f;

        // ---------------- rewards ----------------
        public const int RewardMfcPerKill = 10;
        public const int RewardMfcMatch = 25;
        public const int RewardMfcWin = 60;
        public const int RewardGemPerKills = 5;
        public const int RewardGemWin = 3;
        public const int RewardGemMatch = 1;
        public const float BotRewardFactor = 0.5f;

        // ---------------- spin shop ----------------
        public const int SpinCostMfc = 400;
        public const int SpinCostGem = 20;
        /// <summary>[weight, kind, value] kind: mfc | gems | gunlvl | gunlvl2</summary>
        public static readonly float[][] SpinPrizes = new float[][]
        {
            new[]{40f, 0f, 200f},  // +200 MFC
            new[]{25f, 1f, 1f},    // +1 level for selected gun
            new[]{15f, 0f, 600f},  // +600 MFC
            new[]{10f, 2f, 10f},   // +10 gems
            new[]{6f, 2f, 25f},    // +25 gems
            new[]{4f, 3f, 1f},     // +2 levels for selected gun
        };
        public const int SpinKindMfc = 0, SpinKindGunLvl = 1, SpinKindGems = 2, SpinKindGunLvl2 = 3;

        // ---------------- telegram shop ----------------
        public const string TelegramShopUrl = "https://t.me/MiniFireShop";

        // ---------------- gem codes ----------------
        public const string CodeSecret = "MiniFire::gems::7f3a9c2e51b8d046";
        public const string CodeAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

        // ---------------- movement (px/s in Godot -> units here: 1 unit = 50 px) ----------------
        public const float Gravity = 30f;
        public const float MoveSpeed = 6.8f;
        public const float GroundAccel = 52f;
        public const float AirAccel = 30f;
        public const float JetAccel = 60f;
        public const float JetMaxUp = -11.2f;
        public const float MaxFall = 20f;
        public const float FuelDrain = 0.2f;
        public const float FuelRegenGround = 0.5f;
        public const float FuelRegenAir = 0.08f;
        public const float NetRate = 1f / 30f;
        public const float BodyRadius = 0.28f;
        public const float BodyHeight = 1.04f;

        // ---------------- networking ----------------
        public const int NetPort = 7777;
        public const int DiscoveryPort = 7778;
        public const float SnapshotInterval = 0.05f;
        public const float HeartbeatInterval = 2f;
        public const float TimeoutSeconds = 8f;

        // ---------------- cloud ----------------
        public const string CloudCollection = "players";
    }
}
