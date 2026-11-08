extends Node
## Cloud save facade: Google Sign-In (account picker) + Firestore profile backup.
##
## Uses the godot-firebase plugin (addons/FirebasePlugin, Android aar) when it is
## available at runtime. Game code ONLY talks to this file:
##   Cloud.available() / Cloud.sign_in_google() / Cloud.sign_out()
##   Cloud.save_soon() (automatic after wallet/profile changes)
## On reinstall, sign in with the same Google account and the profile (wallet,
## skins, characters, gun levels, stats) is restored from Firestore and merged.
##
## Without the plugin (desktop / editor / APK built without google-services.json)
## every call is a harmless no-op and `available()` returns false.

signal signed_in(email: String)
signal sign_in_failed(reason: String)
signal cloud_saved
signal cloud_loaded
signal cloud_load_failed(reason: String)

const COLLECTION := "players"
const SAVE_DEBOUNCE := 4.0

var _fb: Node = null
var _auth: Node = null
var _firestore: Node = null
var _uid := ""
var _email := ""
var _save_t := 0.0
var _want_save := false
var _pending_load := false

func _ready() -> void:
	# The plugin's Android singleton only exists in a gradle-built Android APK.
	if not Engine.has_singleton("FirebasePlugin"):
		return
	var firebase_cls := _global_class("Firebase")
	var auth_cls := _global_class("FirebaseAuth")
	var fs_cls := _global_class("Firestore")
	if firebase_cls == null or auth_cls == null or fs_cls == null:
		return
	_fb = firebase_cls.new()
	_auth = auth_cls.new()
	_firestore = fs_cls.new()
	_fb.add_child(_auth)
	_fb.add_child(_firestore)
	add_child(_fb)
	_auth.auth_success.connect(_on_auth_success)
	_auth.auth_failure.connect(_on_auth_failure)
	_firestore.document_query_completed.connect(_on_doc_loaded)
	_firestore.document_query_failed.connect(_on_load_failed)
	Profile.wallet_changed.connect(save_soon)
	Profile.profile_changed.connect(save_soon)
	# restore a previous session (if the user already signed in on this device)
	if _auth.is_signed_in():
		var user = _auth.get_current_user()
		if user != null:
			_on_auth_success(user)
		else:
			_sign_in_silent()

func _sign_in_silent() -> void:
	# plugin keeps the Google session; try to pick it back up
	_auth.sign_in_with_google()

# ================================================================ public API
func available() -> bool:
	return _fb != null

func is_signed_in() -> bool:
	return _uid != ""

func account_email() -> String:
	return _email

## Opens the Google account picker and signs in (or fails).
func sign_in_google() -> void:
	if _auth == null:
		sign_in_failed.emit("Google Sign-In is not available in this build")
		return
	_auth.sign_in_with_google()

func sign_out() -> void:
	if _auth != null:
		_auth.sign_out()
	_uid = ""
	_email = ""
	Profile.cloud_uid = ""
	Profile.cloud_email = ""
	Profile.save_profile()

## Uploads the current profile to Firestore (debounced).
func save_soon() -> void:
	if _fb == null or _uid == "":
		return
	_want_save = true
	_save_t = SAVE_DEBOUNCE

## Uploads immediately (e.g. right after sign-in).
func save_now() -> void:
	if _fb == null or _uid == "":
		return
	var snap := _snapshot()
	var doc = _global_class("FirestoreDocument").new()
	doc.set_collection(COLLECTION).set_document_id(_uid)
	for k in snap.keys():
		doc.set_value(k, snap[k])
	_firestore.set_document(doc)
	cloud_saved.emit()

## Downloads the cloud profile and merges it into the local one.
func load_cloud() -> void:
	if _firestore == null or _uid == "":
		return
	_pending_load = true
	_firestore.get_document(COLLECTION, _uid)

func _process(delta: float) -> void:
	if _want_save:
		_save_t -= delta
		if _save_t <= 0.0:
			_want_save = false
			save_now()

