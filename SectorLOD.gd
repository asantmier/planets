# INFO
# Each SectorLOD is a variation of the mesh for its sector with a different
# level of detail. They are all passed into the displacement shader together.
# The edges are important for defining which sectors are adjacent to this one
# and are also used to dynamically morph this LODs edge vertices to match up
# with those of adjacent sectors. A stitch table is used to define what position
# a vertex should move to based on the LOD of its adjacent sector. Because this
# is all done in a vertex shader and we don't want a million instances of a
# material nor can we use SSBOs or something to bypass the GPU buffer size limit
# we store this information as extra per-vertex arrays in the mesh. For example,
# adjacency data is stored in UV2.x and stitch positions for each adjacent LOD
# are stored in CUSTOM0-3. If more data is ever needed, any way to store floats
# in the mesh can be used.

class_name SectorLOD extends MeshInstance3D
# TODO Same as edge, probably doesn't need to be in global namespace

const TIMING := false
static var avg_times := [0.0,0.0,0.0,0.0,0.0]
static var avg_math_time := [0.0,0.0,0.0,0.0,0.0]
static var time_counter := [0,0,0,0,0]

# the lod level https://github.com/godot-extended-libraries/godot-lod/blob/master/addons/lod/lod_spatial.gd
var level: int # INFO if level is 0 do not use any of this data
@export var begin: float
@export var begin_margin: float
@export var end: float
@export var end_margin: float

var edges: Array[Edge]

var vertex_count : int

var _new_surface_0: Array
var _new_modification_id_0 := -1
var _new_surface_1: Array
var _new_modification_id_1 := -1

var _active_thread_buffer := 0

var _mutex_commit_shit_0 : Mutex
var _mutex_commit_shit_1 : Mutex
var _mutex_thread_results : Mutex

var last_modified_id := -1 # ID of the last crater that updated the surface
var default_surface: Array # Holds a reference to the default surface array so subthreads can access what they need


func _ready():
	_mutex_commit_shit_0 = Mutex.new()
	_mutex_commit_shit_1 = Mutex.new()
	_mutex_thread_results = Mutex.new()
	#cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Properly sets up everything in the right order
func setup(surface_array: Array, p_level: int, p_material: ShaderMaterial, p_edges: Array[Edge] = []) -> void:
	vertex_count = surface_array[Mesh.ARRAY_VERTEX].size()
	self.level = p_level
	var adjacency
	if level > 0:
		self.edges = p_edges
		adjacency = _build_adjacency_arrays()
	material_override = p_material
	set_instance_shader_parameter("lod", level)
	
	var dummy = PackedFloat32Array()
	dummy.resize(surface_array[Mesh.ARRAY_VERTEX].size() * 3)
	surface_array[Mesh.ARRAY_CUSTOM0] = dummy
	surface_array[Mesh.ARRAY_CUSTOM1] = dummy
	surface_array[Mesh.ARRAY_CUSTOM2] = dummy
	surface_array[Mesh.ARRAY_CUSTOM3] = dummy
	# UV2 needs to be filled regardless for in place editing, so fill it with dummy data on lod0
	if level == 0:
		var uv_dummy = PackedVector2Array()
		uv_dummy.resize(surface_array[Mesh.ARRAY_VERTEX].size())
		uv_dummy.fill(Vector2(-1, 0))
		surface_array[Mesh.ARRAY_TEX_UV2] = uv_dummy
	else:
		surface_array[Mesh.ARRAY_TEX_UV2] = adjacency
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array, [], {}, 
	 Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT |
	 Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT |
	 Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT |
	 Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
	default_surface = surface_array


## Commits pending changes to the surface array if any
func try_commit_changes() -> void:
	var nid: int
	var sur: Array
	if _active_thread_buffer == 0:
		# DO NOT LOOK AT 0
		var success = _mutex_commit_shit_1.try_lock()
		if not success:
			printerr("MUTEX CLASH!")
		nid = _new_modification_id_1
		if nid > -1:
			sur = _new_surface_1
			_new_modification_id_1 = -1
		#_active_thread_buffer = 1
		_mutex_commit_shit_1.unlock()
	else:
		var success = _mutex_commit_shit_0.try_lock()
		if not success:
			printerr("MUTEX CLASH!")
		nid = _new_modification_id_0
		if nid > -1:
			sur = _new_surface_0
			_new_modification_id_0 = -1
		#_active_thread_buffer = 0
		_mutex_commit_shit_0.unlock()
	if nid > -1:
		last_modified_id = nid
		commit_new_mesh(sur)


