shader_type spatial;
// Один материал на весь low-poly мир (ADR-5): цвет — ячейка палитры 16×16 по UV.
// TEAM-ячейка перекрашивается в цвет игрока, светящиеся ячейки ночью дают emission (арт-библия §3, §8).
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://src/view/shaders/palette_body.gdshaderinc"
