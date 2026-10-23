extends Node
## Русская локаль из assets/i18n/ru.csv (key;text). Регистрируем Translation вручную,
## чтобы не зависеть от импорта CSV редактором (проект собирается и headless).

const CSV_PATH := "res://assets/i18n/ru.csv"


func _init() -> void:
	var tr_ru := Translation.new()
	tr_ru.locale = "ru"
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("I18n: нет %s" % CSV_PATH)
		return
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var sep := line.find(";")
		if sep <= 0:
			continue
		tr_ru.add_message(line.substr(0, sep), line.substr(sep + 1).replace("\\n", "\n"))
	TranslationServer.add_translation(tr_ru)
	TranslationServer.set_locale("ru")
