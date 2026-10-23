shader_type spatial;
// Подложка за краем карты (CityLoader._ground): ровный цвет травы под туманом войны.
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://src/view/shaders/fog.gdshaderinc"

uniform vec3 color : source_color = vec3(0.26, 0.36, 0.19);

void fragment() {
	ALBEDO = fog_color(color, fog_vis((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
	ROUGHNESS = 1.0;
}
