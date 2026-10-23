extends Node
## Грузит data/*.json при старте. Единственный источник цифр геймдизайна (CLAUDE.md, правило 1).
## Доступ по пути: Config.f("rules.day_cycle.day_s"). Нет ключа — понятная ошибка с путём.

const DATA_DIR := "res://data"
const FILES := {
	"rules": "rules.json", "units": "units.json", "zombies": "zombies.json",
	"civilians": "civilians.json", "buildings": "buildings.json", "tech": "tech.json",
	"doctrines": "doctrines.json", "waves": "waves.json", "combat": "combat.json",
	"map": "map_luzhniki.json",
}

var data: Dictionary = {}
var errors: PackedStringArray = []
var quiet: bool = false   # тесты проверяют ошибки без push_error


func _init() -> void:
	load_all(DATA_DIR)


func load_all(dir: String) -> bool:
	data.clear()
	errors.clear()
	for key: String in FILES:
		var path: String = dir.path_join(FILES[key])
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			_fail("Config: не найден или пуст файл %s" % path)
			continue
		var json := JSON.new()
		if json.parse(text) != OK:
			_fail("Config: %s:%d — %s" % [path, json.get_error_line(), json.get_error_message()])
			continue
		data[key] = json.data
	return errors.is_empty()


func _fail(msg: String) -> void:
	errors.append(msg)
	if not quiet:
		push_error(msg)


## true, если путь существует.
func has(path: String) -> bool:
	var cur: Variant = data
	for part in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = cur[part]
		else:
			return false
	return true


## Значение по пути "файл.ключ.ключ". Отсутствие ключа — ошибка, а не тихий ноль.
func g(path: String) -> Variant:
	var cur: Variant = data
	for part in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = cur[part]
		else:
			_fail("Config: нет ключа '%s' (споткнулись на '%s')" % [path, part])
			return null
	return cur


## Значение или default, если ключа нет (для необязательных полей вроде "abilities").
func opt(path: String, default: Variant = null) -> Variant:
	return g(path) if has(path) else default


func f(path: String) -> float:
	var v: Variant = g(path)
	return float(v) if v != null else 0.0


func i(path: String) -> int:
	var v: Variant = g(path)
	return int(v) if v != null else 0


func d(path: String) -> Dictionary:
	var v: Variant = g(path)
	return v if v is Dictionary else {}


func a(path: String) -> Array:
	var v: Variant = g(path)
	return v if v is Array else []


## Ключи раздела без служебных "_doc".
func keys_of(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in d(path):
		if not k.begins_with("_"):
			out.append(k)
	return out


## [min, max] из JSON → случайное значение по rng симуляции.
func range_roll(path: String, rng: RandomNumberGenerator) -> float:
	var r := a(path)
	if r.size() < 2:
		return f(path) if not r.is_empty() else 0.0
	return rng.randf_range(float(r[0]), float(r[1]))
