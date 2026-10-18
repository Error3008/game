shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_nearest; 

// --- Настройки ветра ---
uniform float wind_strength = 0.005;
uniform float wind_speed = 1.5;
uniform vec2 wind_direction = vec2(1.0, 0.5);
uniform float stiffness = 1.2; 
uniform float trunk_flexibility : hint_range(0.0, 1.0) = 0.5; // Гибкость ствола (1.0 = как листва, 0.0 = бетон)

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 v_color = COLOR.rgb; 
    
    float height_factor = max(0.0, VERTEX.y);
    float wind_time = TIME * wind_speed;
    
    // Определение ствола по красному Vertex Color
    float is_trunk = step(0.9, v_color.r) * step(v_color.g, 0.1) * step(v_color.b, 0.1);
    
    // Базовая волна для всего дерева
    float wave_base = sin(dot(world_pos.xz, wind_direction) + wind_time);
    
    // Мелкая рябь, применяемая только к кроне
    float wave_gusts = sin(dot(world_pos.xz, wind_direction) * 2.5 + wind_time * 3.1) * 0.6;
    float leaf_flutter = wave_gusts * (1.0 - is_trunk); 
    
    float wind_wave = wave_base + leaf_flutter;
    
    // Изгиб на основе высоты от пивота
    float sway = pow(height_factor, stiffness) * wind_strength;
    
    // Ослабление амплитуды раскачивания для ствола
    sway *= mix(1.0, trunk_flexibility, is_trunk);
    
    vec2 wind_dir_norm = normalize(wind_direction);
    VERTEX.x += wind_dir_norm.x * wind_wave * sway;
    VERTEX.z += wind_dir_norm.y * wind_wave * sway;
}

void fragment() {
    vec4 tex_color = texture(albedo_texture, UV);
    ALBEDO = tex_color.rgb;
    
    // Коррекция нормалей для обратных сторон полигонов (при cull_disabled)
    if (!FRONT_FACING) {
        NORMAL = -NORMAL;
    }
}