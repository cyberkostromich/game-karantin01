class_name UiTheme
extends RefCounted
## Стиль интерфейса (арт-библия §9): Inter, графит #2E333B, сигнальный оранжевый #FF6A1F,
## красный — опасность, зелёный — заражение.

const BG := Color(0.11, 0.12, 0.14, 0.92)
const PANEL := Color("2e333b")
const PANEL_L := Color("3a4148")
const TEXT := Color("e8e6e1")
const DIM := Color("9a9c9e")
const ACCENT := Color("ff6a1f")
const DANGER := Color("e5484d")
const INFECT := Color("9be564")
const OK := Color("59d17a")
const WARN := Color("f2c230")
const INFO := Color("5b9bd5")

static var _theme: Theme
static var font_r: FontFile
static var font_sb: FontFile
static var font_b: FontFile


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	font_r = load("res://assets/fonts/Inter-Regular.ttf")
	font_sb = load("res://assets/fonts/Inter-SemiBold.ttf")
	font_b = load("res://assets/fonts/Inter-Bold.ttf")
	var t := Theme.new()
	t.default_font = font_r
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(BG, 10))
	t.set_stylebox("panel", "Panel", box(BG, 10))
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var c := PANEL
		match st:
			"hover": c = PANEL_L
			"pressed": c = ACCENT.darkened(0.25)
			"disabled": c = PANEL.darkened(0.3)
			"focus": c = PANEL_L
		var sb := box(c, 7)
		if st == "focus":
			sb.border_color = ACCENT
			sb.set_border_width_all(1)
		t.set_stylebox(st, "Button", sb)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM.darkened(0.3))
	t.set_font("font", "Button", font_sb)
	t.set_font_size("font_size", "Button", 14)
	t.set_stylebox("normal", "LineEdit", box(PANEL, 6))
	t.set_stylebox("focus", "LineEdit", box(PANEL_L, 6))
	t.set_stylebox("background", "ProgressBar", box(PANEL, 4))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 4))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.08, 0.09, 0.1, 0.96), 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("panel", "PopupPanel", box(BG, 10))
	t.set_stylebox("slider", "HSlider", box(PANEL, 3))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, 3))
	_theme = t
	return t


static func box(c: Color, r: int, pad: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	return sb


static func label(text: String, size: int = 15, color: Color = TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		get_theme()
		l.add_theme_font_override("font", font_sb)
	return l


static func caps(text: String, size: int = 12, color: Color = DIM) -> Label:
	var l := label(text.to_upper(), size, color, true)
	return l


static func icon_rect(id: String, size: int = 22) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Look.icon(id, 64)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	return t


static func button(text: String, cb: Callable, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func panel() -> PanelContainer:
	return PanelContainer.new()
