class_name Sector extends CollisionShape3D

signal exploded(pos: Vector3)

var center: Vector3 # Center of the sector polygon

@export var lod_bias := 0.0
var current_lod: int

var sector_number := -1:
	get: 
		assert(sector_number > -1)
		return sector_number
	set(value):
		sector_number = value

var m_lods : Array[SectorLOD]
# Stores all craters that affect this sector keyed by their ID
var craters : Dictionary
var last_modified_by_crater_id := -1 # Stores the id of the last crater that modified this sector

var awaiting_commit := false

var building: Building
var devastation := 0.0


## Commits mesh changes to server
func commit_changes():
	for lod: SectorLOD in m_lods:
		lod.try_commit_changes()
	awaiting_commit = false


## Updates the LOD, returns true if the LOD changes
func update_lod():
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_transform.origin.distance_to(global_transform.origin + center) + lod_bias
	#var shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if distance > shadow_distance else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var changed = false
	for lod: SectorLOD in m_lods:
		if distance >= lod.begin and (distance < lod.end or lod.end == 0.0):
			changed = current_lod != lod.level
			if lod.get_parent() == null:
				$LODs.add_child(lod)
			#lod.visible = true
			current_lod = lod.level
		else:
			if lod.get_parent() == $LODs:
				$LODs.remove_child(lod)
			#lod.visible = false


## Sets LOD quality to 0 and disables shadows
func set_low_quality():
	for lod: SectorLOD in m_lods:
		if lod.level == 0:
			current_lod = lod.level
			#lod.visible = true
			if lod.get_parent() == null:
				$LODs.add_child(lod)
		else:
			#lod.visible = false
			if lod.get_parent() == $LODs:
				$LODs.remove_child(lod)
		lod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Restores normal LOD quality and enables shadows
func set_normal_quality():
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_transform.origin.distance_to(global_transform.origin + center) + lod_bias
	for lod: SectorLOD in m_lods:
		if distance >= lod.begin and (distance < lod.end or lod.end == 0.0):
			current_lod = lod.level
			#lod.visible = true
			if lod.get_parent() == null:
				$LODs.add_child(lod)
		else:
			#lod.visible = false
			if lod.get_parent() == $LODs:
				$LODs.remove_child(lod)
		lod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Takes some new mesh data for lods and processes it on another thread. Also
## updates last modified crater id. Returns thread id
func queue_new_mesh_data(lod_verts: Array[PackedVector3Array], lod_norms: Array[PackedVector3Array], sender_id: int) -> int:
	if last_modified_by_crater_id > sender_id:
		return -1
	
	last_modified_by_crater_id = sender_id
	
	var callable = precompute_thread.bind(lod_verts, lod_norms, sender_id)
	return WorkerThreadPool.add_task(callable, true, "Sector stitch thread #%d" % sender_id)


## Precomputes stitch tables in a multithreaded manner
func precompute_thread(lod_verts: Array[PackedVector3Array], lod_norms: Array[PackedVector3Array], sender_id: int):
	# Update lods
	for i in range(m_lods.size()):
		m_lods[i].fast_precompute_lod_stitch_and_surface(lod_verts[i], lod_norms[i], sender_id)
		call_deferred("request_commit")


## Requests an update from the sector manager
func request_commit():
	if not awaiting_commit:
		awaiting_commit = true
		SectorManager.request_update(self)


## Set this sector's LODs
func add_lods(p_lods: Array):
	for lod in p_lods:
		$LODs.add_child(lod)
		self.m_lods.append(lod as SectorLOD)


## Get this sector's LODs.
func get_lods() -> Array:
	return m_lods


## Sets the collision polygon used for mouse interaction
func set_collision_shape(shape: Shape3D):
	self.shape = shape
	var border = shape.points
	for p in border:
		center += p
	center /= border.size()


func set_building(new_building):
	building = new_building
	add_child(building)


# Called from TerrainGrid's _on_input_event when an inputevent happens to this shape
func grid_area_input_event(_camera, event, p_position, _normal, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var info = "%s is neighbors with " % name
			for edge in get_lods()[0].edges:
				info += str(edge.neighbor) + " "
			info += " | LOD=%d adjacent LODS " % current_lod
			var material := get_lods()[0].material_override as ShaderMaterial
			var sector_lods = material.get_shader_parameter("sector_lods")
			for edge in get_lods()[0].edges:
				info += str(sector_lods[edge.neighbor]) + " "
			print(info)
			# Position is emitted as world coordinates
			# TEST 
			#exploded.emit(p_position)


func get_planet():
	return get_parent().planet
