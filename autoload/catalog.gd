extends Node
## Static game data: weapons, gun skins, player colors, maps and reward rules.
## Everything that a designer may want to tune lives here.

const GAME_VERSION := 3

# ---------------------------------------------------------------- weapons
# damage: per bullet/pellet. fire_delay: seconds between shots.
# speed: projectile speed px/s. life: projectile lifetime seconds.
# spread: radians (random +/-). pellets: projectiles per shot.
# splash: explosion radius (0 = none). auto: hold to fire.
const WEAPONS := {
	"pistol": {
		"name": "Desert Eagle", "damage": 26, "fire_delay": 0.3, "mag": 8, "reload": 1.2,
		"speed": 1700.0, "life": 0.62, "spread": 0.03, "pellets": 1, "splash": 0.0,
		"auto": false, "length": 26.0, "recoil": 40.0, "sound": "pistol", "scopes": [1, 2], "dual": true, "tier": 1
	},
	"smg": {
		"name": "Uzi", "damage": 9, "fire_delay": 0.07, "mag": 32, "reload": 1.4,
		"speed": 1400.0, "life": 0.5, "spread": 0.1, "pellets": 1, "splash": 0.0,
		"auto": true, "length": 34.0, "recoil": 16.0, "sound": "smg", "scopes": [1, 2], "dual": true, "tier": 1
	},
	"mp5": {
		"name": "MP5", "damage": 12, "fire_delay": 0.08, "mag": 30, "reload": 1.6,
		"speed": 1600.0, "life": 0.6, "spread": 0.06, "pellets": 1, "splash": 0.0,
		"auto": true, "length": 40.0, "recoil": 16.0, "sound": "smg", "scopes": [1, 2, 3], "dual": false, "tier": 2
	},
	"mp40": {
		"name": "MP40", "damage": 14, "fire_delay": 0.1, "mag": 32, "reload": 1.8,
		"speed": 1600.0, "life": 0.62, "spread": 0.07, "pellets": 1, "splash": 0.0,
		"auto": true, "length": 42.0, "recoil": 20.0, "sound": "smg", "scopes": [1, 2, 3], "dual": false, "tier": 2
	},
	"rifle": {
		"name": "AK-47", "damage": 17, "fire_delay": 0.11, "mag": 30, "reload": 1.9,
		"speed": 1900.0, "life": 0.8, "spread": 0.045, "pellets": 1, "splash": 0.0,
		"auto": true, "length": 46.0, "recoil": 28.0, "sound": "rifle", "scopes": [1, 2, 3, 4], "dual": false, "tier": 3
	},
	"woodpecker": {
		"name": "Woodpecker", "damage": 42, "fire_delay": 0.4, "mag": 12, "reload": 2.2,
		"speed": 2700.0, "life": 0.85, "spread": 0.008, "pellets": 1, "splash": 0.0,
		"auto": false, "length": 56.0, "recoil": 60.0, "sound": "sniper", "scopes": [1, 2, 3, 5], "dual": false, "tier": 3
	},
	"shotgun": {
		"name": "Shotgun", "damage": 12, "fire_delay": 0.75, "mag": 6, "reload": 2.2,
		"speed": 1300.0, "life": 0.32, "spread": 0.22, "pellets": 7, "splash": 0.0,
		"auto": false, "length": 42.0, "recoil": 90.0, "sound": "shotgun", "scopes": [1, 2], "dual": false, "tier": 3
	},
	"svd": {
		"name": "SVD", "damage": 62, "fire_delay": 0.6, "mag": 10, "reload": 2.4,
		"speed": 3300.0, "life": 1.0, "spread": 0.004, "pellets": 1, "splash": 0.0,
		"auto": false, "length": 60.0, "recoil": 90.0, "sound": "sniper", "scopes": [1, 2, 4, 7], "dual": false, "tier": 4
	},
	"sniper": {
		"name": "Sniper", "damage": 95, "fire_delay": 1.25, "mag": 5, "reload": 2.5,
		"speed": 3600.0, "life": 1.0, "spread": 0.0, "pellets": 1, "splash": 0.0,
		"auto": false, "length": 58.0, "recoil": 120.0, "sound": "sniper", "scopes": [1, 2, 4, 7], "dual": false, "tier": 4
	},
	"rocket": {
		"name": "Rocket", "damage": 75, "fire_delay": 1.4, "mag": 2, "reload": 2.8,
		"speed": 780.0, "life": 2.0, "spread": 0.0, "pellets": 1, "splash": 130.0,
		"auto": false, "length": 50.0, "recoil": 140.0, "sound": "rocket", "scopes": [1, 2, 3], "dual": false, "tier": 5
	},
}
## Order shown in menus (shop list, etc.).
const WEAPON_ORDER := ["pistol", "smg", "mp5", "mp40", "rifle", "woodpecker", "shotgun", "svd", "sniper", "rocket"]
## Everyone spawns with these two guns (slot 0, slot 1). Better guns are found on the map
## or dropped by killed players.
const START_WEAPONS := ["smg", "pistol"]
const PRIMARY_WEAPONS := WEAPON_ORDER  # kept for older code paths
const SECONDARY_WEAPON := "pistol"
const DUAL_FIRE_FACTOR := 0.55     # dual wield: fire delay multiplier
const GROUND_GUN_LIFETIME := 30.0  # dropped guns vanish after this
const GUN_SPOT_RESPAWN := 20.0     # map gun spots refill after this
const PICK_RADIUS := 60.0

