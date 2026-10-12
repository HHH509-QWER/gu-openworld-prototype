class_name GuHUD
extends CanvasLayer
## 全部用代码构建的 HUD，避免手写 .tscn 出错。
## 只负责「显示」与「发出意图信号」，一切裁决都在 Game.gd（主机权威）。

signal act_use_gu(slot: int)
signal act_gather
signal act_feed(gu_uid: int, item: String)
signal act_rank_up(gu_uid: int)
signal act_equip(gu_uid: int, slot: int)
signal act_breakthrough
signal act_trade
signal act_help

var data := {}
var cd_until := {}

## 所有控件的共同父节点。CanvasLayer 本身没有 theme 属性，
## 所以需要这样一个 Control 根节点来承载字体主题（由 Game 赋值）。
var root: Control = null

var name_label: Label
var stone_label: Label
var hp_bar: ProgressBar
var es_bar: ProgressBar
var log_label: RichTextLabel
var prompt_label: Label
var bag: PanelContainer
var gu_list: ItemList
var mat_list: ItemList
var slot_buttons: Array = []

var _log_lines := 0
var _slot_tick := 0.0


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.name = "HUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top()
	_build_prompt()
	_build_slots()
	_build_log()
	_build_bag()


# ---------------- 构建 ----------------

func _build_top() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12.0, 10.0)
	root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	name_label = Label.new()
	name_label.text = "蛊师"
	vb.add_child(name_label)

	hp_bar = ProgressBar.new()
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(248.0, 14.0)
	hp_bar.max_value = 120.0
	hp_bar.value = 120.0
	vb.add_child(hp_bar)

	es_bar = ProgressBar.new()
	es_bar.show_percentage = false
	es_bar.custom_minimum_size = Vector2(248.0, 14.0)
	es_bar.max_value = 100.0
	es_bar.value = 100.0
	vb.add_child(es_bar)

	stone_label = Label.new()
	stone_label.text = "元石：0"
	vb.add_child(stone_label)


func _build_prompt() -> void:
	prompt_label = Label.new()
	prompt_label.text = ""
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.anchor_left = 0.5
	prompt_label.anchor_right = 0.5
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.offset_left = -320.0
	prompt_label.offset_right = 320.0
	prompt_label.offset_top = -132.0
	prompt_label.offset_bottom = -104.0
	prompt_label.add_theme_font_size_override("font_size", 17)
	root.add_child(prompt_label)


func _build_slots() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -330.0
	bar.offset_right = 330.0
	bar.offset_top = -92.0
	bar.offset_bottom = -24.0
	root.add_child(bar)

	for i in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(160.0, 56.0)
		b.text = "%d  —" % (i + 1)
		b.disabled = true
		var slot := i
		b.pressed.connect(func() -> void: act_use_gu.emit(slot))
		bar.add_child(b)
		slot_buttons.append(b)


func _build_log() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 12.0
	panel.offset_right = 432.0
	panel.offset_top = -190.0
	panel.offset_bottom = -16.0
	root.add_child(panel)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(408.0, 160.0)
	log_label.text = ""
	panel.add_child(log_label)


