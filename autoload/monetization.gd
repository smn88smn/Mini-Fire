extends Node
## Monetization facade: rewarded ads (free gems) and real-money gem packs.
##
## Game code ONLY talks to this file. The plugins are detected at runtime by their
## global class names, so the project compiles and runs with or without them:
##   - Ads:     Poing Studios "Godot AdMob Plugin"   (classes MobileAds, RewardedAdLoader, ...)
##   - Billing: official "GodotGooglePlayBilling"    (class BillingClient)
##
## v1 (LAN, no server): ads + local gem balance.
## v2 (with server):    purchases must be verified server-side before gems are granted
##                      (see _grant_purchase).
##
## Without plugins (desktop / editor) everything reports "unavailable",
## except inside the editor where SIMULATE_IN_EDITOR lets you test the UI flow.

signal reward_granted(gems: int)
signal purchase_completed(product_id: String, gems: int)
signal purchase_failed(product_id: String, reason: String)

const SIMULATE_IN_EDITOR := true

## Google's official TEST rewarded unit. Replace with your own unit id before release.
const REWARDED_AD_UNIT := "ca-app-pub-3940256099942544/5224354917"

var _ads_ok := false
var _ad_loading := false
var _rewarded_ad = null

var _billing = null
var _billing_connected := false
var _pending_tokens: Dictionary = {}  # purchase_token -> product_id
var _granted_tokens: Dictionary = {}  # avoid double grants in one session


func _ready() -> void:
	_init_ads()
	_init_billing()


func _simulated() -> bool:
	return SIMULATE_IN_EDITOR and OS.has_feature("editor")