# ---------------------------------------------------------------- bots
# aim: random aim error (radians). react: think interval range. lead: target lead factor.
# burst: chance to keep the trigger down each think. dmg: damage multiplier for bot shots.
const BOT_LEVELS := [
	{"name": "Easy", "aim": 0.3, "react": [0.75, 1.15], "lead": 0.0, "burst": 0.45, "dmg": 0.7, "dodge": 0.0, "loot": 0.2},
	{"name": "Normal", "aim": 0.14, "react": [0.4, 0.7], "lead": 0.4, "burst": 0.75, "dmg": 0.9, "dodge": 0.25, "loot": 0.5},
	{"name": "Hard", "aim": 0.06, "react": [0.22, 0.4], "lead": 0.8, "burst": 0.92, "dmg": 1.0, "dodge": 0.55, "loot": 0.8},
	{"name": "Legend", "aim": 0.02, "react": [0.12, 0.22], "lead": 1.0, "burst": 1.0, "dmg": 1.1, "dodge": 0.85, "loot": 1.0},
]

# ---------------------------------------------------------------- character skins
# head/body textures in assets/char (white parts are tinted with the player color).
const CHAR_SKINS := {
	"trooper": {"name": "Trooper", "currency": "mfc", "price": 0, "rarity": "common", "head": "head", "body": "body"},
	"commando": {"name": "Commando", "currency": "mfc", "price": 800, "rarity": "rare", "head": "head_commando", "body": "body_commando"},
	"pilot": {"name": "Ace Pilot", "currency": "mfc", "price": 1600, "rarity": "rare", "head": "head_pilot", "body": "body_pilot"},
	"ninja": {"name": "Ninja", "currency": "gem", "price": 40, "rarity": "epic", "head": "head_ninja", "body": "body_ninja"},
	"skull": {"name": "Reaper", "currency": "gem", "price": 70, "rarity": "epic", "head": "head_skull", "body": "body_skull"},
	"cyborg": {"name": "Cyborg", "currency": "gem", "price": 120, "rarity": "legend", "head": "head_cyborg", "body": "body_cyborg"},
	"legend": {"name": "Golden Knight", "currency": "gem", "price": 250, "rarity": "legend", "head": "head_legend", "body": "body_legend"},
}
const CHAR_ORDER := ["trooper", "commando", "pilot", "ninja", "skull", "cyborg", "legend"]

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
# Each map: size, list of solid rects [x, y, w, h, style?], spawn points per team.
# Optional keys (see _warzone): ground (terrain top profile), rooms (interior backgrounds),
# beams (decorative supports), props, guns (weapon spots), pickups.
var MAPS: Array = []
const CLASSIC_MAPS := [
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


func _init() -> void:
	MAPS = [_warzone()] + CLASSIC_MAPS


## Big symmetric map: rolling hills, a 3-floor HQ per team, bunkers, watchtowers,
## a 2-floor central fort and high catwalks. Built from the left half and mirrored.
func _warzone() -> Dictionary:
	var W := 6400.0
	var rects: Array = []
	var rooms: Array = []
	var beams: Array = []
	var props: Array = []
	var guns: Array = []
	var pickups: Array = []
	# ---- terrain top profile (left half), mirrored later
	var ground_l := [Vector2(0, 2000), Vector2(1050, 2000), Vector2(1180, 2040), Vector2(1300, 2110),
		Vector2(1420, 2150), Vector2(2150, 2150), Vector2(2250, 2080), Vector2(2330, 2000),
		Vector2(2400, 1960), Vector2(2540, 1960), Vector2(2640, 2010), Vector2(2770, 2050), Vector2(3200, 2050)]
	# ---- HQ (x 0..1000, ground 2000): floors 1740 / 1480, roof 1220, stair holes alternate
	rooms.append([0, 1220, 1000, 780])
	rects.append_array([[0, 1740, 700, 40, "concrete"], [840, 1740, 160, 40, "concrete"],
		[0, 1480, 160, 40, "concrete"], [300, 1480, 700, 40, "concrete"],
		[0, 1220, 700, 40, "concrete"], [840, 1220, 160, 40, "concrete"],
		[960, 1780, 40, 70, "concrete"], [960, 1520, 40, 70, "concrete"], [960, 1260, 40, 70, "concrete"],
		[960, 1160, 40, 60, "concrete"], [0, 1160, 40, 60, "concrete"],
		[480, 1950, 54, 50, "crate"], [220, 1690, 54, 50, "crate"], [560, 1430, 54, 50, "crate"], [534, 1964, 36, 36, "crate"]])
	props.append_array([[120, 2000, 3, 1.0], [700, 2000, 1, 0.8], [880, 1740, 3, 0.9], [400, 1480, 1, 0.8],
		[250, 1220, 5, 0.9], [900, 1220, 4, 1.0]])
	# ---- bunker (x 1500..2100 on ground 2150)
	rooms.append([1500, 2000, 600, 150])
	rects.append_array([[1480, 1960, 640, 40, "concrete"], [1540, 1915, 110, 45, "sandbag"], [1950, 1915, 110, 45, "sandbag"]])
	beams.append_array([[1530, 2000, 24, 150], [2066, 2000, 24, 150]])
	props.append_array([[1300, 2110, 4, 1.0], [1700, 2150, 1, 0.75], [2200, 2115, 2, 0.9]])
	# ---- watchtower on the hill
	rects.append_array([[2340, 1700, 220, 30, "metal"], [2340, 1440, 220, 30, "metal"], [2300, 1180, 300, 30, "metal"],
		[2300, 1140, 20, 40, "metal"], [2580, 1140, 20, 40, "metal"]])
	beams.append_array([[2356, 1210, 18, 760], [2526, 1210, 18, 760]])
	# ---- catwalks high in the sky
	rects.append_array([[1150, 1100, 450, 30, "metal"], [1750, 850, 420, 30, "metal"], [2700, 1300, 260, 30, "metal"]])
	beams.append_array([[1360, 1130, 14, 340], [1955, 880, 14, 260]])
	# ---- central fort (x 2850..3550, ground 2050), mirrored onto itself
	rooms.append([2850, 1530, 700, 520])
	rects.append_array([[2850, 1790, 280, 40, "concrete"], [3270, 1790, 280, 40, "concrete"],
		[2850, 1530, 700, 40, "concrete"],
		[2850, 1830, 40, 70, "concrete"], [3510, 1830, 40, 70, "concrete"],
		[2850, 1570, 40, 70, "concrete"], [3510, 1570, 40, 70, "concrete"],
		[2850, 1470, 40, 60, "concrete"], [3510, 1470, 40, 60, "concrete"],
		[3050, 1200, 300, 30, "metal"], [3175, 2000, 50, 50, "crate"]])
	beams.append_array([[3192, 1230, 16, 300]])
	props.append_array([[2960, 1790, 3, 0.9], [3200, 1530, 5, 1.0], [2780, 2050, 2, 0.9]])
	# ---- weapons and pickups (left half; mirrored)
	guns.append_array([[850, 1714, "mp5"], [400, 1194, "woodpecker"], [1800, 2124, "shotgun"],
		[2450, 1154, "svd"], [1960, 824, "mp40"], [3020, 2024, "rifle"], [1370, 1074, "rifle"]])
	pickups.append_array([[780, 1976, "medkit"], [800, 1456, "ammo"], [1650, 1936, "medkit"], [2450, 1676, "ammo"],
		[3000, 1766, "medkit"], [2830, 1276, "ammo"]])
	var center_guns := [[3200, 1504, "rocket"], [3200, 1174, "sniper"]]
	# ---- mirror everything onto the right half
	var ground: Array = ground_l.duplicate()
	for i in range(ground_l.size() - 2, -1, -1):
		ground.append(Vector2(W - ground_l[i].x, ground_l[i].y))
	var mirror_rect := func(r: Array) -> Array:
		var o := r.duplicate()
		o[0] = W - float(r[0]) - float(r[2])
		return o
	for list in [rects, rooms, beams]:
		var extra: Array = []
		for r in list:
			var m: Array = mirror_rect.call(r)
			if absf(float(m[0]) - float(r[0])) > 1.0:
				extra.append(m)
		list.append_array(extra)
	for list in [props, guns, pickups]:
		var extra: Array = []
		for it in list:
			var o: Array = it.duplicate()
			o[0] = W - float(it[0])
			if absf(float(o[0]) - float(it[0])) > 1.0:
				extra.append(o)
		list.append_array(extra)
	guns.append_array(center_guns)
	var sp_l := [Vector2(300, 1950), Vector2(650, 1950), Vector2(450, 1690), Vector2(800, 1430), Vector2(450, 1170), Vector2(1200, 1990)]
	var sp_r: Array = []
	for v in sp_l:
		sp_r.append(Vector2(W - v.x, v.y))
	return {
		"name": "Warzone",
		"size": Vector2(W, 2300),
		"bg": Color("141a2e"),
		"solid": Color("4a5468"),
		"bg_image": "warzone", "tex": "metal", "tex_tint": Color(1, 1, 1), "lip": Color("ffc83a"), "edge": Color("0b0f1a"),
		"ground_tex": "dirt", "ground_tint": Color(1, 1, 1),
		"rects": rects, "rooms": rooms, "beams": beams, "props": props,
		"ground": ground, "guns": guns, "pickups": pickups,
		"spawns": [sp_l, sp_r],
	}


func weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS["pistol"])


func char_skin(id: String) -> Dictionary:
	return CHAR_SKINS.get(id, CHAR_SKINS["trooper"])


func bot_level(i: int) -> Dictionary:
	return BOT_LEVELS[clampi(i, 0, BOT_LEVELS.size() - 1)]


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
