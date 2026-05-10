extends RefCounted
class_name SimWorld

const GameConstants = preload("res://scripts/core/GameConstants.gd")
const MassMath = preload("res://scripts/core/MassMath.gd")
const SpatialHashScript = preload("res://scripts/core/SpatialHash.gd")

var rng = RandomNumberGenerator.new()
var players = {}
var parts = {}
var pellets = {}
var ejected = {}
var holes = {}
var time = 0.0

var _next_entity_id = 1000
var _pellet_hash
var _ejected_hash
var _hole_hash
var _part_hash

func _init() -> void:
	_pellet_hash = SpatialHashScript.new(GameConstants.PELLET_CELL)
	_ejected_hash = SpatialHashScript.new(GameConstants.PELLET_CELL)
	_hole_hash = SpatialHashScript.new(GameConstants.PART_COLLISION_CELL)
	_part_hash = SpatialHashScript.new(GameConstants.PART_COLLISION_CELL)

func setup(seed_value = 99173) -> void:
	rng.seed = seed_value
	players.clear()
	parts.clear()
	pellets.clear()
	ejected.clear()
	holes.clear()
	time = 0.0
	_next_entity_id = 1000
	for i in range(GameConstants.PELLET_COUNT):
		_spawn_pellet()
	for i in range(GameConstants.BLACK_HOLE_COUNT):
		_spawn_black_hole(i)
	spawn_player(GameConstants.PLAYER_ID, "You", false, GameConstants.INITIAL_PLAYER_MASS)
	for i in range(GameConstants.BOT_COUNT):
		var bot_mass = rng.randf_range(GameConstants.INITIAL_BOT_MASS_MIN, GameConstants.INITIAL_BOT_MASS_MAX)
		spawn_player(20 + i, _bot_name(i), true, bot_mass)

func spawn_player(owner_id: int, player_name: String, is_bot: bool, mass = -1.0) -> void:
	var color = GameConstants.COLORS[abs(owner_id) % GameConstants.COLORS.size()]
	var spawn_pos = _random_arena_pos(240.0)
	var initial_dir = _random_dir()
	players[owner_id] = {
		"id": owner_id,
		"name": player_name,
		"color": color,
		"parts": [],
		"input_dir": initial_dir,
		"move_mode": "target",
		"target_pos": _clamp_to_arena(spawn_pos + initial_dir * GameConstants.DIRECTION_TARGET_LOOKAHEAD),
		"last_input_dir": initial_dir,
		"is_bot": is_bot,
		"alive": true,
		"respawn_timer": 0.0,
		"eject_cooldown": 0.0,
		"bot_timer": rng.randf_range(0.1, 0.8)
	}
	var spawn_mass = mass if mass > 0.0 else GameConstants.INITIAL_PLAYER_MASS
	_add_part(owner_id, spawn_pos, spawn_mass, Vector2.ZERO, 0.0)

func step(dt: float) -> void:
	time += dt
	_update_respawns(dt)
	_update_bots(dt)
	_update_parts(dt)
	_update_ejected(dt)
	_update_black_holes(dt)
	_resolve_same_owner_spacing(dt)
	_rebuild_hashes()
	_resolve_environment_consumption()
	_resolve_part_consumption()
	_resolve_recombine()

func set_player_input(owner_id: int, direction: Vector2) -> void:
	if not players.has(owner_id):
		return
	var player = players[owner_id]
	if direction.length_squared() <= 0.0001:
		player["input_dir"] = Vector2.ZERO
		player["move_mode"] = "idle"
		return
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	player["input_dir"] = direction
	player["last_input_dir"] = direction
	player["target_pos"] = _clamp_to_arena(get_player_center(owner_id) + direction * GameConstants.DIRECTION_TARGET_LOOKAHEAD)
	player["move_mode"] = "target"

func set_player_target(owner_id: int, target_pos: Vector2) -> void:
	if not players.has(owner_id):
		return
	var player = players[owner_id]
	target_pos = _clamp_to_arena(target_pos)
	var offset = target_pos - get_player_center(owner_id)
	if offset.length_squared() > GameConstants.INPUT_DEADZONE * GameConstants.INPUT_DEADZONE:
		var direction = offset.normalized()
		player["input_dir"] = direction
		player["last_input_dir"] = direction
	else:
		player["input_dir"] = Vector2.ZERO
	player["target_pos"] = target_pos
	player["move_mode"] = "target"

