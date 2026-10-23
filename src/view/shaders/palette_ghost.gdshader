shader_type spatial;
// Призрак постройки и стройплощадка — полупрозрачная палитра.
render_mode cull_back, diffuse_lambert, specular_disabled, blend_mix, depth_draw_never;
#define GHOST
#include "res://src/view/shaders/palette_body.gdshaderinc"
