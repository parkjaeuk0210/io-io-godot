extends RefCounted
class_name MassMath

const GameConstants = preload("res://scripts/core/GameConstants.gd")

static func mass_to_radius(mass: float) -> float:
	return 8.0 + sqrt(max(mass, 0.0)) * 4.45

static func pellet_radius(mass: float) -> float:
	return 2.4 + sqrt(max(mass, 0.0)) * 2.15

static func mass_to_speed(mass: float) -> float:
	var m = max(mass, 1.0)
	var speed = 238.0 / (1.0 + pow(m / 145.0, 0.53)) + 28.0
	return clamp(speed, 52.0, 214.0)

static func recombine_seconds(mass: float) -> float:
	var seconds = GameConstants.RECOMBINE_BASE_SECONDS + sqrt(max(mass, 0.0)) * GameConstants.RECOMBINE_MASS_SCALE
	return clamp(seconds, GameConstants.RECOMBINE_BASE_SECONDS, GameConstants.RECOMBINE_MAX_SECONDS)

static func camera_zoom(total_mass: float) -> float:
	var zoom = 1.0 / (1.0 + pow(max(total_mass, 1.0) / 850.0, 0.42))
	return clamp(zoom, GameConstants.CAMERA_MIN_ZOOM, GameConstants.CAMERA_MAX_ZOOM)

static func ejected_source_loss(source_mass: float) -> float:
	var scaled = source_mass * GameConstants.EJECT_SOURCE_LOSS_RATIO
	return clamp(scaled, GameConstants.EJECT_SOURCE_LOSS_MIN, GameConstants.EJECT_SOURCE_LOSS_MAX)

static func can_consume(attacker_mass: float, victim_mass: float) -> bool:
	return attacker_mass >= victim_mass * GameConstants.CONSUME_MASS_RATIO
