class_name TradeWindow
extends Control
## 面对面自由交易窗口。
##
## 客户端只提出「报价意图」，主机校验拥有关系后再落账，
## 双方都点确认才真正交换（见 Game.gd 的 req_trade_* / _execute_trade）。

signal act_set_offer(items: Dictionary, stones: int, gu_uids: Array)
signal act_confirm
signal act_cancel

var game: Node = null
var my_id := 1
var my_data := {}
var sess := {}

var my_items := {}          # 材料名 -> 数量
var my_gu: Array = []       # 蛊虫 uid

var _mat_list: ItemList
var _gu_list: ItemList
var _stones: SpinBox
var _mine_label: RichTextLabel
var _theirs_label: RichTextLabel
var _confirm_btn: Button
var _title: Label


func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -420.0
	offset_right = 420.0
	offset_top = -280.0
	offset_bottom = 280.0
	visible = false
	_build()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	_title = Label.new()
	_title.text = "交易"
	_title.add_theme_font_size_override("font_size", 19)
	root.add_child(_title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)

	# ---- 左：我的报价 ----
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)

	var l1 := Label.new()
	l1.text = "我的蛊虫（选中后点加入/移除）"
	left.add_child(l1)
	_gu_list = ItemList.new()
	_gu_list.custom_minimum_size = Vector2(300.0, 130.0)
	left.add_child(_gu_list)

	var gu_btns := HBoxContainer.new()
	left.add_child(gu_btns)
	var b_gu_add := Button.new()
	b_gu_add.text = "加入这只蛊"
	b_gu_add.pressed.connect(_toggle_gu.bind(true))
	gu_btns.add_child(b_gu_add)
	var b_gu_del := Button.new()
	b_gu_del.text = "移除"
	b_gu_del.pressed.connect(_toggle_gu.bind(false))
	gu_btns.add_child(b_gu_del)

	var l2 := Label.new()
	l2.text = "我的材料"
	left.add_child(l2)
	_mat_list = ItemList.new()
	_mat_list.custom_minimum_size = Vector2(300.0, 130.0)
	left.add_child(_mat_list)

	var mat_btns := HBoxContainer.new()
	left.add_child(mat_btns)
	var b_plus := Button.new()
	b_plus.text = "加入 1"
	b_plus.pressed.connect(_mat_change.bind(1))
	mat_btns.add_child(b_plus)
	var b_minus := Button.new()
	b_minus.text = "移除 1"
	b_minus.pressed.connect(_mat_change.bind(-1))
	mat_btns.add_child(b_minus)
	var b_all := Button.new()
	b_all.text = "全部加入"
	b_all.pressed.connect(_mat_all)
	mat_btns.add_child(b_all)

	var stone_row := HBoxContainer.new()
	left.add_child(stone_row)
	var sl := Label.new()
	sl.text = "元石："
	stone_row.add_child(sl)
	_stones = SpinBox.new()
	_stones.min_value = 0
	_stones.max_value = 999999
	_stones.step = 1
	_stones.custom_minimum_size = Vector2(150.0, 0.0)
	_stones.value_changed.connect(func(_v: float) -> void: _emit_set())
	stone_row.add_child(_stones)

	var mine_title := Label.new()
	mine_title.text = "我的报价："
	left.add_child(mine_title)
	_mine_label = RichTextLabel.new()
	_mine_label.bbcode_enabled = true
	_mine_label.fit_content = true
	_mine_label.custom_minimum_size = Vector2(300.0, 60.0)
	left.add_child(_mine_label)

	# ---- 右：对方报价 ----
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)

	var rt := Label.new()
	rt.text = "对方报价"
	right.add_child(rt)
	_theirs_label = RichTextLabel.new()
	_theirs_label.bbcode_enabled = true
	_theirs_label.custom_minimum_size = Vector2(300.0, 300.0)
	right.add_child(_theirs_label)

	var tip := Label.new()
	tip.text = "双方都点「确认」才会成交。\n任何一方改动报价都会重置确认状态。"
	tip.modulate = Color(0.72, 0.76, 0.8)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(300.0, 0.0)
	right.add_child(tip)

	# ---- 底部按钮 ----
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	root.add_child(btns)
	_confirm_btn = Button.new()
	_confirm_btn.text = "确认交易"
	_confirm_btn.pressed.connect(func() -> void: act_confirm.emit())
	btns.add_child(_confirm_btn)
	var b_cancel := Button.new()
	b_cancel.text = "取消（Esc）"
	b_cancel.pressed.connect(func() -> void: act_cancel.emit())
	btns.add_child(b_cancel)


