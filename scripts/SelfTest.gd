class_name GuSelfTest
extends RefCounted
## 无头自动化自测：直接驱动主机权威逻辑，跑通「采集 → 喂养 → 升转 → 用蛊 →
## 突破 → 击杀掉落 → 面对面交易」整条链路。
##
##   godot --headless --path <工程目录> -- --selftest
##
## 全部通过退出码 0，有失败则 1，方便接进 CI。

var game: Node = null
var ok_count := 0
var fail_count := 0


func run(g: Node) -> void:
	game = g
	print("========== 蛊真人原型 · 无头自测 ==========")
	_test_world()
	_test_gather()
	_test_feed()
	_test_rank_up()
	_test_equip_and_use()
	_test_breakthrough()
	_test_beast_kill()
	_test_trade()
	print("========== 通过 %d 项，失败 %d 项 ==========" % [ok_count, fail_count])
	game.get_tree().quit(0 if fail_count == 0 else 1)


func _check(name: String, cond: bool, detail := "") -> void:
	if cond:
		ok_count += 1
		print("  [PASS] %s  %s" % [name, detail])
	else:
		fail_count += 1
		print("  [FAIL] %s  %s" % [name, detail])


# ---------------- 1. 世界与初始状态 ----------------
func _test_world() -> void:
	print("[1] 世界与初始状态")
	_check("世界已生成", game.world != null and game.world.resources.size() > 100,
			"资源点 %d 个" % (game.world.resources.size() if game.world != null else -1))
	_check("本地玩家已生成", game.my_player != null)
	_check("妖兽数量正确", game.beasts.size() == GameData.BEAST_COUNT,
			"实际 %d / 期望 %d" % [game.beasts.size(), GameData.BEAST_COUNT])
	var d: Dictionary = game.db.get(1, {})
	_check("初始 4 只蛊虫", (d.get("gu", []) as Array).size() == 4)
	_check("初始元石正确", int(d.get("stones", -1)) == GameData.STARTER_STONES,
			"实际 %d" % int(d.get("stones", -1)))
	# 调试面板（F3）的内容生成逻辑也要能跑，否则按 F3 就炸
	var dbg_text: String = game.debug_panel.build_text()
	_check("调试面板能生成内容",
			dbg_text.length() > 40 and dbg_text.find("我的蛊师") >= 0,
			"%d 字" % dbg_text.length())


# ---------------- 2. 采集 ----------------
func _test_gather() -> void:
	print("[2] 采集")
	var idx := -1
	for i in game.world.resources.size():
		if not game.depleted.has(i):
			idx = i
			break
	if idx < 0:
		_check("找到可采资源点", false)
		return
	var node: Dictionary = game.world.get_resource(idx)
	game.my_player.position = node["pos"]
	var d: Dictionary = game.db[1]
	var before := int(d["items"].get(node["item"], 0))
	game._to_host(&"req_gather", [idx])
	var after := int(d["items"].get(node["item"], 0))
	_check("采集后材料增加", after == before + int(node["amount"]),
			"%s %d -> %d" % [node["item"], before, after])
	_check("资源点标记为已采", game.depleted.has(idx))
	game._to_host(&"req_gather", [idx])
	_check("同一点不能重复采", int(d["items"].get(node["item"], 0)) == after)
	# 距离校验
	var idx2 := -1
	for i in game.world.resources.size():
		if not game.depleted.has(i):
			idx2 = i
			break
	if idx2 >= 0:
		var far: Dictionary = game.world.get_resource(idx2)
		var before2 := int(d["items"].get(far["item"], 0))
		game.my_player.position = far["pos"] + Vector2(4000.0, 0.0)
		game._to_host(&"req_gather", [idx2])
		_check("距离太远采不到", int(d["items"].get(far["item"], 0)) == before2)
		game.my_player.position = far["pos"]


# ---------------- 3. 喂养 ----------------
func _test_feed() -> void:
	print("[3] 喂养蛊虫")
	var d: Dictionary = game.db[1]
	var gu: Dictionary = d["gu"][0]
	d["items"]["灵药"] = int(d["items"].get("灵药", 0)) + 5
	var before_prof := int(gu["prof"])
	var before_item := int(d["items"]["灵药"])
	game._to_host(&"req_feed", [int(gu["uid"]), "灵药"])
	_check("熟练度提升", int(gu["prof"]) > before_prof,
			"%d -> %d" % [before_prof, int(gu["prof"])])
	_check("材料被消耗", int(d["items"].get("灵药", 0)) == before_item - 1)
	var keep := int(gu["prof"])
	game._to_host(&"req_feed", [int(gu["uid"]), "根本没有的材料"])
	_check("没有的材料喂不了", int(gu["prof"]) == keep)


