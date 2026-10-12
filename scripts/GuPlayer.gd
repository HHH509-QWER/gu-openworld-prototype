class_name GuPlayer
extends Node2D
## 玩家（蛊师）节点。
##
## 移动采用「各端自己算自己的位置，然后广播给主机再转发」的简化模型，
## 便于原型快速跑起来；背包／元石／蛊虫等真正有价值的资产全部由主机裁定（见 Game.gd）。

const RADIUS := 13.0
const BASE_SPEED := 800.0

var game: Node = null
var world: GuWorld = null
var peer_id := 1
var player_name := "蛊师"
var is_local := false

var rank := 1
var hp := 120.0
var hp_max := 120.0
var essence := 100.0
var essence_max := 100.0
var facing := Vector2.DOWN
var buffs := {}                 # 蛊名 -> 到期时间（秒）
var font: Font = null

var _sync_accum := 0.0
var _bob := 0.0


func _ready() -> void:
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_local:
		_bob += delta
		queue_redraw()
		return

	# 清掉过期增益
	var now := Time.get_ticks_msec() / 1000.0
	for k in buffs.keys():
		if float(buffs[k]) <= now:
			buffs.erase(k)

	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0

	var speed := BASE_SPEED
	if dir.length() > 0.01:
		dir = dir.normalized()
		facing = dir
		if buffs.has("疾风蛊"):
			speed *= 1.7

	_step(dir * speed * delta)

	_sync_accum += delta
	if _sync_accum >= 0.06:
		_sync_accum = 0.0
		broadcast_now()

	_bob += delta
	queue_redraw()


func _step(step: Vector2) -> void:
	if step.length() <= 0.0:
		return
	if world == null:
		position += step
		return
	if _can_stand(position + step):
		position += step
		return
	# 贴墙滑动：分轴再试一次
	var ax := position + Vector2(step.x, 0.0)
	if absf(step.x) > 0.01 and _can_stand(ax):
		position = ax
	var ay := position + Vector2(0.0, step.y)
	if absf(step.y) > 0.01 and _can_stand(ay):
		position = ay


func _can_stand(p: Vector2) -> bool:
	if world == null:
		return true
	if world.is_blocked(p):
		return false
	if world.is_blocked(p + Vector2(RADIUS, 0.0)):
		return false
	if world.is_blocked(p + Vector2(-RADIUS, 0.0)):
		return false
	if world.is_blocked(p + Vector2(0.0, RADIUS)):
		return false
	if world.is_blocked(p + Vector2(0.0, -RADIUS)):
		return false
	return true


## 百步蛊：朝指定方向冲一段距离。
func try_dash(dir: Vector2, distance: float) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else facing.normalized()
	var remain := distance
	while remain > 0.0:
		var step := minf(18.0, remain)
		var next := position + d * step
		if not _can_stand(next):
			break
		position = next
		remain -= step
	broadcast_now()
	queue_redraw()


func broadcast_now() -> void:
	if is_local and game != null:
		game.push_my_state()


# ---------------- 绘制 ----------------

func _draw() -> void:
	var bob := sin(_bob * 6.0) * 1.6
	var body := Color(0.96, 0.89, 0.68) if is_local else Color(0.82, 0.76, 0.62)

	draw_circle(Vector2(0.0, 11.0), 15.0, Color(0.0, 0.0, 0.0, 0.26))
	draw_circle(Vector2(0.0, bob), 16.0, body)
	draw_arc(Vector2(0.0, bob), 16.0, 0.0, TAU, 28, Color(0.14, 0.11, 0.08), 2.0)
	draw_line(Vector2(0.0, bob), Vector2(0.0, bob) + facing.normalized() * 22.0, Color(0.22, 0.16, 0.1), 3.0)

	if buffs.has("疾风蛊"):
		draw_arc(Vector2(0.0, bob), 22.0, 0.0, TAU, 28, Color(0.66, 0.94, 0.78, 0.55), 2.0)
	if buffs.has("铁骨蛊"):
		draw_arc(Vector2(0.0, bob), 20.0, 0.0, TAU, 28, Color(0.73, 0.70, 0.63, 0.65), 3.0)

	if font != null:
		var label := "%s（%d转）" % [player_name, rank]
		draw_string(font, Vector2(-60.0, -30.0), label,
				HORIZONTAL_ALIGNMENT_CENTER, 120.0, 14, Color(0.95, 0.95, 0.90))

	_bar(Vector2(-23.0, -21.0), 46.0, hp / maxf(hp_max, 1.0), Color(0.85, 0.28, 0.28))
	_bar(Vector2(-23.0, -15.0), 46.0, essence / maxf(essence_max, 1.0), Color(0.34, 0.66, 1.0))


func _bar(pos: Vector2, w: float, ratio: float, col: Color) -> void:
	draw_rect(Rect2(pos, Vector2(w, 4.0)), Color(0.0, 0.0, 0.0, 0.62))
	draw_rect(Rect2(pos, Vector2(w * clampf(ratio, 0.0, 1.0), 4.0)), col)
