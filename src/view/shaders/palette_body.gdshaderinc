// Общее тело палитрового шейдера: подключается palette*.gdshader с разными render_mode.

#ifdef SKIN
// скин персонажа (Kenney, D-11): обычная текстура с фильтрацией вместо ячеек палитры
uniform sampler2D palette : source_color, filter_linear_mipmap;
#else
uniform sampler2D palette : source_color, filter_nearest;
#endif
instance uniform vec4 team_color : source_color = vec4(0.184, 0.502, 0.929, 1.0);
instance uniform float infect_tint = 0.0;   // 0..1 — зелёный тинт инкубации после детекта
instance uniform float highlight = 0.0;     // подсветка выделения/наведения
instance uniform float ghost = 0.0;         // 1 — призрак постройки (зелёный), 2 — нельзя (красный)
instance uniform float build_progress = 1.0;
global uniform float qm_night;

varying float v_y;

void vertex() {
	v_y = VERTEX.y;
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
	ALBEDO = c;
	EMISSION = emit + vec3(1.0, 0.75, 0.3) * highlight * 0.25;
	ROUGHNESS = 0.92;
}
