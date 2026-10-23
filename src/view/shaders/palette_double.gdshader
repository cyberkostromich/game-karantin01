shader_type spatial;
// Палитра без отсечения граней: ориентиры и чанки, где обход граней не гарантирован.
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://src/view/shaders/palette_body.gdshaderinc"
