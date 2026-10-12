class_name GuDebugPanel
extends CanvasLayer
## 调试面板（游戏里按 F3 开关）。
##
## 这是本工程里最简单的「用代码搭 UI」的范例，也是最好的学习工具：
## 它把那些本来看不见的状态（真元、坐标、地形、背包、网络角色）变成了
## 屏幕上的数字。你改任何数值，按 F3 立刻就能看到结果。
##
## 想练手的话，可以直接在这里加一行，显示你自己关心的东西。

var game: Node = null

var panel: PanelContainer = null
var label: RichTextLabel = null
var _accum := 0.0


func _ready() -> void:
	layer = 8

	# 贴在屏幕右上角。锚点 1.0 = 右边，offset 是相对锚点的像素偏移。
	panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -336.0
	panel.offset_right = -10.0
	panel.offset_top = 10.0
	panel.offset_bottom = 470.0
	panel.visible = false
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = true
	label.custom_minimum_size = Vector2(300.0, 0.0)
	margin.add_child(label)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ev := event as InputEventKey
	if ev.pressed and not ev.echo and ev.physical_keycode == KEY_F3:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not panel.visible:
		return
	# 不用每帧刷新文字（太费），每 0.15 秒一次就够看
	_accum += delta
	if _accum < 0.15:
		return
	_accum = 0.0
	label.text = build_text()


func build_text() -> String:
	if game == null or game.world == null:
		return "（尚未进入世界）"

	var lines: Array = []

	# ---------- 运行环境 ----------
	var role := "单机"
	if game.is_online:
		role = "主机" if multiplayer.is_server() else "客户端"
	lines.append("[b]◆ 运行环境[/b]")
	lines.append("模式 %s　peer id %d" % [role, int(game.my_id)])
	lines.append("FPS %d　在线玩家 %d　妖兽 %d" % [
		Engine.get_frames_per_second(), game.players.size(), game.beasts.size()])
	lines.append("资源点 剩余 %d / 共 %d" % [
		game.world.resources.size() - game.depleted.size(), game.world.resources.size()])

	# ---------- 我的蛊师 ----------
	var mp: GuPlayer = game.my_player
	if mp == null:
		lines.append("")
		lines.append("[b]◆ 我的蛊师[/b]")
		lines.append("[color=#ff8888]尚未生成[/color]")
		return "\n".join(PackedStringArray(lines))

	var d: Dictionary = game.my_data
	var rank := int(d.get("rank", 1))
	lines.append("")
	lines.append("[b]◆ 我的蛊师[/b]")
	lines.append("道号 %s　%d 转" % [mp.player_name, rank])
	lines.append("真元 %.0f / %.0f　气血 %.0f / %.0f" % [
		float(d.get("essence", 0.0)), GameData.essence_max(rank),
		float(d.get("hp", 0.0)), GameData.hp_max(rank)])
	lines.append("元石 %d" % int(d.get("stones", 0)))
	lines.append("坐标 (%.0f, %.0f)　格子 %s" % [
		mp.position.x, mp.position.y,
		str(Vector2i(int(mp.position.x / GameData.CELL), int(mp.position.y / GameData.CELL)))])
	lines.append("脚下地形：%s" % GameData.TILE_NAMES.get(game.world.tile_at(mp.position), "?"))

	var near: int = game.world.resource_near(mp.position, GameData.GATHER_RANGE)
	if near < 0:
		lines.append("附近资源：无")
	else:
		var node: Dictionary = game.world.get_resource(near)
		lines.append("附近资源：%s ×%d" % [node["item"], int(node["amount"])])

	# ---------- 快捷栏 ----------
	lines.append("")
	lines.append("[b]◆ 快捷栏（按 1~4 用蛊）[/b]")
	var slots: Array = d.get("slots", [])
	for i in 4:
		var uid := 0
		if i < slots.size():
			uid = int(slots[i])
		var text := "—"
		if uid != 0:
			var g: Dictionary = find_gu(d, uid)
			if not g.is_empty():
				var info: Dictionary = GameData.GU[g["name"]]
				text = "%s　%d转　熟练%d　耗%d真元" % [
					g["name"], int(g["rank"]), int(g["prof"]), int(info["cost"])]
		lines.append("　%d) %s" % [i + 1, text])

	# ---------- 蛊囊 ----------
	lines.append("")
	lines.append("[b]◆ 蛊囊[/b]")
	var gu_list: Array = d.get("gu", [])
	if gu_list.is_empty():
		lines.append("　（空）")
	for g in gu_list:
		var info2: Dictionary = GameData.GU[g["name"]]
		lines.append("　%s　%d转　熟练%d　[%s]" % [
			g["name"], int(g["rank"]), int(g["prof"]),
			GameData.KIND_CN.get(String(info2["kind"]), info2["kind"])])

	# ---------- 材料 ----------
	lines.append("")
	lines.append("[b]◆ 材料[/b]")
	var items: Dictionary = d.get("items", {})
	if items.is_empty():
		lines.append("　（空）")
	for k in items.keys():
		lines.append("　%s ×%d" % [k, int(items[k])])

	lines.append("")
	lines.append("[color=#8899aa]F3 关闭　H 帮助　Tab 蛊囊[/color]")
	return "\n".join(PackedStringArray(lines))


func find_gu(d: Dictionary, uid: int) -> Dictionary:
	for g in d.get("gu", []):
		if int(g["uid"]) == uid:
			return g
	return {}
