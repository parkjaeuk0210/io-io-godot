extends RefCounted
class_name SpatialHash

var cell_size = 128.0
var buckets = {}

func _init(size = 128.0) -> void:
	cell_size = max(size, 1.0)

func clear() -> void:
	buckets.clear()

func insert(id: int, pos: Vector2) -> void:
	var key = _cell_key(pos)
	if not buckets.has(key):
		buckets[key] = []
	buckets[key].append(id)

func query(pos: Vector2, radius: float) -> Array:
	var result = []
	var min_x = floori((pos.x - radius) / cell_size)
	var max_x = floori((pos.x + radius) / cell_size)
	var min_y = floori((pos.y - radius) / cell_size)
	var max_y = floori((pos.y + radius) / cell_size)
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var key = Vector2i(x, y)
			if buckets.has(key):
				result.append_array(buckets[key])
	return result

func _cell_key(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.y / cell_size))
