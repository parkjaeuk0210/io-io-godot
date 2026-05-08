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
	_test_step_stability()
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

func _test_step_stability() -> void:
	var world = SimWorldScript.new()
	world.setup(13)
	for i in range(120):
		world.step(1.0 / GameConstants.SIM_TICK_RATE)
	_assert(world.pellets.size() >= GameConstants.PELLET_COUNT - 5, "pellet population stays replenished")
	_assert(world.parts.size() > 0, "parts survive stress steps")

func _keep_only_player(world) -> void:
	for owner_id in world.players.keys():
		if owner_id == GameConstants.PLAYER_ID:
			continue
		for part_id in world.players[owner_id]["parts"].duplicate():
			world.parts.erase(part_id)
		world.players.erase(owner_id)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
