using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace MiniFire
{
    public class PlayerEntity
    {
        public int id;
        public LobbyPlayer info;
        public CharacterPhysics body;
        public float hp, maxHp, fuel, fuelMult;
        public bool alive = true, burning;
        public float burnLeft;
        public string[] weapons = new string[2];
        public bool[] dual = new bool[2];
        public int[] ammo = new int[2];
        public int slot;
        public float cooldown, reloading, protect;
        public int kills, deaths;
        public bool isBot, isLocal;
        public PlayerInput input;
        public float respawnT;
        public AvatarRender render;
        public int spawnSide;
        public float hurtFlash;
        public bool hasFired;
        // bot state
        public float aiTimer;
        public PlayerEntity aiTarget;
        public float aiStrafe;

        public string Weapon => weapons[slot] ?? "pistol";
        public int GunLevel => info.gunLevels != null && info.gunLevels.ContainsKey(Weapon) ? info.gunLevels[Weapon] : 1;
        public int MagSize(int s, ProfileService profile)
        {
            int w = GameConfig.Weapon(weapons[s]).Mag;
            int pwr = info.powers != null && info.powers.ContainsKey("ammo") ? info.powers["ammo"] : 0;
            int bonus = Mathf.RoundToInt(0.2f * pwr * w);
            return w + bonus;
        }
        public float ReloadTime
        {
            get
            {
                float rl = GameConfig.Weapon(weapons[slot]).Reload;
                int pwr = info.powers != null && info.powers.ContainsKey("reload") ? info.powers["reload"] : 0;
                return rl * (1f - 0.12f * pwr);
            }
        }
    }

    public class Projectile
    {
        public float x, y, vx, vy, life, splash, splashDmg;
        public int dmg, ownerId;
        public bool burn;
        public string weaponId;
    }

    public class GroundGun
    {
        public float x, y, respawnT, expires;
        public string weaponId;
        public bool active = true;
        public GameObject view;
    }

    public class PickupItem
    {
        public float x, y, respawnT;
        public int kind; // 0 medkit 1 ammo
        public bool active = true;
        public GameObject view;
    }

    /// <summary>Host-authoritative match simulation + client-side prediction.</summary>
    public class MatchRunner : MonoBehaviour
    {
        public static MatchRunner I { get; private set; }

        public bool Online, IsHost;
        public MatchStartInfo Info;
        public MapDef Map;
        List<MapData.RectF> solids;

        public readonly Dictionary<int, PlayerEntity> Players = new Dictionary<int, PlayerEntity>();
        readonly List<Projectile> projectiles = new List<Projectile>();
        public readonly List<GroundGun> GroundGuns = new List<GroundGun>();
        public readonly List<PickupItem> Pickups = new List<PickupItem>();

        public float MatchTime;
        public bool Running;
        float snapshotT, inputT;
        public int LocalKills, LocalDeaths;
        bool rewardsGiven;

        // events
        public event Action<string> KillFeed;
        public event Action<List<PlayerEntity>> MatchEnded;
        public event Action LocalDied;
        public event Action LocalRespawned;

        PlayerEntity Local
        {
            get
            {
                PlayerEntity p;
                return Players.TryGetValue(NetSession.I.MyId, out p) ? p : null;
            }
        }

        public static void Begin(MatchStartInfo info, bool online, bool isHost)
        {
            if (I != null) EndAll();
            var go = new GameObject("MatchRunner");
            DontDestroyOnLoad(go);
            I = go.AddComponent<MatchRunner>();
            I.StartMatch(info, online, isHost);
        }

        public static void EndAll()
        {
            if (I == null) return;
            I.Cleanup();
            I = null;
        }

        void Cleanup()
        {
            foreach (var p in Players.Values) if (p.render != null) p.render.Destroy();
            Players.Clear();
            foreach (var g in GroundGuns) if (g.view != null) Destroy(g.view);
            foreach (var pk in Pickups) if (pk.view != null) Destroy(pk.view);
            GroundGuns.Clear(); Pickups.Clear();
            foreach (var obj in mapObjects) if (obj != null) Destroy(obj);
            mapObjects.Clear();
            Running = false;
            Destroy(gameObject);
        }

        readonly List<GameObject> mapObjects = new List<GameObject>();

        void StartMatch(MatchStartInfo info, bool online, bool isHost)
        {
            Info = info;
            Online = online;
            IsHost = isHost;
            MapData.Load();
            Map = MapData.Get(info.mapIndex);
            solids = MapData.Solids(Map);

            // tessellate warzone terrain polyline into collision strips
            if (Map.ground != null && Map.ground.Length > 1)
            {
                for (int i = 0; i < Map.ground.Length - 1; i++)
                {
                    float x0 = Map.ground[i][0], y0 = Map.ground[i][1];
                    float x1 = Map.ground[i + 1][0], y1 = Map.ground[i + 1][1];
                    int steps = Mathf.Max(1, Mathf.CeilToInt((x1 - x0) / 0.5f));
                    for (int s = 0; s < steps; s++)
                    {
                        float ax = x0 + (x1 - x0) * s / steps, bx = x0 + (x1 - x0) * (s + 1) / steps;
                        float ay = y0 + (y1 - y0) * s / steps, by = y0 + (y1 - y0) * (s + 1) / steps;
                        float top = Mathf.Min(ay, by);
                        solids.Add(new MapData.RectF { x = ax - 0.01f, y = top, w = (bx - ax) + 0.02f, h = Map.H - top + 5f });
                    }
                }
            }

            BuildMapVisuals();

            // spawn players
            foreach (var lp in info.players)
            {
                var e = new PlayerEntity
                {
                    id = lp.id,
                    info = lp,
                    body = new CharacterPhysics { solids = solids },
                    isBot = lp.bot,
                    maxHp = GameConfig.MaxHealth + 15 * (lp.powers != null && lp.powers.ContainsKey("armor") ? lp.powers["armor"] : 0),
                    fuelMult = 1f + 0.2f * (lp.powers != null && lp.powers.ContainsKey("jet") ? lp.powers["jet"] : 0),
                    fuel = 1f,
                };
                e.hp = e.maxHp;
                e.weapons[0] = GameConfig.StartWeapons[0];
                e.weapons[1] = GameConfig.StartWeapons[1];
                e.spawnSide = info.mode == GameConfig.ModeTDM ? lp.color % 2 : lp.id % 2;
                e.render = AvatarRender.Create(lp.charSkin, lp.name,
                    HexColor(GameConfig.PlayerColorHex[lp.color % GameConfig.PlayerColorHex.Length]));
                e.render.CurrentSkin = lp.charSkin;
                e.render.SetGun(e.Weapon, GunTint(lp));
                Players[lp.id] = e;
                RespawnPlayer(e, true);
            }

            // local player marker
            var local = Local;
            if (local != null)
            {
                local.isLocal = true;
                if (!Online) NetSession.Init();
            }

            // bots think
            if (IsHost || !Online)
                foreach (var p in Players.Values) if (p.isBot) p.aiTimer = UnityEngine.Random.Range(0.2f, 0.6f);

            // ground guns + pickups
            for (int i = 0; i < Map.gunPos.Length; i++)
                GroundGuns.Add(new GroundGun
                {
                    x = Map.gunPos[i][0], y = Map.gunPos[i][1],
                    weaponId = Map.gunIds[i],
                });
            for (int i = 0; i < Map.pickups.Length; i++)
                Pickups.Add(new PickupItem
                {
                    x = Map.pickups[i][0], y = Map.pickups[i][1],
                    kind = (int)Map.pickups[i][2],
                });
            RefreshGroundGunViews();
            RefreshPickupViews();

            MatchTime = info.timeLimit;
            Running = true;
        }

        void RespawnPlayer(PlayerEntity e, bool initial)
        {
            var spawns = Map.spawns[e.spawnSide % Map.spawns.Length];
            var pick = spawns[UnityEngine.Random.Range(0, spawns.Length)];
            e.body.Teleport(pick[0], pick[1] + 0.1f);
            e.hp = e.maxHp;
            e.alive = true;
            e.burning = false; e.burnLeft = 0;
            e.fuel = 1f;
            e.slot = 0;
            e.weapons[0] = GameConfig.StartWeapons[0];
            e.weapons[1] = GameConfig.StartWeapons[1];
            e.dual[0] = e.dual[1] = false;
            e.ammo[0] = e.MagSize(0, null);
            e.ammo[1] = e.MagSize(1, null);
            e.cooldown = 0; e.reloading = 0;
            e.protect = initial ? 1.5f : 2f;
            e.render.SetVisible(true);
            e.render.SetGun(e.Weapon, GunTint(e.info));
            if (e.isLocal && !initial) { if (LocalRespawned != null) LocalRespawned(); }
        }

        static Color HexColor(string hex)
        {
            Color c;
            ColorUtility.TryParseHtmlString(hex, out c);
            return c;
        }

        Color GunTint(LobbyPlayer lp)
        {
            string skinId = "default";
            if (lp.gunSkins != null && lp.gunSkins.ContainsKey(GameConfig.StartWeapons[0]))
                skinId = lp.gunSkins[GameConfig.StartWeapons[0]];
            return HexColor(GameConfig.GunSkin(skinId).BaseHex);
        }

        // ---------------- map visuals ----------------
        void BuildMapVisuals()
        {
            var cam = Camera.main;
            if (cam != null)
            {
                cam.orthographic = true;
                cam.orthographicSize = 10f;
                cam.transform.position = new Vector3(Map.W / 2, Map.H / 2, -10);
                cam.backgroundColor = HexColor(Map.theme == "canyon" ? "#f5b46e" : Map.theme == "warzone" ? "#141a2e" : "#1b2233");
            }
            // background image
            var bgGo = new GameObject("bg");
            bgGo.transform.position = new Vector3(Map.W / 2, Map.H / 2, 50);
            var bgSr = bgGo.AddComponent<SpriteRenderer>();
            var bgSp = Resources.Load<Sprite>("Maps/bg_" + Map.theme);
            if (bgSp != null)
            {
                bgSr.sprite = bgSp;
                bgSr.transform.localScale = new Vector3(Map.W / bgSp.bounds.size.x, Map.H / bgSp.bounds.size.y, 1);
                bgSr.color = new Color(0.55f, 0.55f, 0.6f, 1f);
            }
            mapObjects.Add(bgGo);

            // rooms (interior backdrop)
            if (Map.rooms != null)
                foreach (var r in Map.rooms)
                    AddBox(r[0], r[1], r[2], r[3], null, new Color(0, 0, 0, 0.25f), 40);
            // beams
            if (Map.beams != null)
                foreach (var b in Map.beams)
                    AddBox(b[0], b[1], b[2], b[3], null, new Color(0.1f, 0.1f, 0.12f, 0.8f), 5);

            // solid rects
            var platSprite = Resources.Load<Sprite>("Maps/tile_plat_" + Map.theme);
            var groundSprite = Resources.Load<Sprite>("Maps/tile_ground_" + Map.theme);
            foreach (var r in Map.rects)
            {
                float style = r.Length > 4 ? r[4] : 0;
                bool isGround = r[3] > 2f;
                var sp = isGround ? groundSprite : platSprite;
                var go = AddBox(r[0], r[1], r[2], r[3], sp, Color.white, 0);
                if (sp == null)
                    go.GetComponent<SpriteRenderer>().color = style == 1 ? new Color(0.55f, 0.58f, 0.62f)
                        : style == 3 ? new Color(0.62f, 0.45f, 0.25f)
                        : style == 4 ? new Color(0.65f, 0.6f, 0.4f)
                        : HexColor(Map.theme == "canyon" ? "#7a4b33" : "#3d4a5e");
            }

            // terrain strips visual (warzone)
            if (Map.ground != null && Map.ground.Length > 1)
            {
                var gs = Resources.Load<Sprite>("Maps/tile_ground_" + Map.theme);
                for (int i = 0; i < Map.ground.Length - 1; i++)
                {
                    float x0 = Map.ground[i][0], y0 = Map.ground[i][1];
                    float x1 = Map.ground[i + 1][0], y1 = Map.ground[i + 1][1];
                    var go = AddBox(Mathf.Min(x0, x1), Mathf.Min(y0, y1), Mathf.Abs(x1 - x0),
                        Mathf.Max(1.2f, Mathf.Abs(y1 - y0)), gs, Color.white, 0);
                    var sr = go.GetComponent<SpriteRenderer>();
                    sr.drawMode = SpriteDrawMode.Tiled;
                    sr.tileSize = new Vector2(Mathf.Abs(x1 - x0), sr.tileSize.y == 0 ? 1.2f : sr.tileSize.y);
                }
            }
        }

        GameObject AddBox(float x, float y, float w, float h, Sprite sp, Color color, int order)
        {
            var go = new GameObject("box");
            var sr = go.AddComponent<SpriteRenderer>();
            sr.sprite = sp; sr.color = color; sr.sortingOrder = order;
            if (sp != null)
            {
                go.transform.position = new Vector3(x + w / 2, y + h / 2, 0);
                go.transform.localScale = new Vector3(w / sp.bounds.size.x, h / sp.bounds.size.y, 1);
            }
            else
            {
                go.transform.position = new Vector3(x + w / 2, y + h / 2, 0);
                go.transform.localScale = new Vector3(w, h, 1);
                sr.sprite = AvatarRender.GetFrames("recruit")[0]; // 1px-ish white
                sr.color = color;
                var tex = new Texture2D(2, 2);
                sr.sprite = Sprite.Create(tex, new Rect(0, 0, 2, 2), new Vector2(0.5f, 0.5f), 2f);
            }
            mapObjects.Add(go);
            return go;
        }

        void RefreshGroundGunViews()
        {
            foreach (var g in GroundGuns)
            {
                if (g.view == null)
                {
                    g.view = new GameObject("groundgun");
                    var sr = g.view.AddComponent<SpriteRenderer>();
                    sr.sprite = Resources.Load<Sprite>("Art/gun_" + g.weaponId);
                    sr.sortingOrder = 3;
                }
                g.view.SetActive(g.active);
                g.view.transform.position = new Vector3(g.x, g.y + 0.35f, 0);
                g.view.transform.rotation = Quaternion.identity;
            }
        }

        void RefreshPickupViews()
        {
            foreach (var p in Pickups)
            {
                if (p.view == null)
                {
                    p.view = new GameObject("pickup");
                    var sr = p.view.AddComponent<SpriteRenderer>();
                    sr.sprite = Resources.Load<Sprite>("Art/icon_" + (p.kind == 0 ? "gem" : "coin"));
                    sr.sortingOrder = 3;
                    if (p.kind == 0) sr.color = new Color(0.2f, 1f, 0.4f);   // medkit green
                    else sr.color = new Color(1f, 0.75f, 0.2f);               // ammo gold
                    p.view.transform.localScale = Vector3.one * 0.7f;
                }
                p.view.SetActive(p.active);
                p.view.transform.position = new Vector3(p.x, p.y + 0.3f, 0);
            }
        }

        // ---------------- main loop ----------------
        void Update()
        {
            if (!Running) return;
            float dt = Time.deltaTime;

            if (IsHost || !Online)
            {
                SimulateHost(dt);
                snapshotT += dt;
                if (Online && snapshotT >= GameConfig.SnapshotInterval)
                {
                    snapshotT = 0;
                    BroadcastSnapshot();
                }
            }
            else
            {
                SimulateClient(dt);
            }

            // camera follow local player
            var local = Local;
            var cam = Camera.main;
            if (local != null && cam != null)
            {
                var target = new Vector3(local.body.x, local.body.y + 0.5f, -10);
                cam.transform.position = Vector3.Lerp(cam.transform.position, target, 1f - Mathf.Exp(-8f * dt));
                cam.transform.position = new Vector3(
                    Mathf.Clamp(cam.transform.position.x, cam.orthographicSize * cam.aspect * 0.7f, Map.W - cam.orthographicSize * cam.aspect * 0.7f),
                    Mathf.Clamp(cam.transform.position.y, cam.orthographicSize * 0.5f, Map.H - cam.orthographicSize * 0.5f),
                    -10);
            }

            // views
            foreach (var p in Players.Values) UpdateView(p, dt);
            RefreshGroundGunViews();
            RefreshPickupViews();
            RenderBullets();

            if (IsHost || !Online)
            {
                MatchTime -= dt;
                if (MatchTime <= 0) EndMatch();
            }
        }

        void UpdateView(PlayerEntity p, float dt)
        {
            if (p.render == null) return;
            if (!p.alive)
            {
                p.render.UpdateView(p.body.x, p.body.y, 0, 0, true, 0, false, true, dt);
                return;
            }
            int anim = 0;
            if (!p.body.grounded && Mathf.Abs(p.body.vy) > 1f) anim = p.input.jet ? 2 : 3;
            else if (Mathf.Abs(p.body.vx) > 0.5f) anim = 1;
            bool facingRight = Mathf.Cos(p.input.aim) >= 0;
            if (p.hurtFlash > 0) { anim = 5; p.hurtFlash -= dt; }
            p.render.SetJet(p.input.jet && p.fuel > 0);
            p.render.UpdateView(p.body.x, p.body.y, anim, p.input.aim, facingRight,
                p.hp / p.maxHp, p.burning, false, dt);
            p.render.SetGun(p.Weapon, GunTintForCurrent(p));
        }

        Color GunTintForCurrent(PlayerEntity p)
        {
            string skinId = "default";
            if (p.info.gunSkins != null && p.info.gunSkins.ContainsKey(p.Weapon))
                skinId = p.info.gunSkins[p.Weapon];
            return HexColor(GameConfig.GunSkin(skinId).BaseHex);
        }

        // ---------------- host simulation ----------------
        void SimulateHost(float dt)
        {
            foreach (var p in Players.Values)
            {
                if (p.isLocal)
                {
                    p.input = SampleLocalInput();
                    // one-shot flags: applied (and consumed) inside StepPlayer
                    p.input.swap |= pendingSwap;
                    p.input.reload |= pendingReload;
                    p.input.pick |= pendingPick;
                    pendingSwap = pendingReload = pendingPick = false;
                }
                if (p.isBot) BotThink(p, dt);
                StepPlayer(p, dt);
            }
            StepProjectiles(dt);
            StepPickupsAndGuns(dt);
        }

        void StepPlayer(PlayerEntity p, float dt)
        {
            if (!p.alive)
            {
                p.respawnT -= dt;
                if (p.respawnT <= 0) { RespawnPlayer(p, false); if (IsHost && Online) SendRespawn(p); }
                return;
            }
            if (p.protect > 0) p.protect -= dt;

            // weapons: swap / reload
            if (p.input.swap) { p.slot = 1 - p.slot; p.reloading = 0; p.input.swap = false; }
            if (p.input.reload && p.reloading <= 0 && p.ammo[p.slot] < p.MagSize(p.slot, null))
            {
                p.reloading = p.ReloadTime;
                Sfx.Play("sfx_ui");
            }
            p.input.reload = false;
            if (p.reloading > 0)
            {
                p.reloading -= dt;
                if (p.reloading <= 0) p.ammo[p.slot] = p.MagSize(p.slot, null);
            }

            // movement
            float fuelUsed;
            p.body.Step(p.input.moveX, p.input.jet, dt, p.fuel, p.fuelMult, out fuelUsed);
            p.fuel = Mathf.Clamp01(p.fuel - fuelUsed + (p.body.grounded ? GameConfig.FuelRegenGround : GameConfig.FuelRegenAir) * dt);

            // jetpack sound (local only)
            if (p.isLocal) Sfx.LoopJet(p.input.jet && p.fuel > 0);

            // firing
            p.cooldown -= dt;
            var w = GameConfig.Weapon(p.Weapon);
            bool wantFire = p.input.fire;
            if (wantFire && (w.Auto || !p.hasFired) && p.cooldown <= 0 && p.reloading <= 0)
            {
                if (p.ammo[p.slot] > 0) FireWeapon(p);
                else if (p.isLocal) Sfx.Play("sfx_ui");
            }
            if (!wantFire) p.hasFired = false;

            // burn
            if (p.burning)
            {
                p.burnLeft -= dt;
                p.burnTick -= dt;
                if (p.burnTick <= 0)
                {
                    p.burnTick = GameConfig.BurnTick;
                    ApplyDamage(p, GameConfig.BurnDps * GameConfig.BurnTick, null, "burn");
                }
                if (p.burnLeft <= 0) p.burning = false;
            }
        }

        void FireWeapon(PlayerEntity p)
        {
            var w = GameConfig.Weapon(p.Weapon);
            int lvl = p.GunLevel;
            int dmg = GameConfig.GunLevelDamage(p.Weapon, lvl);
            bool burn = lvl >= GameConfig.GunLevelMax;
            float delay = w.FireDelay * (p.dual[p.slot] ? GameConfig.DualFireFactor : 1f);
            p.cooldown = delay;
            p.ammo[p.slot]--;
            p.hasFired = true;

            float aim = p.input.aim;
            bool facingRight = Mathf.Cos(aim) >= 0;
            float originX = p.body.x + Mathf.Cos(aim) * 0.6f;
            float originY = p.body.y + 0.72f + Mathf.Sin(aim) * 0.6f;
            for (int i = 0; i < w.Pellets; i++)
            {
                float a = aim + UnityEngine.Random.Range(-w.Spread, w.Spread);
                projectiles.Add(new Projectile
                {
                    x = originX, y = originY,
                    vx = Mathf.Cos(a) * w.Speed, vy = Mathf.Sin(a) * w.Speed,
                    life = w.Life, dmg = dmg, ownerId = p.id,
                    weaponId = p.Weapon, burn = burn,
                    splash = w.Splash, splashDmg = w.Splash > 0 ? GameConfig.GunLevelDamage(p.Weapon, lvl) * 0.6f : 0,
                });
            }
            // recoil
            p.body.vx -= Mathf.Cos(aim) * w.Recoil * 0.1f;
            p.body.vy -= Mathf.Sin(aim) * w.Recoil * 0.1f;

            Sfx.PlayAt("sfx_" + w.Sound, new Vector2(p.body.x, p.body.y));
            Effects.Muzzle(new Vector3(originX, originY, 0), aim);

            if (Online && IsHost)
            {
                var nw = new NetWriter();
                nw.W(p.id); nw.W(originX); nw.W(originY); nw.W(aim); nw.W(p.Weapon);
                NetSession.I.Broadcast(MsgType.GameEvent, nw, true);
            }
        }

        void StepProjectiles(float dt)
        {
            for (int i = projectiles.Count - 1; i >= 0; i--)
            {
                var b = projectiles[i];
                b.life -= dt;
                float nx = b.x + b.vx * dt, ny = b.y + b.vy * dt;
                bool hit = false;
                // terrain
                if (MapData.SegmentBlocked(solids, b.x, b.y, nx, ny))
                {
                    if (b.splash > 0) Explode(b);
                    else Effects.Hit(new Vector3(nx, ny, 0));
                    hit = true;
                }
                else
                {
                    // players
                    foreach (var p in Players.Values)
                    {
                        if (!p.alive || p.id == b.ownerId || p.protect > 0) continue;
                        if (SameTeam(p.id, b.ownerId)) continue;
                        if (p.body.OverlapsCircle(nx, ny + 0.5f, 0.22f))
                        {
                            if (b.splash > 0) Explode(b);
                            else
                            {
                                ApplyDamage(p, b.dmg, Players[b.ownerId], b.weaponId);
                                if (b.burn && !p.burning) { p.burning = true; p.burnLeft = GameConfig.BurnTime; p.burnTick = GameConfig.BurnTick; }
                                Effects.Hit(new Vector3(nx, ny, 0));
                                Sfx.PlayAt("sfx_hit", new Vector2(nx, ny));
                            }
                            hit = true;
                            break;
                        }
                    }
                }
                if (hit) { projectiles.RemoveAt(i); continue; }
                b.x = nx; b.y = ny;
                if (b.life <= 0 || b.x < -5 || b.x > Map.W + 5 || b.y < -5 || b.y > Map.H + 5)
                    projectiles.RemoveAt(i);
            }
        }

        void Explode(Projectile b)
        {
            Effects.Explosion(new Vector3(b.x, b.y, 0), b.splash);
            Sfx.PlayAt("sfx_explosion", new Vector2(b.x, b.y));
            foreach (var p in Players.Values)
            {
                if (!p.alive || p.protect > 0 || SameTeam(p.id, b.ownerId)) continue;
                float dx = p.body.x - b.x, dy = (p.body.y + 0.5f) - b.y;
                float d = Mathf.Sqrt(dx * dx + dy * dy);
                if (d <= b.splash)
                {
                    float f = 1f - d / b.splash;
                    ApplyDamage(p, (int)(b.splashDmg * f), Players[b.ownerId], b.weaponId);
                    p.body.vx += dx / (d + 0.1f) * 8f * f;
                    p.body.vy += dy / (d + 0.1f) * 8f * f;
                    if (b.burn && !p.burning) { p.burning = true; p.burnLeft = GameConfig.BurnTime; p.burnTick = GameConfig.BurnTick; }
                }
            }
            if (Online && IsHost)
            {
                var nw = new NetWriter();
                nw.W(-1); nw.W(b.x); nw.W(b.y); nw.W(b.splash);
                NetSession.I.Broadcast(MsgType.GameEvent, nw, true);
            }
        }

        bool SameTeam(int a, int b)
        {
            if (Info.mode != GameConfig.ModeTDM) return false;
            PlayerEntity pa, pb;
            return Players.TryGetValue(a, out pa) && Players.TryGetValue(b, out pb) && pa.spawnSide == pb.spawnSide;
        }

        public void ApplyDamage(PlayerEntity target, float dmg, PlayerEntity by, string weaponId)
        {
            if (!target.alive || target.protect > 0) return;
            target.hp -= dmg;
            target.hurtFlash = 0.25f;
            if (target.isLocal) Sfx.Play("sfx_hurt");
            if (Online && IsHost)
            {
                var nw = new NetWriter();
                nw.W(-2); nw.W(target.id); nw.W(dmg); nw.W(by != null ? by.id : -1);
                NetSession.I.Broadcast(MsgType.GameEvent, nw, true);
            }
            if (target.hp <= 0) KillPlayer(target, by, weaponId);
        }

        void KillPlayer(PlayerEntity victim, PlayerEntity killer, string weaponId)
        {
            victim.alive = false;
            victim.deaths++;
            victim.respawnT = GameConfig.RespawnTime;
            victim.render.SetVisible(true); // dead pose
            if (killer != null && killer != victim)
            {
                if (!SameTeam(killer.id, victim.id)) killer.kills++;
                if (killer.isLocal) { LocalKills++; Sfx.Play("sfx_coin"); }
            }
            if (victim.isLocal) { LocalDeaths++; if (LocalDied != null) LocalDied(); Sfx.Play("sfx_death"); }

            // drop current weapon
            if (victim.Weapon != "pistol" && victim.Weapon != "smg")
                DropGun(victim.body.x, victim.body.y, victim.Weapon);

            string feed = (killer != null && killer != victim ? killer.info.name : "The world")
                + (killer != null && killer != victim && killer.id == victim.id ? "" : " killed ") + victim.info.name;
            if (KillFeed != null) KillFeed(feed);
            if (Online && IsHost)
            {
                var nw = new NetWriter();
                nw.W(-3); nw.W(victim.id); nw.W(killer != null ? killer.id : -1);
                NetSession.I.Broadcast(MsgType.GameEvent, nw, true);
            }

            // win check
            if (IsHost || !Online)
            {
                if (Info.mode == GameConfig.ModeTDM)
                {
                    foreach (var side in new[] { 0, 1 })
                        if (Players.Values.Where(p => p.spawnSide == side).Sum(p => p.kills) >= Info.killLimit)
                        { EndMatch(); break; }
                }
                else
                {
                    var top = Players.Values.OrderByDescending(p => p.kills).FirstOrDefault();
                    if (top != null && top.kills >= Info.killLimit) EndMatch();
                }
            }
        }

        void DropGun(float x, float y, string weaponId)
        {
            var g = new GroundGun { x = x, y = Mathf.Max(0.5f, y), weaponId = weaponId, expires = GameConfig.GroundGunLifetime };
            GroundGuns.Add(g);
        }

        void StepPickupsAndGuns(float dt)
        {
            foreach (var g in GroundGuns)
            {
                if (g.expires > 0)
                {
                    g.expires -= dt;
                    if (g.expires <= 0) { g.active = false; g.respawnT = GameConfig.GunSpotRespawn; }
                }
                else if (!g.active)
                {
                    g.respawnT -= dt;
                    if (g.respawnT <= 0 && g.weaponId != null) g.active = true;
                }
            }
            foreach (var p in Pickups)
            {
                if (p.active) continue;
                p.respawnT -= dt;
                if (p.respawnT <= 0) p.active = true;
            }
            // interaction: only when pick pressed (host side, for every player)
            foreach (var p in Players.Values)
            {
                if (!p.alive) continue;
                // pickups: automatic touch
                foreach (var pk in Pickups)
                {
                    if (!pk.active) continue;
                    if (Mathf.Abs(p.body.x - pk.x) < 0.8f && Mathf.Abs(p.body.y - pk.y) < 1.2f)
                    {
                        if (pk.kind == 0 && p.hp < p.maxHp)
                        {
                            p.hp = Mathf.Min(p.maxHp, p.hp + GameConfig.PickupHeal);
                            pk.active = false; pk.respawnT = GameConfig.PickupRespawn;
                            Sfx.PlayAt("sfx_gem", new Vector2(p.body.x, p.body.y));
                            Effects.Hit(new Vector3(pk.x, pk.y, 0));
                        }
                        else if (pk.kind == 1)
                        {
                            p.ammo[0] = p.MagSize(0, null); p.ammo[1] = p.MagSize(1, null);
                            pk.active = false; pk.respawnT = GameConfig.PickupRespawn;
                            Sfx.PlayAt("sfx_purchase", new Vector2(p.body.x, p.body.y));
                        }
                    }
                }
                // ground guns: press pick
                if (p.input.pick)
                {
                    p.input.pick = false;
                    GroundGun best = null; float bd = GameConfig.PickRadius * GameConfig.PickRadius;
                    foreach (var g in GroundGuns)
                    {
                        if (!g.active) continue;
                        float dx = g.x - p.body.x, dy = g.y - p.body.y;
                        float d2 = dx * dx + dy * dy;
                        if (d2 < bd) { bd = d2; best = g; }
                    }
                    if (best != null)
                    {
                        string old = p.Weapon;
                        // dual wield if same weapon
                        if (best.weaponId == p.weapons[p.slot] && GameConfig.Weapon(best.weaponId).Dual)
                            p.dual[p.slot] = true;
                        else
                        {
                            p.weapons[p.slot] = best.weaponId;
                            p.dual[p.slot] = false;
                        }
                        p.ammo[p.slot] = p.MagSize(p.slot, null);
                        best.active = false; best.respawnT = GameConfig.GunSpotRespawn; best.expires = 0;
                        if (best.weaponId != old)
                            DropGun(best.x, best.y, old != "pistol" && old != "smg" ? old : null);
                        Sfx.PlayAt("sfx_purchase", new Vector2(p.body.x, p.body.y));
                        if (Online && IsHost)
                        {
                            var nw = new NetWriter();
                            nw.W(-4); nw.W(p.id); nw.W(best.x); nw.W(best.y); nw.W(p.Weapon);
                            NetSession.I.Broadcast(MsgType.GameEvent, nw, true);
                        }
                    }
                }
            }
        }

        void EndMatch()
        {
            if (!Running) return;
            Running = false;
            Sfx.Play("sfx_win");
            var ordered = Players.Values.OrderByDescending(p => p.kills).ToList();
            bool won;
            if (Info.mode == GameConfig.ModeTDM)
            {
                int mySide = Local != null ? Local.spawnSide : 0;
                won = Players.Values.Where(p => p.spawnSide == mySide).Sum(p => p.kills) >
                      Players.Values.Where(p => p.spawnSide != mySide).Sum(p => p.kills);
            }
            else won = Local != null && ordered.Count > 0 && ordered[0].id == Local.id;

            // rewards (local player only, vs bots only if offline)
            if (!rewardsGiven)
            {
                rewardsGiven = true;
                bool botsOnly = !Online || Players.Values.Where(p => !p.isBot).Count() <= 1;
                App.I.Profile.GrantMatchRewards(LocalKills, LocalDeaths, won, botsOnly);
            }
            if (MatchEnded != null) MatchEnded(ordered);
        }

        // ---------------- client simulation ----------------
        Dictionary<int, PlayerNetState> lastSnap = new Dictionary<int, PlayerNetState>();

        void SimulateClient(float dt)
        {
            var local = Local;
            if (local != null && local.alive)
            {
                local.input = SampleLocalInput();
                float fuelUsed;
                local.body.Step(local.input.moveX, local.input.jet, dt, local.fuel, local.fuelMult, out fuelUsed);
                local.fuel = Mathf.Clamp01(local.fuel - fuelUsed + (local.body.grounded ? GameConfig.FuelRegenGround : GameConfig.FuelRegenAir) * dt);
                Sfx.LoopJet(local.input.jet && local.fuel > 0);
                // local weapon feel: cooldown & reload visuals
                local.cooldown -= dt;
                if (pendingSwap) { local.slot = 1 - local.slot; local.reloading = 0; pendingSwap = false; sendSwap = true; }
                if (pendingReload && local.reloading <= 0 && local.ammo[local.slot] < local.MagSize(local.slot, null))
                { local.reloading = local.ReloadTime; Sfx.Play("sfx_ui"); }
                if (pendingReload) { pendingReload = false; sendReload = true; }
                if (pendingPick) { pendingPick = false; sendPick = true; }
                if (local.reloading > 0)
                {
                    local.reloading -= dt;
                    if (local.reloading <= 0) local.ammo[local.slot] = local.MagSize(local.slot, null);
                }
                if (local.input.fire && local.cooldown <= 0 && local.reloading <= 0 && local.ammo[local.slot] > 0)
                {
                    var w = GameConfig.Weapon(local.Weapon);
                    local.cooldown = w.FireDelay;
                    local.ammo[local.slot]--;
                    float aim = local.input.aim;
                    Sfx.Play("sfx_" + w.Sound);
                    Effects.Muzzle(new Vector3(local.body.x + Mathf.Cos(aim) * 0.6f, local.body.y + 0.72f + Mathf.Sin(aim) * 0.6f, 0), aim);
                }
            }
            else if (local != null)
            {
                local.respawnT -= dt;
            }

            // send input @30Hz
            inputT += dt;
            if (inputT >= GameConfig.NetRate)
            {
                inputT = 0;
                if (local != null)
                {
                    NetSession.I.SendInput(local.input);
                    // edge-triggered flags must fire once: flush queued one-shots
                    if (sendSwap || sendReload || sendPick)
                    {
                        var one = local.input;
                        one.swap = sendSwap; one.reload = sendReload; one.pick = sendPick;
                        NetSession.I.SendInput(one);
                        sendSwap = sendReload = sendPick = false;
                    }
                }
            }

            // interpolate remotes toward last snapshot
            foreach (var kv in Players)
            {
                if (kv.Key == NetSession.I.MyId) continue;
                PlayerNetState st;
                if (!lastSnap.TryGetValue(kv.Key, out st)) continue;
                var p = kv.Value;
                p.body.x = Mathf.Lerp(p.body.x, st.x, 1f - Mathf.Exp(-12f * dt));
                p.body.y = Mathf.Lerp(p.body.y, st.y, 1f - Mathf.Exp(-12f * dt));
                p.body.vx = st.vx; p.body.vy = st.vy;
                p.hp = st.hp; p.alive = st.alive;
                p.input.aim = st.aim;
                p.input.jet = st.anim == 2;
                p.burning = st.burn;
                p.weapons[p.slot] = st.weapon ?? p.weapons[p.slot];
            }
        }

        bool pendingSwap, pendingReload, pendingPick;   // drained from TouchInput, consumed locally
        bool sendSwap, sendReload, sendPick;            // flushed to host on the next input send

        /// <summary>Continuous input; one-shot touch flags are drained here and
        /// queued in pending* until the client send-block has flushed them to the host.</summary>
        PlayerInput SampleLocalInput()
        {
            if (TouchInput.swapPressed) { TouchInput.swapPressed = false; pendingSwap = true; }
            if (TouchInput.reloadPressed) { TouchInput.reloadPressed = false; pendingReload = true; }
            if (TouchInput.pickPressed) { TouchInput.pickPressed = false; pendingPick = true; }
            return new PlayerInput
            {
                moveX = TouchInput.moveX, jet = TouchInput.jet, fire = TouchInput.fire, aim = TouchInput.aim,
            };
        }

        // ---------------- bots ----------------
        void BotThink(PlayerEntity p, float dt)
        {
            var lvl = GameConfig.BotLevels[Mathf.Clamp(Info.botLevel, 0, GameConfig.BotLevels.Length - 1)];
            p.aiTimer -= dt;
            if (p.aiTimer <= 0 || p.aiTarget == null || !p.aiTarget.alive)
            {
                p.aiTimer = UnityEngine.Random.Range(lvl.ReactMin, lvl.ReactMax);
                float bd = float.MaxValue; p.aiTarget = null;
                foreach (var e in Players.Values)
                {
                    if (!e.alive || e.id == p.id || SameTeam(e.id, p.id)) continue;
                    float d = (e.body.x - p.body.x) * (e.body.x - p.body.x) + (e.body.y - p.body.y) * (e.body.y - p.body.y);
                    if (d < bd) { bd = d; p.aiTarget = e; }
                }
                p.aiStrafe = UnityEngine.Random.value < 0.5f ? -1 : 1;
            }
            var inp = new PlayerInput();
            if (p.aiTarget != null && p.alive)
            {
                float tx = p.aiTarget.body.x, ty = p.aiTarget.body.y + 0.5f;
                float dx = tx - p.body.x, dy = ty - (p.body.y + 0.5f);
                float dist = Mathf.Sqrt(dx * dx + dy * dy);
                float aim = Mathf.Atan2(dy, dx) + UnityEngine.Random.Range(-lvl.Aim, lvl.Aim)
                            + lvl.Lead * (p.aiTarget.body.vx * 0.05f) / Mathf.Max(1f, dist);
                inp.aim = aim;
                inp.fire = dist < 28f && Mathf.Abs(Mathf.DeltaAngle(aim * Mathf.Rad2Deg, Mathf.Atan2(dy, dx) * Mathf.Rad2Deg)) < 25f
                           && UnityEngine.Random.value < lvl.Burst;
                // movement: approach, keep mid distance, strafe
                if (dist > 14f) inp.moveX = Mathf.Sign(dx);
                else if (dist < 6f) inp.moveX = -Mathf.Sign(dx);
                else inp.moveX = p.aiStrafe * 0.6f;
                // jet: if below target or falling into hazard
                if ((dy > 3f || p.body.vy < -6f) && UnityEngine.Random.value < 0.9f) inp.jet = true;
                if (p.body.y < 1.5f && p.body.vy < 0) inp.jet = true;
                // don't fly into ceiling
                if (p.body.y > Map.H - 3f) inp.jet = false;
                // occasionally pick up guns / reload
                if (p.ammo[p.slot] <= 0)
                {
                    if (UnityEngine.Random.value < 0.7f) inp.reload = true;
                    else inp.pick = true;
                }
                else if (UnityEngine.Random.value < 0.02f * lvl.Loot) inp.pick = true;
            }
            p.input = inp;
        }

        // ---------------- bullet visuals ----------------
        readonly List<SpriteRenderer> bulletPool = new List<SpriteRenderer>();

        void RenderBullets()
        {
            int need = projectiles.Count;
            while (bulletPool.Count < need)
            {
                var go = new GameObject("bullet");
                var sr = go.AddComponent<SpriteRenderer>();
                sr.sortingOrder = 8;
                bulletPool.Add(sr);
            }
            for (int i = 0; i < bulletPool.Count; i++)
            {
                bool on = i < projectiles.Count;
                bulletPool[i].gameObject.SetActive(on);
                if (!on) continue;
                var b = projectiles[i];
                var sr = bulletPool[i];
                string spriteName = b.burn ? "bullet_fire" : "bullet_" + (b.weaponId ?? "pistol");
                var sp = Resources.Load<Sprite>("Art/" + spriteName) ?? Resources.Load<Sprite>("Art/bullet_pistol");
                if (sr.sprite != sp) sr.sprite = sp;
                sr.color = b.burn ? Color.white : Color.white;
                sr.transform.position = new Vector3(b.x, b.y, 0);
                float ang = Mathf.Atan2(b.vy, b.vx) * Mathf.Rad2Deg;
                sr.transform.rotation = Quaternion.Euler(0, 0, ang);
            }
        }

        // ---------------- networking ----------------
        public void OnNetInput(int playerId, PlayerInput input)
        {
            PlayerEntity p;
            if (Players.TryGetValue(playerId, out p))
            {
                p.input = input;
                if (input.swap) p.input.swap = true; // host consumes in StepPlayer
            }
        }

        public void BroadcastSnapshot()
        {
            var w = new NetWriter();
            w.W(MatchTime);
            w.W(Players.Count);
            foreach (var p in Players.Values)
            {
                w.W(p.id); w.W(p.body.x); w.W(p.body.y); w.W(p.body.vx); w.W(p.body.vy);
                w.W(p.hp); w.W(p.maxHp); w.W(p.alive); w.W(p.input.aim);
                w.W(p.burning); w.W(p.Weapon); w.W(p.ammo[p.slot]); w.W(p.MagSize(p.slot, null));
                w.W(p.body.grounded); w.W(Mathf.Abs(p.body.vx) > 0.5f);
            }
            w.W(projectiles.Count);
            foreach (var b in projectiles)
            { w.W(b.x); w.W(b.y); w.W(b.vx); w.W(b.vy); w.W(b.weaponId); w.W(b.burn); }
            w.W(GroundGuns.Count);
            foreach (var g in GroundGuns)
            { w.W(g.x); w.W(g.y); w.W(g.weaponId); w.W(g.active); }
            w.W(Pickups.Count);
            foreach (var pk in Pickups)
            { w.W(pk.x); w.W(pk.y); w.W(pk.kind); w.W(pk.active); }
            NetSession.I.Broadcast(MsgType.Snapshot, w);
        }

        public void ApplySnapshot(NetReader r)
        {
            MatchTime = r.RFloat();
            int n = r.RInt();
            for (int i = 0; i < n; i++)
            {
                var st = new PlayerNetState
                {
                    id = r.RInt(), x = r.RFloat(), y = r.RFloat(), vx = r.RFloat(), vy = r.RFloat(),
                    hp = r.RFloat(), alive = r.RBool(), aim = r.RFloat(),
                    burn = r.RBool(), weapon = r.RString(), mag = r.RInt(),
                };
                int maxHp = r.RInt();
                bool grounded = r.RBool(), moving = r.RBool();
                lastSnap[st.id] = st;
                PlayerEntity p;
                if (Players.TryGetValue(st.id, out p))
                {
                    p.maxHp = maxHp;
                    if (st.id == NetSession.I.MyId)
                    {
                        // reconcile local prediction gently
                        float dx = p.body.x - st.x, dy = p.body.y - st.y;
                        if (dx * dx + dy * dy > 2.25f) { p.body.x = st.x; p.body.y = st.y; }
                        else { p.body.x = Mathf.Lerp(st.x, p.body.x, 0.35f); p.body.y = Mathf.Lerp(st.y, p.body.y, 0.35f); }
                        p.hp = st.hp; p.alive = st.alive;
                        p.ammo[p.slot] = Mathf.Min(p.ammo[p.slot] < 0 ? 0 : p.ammo[p.slot], st.mag);
                        if (st.mag == 0 && p.reloading <= 0) p.ammo[p.slot] = 0;
                    }
                }
            }
            // projectiles: replace visual list
            int pc = r.RInt();
            projectiles.Clear();
            for (int i = 0; i < pc; i++)
            {
                projectiles.Add(new Projectile
                {
                    x = r.RFloat(), y = r.RFloat(), vx = r.RFloat(), vy = r.RFloat(),
                    weaponId = r.RString(), burn = r.RBool(),
                });
            }
            // ground guns
            int gc = r.RInt();
            if (GroundGuns.Count == gc)
                for (int i = 0; i < gc; i++)
                {
                    GroundGuns[i].x = r.RFloat(); GroundGuns[i].y = r.RFloat();
                    GroundGuns[i].weaponId = r.RString(); GroundGuns[i].active = r.RBool();
                }
            else
                for (int i = 0; i < gc; i++)
                { r.RFloat(); r.RFloat(); r.RString(); r.RBool(); }
            // pickups
            int kc = r.RInt();
            if (Pickups.Count == kc)
                for (int i = 0; i < kc; i++)
                {
                    Pickups[i].x = r.RFloat(); Pickups[i].y = r.RFloat();
                    Pickups[i].kind = r.RInt(); Pickups[i].active = r.RBool();
                }
            else
                for (int i = 0; i < kc; i++)
                { r.RFloat(); r.RFloat(); r.RInt(); r.RBool(); }
        }

        public void OnNetEvent(NetReader r)
        {
            int code = r.RInt();
            switch (code)
            {
                case -1: // explosion
                    {
                        float x = r.RFloat(), y = r.RFloat(), rad = r.RFloat();
                        Effects.Explosion(new Vector3(x, y, 0), rad);
                        Sfx.PlayAt("sfx_explosion", new Vector2(x, y));
                        break;
                    }
                case -2: // damage
                    {
                        int target = r.RInt(); float dmg = r.RFloat(); int by = r.RInt();
                        PlayerEntity t;
                        if (Players.TryGetValue(target, out t))
                        {
                            t.hp -= dmg; t.hurtFlash = 0.25f;
                            if (t.isLocal) Sfx.Play("sfx_hurt");
                        }
                        break;
                    }
                case -3: // kill
                    {
                        int victim = r.RInt(), killer = r.RInt();
                        PlayerEntity v, k;
                        Players.TryGetValue(victim, out v);
                        Players.TryGetValue(killer, out k);
                        if (v != null)
                        {
                            v.alive = false; v.deaths++;
                            if (v.isLocal) { LocalDeaths++; if (LocalDied != null) LocalDied(); Sfx.Play("sfx_death"); }
                            if (k != null && k.isLocal && k != v) { LocalKills++; Sfx.Play("sfx_coin"); }
                            if (KillFeed != null) KillFeed((k != null ? k.info.name : "The world") + " killed " + v.info.name);
                        }
                        break;
                    }
                case -4: // gun picked
                    {
                        int pid = r.RInt(); float x = r.RFloat(), y = r.RFloat(); string wid = r.RString();
                        PlayerEntity p;
                        if (Players.TryGetValue(pid, out p)) { p.weapons[p.slot] = wid; p.render.SetGun(wid, GunTintForCurrent(p)); }
                        Sfx.PlayAt("sfx_purchase", new Vector2(x, y));
                        break;
                    }
                case -5: // respawn
                    {
                        int pid = r.RInt(); float x = r.RFloat(), y = r.RFloat();
                        PlayerEntity p;
                        if (Players.TryGetValue(pid, out p))
                        {
                            p.body.Teleport(x, y);
                            p.alive = true; p.hp = p.maxHp; p.burning = false;
                            p.weapons[0] = GameConfig.StartWeapons[0]; p.weapons[1] = GameConfig.StartWeapons[1];
                            p.dual[0] = p.dual[1] = false;
                            p.ammo[0] = p.MagSize(0, null); p.ammo[1] = p.MagSize(1, null);
                            p.slot = 0; p.protect = 2f;
                            p.render.SetVisible(true);
                            p.render.SetGun(p.Weapon, GunTintForCurrent(p));
                            if (p.isLocal && LocalRespawned != null) LocalRespawned();
                            Effects.SpawnRing(new Vector3(x, y, 0));
                        }
                        break;
                    }
                default:
                    if (code >= 0)
                    {
                        // shot fired
                        int pid = code;
                        float x = r.RFloat(), y = r.RFloat(), aim = r.RFloat();
                        string wid = r.RString();
                        PlayerEntity p;
                        if (Players.TryGetValue(pid, out p) && !p.isLocal)
                        {
                            Sfx.PlayAt("sfx_" + GameConfig.Weapon(wid).Sound, new Vector2(x, y));
                            Effects.Muzzle(new Vector3(x, y, 0), aim);
                        }
                    }
                    break;
            }
        }

        void SendRespawn(PlayerEntity p)
        {
            var nw = new NetWriter();
            nw.W(-5); nw.W(p.id); nw.W(p.body.x); nw.W(p.body.y);
            NetSession.I.Broadcast(MsgType.GameEvent, nw, true);
        }

        // ---------------- HUD API ----------------
        public PlayerEntity LocalPlayer => Local;
        public float MatchTimeLeft => Mathf.Max(0, MatchTime);

        public void LeaveMatch()
        {
            if (Online) NetSession.I.Leave();
            EndAll();
            App.I.ShowMenu();
        }
    }
}
