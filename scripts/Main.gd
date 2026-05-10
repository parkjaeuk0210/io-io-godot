extends Node2D

const GameConstants = preload("res://scripts/core/GameConstants.gd")
const MassMath = preload("res://scripts/core/MassMath.gd")
const SimWorldScript = preload("res://scripts/core/SimWorld.gd")

const DRAW_CULL_MARGIN = 180.0
const SOFT_CIRCLE_TEXTURE_SIZE = 64
const UI_UPDATE_INTERVAL = 0.125

var world
var camera: Camera2D
var ui_layer: CanvasLayer
var score_label: Label
var leaderboard_label: Label
var hint_label: Label
var split_button: Button
var eject_button: Button
var soft_circle_texture: Texture2D
var font: Font

var tick_accumulator = 0.0
var ui_update_accumulator = 0.0
var last_viewport_size = Vector2.ZERO
var stars = []
var show_grid = false
var classic_display = false
var paused = false

func _ready() -> void:
	world = SimWorldScript.new()
	world.setup(44771)
	font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	soft_circle_texture = _create_soft_circle_texture()
	camera = Camera2D.new()
	camera.name = "GameCamera"
	camera.enabled = true
	var initial_zoom = MassMath.camera_zoom(world.get_player_total_mass(GameConstants.PLAYER_ID))
	camera.zoom = Vector2(initial_zoom, initial_zoom)
	camera.position = _clamp_camera_center(world.get_player_center(GameConstants.PLAYER_ID), camera.zoom)
	add_child(camera)
	_generate_stars()
	_create_ui()
	_update_ui(0.0, true)
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
	_update_ui(delta)
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
	var visible_rect = _camera_world_rect(DRAW_CULL_MARGIN)
	_draw_backdrop(visible_rect)
	_draw_pellets(visible_rect)
	_draw_debris(visible_rect)
	_draw_ejected(visible_rect)
	_draw_black_holes(visible_rect)
	_draw_blobs(visible_rect)

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
	var mouse_world = get_global_mouse_position()
	world.set_player_target(GameConstants.PLAYER_ID, mouse_world)

func _update_camera(delta: float) -> void:
	var center = world.get_player_center(GameConstants.PLAYER_ID)
	var zoom = MassMath.camera_zoom(world.get_player_total_mass(GameConstants.PLAYER_ID))
	camera.zoom = camera.zoom.lerp(Vector2(zoom, zoom), 1.0 - exp(-delta * 5.0))
	var clamped_center = _clamp_camera_center(center, camera.zoom)
	camera.position = camera.position.lerp(clamped_center, 1.0 - exp(-delta * 7.5))

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
	hint_label.text = "Mouse/WASD move  Space split  E eject  C classic display  G grid  P pause"
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

func _update_ui(delta: float, force = false) -> void:
	var viewport_size = get_viewport_rect().size
	if force or viewport_size != last_viewport_size:
		_layout_ui()
		last_viewport_size = viewport_size
	ui_update_accumulator += delta
	if not force and ui_update_accumulator < UI_UPDATE_INTERVAL:
		return
	ui_update_accumulator = 0.0
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
	split_button.disabled = not _player_has_mass(GameConstants.SPLIT_MIN_MASS)
	eject_button.disabled = not _player_has_mass(GameConstants.EJECT_MIN_MASS)

func _player_has_mass(min_mass: float) -> bool:
	if not world.players.has(GameConstants.PLAYER_ID):
		return false
	for part_id in world.players[GameConstants.PLAYER_ID]["parts"]:
		if world.parts.has(part_id) and world.parts[part_id]["mass"] >= min_mass:
			return true
	return false

func _draw_backdrop(visible_rect: Rect2) -> void:
	draw_rect(visible_rect, Color(0.012, 0.016, 0.024), true)
	var rect = Rect2(Vector2.ZERO, GameConstants.WORLD_SIZE)
	draw_rect(rect, Color(0.012, 0.016, 0.024), true)
	for star in stars:
		if _circle_visible(visible_rect, star["pos"], star["radius"]):
			_draw_soft_circle(star["pos"], star["radius"] * 1.35, star["color"])
	if show_grid:
		var grid_color = Color(0.05, 0.55, 0.72, 0.22)
		var grid_step = 220
		var start_x = max(0, floori(visible_rect.position.x / float(grid_step)) * grid_step)
		var end_x = min(int(GameConstants.WORLD_SIZE.x), ceili(visible_rect.end.x / float(grid_step)) * grid_step)
		var start_y = max(0, floori(visible_rect.position.y / float(grid_step)) * grid_step)
		var end_y = min(int(GameConstants.WORLD_SIZE.y), ceili(visible_rect.end.y / float(grid_step)) * grid_step)
		for x in range(start_x, end_x + 1, grid_step):
			draw_line(Vector2(x, 0), Vector2(x, GameConstants.WORLD_SIZE.y), grid_color, 1.0)
		for y in range(start_y, end_y + 1, grid_step):
			draw_line(Vector2(0, y), Vector2(GameConstants.WORLD_SIZE.x, y), grid_color, 1.0)
	draw_rect(rect, Color(0.0, 0.82, 0.92, 0.72), false, 3.0)

