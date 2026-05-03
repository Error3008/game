shader_type spatial;

uniform float wave_size = 0.0;
uniform float wave_speed = 0.0;

uniform vec3 color : source_color;
uniform float metalic = 0.0; 
uniform float roughness = 0.0;
uniform float alpha = 1.0;

float rand(uint current_seed, float min_val, float max_val) 
{
    const uint a = 1103515245u;
    const uint c = 12345u;
    const uint m = 2147483648u; // 2^31
    
    uint next_seed = (a * current_seed + c) % m;
    float res = float(next_seed) / float(m);
    return min_val + res * (max_val - min_val);
}

float get_offset(float main, float second, float third, float num)
{
	return sin(((main * num + second * third) + TIME) * wave_speed) * wave_size;
}

void vertex() 
{
	VERTEX.y = get_offset(VERTEX.y, VERTEX.x, VERTEX.z, 0.5);
	VERTEX.x += get_offset(VERTEX.x, VERTEX.y, VERTEX.z, 0.9);
	VERTEX.z += get_offset(VERTEX.z, VERTEX.x, VERTEX.y, 1.6);
}

void fragment() 
{
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = color;
	METALLIC = metalic;
	ROUGHNESS = roughness;
	ALPHA = alpha;
}
