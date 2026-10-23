shader_type spatial;
// Орда на MultiMesh (tech spec §3.1): меш модели слит в один, UV2.x — индекс части.
// Конечности качаются вокруг пивотов вершинным шейдером («VAT-lite», арт-библия §7).
// INSTANCE_CUSTOM: x — фаза, y — состояние/255, z — скорость 0..1, w — прогресс смерти 0..1.
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D palette : source_color, filter_nearest;
uniform vec3 piv_head = vec3(0.0, 1.5, 0.0);
uniform vec3 piv_arm_l = vec3(-0.33, 1.4, 0.0);
uniform vec3 piv_arm_r = vec3(0.33, 1.4, 0.0);
uniform vec3 piv_leg_l = vec3(-0.12, 0.88, 0.0);
uniform vec3 piv_leg_r = vec3(0.12, 0.88, 0.0);
uniform float stride = 6.0;
uniform float sway = 1.0;
global uniform float qm_night;

varying float v_dead;

mat3 rot_x(float a) { float c = cos(a), s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_z(float a) { float c = cos(a), s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }

vec3 swing(vec3 v, vec3 piv, float a) { return rot_x(a) * (v - piv) + piv; }

void vertex() {
	float part = floor(UV2.x + 0.5);
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float st = floor(INSTANCE_CUSTOM.y * 255.0 + 0.5);
	float spd = INSTANCE_CUSTOM.z;
	float die = INSTANCE_CUSTOM.w;
	float t = TIME * stride * (0.35 + spd) + ph;
	vec3 v = VERTEX;
	float atk = (st == 3.0) ? 1.0 : 0.0;
	if (part == 4.0) { v = swing(v, piv_leg_l, sin(t) * 0.55 * spd); }
	else if (part == 5.0) { v = swing(v, piv_leg_r, -sin(t) * 0.55 * spd); }
	else if (part == 2.0) { v = swing(v, piv_arm_l, -sin(t) * 0.25 * spd - atk * (0.6 + 0.6 * sin(TIME * 9.0 + ph))); }
	else if (part == 3.0) { v = swing(v, piv_arm_r, sin(t) * 0.25 * spd - atk * (0.6 + 0.6 * sin(TIME * 9.0 + ph + 1.6))); }
	else if (part == 1.0) { v = swing(v, piv_head, 0.15 * sin(TIME * 1.3 + ph)); }
	// шатание всем телом
	v = rot_z(sin(TIME * 1.1 + ph) * 0.06 * sway) * v;
	// смерть: падает навзничь и уходит в землю
	if (die > 0.0) {
		v = rot_x(-1.45 * min(die * 3.0, 1.0)) * v;
		v.y -= max(0.0, die - 0.7) * 1.5;
	}
	v_dead = die;
	VERTEX = v;
}

void fragment() {
	vec2 cell = floor(UV * 16.0);
	float idx = cell.y * 16.0 + cell.x;
	vec3 c = texture(palette, UV).rgb;
	vec3 emit = vec3(0.0);
	if (idx == 54.0 && v_dead <= 0.0) { emit = c * (0.6 + qm_night * 2.2); }
	ALBEDO = c * (1.0 - v_dead * 0.4);
	EMISSION = emit;
	ROUGHNESS = 0.95;
}
