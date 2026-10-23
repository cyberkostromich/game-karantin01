class_name UiTheme
extends RefCounted
## Стиль интерфейса (арт-библия §9, D-12): «полевой планшет штаба». Крашеная сталь с фасками и заклёпками
## (assets/ui/*.png, tools/asset_gen/ui_skin.py), утопленные слоты, кнопки-пластины, подписи разделов на
## малярном скотче. Шрифты ParaType PT Sans / PT Sans Narrow (кириллица «родная», российская навигация),
## Oswald — крупные цифры, PT Mono — таймеры. Акцент — сигнальный оранжевый, тревога — «зебра».

const BG := Color(0.11, 0.12, 0.11, 0.96)
const PANEL := Color("262a25")
const PANEL_L := Color("3a4036")
const TEXT := Color("ece6d6")      # «бумага»: тёплый, не стерильно-белый
const DIM := Color("a39f92")
const INK := Color("1d1f1c")       # текст на скотче
const ACCENT := Color("ff6a1f")
const DANGER := Color("e04b3a")
const INFECT := Color("9be564")
const OK := Color("7cc86a")
const WARN := Color("f2b53a")
const INFO := Color("8fb4e3")

## имя текстуры → поля 9-slice (лево, верх, право, низ) и внутренние отступы
const SKINS := {
	"panel": [14, 14, 10], "panel_dark": [14, 14, 10], "inset": [8, 8, 6], "btn": [9, 9, 6],
	"btn_hover": [9, 9, 6], "btn_pressed": [9, 9, 6], "btn_disabled": [9, 9, 6], "btn_active": [9, 9, 6],
	"bar_bg": [4, 4, 2], "tape": [10, 6, 8],
}

static var _theme: Theme
static var font_r: Font
static var font_b: Font
static var font_n: Font      # PT Sans Narrow Bold — кнопки, подписи, заголовки
static var font_d: Font      # Oswald — крупные цифры и заголовки экранов
static var font_m: Font      # PT Mono — таймеры, координаты
static var _skins: Dictionary = {}


