shader_type spatial;
// Москва-река: тёмная вода с лёгкой рябью и бликом. Без текстур — только шум по позиции.
render_mode cull_disabled, specular_schlick_ggx;

global uniform float qm_night;
#include "res://src/view/shaders/fog.gdshaderinc"
varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float n2(vec2 p) {
	return sin(p.x * 0.35 + TIME * 0.6) * cos(p.y * 0.27 - TIME * 0.45) + sin((p.x + p.y) * 0.11 + TIME * 0.3);
}

void fragment() {
	float w = n2(w_pos.xz);
	vec3 deep = vec3(0.17, 0.27, 0.35);
	vec3 shallow = vec3(0.3, 0.45, 0.55);
	ALBEDO = fog_color(mix(deep, shallow, 0.5 + 0.25 * w), fog_vis(w_pos));
	vec3 n = normalize(vec3(cos(w_pos.x * 0.35 + TIME) * 0.06, 1.0, sin(w_pos.z * 0.3 - TIME * 0.8) * 0.06));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ROUGHNESS = 0.15;
	METALLIC = 0.1;
	SPECULAR = 0.6;
}
