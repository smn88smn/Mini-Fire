extends Node
## Static game data: weapons, gun skins, player colors, maps and reward rules.
## Everything that a designer may want to tune lives here.

const GAME_VERSION := 2

# ---------------------------------------------------------------- weapons
# damage: per bullet/pellet. fire_delay: seconds between shots.
# speed: projectile speed px/s. life: projectile lifetime seconds.
# spread: radians (random +/-). pellets: projectiles per shot.
# splash: explosion radius (0 = none). auto: hold to fire.
const WEAPONS := {
	"pistol": {
		"name": "Pistol", "damage": 18, "fire_delay": 0.32, "mag": 12, "reload": 1.1,
		"speed": 1500.0, "life": 0.7, "spread": 0.03, "pellets": 1, "splash": 0.0,
		"auto": false, "length": 26.0, "recoil": 30.0, "sound": "pistol"
	},
	"smg": {
		"name": "Uzi", "damage": 11, "fire_delay": 0.075, "mag": 32, "reload": 1.5,
		"speed": 1400.0, "life": 0.55, "spread": 0.09, "pellets": 1, "splash": 0.0,
		"auto": true, "length": 34.0, "recoil": 18.0, "sound": "smg"
	},
	"rifle": {
		"name": "AK-47", "damage": 16, "fire_delay": 0.11, "mag": 30, "reload": 1.8,
		"speed": 1800.0, "life": 0.75, "spread": 0.045, "pellets": 1, "splash": 0.0,
		"auto": true, "length": 46.0, "recoil": 28.0, "sound": "rifle"
	},
	"shotgun": {
		"name": "Shotgun", "damage": 12, "fire_delay": 0.75, "mag": 6, "reload": 2.2,
		"speed": 1300.0, "life": 0.32, "spread": 0.22, "pellets": 7, "splash": 0.0,
		"auto": false, "length": 42.0, "recoil": 90.0, "sound": "shotgun"
	},
	"sniper": {
		"name": "Sniper", "damage": 85, "fire_delay": 1.25, "mag": 5, "reload": 2.5,
		"speed": 3200.0, "life": 0.8, "spread": 0.0, "pellets": 1, "splash": 0.0,
		"auto": false, "length": 58.0, "recoil": 120.0, "sound": "sniper"
	},
	"rocket": {
		"name": "Rocket", "damage": 70, "fire_delay": 1.4, "mag": 2, "reload": 2.8,
		"speed": 750.0, "life": 2.0, "spread": 0.0, "pellets": 1, "splash": 120.0,
		"auto": false, "length": 50.0, "recoil": 140.0, "sound": "rocket"
	},
}
## Order shown in menus. Pistol is always the secondary weapon.
const PRIMARY_WEAPONS := ["rifle", "smg", "shotgun", "sniper", "rocket"]
const SECONDARY_WEAPON := "pistol"

