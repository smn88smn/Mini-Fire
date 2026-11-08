extends Node
## Local player profile: name, color, wallet (MFC + Gems), owned/equipped skins, settings.
## Saved encrypted to user:// so casual editing of the save file does not work.
## NOTE: when real-money gems are enabled, the gem balance must move to a server (see docs).

signal wallet_changed
signal profile_changed

const SAVE_PATH := "user://profile.save"
const SAVE_KEY := "MiniFire::v1::673eec6d1c4a09e814693a1654a36c82a2983d6b40cbea01"

var player_name: String = ""
var color_index: int = 0
var primary_weapon: String = "smg"  # weapon shown in the shop first
var mfc: int = 0
var gems: int = 0
var owned_skins: Array = ["default"]
var equipped_skins: Dictionary = {}  # weapon_id -> skin_id
var powers: Dictionary = {}  # power_id -> level (0..Catalog.POWER_MAX)
var total_kills: int = 0
var total_deaths: int = 0
var matches_played: int = 0
var wins: int = 0
var sfx_volume: float = 0.8
var touch_controls: int = 0  # 0 auto, 1 always on, 2 off
var last_join_ip: String = ""
var char_skin: String = "trooper"
var owned_chars: Array = ["trooper"]
var bot_level: int = 1
## Touch layout overrides: control id -> [x_frac, y_frac, scale]. Empty = defaults.
var controls: Dictionary = {}
## Per-weapon level 1..Catalog.GUN_LEVEL_MAX (raised in the Spin Shop).
var gun_levels: Dictionary = {}  # weapon_id -> int
## Redeemed gift codes (Telegram gem sales) so a code cannot be reused locally.
var redeemed_codes: Array = []
## Cloud account (set after Google Sign-In; see autoload/cloud.gd).
var cloud_uid: String = ""
var cloud_email: String = ""


func _ready() -> void:
	load_profile()
	if player_name.is_empty():
		player_name = "Player%d" % (randi() % 9000 + 1000)
		save_profile()


# ---------------------------------------------------------------- wallet
func add_currency(add_mfc: int, add_gems: int) -> void:
	mfc = maxi(0, mfc + add_mfc)
	gems = maxi(0, gems + add_gems)
	save_profile()
	wallet_changed.emit()


func can_afford(currency: String, price: int) -> bool:
	return (mfc if currency == "mfc" else gems) >= price


## Returns true if the skin was bought (or already owned).
func buy_skin(skin_id: String) -> bool:
	if owns_skin(skin_id):
		return true
	if not Catalog.SKINS.has(skin_id):
		return false
	var s: Dictionary = Catalog.SKINS[skin_id]
	var price: int = s["price"]
	if not can_afford(s["currency"], price):
		return false
	if s["currency"] == "mfc":
		mfc -= price
	else:
		gems -= price
	owned_skins.append(skin_id)
	save_profile()
	wallet_changed.emit()
	profile_changed.emit()
	return true


func owns_skin(skin_id: String) -> bool:
	return skin_id in owned_skins


func equip_skin(weapon_id: String, skin_id: String) -> void:
	if not owns_skin(skin_id):
		return
	equipped_skins[weapon_id] = skin_id
	save_profile()
	profile_changed.emit()


func skin_for(weapon_id: String) -> String:
	var s: String = equipped_skins.get(weapon_id, "default")
	return s if owns_skin(s) else "default"


# ---------------------------------------------------------------- character skins
func owns_char(id: String) -> bool:
	return id in owned_chars


func buy_char(id: String) -> bool:
	if owns_char(id):
		return true
	if not Catalog.CHAR_SKINS.has(id):
		return false
	var c: Dictionary = Catalog.CHAR_SKINS[id]
	if not can_afford(c["currency"], int(c["price"])):
		return false
	if c["currency"] == "mfc":
		mfc -= int(c["price"])
	else:
		gems -= int(c["price"])
	owned_chars.append(id)
	save_profile()
	wallet_changed.emit()
	profile_changed.emit()
	return true


func equip_char(id: String) -> void:
	if owns_char(id):
		char_skin = id
		save_profile()
		profile_changed.emit()


# ---------------------------------------------------------------- powers
func power_level(power_id: String) -> int:
	return clampi(int(powers.get(power_id, 0)), 0, Catalog.POWER_MAX)


