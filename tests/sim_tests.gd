extends SceneTree

const GameConstants = preload("res://scripts/core/GameConstants.gd")
const MassMath = preload("res://scripts/core/MassMath.gd")
const SimWorldScript = preload("res://scripts/core/SimWorld.gd")

var failures = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_mass_math()
	_test_split_cap_and_mass()
	_test_eject_loss()
	_test_black_hole_threshold()
	_test_black_hole_spray_uses_limited_transient_debris()
	_test_blue_hole_reward_respects_total_mass_cap()
	_test_food_gain_tapers_above_hard_cap()
	_test_part_consumption_tapers_above_hard_cap()
	_test_step_stability()
	_test_direction_input_uses_per_part_steering()
	_test_unlocked_same_owner_parts_merge_on_shared_target()
	if failures.is_empty():
		print("sim_tests: OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_mass_math() -> void:
	_assert(MassMath.mass_to_radius(400.0) > MassMath.mass_to_radius(100.0), "radius grows with mass")
	_assert(MassMath.mass_to_speed(400.0) < MassMath.mass_to_speed(40.0), "speed falls with mass")
	_assert(MassMath.recombine_seconds(100000.0) <= GameConstants.RECOMBINE_MAX_SECONDS, "recombine has public cap")
	_assert(MassMath.can_consume(116.0, 100.0), "consume ratio threshold")
	_assert(not MassMath.can_consume(110.0, 100.0), "consume ratio rejects near equal masses")

func _test_split_cap_and_mass() -> void:
	var world = SimWorldScript.new()
	world.setup(7)
	_keep_only_player(world)
	var part_id = world.players[GameConstants.PLAYER_ID]["parts"][0]
	world.parts[part_id]["mass"] = 640.0
	var before = world.get_player_total_mass(GameConstants.PLAYER_ID)
	for i in range(5):
		world.request_split(GameConstants.PLAYER_ID)
	var after = world.get_player_total_mass(GameConstants.PLAYER_ID)
	_assert(world.players[GameConstants.PLAYER_ID]["parts"].size() == GameConstants.BASIC_SPLIT_CAP, "split reaches basic cap")
	_assert(abs(before - after) < 0.01, "manual split conserves mass")

func _test_eject_loss() -> void:
	var world = SimWorldScript.new()
	world.setup(9)
	_keep_only_player(world)
	var part_id = world.players[GameConstants.PLAYER_ID]["parts"][0]
	world.parts[part_id]["mass"] = 100.0
	world.set_player_input(GameConstants.PLAYER_ID, Vector2.RIGHT)
	world.request_eject(GameConstants.PLAYER_ID)
	var player_mass = world.get_player_total_mass(GameConstants.PLAYER_ID)
	var ejected_mass = 0.0
	for id in world.ejected.keys():
		ejected_mass += world.ejected[id]["mass"]
	_assert(world.ejected.size() == 1, "eject creates one pellet from one part")
	_assert(player_mass < 100.0, "eject reduces player mass")
	_assert(player_mass + ejected_mass < 100.0, "eject has loss")

func _test_black_hole_threshold() -> void:
	var world = SimWorldScript.new()
	world.setup(11)
	_keep_only_player(world)
	var part_id = world.players[GameConstants.PLAYER_ID]["parts"][0]
	var hole_id = world.holes.keys()[0]
	world.holes[hole_id]["kind"] = "normal"
	world.parts[part_id]["mass"] = GameConstants.BLACK_HOLE_DANGER_MASS + 20.0
	world.parts[part_id]["pos"] = world.holes[hole_id]["pos"]
	world.step(1.0 / GameConstants.SIM_TICK_RATE)
	_assert(world.players[GameConstants.PLAYER_ID]["parts"].size() > 1, "danger-mass blob splits on black hole")

func _test_black_hole_spray_uses_limited_transient_debris() -> void:
	var world = SimWorldScript.new()
	world.setup(18)
	_keep_only_player(world)
	_clear_environment(world)
	world._spawn_mass_spray(Vector2(2800.0, 1800.0), 2000.0)
	_assert(world.pellets.is_empty(), "black hole spray does not expand persistent pellet pool")
	_assert(world.debris.size() > 0, "black hole spray creates transient debris")
	_assert(world.debris.size() <= GameConstants.MASS_SPRAY_MAX_PIECES, "black hole spray debris count is capped")
	var part_id = world.players[GameConstants.PLAYER_ID]["parts"][0]
	var debris_id = world.debris.keys()[0]
	world.parts[part_id]["pos"] = world.debris[debris_id]["pos"]
	world.parts[part_id]["vel"] = Vector2.ZERO
	var before_pellets = world.pellets.size()
	world.step(1.0 / GameConstants.SIM_TICK_RATE)
	_assert(world.pellets.size() == before_pellets, "eaten debris does not respawn as persistent food")

func _test_blue_hole_reward_respects_total_mass_cap() -> void:
	var world = SimWorldScript.new()
	world.setup(12)
	_keep_only_player(world)
	_clear_environment(world)
	var owner_id = GameConstants.PLAYER_ID
	var first_id = world.players[owner_id]["parts"][0]
	var second_id = world._add_part(owner_id, Vector2(2800.0, 1800.0), 160.0, Vector2.ZERO, 0.0)
	world.parts[first_id]["mass"] = 120.0
	world.parts[first_id]["pos"] = Vector2(2800.0, 1800.0)
	world.parts[first_id]["vel"] = Vector2.ZERO
	world.parts[second_id]["vel"] = Vector2.ZERO
	var hole_id = world._spawn_black_hole(1)
	world.holes[hole_id]["kind"] = "blue"
	world.holes[hole_id]["pos"] = world.parts[first_id]["pos"]
	world.holes[hole_id]["vel"] = Vector2.ZERO
	world.holes[hole_id]["base_vel"] = Vector2.ZERO
	var before = world.get_player_total_mass(owner_id)
	world.step(1.0 / GameConstants.SIM_TICK_RATE)
	var after = world.get_player_total_mass(owner_id)
	_assert(before >= GameConstants.BLACK_HOLE_DANGER_MASS, "test setup starts above blue reward cap")
	_assert(after <= before + 0.01, "blue hole reward does not feed already large total mass")

func _test_food_gain_tapers_above_hard_cap() -> void:
	var world = SimWorldScript.new()
	world.setup(14)
	_keep_only_player(world)
	_clear_environment(world)
	var owner_id = GameConstants.PLAYER_ID
	var part_id = world.players[owner_id]["parts"][0]
	world.parts[part_id]["mass"] = GameConstants.MASS_GAIN_HARD_CAP + 800.0
	world.parts[part_id]["pos"] = Vector2(2800.0, 1800.0)
	world.parts[part_id]["vel"] = Vector2.ZERO
	world._spawn_pellet(world.parts[part_id]["pos"], 3.0)
	var before = world.get_player_total_mass(owner_id)
	world.step(1.0 / GameConstants.SIM_TICK_RATE)
	var after = world.get_player_total_mass(owner_id)
	_assert(after <= before, "food gain is suppressed above hard cap")

func _test_part_consumption_tapers_above_hard_cap() -> void:
	var world = SimWorldScript.new()
	world.setup(16)
	_keep_only_owners(world, [GameConstants.PLAYER_ID, 20])
	_clear_environment(world)
	var owner_id = GameConstants.PLAYER_ID
	var prey_owner_id = 20
	var attacker_id = world.players[owner_id]["parts"][0]
	var victim_id = world.players[prey_owner_id]["parts"][0]
	world.parts[attacker_id]["mass"] = GameConstants.MASS_GAIN_HARD_CAP + 500.0
	world.parts[attacker_id]["pos"] = Vector2(2800.0, 1800.0)
	world.parts[attacker_id]["vel"] = Vector2.ZERO
	world.parts[victim_id]["mass"] = 120.0
	world.parts[victim_id]["pos"] = Vector2(2800.0, 1800.0)
	world.parts[victim_id]["vel"] = Vector2.ZERO
	var before = world.get_player_total_mass(owner_id)
	world.step(1.0 / GameConstants.SIM_TICK_RATE)
	var after = world.get_player_total_mass(owner_id)
	_assert(not world.parts.has(victim_id), "oversized part can still remove consumed victim")
	_assert(after <= before, "part consumption gain is suppressed above hard cap")

func _test_step_stability() -> void:
	var world = SimWorldScript.new()
	world.setup(13)
	for i in range(120):
		world.step(1.0 / GameConstants.SIM_TICK_RATE)
	_assert(world.pellets.size() >= GameConstants.PELLET_COUNT - 5, "pellet population stays replenished")
	_assert(world.parts.size() > 0, "parts survive stress steps")

func _test_direction_input_uses_per_part_steering() -> void:
	var world = SimWorldScript.new()
	world.setup(15)
	_keep_only_player(world)
	_clear_environment(world)
	var owner_id = GameConstants.PLAYER_ID
	var first_id = world.players[owner_id]["parts"][0]
	var second_id = world._add_part(owner_id, Vector2(2000.0, 2000.0), 80.0, Vector2.ZERO, 0.0)
	world.parts[first_id]["mass"] = 80.0
	world.parts[first_id]["pos"] = Vector2(2000.0, 1800.0)
	world.parts[first_id]["vel"] = Vector2.ZERO
	world.parts[second_id]["vel"] = Vector2.ZERO
	world.set_player_input(owner_id, Vector2.RIGHT)
	world.step(1.0 / GameConstants.SIM_TICK_RATE)
	var first_dir: Vector2 = world.parts[first_id]["vel"].normalized()
	var second_dir: Vector2 = world.parts[second_id]["vel"].normalized()
	_assert(abs(first_dir.cross(second_dir)) > 0.001, "same direction input creates per-part steering")

func _test_unlocked_same_owner_parts_merge_on_shared_target() -> void:
	var world = SimWorldScript.new()
	world.setup(17)
	_keep_only_player(world)
	_clear_environment(world)
	var owner_id = GameConstants.PLAYER_ID
	var first_id = world.players[owner_id]["parts"][0]
	var second_id = world._add_part(owner_id, Vector2(2600.0, 1920.0), 80.0, Vector2.ZERO, 0.0)
	world.parts[first_id]["mass"] = 80.0
	world.parts[first_id]["pos"] = Vector2(2600.0, 1680.0)
	world.parts[first_id]["vel"] = Vector2.ZERO
	world.parts[first_id]["merge_time"] = 0.0
	world.parts[second_id]["vel"] = Vector2.ZERO
	world.parts[second_id]["merge_time"] = 0.0
	world.set_player_target(owner_id, Vector2(2600.0, 1800.0))
	for i in range(120):
		if world.players[owner_id]["parts"].size() == 1:
			break
		world.step(1.0 / GameConstants.SIM_TICK_RATE)
	_assert(world.players[owner_id]["parts"].size() == 1, "unlocked same-owner parts merge on a shared target")

func _keep_only_player(world) -> void:
	_keep_only_owners(world, [GameConstants.PLAYER_ID])

func _keep_only_owners(world, allowed: Array) -> void:
	for owner_id in world.players.keys():
		if allowed.has(owner_id):
			continue
		for part_id in world.players[owner_id]["parts"].duplicate():
			world.parts.erase(part_id)
		world.players.erase(owner_id)

func _clear_environment(world) -> void:
	world.pellets.clear()
	world.debris.clear()
	world.ejected.clear()
	world.holes.clear()

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
