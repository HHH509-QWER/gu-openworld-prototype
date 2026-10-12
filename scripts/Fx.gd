class_name FxLayer
extends Node2D
## 极简特效层：扩散圆环 + 飘字。主机广播 → 所有端播放。

var items: Array = []
var font: Font = null


func ring(pos: Vector2, color: Color, radius: float, life := 0.34) -> void:
	items.append({"type": "ring", "pos": pos, "color": color, "t": 0.0, "life": life, "radius": radius})
	queue_redraw()


func flash_text(pos: Vector2, text: String, color: Color) -> void:
	items.append({"type": "text", "pos": pos, "color": color, "t": 0.0, "life": 0.9, "text": text})
	queue_redraw()


func _process(delta: float) -> void:
	if items.is_empty():
		return
	var keep: Array = []
	for it in items:
		it["t"] = float(it["t"]) + delta
		if float(it["t"]) < float(it["life"]):
			keep.append(it)
	items = keep
	queue_redraw()


func _draw() -> void:
	for it in items:
		var k: float = clampf(float(it["t"]) / maxf(float(it["life"]), 0.001), 0.0, 1.0)
		var c: Color = it["color"]
		if it["type"] == "ring":
			var r: float = float(it["radius"]) * (0.35 + 0.75 * k)
			draw_arc(it["pos"], r, 0.0, TAU, 36, Color(c.r, c.g, c.b, 1.0 - k), 3.0)
		elif font != null:
			draw_string(font, it["pos"] + Vector2(-60.0, -32.0 * k), String(it["text"]),
					HORIZONTAL_ALIGNMENT_CENTER, 120.0, 15, Color(c.r, c.g, c.b, 1.0 - k))
