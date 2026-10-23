// Общее тело шейдера орды: zombie.gdshader (палитра) и zombie_skin.gdshader (скин Kenney).
// Орда на MultiMesh (tech spec §3.1): меш модели слит в один, UV2.x — индекс части (Look.PART_NAMES).
// Скелет «VAT-lite» (арт-библия §7): бедро→колено, плечо→локоть, шея и корпус вращаются вокруг пивотов,
// нормали поворачиваются вместе с вершинами (гладкий шейдинг моделей v3).
// Позы по состоянию: шаг с подволакиванием, выпад и удары в атаке, присед над добычей, покачивание в покое.
// INSTANCE_CUSTOM: x — фаза, y — состояние/255 (ZombieSystem.S), z — скорость 0..1, w — прогресс смерти 0..1.

#ifdef SKIN
uniform sampler2D palette : source_color, filter_linear_mipmap;
#else
uniform sampler2D palette : source_color, filter_nearest;
#endif
uniform vec3 piv_body = vec3(0.0, 0.92, 0.0);
uniform vec3 piv_head = vec3(0.0, 1.47, 0.0);
uniform vec3 piv_arm_l = vec3(-0.2, 1.43, 0.0);
uniform vec3 piv_arm_r = vec3(0.2, 1.43, 0.0);
uniform vec3 piv_forearm_l = vec3(-0.21, 1.15, 0.0);
uniform vec3 piv_forearm_r = vec3(0.21, 1.15, 0.0);
uniform vec3 piv_leg_l = vec3(-0.09, 0.92, 0.0);
uniform vec3 piv_leg_r = vec3(0.09, 0.92, 0.0);
uniform vec3 piv_shin_l = vec3(-0.09, 0.52, 0.0);
uniform vec3 piv_shin_r = vec3(0.09, 0.52, 0.0);
uniform float stride = 6.0;
uniform float sway = 1.0;
global uniform float qm_night;

varying float v_dead;
varying float v_h;

mat3 rot_x(float a) { float c = cos(a), s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a), s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
mat3 rot_z(float a) { float c = cos(a), s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }

void turn(inout vec3 v, inout vec3 n, vec3 piv, mat3 m) {
	v = m * (v - piv) + piv;
	n = m * n;
}

void vertex() {
	float part = floor(UV2.x + 0.5);
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float st = floor(INSTANCE_CUSTOM.y * 255.0 + 0.5);
	float spd = INSTANCE_CUSTOM.z;
	float die = INSTANCE_CUSTOM.w;
	float t = TIME * stride * (0.35 + spd) + ph;
	float s = sin(t), c = cos(t);
	float atk = st == 3.0 ? 1.0 : 0.0;
	float feed = st == 5.0 ? 1.0 : 0.0;
	float hit = sin(TIME * 9.0 + ph);
	// ноги: бедро качается, колено сгибается на выносе; над добычей — присед
	float hip_l = mix(-s * 0.6 * spd, -1.05, feed);
	float hip_r = mix(s * 0.6 * spd, -0.85, feed);
	float knee_l = mix((0.1 + 0.85 * max(0.0, c)) * spd, 1.85, feed);
	float knee_r = mix((0.1 + 0.85 * max(0.0, -c)) * spd, 1.6, feed);
	// руки: вытянуты вперёд (поза модели) + раскачка; в атаке — удары, над добычей — тянут к земле
	float arm_l = -s * 0.22 * spd - atk * (0.55 + 0.55 * hit) + feed * (0.5 + 0.2 * hit);
	float arm_r = s * 0.22 * spd - atk * (0.55 - 0.55 * hit) + feed * (0.4 - 0.2 * hit);
	float elb_l = -0.15 - atk * 0.5 * max(0.0, -hit) - feed * 0.7;
	float elb_r = -0.15 - atk * 0.5 * max(0.0, hit) - feed * 0.7;
	float lean = atk * (0.22 + 0.12 * hit) + feed * (0.75 + 0.08 * sin(TIME * 7.0 + ph));
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	if (part == 7.0 || part == 4.0) {
		if (part == 7.0) { turn(v, n, piv_shin_l, rot_x(knee_l)); }
		turn(v, n, piv_leg_l, rot_x(hip_l));
	} else if (part == 8.0 || part == 5.0) {
		if (part == 8.0) { turn(v, n, piv_shin_r, rot_x(knee_r)); }
		turn(v, n, piv_leg_r, rot_x(hip_r));
	} else {
		if (part == 9.0 || part == 2.0) {
			if (part == 9.0) { turn(v, n, piv_forearm_l, rot_x(elb_l)); }
			turn(v, n, piv_arm_l, rot_x(arm_l));
		} else if (part == 10.0 || part == 3.0) {
			if (part == 10.0) { turn(v, n, piv_forearm_r, rot_x(elb_r)); }
			turn(v, n, piv_arm_r, rot_x(arm_r));
		} else if (part == 1.0) {
			float nod = 0.12 * sin(TIME * 1.3 + ph) + feed * 0.3 * max(0.0, sin(TIME * 7.0 + ph));
			turn(v, n, piv_head, rot_x(nod) * rot_y(0.25 * sin(TIME * 0.7 + ph * 1.3)));
		}
		// корпус с руками и головой: выпад/наклон вокруг таза, перекат плеч в такт шагу
		turn(v, n, piv_body, rot_x(lean) * rot_y(s * 0.08 * spd));
	}
	v.y -= feed * 0.32 + abs(s) * 0.04 * spd;
	// шатание всем телом
	mat3 rz = rot_z(sin(TIME * 1.1 + ph) * 0.06 * sway);
	v = rz * v;
	n = rz * n;
	// смерть: подгибаются колени, падает навзничь и уходит в землю
	if (die > 0.0) {
		mat3 rd = rot_x(-1.45 * min(die * 3.0, 1.0));
		v = rd * v;
		n = rd * n;
		v.y -= max(0.0, die - 0.7) * 1.5;
	}
	v_dead = die;
	v_h = v.y;
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	vec3 c = texture(palette, UV).rgb;
	vec3 emit = vec3(0.0);
#ifndef SKIN
	vec2 cell = floor(UV * 16.0);
	float idx = cell.y * 16.0 + cell.x;
	if (idx == 54.0 && v_dead <= 0.0) { emit = c * (0.6 + qm_night * 2.2); }
#endif
	c *= mix(0.62, 1.06, smoothstep(0.05, 2.0, v_h));   // ноги в тени, головы светлее — орда читается массой
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	emit += vec3(0.75, 0.95, 0.6) * rim * (0.1 + qm_night * 0.18) * (1.0 - v_dead);   // мертвенный контур
	ALBEDO = c * (1.0 - v_dead * 0.4);
	EMISSION = emit;
	ROUGHNESS = 0.95;
}
