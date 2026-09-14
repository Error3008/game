shader_type spatial;

render_mode cull_disabled;

// --- Данные рельефа чанка (R = высота в метрах, G = маска плотности травы 0.0..1.0) ---
uniform sampler2D terrain_data : filter_linear, repeat_disable;
uniform float chunk_size_world = 16.0;

// --- Цвета травы и шум оттенков ---
uniform vec3 color : source_color = vec3(0.0, 0.86, 0.0);
uniform vec3 color2 : source_color = vec3(0.0, 0.36, 0.0);
uniform sampler2D color_noise;
uniform float color_noise_scale = 20.0;

// --- Настройки ветра ---
uniform sampler2D wind_noise;
uniform float noise_scale = 0.01;
uniform vec2 wind_wave_vec = vec2(-0.1, 0.0);
uniform vec3 wind_direction = vec3(1.0, -0.5, 0.0);
uniform float wind_strength = 0.75;

varying vec3 world_pos;
varying float v_grass_mask;

void vertex() {
	// 1. Вычисляем координаты инстанса относительно чанка для UV сэмплирования
	vec3 instance_world_pos = MODEL_MATRIX[3].xyz;
	vec2 chunk_uv = clamp((instance_world_pos.xz - NODE_POSITION_WORLD.xz) / chunk_size_world, 0.0, 1.0);
	
	// 2. Считываем данные рельефа чанка: R = высота, G = маска препятствий
	vec4 terrain_sample = texture(terrain_data, chunk_uv);
	float terrain_height = terrain_sample.r;
	float grass_mask = terrain_sample.g;
	v_grass_mask = grass_mask;
	
	// 3. Схлопывание вершин (Vertex Collapsing):
	// Если маска близка к 0 (препятствие, ствол дерева, валун, вода, крутая скала)
	if (grass_mask < 0.05) {
		VERTEX = vec3(0.0);
	} else {
		// Плавное уменьшение высоты травы на границе препятствий (градиент)
		float blade_height_scale = clamp(grass_mask * 1.4, 0.0, 1.0);
		VERTEX.y *= blade_height_scale;
		
		// Поднимаем травинку на точную высоту поверхности рельефа
		VERTEX.y += terrain_height;
		
		// 4. Покачивание от ветра (верхушка колышется, корень неподвижен)
		world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 noise_uv = world_pos.xz * noise_scale + (TIME * wind_wave_vec);
		float noise_value = texture(wind_noise, noise_uv).r;
		
		float sway_mask = 1.0 - UV.y;
		float sway = noise_value * wind_strength;
		vec3 wind_dir = length(wind_direction) > 0.001 ? normalize(wind_direction) : vec3(1.0, 0.0, 0.0);
		vec3 global_sway = wind_dir * sway * sway_mask;
		
		VERTEX += (global_sway * mat3(MODEL_MATRIX));
	}
}

void fragment() {
	// Не рендерить схлопнутые треугольники
	if (v_grass_mask < 0.05) {
		discard;
	}
	
	vec3 noise_level = texture(color_noise, world_pos.xz / color_noise_scale).rgb;
	ALBEDO = mix(color, color2, UV.y) * mix(color, color2, noise_level.r);
	
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
