shader_type canvas_item;
// Paints the white parts of a sprite (helmet, vest) with the player color, keeping shading.
uniform vec4 tint : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform float flash = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float w = (1.0 - smoothstep(0.06, 0.16, mx - mn)) * smoothstep(0.42, 0.62, mx);
	vec3 shaded = tint.rgb * (0.35 + 0.8 * mx) + vec3(0.25) * smoothstep(0.93, 1.0, mx);
	vec3 col = mix(c.rgb, shaded, w);
	col = mix(col, vec3(1.0), flash);
	COLOR = vec4(col, c.a) * COLOR;
}
