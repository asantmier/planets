extends CSGCombiner3D

@export var inner_scale := 0.9


func _on_sector_selected(sector: Sector, focused: bool):
	# INFO ignoring unfocused sectors
	if not focused: return
	
	var points = []
	var center = sector.center
	for p in sector.shape.points:
		points.append(p + sector.global_position)
	var outer_points = []
	var inner_points = []
	var normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var x = (points[1] - points[0]).normalized()
	var y = x.cross(normal).normalized()
	var local_basis = Basis(x, y, normal)
	var sector_position = sector.global_position + center
	var local_transform = Transform3D(local_basis, sector_position)
	
	for point_3d in points:
		var point_local = point_3d * local_transform
		outer_points.append(Vector2(point_local.x, point_local.y))
		inner_points.append(Vector2(point_local.x, point_local.y) * inner_scale)
	
	reparent(sector)
	transform = Transform3D(local_basis, center)
	$Outer.polygon = outer_points
	$Inner.polygon = inner_points