static func _fonts() -> void:
	if font_r != null:
		return
	font_r = load("res://assets/fonts/PT_Sans-Web-Regular.ttf")
	font_b = load("res://assets/fonts/PT_Sans-Web-Bold.ttf")
	var n := FontVariation.new()
	n.base_font = load("res://assets/fonts/PT_Sans-Narrow-Web-Bold.ttf")
	n.spacing_glyph = 1
	font_n = n
	var d := FontVariation.new()
	d.base_font = load("res://assets/fonts/Oswald.ttf")
	d.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 560}
	font_d = d
	font_m = load("res://assets/fonts/PTM55FT.ttf")


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	_fonts()
	var t := Theme.new()
	t.default_font = font_r
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_stylebox("panel", "PanelContainer", skin("panel"))
	t.set_stylebox("panel", "Panel", skin("panel"))
	t.set_stylebox("normal", "Button", skin("btn"))
	t.set_stylebox("hover", "Button", skin("btn_hover"))
	t.set_stylebox("pressed", "Button", skin("btn_pressed"))
	t.set_stylebox("disabled", "Button", skin("btn_disabled"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", DIM.darkened(0.35))
	t.set_font("font", "Button", font_n)
	t.set_font_size("font_size", "Button", 15)
	t.set_stylebox("normal", "LineEdit", skin("inset"))
	t.set_stylebox("focus", "LineEdit", skin("inset"))
	t.set_stylebox("background", "ProgressBar", skin("bar_bg"))
	t.set_stylebox("fill", "ProgressBar", fill(ACCENT))
	var tip := skin("panel_dark", 10)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", font_r)
	t.set_font_size("font_size", "TooltipLabel", 14)
	t.set_stylebox("panel", "PopupPanel", skin("panel"))
	t.set_stylebox("slider", "HSlider", skin("bar_bg"))
	t.set_stylebox("grabber_area", "HSlider", fill(ACCENT))
	t.set_stylebox("grabber_area_highlight", "HSlider", fill(ACCENT.lightened(0.15)))
	t.set_stylebox("normal", "OptionButton", skin("btn"))
	t.set_stylebox("hover", "OptionButton", skin("btn_hover"))
	t.set_stylebox("pressed", "OptionButton", skin("btn_pressed"))
	_theme = t
	return t


## 9-slice из assets/ui; pad — внутренний отступ (по умолчанию из SKINS).
static func skin(name: String, pad: int = -1) -> StyleBoxTexture:
	var key := "%s@%d" % [name, pad]
	if _skins.has(key):
		return _skins[key]
	var spec: Array = SKINS.get(name, [8, 8, 6])
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/ui/%s.png" % name)
	sb.texture_margin_left = spec[0]
	sb.texture_margin_right = spec[0]
	sb.texture_margin_top = spec[1]
	sb.texture_margin_bottom = spec[1]
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT   # зерно металла не растягивается
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	var p := float(spec[2] if pad < 0 else pad)
	sb.content_margin_left = p
	sb.content_margin_right = p
	sb.content_margin_top = p * 0.75
	sb.content_margin_bottom = p * 0.75
	_skins[key] = sb
	return sb


## Плоская заливка полос (HP, прогресс) — без скруглений, «индикатор прибора».
static func fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.expand_margin_top = -2
	sb.expand_margin_bottom = -2
	sb.expand_margin_left = -2
	sb.expand_margin_right = -2
	return sb


## Квадрат чек-листа: пустой с кантом или залитый.
static func check_box(done: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = OK if done else Color(0.07, 0.08, 0.08)
	sb.border_color = OK if done else DIM
	sb.set_border_width_all(1)
	return sb


## Совместимость: цветная плашка (оверлеи, затемнения). r — фаска-радиус, оставлен минимальным.
static func box(c: Color, r: int, pad: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(mini(r, 2))
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	return sb


static func label(text: String, size: int = 15, color: Color = TEXT, bold := false) -> Label:
	_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_b)
	return l


## Подпись-«трафарет»: узкий жирный капс с разрядкой (заголовки блоков, единицы измерения).
static func caps(text: String, size: int = 12, color: Color = DIM) -> Label:
	_fonts()
	var l := label(text.to_upper(), size, color)
	l.add_theme_font_override("font", font_n)
	return l


## Крупные цифры (ресурсы, часы) — Oswald.
static func digits(text: String, size: int = 20, color: Color = TEXT) -> Label:
	_fonts()
	var l := label(text, size, color)
	l.add_theme_font_override("font", font_d)
	return l


static func mono(text: String, size: int = 14, color: Color = TEXT) -> Label:
	_fonts()
	var l := label(text, size, color)
	l.add_theme_font_override("font", font_m)
	return l


## Заголовок раздела на полоске малярного скотча (как подписывают ящики и карты в поле).
static func tape(text: String, size: int = 13) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", skin("tape"))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := caps(text, size, INK)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	p.add_child(l)
	return p


static func icon_rect(id: String, size: int = 22) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Look.icon(id, 64 if size <= 40 else 128)
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


## Кнопка-пластина с глифом, горячей клавишей в углу и (опционально) короткой подписью внизу.
static func icon_button(icon_id: String, hotkey: String, tooltip: String, cb: Callable, px: int = 60, caption := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tooltip
	b.pressed.connect(cb)
	if icon_id != "":
		var isz := int(px * (0.46 if caption != "" else 0.62))
		var ic := icon_rect(icon_id, isz)
		ic.position = Vector2((px - isz) * 0.5, 6 if caption != "" else (px - isz) * 0.5)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.name = "Icon"
		b.add_child(ic)
	if caption != "":
		var c := caps(caption, 10, TEXT)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.clip_text = true
		c.position = Vector2(2, px - 19)
		c.size = Vector2(px - 4, 16)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(c)
	if hotkey != "":
		var k := caps(hotkey, 11, ACCENT)
		k.position = Vector2(5, 2)
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(k)
	return b


static func panel(dark := false) -> PanelContainer:
	var p := PanelContainer.new()
	if dark:
		p.add_theme_stylebox_override("panel", skin("panel_dark"))
	return p


## Полоса «зебры» — тревожные плашки (волна, вспышка в базе).
static func hazard_strip(h: int = 6) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/ui/hazard.png")
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.custom_minimum_size = Vector2(0, h)
	return t
