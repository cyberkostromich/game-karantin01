// Общее тело палитрового шейдера: подключается palette*.gdshader с разными render_mode.

#ifdef SKIN
// скин персонажа (Kenney, D-11): обычная текстура с фильтрацией вместо ячеек палитры
uniform sampler2D palette : source_color, filter_linear_mipmap;
#else
uniform sampler2D palette : source_color, filter_nearest;
#endif
// Параметры экземпляра занимают слоты общего буфера (в WebGL 4096 ячеек, по 16 на экземпляр — то есть
// не больше ~250 объектов): город и пропсы (STATIC) — без них; персонажи (CHAR) — параметры материала;
// постройки — один bstate = (подсветка, призрак, прогресс стройки, —).
#if defined(STATIC)
const vec4 team_color = vec4(0.184, 0.502, 0.929, 1.0);
const float infect_tint = 0.0;
const float highlight = 0.0;
const float ghost = 0.0;
const float build_progress = 1.0;
#elif defined(CHAR)
// персонажи: цвет игрока и тинт — параметры материала (материал на команду × заражён, Look.char_mat),
// без параметров экземпляра: в WebGL каждый такой экземпляр съедает 16 ячеек, а деталей у людей — тысячи
uniform vec4 team_color : source_color = vec4(0.184, 0.502, 0.929, 1.0);
uniform float infect_tint = 0.0;
const float highlight = 0.0;
const float ghost = 0.0;
const float build_progress = 1.0;
#else
instance uniform vec4 bstate = vec4(0.0, 0.0, 1.0, 0.0);
const vec4 team_color = vec4(0.184, 0.502, 0.929, 1.0);
const float infect_tint = 0.0;
#define highlight bstate.x
#define ghost bstate.y
#define build_progress bstate.z
#endif
global uniform float qm_night;
#include "res://src/view/shaders/fog.gdshaderinc"

varying float v_y;
varying float v_wy;

void vertex() {
	v_y = VERTEX.y;
	v_wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 c = texture(palette, UV).rgb;
	vec3 emit = vec3(0.0);
#ifndef SKIN
	vec2 cell = floor(UV * 16.0);
	float idx = cell.y * 16.0 + cell.x;
	if (idx == 80.0) { c = team_color.rgb; }
	// INFECT_GLOW, LIGHT_WARM, LIGHT_EMIT, GREEN_LIGHT светятся в темноте
	if (idx == 54.0 || idx == 83.0 || idx == 84.0 || idx == 86.0) {
		emit = c * (0.25 + qm_night * 1.6);
	}
#endif
	c = mix(c, vec3(0.61, 0.9, 0.39), infect_tint * 0.35);
#ifdef CHAR
	// Читаемость персонажей сверху (приём Blizzard/Relic): «нарисованный» свет — ноги темнее, голова и плечи
	// светлее (фальшивая AO у земли), и тонкий тёплый контур по краю силуэта — юнит отделяется от земли.
	c *= mix(0.68, 1.08, smoothstep(0.05, 2.3, v_wy));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	emit += vec3(1.0, 0.9, 0.75) * rim * (0.2 + qm_night * 0.06);
#endif
#ifdef GHOST
	// стройплощадка: выше достроенной высоты — оранжевая «плёнка»; призрак — зелёный/красный
	float a = 1.0;
	if (build_progress < 1.0 && v_y > build_progress * 12.0) { c = mix(c, vec3(1.0, 0.42, 0.12), 0.55); a = 0.4; }
	if (ghost > 0.5) {
		c = ghost > 1.5 ? vec3(0.9, 0.2, 0.15) : vec3(0.3, 0.9, 0.4);
		a = 0.5;
		emit = c * 0.3;
	}
	ALPHA = a;
#endif
	vec2 fe = fog_vis((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	ALBEDO = fog_color(c, fe);
	EMISSION = (emit + vec3(1.0, 0.75, 0.3) * highlight * 0.25) * fog_glow(fe);
	ROUGHNESS = 0.92;
}
