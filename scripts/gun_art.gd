class_name GunArt
extends RefCounted
## Gun sprites + skins. Guns are hand-painted PNGs (assets/guns) recolored by
## shaders/gun_skin.gdshader. Coordinates: +X is the aim direction, origin is the shoulder.

const SHADER := preload("res://shaders/gun_skin.gdshader")

## Per weapon: display width (px in world), hand grip and fore-grip in texture pixels,
## muzzle Y in texture pixels. Textures are 512 px wide.
const ART := {
	"pistol": {"w": 42.0, "grip": Vector2(82, 150), "fore": Vector2(-1, -1), "muzzle_y": 43.0},
	"mp5": {"w": 62.0, "grip": Vector2(180, 105), "fore": Vector2(370, 52), "muzzle_y": 45.5},
	"mp40": {"w": 66.0, "grip": Vector2(150, 82), "fore": Vector2(285, 100), "muzzle_y": 24.5},
	"woodpecker": {"w": 92.0, "grip": Vector2(125, 100), "fore": Vector2(300, 57), "muzzle_y": 55.5},
	"svd": {"w": 104.0, "grip": Vector2(112, 78), "fore": Vector2(285, 42), "muzzle_y": 49.0},
	"smg": {"w": 54.0, "grip": Vector2(228, 128), "fore": Vector2(400, 60), "muzzle_y": 60.5},
	"rifle": {"w": 84.0, "grip": Vector2(150, 88), "fore": Vector2(340, 66), "muzzle_y": 40.0},
	"shotgun": {"w": 84.0, "grip": Vector2(128, 72), "fore": Vector2(360, 46), "muzzle_y": 18.0},
	"sniper": {"w": 100.0, "grip": Vector2(118, 88), "fore": Vector2(300, 60), "muzzle_y": 50.5},
	"rocket": {"w": 88.0, "grip": Vector2(240, 112), "fore": Vector2(355, 112), "muzzle_y": 67.5},
}
const TEX_W := 512.0
const MUZZLE_PX := 509.0
const HAND_X := 8.0  # where the hand sits in front of the shoulder

static var _tex_cache: Dictionary = {}


static func texture(weapon_id: String) -> Texture2D:
	if not _tex_cache.has(weapon_id):
		var id := weapon_id if ART.has(weapon_id) else "pistol"
		_tex_cache[weapon_id] = load("res://assets/guns/%s.png" % id)
	return _tex_cache[weapon_id]


static func art(weapon_id: String) -> Dictionary:
	return ART.get(weapon_id, ART["pistol"])


static func scale_of(weapon_id: String) -> float:
	return float(art(weapon_id)["w"]) / TEX_W


## Position (in shoulder space) where the sprite's top-left corner goes.
static func sprite_offset(weapon_id: String) -> Vector2:
	var a := art(weapon_id)
	var s := scale_of(weapon_id)
	var grip: Vector2 = a["grip"]
	return Vector2(HAND_X - grip.x * s, -float(a["muzzle_y"]) * s)


## Hand positions in shoulder space: [grip, fore-grip or null].
static func hands(weapon_id: String) -> Array:
	var a := art(weapon_id)
	var s := scale_of(weapon_id)
	var off := sprite_offset(weapon_id)
	var res: Array = [off + (a["grip"] as Vector2) * s]
	var f: Vector2 = a["fore"]
	res.append(off + f * s if f.x >= 0.0 else null)
	return res


## Muzzle position (in shoulder space) along +X.
static func muzzle_offset(weapon_id: String) -> Vector2:
	var off := sprite_offset(weapon_id)
	return Vector2(off.x + MUZZLE_PX * scale_of(weapon_id), 0.0)


## New ShaderMaterial for a skin. Reuse it for the same sprite; call apply_skin to change.
static func make_material(skin_id: String, weapon_id: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	apply_skin(m, skin_id, weapon_id)
	return m


static func apply_skin(m: ShaderMaterial, skin_id: String, weapon_id: String) -> void:
	var s: Dictionary = Catalog.skin(skin_id)
	var tex := texture(weapon_id)
	m.set_shader_parameter("pattern", int(s.get("pattern", 0)))
	m.set_shader_parameter("base", s["base"])
	m.set_shader_parameter("accent", s["accent"])
	m.set_shader_parameter("accent2", s.get("accent2", s["accent"]))
	m.set_shader_parameter("aspect", float(tex.get_width()) / float(tex.get_height()) * 0.5)


## Configures a Sprite2D as the gun for weapon/skin, in shoulder space.
static func setup_sprite(sp: Sprite2D, weapon_id: String, skin_id: String) -> void:
	sp.texture = texture(weapon_id)
	sp.centered = false
	var s := scale_of(weapon_id)
	sp.scale = Vector2(s, s)
	sp.position = sprite_offset(weapon_id)
	if sp.material is ShaderMaterial:
		apply_skin(sp.material, skin_id, weapon_id)
	else:
		sp.material = make_material(skin_id, weapon_id)