func request_split(owner_id: int) -> void:
	if not players.has(owner_id) or not players[owner_id]["alive"]:
		return
	var player = players[owner_id]
	var candidates: Array = player["parts"].duplicate()
	candidates.sort_custom(func(a, b): return parts.get(a, {}).get("mass", 0.0) > parts.get(b, {}).get("mass", 0.0))
	for part_id in candidates:
		if player["parts"].size() >= GameConstants.BASIC_SPLIT_CAP:
			break
		if parts.has(part_id) and parts[part_id]["mass"] >= GameConstants.SPLIT_MIN_MASS:
			var direction = _action_direction_for_part(player, parts[part_id])
			_split_part(part_id, direction)

func request_eject(owner_id: int) -> void:
	if not players.has(owner_id) or not players[owner_id]["alive"]:
		return
	if players[owner_id]["eject_cooldown"] > 0.0:
		return
	players[owner_id]["eject_cooldown"] = GameConstants.EJECT_COOLDOWN
	var player = players[owner_id]
	for part_id in player["parts"].duplicate():
		if not parts.has(part_id):
			continue
		var part = parts[part_id]
		if part["mass"] < GameConstants.EJECT_MIN_MASS:
			continue
		var loss = MassMath.ejected_source_loss(part["mass"])
		if part["mass"] - loss < GameConstants.NATURAL_DECAY_MIN_MASS:
			continue
		part["mass"] -= loss
		var direction = _action_direction_for_part(player, part)
		var pellet_mass = loss * GameConstants.EJECT_PELLET_GAIN_RATIO
		var radius = MassMath.mass_to_radius(part["mass"])
		var pos: Vector2 = part["pos"] + direction.normalized() * (radius + 18.0)
		var id = _next_id()
		ejected[id] = {
			"id": id,
			"owner_id": owner_id,
			"pos": _clamp_to_arena(pos),
			"vel": direction.normalized() * GameConstants.EJECT_IMPULSE + part["vel"] * 0.25,
			"mass": pellet_mass,
			"age": 0.0,
			"life": GameConstants.EJECT_LIFETIME,
			"color": part["color"].lerp(Color.WHITE, 0.35)
		}

func get_player_center(owner_id: int) -> Vector2:
	if not players.has(owner_id):
		return GameConstants.WORLD_SIZE * 0.5
	var total = 0.0
	var center = Vector2.ZERO
	for part_id in players[owner_id]["parts"]:
		if parts.has(part_id):
			var mass: float = parts[part_id]["mass"]
			center += parts[part_id]["pos"] * mass
			total += mass
	if total <= 0.0:
		return GameConstants.WORLD_SIZE * 0.5
	return center / total

func get_player_total_mass(owner_id: int) -> float:
	if not players.has(owner_id):
		return 0.0
	var total = 0.0
	for part_id in players[owner_id]["parts"]:
		if parts.has(part_id):
			total += parts[part_id]["mass"]
	return total

func get_largest_part_mass(owner_id: int) -> float:
	if not players.has(owner_id):
		return 0.0
	var largest = 0.0
	for part_id in players[owner_id]["parts"]:
		if parts.has(part_id):
			largest = max(largest, parts[part_id]["mass"])
	return largest

func get_player_recombine_remaining(owner_id: int) -> float:
	if not players.has(owner_id):
		return 0.0
	var remaining = 0.0
	for part_id in players[owner_id]["parts"]:
		if parts.has(part_id):
			remaining = max(remaining, parts[part_id]["merge_time"])
	return remaining

func get_leaderboard(limit = 5) -> Array:
	var rows = []
	for owner_id in players.keys():
		if players[owner_id]["parts"].is_empty():
			continue
		rows.append({
			"id": owner_id,
			"name": players[owner_id]["name"],
			"score": int(round(get_player_total_mass(owner_id)))
		})
	rows.sort_custom(func(a, b): return a["score"] > b["score"])
	return rows.slice(0, limit)

