class_name SettingsPanel
extends VBoxContainer
## Настройки: громкость, прокрутка краем, тени, полноэкранный режим (Settings → user://settings.cfg).


func build() -> void:
	add_theme_constant_override("separation", 6)
	_slider("SET_MASTER", Settings.master_volume, func(v: float) -> void: Settings.master_volume = v)
	_slider("SET_MUSIC", Settings.music_volume, func(v: float) -> void: Settings.music_volume = v)
	_slider("SET_SFX", Settings.sfx_volume, func(v: float) -> void: Settings.sfx_volume = v)
	_check("SET_EDGE", Settings.edge_scroll, func(v: bool) -> void: Settings.edge_scroll = v)
	_check("SET_SHADOWS", Settings.shadows, func(v: bool) -> void: Settings.shadows = v)
	_check("SET_FULLSCREEN", Settings.fullscreen, func(v: bool) -> void: Settings.fullscreen = v)


func _slider(key: String, v: float, cb: Callable) -> void:
	var h := HBoxContainer.new()
	var l := UiTheme.label(tr(key), 13)
	l.custom_minimum_size.x = 150
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = v
	s.custom_minimum_size.x = 160
	s.value_changed.connect(func(x: float) -> void:
		cb.call(x)
		Settings.apply()
		Settings.save_settings())
	h.add_child(s)
	add_child(h)


func _check(key: String, v: bool, cb: Callable) -> void:
	var c := CheckBox.new()
	c.text = tr(key)
	c.button_pressed = v
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(x: bool) -> void:
		cb.call(x)
		Settings.apply()
		Settings.save_settings())
	add_child(c)
