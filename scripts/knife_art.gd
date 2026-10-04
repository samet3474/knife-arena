class_name KnifeArt
extends RefCounted
## Bıçak çizimi. Bıçağın ucu rot = 0 iken -Y yönünü gösterir.
## kind: GameData.KNIVES içindeki bıçak türünün sırası.

const SPRITE_HEIGHT := 42.0


static func draw(ci: CanvasItem, pos: Vector2, rot: float, s: float = 1.0, kind: int = 0, glow := true) -> void:
	var info: Dictionary = GameData.KNIVES[kind]
	var glow_col: Color = info["glow"]
	if glow and glow_col.a > 0.0:
		var gs := 30.0 * s
		ci.draw_texture_rect(GameData.glow_tex(), Rect2(pos - Vector2(gs, gs), Vector2(gs, gs) * 2.0), false, glow_col)
	var t := GameData.tex(info["tex"])
	var tint := Color.WHITE
	if t == null:
		t = GameData.tex("knife")
		tint = info["color"]
	elif info["tex"] == "knife":
		tint = info["color"]
	if t != null:
		var sc := SPRITE_HEIGHT / t.get_height() * s
		ci.draw_set_transform(pos, rot, Vector2(sc, sc))
		ci.draw_texture(t, -t.get_size() / 2.0, tint)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	ci.draw_set_transform(pos, rot, Vector2(s, s))
	var blade := PackedVector2Array([
		Vector2(0, -18), Vector2(4.5, -6), Vector2(3.5, 4), Vector2(-3.5, 4), Vector2(-4.5, -6)
	])
	ci.draw_colored_polygon(blade, Color(0.9, 0.92, 0.97) * tint)
	ci.draw_rect(Rect2(-6, 4, 12, 3), Color(0.3, 0.3, 0.34))
	ci.draw_rect(Rect2(-2.5, 7, 5, 9), Color(0.5, 0.3, 0.15))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