# ---------------------------------------------------------------- skins
# currency: "mfc" (soft coin) or "gem". price 0 = free/default.
# pattern ids are implemented in shaders/gun_skin.gdshader:
#   0 factory 1 camo 2 tiger 3 carbon 4 ice 5 neon 6 blood 7 gold 8 galaxy 9 dragon 10 arctic
# rarity: common | rare | epic | legend (card color in the shop)
const SKINS := {
	"default": {"name": "Factory", "currency": "mfc", "price": 0, "rarity": "common", "pattern": 0,
		"base": Color("8a8f99"), "accent": Color("2a2d33"), "accent2": Color("b0b4bc")},
	"desert": {"name": "Desert", "currency": "mfc", "price": 400, "rarity": "common", "pattern": 1,
		"base": Color("d9bf86"), "accent": Color("9a7442"), "accent2": Color("6e5330")},
	"forest": {"name": "Forest", "currency": "mfc", "price": 400, "rarity": "common", "pattern": 1,
		"base": Color("6f8f4a"), "accent": Color("3a5226"), "accent2": Color("2a2f1c")},
	"tiger": {"name": "Tiger", "currency": "mfc", "price": 900, "rarity": "rare", "pattern": 2,
		"base": Color("ff9a1f"), "accent": Color("1a1410"), "accent2": Color("ffd28a")},
	"arctic": {"name": "Arctic", "currency": "mfc", "price": 1400, "rarity": "rare", "pattern": 10,
		"base": Color("e8f0f8"), "accent": Color("8aa4bf"), "accent2": Color("c4d3e2")},
	"carbon": {"name": "Carbon", "currency": "gem", "price": 25, "rarity": "rare", "pattern": 3,
		"base": Color("1e2126"), "accent": Color("4a505c"), "accent2": Color("2e323a")},
	"ice": {"name": "Ice", "currency": "gem", "price": 40, "rarity": "epic", "pattern": 4,
		"base": Color("7fd8ff"), "accent": Color("e8fbff"), "accent2": Color("3aa0e0")},
	"neon": {"name": "Neon", "currency": "gem", "price": 60, "rarity": "epic", "pattern": 5,
		"base": Color("16161f"), "accent": Color("39ff6a"), "accent2": Color("00e5ff")},
	"blood": {"name": "Blood Moon", "currency": "gem", "price": 80, "rarity": "epic", "pattern": 6,
		"base": Color("3a060c"), "accent": Color("ff2a3d"), "accent2": Color("ff7a5a")},
	"gold": {"name": "Gold", "currency": "gem", "price": 150, "rarity": "legend", "pattern": 7,
		"base": Color("ffe27a"), "accent": Color("b07a10"), "accent2": Color("fff3c0")},
	"galaxy": {"name": "Galaxy", "currency": "gem", "price": 220, "rarity": "legend", "pattern": 8,
		"base": Color("120a3a"), "accent": Color("7a3cff"), "accent2": Color("ff4fd8")},
	"dragon": {"name": "Dragon", "currency": "gem", "price": 300, "rarity": "legend", "pattern": 9,
		"base": Color("2a0804"), "accent": Color("ff5a10"), "accent2": Color("ffd23a")},
}
const SKIN_ORDER := ["default", "desert", "forest", "tiger", "arctic", "carbon", "ice", "neon", "blood", "gold", "galaxy", "dragon"]
const RARITY_COLORS := {"common": Color("a0aabb"), "rare": Color("46a0ff"), "epic": Color("be5aff"), "legend": Color("ffbe28")}

# ---------------------------------------------------------------- powers (permanent upgrades, like Mini Militia perks)
# Each level costs prices[level]. Effects are applied by the host at spawn time.
const POWERS := {
	"armor": {"name": "Armor", "icon": "armor", "desc": "+15 max health per level",
		"currency": ["mfc", "mfc", "gem"], "prices": [500, 1200, 60]},
	"jet": {"name": "Jet Fuel", "icon": "jet", "desc": "+20% jetpack fuel per level",
		"currency": ["mfc", "mfc", "gem"], "prices": [400, 1000, 50]},
	"ammo": {"name": "Big Mags", "icon": "ammo", "desc": "+20% magazine size per level",
		"currency": ["mfc", "mfc", "gem"], "prices": [450, 1100, 50]},
	"reload": {"name": "Fast Hands", "icon": "reload", "desc": "-12% reload time per level",
		"currency": ["mfc", "mfc", "gem"], "prices": [450, 1100, 50]},
}
const POWER_ORDER := ["armor", "jet", "ammo", "reload"]
const POWER_MAX := 3

# pickups placed on the map (host-authoritative)
const PICKUP_HEAL := 50
const PICKUP_RESPAWN := 15.0

# ---------------------------------------------------------------- players
const PLAYER_COLORS := [
	Color("ff4d4d"), Color("4da6ff"), Color("4dff88"), Color("ffd24d"),
	Color("c44dff"), Color("ff8f4d"), Color("4dffff"), Color("ff4dc4"),
	Color("f2f2f2"), Color("8c8c8c"),
]
const TEAM_COLORS := [Color("ff4d4d"), Color("4da6ff")]
const TEAM_NAMES := ["Red", "Blue"]

# ---------------------------------------------------------------- modes
const MODE_FFA := 0
const MODE_TDM := 1
const MODE_NAMES := ["Free For All", "Team Deathmatch"]
const KILL_LIMITS := {0: 20, 1: 30}
const MATCH_TIMES := [180, 300, 480, 600]  # seconds
const MAX_PLAYERS := 12
const RESPAWN_TIME := 3.0
const MAX_HEALTH := 100

# ---------------------------------------------------------------- rewards (v1: earned by playing)
const REWARD_MFC_PER_KILL := 10
const REWARD_MFC_MATCH := 25
const REWARD_MFC_WIN := 60
const REWARD_GEM_PER_KILLS := 5     # +1 gem every N kills
const REWARD_GEM_WIN := 3
const REWARD_GEM_MATCH := 1
const BOT_REWARD_FACTOR := 0.5      # matches vs bots only give half
const REWARDED_AD_GEMS := 5         # gems for watching a rewarded ad (when ads plugin present)

