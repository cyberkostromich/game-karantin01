shader_type spatial;
// Палитра без параметров экземпляра: пропсы, ориентиры, POI (их сотни — слоты буфера не тратятся).
render_mode cull_back, diffuse_lambert, specular_disabled;
#define STATIC
#include "res://src/view/shaders/palette_body.gdshaderinc"