## Returns the script of a global class (e.g. from an addon) or null if missing.
func _global_class(class_id: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c.get("class", "") == class_id:
			return load(c["path"])
	return null


func _const(script: Script, enum_name: String, key: String, fallback):
	if script == null:
		return fallback
	var m: Dictionary = script.get_script_constant_map()
	if m.has(enum_name) and m[enum_name] is Dictionary and m[enum_name].has(key):
		return m[enum_name][key]
	return fallback


# ================================================================ public API
func ads_available() -> bool:
	return _ads_ok or _simulated()


func billing_available() -> bool:
	return (_billing != null and _billing_connected) or _simulated()


## Loads and shows a rewarded ad. Gems are granted when the user earns the reward.
func show_rewarded_ad() -> void:
	if _ads_ok:
		_ads_load_and_show()
	elif _simulated():
		_on_ad_rewarded()


func buy_gem_pack(product_id: String) -> void:
	if _pack(product_id).is_empty():
		purchase_failed.emit(product_id, "unknown product")
		return
	if _billing != null and _billing_connected:
		var res = _billing.purchase(product_id)
		if res is Dictionary and int(res.get("response_code", 0)) != _billing_ok():
			purchase_failed.emit(product_id, str(res.get("debug_message", "billing error")))
	elif _simulated():
		_grant_purchase(product_id, "editor-sim-%d" % Time.get_ticks_msec())
	else:
		purchase_failed.emit(product_id, "store unavailable")


# ================================================================ internal
func _pack(product_id: String) -> Dictionary:
	for p in Catalog.GEM_PACKS:
		if p["product_id"] == product_id:
			return p
	return {}


func _on_ad_rewarded() -> void:
	Profile.add_currency(0, Catalog.REWARDED_AD_GEMS)
	reward_granted.emit(Catalog.REWARDED_AD_GEMS)


func _grant_purchase(product_id: String, token: String) -> void:
	if _granted_tokens.has(token):
		return
	var pack := _pack(product_id)
	if pack.is_empty():
		return
	_granted_tokens[token] = true
	# v2 TODO: send `token` to your server, verify it with the Google Play Developer API,
	# and let the SERVER credit the gems to the player's account instead of this line.
	Profile.add_currency(0, int(pack["gems"]))
	purchase_completed.emit(product_id, int(pack["gems"]))


# ================================================================ ADS (Poing Studios AdMob)
func _init_ads() -> void:
	if not OS.has_feature("android") and not OS.has_feature("ios"):
		return
	var mobile_ads := _global_class("MobileAds")
	if mobile_ads == null or _global_class("RewardedAdLoader") == null:
		return
	mobile_ads.initialize()
	_ads_ok = true


func _ads_load_and_show() -> void:
	if _ad_loading:
		return
	_ad_loading = true
	var loader = _global_class("RewardedAdLoader").new()
	var cb = _global_class("RewardedAdLoadCallback").new()
	cb.on_ad_loaded = _on_rewarded_loaded
	cb.on_ad_failed_to_load = _on_rewarded_failed
	loader.load(REWARDED_AD_UNIT, _global_class("AdRequest").new(), cb)


func _on_rewarded_loaded(ad) -> void:
	_ad_loading = false
	_rewarded_ad = ad
	var listener = _global_class("OnUserEarnedRewardListener").new()
	listener.on_user_earned_reward = _on_user_earned_reward
	ad.show(listener)


func _on_user_earned_reward(_item = null) -> void:
	_on_ad_rewarded()
	if _rewarded_ad and _rewarded_ad.has_method("destroy"):
		_rewarded_ad.destroy()
	_rewarded_ad = null


func _on_rewarded_failed(_err = null) -> void:
	_ad_loading = false
	purchase_failed.emit("", "No ad available right now")


# ================================================================ BILLING (official GodotGooglePlayBilling 2.x+)
func _billing_ok() -> int:
	return int(_const(_global_class("BillingClient"), "BillingResponseCode", "OK", 0))


func _init_billing() -> void:
	if not OS.has_feature("android"):
		return
	var cls := _global_class("BillingClient")
	if cls == null:
		return
	_billing = cls.new()
	_billing.connected.connect(_on_billing_connected)
	_billing.disconnected.connect(func(): _billing_connected = false)
	_billing.connect_error.connect(func(_code, _msg): _billing_connected = false)
	if _billing.has_signal("on_purchase_updated"):
		_billing.on_purchase_updated.connect(_on_purchases_updated)
	elif _billing.has_signal("on_purchases_updated"):
		_billing.on_purchases_updated.connect(_on_purchases_updated)
	_billing.query_purchases_response.connect(_on_purchases_updated)
	_billing.consume_purchase_response.connect(_on_consume_response)
	_billing.start_connection()


func _on_billing_connected() -> void:
	_billing_connected = true
	# finish any purchase that was paid but not consumed (e.g. app was killed)
	var inapp = _const(_global_class("BillingClient"), "ProductType", "INAPP", 0)
	_billing.query_purchases(inapp)


func _on_purchases_updated(result: Dictionary) -> void:
	if int(result.get("response_code", -1)) != _billing_ok():
		var msg := str(result.get("debug_message", "purchase cancelled"))
		purchase_failed.emit("", msg)
		return
	var purchased := int(_const(_global_class("BillingClient"), "PurchaseState", "PURCHASED", 1))
	for p in result.get("purchases", []):
		if int(p.get("purchase_state", 0)) != purchased:
			continue  # pending purchases are completed later by Google Play
		var token := str(p.get("purchase_token", ""))
		for id in p.get("product_ids", []):
			if not _pack(str(id)).is_empty() and token != "" and not _pending_tokens.has(token):
				_pending_tokens[token] = str(id)
				_billing.consume_purchase(token)


func _on_consume_response(result: Dictionary) -> void:
	var token := str(result.get("token", ""))
	var pid: String = _pending_tokens.get(token, "")
	_pending_tokens.erase(token)
	if int(result.get("response_code", -1)) == _billing_ok() and pid != "":
		_grant_purchase(pid, token)
	elif pid != "":
		purchase_failed.emit(pid, str(result.get("debug_message", "consume failed")))
