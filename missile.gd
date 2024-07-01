extends Node3D

var start_position: Vector3
var end_position: Vector3
var start_planet
var end_planet

var last_angle

@export var speed: float
@export var turn_speed_rad: float
@export var epsilion := 0.01
@export var gamma := 0.01
@export var penetration := 0.1

var taking_off := true

## Start and end should be global coordinates
func set_target(start, end, starting_planet, ending_planet):
	start_position = start
	end_position = end
	start_planet = starting_planet
	end_planet = ending_planet
	print("Missile | %s->%s (%s->%s)" % [starting_planet.name, ending_planet.name, start, end])
	#build_curve()
	taking_off = true


func _physics_process(delta):
	if global_position.distance_to(end_position) <= gamma or global_position.distance_to(end_planet.global_position) <= 1.0 - penetration:
		end_planet.terrain_grid.explode(global_position)
		queue_free()
		return
	
	var turn_circumference := ((2 * PI) / turn_speed_rad) * speed
	var turn_radius := turn_circumference / (2 * PI)
	var turn_circle_radius := 2 * turn_radius
	
	var target_quat := global_transform.looking_at(end_position, global_basis.z.cross(end_position), true).basis.get_rotation_quaternion()
	var curr_quat := global_transform.basis.get_rotation_quaternion()
	var angle_to_target := global_position.angle_to(end_position)
	var rot_delta := clampf(turn_speed_rad, 0, angle_to_target)
	var weight: = rot_delta / angle_to_target
	var curr_heading := global_basis.z
	
	if taking_off:
		taking_off = (global_position - start_planet.global_position).length() < start_planet.orbit_radius
	## If within radius of start, don't turn
	else:
		## turn towards target, clamp on the following
		var to_target = (end_position - global_position).normalized()
		#DebugDraw3D.draw_sphere(end_position, 0.1, Color.DARK_RED)
		#DebugDraw3D.draw_sphere(end_planet.global_position, end_planet.orbit_radius, Color.YELLOW)
		#DebugDraw3D.draw_sphere(end_position, turn_circle_radius, Color.BLUE)
		
		var intersection := ray_sphere_intersection(end_planet.global_position, 1.0, global_position, to_target)
		#print("%s | %s, %s, %s" % [abs(intersection - global_position.distance_to(end_position)) <= epsilion, intersection,
		 #global_position.distance_to(end_position), abs(intersection - global_position.distance_to(end_position))])
		
		# TODO to improve pathing, try turning on one axis at a time
		## If we do not have line of sight on the target and at a proper distance
		if not (abs(intersection - global_position.distance_to(end_position)) <= epsilion and global_position.distance_to(end_position) >= turn_circle_radius):
			##  If line to target intersects start, heading must not intersect start
			if ray_sphere(start_planet.global_position, start_planet.orbit_radius, global_position, to_target):
				var rotated_quat := curr_quat.slerp(target_quat, weight)
				var rotated_basis := Basis(rotated_quat)
				if ray_sphere(start_planet.global_position, start_planet.orbit_radius, global_position, rotated_basis.z)\
				or ray_sphere(end_planet.global_position, end_planet.orbit_radius, global_position, rotated_basis.z)\
				or ray_sphere(end_position, turn_circle_radius, global_position, rotated_basis.z):
					# Rotated too far
					rot_delta = 0
			##  If line to target intersects end, heading must not intersect end
			if ray_sphere(end_planet.global_position, end_planet.orbit_radius, global_position, to_target):
				var rotated_quat := curr_quat.slerp(target_quat, weight)
				var rotated_basis := Basis(rotated_quat)
				if ray_sphere(end_planet.global_position, end_planet.orbit_radius, global_position, rotated_basis.z)\
				or ray_sphere(end_position, turn_circle_radius, global_position, rotated_basis.z):
					# Rotated too far
					rot_delta = 0
			## If no rotation, but heading into circle, continue last rotation
			if rot_delta == 0 and (ray_sphere(end_planet.global_position, end_planet.orbit_radius, global_position, curr_heading)
			or ray_sphere(end_position, turn_circle_radius, global_position, curr_heading)):
				rot_delta = clampf(last_angle, 0, angle_to_target)
			##  Heading must never intersect turning circle
			##   Turning circle is centered on target with r = 2 * turn radius
		
		global_basis = Basis(curr_quat.slerp(target_quat, rot_delta / angle_to_target))
		last_angle = angle_to_target
	global_position += global_basis.z * speed


## Checks if a ray intersects a sphere
func ray_sphere(center: Vector3, radius: float, origin: Vector3, direction: Vector3) -> bool:
	## https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-sphere-intersection.html
	var L := center - origin # vector to sphere
	var tca := L.dot(direction) # length of ray to sphere
	if tca < 0: # This condition ignores if the sphere is behind the origin
		return false
	var d2 := L.dot(L) - tca * tca
	if d2 > (radius * radius):
		return false
	# At this point we know that there is an intersection
	return true


## Returns distance of intersection of a ray and a sphere. Value is negative if no intersection
func ray_sphere_intersection(center: Vector3, radius: float, origin: Vector3, direction: Vector3) -> float:
	## https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-sphere-intersection.html
	var L := center - origin # vector to sphere
	var tca := L.dot(direction) # length of ray to sphere
	if tca < 0: # This condition ignores if the sphere is behind the origin
		return -1
	var d2 := L.dot(L) - tca * tca
	if d2 > (radius * radius):
		return -1
	var thc = sqrt(radius * radius - d2)
	var t0 = tca - thc
	var t1 = tca + thc
	if t0 > t1:
		var tmp = t0
		t0 = t1
		t1 = tmp
	if t0 < 0:
		t0 = t1
		if t0 < 0:
			return -1
	return t0