func _build_bag() -> void:
	bag = PanelContainer.new()
	bag.visible = false
	bag.anchor_left = 0.5
	bag.anchor_right = 0.5
	bag.anchor_top = 0.5
	bag.anchor_bottom = 0.5
	bag.offset_left = -360.0
	bag.offset_right = 360.0
	bag.offset_top = -250.0
	bag.offset_bottom = 250.0
	root.add_child(bag)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	bag.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "蛊囊　·　Tab 关闭"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	vbox.add_child(cols)

	# 蛊虫列
	var c1 := VBoxContainer.new()
	c1.add_theme_constant_override("separation", 6)
	var l1 := Label.new()
	l1.text = "蛊虫"
	c1.add_child(l1)
	gu_list = ItemList.new()
	gu_list.custom_minimum_size = Vector2(340.0, 250.0)
	c1.add_child(gu_list)
	cols.add_child(c1)

	# 材料列
	var c2 := VBoxContainer.new()
	c2.add_theme_constant_override("separation", 6)
	var l2 := Label.new()
	l2.text = "材料"
	c2.add_child(l2)
	mat_list = ItemList.new()
	mat_list.custom_minimum_size = Vector2(220.0, 250.0)
	c2.add_child(mat_list)
	cols.add_child(c2)

	# 操作列
	var c3 := VBoxContainer.new()
	c3.add_theme_constant_override("separation", 8)
	var l3 := Label.new()
	l3.text = "操作"
	c3.add_child(l3)

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 4)
	c3.add_child(slot_row)
	for i in 4:
		var b := Button.new()
		b.text = "槽 %d" % (i + 1)
		var slot := i
		b.pressed.connect(func() -> void: _emit_equip(slot))
		slot_row.add_child(b)

	var b_feed := Button.new()
	b_feed.text = "喂养（选中蛊虫 ← 选中材料）"
	b_feed.pressed.connect(_emit_feed)
	c3.add_child(b_feed)

	var b_up := Button.new()
	b_up.text = "升转（需熟练 100 + 月华露）"
	b_up.pressed.connect(func() -> void:
		var uid := _selected_gu()
		if uid == 0:
			push_log("先在蛊虫列表里选中一只蛊。")
			return
		act_rank_up.emit(uid))
	c3.add_child(b_up)

	var b_break := Button.new()
	b_break.text = "蛊师突破（消耗元石与材料）"
	b_break.pressed.connect(func() -> void: act_breakthrough.emit())
	c3.add_child(b_break)

	var b_trade := Button.new()
	b_trade.text = "与身旁蛊师交易（T）"
	b_trade.pressed.connect(func() -> void: act_trade.emit())
	c3.add_child(b_trade)

	var b_close := Button.new()
	b_close.text = "关闭"
	b_close.pressed.connect(func() -> void: bag.visible = false)
	c3.add_child(b_close)

	var hint := Label.new()
	hint.text = "提示：喂到熟练 100 再升转，蛊虫威力随转数与熟练度提升。"
	hint.modulate = Color(0.72, 0.76, 0.8)
	c3.add_child(hint)


# ---------------- 数据刷新 ----------------

func refresh(d: Dictionary) -> void:
	if d.is_empty():
		return
	data = d
	var rk := int(d["rank"])
	var es_max := GameData.essence_max(rk)
	var hp_max := GameData.hp_max(rk)

	name_label.text = "%s　%d 转蛊师" % [d["name"], rk]
	hp_bar.max_value = hp_max
	hp_bar.value = float(d["hp"])
	es_bar.max_value = es_max
	es_bar.value = float(d["essence"])
	stone_label.text = "元石 %d　│　气血 %d/%d　真元 %d/%d" % [
		int(d["stones"]), int(d["hp"]), int(hp_max), int(d["essence"]), int(es_max),
	]

	_refresh_gu_list(d)
	_refresh_mat_list(d)
	_refresh_slots(d)


func _refresh_gu_list(d: Dictionary) -> void:
	var prev := _selected_gu()
	gu_list.clear()
	for g in d["gu"]:
		var info: Dictionary = GameData.GU[g["name"]]
		var line := "%s　%d转·%s　熟练 %d%%　[%s]" % [
			g["name"], int(g["rank"]), info["dao"], int(g["prof"]),
			GameData.KIND_CN.get(String(info["kind"]), info["kind"]),
		]
		var idx := gu_list.add_item(line)
		gu_list.set_item_metadata(idx, int(g["uid"]))
		if String(info["kind"]) == "attack":
			gu_list.set_item_custom_fg_color(idx, Color(0.96, 0.76, 0.72))
		else:
			gu_list.set_item_custom_fg_color(idx, Color(0.80, 0.90, 0.85))
	for i in gu_list.item_count:
		if int(gu_list.get_item_metadata(i)) == prev:
			gu_list.select(i)
			break


func _refresh_mat_list(d: Dictionary) -> void:
	var prev := _selected_mat()
	mat_list.clear()
	var items: Dictionary = d["items"]
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
		var idx := mat_list.add_item("%s ×%d" % [k, n])
		mat_list.set_item_metadata(idx, k)
	for i in mat_list.item_count:
		if String(mat_list.get_item_metadata(i)) == prev:
			mat_list.select(i)
			break


