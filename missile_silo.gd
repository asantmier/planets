extends Building

@export_flags_3d_physics var terrain_layer

func _init():
	is_turret = true


## Target pos must be global
# TODO connect one shot to the physics frame to do the missile stuff.
# Better yet let the manager handle all of that
func fire(target_pos, target_planet):
	print("Firing!")
	var start_planet = get_parent().get_parent().planet
	var missile = ProjectileManager.create_missle()
	missile.set_target(global_position, target_pos, start_planet, target_planet)
	missile.global_position = global_position
	## Intersect with terraingrid and call exploded on it
	#var space_state = get_world_3d().direct_space_state
	#var query = PhysicsRayQueryParameters3D.create(global_position, target_pos, terrain_layer)
	#query.collide_with_areas = true
	#var result = space_state.intersect_ray(query)
	#var end_planet
	#if not result.is_empty():
		##result.collider.explode(result.position)
		#end_planet = result.collider.planet
		#var start_planet = get_parent().get_parent().planet
		#var missile = ProjectileManager.create_missle()
		#missile.set_target(global_position, target_pos, start_planet, end_planet)
		#missile.global_position = global_position
	#else:
		#printerr("Missile silo hit no terrain!")
