extends Node2D

const GameConstants = preload("res://scripts/core/GameConstants.gd")
const MassMath = preload("res://scripts/core/MassMath.gd")
const SimWorldScript = preload("res://scripts/core/SimWorld.gd")

var world
var camera: Camera2D
var ui_layer: CanvasLayer
var score_label: Label
var leaderboard_label: Label
var hint_label: Label
var split_button: Button
var eject_button: Button
var font: Font

var tick_accumulator = 0.0
var stars = []
var show_grid = false
var classic_display = false
var paused = false

func _ready() -> void:
	world = SimWorldScript.new()
	world.setup(44771)
	font = ThemeDB.fallback_font
	camera = Camera2D.new()
	camera.name = "GameCamera"
	camera.enabled = true
	camera.position = world.get_player_center(GameConstants.PLAYER_ID)
	add_child(camera)
	_generate_stars()
	_create_ui()
	set_process(true)
	set_process_unhandled_input(true)

func _process(delta: float) -> void:
	_update_player_input()
	if not paused:
		tick_accumulator += delta
		var fixed_dt = 1.0 / GameConstants.SIM_TICK_RATE
		var guard = 0
		while tick_accumulator >= fixed_dt and guard < 8:
			world.step(fixed_dt)
			tick_accumulator -= fixed_dt
			guard += 1
	_update_camera(delta)
	_update_ui()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				world.request_split(GameConstants.PLAYER_ID)
			KEY_E:
				world.request_eject(GameConstants.PLAYER_ID)
			KEY_C:
				classic_display = not classic_display
			KEY_G:
				show_grid = not show_grid
			KEY_P:
				paused = not paused
			KEY_R:
				_force_respawn_player()

func _draw() -> void:
	_draw_backdrop()
	_draw_pellets()
	_draw_ejected()
	_draw_black_holes()
	_draw_blobs()

func _update_player_input() -> void:
	var key_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		key_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		key_dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		key_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		key_dir.y += 1.0
	if key_dir.length_squared() > 0.0:
		world.set_player_input(GameConstants.PLAYER_ID, key_dir.normalized())
		return
	var center = world.get_player_center(GameConstants.PLAYER_ID)
	var mouse_world = get_global_mouse_position()
	var offset = mouse_world - center
	if offset.length() > 18.0:
		world.set_player_input(GameConstants.PLAYER_ID, offset.normalized())
	else:
		world.set_player_input(GameConstants.PLAYER_ID, Vector2.ZERO)

func _update_camera(delta: float) -> void:
	var center = world.get_player_center(GameConstants.PLAYER_ID)
	camera.position = camera.position.lerp(center, 1.0 - exp(-delta * 7.5))
	var zoom = MassMath.camera_zoom(world.get_player_total_mass(GameConstants.PLAYER_ID))
	camera.zoom = camera.zoom.lerp(Vector2(zoom, zoom), 1.0 - exp(-delta * 5.0))

func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "HUD"
	add_child(ui_layer)
	score_label = Label.new()
	score_label.name = "Score"
	score_label.add_theme_font_size_override("font_size", 24)
	score_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	score_label.add_theme_constant_override("shadow_offset_x", 2)
	score_label.add_theme_constant_override("shadow_offset_y", 2)
	ui_layer.add_child(score_label)
	leaderboard_label = Label.new()
	leaderboard_label.name = "Leaderboard"
	leaderboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	leaderboard_label.add_theme_font_size_override("font_size", 24)
	leaderboard_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	leaderboard_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	leaderboard_label.add_theme_constant_override("shadow_offset_x", 2)
	leaderboard_label.add_theme_constant_override("shadow_offset_y", 2)
	ui_layer.add_child(leaderboard_label)
	hint_label = Label.new()
	hint_label.name = "Hint"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.add_theme_color_override("font_color", Color(0.72, 0.84, 0.96, 0.88))
	ui_layer.add_child(hint_label)
	split_button = Button.new()
	split_button.text = "SPLIT"
	split_button.pressed.connect(_on_split_pressed)
	ui_layer.add_child(split_button)
	eject_button = Button.new()
	eject_button.text = "EJECT"
	eject_button.pressed.connect(_on_eject_pressed)
	ui_layer.add_child(eject_button)
	_layout_ui()