func _refresh_slots(d: Dictionary) -> void:
	var slots: Array = d["slots"]
	var now := Time.get_ticks_msec() / 1000.0
	for i in 4:
		if i >= slot_buttons.size():
			return
		var btn: Button = slot_buttons[i]
		var uid := 0
		if i < slots.size():
			uid = int(slots[i])
		var text := "%d  —" % (i + 1)
		if uid != 0:
			var g := _find_gu(d, uid)
			if not g.is_empty():
				var info: Dictionary = GameData.GU[g["name"]]
				text = "%d  %s\n%d真元 · 熟练%d" % [i + 1, g["name"], int(info["cost"]), int(g["prof"])]
		if uid != 0:
			var remain := float(cd_until.get(uid, 0.0)) - now
			if remain > 0.0:
				text += "　[冷却 %.1f]" % remain
		btn.text = text
		btn.disabled = uid == 0


func set_cooldown(uid: int, secs: float) -> void:
	cd_until[uid] = Time.get_ticks_msec() / 1000.0 + secs
	if not data.is_empty():
		_refresh_slots(data)


func set_prompt(text: String) -> void:
	if prompt_label != null and prompt_label.text != text:
		prompt_label.text = text


## 注意：不能叫 log()，会和 GDScript 全局的 log()（自然对数）冲突。
func push_log(text: String) -> void:
	# 同时打到 stdout，方便无头服务器/自动化测试看日志
	print("[蛊] " + text)
	if log_label == null:
		return
	log_label.append_text(text + "\n")
	_log_lines += 1
	if _log_lines > 90:
		log_label.clear()
		_log_lines = 1


# ---------------- 选择辅助 ----------------

func _selected_gu() -> int:
	var sel := gu_list.get_selected_items()
	if sel.is_empty():
		return 0
	return int(gu_list.get_item_metadata(sel[0]))


func _selected_mat() -> String:
	var sel := mat_list.get_selected_items()
	if sel.is_empty():
		return ""
	return String(mat_list.get_item_metadata(sel[0]))


func _find_gu(d: Dictionary, uid: int) -> Dictionary:
	for g in d.get("gu", []):
		if int(g["uid"]) == uid:
			return g
	return {}


func _emit_equip(slot: int) -> void:
	var uid := _selected_gu()
	if uid == 0:
		push_log("先在蛊虫列表里选中一只蛊。")
		return
	act_equip.emit(uid, slot)


func _emit_feed() -> void:
	var uid := _selected_gu()
	var mat := _selected_mat()
	if uid == 0:
		push_log("先在蛊虫列表里选中一只蛊。")
		return
	if mat == "":
		push_log("先在材料列表里选中一种材料。")
		return
	act_feed.emit(uid, mat)


# ---------------- 输入 ----------------

func _process(delta: float) -> void:
	if data.is_empty():
		return
	_slot_tick += delta
	if _slot_tick >= 0.15:
		_slot_tick = 0.0
		_refresh_slots(data)


func _input(event: InputEvent) -> void:
	# 用 _input 而不是 _unhandled_input：Tab 默认被 Godot 的 UI 焦点导航占用，
	# 只要有一个按钮拿过焦点，Tab 就到不了 _unhandled_input。
	if not (event is InputEventKey):
		return
	var ev := event as InputEventKey
	if not ev.pressed or ev.echo:
		return
	# 有文本输入框在焦点上（例如交易窗口的元石数量）时，把按键让给它
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		return
	match ev.physical_keycode:
		KEY_TAB:
			bag.visible = not bag.visible
		KEY_ESCAPE:
			if not bag.visible:
				return
			bag.visible = false
		KEY_E:
			act_gather.emit()
		KEY_T:
			act_trade.emit()
		KEY_F:
			act_breakthrough.emit()
		KEY_H:
			act_help.emit()
		KEY_1, KEY_2, KEY_3, KEY_4:
			act_use_gu.emit(int(ev.physical_keycode) - int(KEY_1))
		_:
			return
	get_viewport().set_input_as_handled()