func _update_respawns(dt: float) -> void:
	for owner_id in players.keys():
		if players[owner_id]["eject_cooldown"] > 0.0:
			players[owner_id]["eject_cooldown"] = max(0.0, players[owner_id]["eject_cooldown"] - dt)
		if players[owner_id]["alive"]:
			continue
		players[owner_id]["respawn_timer"] -= dt
		if players[owner_id]["respawn_timer"] <= 0.0:
			players[owner_id]["alive"] = true
			var mass = GameConstants.INITIAL_PLAYER_MASS
			if players[owner_id]["is_bot"]:
				mass = rng.randf_range(GameConstants.INITIAL_BOT_MASS_MIN, GameConstants.INITIAL_BOT_MASS_MAX)
			_add_part(owner_id, _random_arena_pos(240.0), mass, Vector2.ZERO, 0.0)

func _update_bots(dt: float) -> void:
	for owner_id in players.keys():
		var player = players[owner_id]
		if not player["is_bot"] or not player["alive"]:
			continue
		player["bot_timer"] -= dt
		if player["bot_timer"] > 0.0:
			continue
		player["bot_timer"] = rng.randf_range(GameConstants.BOT_DECISION_SECONDS_MIN, GameConstants.BOT_DECISION_SECONDS_MAX)
		var center = get_player_center(owner_id)
		var largest = get_largest_part_mass(owner_id)
		var threat = Vector2.ZERO
		var prey = Vector2.ZERO
		var prey_distance = INF
		for other_id in parts.keys():
			var other = parts[other_id]
			if other["owner_id"] == owner_id:
				continue
			var offset: Vector2 = other["pos"] - center
			var dist = max(offset.length(), 1.0)
			if other["mass"] > largest * 1.08 and dist < 620.0:
				threat -= offset.normalized() * (620.0 - dist)
			elif largest > other["mass"] * GameConstants.CONSUME_MASS_RATIO and dist < prey_distance:
				prey = offset
				prey_distance = dist
		if threat.length_squared() > 1.0:
			set_player_input(owner_id, threat.normalized())
		elif prey_distance < 920.0:
			set_player_input(owner_id, prey.normalized())
			if prey_distance < 360.0 and largest >= GameConstants.SPLIT_MIN_MASS * 2.0 and rng.randf() < 0.22:
				request_split(owner_id)
		else:
			set_player_input(owner_id, _direction_to_nearest_pellet(center))
		if rng.randf() < 0.035:
			request_eject(owner_id)

func _update_parts(dt: float) -> void:
	for part_id in parts.keys():
		if not parts.has(part_id):
			continue
		var part = parts[part_id]
		var owner_id: int = part["owner_id"]
		var input_dir = Vector2.ZERO
		if players.has(owner_id):
			input_dir = _movement_direction_for_part(players[owner_id], part)
		var desired = input_dir * MassMath.mass_to_speed(part["mass"])
		part["vel"] = part["vel"].move_toward(desired, 710.0 * dt)
		part["pos"] += part["vel"] * dt
		part["pos"] = _bounce_inside_arena(part["pos"], part)
		part["merge_time"] = max(0.0, part["merge_time"] - dt)
		part["hole_cd"] = max(0.0, part["hole_cd"] - dt)
		part["age"] += dt
		if part["mass"] > GameConstants.NATURAL_DECAY_MIN_MASS:
			part["mass"] = max(GameConstants.NATURAL_DECAY_MIN_MASS, part["mass"] * (1.0 - GameConstants.NATURAL_DECAY_PER_SECOND * dt))

func _update_ejected(dt: float) -> void:
	for id in ejected.keys():
		if not ejected.has(id):
			continue
		var pellet = ejected[id]
		pellet["pos"] += pellet["vel"] * dt
		pellet["vel"] = pellet["vel"].move_toward(Vector2.ZERO, 260.0 * dt)
		pellet["age"] += dt
		pellet["life"] -= dt
		if pellet["life"] <= 0.0:
			ejected.erase(id)
			continue
		var radius = MassMath.pellet_radius(pellet["mass"])
		var pos: Vector2 = pellet["pos"]
		if pos.x < radius or pos.x > GameConstants.WORLD_SIZE.x - radius:
			pellet["vel"].x *= -0.45
		if pos.y < radius or pos.y > GameConstants.WORLD_SIZE.y - radius:
			pellet["vel"].y *= -0.45
		pellet["pos"] = _clamp_to_arena(pos, radius)