# ================================================================ internal
func _global_class(class_id: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c.get("class", "") == class_id:
			return load(c["path"])
	return null

func _snapshot() -> Dictionary:
	return {
		"name": Profile.player_name,
		"mfc": Profile.mfc,
		"gems": Profile.gems,
		"owned_skins": Profile.owned_skins,
		"equipped_skins": Profile.equipped_skins,
		"powers": Profile.powers,
		"gun_levels": Profile.gun_levels,
		"owned_chars": Profile.owned_chars,
		"char_skin": Profile.char_skin,
		"redeemed_codes": Profile.redeemed_codes,
		"total_kills": Profile.total_kills,
		"total_deaths": Profile.total_deaths,
		"matches_played": Profile.matches_played,
		"wins": Profile.wins,
		"color_index": Profile.color_index,
		"updated": Time.get_unix_time_from_system(),
	}

func _on_auth_success(user) -> void:
	_uid = str(user.get_user_id())
	_email = str(user.get_email())
	Profile.cloud_uid = _uid
	Profile.cloud_email = _email
	Profile.save_profile()
	signed_in.emit(_email)
	# merge cloud backup first (reinstall recovery), then upload the merged state
	load_cloud()
	save_soon()

func _on_auth_failure(reason: String) -> void:
	sign_in_failed.emit(reason)

func _on_doc_loaded(doc) -> void:
	if not _pending_load:
		return
	_pending_load = false
	var data: Dictionary = doc.get_all_values()
	if data.is_empty():
		cloud_loaded.emit()
		return
	_apply_cloud(data)
	cloud_loaded.emit()
	save_soon()

func _on_load_failed(_error) -> void:
	if _pending_load:
		_pending_load = false
		cloud_load_failed.emit("Could not read cloud save (new account?)")
		save_soon()

## Merges a cloud snapshot into the local profile: keeps the best of both.
func _apply_cloud(data: Dictionary) -> void:
	Profile.mfc = maxi(Profile.mfc, int(data.get("mfc", 0)))
	Profile.gems = maxi(Profile.gems, int(data.get("gems", 0)))
	Profile.total_kills = maxi(Profile.total_kills, int(data.get("total_kills", 0)))
	Profile.total_deaths = maxi(Profile.total_deaths, int(data.get("total_deaths", 0)))
	Profile.matches_played = maxi(Profile.matches_played, int(data.get("matches_played", 0)))
	Profile.wins = maxi(Profile.wins, int(data.get("wins", 0)))
	_merge_list(Profile.owned_skins, data.get("owned_skins", []), "default")
	_merge_list(Profile.owned_chars, data.get("owned_chars", []), "trooper")
	_merge_list(Profile.redeemed_codes, data.get("redeemed_codes", []), "")
	var eq = data.get("equipped_skins", {})
	if eq is Dictionary:
		for k in eq:
			if Profile.owns_skin(str(eq[k])):
				Profile.equipped_skins[k] = eq[k]
	var pw = data.get("powers", {})
	if pw is Dictionary:
		for k in Catalog.POWERS.keys():
			var lvl := clampi(int(pw.get(k, 0)), 0, Catalog.POWER_MAX)
			Profile.powers[k] = maxi(Profile.power_level(k), lvl)
	var gl = data.get("gun_levels", {})
	if gl is Dictionary:
		for w in Catalog.WEAPON_ORDER:
			var lvl := clampi(int(gl.get(w, 1)), 1, Catalog.GUN_LEVEL_MAX)
			Profile.gun_levels[w] = maxi(Profile.gun_level(w), lvl)
	var ch := str(data.get("char_skin", ""))
	if ch != "" and Profile.owns_char(ch):
		Profile.char_skin = ch
	var ci := int(data.get("color_index", -1))
	if ci >= 0 and ci < Catalog.PLAYER_COLORS.size():
		Profile.color_index = ci
	Profile.save_profile()
	Profile.wallet_changed.emit()
	Profile.profile_changed.emit()

func _merge_list(into: Array, from, must_have: String) -> void:
	if not from is Array:
		return
	for v in from:
		var s := str(v)
		if not s in into:
			into.append(s)
	if must_have != "" and not must_have in into:
		into.append(must_have)