# ---------------- 4. 蛊虫升转 ----------------
func _test_rank_up() -> void:
	print("[4] 蛊虫升转")
	var d: Dictionary = game.db[1]
	var gu: Dictionary = d["gu"][0]
	var uid := int(gu["uid"])
	var before_rank := int(gu["rank"])
	gu["prof"] = 50
	game._to_host(&"req_rank_up", [uid])
	_check("熟练不满不能升转", int(gu["rank"]) == before_rank)
	gu["prof"] = 100
	d["items"]["月华露"] = int(d["items"].get("月华露", 0)) + 2
	var before_mat := int(d["items"]["月华露"])
	game._to_host(&"req_rank_up", [uid])
	_check("升转成功", int(gu["rank"]) == before_rank + 1,
			"%d 转 -> %d 转" % [before_rank, int(gu["rank"])])
	_check("月华露被扣除", int(d["items"].get("月华露", 0)) == before_mat - 2)
	_check("熟练度清零", int(gu["prof"]) == 0)


# ---------------- 5. 装配与用蛊 ----------------
func _test_equip_and_use() -> void:
	print("[5] 装配与用蛊")
	var d: Dictionary = game.db[1]
	var attack_uid := 0
	for g in d["gu"]:
		if String(GameData.GU[g["name"]]["kind"]) == "attack":
			attack_uid = int(g["uid"])
			break
	_check("持有攻伐蛊", attack_uid != 0)
	if attack_uid == 0:
		return
	game._to_host(&"req_equip", [attack_uid, 0])
	_check("装配到快捷栏 1", int(d["slots"][0]) == attack_uid)

	var gu: Dictionary = game._find_gu(d, attack_uid)
	var cost := float(GameData.GU[gu["name"]]["cost"])
	d["essence"] = GameData.essence_max(int(d["rank"]))
	var before_ess := float(d["essence"])

	var beast: GuBeast = null
	for k in game.beasts.keys():
		beast = game.beasts[k]
		break
	var before_hp := 0.0
	if beast != null:
		beast.position = game.my_player.position + Vector2(40.0, 0.0)
		before_hp = beast.hp

	game._to_host(&"req_use_gu", [0])
	_check("真元被消耗", absf(float(d["essence"]) - (before_ess - cost)) < 0.01,
			"%.1f -> %.1f（消耗 %.1f）" % [before_ess, float(d["essence"]), cost])
	if beast != null:
		_check("妖兽受到伤害", beast.hp < before_hp,
				"%.1f -> %.1f" % [before_hp, beast.hp])

	var after_use := float(d["essence"])
	game._to_host(&"req_use_gu", [0])
	_check("冷却中无法连放", absf(float(d["essence"]) - after_use) < 0.01)

	# 真元不足
	d["essence"] = 0.0
	game.cooldowns.clear()
	var hp_before := float(d["hp"])
	game._to_host(&"req_use_gu", [0])
	_check("真元不足放不出蛊", float(d["essence"]) == 0.0 and float(d["hp"]) == hp_before)


# ---------------- 6. 蛊师突破 ----------------
func _test_breakthrough() -> void:
	print("[6] 蛊师突破")
	var d: Dictionary = game.db[1]
	var rk := int(d["rank"])
	d["stones"] = 0
	game._to_host(&"req_breakthrough", [])
	_check("元石不足无法突破", int(d["rank"]) == rk)

	var need: Dictionary = GameData.RANK_BREAK[rk]
	d["stones"] = int(need["stones"]) + 50
	var need_items: Dictionary = need["items"]
	for k in need_items.keys():
		d["items"][k] = int(d["items"].get(k, 0)) + int(need_items[k])
	game._to_host(&"req_breakthrough", [])
	_check("突破成功", int(d["rank"]) == rk + 1, "%d 转 -> %d 转" % [rk, int(d["rank"])])
	_check("真元上限提升", float(d["essence"]) == GameData.essence_max(rk + 1),
			"%.0f" % float(d["essence"]))
	_check("元石被扣除", int(d["stones"]) == 50, "剩 %d" % int(d["stones"]))


# ---------------- 7. 妖兽击杀与掉落 ----------------
func _test_beast_kill() -> void:
	print("[7] 妖兽击杀与掉落")
	var idx := -1
	var beast: GuBeast = null
	for k in game.beasts.keys():
		idx = int(k)
		beast = game.beasts[k]
		break
	if beast == null:
		_check("存在可击杀的妖兽", false)
		return
	var kind := beast.kind
	var drop: Dictionary = GameData.BEASTS[kind]["drop"]
	beast.position = game.my_player.position + Vector2(20.0, 0.0)
	var d: Dictionary = game.db[1]
	var before: Dictionary = {}
	for k in drop.keys():
		before[k] = int(d["items"].get(k, 0))
	var n_before: int = game.beasts.size()
	game._kill_beast(idx)
	_check("妖兽被移除", game.beasts.size() == n_before - 1)
	var all_ok := true
	for k in drop.keys():
		if int(d["items"].get(k, 0)) != int(before[k]) + int(drop[k]):
			all_ok = false
	_check("掉落物进入最近玩家的背包", all_ok, "%s 掉落 %s" % [kind, str(drop)])
	_check("进入重生队列", game.respawn_queue.size() >= 1)