func _update_black_holes(dt: float) -> void:
	for id in holes.keys():
		var hole = holes[id]
		hole["phase"] += dt * hole["spin"]
		hole["pos"] += hole["vel"] * dt
		hole["vel"] = hole["vel"].move_toward(hole["base_vel"], 12.0 * dt)
		var radius: float = hole["radius"]
		var pos: Vector2 = hole["pos"]
		if pos.x < radius or pos.x > GameConstants.WORLD_SIZE.x - radius:
			hole["vel"].x *= -1.0
			hole["base_vel"].x *= -1.0
		if pos.y < radius or pos.y > GameConstants.WORLD_SIZE.y - radius:
			hole["vel"].y *= -1.0
			hole["base_vel"].y *= -1.0
		hole["pos"] = _clamp_to_arena(pos, radius)

func _resolve_same_owner_spacing(dt: float) -> void:
	for owner_id in players.keys():
		var list: Array = players[owner_id]["parts"]
		for i in range(list.size()):
			if not parts.has(list[i]):
				continue
			for j in range(i + 1, list.size()):
				if not parts.has(list[j]):
					continue
				var a = parts[list[i]]
				var b = parts[list[j]]
				if a["merge_time"] <= 0.0 and b["merge_time"] <= 0.0:
					continue
				var delta: Vector2 = b["pos"] - a["pos"]
				var dist = max(delta.length(), 1.0)
				var min_dist = (MassMath.mass_to_radius(a["mass"]) + MassMath.mass_to_radius(b["mass"])) * 0.68
				if dist < min_dist:
					var push = delta.normalized() * (min_dist - dist) * GameConstants.SAME_OWNER_REPEL * dt / max(min_dist, 1.0)
					a["pos"] -= push
					b["pos"] += push

func _rebuild_hashes() -> void:
	_pellet_hash.clear()
	for id in pellets.keys():
		_pellet_hash.insert(id, pellets[id]["pos"])
	_ejected_hash.clear()
	for id in ejected.keys():
		_ejected_hash.insert(id, ejected[id]["pos"])
	_hole_hash.clear()
	for id in holes.keys():
		_hole_hash.insert(id, holes[id]["pos"])
	_part_hash.clear()
	for id in parts.keys():
		_part_hash.insert(id, parts[id]["pos"])

func _resolve_environment_consumption() -> void:
	for part_id in parts.keys():
		if not parts.has(part_id):
			continue
		var part = parts[part_id]
		var radius = MassMath.mass_to_radius(part["mass"])
		for pellet_id in _pellet_hash.query(part["pos"], radius + 22.0):
			if not pellets.has(pellet_id):
				continue
			var pellet = pellets[pellet_id]
			if part["pos"].distance_to(pellet["pos"]) <= radius + MassMath.pellet_radius(pellet["mass"]) * 0.45:
				part["mass"] += pellet["mass"]
				pellets.erase(pellet_id)
				_spawn_pellet()
		for eject_id in _ejected_hash.query(part["pos"], radius + 26.0):
			if not ejected.has(eject_id):
				continue
			var pellet = ejected[eject_id]
			if pellet["owner_id"] == part["owner_id"] and pellet["age"] < GameConstants.EJECT_PICKUP_DELAY:
				continue
			if part["pos"].distance_to(pellet["pos"]) <= radius + MassMath.pellet_radius(pellet["mass"]) * 0.55:
				part["mass"] += pellet["mass"]
				ejected.erase(eject_id)
		for hole_id in _hole_hash.query(part["pos"], radius + GameConstants.BLUE_BLACK_HOLE_RADIUS + 12.0):
			if not holes.has(hole_id) or not parts.has(part_id):
				continue
			_resolve_part_hole(part_id, hole_id)
	for eject_id in ejected.keys():
		if not ejected.has(eject_id):
			continue
		var pellet = ejected[eject_id]
		var pellet_radius = MassMath.pellet_radius(pellet["mass"])
		for hole_id in _hole_hash.query(pellet["pos"], pellet_radius + GameConstants.BLUE_BLACK_HOLE_RADIUS):
			if not holes.has(hole_id) or not ejected.has(eject_id):
				continue
			var hole = holes[hole_id]
			if pellet["pos"].distance_to(hole["pos"]) <= hole["radius"] + pellet_radius:
				hole["vel"] += pellet["vel"].normalized() * pellet["mass"] * GameConstants.BLACK_HOLE_PUSH_SCALE
				ejected.erase(eject_id)