## Returns {"currency", "price"} for the next level, or {} when maxed.
func next_power_cost(power_id: String) -> Dictionary:
	var lvl := power_level(power_id)
	if lvl >= Catalog.POWER_MAX or not Catalog.POWERS.has(power_id):
		return {}
	var p: Dictionary = Catalog.POWERS[power_id]
	return {"currency": p["currency"][lvl], "price": int(p["prices"][lvl])}


func buy_power(power_id: String) -> bool:
	var cost := next_power_cost(power_id)
	if cost.is_empty() or not can_afford(cost["currency"], cost["price"]):
		return false
	if cost["currency"] == "mfc":
		mfc -= int(cost["price"])
	else:
		gems -= int(cost["price"])
	powers[power_id] = power_level(power_id) + 1
	save_profile()
	wallet_changed.emit()
	profile_changed.emit()
	return true


# ---------------------------------------------------------------- gun levels
func gun_level(weapon_id: String) -> int:
	return clampi(int(gun_levels.get(weapon_id, 1)), 1, Catalog.GUN_LEVEL_MAX)

func set_gun_level(weapon_id: String, level: int) -> void:
	gun_levels[weapon_id] = clampi(level, 1, Catalog.GUN_LEVEL_MAX)
	save_profile()
	profile_changed.emit()

## Adds levels (from the Spin Shop). Returns the new level.
func add_gun_levels(weapon_id: String, add: int) -> int:
	var nl := clampi(gun_level(weapon_id) + add, 1, Catalog.GUN_LEVEL_MAX)
	set_gun_level(weapon_id, nl)
	return nl

# ---------------------------------------------------------------- gift codes
func redeem_code(code: String) -> int:
	## Returns gems granted, or -1 if the code is invalid, -2 if already used.
	var clean := code.strip_edges().to_upper()
	if clean in redeemed_codes:
		return -2
	var gems := _code_gems(clean)
	if gems <= 0:
		return -1
	redeemed_codes.append(clean)
	add_currency(0, gems)
	save_profile()
	return gems

## Validates a gift code: "MF-<payload>-<checksum>-<gems>" where <checksum> is
## derived from the payload with HMAC-SHA256 + the app secret (see tools/gem_codes.py).
const CODE_SECRET := "MiniFire::gems::7f3a9c2e51b8d046"
const CODE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

func _code_gems(code: String) -> int:
	# format: MF-<payload>-<checksum>-<gems>
	var parts := code.split("-")
	if parts.size() != 4 or parts[0] != "MF":
		return 0
	var payload := parts[1]
	var checksum := parts[2]
	if not _checksum_ok(payload, checksum):
		return 0
	var gems := int(parts[3])
	if gems <= 0 or gems > 100000:
		return 0
	return gems

func _checksum_ok(payload: String, checksum: String) -> bool:
	var crypto := Crypto.new()
	var key := CODE_SECRET.to_utf8_buffer()
	var mac := crypto.hmac_digest(HashingContext.HASH_SHA256, key, payload.to_utf8_buffer())
	var want := ""
	for i in 5:
		var byte := int(mac[i])
		want += CODE_ALPHABET[(byte >> 3) & 31] if i % 2 == 0 else CODE_ALPHABET[byte & 31]
	return want == checksum

# ---------------------------------------------------------------- rewards
## stats: {kills, deaths, won(bool), vs_bots_only(bool)}. Returns {mfc, gems}.
func grant_match_rewards(kills: int, deaths: int, won: bool, bots_only: bool) -> Dictionary:
	var r_mfc := Catalog.REWARD_MFC_MATCH + kills * Catalog.REWARD_MFC_PER_KILL
	var r_gems := Catalog.REWARD_GEM_MATCH + int(kills / float(Catalog.REWARD_GEM_PER_KILLS))
	if won:
		r_mfc += Catalog.REWARD_MFC_WIN
		r_gems += Catalog.REWARD_GEM_WIN
	if bots_only:
		r_mfc = int(r_mfc * Catalog.BOT_REWARD_FACTOR)
		r_gems = int(r_gems * Catalog.BOT_REWARD_FACTOR)
	total_kills += kills
	total_deaths += deaths
	matches_played += 1
	if won:
		wins += 1
	add_currency(r_mfc, r_gems)
	return {"mfc": r_mfc, "gems": r_gems}


