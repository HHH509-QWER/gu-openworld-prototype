extends Node2D
## 《蛊真人》题材大世界开放原型 · 主控节点
##
## 架构要点：
##  * 主机（Host / 单机时就是本机，peer id = 1）是唯一权威：
##    元石、材料、蛊虫、采矿采集、妖兽掉落、交易结算全部在主机侧计算。
##  * 客户端只发送「意图」（req_*），主机校验后广播状态（net_*）。
##  * 世界地形由固定种子生成，各端结果一致，所以只需同步「已采走的资源点」。
##  * 位置同步采用各端自算 + 主机转发，原型够用；正式项目必须改成服务端权威移动。

# ---------------- 运行状态 ----------------
var is_online := false
var my_id := 1
var my_name := "蛊师"
var my_data := {}
var my_player: GuPlayer = null

var world: GuWorld = null
var players_node: Node2D = null
var beasts_node: Node2D = null
var fx: FxLayer = null
var camera: Camera2D = null
var hud: GuHUD = null
var debug_panel: GuDebugPanel = null
var trade_win: TradeWindow = null
var menu_layer: CanvasLayer = null
var menu: Control = null

# ---------------- 主机权威数据 ----------------
var players := {}          # peer_id -> GuPlayer
var beasts := {}           # beast index -> GuBeast
var db := {}               # peer_id -> {name, rank, stones, hp, essence, items, gu, slots}
var depleted := {}         # 已采走的资源点下标
var cooldowns := {}        # "pid|uid" -> 到期时间
var trade := {}            # 当前交易会话（同时只允许一笔）
var trade_seq := 0
var gu_seq := 0
var beast_seq := 0
var respawn_queue: Array = []
var _push_accum := 0.0
var _local_sender := 0        # 本地（非 RPC）调用主机接口时的调用者身份，见 _sender()


func _ready() -> void:
	randomize()
	_build_menu()
	# 命令行快捷启动，便于自动化测试与快速开服：
	#   godot --path <工程> -- --solo
	#   godot --path <工程> -- --host
	#   godot --path <工程> -- --join=192.168.1.7
	for a in OS.get_cmdline_user_args():
		if a == "--solo":
			my_name = "无名蛊师"
			call_deferred("start_solo")
		elif a == "--host":
			my_name = "无名蛊师"
			call_deferred("start_host", GameData.PORT)
		elif a.begins_with("--join="):
			my_name = "无名蛊师"
			call_deferred("start_client", a.substr(7), GameData.PORT)
		elif a == "--selftest":
			my_name = "自测"
			call_deferred("start_solo")
			call_deferred("_run_selftest")


# =========================================================
#  启动界面
# =========================================================

