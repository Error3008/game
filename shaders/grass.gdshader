 shader_type spatial;

render_mode cull_disabled;

uniform vec3 color : source_color;
uniform vec3 color2 : source_color;
uniform sampler2D color_noise;
uniform float color_noise_scale = 20.0;

uniform sampler2D wind_noise;
uniform float noise_scale = 0.0;
uniform vec2 wind_wave_vec = vec2(0.0, 0.0);
uniform vec3 wind_direction = vec3(0.0, 0.0, 0.0);
uniform float wind_strength = 0.0;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec2 noise_uv = world_pos.xz * noise_scale + (TIME * wind_wave_vec);
	
	float noise_value = texture(wind_noise, noise_uv).r;
    
    float mask = 1.0 - UV.y;
    float sway = noise_value * wind_strength; 
    
    vec3 global_sway = normalize(wind_direction) * sway * mask;

    VERTEX += (global_sway * mat3(MODEL_MATRIX));
}

void fragment() {
	vec3 noise_level = texture(color_noise, world_pos.xz / color_noise_scale).rgb;
	ALBEDO = mix(color, color2, UV.y) * mix(color, color2, noise_level.r);
	
	if (!FRONT_FACING)
	{
		NORMAL = -NORMAL;
	}
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
