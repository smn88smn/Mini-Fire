extends Node
## Static game data: weapons, gun skins, player colors, maps and reward rules.
## Everything that a designer may want to tune lives here.

const GAME_VERSION := 1

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
# pattern: plain | stripes | camo | gold | neon | carbon
const SKINS := {
	"default": {"name": "Factory", "currency": "mfc", "price": 0,
		"base": Color("3a3f4b"), "accent": Color("1f2229"), "pattern": "plain"},
	"desert": {"name": "Desert", "currency": "mfc", "price": 400,
		"base": Color("c8a96b"), "accent": Color("8a6d3b"), "pattern": "camo"},
	"forest": {"name": "Forest", "currency": "mfc", "price": 400,
		"base": Color("4f6b3a"), "accent": Color("2c3d22"), "pattern": "camo"},
	"tiger": {"name": "Tiger", "currency": "mfc", "price": 900,
		"base": Color("ff8c1a"), "accent": Color("1a1a1a"), "pattern": "stripes"},
	"carbon": {"name": "Carbon", "currency": "gem", "price": 25,
		"base": Color("22252b"), "accent": Color("3c4250"), "pattern": "carbon"},
	"ice": {"name": "Ice", "currency": "gem", "price": 40,
		"base": Color("9fe7ff"), "accent": Color("ffffff"), "pattern": "stripes"},
	"neon": {"name": "Neon", "currency": "gem", "price": 60,
		"base": Color("12121a"), "accent": Color("39ff14"), "pattern": "neon"},
	"blood": {"name": "Blood Moon", "currency": "gem", "price": 80,
		"base": Color("5a0a12"), "accent": Color("ff2a3d"), "pattern": "neon"},
	"gold": {"name": "Gold", "currency": "gem", "price": 150,
		"base": Color("ffcc33"), "accent": Color("b8860b"), "pattern": "gold"},
}
const SKIN_ORDER := ["default", "desert", "forest", "tiger", "carbon", "ice", "neon", "blood", "gold"]

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