# ---------------- 对外接口 ----------------

func open(pid: int, data: Dictionary, session: Dictionary) -> void:
	my_id = pid
	my_data = data
	sess = session
	my_items = {}
	my_gu = []
	_build_lists()
	visible = true
	update_session(session)


func update_session(session: Dictionary) -> void:
	sess = session
	if sess.is_empty():
		return
	var mine: Dictionary = sess["offer"].get(my_id, {"items": {}, "stones": 0, "gu": []})
	my_items = (mine["items"] as Dictionary).duplicate()
	my_gu = []
	for g in mine["gu"]:
		my_gu.append(int(g["uid"]))
	_stones.set_value_no_signal(float(mine["stones"]))

	var a := int(sess["a"])
	var b := int(sess["b"])
	var other := b if my_id == a else a
	var their_name := "对方"
	if game != null and game.players.has(other):
		their_name = game.players[other].player_name
	_title.text = "交易　——　你 与 %s" % their_name

	var theirs: Dictionary = sess["offer"].get(other, {"items": {}, "stones": 0, "gu": []})
	_mine_label.text = _describe(mine)
	_theirs_label.text = _describe(theirs)

	var confirmed := bool(sess["confirm"].get(my_id, false))
	_confirm_btn.disabled = confirmed
	_confirm_btn.text = "已确认，等待对方…" if confirmed else "确认交易"


func close() -> void:
	visible = false
	sess = {}
	my_items = {}
	my_gu = []


# ---------------- 内部 ----------------

func _build_lists() -> void:
	_gu_list.clear()
	for g in my_data.get("gu", []):
		var info: Dictionary = GameData.GU[g["name"]]
		var idx := _gu_list.add_item("%s　%d转　熟练 %d%%" % [g["name"], int(g["rank"]), int(g["prof"])])
		_gu_list.set_item_metadata(idx, int(g["uid"]))

	_mat_list.clear()
	var items: Dictionary = my_data.get("items", {})
	var ordered: Array = []
	for k in GameData.ITEM_ORDER:
		ordered.append(k)
	for k in items.keys():
		if not ordered.has(k):
			ordered.append(k)
	for k in ordered:
		var n := int(items.get(k, 0))
		if n <= 0:
			continue
		var idx2 := _mat_list.add_item("%s ×%d" % [k, n])
		_mat_list.set_item_metadata(idx2, k)


func _emit_set() -> void:
	act_set_offer.emit(my_items.duplicate(), int(_stones.value), my_gu.duplicate())


func _toggle_gu(add: bool) -> void:
	var sel := _gu_list.get_selected_items()
	if sel.is_empty():
		return
	var uid := int(_gu_list.get_item_metadata(sel[0]))
	if add:
		if not my_gu.has(uid):
			my_gu.append(uid)
	else:
		my_gu.erase(uid)
	_emit_set()


func _mat_change(delta: int) -> void:
	var sel := _mat_list.get_selected_items()
	if sel.is_empty():
		return
	var key := String(_mat_list.get_item_metadata(sel[0]))
	var have := int(my_data.get("items", {}).get(key, 0))
	var cur := int(my_items.get(key, 0)) + delta
	cur = clampi(cur, 0, have)
	if cur <= 0:
		my_items.erase(key)
	else:
		my_items[key] = cur
	_emit_set()


func _mat_all() -> void:
	var items: Dictionary = my_data.get("items", {})
	for k in items.keys():
		if int(items[k]) > 0:
			my_items[k] = int(items[k])
	_emit_set()


func _describe(offer: Dictionary) -> String:
	var parts: Array = []
	var items: Dictionary = offer.get("items", {})
	for k in items.keys():
		parts.append("%s ×%d" % [k, int(items[k])])
	if int(offer.get("stones", 0)) > 0:
		parts.append("元石 ×%d" % int(offer["stones"]))
	for g in offer.get("gu", []):
		parts.append("【%s】" % String(g.get("name", "蛊")))
	if parts.is_empty():
		return "[color=#888888]（空）[/color]"
	var s := ""
	for i in parts.size():
		if i > 0:
			s += "、"
		s += String(parts[i])
	return s


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var ev := event as InputEventKey
		if ev.pressed and not ev.echo and ev.physical_keycode == KEY_ESCAPE:
			act_cancel.emit()