func _resolve_part_consumption() -> void:
	var checked = {}
	for part_id in parts.keys():
		if not parts.has(part_id):
			continue
		var part = parts[part_id]
		var query_radius = MassMath.mass_to_radius(part["mass"]) + 360.0
		for other_id in _part_hash.query(part["pos"], query_radius):
			if other_id == part_id or not parts.has(part_id) or not parts.has(other_id):
				continue
			var key = str(min(part_id, other_id)) + ":" + str(max(part_id, other_id))
			if checked.has(key):
				continue
			checked[key] = true
			var a = parts[part_id]
			var b = parts[other_id]
			if a["owner_id"] == b["owner_id"]:
				continue
			if _can_consume_part(a, b):
				a["mass"] += b["mass"]
				_remove_part(other_id)
			elif _can_consume_part(b, a):
				b["mass"] += a["mass"]
				_remove_part(part_id)

func _resolve_recombine() -> void:
	for owner_id in players.keys():
		var list: Array = players[owner_id]["parts"].duplicate()
		for i in range(list.size()):
			if not parts.has(list[i]):
				continue
			for j in range(i + 1, list.size()):
				if not parts.has(list[i]) or not parts.has(list[j]):
					continue
				var a = parts[list[i]]
				var b = parts[list[j]]
				if a["merge_time"] > 0.0 or b["merge_time"] > 0.0:
					continue
				var ra = MassMath.mass_to_radius(a["mass"])
				var rb = MassMath.mass_to_radius(b["mass"])
				var merge_distance = max(ra, rb) * 0.80
				if a["pos"].distance_to(b["pos"]) <= merge_distance:
					_merge_parts(list[i], list[j])

func _resolve_part_hole(part_id: int, hole_id: int) -> void:
	var part = parts[part_id]
	var hole = holes[hole_id]
	if part["hole_cd"] > 0.0:
		return
	var dist = part["pos"].distance_to(hole["pos"])
	var part_radius = MassMath.mass_to_radius(part["mass"])
	if dist > part_radius + hole["radius"] * 0.46:
		return
	if hole["kind"] == "blue" and part["mass"] < GameConstants.BLACK_HOLE_DANGER_MASS:
		part["mass"] += GameConstants.BLUE_BLACK_HOLE_REWARD
		part["hole_cd"] = 0.65
		_respawn_hole(hole_id)
		return
	if part["mass"] >= GameConstants.BLACK_HOLE_DANGER_MASS:
		_explode_part_on_hole(part_id)

func _explode_part_on_hole(part_id: int) -> void:
	if not parts.has(part_id):
		return
	var part = parts[part_id]
	var owner_id: int = part["owner_id"]
	var current_count = players[owner_id]["parts"].size()
	if current_count >= GameConstants.BASIC_SPLIT_CAP:
		var loss = part["mass"] * GameConstants.BLACK_HOLE_ALREADY_SPLIT_LOSS_RATIO
		part["mass"] -= loss
		_spawn_mass_spray(part["pos"], loss)
		part["hole_cd"] = 0.75
		return
	var target_count = min(GameConstants.BASIC_SPLIT_CAP - current_count + 1, 8)
	target_count = max(target_count, 2)
	var retained_mass = part["mass"] * (1.0 - GameConstants.BLACK_HOLE_MASS_LOSS_RATIO)
	var lost_mass = part["mass"] - retained_mass
	var each = retained_mass / float(target_count)
	part["mass"] = each
	part["merge_time"] = MassMath.recombine_seconds(each)
	part["hole_cd"] = 0.9
	_spawn_mass_spray(part["pos"], lost_mass)
	for i in range(target_count - 1):
		var angle = (TAU * float(i) / float(target_count - 1)) + rng.randf_range(-0.18, 0.18)
		var dir = Vector2.from_angle(angle)
		_add_part(owner_id, _clamp_to_arena(part["pos"] + dir * 42.0), each, dir * GameConstants.SPLIT_IMPULSE * 0.82, part["merge_time"], 0.9)

