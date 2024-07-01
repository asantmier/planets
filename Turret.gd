extends Building

@export_flags_3d_physics var terrain_layer

func _init():
	is_turret = true


## Target pos must be global
func fire(target_pos, target_planet):
	print("Firing!")
	# Intersect with terraingrid and call exploded on it
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, target_pos, terrain_layer)
	query.collide_with_areas = true
	var result = space_state.intersect_ray(query)
	if not result.is_empty():
		result.collider.explode(result.position)
	else:
		printerr("Turret hit no terrain!")
