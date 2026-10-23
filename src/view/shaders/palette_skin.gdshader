shader_type spatial;
// Скины персонажей Kenney (D-11): тело палитрового шейдера (тинт заражения, подсветка), но текстура обычная.
render_mode cull_back, diffuse_lambert, specular_disabled;
#define SKIN
#define CHAR
#include "res://src/view/shaders/palette_body.gdshaderinc"