## Adjacency Gives a vertex's adjacent sector number or -1 if it is not an edge vertex
## Stored as vector2s so it can be put in UV2. only use x coordinate
func _build_adjacency_arrays() -> PackedVector2Array:
	# Shove into UV2.x
	var adjacency_vec2 = PackedVector2Array()
	adjacency_vec2.resize(vertex_count)
	adjacency_vec2.fill(Vector2(-1, 0))
	for edge: Edge in edges:
		for ev in edge.divisions:
			adjacency_vec2[ev] = Vector2(edge.neighbor, 0)
	return adjacency_vec2
	# This is how you update region (its actually faster for some reason)
	#var format = mesh.surface_get_format(0)
	#var uv_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, RenderingServer.ARRAY_TEX_UV2)
	#var attrib_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
	#adjacency_bytes = conversion.to_byte_array()
	#var jim := PackedByteArray()
	#jim.resize(attrib_stride * vertex_count)
	#for i in range(vertex_count):
		#jim[i * attrib_stride + uv_offset + 0] = adjacency_bytes[i * 8 + 0]
		#jim[i * attrib_stride + uv_offset + 1] = adjacency_bytes[i * 8 + 1]
		#jim[i * attrib_stride + uv_offset + 2] = adjacency_bytes[i * 8 + 2]
		#jim[i * attrib_stride + uv_offset + 3] = adjacency_bytes[i * 8 + 3]
		#jim[i * attrib_stride + uv_offset + 4] = adjacency_bytes[i * 8 + 4]
		#jim[i * attrib_stride + uv_offset + 5] = adjacency_bytes[i * 8 + 5]
		#jim[i * attrib_stride + uv_offset + 6] = adjacency_bytes[i * 8 + 6]
		#jim[i * attrib_stride + uv_offset + 7] = adjacency_bytes[i * 8 + 7]
	#mesh.surface_update_attribute_region(0, 0, jim)
	# This is only called on initialization so mutexes shouldn't be necessary
	#last_surface = mesh.surface_get_arrays(0)


## Returns a list of adjacent sector ids
func get_adjacent_sectors() -> Array:
	var adj = []
	for edge: Edge in edges:
		adj.append(edge.neighbor)
	return adj


## Converts an array of vector3s to a packedfloat32array of their components
func vec3_to_float3(array: Array[Vector3]) -> PackedFloat32Array:
	var out_array := PackedFloat32Array()
	out_array.resize(array.size() * 3)
	for i in range(array.size()):
		out_array[i * 3 + 0] = array[i].x
		out_array[i * 3 + 1] = array[i].y
		out_array[i * 3 + 2] = array[i].z
	return out_array


## Computes a stitch table for a set of vertices
func compute_stitch_array(verts: PackedVector3Array) -> Array:
	var stitch_table := []
	for target_lod_level: int in range(level):
		var coord_array : Array[Vector3]
		coord_array.resize(vertex_count)
		for edge: Edge in edges:
			# Left and right must always be points in common between lod and target lod
			var spacing = pow(2, level - target_lod_level)
			var left = edge.A
			# ALWAYS use A as the origin point. Not doing so is VERY VERY bad
			var right = edge.get_point(spacing, edge.A)
			var counter = 1 # start at 1 because we skip leftmost point (aka corner)
			var jumps = 0
			for intermediate_vtx in edge.divisions:
				if counter == spacing:
					left = right
					right = edge.get_point(spacing * (jumps + 2), edge.A)
					counter = 0
					jumps += 1
				var downsampled_coord = lerp(verts[left], verts[right], counter / float(spacing))
				coord_array[intermediate_vtx] = downsampled_coord
				counter += 1
		stitch_table.append(coord_array)
	assert(stitch_table.size() <= 4 and (stitch_table.size() >= 1 or level == 0))
	return stitch_table


