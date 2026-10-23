shader_type spatial;
// Палитра для снаряжения персонажей: + градиент по высоте и контровой свет (CHAR).
render_mode cull_back, diffuse_lambert, specular_disabled;
#define CHAR
#include "res://src/view/shaders/palette_body.gdshaderinc"