func _split_part(part_id: int, direction: Vector2) -> void:
	var part = parts[part_id]
	var old_mass: float = part["mass"]
	var new_mass = old_mass * GameConstants.SPLIT_MASS_FRACTION
	part["mass"] = old_mass - new_mass
	var merge_time = MassMath.recombine_seconds(old_mass)
	part["merge_time"] = merge_time
	part["hole_cd"] = 0.22
	var radius = MassMath.mass_to_radius(part["mass"])
	var spawn_pos: Vector2 = part["pos"] + direction.normalized() * radius * GameConstants.SPLIT_SPAWN_OFFSET
	var new_vel: Vector2 = direction.normalized() * GameConstants.SPLIT_IMPULSE + part["vel"] * 0.35
	part["vel"] -= direction.normalized() * 60.0
	_add_part(part["owner_id"], _clamp_to_arena(spawn_pos), new_mass, new_vel, merge_time, 0.22)

func _merge_parts(a_id: int, b_id: int) -> void:
	if not parts.has(a_id) or not parts.has(b_id):
		return
	var a = parts[a_id]
	var b = parts[b_id]
	var total = a["mass"] + b["mass"]
	a["pos"] = (a["pos"] * a["mass"] + b["pos"] * b["mass"]) / total
	a["vel"] = (a["vel"] * a["mass"] + b["vel"] * b["mass"]) / total
	a["mass"] = total
	a["merge_time"] = 0.0
	_remove_part(b_id, false)

func _can_consume_part(attacker: Dictionary, victim: Dictionary) -> bool:
	if not MassMath.can_consume(attacker["mass"], victim["mass"]):
		return false
	var ra = MassMath.mass_to_radius(attacker["mass"])
	var rv = MassMath.mass_to_radius(victim["mass"])
	var dist = attacker["pos"].distance_to(victim["pos"])
	return dist + rv * GameConstants.CONSUME_OVERLAP_FRACTION <= ra

func _movement_direction_for_part(player: Dictionary, part: Dictionary) -> Vector2:
	if player.get("move_mode", "target") == "target":
		var offset: Vector2 = player.get("target_pos", part["pos"]) - part["pos"]
		if offset.length_squared() <= GameConstants.INPUT_DEADZONE * GameConstants.INPUT_DEADZONE:
			return Vector2.ZERO
		return offset.normalized()
	var direction: Vector2 = player.get("input_dir", Vector2.ZERO)
	if direction.length_squared() > 1.0:
		return direction.normalized()
	return direction

func _action_direction_for_part(player: Dictionary, part: Dictionary) -> Vector2:
	if player.get("move_mode", "target") == "target":
		var offset: Vector2 = player.get("target_pos", part["pos"]) - part["pos"]
		if offset.length_squared() > 0.001:
			return offset.normalized()
	var direction: Vector2 = player.get("last_input_dir", player.get("input_dir", Vector2.RIGHT))
	if direction.length_squared() > 0.001:
		return direction.normalized()
	return Vector2.RIGHT

func _add_part(owner_id: int, pos: Vector2, mass: float, vel = Vector2.ZERO, merge_time = 0.0, hole_cd = 0.0) -> int:
	var id = _next_id()
	var color: Color = players[owner_id]["color"]
	parts[id] = {
		"id": id,
		"owner_id": owner_id,
		"pos": pos,
		"vel": vel,
		"mass": mass,
		"merge_time": merge_time,
		"hole_cd": hole_cd,
		"age": 0.0,
		"color": color
	}
	players[owner_id]["parts"].append(id)
	return id

func _remove_part(part_id: int, mark_death = true) -> void:
	if not parts.has(part_id):
		return
	var owner_id: int = parts[part_id]["owner_id"]
	parts.erase(part_id)
	if players.has(owner_id):
		players[owner_id]["parts"].erase(part_id)
		if mark_death and players[owner_id]["parts"].is_empty():
			players[owner_id]["alive"] = false
			players[owner_id]["respawn_timer"] = 2.0 if owner_id == GameConstants.PLAYER_ID else rng.randf_range(1.0, 4.5)

func _spawn_pellet(pos = Vector2.INF, mass = -1.0) -> int:
	var id = _next_id()
	var pellet_mass = mass if mass > 0.0 else rng.randf_range(GameConstants.PELLET_MASS_MIN, GameConstants.PELLET_MASS_MAX)
	pellets[id] = {
		"id": id,
		"pos": _random_arena_pos(42.0) if pos == Vector2.INF else pos,
		"mass": pellet_mass,
		"color": _pellet_color()
	}
	return id

