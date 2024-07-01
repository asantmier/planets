## A crater for crater processing and storage
class_name Crater

var pos: Vector3
var radius: float
var floor_height: float
var rim_width: float
var rim_steepness: float
var affected_sectors: Dictionary # List of sectors this crater covers keyed on sector number
var id := 0 # ID to uniquely identify a crater
static var _global_id := 0

var _base_bytes : PackedByteArray


@warning_ignore("shadowed_variable")
func _init(pos, radius, floor_height, rim_width, rim_steepness, affected_sectors):
	self.pos = pos
	self.radius = radius
	self.floor_height = floor_height
	self.rim_width = rim_width
	self.rim_steepness = rim_steepness
	for sector: Sector in affected_sectors:
		self.affected_sectors[sector.sector_number] = sector
	id = _global_id
	_global_id += 1


## Checks if two craters have the same ID
func equals(other: Crater) -> bool:
	return self.id == other.id


## Sets base bytes to a so that you can get them back later
func set_base_bytes(bytes: PackedByteArray) -> void:
	_base_bytes = bytes


## Returns base bytes and removes internal reference to conserve memory
func get_and_clear_base_bytes() -> PackedByteArray:
	var out = _base_bytes
	_base_bytes = []
	return out
