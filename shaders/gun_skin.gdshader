shader_type canvas_item;
// Recolors the neutral-gray gun sprites into animated skins.
// Light low-saturation pixels = paintable metal, dark pixels = grip/details, near-black = outline.
uniform int pattern = 0; // 0 factory 1 camo 2 tiger 3 carbon 4 ice 5 neon 6 blood 7 gold 8 galaxy 9 dragon 10 arctic
uniform vec4 base : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 accent : source_color = vec4(0.2, 0.2, 0.2, 1.0);
uniform vec4 accent2 : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float aspect = 3.0;
uniform float flash = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
vec2 voronoi(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); float d1 = 8.0; float d2 = 8.0;
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = vec2(hash(i + g), hash(i + g + 17.0));
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return vec2(d1, d2);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = mx - mn;
	float metal = smoothstep(0.30, 0.42, mx) * (1.0 - smoothstep(0.10, 0.22, sat));
	float dark = (1.0 - metal) * smoothstep(0.10, 0.20, mx);
	float light = clamp((mx - 0.35) / 0.6, 0.0, 1.0);
	vec2 p = vec2(UV.x * aspect, UV.y) * 4.0;
	float t = TIME;
	vec3 col = c.rgb;
	vec3 glow = vec3(0.0);
	if (pattern > 0) {
		vec3 pc = base.rgb;
		float shade = 0.55 + 0.75 * light;
		if (pattern == 1) { // camo
			float n = fbm(p * 1.3);
			float n2 = fbm(p * 1.3 + 9.0);
			pc = n > 0.55 ? accent.rgb : (n2 > 0.55 ? accent2.rgb : base.rgb);
		} else if (pattern == 2) { // tiger
			float s = sin(p.x * 3.2 + fbm(p * 1.5) * 4.0 + p.y * 1.5);
			pc = mix(base.rgb, accent.rgb, smoothstep(0.45, 0.6, s));
		} else if (pattern == 3) { // carbon weave
			vec2 q = p * 6.0;
			float chk = mod(floor(q.x) + floor(q.y), 2.0);
			float w = chk > 0.5 ? fract(q.x) : fract(q.y);
			pc = mix(base.rgb, accent.rgb, 0.35 + 0.65 * smoothstep(0.0, 1.0, abs(w - 0.5) * 2.0));
			shade = 0.7 + 0.5 * light;
		} else if (pattern == 4) { // ice crystals
			vec2 v = voronoi(p * 1.6);
			float edge = smoothstep(0.08, 0.0, v.y - v.x);
			pc = mix(base.rgb, accent.rgb, v.x * 0.9) + edge * 0.5;
			float sp = pow(max(0.0, sin(t * 3.0 + hash(floor(p * 3.0)) * 40.0)), 30.0) * step(0.85, hash(floor(p * 3.0) + 3.0));
			glow += vec3(0.8, 0.95, 1.0) * sp * metal;
		} else if (pattern == 5) { // neon circuit
			pc = base.rgb;
			vec2 q = p * 2.5;
			float lines = max(smoothstep(0.08, 0.0, abs(fract(q.y) - 0.5)) * step(0.5, hash(vec2(floor(q.y), 1.0))),
				smoothstep(0.08, 0.0, abs(fract(q.x) - 0.5)) * step(0.7, hash(vec2(floor(q.x), 2.0))));
			float pulse = 0.5 + 0.5 * sin(t * 4.0 - p.x * 2.0);
			glow += accent.rgb * lines * (0.6 + 0.8 * pulse) * metal;
			shade = 0.6 + 0.6 * light;
		} else if (pattern == 6) { // blood moon veins
			float n = fbm(p * 1.4 + vec2(t * 0.15, 0.0));
			float vein = smoothstep(0.05, 0.0, abs(n - 0.5));
			pc = mix(base.rgb, accent.rgb * 0.6, n);
			glow += accent.rgb * vein * (0.7 + 0.5 * sin(t * 3.0)) * metal;
		} else if (pattern == 7) { // gold
			pc = mix(accent.rgb, base.rgb, light);
			float band = smoothstep(0.25, 0.0, abs(fract(UV.x * 0.8 - t * 0.35 + UV.y * 0.3) - 0.5) - 0.18);
			glow += vec3(1.0, 0.95, 0.7) * band * 0.55 * metal;
			shade = 0.75 + 0.6 * light;
		} else if (pattern == 8) { // galaxy
			float n = fbm(p * 0.9 + vec2(t * 0.05, 0.0));
			pc = mix(base.rgb, accent.rgb, smoothstep(0.35, 0.75, n));
			pc = mix(pc, accent2.rgb, smoothstep(0.65, 0.9, fbm(p * 1.7 + 4.0)));
			vec2 cell = floor(p * 5.0);
			float star = step(0.93, hash(cell)) * pow(max(0.0, sin(t * 2.5 + hash(cell + 1.0) * 30.0)), 6.0);
			float d = length(fract(p * 5.0) - 0.5);
			glow += vec3(1.0) * star * smoothstep(0.25, 0.0, d) * metal;
			shade = 0.7 + 0.6 * light;
		} else if (pattern == 9) { // dragon fire
			vec2 q = p * 1.2 + vec2(-t * 0.8, t * 0.25);
			float n = fbm(q);
			float f2 = fbm(q * 2.0 + 5.0);
			float heat = smoothstep(0.45, 0.8, n * 0.7 + f2 * 0.5);
			pc = mix(base.rgb, accent.rgb, heat);
			glow += accent2.rgb * smoothstep(0.7, 0.95, n * 0.7 + f2 * 0.5) * metal * 0.9;
		} else if (pattern == 10) { // arctic digital camo
			vec2 cell = floor(p * 3.0);
			float h = hash(cell);
			pc = h > 0.66 ? accent.rgb : (h > 0.33 ? accent2.rgb : base.rgb);
		}
		col = mix(col, pc * shade, metal);
		// tint grips and small details slightly with the skin accent
		col = mix(col, col * 0.6 + accent.rgb * 0.25, dark * 0.6);
		// specular top highlight
		col += vec3(1.0) * smoothstep(0.92, 1.0, light) * 0.25 * metal;
	}
	col += glow;
	col = mix(col, vec3(1.0), flash);
	COLOR = vec4(col, c.a) * COLOR;
}
