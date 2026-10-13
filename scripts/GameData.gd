class_name GameData
extends RefCounted
## 全局静态数据与工具函数。
##
## 这里只放「常量」，主机与所有客户端共用同一份，保证世界生成与表现一致。
## 注意：本原型为了在 Godot 默认字体缺字的情况下依然显示中文，
## 用 SystemFont 直接调用系统里的中文字体，见 make_font()。

# ---------------- 基础参数 ----------------
const PORT := 27015
const MAX_PLAYERS := 8
const WORLD_SEED := 20240617
const MAP := 84                    # 世界为 MAP × MAP 格
const CELL := 48                   # 每格像素
const WORLD_PX := MAP * CELL
const BEAST_COUNT := 16
const STARTER_STONES := 150
const GATHER_RANGE := 90.0         # 采集判定距离
const TRADE_RANGE := 160.0         # 交易判定距离

# ---------------- 地形 ----------------
const TILE_GRASS := 0
const TILE_FOREST := 1
const TILE_WATER := 2
const TILE_ROCK := 3
const TILE_HERB := 4

const TILE_COLORS := {
	TILE_GRASS: Color(0.24, 0.36, 0.23),
	TILE_FOREST: Color(0.15, 0.25, 0.16),
	TILE_WATER: Color(0.11, 0.25, 0.36),
	TILE_ROCK: Color(0.29, 0.29, 0.32),
	TILE_HERB: Color(0.29, 0.42, 0.23),
}

const TILE_NAMES := {
	TILE_GRASS: "草地",
	TILE_FOREST: "密林",
	TILE_WATER: "水域",
	TILE_ROCK: "岩地",
	TILE_HERB: "药田",
}

# ---------------- 材料 ----------------
const ITEMS := {
	"灵药": {"color": Color(0.44, 0.75, 0.35), "desc": "寻常药草，喂养蛊虫可增长熟练度。"},
	"精铁": {"color": Color(0.60, 0.64, 0.70), "desc": "铁矿，炼蛊所需的基础材料。"},
	"兽骨": {"color": Color(0.88, 0.85, 0.75), "desc": "妖兽残骨，喂养力道／血道蛊虫效果不错。"},
	"月华露": {"color": Color(0.62, 0.84, 1.00), "desc": "月下凝露，稀有。蛊虫升转的关键材料。"},
	"血食": {"color": Color(0.82, 0.31, 0.31), "desc": "新鲜血肉，喂养攻伐类蛊虫最佳。"},
}
const ITEM_ORDER := ["灵药", "精铁", "兽骨", "月华露", "血食"]

# ---------------- 蛊虫图鉴 ----------------
# kind: attack 攻伐 / heal 疗伤 / buff 增益 / dash 身法 / scan 感知
const KIND_CN := {
	"attack": "攻伐",
	"heal": "疗伤",
	"buff": "增益",
	"dash": "身法",
	"scan": "感知",
}

