// Туман войны в материалах мира (D-14): каждый шейдер затемняет свой цвет по растру FogOfWar.
// Раньше был пост-эффект с восстановлением XZ из глубины — в WebGL (Compatibility) глубина другая,
// и туман «плыл» за камерой. Растр и параметры — глобальные (FogRenderer): 0 — не открыто,
// 110 — открыто (приглушено), 255 — видно сейчас.
global uniform sampler2D qm_fog : filter_linear;
global uniform vec4 qm_fog_rect;   // origin.xy, size.xy (м)
global uniform vec4 qm_fog_k;      // x — туман включён, y — яркость неразведанного, z — шаг растра (доля uv)

// Видимость точки мира: x — разведано, y — видно сейчас. Пять выборок — мягкий край вместо «лесенки» клеток.
vec2 fog_vis(vec3 wp) {
	vec2 uv = (wp.xz - qm_fog_rect.xy) / qm_fog_rect.zw;
	float d = qm_fog_k.z * 0.7;
	float v = texture(qm_fog, uv).r * 0.4
		+ (texture(qm_fog, uv + vec2(d, 0.0)).r + texture(qm_fog, uv - vec2(d, 0.0)).r
		+ texture(qm_fog, uv + vec2(0.0, d)).r + texture(qm_fog, uv - vec2(0.0, d)).r) * 0.15;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) { v = 0.0; }
	return vec2(smoothstep(0.03, 0.4, v), smoothstep(0.5, 0.9, v));
}

// Разведанное вне обзора — приглушено и обесцвечено (как «серый» город в AoE); неразведанное — тёмная,
// но читаемая карта: при отдалении игрок видит город, а не чёрный экран.
vec3 fog_color(vec3 c, vec2 e) {
	float grey = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 dim = mix(vec3(grey), c, 0.6) * 0.62;
	vec3 dark = mix(vec3(grey), c, 0.35) * qm_fog_k.y;
	vec3 r = mix(mix(dark, dim, e.x), c, e.y);
	return mix(c, r, qm_fog_k.x);
}

// Множитель свечения (окна, огни) — в тумане не светится то, чего не видно.
float fog_glow(vec2 e) {
	return mix(1.0, mix(0.15, 0.6, e.x) * (1.0 - e.y) + e.y, qm_fog_k.x);
}