func _layout_ui() -> void:
	var size = get_viewport_rect().size
	score_label.position = Vector2(10, 8)
	score_label.size = Vector2(360, 120)
	leaderboard_label.position = Vector2(size.x - 365.0, 8.0)
	leaderboard_label.size = Vector2(355, 170)
	hint_label.position = Vector2(size.x * 0.5 - 370.0, size.y - 34.0)
	hint_label.size = Vector2(740, 28)
	split_button.position = Vector2(size.x - 244.0, size.y - 92.0)
	split_button.size = Vector2(108, 66)
	eject_button.position = Vector2(size.x - 126.0, size.y - 92.0)
	eject_button.size = Vector2(108, 66)

func _update_ui() -> void:
	_layout_ui()
	var mass = int(round(world.get_player_total_mass(GameConstants.PLAYER_ID)))
	var recombine = int(ceil(world.get_player_recombine_remaining(GameConstants.PLAYER_ID)))
	var parts_count = 0
	if world.players.has(GameConstants.PLAYER_ID):
		parts_count = world.players[GameConstants.PLAYER_ID]["parts"].size()
	score_label.text = "Level: 1\nScore: %d\nRecombine: %d\nParts: %d" % [mass, recombine, parts_count]
	var lines = []
	for row in world.get_leaderboard(6):
		lines.append("%s: %d" % [row["name"], row["score"]])
	leaderboard_label.text = "\n".join(lines)
	hint_label.text = "Mouse/WASD move  Space split  E eject  C classic display  G grid  P pause"
	split_button.disabled = not _player_has_mass(GameConstants.SPLIT_MIN_MASS)
	eject_button.disabled = not _player_has_mass(GameConstants.EJECT_MIN_MASS)

func _player_has_mass(min_mass: float) -> bool:
	if not world.players.has(GameConstants.PLAYER_ID):
		return false
	for part_id in world.players[GameConstants.PLAYER_ID]["parts"]:
		if world.parts.has(part_id) and world.parts[part_id]["mass"] >= min_mass:
			return true
	return false

func _draw_backdrop() -> void:
	var rect = Rect2(Vector2.ZERO, GameConstants.WORLD_SIZE)
	draw_rect(rect, Color(0.012, 0.016, 0.024), true)
	for star in stars:
		draw_circle(star["pos"], star["radius"], star["color"])
	if show_grid:
		var grid_color = Color(0.05, 0.55, 0.72, 0.22)
		for x in range(0, int(GameConstants.WORLD_SIZE.x) + 1, 220):
			draw_line(Vector2(x, 0), Vector2(x, GameConstants.WORLD_SIZE.y), grid_color, 1.0)
		for y in range(0, int(GameConstants.WORLD_SIZE.y) + 1, 220):
			draw_line(Vector2(0, y), Vector2(GameConstants.WORLD_SIZE.x, y), grid_color, 1.0)
	draw_rect(rect, Color(0.0, 0.82, 0.92, 0.72), false, 3.0)

func _draw_pellets() -> void:
	for pellet_id in world.pellets.keys():
		var pellet = world.pellets[pellet_id]
		var radius = MassMath.pellet_radius(pellet["mass"])
		draw_circle(pellet["pos"], radius + 1.4, Color(1.0, 1.0, 1.0, 0.10))
		draw_circle(pellet["pos"], radius, pellet["color"])

func _draw_ejected() -> void:
	for id in world.ejected.keys():
		var pellet = world.ejected[id]
		var radius = MassMath.pellet_radius(pellet["mass"]) + 3.0
		draw_circle(pellet["pos"], radius + 4.0, Color(pellet["color"].r, pellet["color"].g, pellet["color"].b, 0.16))
		draw_circle(pellet["pos"], radius, pellet["color"])

func _draw_black_holes() -> void:
	for id in world.holes.keys():
		var hole = world.holes[id]
		var pos: Vector2 = hole["pos"]
		var radius: float = hole["radius"]
		var blue = hole["kind"] == "blue"
		var base = Color(0.20, 0.88, 1.0, 0.94) if blue else Color(0.70, 0.70, 0.72, 0.92)
		var core = Color(0.03, 0.04, 0.05, 1.0) if not blue else Color(0.05, 0.22, 0.28, 1.0)
		draw_circle(pos, radius * 1.42, Color(base.r, base.g, base.b, 0.10))
		draw_circle(pos, radius * 1.08, Color(base.r, base.g, base.b, 0.22))
		draw_circle(pos, radius * 0.86, core)
		for i in range(5):
			var r = radius * (0.44 + float(i) * 0.11)
			var a = hole["phase"] + float(i) * 0.72
			draw_arc(pos, r, a, a + PI * 1.24, 34, Color(base.r, base.g, base.b, 0.54 - float(i) * 0.06), 4.0)
		draw_arc(pos, radius * 0.98, 0.0, TAU, 72, Color(0.88, 0.96, 1.0, 0.46), 2.0)

