shader_type spatial;
// Город из OSM: фасады получают окна шейдером (арт-библия §6: «окна — шейдером»).
// Этаж 3 м, шаг окон ~3.2 м; ночью горит редкое окно — город брошен.
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D palette : source_color, filter_nearest;
global uniform float qm_night;
#include "res://src/view/shaders/fog.gdshaderinc"

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 cell = floor(UV * 16.0);
	float idx = cell.y * 16.0 + cell.x;
	vec3 c = texture(palette, UV).rgb;
	vec3 emit = vec3(0.0);
	bool facade = (idx >= 5.0 && idx <= 10.0) || idx == 15.0;
	if (facade && abs(w_nrm.y) < 0.3 && w_pos.y > 1.2) {
		vec2 tng = normalize(vec2(-w_nrm.z, w_nrm.x));
		float u = dot(w_pos.xz, tng) / 3.2;
		float fl = w_pos.y / 3.0;
		vec2 f = fract(vec2(u, fl));
		if (f.x > 0.28 && f.x < 0.72 && f.y > 0.32 && f.y < 0.78) {
			vec2 id = floor(vec2(u, fl)) + floor(w_pos.xz * 0.01);
			float h = hash(id);
			c = mix(vec3(0.16, 0.2, 0.25), vec3(0.42, 0.52, 0.6), step(0.75, h) * (1.0 - qm_night));
			if (h > 0.975) { emit = vec3(1.0, 0.82, 0.5) * qm_night * 1.4; }
		}
	}
	vec2 fe = fog_vis(w_pos);
	ALBEDO = fog_color(c, fe);
	EMISSION = emit * fog_glow(fe);
	ROUGHNESS = 0.95;
}