# ---------------- 8. 面对面自由交易 ----------------
func _test_trade() -> void:
	print("[8] 面对面自由交易（核心）")
	var d1: Dictionary = game.db[1]
	d1["items"]["灵药"] = int(d1["items"].get("灵药", 0)) + 10
	d1["items"]["月华露"] = int(d1["items"].get("月华露", 0)) + 3
	d1["stones"] = 500

	# 造一个本地模拟的第二位蛊师，走的仍是真实的主机权威交易代码
	var pid2 := 2
	game.db[pid2] = game._new_player_data("交易对手")
	game._spawn_player(pid2, "交易对手", game.my_player.position + Vector2(30.0, 0.0))
	_check("第二位蛊师已生成", game.players.has(pid2) and game.players[pid2] != null)
	if not game.players.has(pid2):
		return
	var d2: Dictionary = game.db[pid2]
	var p2: GuPlayer = game.players[pid2]

	game.gu_seq += 1
	var gu2_uid: int = int(game.gu_seq)
	d2["gu"].append({"uid": gu2_uid, "name": "火蛇蛊", "rank": 1, "prof": 0})
	d2["slots"][0] = gu2_uid

	# 8.1 太远不能发起
	p2.position = game.my_player.position + Vector2(3000.0, 0.0)
	game._test_as(1, &"req_trade_request", [pid2])
	_check("距离过远无法发起交易", game.trade.is_empty())

	# 8.2 靠近后可以发起
	p2.position = game.my_player.position + Vector2(30.0, 0.0)
	game._test_as(1, &"req_trade_request", [pid2])
	_check("交易会话已创建", not game.trade.is_empty())
	if game.trade.is_empty():
		return

	# 8.3 报价被主机裁剪：不能报出自己没有的东西
	game._test_as(1, &"req_trade_set", [{"灵药": 2, "月华露": 9999}, 5, []])
	var o1: Dictionary = game.trade["offer"][1]
	_check("材料报价裁剪到实际持有量",
			int(o1["items"].get("月华露", 0)) == int(d1["items"].get("月华露", 0)),
			"报 9999 → 实际 %d" % int(o1["items"].get("月华露", 0)))
	_check("元石报价裁剪", int(o1["stones"]) == mini(5, int(d1["stones"])),
			"报 5 → %d" % int(o1["stones"]))

	# 8.4 对手报价
	game._test_as(pid2, &"req_trade_set", [{}, 0, [gu2_uid]])
	_check("对手报价含蛊虫", (game.trade["offer"][pid2]["gu"] as Array).size() == 1)

	# 8.5 改变报价会重置确认状态
	game._test_as(1, &"req_trade_confirm", [])
	_check("确认状态已被主机记录", bool(game.trade["confirm"][1]))
	game._test_as(1, &"req_trade_set", [{"灵药": 2}, 5, []])
	_check("改动报价后确认状态被重置", not bool(game.trade["confirm"][1]))

	# 8.6 双方确认 → 一次性交换
	game._test_as(1, &"req_trade_set", [{"灵药": 2}, 5, []])
	game._test_as(pid2, &"req_trade_set", [{}, 0, [gu2_uid]])
	var i1_before := int(d1["items"].get("灵药", 0))
	var i2_before := int(d2["items"].get("灵药", 0))
	var s1_before := int(d1["stones"])
	var s2_before := int(d2["stones"])
	game._test_as(1, &"req_trade_confirm", [])
	game._test_as(pid2, &"req_trade_confirm", [])

	_check("双方确认后交易关闭", game.trade.is_empty())
	_check("我拿到了对手的蛊虫", not game._find_gu(d1, gu2_uid).is_empty())
	_check("对手不再持有该蛊虫", game._find_gu(d2, gu2_uid).is_empty())
	_check("蛊虫实体是移交而非复制",
			int(game._find_gu(d1, gu2_uid).get("rank", 0)) == 1
			and String(game._find_gu(d1, gu2_uid).get("name", "")) == "火蛇蛊")
	_check("我的灵药减少 2", int(d1["items"].get("灵药", 0)) == i1_before - 2,
			"%d -> %d" % [i1_before, int(d1["items"].get("灵药", 0))])
	_check("对手灵药增加 2", int(d2["items"].get("灵药", 0)) == i2_before + 2,
			"%d -> %d" % [i2_before, int(d2["items"].get("灵药", 0))])
	_check("元石完成对转",
			int(d1["stones"]) == s1_before - 5 and int(d2["stones"]) == s2_before + 5,
			"我 %d -> %d，对手 %d -> %d" % [s1_before, int(d1["stones"]),
					s2_before, int(d2["stones"])])

	# 8.7 交易不会凭空创造资产（总量守恒）
	var total_stones := int(d1["stones"]) + int(d2["stones"])
	_check("元石总量守恒", total_stones == s1_before + s2_before, "合计 %d" % total_stones)
