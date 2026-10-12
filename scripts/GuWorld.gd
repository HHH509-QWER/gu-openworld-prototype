class_name GuWorld
extends Node2D
## 程序化生成的二维大世界。
##
## 世界由固定种子生成，因此主机与所有客户端得到完全相同的地形与资源点分布，
## 网络里只需要同步「哪些资源点已被采走」这种增量状态。

var tiles := PackedByteArray()
var resources: Array = []          # [{pos: Vector2, item: String, amount: int}]
var taken := {}                    # 资源点下标 -> true
var font: Font = null

var _build_done := false


func build() -> void:
	font = GameData.make_font()

	var terrain := FastNoiseLite.new()
	terrain.seed = GameData.WORLD_SEED
	terrain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrain.frequency = 0.045

	var herb := FastNoiseLite.new()
	herb.seed = GameData.WORLD_SEED + 977
	herb.noise_type = FastNoiseLite.TYPE_SIMPLEX
	herb.frequency = 0.14

	var n := GameData.MAP
	tiles.resize(n * n)
	for y in n:
		for x in n:
			var h := terrain.get_noise_2d(float(x), float(y))
			var hh := herb.get_noise_2d(float(x), float(y))
			var t := GameData.TILE_GRASS
			if h < -0.22:
				t = GameData.TILE_WATER
			elif h > 0.42:
				t = GameData.TILE_ROCK
			elif h > 0.16:
				t = GameData.TILE_FOREST
			if t != GameData.TILE_WATER and t != GameData.TILE_ROCK and hh > 0.46:
				t = GameData.TILE_HERB
			tiles[y * n + x] = t

	# 四周围一圈岩地，形成天然边界
	for i in n:
		tiles[i] = GameData.TILE_ROCK
		tiles[(n - 1) * n + i] = GameData.TILE_ROCK
		tiles[i * n] = GameData.TILE_ROCK
		tiles[i * n + n - 1] = GameData.TILE_ROCK

	_build_resources()
	_build_done = true
	queue_redraw()


func _build_resources() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameData.WORLD_SEED + 31
	var n := GameData.MAP
	var tries := 0
	while resources.size() < 430 and tries < 40000:
		tries += 1
		var x := rng.randi_range(2, n - 3)
		var y := rng.randi_range(2, n - 3)
		var t := tiles[y * n + x]
		var item := ""
		var amount := 1
		if t == GameData.TILE_HERB:
			item = "灵药"
			amount = rng.randi_range(2, 4)
		elif t == GameData.TILE_FOREST:
			item = "灵药" if rng.randf() < 0.6 else "兽骨"
			amount = rng.randi_range(1, 3)
		elif t == GameData.TILE_ROCK:
			item = "精铁"
			amount = rng.randi_range(1, 3)
		elif t == GameData.TILE_GRASS:
			if rng.randf() < 0.16:
				item = "月华露"
				amount = 1
			else:
				item = "灵药"
				amount = 1
		else:
			continue
		resources.append({
			"pos": Vector2(x * GameData.CELL + GameData.CELL * 0.5,
					y * GameData.CELL + GameData.CELL * 0.5),
			"item": item,
			"amount": amount,
		})


# ---------------- 绘制 ----------------

func _draw() -> void:
	if tiles.is_empty():
		return
	var cell := float(GameData.CELL)
	for y in GameData.MAP:
		for x in GameData.MAP:
			var t: int = tiles[y * GameData.MAP + x]
			var col: Color = GameData.TILE_COLORS[t]
			draw_rect(Rect2(x * cell, y * cell, cell, cell), col)

	for i in resources.size():
		if taken.has(i):
			continue
		var r: Dictionary = resources[i]
		var c: Color = GameData.ITEMS[r["item"]]["color"]
		var p: Vector2 = r["pos"]
		draw_circle(p, 7.0, c)
		draw_arc(p, 12.0, 0.0, TAU, 20, Color(c.r, c.g, c.b, 0.42), 1.5)


# ---------------- 查询 ----------------

func tile_at(world_pos: Vector2) -> int:
	if tiles.is_empty():
		return GameData.TILE_ROCK
	var x := int(floor(world_pos.x / GameData.CELL))
	var y := int(floor(world_pos.y / GameData.CELL))
	if x < 0 or y < 0 or x >= GameData.MAP or y >= GameData.MAP:
		return GameData.TILE_ROCK
	return tiles[y * GameData.MAP + x]


func is_blocked(world_pos: Vector2) -> bool:
	var t := tile_at(world_pos)
	return t == GameData.TILE_WATER or t == GameData.TILE_ROCK


## 返回最近的未采集资源点下标，找不到返回 -1。
func resource_near(world_pos: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in resources.size():
		if taken.has(i):
			continue
		var d: float = world_pos.distance_to(resources[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best


func get_resource(idx: int) -> Dictionary:
	if idx < 0 or idx >= resources.size():
		return {}
	return resources[idx]


func mark_taken(idx: int) -> void:
	if idx < 0 or taken.has(idx):
		return
	taken[idx] = true
	queue_redraw()


func total_size() -> float:
	return float(GameData.WORLD_PX)