## Precomputes the surface for the stitch array. Modifies the given surface in place.
## Thread safe.
func fast_precompute_lod_stitch_and_surface(verts: PackedVector3Array, norms: PackedVector3Array, crater_id: int):
	# If we were somehow slower than a newer thread, stop here
	if last_modified_id > crater_id or _new_modification_id_0 > crater_id or _new_modification_id_1 > crater_id:
		return
		
	var stitch_table := compute_stitch_array(verts)
	var float_table : Array[PackedFloat32Array]
	for t in stitch_table:
		var out_array := PackedFloat32Array()
		out_array.resize(t.size() * 3)
		for i in range(t.size()):
			out_array[i * 3 + 0] = t[i].x
			out_array[i * 3 + 1] = t[i].y
			out_array[i * 3 + 2] = t[i].z
		float_table.append(out_array)
		#float_table.append(vec3_to_float3(t))

	var surface := default_surface.duplicate()
	# Put into the mesh CUSTOM arrays
	surface[Mesh.ARRAY_VERTEX] = verts
	surface[Mesh.ARRAY_NORMAL] = norms
	
	if float_table.size() > 0:
		# target lod 0
		surface[Mesh.ARRAY_CUSTOM0] = float_table[0]
	if float_table.size() > 1:
		# target lod 1
		surface[Mesh.ARRAY_CUSTOM1] = float_table[1]
	if float_table.size() > 2:
		# target lod 2
		surface[Mesh.ARRAY_CUSTOM2] = float_table[2]
	if float_table.size() > 3:
		# target lod 3
		surface[Mesh.ARRAY_CUSTOM3] = float_table[3]
	
	_mutex_thread_results.lock()
	if crater_id > last_modified_id:
		if _active_thread_buffer == 0:
			_mutex_commit_shit_0.lock()
			var new_buffer = 0
			if crater_id > _new_modification_id_0 and crater_id > _new_modification_id_1:
				_new_surface_0 = surface
				_new_modification_id_0 = crater_id
				new_buffer = 1
			_mutex_commit_shit_0.unlock()
			_active_thread_buffer = new_buffer
		else:
			# We need to use 1
			_mutex_commit_shit_1.lock()
			var new_buffer = 1
			if crater_id > _new_modification_id_0 and crater_id > _new_modification_id_1:
				_new_surface_1 = surface
				_new_modification_id_1 = crater_id
				new_buffer = 0
			_mutex_commit_shit_1.unlock()
			_active_thread_buffer = new_buffer
	_mutex_thread_results.unlock()