func _draw_blobs() -> void:
	var ids = world.parts.keys()
	ids.sort_custom(func(a, b): return world.parts[a]["mass"] < world.parts[b]["mass"])
	for part_id in ids:
		if world.parts.has(part_id):
			_draw_blob(world.parts[part_id])

func _draw_blob(part: Dictionary) -> void:
	var pos: Vector2 = part["pos"]
	var mass: float = part["mass"]
	var radius = MassMath.mass_to_radius(mass)
	var owner_id: int = part["owner_id"]
	var color: Color = part["color"]
	draw_circle(pos, radius * 1.22, Color(color.r, color.g, color.b, 0.13))
	draw_circle(pos, radius * 1.10, Color(1.0, 1.0, 1.0, 0.10))
	var fill = color.darkened(0.10)
	draw_circle(pos, radius, fill)
	if not classic_display:
		_draw_blob_pattern(pos, radius, color, owner_id)
	draw_arc(pos, radius, 0.0, TAU, 96, Color(0.92, 0.94, 1.0, 0.72), max(2.0, radius * 0.035))
	if not classic_display:
		var name = world.players[owner_id]["name"] if world.players.has(owner_id) else "Blob"
		var name_size = int(clamp(radius * 0.34, 13.0, 34.0))
		var score_size = int(clamp(radius * 0.24, 11.0, 26.0))
		var width = radius * 2.4
		draw_string(font, pos + Vector2(-width * 0.5, -name_size * 0.25), name, HORIZONTAL_ALIGNMENT_CENTER, width, name_size, Color.WHITE)
		draw_string(font, pos + Vector2(-width * 0.5, score_size * 1.05), str(int(round(mass))), HORIZONTAL_ALIGNMENT_CENTER, width, score_size, Color(0.44, 0.78, 1.0))

func _draw_blob_pattern(pos: Vector2, radius: float, color: Color, owner_id: int) -> void:
	var accent = color.lerp(Color.WHITE, 0.38)
	var dark = color.darkened(0.42)
	if owner_id % 3 == 0:
		for i in range(4):
			var angle = float(i) * TAU / 4.0 + world.time * 0.12
			var p = pos + Vector2.from_angle(angle) * radius * 0.34
			draw_circle(p, radius * 0.19, Color(accent.r, accent.g, accent.b, 0.34))
	elif owner_id % 3 == 1:
		for i in range(5):
			var angle = float(i) * TAU / 5.0 - world.time * 0.08
			draw_arc(pos, radius * (0.25 + float(i) * 0.11), angle, angle + PI * 0.9, 28, Color(accent.r, accent.g, accent.b, 0.30), max(2.0, radius * 0.028))
	else:
		draw_circle(pos + Vector2(-radius * 0.22, -radius * 0.12), radius * 0.28, Color(dark.r, dark.g, dark.b, 0.36))
		draw_circle(pos + Vector2(radius * 0.18, radius * 0.18), radius * 0.22, Color(accent.r, accent.g, accent.b, 0.24))

func _generate_stars() -> void:
	var star_rng = RandomNumberGenerator.new()
	star_rng.seed = 81991
	stars.clear()
	for i in range(760):
		var color = Color(0.72, 0.82, 0.95, star_rng.randf_range(0.30, 0.88))
		if i % 13 == 0:
			color = Color(0.40, 0.92, 1.0, 0.75)
		elif i % 17 == 0:
			color = Color(1.0, 0.75, 0.42, 0.72)
		stars.append({
			"pos": Vector2(star_rng.randf_range(0.0, GameConstants.WORLD_SIZE.x), star_rng.randf_range(0.0, GameConstants.WORLD_SIZE.y)),
			"radius": star_rng.randf_range(1.0, 3.1),
			"color": color
		})

func _on_split_pressed() -> void:
	world.request_split(GameConstants.PLAYER_ID)

func _on_eject_pressed() -> void:
	world.request_eject(GameConstants.PLAYER_ID)

func _force_respawn_player() -> void:
	if not world.players.has(GameConstants.PLAYER_ID):
		return
	for part_id in world.players[GameConstants.PLAYER_ID]["parts"].duplicate():
		world.parts.erase(part_id)
	world.players[GameConstants.PLAYER_ID]["parts"].clear()
	world.players[GameConstants.PLAYER_ID]["alive"] = false
	world.players[GameConstants.PLAYER_ID]["respawn_timer"] = 0.05