func _spawn_mass_spray(origin: Vector2, mass: float) -> void:
	var remaining = max(mass, 0.0)
	while remaining > 0.8:
		var pellet_mass = min(rng.randf_range(1.0, 3.2), remaining)
		remaining -= pellet_mass
		var dir = _random_dir()
		var pos = _clamp_to_arena(origin + dir * rng.randf_range(22.0, 80.0))
		_spawn_pellet(pos, pellet_mass)

func _spawn_black_hole(index: int) -> int:
	var id = _next_id()
	var kind = "normal"
	if index % 4 == 1:
		kind = "blue"
	var radius = GameConstants.BLUE_BLACK_HOLE_RADIUS if kind == "blue" else GameConstants.BLACK_HOLE_RADIUS
	var base_vel = _random_dir() * rng.randf_range(GameConstants.BLACK_HOLE_DRIFT_SPEED * 0.45, GameConstants.BLACK_HOLE_DRIFT_SPEED)
	holes[id] = {
		"id": id,
		"kind": kind,
		"pos": _random_arena_pos(220.0),
		"vel": base_vel,
		"base_vel": base_vel,
		"radius": radius,
		"phase": rng.randf_range(0.0, TAU),
		"spin": rng.randf_range(0.65, 1.45)
	}
	return id

func _respawn_hole(hole_id: int) -> void:
	if not holes.has(hole_id):
		return
	holes[hole_id]["pos"] = _random_arena_pos(220.0)
	holes[hole_id]["vel"] = _random_dir() * rng.randf_range(GameConstants.BLACK_HOLE_DRIFT_SPEED * 0.45, GameConstants.BLACK_HOLE_DRIFT_SPEED)
	holes[hole_id]["base_vel"] = holes[hole_id]["vel"]

func _direction_to_nearest_pellet(center: Vector2) -> Vector2:
	var best = Vector2.ZERO
	var best_dist = INF
	var checked = 0
	for id in pellets.keys():
		var offset: Vector2 = pellets[id]["pos"] - center
		var dist = offset.length_squared()
		if dist < best_dist:
			best = offset
			best_dist = dist
		checked += 1
		if checked > 80:
			break
	if best.length_squared() < 1.0:
		return _random_dir()
	return best.normalized()

func _bounce_inside_arena(pos: Vector2, part: Dictionary) -> Vector2:
	var radius = MassMath.mass_to_radius(part["mass"])
	if pos.x < radius or pos.x > GameConstants.WORLD_SIZE.x - radius:
		part["vel"].x *= -0.24
	if pos.y < radius or pos.y > GameConstants.WORLD_SIZE.y - radius:
		part["vel"].y *= -0.24
	return _clamp_to_arena(pos, radius)

func _clamp_to_arena(pos: Vector2, margin = 0.0) -> Vector2:
	return Vector2(
		clamp(pos.x, margin, GameConstants.WORLD_SIZE.x - margin),
		clamp(pos.y, margin, GameConstants.WORLD_SIZE.y - margin)
	)

func _random_arena_pos(margin = 0.0) -> Vector2:
	return Vector2(
		rng.randf_range(margin, GameConstants.WORLD_SIZE.x - margin),
		rng.randf_range(margin, GameConstants.WORLD_SIZE.y - margin)
	)

func _random_dir() -> Vector2:
	return Vector2.from_angle(rng.randf_range(0.0, TAU))

func _pellet_color() -> Color:
	var palette = [
		Color(0.80, 0.94, 1.0),
		Color(0.98, 0.74, 0.46),
		Color(0.98, 0.47, 0.68),
		Color(0.60, 0.94, 0.82),
		Color(0.78, 0.72, 1.0),
		Color(0.98, 0.93, 0.52)
	]
	return palette[rng.randi_range(0, palette.size() - 1)]

func _bot_name(index: int) -> String:
	var names = [
		"Nova", "Astra", "Delta", "Quasar", "Nibbler", "Orbit", "Halo",
		"Vortex", "Zenith", "Pulse", "Comet", "Lumen", "Spectra", "Ion",
		"Photon", "Drift", "Glint", "Vector", "Cosmo", "Prism"
	]
	return names[index % names.size()]

func _next_id() -> int:
	_next_entity_id += 1
	return _next_entity_id
