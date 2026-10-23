shader_type spatial;
// Туман войны пост-эффектом: восстанавливаем мировую XZ из буфера глубины и читаем растр FogOfWar.
// 0 — не открыто (почти чёрное), 110 — открыто (затемнение и обесцвечивание), 255 — видно.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D fog_tex : filter_linear;
uniform vec2 fog_origin;
uniform vec2 fog_size;
uniform float enabled = 1.0;
uniform float unexplored = 0.22;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec2 uv = (world.xz - fog_origin) / fog_size;
	float v = texture(fog_tex, uv).r;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) { v = 0.0; }
	vec3 scene = texture(screen_tex, SCREEN_UV).rgb;
	float grey = dot(scene, vec3(0.3, 0.59, 0.11));
	float explored = smoothstep(0.02, 0.43, v);
	float visible = smoothstep(0.55, 0.95, v);
	// разведанное вне обзора — чуть приглушено (как «серый» город в AoE), неразведанное — тёмная, но читаемая карта:
	// при отдалении игрок должен видеть город, а не чёрный экран
	vec3 dim = mix(vec3(grey), scene, 0.7) * 0.72;
	vec3 dark = mix(vec3(grey), scene, 0.45) * unexplored;
	vec3 col = mix(dark, dim, explored);
	col = mix(col, scene, visible);
	ALBEDO = mix(scene, col, enabled);
}
