extends Node
## Глобальная шина сигналов sim → view/UI (tech spec §2.1). Сигналы — прошедшее время.
## На клиенте сети эти же сигналы переизлучает Net из reliable-RPC хоста.

# --- время ---
signal phase_changed(day: int, phase: String)
signal day_started(day: int)
signal dawn_report(report: Dictionary)
signal wave_announced(night: int, directions: PackedStringArray, composition: Dictionary)
signal wave_started(night: int)
signal scenario_event(day: int, kind: String, text: String, pos: Vector2)
signal objective_updated(id: String, state: String)

# --- люди ---
signal civilian_found(id: int, pos: Vector2)
signal civilian_rescued(id: int, pos: Vector2)
signal civilian_infected(id: int, pos: Vector2, inside_base: bool)
signal infection_detected(id: int, pos: Vector2, by: String)
signal civilian_died(id: int, pos: Vector2)
signal civilian_turned(id: int, pos: Vector2, inside_base: bool)
signal child_born(id: int, pos: Vector2)
signal outbreak_in_base(pos: Vector2)

# --- армия ---
signal unit_trained(id: int, type: String, owner: int)
signal unit_died(id: int, type: String, pos: Vector2)
signal shot_fired(from: Vector3, to: Vector3, kind: String)
signal explosion(pos: Vector2, radius: float, kind: String)
signal ability_used(unit_id: int, ability: String, pos: Vector2)
signal recruit_failed(reason: String)

# --- зомби ---
signal zombie_died(pos: Vector2, type: int, dir: float)
signal zombie_hit(pos: Vector2)
signal scream(pos: Vector2, radius: float)
signal nest_destroyed(id: int, pos: Vector2)

# --- постройки и экономика ---
signal building_placed(id: int, type: String)
signal building_completed(id: int, type: String)
signal building_destroyed(id: int, type: String, pos: Vector2)
signal building_attacked(id: int, pos: Vector2)
signal research_completed(tech: String)
signal power_deficit(shut_off: PackedInt32Array)
signal loot_collected(poi: String, loot: Dictionary, pos: Vector2)
signal alert(kind: String, text: String, pos: Vector2)

# --- матч ---
signal game_over(victory: bool, score: Dictionary)
signal ping_placed(pid: int, kind: String, pos: Vector2)
