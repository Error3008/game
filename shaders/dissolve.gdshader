shader_type spatial;
render_mode cull_disabled;

// Растворение трупа: шум + градиент по высоте (снизу вверх), светящаяся кромка.
// Параметры внешнего вида (albedo/roughness/metallic) копируются из исходного материала.

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale = 6.0;
uniform float edge_width : hint_range(0.01, 0.5) = 0.12;
uniform vec3 edge_color : source_color = vec3(1.0, 0.55, 0.15);
uniform float edge_energy = 4.0;
// Доля градиента по высоте в пороге растворения (0 = чистый шум, 1 = ровный фронт снизу вверх).
uniform float height_bias : hint_range(0.0, 1.0) = 0.35;
// Мировая высота «ног» и диапазон высот тела (задаются кодом при старте растворения).
uniform float origin_y = 0.0;
uniform float height_range = 1.0;

varying vec3 world_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Value-noise редко выходит к краям 0..1 (в основном ~0.15–0.85): растягиваем,
	// чтобы порог d покрывал весь диапазон progress и растворение не имело «мёртвого» времени.
	float n = clamp((value_noise(world_pos * noise_scale) - 0.15) / 0.70, 0.0, 1.0);
	float h = clamp((world_pos.y - origin_y) / max(height_range, 0.001), 0.0, 1.0);
	// Чем ниже точка, тем меньше d, тем раньше она отбрасывается (снизу вверх).
	float d = mix(n, h, height_bias);
	// При progress=0 ничего не отбрасывается, при 1 — всё.
	float v = progress * (1.0 + edge_width) - edge_width;
	if (d < v) {
		discard;
	}
	vec4 tex = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = tex.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	float edge = 1.0 - smoothstep(0.0, edge_width, d - v);
	EMISSION = edge_color * edge_energy * edge * step(0.0001, progress);
}