const GU := {
	"月刃蛊": {
		"rank": 1, "dao": "力道", "cost": 6, "kind": "attack", "power": 9, "cd": 0.9,
		"color": Color(0.81, 0.90, 1.00),
		"desc": "凝月华成刃，斩出弧形刀光，杀伤周身之敌。",
	},
	"火蛇蛊": {
		"rank": 1, "dao": "火道", "cost": 8, "kind": "attack", "power": 12, "cd": 1.1,
		"color": Color(1.00, 0.54, 0.24),
		"desc": "喷吐火蛇，灼烧近身之敌。",
	},
	"铁骨蛊": {
		"rank": 1, "dao": "力道", "cost": 10, "kind": "buff", "power": 6, "cd": 6.0,
		"color": Color(0.73, 0.70, 0.63),
		"desc": "以真元凝骨甲，短暂强化自身。",
	},
	"疾风蛊": {
		"rank": 1, "dao": "风道", "cost": 5, "kind": "buff", "power": 8, "cd": 5.0,
		"color": Color(0.66, 0.94, 0.78),
		"desc": "身法如风，短时间内移动速度大增。",
	},
	"水幕蛊": {
		"rank": 1, "dao": "水道", "cost": 7, "kind": "heal", "power": 24, "cd": 5.0,
		"color": Color(0.50, 0.83, 1.00),
		"desc": "化水成幕，恢复自身伤势。",
	},
	"灵犀蛊": {
		"rank": 1, "dao": "智道", "cost": 4, "kind": "scan", "power": 0, "cd": 3.0,
		"color": Color(1.00, 0.88, 0.54),
		"desc": "灵犀一动，感知附近的资源灵机。",
	},
	"春泥蛊": {
		"rank": 2, "dao": "木道", "cost": 12, "kind": "heal", "power": 55, "cd": 6.0,
		"color": Color(0.56, 0.88, 0.48),
		"desc": "春泥护花，大幅回复气血。",
	},
	"血影蛊": {
		"rank": 2, "dao": "血道", "cost": 14, "kind": "attack", "power": 24, "cd": 1.0,
		"color": Color(0.88, 0.29, 0.42),
		"desc": "血影噬敌，威能远胜寻常一转蛊虫。",
	},
	"百步蛊": {
		"rank": 2, "dao": "变化道", "cost": 10, "kind": "dash", "power": 260, "cd": 2.0,
		"color": Color(0.84, 0.65, 1.00),
		"desc": "百步穿林，瞬间前冲一段距离。",
	},
	"金蝉蛊": {
		"rank": 3, "dao": "力道", "cost": 30, "kind": "attack", "power": 70, "cd": 2.0,
		"color": Color(1.00, 0.83, 0.47),
		"desc": "金蝉破壳，一击碎阵，威能惊人。",
	},
}
const GU_ORDER := [
	"月刃蛊", "火蛇蛊", "铁骨蛊", "疾风蛊", "水幕蛊",
	"灵犀蛊", "春泥蛊", "血影蛊", "百步蛊", "金蝉蛊",
]
const STARTER_GU := ["月刃蛊", "铁骨蛊", "疾风蛊", "水幕蛊"]

# ---------------- 养成 ----------------
const FEED_VALUE := {"灵药": 6, "精铁": 5, "兽骨": 8, "血食": 14, "月华露": 26}

# 蛊虫升转消耗，下标 = 当前转数
const RANK_UP_COST := [
	{},
	{"item": "月华露", "count": 2},
	{"item": "月华露", "count": 4},
	{"item": "月华露", "count": 8},
	{"item": "月华露", "count": 14},
]

# 蛊师转数属性，下标 = 转数
const RANK_ESSENCE := [0, 100, 180, 300, 460, 680]
const RANK_HP := [0, 120, 200, 320, 480, 680]

# 蛊师突破消耗，下标 = 当前转数
const RANK_BREAK := [
	{},
	{"stones": 200, "items": {"月华露": 2}},
	{"stones": 600, "items": {"月华露": 4, "兽骨": 6}},
	{"stones": 1800, "items": {"月华露": 8, "血食": 10}},
	{"stones": 5000, "items": {"月华露": 16, "血食": 30}},
]

# ---------------- 妖兽 ----------------
const BEASTS := {
	"铁甲猪": {
		"hp": 70.0, "dmg": 7, "speed": 95.0, "aggro": 260.0,
		"color": Color(0.54, 0.44, 0.37), "drop": {"兽骨": 1, "血食": 1},
	},
	"青纹蛇": {
		"hp": 50.0, "dmg": 11, "speed": 132.0, "aggro": 300.0,
		"color": Color(0.31, 0.60, 0.42), "drop": {"血食": 2},
	},
	"赤目狼": {
		"hp": 1.0, "dmg": 15, "speed": 152.0, "aggro": 340.0,
		"color": Color(0.61, 0.29, 0.23), "drop": {"兽骨": 2, "精铁": 1},
	},
}
const BEAST_ORDER := ["铁甲猪", "青纹蛇", "赤目狼"]

# ---------------- 工具函数 ----------------

static func essence_max(rank: int) -> float:
	return float(RANK_ESSENCE[clampi(rank, 1, RANK_ESSENCE.size() - 1)])

static func hp_max(rank: int) -> float:
	return float(RANK_HP[clampi(rank, 1, RANK_HP.size() - 1)])

## Godot 默认字体不含中日韩字形，这里直接向系统要一份中文字体。
static func make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "微软雅黑", "SimHei", "黑体",
		"Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC",
		"WenQuanYi Micro Hei", "sans-serif",
	])
	f.allow_system_fallback = true
	return f

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = make_font()
	t.default_font_size = 15
	return t
