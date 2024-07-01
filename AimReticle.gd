extends CSGCombiner3D

var on_planet

# Called when the node enters the scene tree for the first time.
func _ready():
	hide()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_sector_selected(sector: Sector, focused: bool):
	var points = []
	var center = sector.center
	# TODO is this necesary since we reparent it anyway?
	for p in sector.shape.points:
		points.append(p + sector.global_position)
	var normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var x = (points[1] - points[0]).normalized()
	var y = x.cross(normal).normalized()
	var local_basis = Basis(x, y, normal)
	reparent(sector)
	transform = Transform3D(local_basis, center)
	on_planet = sector.get_planet()
