class_name GuBeast
extends Node2D
## 妖兽。只有主机（或单机）模拟，位置与气血由主机广播给其他端。

var game: Node = null
var world: GuWorld = null
var index := 0
var kind := "铁甲猪"
var hp := 60.0
var hp_max := 60.0
var host_sim := false
var players_ref := {}
var font: Font = null

var _wander := Vector2.ZERO
var _wander_t := 0.0
var _atk_cd := 0.0
var _sync_accum := 0.0
var _flash := 0.0


func _ready() -> void:
	_wander = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()


func flash() -> void:
	_flash = 1.0


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.5)
		queue_redraw()
	if not host_sim:
		return

	_atk_cd = maxf(0.0, _atk_cd - delta)
	var info: Dictionary = GameData.BEASTS[kind]

	# 找最近的玩家
	var target: GuPlayer = null
	var best := 1.0e20
	for pid in players_ref.keys():
		var p: GuPlayer = players_ref[pid]
		if p == null or not is_instance_valid(p):
			continue
		var d: float = position.distance_to(p.position)
		if d < best:
			best = d
			target = p

	var dir := Vector2.ZERO
	var speed := float(info["speed"])
	if target != null and best < float(info["aggro"]):
		var to_target := target.position - position
		if to_target.length() > 1.0:
			dir = to_target.normalized()
		if best < 46.0:
			dir = Vector2.ZERO
			if _atk_cd <= 0.0:
				_atk_cd = 1.3
				if game != null:
					game.apply_beast_damage(target.peer_id, int(info["dmg"]))
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(1.2, 3.2)
			_wander = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		dir = _wander

	var step := dir * speed * delta
	if step.length() > 0.0 and (world == null or not world.is_blocked(position + step)):
		position += step

	_sync_accum += delta
	if _sync_accum >= 0.12:
		_sync_accum = 0.0
		if game != null:
			game.broadcast_beast_state(index, position, hp, hp_max)


func _draw() -> void:
	var info: Dictionary = GameData.BEASTS[kind]
	var col: Color = info["color"]
	if _flash > 0.0:
		col = col.lerp(Color(1.0, 1.0, 1.0), _flash * 0.7)

	draw_circle(Vector2(2.0, 9.0), 14.0, Color(0.0, 0.0, 0.0, 0.28))
	draw_circle(Vector2.ZERO, 15.0, col)
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, Color(0.0, 0.0, 0.0, 0.55), 2.0)

	if font != null:
		draw_string(font, Vector2(-45.0, -20.0), kind,
				HORIZONTAL_ALIGNMENT_CENTER, 90.0, 13, Color(0.92, 0.90, 0.86))

	draw_rect(Rect2(-20.0, -14.0, 40.0, 4.0), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(-20.0, -14.0, 40.0 * clampf(hp / maxf(hp_max, 1.0), 0.0, 1.0), 4.0),
			Color(0.85, 0.30, 0.30))
