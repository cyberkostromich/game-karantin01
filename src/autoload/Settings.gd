extends Node
## Пользовательские настройки (user://settings.cfg). Не баланс — только комфорт игрока.

const PATH := "user://settings.cfg"

var master_volume := 0.8
var music_volume := 0.5
var sfx_volume := 0.8
var edge_scroll := true
var fullscreen := false
var shadows := true
var player_name := "Командир"
var last_ip := "127.0.0.1"


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	master_volume = cf.get_value("audio", "master", master_volume)
	music_volume = cf.get_value("audio", "music", music_volume)
	sfx_volume = cf.get_value("audio", "sfx", sfx_volume)
	edge_scroll = cf.get_value("input", "edge_scroll", edge_scroll)
	fullscreen = cf.get_value("video", "fullscreen", fullscreen)
	shadows = cf.get_value("video", "shadows", shadows)
	player_name = cf.get_value("net", "name", player_name)
	last_ip = cf.get_value("net", "ip", last_ip)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master_volume)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("input", "edge_scroll", edge_scroll)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("video", "shadows", shadows)
	cf.set_value("net", "name", player_name)
	cf.set_value("net", "ip", last_ip)
	cf.save(PATH)


func apply() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)


func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