## Gem packs sold for real money (needs Google Play Billing plugin, see docs).
const GEM_PACKS := [
	{"product_id": "gems_small", "gems": 80, "label": "80 Gems"},
	{"product_id": "gems_medium", "gems": 450, "label": "450 Gems"},
	{"product_id": "gems_large", "gems": 1000, "label": "1000 Gems"},
]

# ---------------------------------------------------------------- maps
# Each map: size, list of solid rects [x, y, w, h], spawn points per team.
const MAPS := [
	{
		"name": "Outpost",
		"size": Vector2(3200, 1800),
		"bg": Color("1b2233"),
		"solid": Color("3d4a5e"),
		"bg_image": "outpost", "tex": "metal", "tex_tint": Color(1, 1, 1), "lip": Color("ffc83a"), "edge": Color("0e1420"),
		"rects": [
			[0, 1700, 3200, 100],
			[200, 1450, 500, 40], [1000, 1500, 400, 40], [1800, 1500, 400, 40], [2500, 1450, 500, 40],
			[500, 1200, 350, 40], [1350, 1250, 500, 40], [2350, 1200, 350, 40],
			[150, 950, 400, 40], [1000, 950, 300, 40], [1900, 950, 300, 40], [2650, 950, 400, 40],
			[650, 700, 400, 40], [1400, 650, 400, 40], [2150, 700, 400, 40],
			[250, 420, 350, 40], [1250, 380, 700, 40], [2600, 420, 350, 40],
			[1570, 1520, 60, 180],
			[800, 1240, 40, 260], [2360, 1240, 40, 260],
		],
		"spawns": [
			[Vector2(250, 1600), Vector2(300, 1380), Vector2(250, 880), Vector2(320, 350), Vector2(600, 1130)],
			[Vector2(2950, 1600), Vector2(2900, 1380), Vector2(2950, 880), Vector2(2880, 350), Vector2(2600, 1130)],
		],
	},
	{
		"name": "Canyon",
		"size": Vector2(3600, 2000),
		"bg": Color("2b1d18"),
		"solid": Color("7a4b33"),
		"bg_image": "canyon", "tex": "rock", "tex_tint": Color(1.0, 0.72, 0.55), "lip": Color("e8a050"), "edge": Color("2a1208"),
		"rects": [
			[0, 1900, 1200, 100], [1500, 1900, 600, 100], [2400, 1900, 1200, 100],
			[1200, 1960, 300, 40], [2100, 1960, 300, 40],
			[0, 1300, 600, 600], [3000, 1300, 600, 600],
			[750, 1600, 300, 40], [2550, 1600, 300, 40],
			[1300, 1500, 1000, 40],
			[900, 1200, 400, 40], [2300, 1200, 400, 40],
			[1600, 1000, 400, 40],
			[300, 900, 500, 40], [2800, 900, 500, 40],
			[1100, 700, 300, 40], [2200, 700, 300, 40],
			[1500, 400, 600, 40],
			[1780, 1200, 40, 300],
		],
		"spawns": [
			[Vector2(200, 1200), Vector2(450, 1200), Vector2(450, 820), Vector2(850, 1530), Vector2(1000, 1100)],
			[Vector2(3400, 1200), Vector2(3150, 1200), Vector2(3150, 820), Vector2(2750, 1530), Vector2(2600, 1100)],
		],
	},
]


func weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS["pistol"])


func skin(id: String) -> Dictionary:
	return SKINS.get(id, SKINS["default"])


func color_by_index(i: int) -> Color:
	return PLAYER_COLORS[clampi(i, 0, PLAYER_COLORS.size() - 1)]


## Power effects for a lobby info dictionary ({"powers": {"armor": 2, ...}}).
func power_level(info: Dictionary, power_id: String) -> int:
	var pw = info.get("powers", {})
	if not pw is Dictionary:
		return 0
	return clampi(int(pw.get(power_id, 0)), 0, POWER_MAX)


func max_health_for(info: Dictionary) -> int:
	return MAX_HEALTH + 15 * power_level(info, "armor")


func fuel_factor_for(info: Dictionary) -> float:
	return 1.0 + 0.2 * power_level(info, "jet")


func mag_for(info: Dictionary, weapon_id: String) -> int:
	return int(round(float(weapon(weapon_id)["mag"]) * (1.0 + 0.2 * power_level(info, "ammo"))))


func reload_for(info: Dictionary, weapon_id: String) -> float:
	return float(weapon(weapon_id)["reload"]) * (1.0 - 0.12 * power_level(info, "reload"))