# ---------------------------------------------------------------- network info
## Info sent to the host when joining a lobby.
func lobby_info() -> Dictionary:
	var skins := {}
	for w in Catalog.WEAPONS.keys():
		skins[w] = skin_for(w)
	var glvls := {}
	for w in Catalog.WEAPON_ORDER:
		glvls[w] = gun_level(w)
	return {
		"name": player_name.substr(0, 16),
		"color": color_index,
		"skins": skins,
		"char": char_skin if owns_char(char_skin) else "trooper",
		"powers": powers.duplicate(),
		"gun_levels": glvls,
		"team": color_index,
		"bot": false,
	}


# ---------------------------------------------------------------- persistence
func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("p", "name", player_name)
	cfg.set_value("p", "color", color_index)
	cfg.set_value("w", "mfc", mfc)
	cfg.set_value("w", "gems", gems)
	cfg.set_value("s", "owned", owned_skins)
	cfg.set_value("s", "equipped", equipped_skins)
	cfg.set_value("s", "powers", powers)
	cfg.set_value("st", "kills", total_kills)
	cfg.set_value("st", "deaths", total_deaths)
	cfg.set_value("st", "matches", matches_played)
	cfg.set_value("st", "wins", wins)
	cfg.set_value("o", "sfx", sfx_volume)
	cfg.set_value("o", "touch", touch_controls)
	cfg.set_value("o", "ip", last_join_ip)
	cfg.set_value("c", "skin", char_skin)
	cfg.set_value("c", "owned", owned_chars)
	cfg.set_value("o", "bots", bot_level)
	cfg.set_value("o", "controls", controls)
	cfg.set_value("g", "levels", gun_levels)
	cfg.set_value("g", "codes", redeemed_codes)
	cfg.set_value("cl", "uid", cloud_uid)
	cfg.set_value("cl", "email", cloud_email)
	var err := cfg.save_encrypted_pass(SAVE_PATH, SAVE_KEY)
	if err != OK:
		push_warning("Profile save failed: %s" % error_string(err))


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	if cfg.load_encrypted_pass(SAVE_PATH, SAVE_KEY) != OK:
		push_warning("Profile corrupted or tampered, starting fresh")
		return
	player_name = str(cfg.get_value("p", "name", ""))
	color_index = clampi(int(cfg.get_value("p", "color", 0)), 0, Catalog.PLAYER_COLORS.size() - 1)
	mfc = maxi(0, int(cfg.get_value("w", "mfc", 0)))
	gems = maxi(0, int(cfg.get_value("w", "gems", 0)))
	var o = cfg.get_value("s", "owned", ["default"])
	owned_skins = o if o is Array else ["default"]
	if not "default" in owned_skins:
		owned_skins.append("default")
	var e = cfg.get_value("s", "equipped", {})
	equipped_skins = e if e is Dictionary else {}
	var pw = cfg.get_value("s", "powers", {})
	powers = pw if pw is Dictionary else {}
	total_kills = int(cfg.get_value("st", "kills", 0))
	total_deaths = int(cfg.get_value("st", "deaths", 0))
	matches_played = int(cfg.get_value("st", "matches", 0))
	wins = int(cfg.get_value("st", "wins", 0))
	sfx_volume = clampf(float(cfg.get_value("o", "sfx", 0.8)), 0.0, 1.0)
	touch_controls = clampi(int(cfg.get_value("o", "touch", 0)), 0, 2)
	last_join_ip = str(cfg.get_value("o", "ip", ""))
	var oc = cfg.get_value("c", "owned", ["trooper"])
	owned_chars = oc if oc is Array else ["trooper"]
	if not "trooper" in owned_chars:
		owned_chars.append("trooper")
	char_skin = str(cfg.get_value("c", "skin", "trooper"))
	if not owns_char(char_skin):
		char_skin = "trooper"
	bot_level = clampi(int(cfg.get_value("o", "bots", 1)), 0, Catalog.BOT_LEVELS.size() - 1)
	var ct = cfg.get_value("o", "controls", {})
	controls = ct if ct is Dictionary else {}
	var gl = cfg.get_value("g", "levels", {})
	gun_levels = gl if gl is Dictionary else {}
	for w in Catalog.WEAPON_ORDER:
		if not gun_levels.has(w):
			gun_levels[w] = 1
	var rc = cfg.get_value("g", "codes", [])
	redeemed_codes = rc if rc is Array else []
	cloud_uid = str(cfg.get_value("cl", "uid", ""))
	cloud_email = str(cfg.get_value("cl", "email", ""))


func use_touch_controls() -> bool:
	if touch_controls == 1:
		return true
	if touch_controls == 2:
		return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