## Downsamples vertex positions and ssigns a new vertex and normal array in the process
## Stitch table contains an array for each lod containing the coordinates
## of the edge vertices downsampled to that lod.
func fast_precompute_lod_stitch_array(verts: PackedVector3Array, norms: PackedVector3Array):
	assert(mesh.get_surface_count() == 1)
	var start = Time.get_ticks_usec()
	var stitch_table := compute_stitch_array(verts)
	var float_table : Array[PackedFloat32Array]
	for t in stitch_table:
		float_table.append(vec3_to_float3(t))
		
	# Put into the mesh CUSTOM arrays
	assert(mesh.get_surface_count() == 1)
	var surface = mesh.surface_get_arrays(0)
	surface[Mesh.ARRAY_VERTEX] = verts
	surface[Mesh.ARRAY_NORMAL] = norms
	
	if stitch_table.size() > 0:
		# target lod 0
		surface[Mesh.ARRAY_CUSTOM0] = float_table[0]
	if stitch_table.size() > 1:
		# target lod 1
		surface[Mesh.ARRAY_CUSTOM1] = float_table[1]
	if stitch_table.size() > 2:
		# target lod 2
		surface[Mesh.ARRAY_CUSTOM2] = float_table[2]
	if stitch_table.size() > 3:
		# target lod 3
		surface[Mesh.ARRAY_CUSTOM3] = float_table[3]

	var stitch_end = Time.get_ticks_usec()
	
	commit_new_mesh(surface)
	
	#region Surface update method
	# The new technique doesn't give performance gains until lod 3 but it does save about 1 second,
	# So do the old method on lower lods
	#else:
	## INFO
	## The update region method is really fast for large meshes, but slower for small ones
	## If this was done in C, it would probably be faster for both, but alas
	## Normals and tangents are stored as octahedral uint16 vec2s in the server
	## which is unfortunately impossible to create in GDScript afaik, so this method
	## is impossible currently. In the future it would be worth exploring this area
	## again but using C because the issue here is unexposed capabilities of the
	## engine being required to use these low level functions. 
	## For future reference these functions can be found in 
	## https://github.com/godotengine/godot/blob/fe01776f05b1787b28b4a270d53037a3c25f4ca2/servers/rendering_server.cpp
	## and the following lines of code are an example of how you're supposed to use
	## offsets and strides to write to the buffers
	## https://github.com/godotengine/godot/blob/fe01776f05b1787b28b4a270d53037a3c25f4ca2/scene/3d/sprite_3d.cpp#L241
	## !!!KEEP THE BELOW CODE!!!
	## ITS NOT USEFUL RIGHT NOW B/C THE NORMALS AND TANGENTS ARE BROKEN BUT ITS VERY COMPLICATED AND WORTH KEEPING
		#var byte_table : Array[PackedByteArray]
		#for t in stitch_table:
			#byte_table.append(PackedVector3Array(t).to_byte_array())
		#var format = mesh.surface_get_format(0)
		#
		##mesh.surface_update_vertex_region(0, 0, verts.to_byte_array())
		#var nt_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
		#var n_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, RenderingServer.ARRAY_NORMAL)
		#var t_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, RenderingServer.ARRAY_TANGENT)
		#var vbytes = verts.to_byte_array()
		##var frank := PackedByteArray()
		#vbytes.resize(vbytes.size() + nt_stride * vertex_count)
		#var jimin := PackedVector2Array()
		#jimin.resize(norms.size())
		#var tangents := PackedVector2Array()
		#tangents.resize(norms.size())
		#for i in range(norms.size()):
			#jimin[i] = norms[i].octahedron_encode()
			## No idea how to make clamping work
			#jimin[i].x = clampi(jimin[i].x, 0, 65535)
			#jimin[i].y = clampi(jimin[i].y, 0, 65535)
			#var temp := Vector3(norms[i].z, -norms[i].x, norms[i].y).cross(norms[i].normalized()).normalized()
			#tangents[i] = temp.octahedron_encode()
			## This is in godot's source code so its probably important
			#tangents[i].x = clampi(tangents[i].x, 0, 65535)
			#tangents[i].y = clampi(tangents[i].y, 0, 65535)
			#if tangents[i].x == 0 and tangents[i].y == 1:
				#tangents[i].x = 1
		#var fred := jimin.to_byte_array()
		#var tanbytes := tangents.to_byte_array()
		## Tangent could be done in the compute shader tbh
		#for i in range(vertex_count):
			#vbytes[i * nt_stride + n_offset + 0] = fred[i * 8 + 0]
			#vbytes[i * nt_stride + n_offset + 1] = fred[i * 8 + 1]
			##vbytes[i * nt_stride + n_offset + 2] = fred[i * 8 + 2]
			##vbytes[i * nt_stride + n_offset + 3] = fred[i * 8 + 3]
			#vbytes[i * nt_stride + n_offset + 2] = fred[i * 8 + 4]
			#vbytes[i * nt_stride + n_offset + 3] = fred[i * 8 + 5]
			##vbytes[i * nt_stride + n_offset + 4] = fred[i * 8 + 4]
			##vbytes[i * nt_stride + n_offset + 5] = fred[i * 8 + 5]
			##vbytes[i * nt_stride + n_offset + 6] = fred[i * 8 + 6]
			##vbytes[i * nt_stride + n_offset + 7] = fred[i * 8 + 7]
			#vbytes[i * nt_stride + t_offset + 0] = tanbytes[i * 8 + 0]
			#vbytes[i * nt_stride + t_offset + 1] = tanbytes[i * 8 + 1]
			##vbytes[i * nt_stride + t_offset + 2] = tanbytes[i * 8 + 2]
			##vbytes[i * nt_stride + t_offset + 3] = tanbytes[i * 8 + 3]
			#vbytes[i * nt_stride + n_offset + 2] = tanbytes[i * 8 + 4]
			#vbytes[i * nt_stride + n_offset + 3] = tanbytes[i * 8 + 5]
			##vbytes[i * nt_stride + t_offset + 4] = tanbytes[i * 8 + 4]
			##vbytes[i * nt_stride + t_offset + 5] = tanbytes[i * 8 + 5]
			##vbytes[i * nt_stride + t_offset + 6] = tanbytes[i * 8 + 6]
			##vbytes[i * nt_stride + t_offset + 7] = tanbytes[i * 8 + 7]
		#
		##vbytes.append_array(frank)
		#mesh.surface_update_vertex_region(0, 0, vbytes)
		#
		#var attrib_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
		#var jim := PackedByteArray()
		#jim.resize(attrib_stride * vertex_count)
	#
		#if level != 0:
			#var uv_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, RenderingServer.ARRAY_TEX_UV2)
			#for i in range(vertex_count):
				#jim[i * attrib_stride + uv_offset + 0] = adjacency_bytes[i * 8 + 0]
				#jim[i * attrib_stride + uv_offset + 1] = adjacency_bytes[i * 8 + 1]
				#jim[i * attrib_stride + uv_offset + 2] = adjacency_bytes[i * 8 + 2]
				#jim[i * attrib_stride + uv_offset + 3] = adjacency_bytes[i * 8 + 3]
				#jim[i * attrib_stride + uv_offset + 4] = adjacency_bytes[i * 8 + 4]
				#jim[i * attrib_stride + uv_offset + 5] = adjacency_bytes[i * 8 + 5]
				#jim[i * attrib_stride + uv_offset + 6] = adjacency_bytes[i * 8 + 6]
				#jim[i * attrib_stride + uv_offset + 7] = adjacency_bytes[i * 8 + 7]
		#
		#var c0_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, RenderingServer.ARRAY_CUSTOM0)
		#var c1_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, RenderingServer.ARRAY_CUSTOM1)
		#var c2_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, RenderingServer.ARRAY_CUSTOM2)
		#var c3_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, RenderingServer.ARRAY_CUSTOM3)
		#for i in range(vertex_count):
			#if stitch_table.size() > 0:
				#var dan := byte_table[0]
				#jim[i * attrib_stride + c0_offset + 0] = dan[i * 12 + 0]
				#jim[i * attrib_stride + c0_offset + 1] = dan[i * 12 + 1]
				#jim[i * attrib_stride + c0_offset + 2] = dan[i * 12 + 2]
				#jim[i * attrib_stride + c0_offset + 3] = dan[i * 12 + 3]
				#jim[i * attrib_stride + c0_offset + 4] = dan[i * 12 + 4]
				#jim[i * attrib_stride + c0_offset + 5] = dan[i * 12 + 5]
				#jim[i * attrib_stride + c0_offset + 6] = dan[i * 12 + 6]
				#jim[i * attrib_stride + c0_offset + 7] = dan[i * 12 + 7]
				#jim[i * attrib_stride + c0_offset + 8] = dan[i * 12 + 8]
				#jim[i * attrib_stride + c0_offset + 9] = dan[i * 12 + 9]
				#jim[i * attrib_stride + c0_offset + 10] = dan[i * 12 + 10]
				#jim[i * attrib_stride + c0_offset + 11] = dan[i * 12 + 11]
			#if stitch_table.size() > 1:
				#var dan := byte_table[1]
				#jim[i * attrib_stride + c1_offset + 0] = dan[i * 12 + 0]
				#jim[i * attrib_stride + c1_offset + 1] = dan[i * 12 + 1]
				#jim[i * attrib_stride + c1_offset + 2] = dan[i * 12 + 2]
				#jim[i * attrib_stride + c1_offset + 3] = dan[i * 12 + 3]
				#jim[i * attrib_stride + c1_offset + 4] = dan[i * 12 + 4]
				#jim[i * attrib_stride + c1_offset + 5] = dan[i * 12 + 5]
				#jim[i * attrib_stride + c1_offset + 6] = dan[i * 12 + 6]
				#jim[i * attrib_stride + c1_offset + 7] = dan[i * 12 + 7]
				#jim[i * attrib_stride + c1_offset + 8] = dan[i * 12 + 8]
				#jim[i * attrib_stride + c1_offset + 9] = dan[i * 12 + 9]
				#jim[i * attrib_stride + c1_offset + 10] = dan[i * 12 + 10]
				#jim[i * attrib_stride + c1_offset + 11] = dan[i * 12 + 11]
			#if stitch_table.size() > 2:
				#var dan := byte_table[2]
				#jim[i * attrib_stride + c2_offset + 0] = dan[i * 12 + 0]
				#jim[i * attrib_stride + c2_offset + 1] = dan[i * 12 + 1]
				#jim[i * attrib_stride + c2_offset + 2] = dan[i * 12 + 2]
				#jim[i * attrib_stride + c2_offset + 3] = dan[i * 12 + 3]
				#jim[i * attrib_stride + c2_offset + 4] = dan[i * 12 + 4]
				#jim[i * attrib_stride + c2_offset + 5] = dan[i * 12 + 5]
				#jim[i * attrib_stride + c2_offset + 6] = dan[i * 12 + 6]
				#jim[i * attrib_stride + c2_offset + 7] = dan[i * 12 + 7]
				#jim[i * attrib_stride + c2_offset + 8] = dan[i * 12 + 8]
				#jim[i * attrib_stride + c2_offset + 9] = dan[i * 12 + 9]
				#jim[i * attrib_stride + c2_offset + 10] = dan[i * 12 + 10]
				#jim[i * attrib_stride + c2_offset + 11] = dan[i * 12 + 11]
			#if stitch_table.size() > 3:
				#var dan := byte_table[3]
				#jim[i * attrib_stride + c3_offset + 0] = dan[i * 12 + 0]
				#jim[i * attrib_stride + c3_offset + 1] = dan[i * 12 + 1]
				#jim[i * attrib_stride + c3_offset + 2] = dan[i * 12 + 2]
				#jim[i * attrib_stride + c3_offset + 3] = dan[i * 12 + 3]
				#jim[i * attrib_stride + c3_offset + 4] = dan[i * 12 + 4]
				#jim[i * attrib_stride + c3_offset + 5] = dan[i * 12 + 5]
				#jim[i * attrib_stride + c3_offset + 6] = dan[i * 12 + 6]
				#jim[i * attrib_stride + c3_offset + 7] = dan[i * 12 + 7]
				#jim[i * attrib_stride + c3_offset + 8] = dan[i * 12 + 8]
				#jim[i * attrib_stride + c3_offset + 9] = dan[i * 12 + 9]
				#jim[i * attrib_stride + c3_offset + 10] = dan[i * 12 + 10]
				#jim[i * attrib_stride + c3_offset + 11] = dan[i * 12 + 11]
		#
		#mesh.surface_update_attribute_region(0, 0, jim)
	#endregion

	var end = Time.get_ticks_usec()
	assert(mesh.get_surface_count() == 1)
	if TIMING:
		time_counter[level] += 1
		avg_times[level] = avg_times[level] * (time_counter[level] - 1) / time_counter[level] + (end - start) / time_counter[level]
		avg_math_time[level] = avg_math_time[level] * (time_counter[level] - 1) / time_counter[level] + (stitch_end - start) / time_counter[level]
		print("Average stitching times: %s, math only: %s" % [avg_times, avg_math_time])


## Sends new surface data to the mesh with correct formatting
func commit_new_mesh(surface):
	var format = mesh.surface_get_format(0)
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface, [], {}, format |
	 Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT |
	 Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT |
	 Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT |
	 Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