func _draw_pellets(visible_rect: Rect2) -> void:
	for pellet_id in world.pellets.keys():
		var pellet = world.pellets[pellet_id]
		var radius = MassMath.pellet_radius(pellet["mass"])
		if not _circle_visible(visible_rect, pellet["pos"], radius + 2.0):
			continue
		_draw_soft_circle(pellet["pos"], radius + 1.6, pellet["color"])

func _draw_debris(visible_rect: Rect2) -> void:
	for id in world.debris.keys():
		var pellet = world.debris[id]
		var radius = MassMath.pellet_radius(pellet["mass"]) + 2.2
		if not _circle_visible(visible_rect, pellet["pos"], radius + 4.0):
			continue
		_draw_soft_circle(pellet["pos"], radius + 3.2, pellet["color"])

func _draw_ejected(visible_rect: Rect2) -> void:
	for id in world.ejected.keys():
		var pellet = world.ejected[id]
		var radius = MassMath.pellet_radius(pellet["mass"]) + 3.0
		if not _circle_visible(visible_rect, pellet["pos"], radius + 4.0):
			continue
		_draw_soft_circle(pellet["pos"], radius + 4.0, pellet["color"])

func _draw_black_holes(visible_rect: Rect2) -> void:
	for id in world.holes.keys():
		var hole = world.holes[id]
		var pos: Vector2 = hole["pos"]
		var radius: float = hole["radius"]
		if not _circle_visible(visible_rect, pos, radius * 1.45):
			continue
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

func _draw_blobs(visible_rect: Rect2) -> void:
	var ids = world.parts.keys()
	ids.sort_custom(func(a, b): return world.parts[a]["mass"] < world.parts[b]["mass"])
	for part_id in ids:
		if world.parts.has(part_id):
			var part = world.parts[part_id]
			var radius = MassMath.mass_to_radius(part["mass"])
			if _circle_visible(visible_rect, part["pos"], radius * 1.25):
				_draw_blob(part)

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

func _camera_world_rect(margin: float) -> Rect2:
	var viewport_size = get_viewport_rect().size
	var zoom = Vector2.ONE
	var center = GameConstants.WORLD_SIZE * 0.5
	if camera != null:
		zoom = camera.zoom
		center = camera.position
	var visible_size = Vector2(
		viewport_size.x / max(zoom.x, 0.001),
		viewport_size.y / max(zoom.y, 0.001)
	)
	var margin_vec = Vector2(margin, margin)
	return Rect2(center - visible_size * 0.5 - margin_vec, visible_size + margin_vec * 2.0)

func _clamp_camera_center(center: Vector2, zoom: Vector2) -> Vector2:
	var viewport_size = get_viewport_rect().size
	var visible_size = Vector2(
		viewport_size.x / max(zoom.x, 0.001),
		viewport_size.y / max(zoom.y, 0.001)
	)
	var clamped = center
	if visible_size.x >= GameConstants.WORLD_SIZE.x:
		clamped.x = GameConstants.WORLD_SIZE.x * 0.5
	else:
		var half_width = visible_size.x * 0.5
		clamped.x = clamp(center.x, half_width, GameConstants.WORLD_SIZE.x - half_width)
	if visible_size.y >= GameConstants.WORLD_SIZE.y:
		clamped.y = GameConstants.WORLD_SIZE.y * 0.5
	else:
		var half_height = visible_size.y * 0.5
		clamped.y = clamp(center.y, half_height, GameConstants.WORLD_SIZE.y - half_height)
	return clamped

func _circle_visible(rect: Rect2, pos: Vector2, radius: float) -> bool:
	var diameter = radius * 2.0
	return rect.intersects(Rect2(pos - Vector2(radius, radius), Vector2(diameter, diameter)))

func _draw_soft_circle(pos: Vector2, radius: float, color: Color) -> void:
	var diameter = radius * 2.0
	draw_texture_rect(soft_circle_texture, Rect2(pos - Vector2(radius, radius), Vector2(diameter, diameter)), false, color)

func _create_soft_circle_texture() -> Texture2D:
	var image = Image.create(SOFT_CIRCLE_TEXTURE_SIZE, SOFT_CIRCLE_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center = Vector2(SOFT_CIRCLE_TEXTURE_SIZE - 1, SOFT_CIRCLE_TEXTURE_SIZE - 1) * 0.5
	var outer_radius = float(SOFT_CIRCLE_TEXTURE_SIZE - 2) * 0.5
	var core_fraction = 0.74
	for y in range(SOFT_CIRCLE_TEXTURE_SIZE):
		for x in range(SOFT_CIRCLE_TEXTURE_SIZE):
			var dist = Vector2(x, y).distance_to(center)
			var t = dist / outer_radius
			var alpha = 0.0
			if t <= core_fraction:
				alpha = 1.0
			elif t <= 1.0:
				var fade = 1.0 - ((t - core_fraction) / (1.0 - core_fraction))
				alpha = pow(fade, 1.8) * 0.38
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)

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