func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.name = "MenuLayer"
	menu_layer.layer = 10
	add_child(menu_layer)

	menu = Control.new()
	menu.name = "Menu"
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.theme = GameData.make_theme()
	menu_layer.add_child(menu)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.055, 0.065)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "蛊　·　真　人"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "大世界开放探索 · 养蛊炼蛊 · 自由交易"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.70, 0.75, 0.80)
	box.add_child(sub)

	box.add_child(HSeparator.new())

	var name_row := HBoxContainer.new()
	box.add_child(name_row)
	var nl := Label.new()
	nl.text = "道号　"
	name_row.add_child(nl)
	var name_edit := LineEdit.new()
	name_edit.text = "无名蛊师"
	name_edit.custom_minimum_size = Vector2(200.0, 0.0)
	name_row.add_child(name_edit)

	var ip_row := HBoxContainer.new()
	box.add_child(ip_row)
	var il := Label.new()
	il.text = "主机 IP"
	ip_row.add_child(il)
	var ip_edit := LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(200.0, 0.0)
	ip_row.add_child(ip_edit)

	var port_row := HBoxContainer.new()
	box.add_child(port_row)
	var pl := Label.new()
	pl.text = "端口　　"
	port_row.add_child(pl)
	var port_edit := LineEdit.new()
	port_edit.text = str(GameData.PORT)
	port_edit.custom_minimum_size = Vector2(200.0, 0.0)
	port_row.add_child(port_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	box.add_child(btn_row)
	var b_solo := Button.new()
	b_solo.text = "单机试玩"
	btn_row.add_child(b_solo)
	var b_host := Button.new()
	b_host.text = "开服（主机）"
	btn_row.add_child(b_host)
	var b_join := Button.new()
	b_join.text = "加入"
	btn_row.add_child(b_join)

	var tip := Label.new()
	tip.text = "WASD 移动　E 采集　1~4 用蛊　Tab 蛊囊　T 交易　F 突破　H 帮助　F3 调试面板"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.modulate = Color(0.62, 0.67, 0.72)
	box.add_child(tip)

	b_solo.pressed.connect(func() -> void:
		_read_name(name_edit)
		start_solo())
	b_host.pressed.connect(func() -> void:
		_read_name(name_edit)
		start_host(port_edit.text.to_int()))
	b_join.pressed.connect(func() -> void:
		_read_name(name_edit)
		start_client(ip_edit.text.strip_edges(), port_edit.text.to_int()))


func _run_selftest() -> void:
	var tester := GuSelfTest.new()
	tester.run(self)


func _read_name(edit: LineEdit) -> void:
	var t := edit.text.strip_edges()
	my_name = t if t != "" else "无名蛊师"


func _menu_error(msg: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.dialog_text = msg
	dlg.title = "出了问题"
	if menu != null:
		menu.add_child(dlg)
	else:
		add_child(dlg)
	dlg.popup_centered()


# =========================================================
#  启动流程
# =========================================================

func start_solo() -> void:
	is_online = false
	my_id = 1
	_begin_world()
	if hud != null:
		hud.push_log("单机模式：按 Tab 查看蛊囊，出门采药喂蛊，打妖兽换材料。")


func start_host(port: int) -> void:
	if port <= 0:
		port = GameData.PORT
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, GameData.MAX_PLAYERS - 1)
	if err != OK:
		_menu_error("开服失败：端口 %d 可能已被占用（错误码 %d）。" % [port, err])
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	is_online = true
	my_id = 1
	_begin_world()
	if hud != null:
		hud.push_log("已开服，端口 %d。把本机局域网 IP 告诉同伴即可加入。" % port)


func start_client(ip: String, port: int) -> void:
	if ip == "":
		ip = "127.0.0.1"
	if port <= 0:
		port = GameData.PORT
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		_menu_error("连接 %s:%d 失败（错误码 %d）。" % [ip, port, err])
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	is_online = true
	my_id = multiplayer.get_unique_id()
	_begin_world()
	if hud != null:
		hud.push_log("正在连接 %s:%d …" % [ip, port])


func _on_connected_ok() -> void:
	my_id = multiplayer.get_unique_id()
	_to_host(&"req_hello", [my_name])


func _on_connect_failed() -> void:
	if hud != null:
		hud.push_log("连接失败：对方未开服或网络不通。")
	multiplayer.multiplayer_peer = null


func _on_server_gone() -> void:
	if hud != null:
		hud.push_log("主机已关闭连接。")
	for pid in players.keys():
		var p: GuPlayer = players[pid]
		if p != null and is_instance_valid(p):
			p.queue_free()
	players.clear()
	my_player = null


func _on_peer_connected(id: int) -> void:
	if hud != null:
		hud.push_log("有蛊师正在接入（peer %d）……" % id)


func _on_peer_disconnected(id: int) -> void:
	if not trade.is_empty() and (int(trade["a"]) == id or int(trade["b"]) == id):
		_close_trade("对方已离开，交易中止。")
	var nm := "对方"
	if players.has(id):
		var p: GuPlayer = players[id]
		nm = p.player_name
		players.erase(id)
		if is_instance_valid(p):
			p.queue_free()
	db.erase(id)
	# 清理该玩家的冷却记录
	for k in cooldowns.keys():
		if String(k).begins_with("%d|" % id):
			cooldowns.erase(k)
	if hud != null:
		hud.push_log("%s 离开了。" % nm)


# =========================================================
#  世界装配
# =========================================================

func _begin_world() -> void:
	if menu != null and is_instance_valid(menu):
		menu.queue_free()
	if menu_layer != null and is_instance_valid(menu_layer):
		menu_layer.queue_free()
	menu = null
	menu_layer = null

	world = GuWorld.new()
	world.name = "World"
	add_child(world)
	world.build()

	players_node = Node2D.new()
	players_node.name = "Players"
	add_child(players_node)

	beasts_node = Node2D.new()
	beasts_node.name = "Beasts"
	add_child(beasts_node)

	fx = FxLayer.new()
	fx.name = "Fx"
	fx.font = world.font
	add_child(fx)

	camera = Camera2D.new()
	camera.name = "Cam"
	camera.zoom = Vector2(1.15, 1.15)
	camera.position = Vector2(GameData.WORLD_PX, GameData.WORLD_PX) * 0.5
	add_child(camera)
	camera.make_current()

	hud = GuHUD.new()
	hud.name = "HUD"
	add_child(hud)
	if hud.root != null:
		hud.root.theme = GameData.make_theme()
	_connect_hud()

	# 调试面板（F3 开关）：把看不见的状态变成看得见的数字
	debug_panel = GuDebugPanel.new()
	debug_panel.name = "DebugPanel"
	debug_panel.game = self
	add_child(debug_panel)
	if debug_panel.panel != null:
		debug_panel.panel.theme = GameData.make_theme()

	trade_win = TradeWindow.new()
	trade_win.name = "TradeWindow"
	trade_win.theme = GameData.make_theme()
	trade_win.game = self
	add_child(trade_win)
	trade_win.act_set_offer.connect(_on_offer_changed)
	trade_win.act_confirm.connect(_on_trade_confirm)
	trade_win.act_cancel.connect(_on_trade_cancel)

	# 只有主机（含单机）创建玩家与妖兽
	if _is_authority():
		_host_make_player(1, my_name)
		for i in GameData.BEAST_COUNT:
			_spawn_beast("")
	if hud != null:
		hud.push_log("—— 蛊道茫茫，此身已入 ——")


func _connect_hud() -> void:
	hud.act_use_gu.connect(func(slot: int) -> void: _to_host(&"req_use_gu", [slot]))
	hud.act_gather.connect(_on_gather)
	hud.act_feed.connect(func(uid: int, item: String) -> void: _to_host(&"req_feed", [uid, item]))
	hud.act_rank_up.connect(func(uid: int) -> void: _to_host(&"req_rank_up", [uid]))
	hud.act_equip.connect(func(uid: int, slot: int) -> void: _to_host(&"req_equip", [uid, slot]))
	hud.act_breakthrough.connect(func() -> void: _to_host(&"req_breakthrough", []))
	hud.act_trade.connect(_on_trade_button)
	hud.act_help.connect(_on_help)


# =========================================================
#  网络小工具
#
#  注意：Node.rpc() / Node.rpc_id() 是 vararg 的，把「数组」传进去会被当成
#  *一个* 参数（而不是展开成多个参数），所以这里统一改用数组版的
#  MultiplayerAPI.rpc(peer, object, method, arguments)。peer == 0 表示广播。
#  是否在本机也执行，由方法上的 @rpc 注解（call_local）决定。
# =========================================================

func _is_authority() -> bool:
	return (not is_online) or multiplayer.is_server()


## 谁在调用主机接口？
##
## 关键点：单机模式、以及主机自己的操作，都**不是** RPC，
## 此时 multiplayer.get_remote_sender_id() 返回 0。
## 所以本地调用用 _local_sender 记录身份，只有远程调用才去问 MultiplayerAPI。
func _sender() -> int:
	if _local_sender != 0:
		return _local_sender
	return multiplayer.get_remote_sender_id()


## 主机 → 所有端（含自己）
func _srv_broadcast(method: StringName, args: Array = []) -> void:
	if not multiplayer.has_multiplayer_peer():
		callv(method, args)
	elif multiplayer.is_server():
		multiplayer.rpc(0, self, method, args)


## 主机 → 单个端（含主机自己 pid == 1）
func _srv_to(pid: int, method: StringName, args: Array = []) -> void:
	if not multiplayer.has_multiplayer_peer():
		callv(method, args)
		return
	if not multiplayer.is_server():
		return
	if pid == 1:
		callv(method, args)
	elif multiplayer.get_peers().has(pid):
		multiplayer.rpc(pid, self, method, args)


## 本端 → 主机（主机自己或单机则直接本地执行，但要把调用者身份补上）
func _to_host(method: StringName, args: Array = []) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_local_sender = my_id
		callv(method, args)
		_local_sender = 0
	else:
		multiplayer.rpc(1, self, method, args)


## 仅供自动化自测：以指定 peer 的身份调用主机接口。
func _test_as(pid: int, method: StringName, args: Array = []) -> void:
	_local_sender = pid
	callv(method, args)
	_local_sender = 0


# =========================================================
#  主机：玩家数据
# =========================================================

func _next_gu_uid() -> int:
	gu_seq += 1
	return gu_seq


func _new_player_data(pname: String) -> Dictionary:
	var gus: Array = []
	var slots: Array = []
	for gu_name in GameData.STARTER_GU:
		var uid := _next_gu_uid()
		gus.append({"uid": uid, "name": gu_name, "rank": 1, "prof": 0})
		slots.append(uid)
	return {
		"name": pname,
		"rank": 1,
		"stones": GameData.STARTER_STONES,
		"hp": GameData.hp_max(1),
		"essence": GameData.essence_max(1),
		"items": {"灵药": 8, "精铁": 5, "兽骨": 3, "月华露": 1},
		"gu": gus,
		"slots": slots,
	}


func _host_make_player(pid: int, pname: String) -> void:
	if db.has(pid):
		return
	db[pid] = _new_player_data(pname)
	_spawn_player(pid, pname, _free_spawn_point())
	_send_self(pid)


## 主机 → 所有端（含自己）：创建玩家节点。
## 所有端都用同一个节点路径 Game/Players/P_<pid>，RPC 才能对上。
func _spawn_player(pid: int, pname: String, pos: Vector2) -> void:
	var rank := 1
	if db.has(pid):
		rank = int(db[pid]["rank"])
	_srv_broadcast("net_spawn_player", [pid, pname, pos, rank])


func _send_self(pid: int) -> void:
	if not db.has(pid):
		return
	_srv_to(pid, "net_self", [db[pid]])


func _add_item(pid: int, item: String, n: int) -> void:
	if n <= 0 or not db.has(pid):
		return
	var d: Dictionary = db[pid]
	d["items"][item] = int(d["items"].get(item, 0)) + n


func _take_item(d: Dictionary, item: String, n: int) -> void:
	var left := int(d["items"].get(item, 0)) - n
	if left <= 0:
		d["items"].erase(item)
	else:
		d["items"][item] = left


func _find_gu(d: Dictionary, uid: int) -> Dictionary:
	for g in d["gu"]:
		if int(g["uid"]) == uid:
			return g
	return {}


func _remove_gu(d: Dictionary, uid: int) -> Dictionary:
	var found := {}
	var rest: Array = []
	for g in d["gu"]:
		if int(g["uid"]) == uid and found.is_empty():
			found = g
		else:
			rest.append(g)
	d["gu"] = rest
	d["slots"].erase(uid)
	return found


## 找一个远离世界中心、且不在水／岩上的出生点（靠近中心方便玩家互相遇见）。
func _free_spawn_point() -> Vector2:
	var center := Vector2(GameData.WORLD_PX, GameData.WORLD_PX) * 0.5
	for i in 500:
		var ang := randf() * TAU
		var rad := randf_range(0.0, 560.0)
		var p := center + Vector2(cos(ang), sin(ang)) * rad
		if world != null and not world.is_blocked(p):
			return p
	return center + Vector2(0.0, 60.0)


# =========================================================
#  主机：RPC 入口（客户端意图）
# =========================================================

@rpc("any_peer", "call_remote", "reliable")
func req_hello(pname: String) -> void:
	var pid := _sender()
	if pid == 0 or db.has(pid):
		return
	var nm := pname.strip_edges()
	if nm == "":
		nm = "无名蛊师"
	db[pid] = _new_player_data(nm)

	# 1) 把已有玩家推给新来的
	for old_pid in players.keys():
		var op: GuPlayer = players[old_pid]
		_srv_to(pid, "net_spawn_player",
				[old_pid, op.player_name, op.position, int(db[old_pid]["rank"])])

	# 2) 广播新玩家
	_spawn_player(pid, nm, _free_spawn_point())

	# 3) 同步环境状态
	_srv_to(pid, "net_sync_depleted", [depleted.keys()])
	for idx in beasts.keys():
		var b: GuBeast = beasts[idx]
		_srv_to(pid, "net_beast_spawn", [idx, b.kind, b.position, b.hp, b.hp_max])

	# 4) 自己的蛊囊
	_send_self(pid)
	_srv_broadcast("net_log", ["%s 步入了蛊道。" % nm])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func req_state(pid: int, pos: Vector2, face: Vector2, es: float, hp: float) -> void:
	if multiplayer.get_remote_sender_id() != pid:
		return
	if multiplayer.is_server():
		multiplayer.rpc(0, self, &"net_state", [pid, pos, face, es, hp])


@rpc("any_peer", "call_remote", "reliable")
func req_gather(idx: int) -> void:
	var pid := _sender()
	if not db.has(pid) or depleted.has(idx):
		return
	var node := world.get_resource(idx)
	if node.is_empty():
		return
	var p: GuPlayer = players.get(pid)
	if p == null:
		return
	if p.position.distance_to(node["pos"]) > GameData.GATHER_RANGE + 10.0:
		_srv_to(pid, "net_log", ["距离太远，够不着。"])
		return
	depleted[idx] = true
	world.mark_taken(idx)
	_add_item(pid, String(node["item"]), int(node["amount"]))
	_srv_broadcast("net_resource_taken", [idx])
	_srv_broadcast("net_fx", ["ring", node["pos"], GameData.ITEMS[node["item"]]["color"], 34.0, "", 0.0])
	_srv_to(pid, "net_log", ["采得 %s ×%d。" % [node["item"], node["amount"]]])
	_send_self(pid)


@rpc("any_peer", "call_remote", "reliable")
func req_use_gu(slot: int) -> void:
	var pid := _sender()
	if not db.has(pid):
		return
	var d: Dictionary = db[pid]
	var slots: Array = d["slots"]
	if slot < 0 or slot >= slots.size():
		return
	var uid := int(slots[slot])
	if uid == 0:
		_srv_to(pid, "net_log", ["该快捷栏是空的。"])
		return
	var gu := _find_gu(d, uid)
	if gu.is_empty():
		return
	var info: Dictionary = GameData.GU[gu["name"]]
	var now := Time.get_ticks_msec() / 1000.0
	var key := "%d|%d" % [pid, uid]
	if float(cooldowns.get(key, 0.0)) > now:
		_srv_to(pid, "net_log", ["%s 尚在蓄势。" % gu["name"]])
		return
	var cost := float(info["cost"])
	if float(d["essence"]) < cost:
		_srv_to(pid, "net_log", ["真元不足，%s 需 %d 点。" % [gu["name"], int(cost)]])
		return

	d["essence"] = float(d["essence"]) - cost
	cooldowns[key] = now + float(info["cd"])
	_srv_to(pid, "net_cooldown", [uid, float(info["cd"])])

	var p: GuPlayer = players.get(pid)
	var col: Color = info["color"]
	var kind := String(info["kind"])
	if kind == "attack":
		_do_attack(pid, gu, info)
	elif kind == "heal":
		var amount := float(info["power"]) * (1.0 + float(gu["prof"]) / 150.0)
		d["hp"] = minf(GameData.hp_max(int(d["rank"])), float(d["hp"]) + amount)
		if p != null:
			_srv_broadcast("net_fx", ["heal", p.position, col, 58.0, "+%d" % int(amount), 0.0])
	elif kind == "buff":
		var secs := 4.0 + float(gu["prof"]) / 22.0
		_srv_broadcast("net_buff", [pid, String(gu["name"]), secs])
	elif kind == "dash":
		if p != null:
			_srv_broadcast("net_dash", [pid, p.facing, float(info["power"])])
			_srv_broadcast("net_fx", ["ring", p.position, col, 40.0, "", 0.0])
	elif kind == "scan":
		_do_scan(pid)

	_send_self(pid)


@rpc("any_peer", "call_remote", "reliable")
func req_feed(uid: int, item: String) -> void:
	var pid := _sender()
	if not db.has(pid):
		return
	var d: Dictionary = db[pid]
	var gu := _find_gu(d, uid)
	if gu.is_empty():
		_srv_to(pid, "net_log", ["没有找到这只蛊。"])
		return
	if int(d["items"].get(item, 0)) <= 0:
		_srv_to(pid, "net_log", ["没有 %s 可以喂养。" % item])
		return
	if int(gu["prof"]) >= 100:
		_srv_to(pid, "net_log", ["%s 熟练已满，可以尝试升转。" % gu["name"]])
		return
	var gain := int(GameData.FEED_VALUE.get(item, 5))
	if item == "血食" and String(GameData.GU[gu["name"]]["kind"]) == "attack":
		gain = int(float(gain) * 1.5)
	_take_item(d, item, 1)
	gu["prof"] = mini(100, int(gu["prof"]) + gain)
	_srv_to(pid, "net_log", ["%s 吞食 %s，熟练 +%d（现 %d）。"
			% [gu["name"], item, gain, int(gu["prof"])]])
	_send_self(pid)


@rpc("any_peer", "call_remote", "reliable")
func req_rank_up(uid: int) -> void:
	var pid := _sender()
	if not db.has(pid):
		return
	var d: Dictionary = db[pid]
	var gu := _find_gu(d, uid)
	if gu.is_empty():
		return
	var rk := int(gu["rank"])
	if rk >= GameData.RANK_UP_COST.size() - 1:
		_srv_to(pid, "net_log", ["%s 已达本原型支持的最高转数。" % gu["name"]])
		return
	if int(gu["prof"]) < 100:
		_srv_to(pid, "net_log", ["熟练未满 100，无法升转。"])
		return
	var need: Dictionary = GameData.RANK_UP_COST[rk]
	if int(d["items"].get(need["item"], 0)) < int(need["count"]):
		_srv_to(pid, "net_log", ["升转需 %s ×%d。" % [need["item"], need["count"]]])
		return
	_take_item(d, String(need["item"]), int(need["count"]))
	gu["rank"] = rk + 1
	gu["prof"] = 0
	_srv_broadcast("net_log", ["%s 的 %s 破而后立，晋升 %d 转！" % [d["name"], gu["name"], rk + 1]])
	_send_self(pid)


@rpc("any_peer", "call_remote", "reliable")
func req_equip(uid: int, slot: int) -> void:
	var pid := _sender()
	if not db.has(pid):
		return
	var d: Dictionary = db[pid]
	if _find_gu(d, uid).is_empty():
		return
	var slots: Array = d["slots"]
	while slots.size() < 4:
		slots.append(0)
	slots.erase(uid)
	if slot >= 0 and slot < 4:
		slots[slot] = uid
	_send_self(pid)


@rpc("any_peer", "call_remote", "reliable")
func req_breakthrough() -> void:
	var pid := _sender()
	if not db.has(pid):
		return
	var d: Dictionary = db[pid]
	var rk := int(d["rank"])
	if rk >= GameData.RANK_BREAK.size() - 1:
		_srv_to(pid, "net_log", ["你已至本原型最高转数（%d 转）。" % rk])
		return
	var need: Dictionary = GameData.RANK_BREAK[rk]
	var stones := int(need.get("stones", 0))
	if int(d["stones"]) < stones:
		_srv_to(pid, "net_log", ["突破需元石 %d，你只有 %d。" % [stones, int(d["stones"])]])
		return
	var need_items: Dictionary = need.get("items", {})
	for k in need_items.keys():
		if int(d["items"].get(k, 0)) < int(need_items[k]):
			_srv_to(pid, "net_log", ["突破需要 %s ×%d。" % [k, need_items[k]]])
			return
	d["stones"] = int(d["stones"]) - stones
	for k in need_items.keys():
		_take_item(d, String(k), int(need_items[k]))
	d["rank"] = rk + 1
	d["hp"] = GameData.hp_max(rk + 1)
	d["essence"] = GameData.essence_max(rk + 1)
	_srv_broadcast("net_log", ["%s 空窍开阖，晋升 %d 转蛊师！" % [d["name"], rk + 1]])
	_srv_to(pid, "net_log", ["真元上限 %d，气血上限 %d。"
			% [int(GameData.essence_max(rk + 1)), int(GameData.hp_max(rk + 1))]])
	_send_self(pid)


# =========================================================
#  主机：交易
# =========================================================

@rpc("any_peer", "call_remote", "reliable")
func req_trade_request(target: int) -> void:
	var pid := _sender()
	if not db.has(pid) or not db.has(target) or pid == target:
		return
	if not trade.is_empty():
		_srv_to(pid, "net_log", ["当前已有一笔交易在进行。"])
		return
	var pa: GuPlayer = players.get(pid)
	var pb: GuPlayer = players.get(target)
	if pa == null or pb == null:
		return
	if pa.position.distance_to(pb.position) > GameData.TRADE_RANGE:
		_srv_to(pid, "net_log", ["需靠近对方才能当面交易。"])
		return
	trade_seq += 1
	trade = {
		"id": trade_seq,
		"a": pid,
		"b": target,
		"offer": {
			pid: {"items": {}, "stones": 0, "gu": []},
			target: {"items": {}, "stones": 0, "gu": []},
		},
		"confirm": {pid: false, target: false},
	}
	_srv_to(pid, "net_log", ["已向 %s 发起交易。" % pb.player_name])
	_srv_to(target, "net_log", ["%s 向你发起交易。" % pa.player_name])
	_push_trade()


@rpc("any_peer", "call_remote", "reliable")
func req_trade_set(items: Dictionary, stones: int, gu_uids: Array) -> void:
	var pid := _sender()
	if trade.is_empty() or not db.has(pid):
		return
	if pid != int(trade["a"]) and pid != int(trade["b"]):
		return
	var d: Dictionary = db[pid]

	var clean_items := {}
	for k in items.keys():
		var want := int(items[k])
		if want <= 0:
			continue
		var have := int(d["items"].get(k, 0))
		if have <= 0:
			continue
		clean_items[String(k)] = mini(want, have)

	var clean_gu: Array = []
	for u in gu_uids:
		var ui := int(u)
		var dup := false
		for e in clean_gu:
			if int(e["uid"]) == ui:
				dup = true
				break
		if dup:
			continue
		var g := _find_gu(d, ui)
		if g.is_empty():
			continue
		clean_gu.append({"uid": ui, "name": String(g["name"])})

	var clean_stones := clampi(stones, 0, int(d["stones"]))
	trade["offer"][pid] = {"items": clean_items, "stones": clean_stones, "gu": clean_gu}
	trade["confirm"][pid] = false
	_push_trade()


@rpc("any_peer", "call_remote", "reliable")
func req_trade_confirm() -> void:
	var pid := _sender()
	if trade.is_empty() or not db.has(pid):
		return
	if pid != int(trade["a"]) and pid != int(trade["b"]):
		return
	trade["confirm"][pid] = true
	if bool(trade["confirm"][int(trade["a"])]) and bool(trade["confirm"][int(trade["b"])]):
		_execute_trade()
	else:
		_push_trade()


@rpc("any_peer", "call_remote", "reliable")
func req_trade_cancel() -> void:
	var pid := _sender()
	if trade.is_empty():
		return
	if pid != int(trade["a"]) and pid != int(trade["b"]):
		return
	_close_trade("交易已取消。")


func _push_trade() -> void:
	if trade.is_empty():
		return
	var a := int(trade["a"])
	var b := int(trade["b"])
	_srv_to(a, "net_trade_state", [trade])
	_srv_to(b, "net_trade_state", [trade])


func _close_trade(msg: String) -> void:
	if trade.is_empty():
		return
	var a := int(trade["a"])
	var b := int(trade["b"])
	trade = {}
	_srv_to(a, "net_trade_closed", [msg])
	_srv_to(b, "net_trade_closed", [msg])


func _owns(d: Dictionary, offer: Dictionary) -> bool:
	if int(d["stones"]) < int(offer["stones"]):
		return false
	var items: Dictionary = offer["items"]
	for k in items.keys():
		if int(d["items"].get(k, 0)) < int(items[k]):
			return false
	for g in offer["gu"]:
		if _find_gu(d, int(g["uid"])).is_empty():
			return false
	return true


## 从 d 中扣除报价内容，返回被扣走的蛊虫实体列表。
func _extract(d: Dictionary, offer: Dictionary) -> Array:
	var taken_gu: Array = []
	var items: Dictionary = offer["items"]
	for k in items.keys():
		_take_item(d, String(k), int(items[k]))
	var stones := int(offer["stones"])
	if stones > 0:
		d["stones"] = int(d["stones"]) - stones
	for g in offer["gu"]:
		var got := _remove_gu(d, int(g["uid"]))
		if not got.is_empty():
			taken_gu.append(got)
	return taken_gu


## 把报价内容交付给 d（蛊虫实体由调用方传入）。
func _deposit(d: Dictionary, offer: Dictionary, gu_list: Array) -> void:
	var items: Dictionary = offer["items"]
	for k in items.keys():
		d["items"][k] = int(d["items"].get(k, 0)) + int(items[k])
	d["stones"] = int(d["stones"]) + int(offer["stones"])
	for g in gu_list:
		d["gu"].append(g)


func _execute_trade() -> void:
	var a := int(trade["a"])
	var b := int(trade["b"])
	if not db.has(a) or not db.has(b):
		_close_trade("交易失败：对方已离线。")
		return
	var pa: GuPlayer = players.get(a)
	var pb: GuPlayer = players.get(b)
	if pa == null or pb == null or pa.position.distance_to(pb.position) > GameData.TRADE_RANGE + 60.0:
		_close_trade("交易失败：双方距离太远。")
		return
	var da: Dictionary = db[a]
	var db2: Dictionary = db[b]
	var oa: Dictionary = trade["offer"][a]
	var ob: Dictionary = trade["offer"][b]
	if not (_owns(da, oa) and _owns(db2, ob)):
		_close_trade("交易失败：物品已变动。")
		return

	var gu_from_a := _extract(da, oa)
	var gu_from_b := _extract(db2, ob)
	_deposit(db2, oa, gu_from_a)
	_deposit(da, ob, gu_from_b)

	trade = {}
	_srv_broadcast("net_fx", ["ring", pa.position, Color(0.95, 0.85, 0.45), 64.0, "", 0.0])
	_send_self(a)
	_send_self(b)
	_srv_to(a, "net_trade_closed", ["交易完成。"])
	_srv_to(b, "net_trade_closed", ["交易完成。"])
	if hud != null:
		hud.push_log("%s 与 %s 达成一笔交易。" % [da["name"], db2["name"]])


# =========================================================
#  主机：战斗与掉落
# =========================================================

func _do_attack(pid: int, gu: Dictionary, info: Dictionary) -> void:
	var p: GuPlayer = players.get(pid)
	if p == null:
		return
	var power := float(info["power"])
	power *= 1.0 + float(gu["prof"]) / 150.0
	power *= 1.0 + (float(gu["rank"]) - 1.0) * 0.6
	var col: Color = info["color"]
	var hit := 0
	var idx_list: Array = beasts.keys()
	for idx in idx_list:
		var b: GuBeast = beasts.get(idx)
		if b == null or not is_instance_valid(b):
			continue
		if p.position.distance_to(b.position) <= 175.0:
			b.hp = b.hp - power
			b.flash()
			hit += 1
			_srv_broadcast("net_fx", ["ring", b.position, col, 44.0, "-%d" % int(power), 0.0])
			_srv_broadcast("net_beast_state", [idx, b.position, b.hp, b.hp_max])
			if b.hp <= 0.0:
				_kill_beast(idx)
	if hit == 0:
		var at := p.position + p.facing.normalized() * 80.0
		_srv_broadcast("net_fx", ["ring", at, col, 62.0, "", 0.0])


func _do_scan(pid: int) -> void:
	var p: GuPlayer = players.get(pid)
	if p == null:
		return
	var found: Array = []
	for i in world.resources.size():
		if depleted.has(i):
			continue
		var r: Dictionary = world.resources[i]
		var dist: float = p.position.distance_to(r["pos"])
		if dist <= 560.0:
			found.append({"d": dist, "text": "%s ×%d（约 %d 步）"
					% [r["item"], r["amount"], int(dist / float(GameData.CELL))]})
	found.sort_custom(func(x, y) -> bool: return float(x["d"]) < float(y["d"]))
	var lines: Array = []
	var n := mini(4, found.size())
	for i in n:
		lines.append("灵犀所感 · " + String(found[i]["text"]))
	_srv_to(pid, "net_scan", [lines])


func _kill_beast(idx: int) -> void:
	var b: GuBeast = beasts.get(idx)
	if b == null:
		return
	var kind := b.kind
	var pos := b.position
	var info: Dictionary = GameData.BEASTS[kind]

	var killer := 0
	var best := 1.0e20
	for pid in players.keys():
		var p: GuPlayer = players[pid]
		if p == null or not is_instance_valid(p):
			continue
		var dist: float = p.position.distance_to(pos)
		if dist < best:
			best = dist
			killer = pid

	if killer != 0 and db.has(killer):
		var drops: Dictionary = info["drop"]
		var parts: Array = []
		for k in drops.keys():
			_add_item(killer, String(k), int(drops[k]))
			parts.append("%s×%d" % [k, drops[k]])
		var txt := ""
		for i in parts.size():
			if i > 0:
				txt += "、"
			txt += String(parts[i])
		_srv_to(killer, "net_log", ["击杀 %s，得 %s。" % [kind, txt]])
		_send_self(killer)

	# 顺序很重要：必须先广播、后删除！
	#
	# net_beast_died() 靠 beasts.get(idx) 拿到节点引用才能 queue_free()。
	# 如果在这里先 beasts.erase(idx)，本机收到广播时取到的就是 null，
	# queue_free() 永远不会执行 —— 妖兽会变成一个「血条空了、还在追你、
	# 还打不死」的幽灵（因为它已经不在 beasts 里，_do_attack 再也瞄不到它）。
	_srv_broadcast("net_beast_died", [idx])
	respawn_queue.append({"kind": kind, "at": Time.get_ticks_msec() + 20000})


func apply_beast_damage(pid: int, dmg: int) -> void:
	if not db.has(pid):
		return
	var d: Dictionary = db[pid]
	# 真元先护体（1 点真元抵 0.35 点伤害），再伤气血
	var shield := float(d["essence"]) * 0.35
	var left := float(dmg)
	if shield > 0.0:
		var used := minf(shield, left)
		d["essence"] = maxf(0.0, float(d["essence"]) - used / 0.35)
		left -= used
	d["hp"] = maxf(0.0, float(d["hp"]) - left)

	var p: GuPlayer = players.get(pid)
	if p != null:
		_srv_broadcast("net_fx", ["ring", p.position, Color(0.90, 0.30, 0.30), 30.0,
				"-%d" % dmg, 0.0])
	if float(d["hp"]) <= 0.0:
		_die(pid)
	_send_self(pid)


func _die(pid: int) -> void:
	var d: Dictionary = db[pid]
	var rk := int(d["rank"])
	d["hp"] = GameData.hp_max(rk) * 0.5
	d["essence"] = GameData.essence_max(rk) * 0.3
	var p: GuPlayer = players.get(pid)
	if p != null:
		p.position = _free_spawn_point()
		p.broadcast_now()
	_srv_to(pid, "net_log", ["气血耗尽，你被人拖回蛊道起始之地。"])


# =========================================================
#  主机：妖兽生成与状态广播
# =========================================================

func _spawn_beast(forced_kind: String) -> void:
	var kind := forced_kind
	if kind == "" or not GameData.BEASTS.has(kind):
		kind = GameData.BEAST_ORDER[randi() % GameData.BEAST_ORDER.size()]
	var center := Vector2(GameData.WORLD_PX, GameData.WORLD_PX) * 0.5
	var pos := _free_spawn_point()
	if forced_kind == "" and pos.distance_to(center) < 700.0:
		var dir := pos - center
		if dir.length() < 1.0:
			dir = Vector2.RIGHT
		var far := center + dir.normalized() * 900.0
		if not world.is_blocked(far):
			pos = far
	beast_seq += 1
	var idx := beast_seq
	var hp := float(GameData.BEASTS[kind]["hp"])
	_srv_broadcast("net_beast_spawn", [idx, kind, pos, hp, hp])


func broadcast_beast_state(idx: int, pos: Vector2, hp: float, hp_max: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		multiplayer.rpc(0, self, &"net_beast_state", [idx, pos, hp, hp_max])


func push_my_state() -> void:
	if my_player == null or not is_instance_valid(my_player):
		return
	var args := [my_id, my_player.position, my_player.facing, my_player.essence, my_player.hp]
	if not multiplayer.has_multiplayer_peer():
		callv(&"net_state", args)
	elif multiplayer.is_server():
		multiplayer.rpc(0, self, &"net_state", args)
	else:
		multiplayer.rpc(1, self, &"req_state", args)


# =========================================================
#  主机 → 所有端：状态广播
# =========================================================

@rpc("authority", "call_local", "reliable")
func net_self(d: Dictionary) -> void:
	my_data = d
	if my_player != null and is_instance_valid(my_player):
		my_player.rank = int(d["rank"])
		my_player.hp_max = GameData.hp_max(my_player.rank)
		my_player.essence_max = GameData.essence_max(my_player.rank)
		my_player.hp = float(d["hp"])
		my_player.essence = float(d["essence"])
		my_player.queue_redraw()
	if hud != null:
		hud.refresh(d)
	# 交易进行中时同步刷新，保证「还能报价多少」的依据是最新的
	if trade_win != null and trade_win.visible:
		trade_win.my_data = d


@rpc("authority", "call_local", "reliable")
func net_spawn_player(pid: int, pname: String, pos: Vector2, rank: int) -> void:
	if players.has(pid):
		return
	var p := GuPlayer.new()
	p.name = "P_%d" % pid
	p.peer_id = pid
	p.player_name = pname
	p.rank = rank
	p.hp_max = GameData.hp_max(rank)
	p.essence_max = GameData.essence_max(rank)
	p.hp = p.hp_max
	p.essence = p.essence_max
	p.game = self
	p.world = world
	p.font = world.font if world != null else null
	p.position = pos
	players[pid] = p
	players_node.add_child(p)
	if pid == my_id and my_player == null:
		my_player = p
		p.is_local = true
		if camera != null:
			camera.position = pos
			camera.make_current()
	if hud != null:
		hud.push_log("%s 步入蛊道。" % pname)


@rpc("authority", "call_local", "unreliable_ordered")
func net_state(pid: int, pos: Vector2, face: Vector2, es: float, hp: float) -> void:
	var p: GuPlayer = players.get(pid)
	if p == null or p.is_local:
		return
	p.position = pos
	p.facing = face
	p.essence = es
	p.hp = hp
	p.queue_redraw()


@rpc("authority", "call_local", "reliable")
func net_log(text: String) -> void:
	if hud != null:
		hud.push_log(text)


@rpc("authority", "call_local", "reliable")
func net_fx(kind: String, pos: Vector2, color: Color, radius: float, text: String,
		_extra: float) -> void:
	if fx == null:
		return
	if kind == "ring" or kind == "heal":
		fx.ring(pos, color, radius)
	if text != "":
		fx.flash_text(pos, text, color)


@rpc("authority", "call_local", "reliable")
func net_scan(lines: Array) -> void:
	if hud == null:
		return
	if lines.is_empty():
		hud.push_log("灵犀所感：附近并无明显灵机。")
	else:
		for l in lines:
			hud.push_log(String(l))


@rpc("authority", "call_local", "reliable")
func net_cooldown(uid: int, secs: float) -> void:
	if hud != null:
		hud.set_cooldown(uid, secs)


@rpc("authority", "call_local", "reliable")
func net_buff(pid: int, key: String, secs: float) -> void:
	var p: GuPlayer = players.get(pid)
	if p == null:
		return
	p.buffs[key] = Time.get_ticks_msec() / 1000.0 + secs
	p.queue_redraw()
	if hud != null:
		hud.push_log("%s 施展 %s（%.0f 秒）。" % [p.player_name, key, secs])


@rpc("authority", "call_local", "reliable")
func net_dash(pid: int, dir: Vector2, dist: float) -> void:
	var p: GuPlayer = players.get(pid)
	if p == null or not p.is_local:
		return
	p.try_dash(dir, dist)


@rpc("authority", "call_local", "reliable")
func net_resource_taken(idx: int) -> void:
	depleted[idx] = true
	if world != null:
		world.mark_taken(idx)


@rpc("authority", "call_local", "reliable")
func net_sync_depleted(list: Array) -> void:
	for i in list:
		net_resource_taken(int(i))


@rpc("authority", "call_local", "reliable")
func net_beast_spawn(idx: int, kind: String, pos: Vector2, hp: float, hp_max: float) -> void:
	if beasts.has(idx):
		return
	var b := GuBeast.new()
	b.name = "B_%d" % idx
	b.index = idx
	b.kind = kind
	b.hp = hp
	b.hp_max = hp_max
	b.world = world
	b.game = self
	b.font = world.font if world != null else null
	b.host_sim = _is_authority()
	b.players_ref = players
	b.position = pos
	beasts[idx] = b
	beasts_node.add_child(b)


@rpc("authority", "call_local", "unreliable_ordered")
func net_beast_state(idx: int, pos: Vector2, hp: float, hp_max: float) -> void:
	var b: GuBeast = beasts.get(idx)
	if b == null:
		return
	if hp < b.hp:
		b.flash()
	b.hp = hp
	b.hp_max = hp_max
	if not b.host_sim:
		b.position = pos
	b.queue_redraw()


@rpc("authority", "call_local", "reliable")
func net_beast_died(idx: int) -> void:
	var b: GuBeast = beasts.get(idx)
	beasts.erase(idx)
	if b != null and is_instance_valid(b):
		b.queue_free()


@rpc("authority", "call_local", "reliable")
func net_trade_state(session: Dictionary) -> void:
	if trade_win == null:
		return
	if trade_win.visible:
		trade_win.update_session(session)
	else:
		trade_win.open(my_id, my_data, session)


@rpc("authority", "call_local", "reliable")
func net_trade_closed(msg: String) -> void:
	if trade_win != null:
		trade_win.close()
	if hud != null and msg != "":
		hud.push_log(msg)


# =========================================================
#  输入回调 → 意图
# =========================================================

func _on_gather() -> void:
	if my_player == null or world == null:
		return
	var idx := world.resource_near(my_player.position, GameData.GATHER_RANGE)
	if idx < 0:
		if hud != null:
			hud.push_log("附近没有可采之物。")
		return
	_to_host(&"req_gather", [idx])


func _on_trade_button() -> void:
	if my_player == null:
		return
	var target := 0
	var best := GameData.TRADE_RANGE
	for pid in players.keys():
		if pid == my_id:
			continue
		var p: GuPlayer = players[pid]
		if p == null or not is_instance_valid(p):
			continue
		var dist: float = my_player.position.distance_to(p.position)
		if dist < best:
			best = dist
			target = pid
	if target == 0:
		if hud != null:
			hud.push_log("需先靠近另一位蛊师（约 3 格内），再按 T。")
		return
	_to_host(&"req_trade_request", [target])


func _on_offer_changed(items: Dictionary, stones: int, gu_uids: Array) -> void:
	_to_host(&"req_trade_set", [items, stones, gu_uids])


func _on_trade_confirm() -> void:
	_to_host(&"req_trade_confirm", [])


func _on_trade_cancel() -> void:
	_to_host(&"req_trade_cancel", [])


func _on_help() -> void:
	if hud == null:
		return
	hud.push_log("【操作】WASD 移动　E 采集　1~4 用蛊　Tab 蛊囊　T 交易　F 突破　H 帮助　F3 调试面板")
	hud.push_log("【循环】采药／打妖兽 → 喂养蛊虫涨熟练 → 熟练满 + 月华露 升转 → 换更好的蛊")
	hud.push_log("【交易】走到另一位蛊师身边按 T；双方各自放入材料／蛊虫／元石，都点确认才成交")
	hud.push_log("【突破】蛊师转数决定真元与气血上限，需元石与材料，元石主要靠交易获得")
	hud.push_log("【学习】想改数值看结果？按 F3 打开面板，改完保存重跑就能立刻看到变化")


# =========================================================
#  主循环
# =========================================================

func _process(delta: float) -> void:
	if world == null:
		return

	if my_player != null and is_instance_valid(my_player) and camera != null:
		camera.position = camera.position.lerp(my_player.position, clampf(11.0 * delta, 0.0, 1.0))
		_update_prompt()

	if _is_authority() and not db.is_empty():
		_authority_tick(delta)


func _update_prompt() -> void:
	if hud == null or my_player == null:
		return
	var idx := world.resource_near(my_player.position, GameData.GATHER_RANGE)
	if idx >= 0:
		var r := world.get_resource(idx)
		hud.set_prompt("[E] 采集 %s ×%d" % [r["item"], r["amount"]])
		return
	var near_name := ""
	for pid in players.keys():
		if pid == my_id:
			continue
		var p: GuPlayer = players[pid]
		if p == null or not is_instance_valid(p):
			continue
		if my_player.position.distance_to(p.position) <= GameData.TRADE_RANGE:
			near_name = p.player_name
			break
	if near_name != "":
		hud.set_prompt("[T] 与 %s 当面交易" % near_name)
	else:
		hud.set_prompt("")


func _authority_tick(delta: float) -> void:
	# 真元与气血自然回复
	for pid in db.keys():
		var d: Dictionary = db[pid]
		var rk := int(d["rank"])
		d["essence"] = minf(GameData.essence_max(rk), float(d["essence"]) + 3.5 * delta)
		d["hp"] = minf(GameData.hp_max(rk), float(d["hp"]) + 1.2 * delta)

	# 定期把自己的权威数据推给自己
	_push_accum += delta
	if _push_accum >= 0.25:
		_push_accum = 0.0
		for pid in db.keys():
			_send_self(pid)

	# 妖兽重生
	if not respawn_queue.is_empty():
		var now := Time.get_ticks_msec()
		var keep: Array = []
		for r in respawn_queue:
			if int(r["at"]) <= now:
				_spawn_beast(String(r["kind"]))
			else:
				keep.append(r)
		respawn_queue = keep
