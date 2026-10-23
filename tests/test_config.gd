extends GutTest
## M0-2: Config грузит все data/*.json и громко падает на отсутствующем ключе.


func test_loads_all_files() -> void:
	assert_true(Config.errors.is_empty(), "ошибки загрузки: %s" % [Config.errors])
	for k: String in Config.FILES:
		assert_true(Config.data.has(k), "нет раздела " + k)


func test_paths() -> void:
	assert_eq(Config.f("rules.day_cycle.day_s"), 240.0)
	assert_eq(Config.i("units.assault.recruits"), 1)
	assert_true(Config.has("zombies.walker.hp"))
	assert_false(Config.has("zombies.walker.nonexistent"))


func test_missing_key_reports_error() -> void:
	var before := Config.errors.size()
	Config.quiet = true
	var v: Variant = Config.g("rules.no_such_section.key")
	Config.quiet = false
	assert_null(v)
	assert_eq(Config.errors.size(), before + 1)
	Config.errors.resize(before)
