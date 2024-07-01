extends Area3D

# It would probably be wise to divide the planet's surface into submeshes and displace individual submeshes
# during gameplay, physical displacement would only occur occasionally to small parts of the planet
# so being able to modify the entire thing at once is entirely unnecessary
# all this stuff should eventually go in C or a computer shader anyway, but try to avoid if possible
# even for the gpu, doing all those mesh calculations as inefficiently as i'll program them is hard work
# a compute shader can be called at will, so we could run the displacement on the gpu and the rest here
#
# submeshes could potentially be divided at each hexagon if we use the goldberg sphere as the basis for the
# planet's shape as opposed to a geodesic sphere
#
# go follow https://www.youtube.com/watch?v=lctXaT9pxA0&t=302s and use compute shaders
# Next step: Make a second sphere for the ocean and shade it like sebastian
# Alternatives:
#         - Check sector properties (mountain, ocean, biome, etc)
#         - !!!!! Explosions to displace terrain !!!!!!!!!!! DO THIS NEXT
# We can probably do the entire displace() function in a separate thread, that way that thread
# can wait on RenderingDevice.sync() while the main thread does its thing. then it can set a flag
# with a mutex that the main thread can check for to update the mesh when it's done.
# Do HLODs for lod since the arraymesh lod feature doesn't seem to work.
# Generate lod variations of the icosphere then use those to generate variations of the displaced sphere
# The use visibility range to switch between them.
# This will run like ass at first but once we divide the planet up into hexes it should be alright
# TODO consider adding more invocations
# TODO cleanup that threading code
# TODO try making a smaller planet. This would require changing several hardcoded values and having
# a way to toggle between them on load
# TODO per explosion settings (big explosions may be unoptimized)
# TODO potentially limit executions per frame based on elapsed time
# TODO identify each terrain grid by a unique ID and mark it in every message to see why i can only do explosions on
# one terrain grid at a time

signal sector_input(camera, event, position, normal, sector)

# Beleive it or not the data we're running is so simple that changing this does nothing
const INVOCATION_SIZE := 512
const EXPLODE_INVOCATION_SIZE := 512
const SAVE := false
const TIMING := true
# WARNING CHANGE THESE IF THEY EVER CHANGE IN THE SHADER
# WARNING RAISING THIS LIMIT IS LAG HELL. IF THIS ISN'T SUFFICIENT, SWAP TO A DECAL SYSTEM
const NUM_CRATERS := 200
const CRATER_PROCESSORS := 4
#static var global_id := 0
var id : int

# Helper variable for turrets
@export var planet_path: NodePath
@onready var planet = get_node(planet_path)

#region Compute shader arguments
@export_group("Crater Settings")
@export var num_craters := 1
@export var radius_min := 0.0
@export var radius_max := 0.05
@export var rim_width := 0.0
@export var rim_steepness := 0.3
@export var smoothness := 0.0
@export_range(0, 1) var size_distribution := 0.0
@export_group("Ridge Noise")
@export var r_num_layers := 4
@export var r_lacunarity := 5.0
@export var r_persistence := 0.5
@export var r_scale := 2.0
@export var r_power := 3.0
@export var r_elevation := 0.0
@export var r_gain := 1.0
@export var r_vertical_shift := 0.0
@export var r_peak_smoothing := 1.5
@export var r_offset := Vector3.ZERO
@export_group("Shape Noise")
@export var s_num_layers := 3
@export var s_lacunarity := 2.0
@export var s_persistence := 0.5
@export var s_scale := 2.0
@export var s_elevation := 0.0
@export var s_vertical_shift := 0.0
@export var s_offset := Vector3.ZERO
@export_group("Detail Ridge Noise")
@export var det_r_num_layers := 6
@export var det_r_lacunarity := 5.0
@export var det_r_persistence := 0.5
@export var det_r_scale := 2.0
@export var det_r_power := 3.0
@export var det_r_elevation := 0.0
@export var det_r_gain := 1.0
@export var det_r_vertical_shift := 0.0
@export var det_r_offset := Vector3.ZERO
@export_group("Detail Shape Noise")
@export var det_s_num_layers := 5
@export var det_s_lacunarity := 2.0
@export var det_s_persistence := 0.5
@export var det_s_scale := 2.0
@export var det_s_elevation := 0.0
@export var det_s_vertical_shift := 0.0
@export var det_s_offset := Vector3.ZERO
@export_group("Earth Settings")
@export var ocean_floor_depth := 0.0
@export var ocean_floor_smoothing := 0.5
@export var ocean_depth_multiplier := 1.0
@export var mountain_blend := 0.5
@export_group("Continent Noise")
@export var continent_num_layers := 5
@export var continent_lacunarity := 2.0
@export var continent_persistence := 0.5
@export var continent_scale := 2.0
@export var continent_elevation := 0.0
@export var continent_vertical_shift := 0.0
@export var continent_offset := Vector3.ZERO
@export_group("Mountain Noise")
@export var mountain_num_layers := 6
@export var mountain_lacunarity := 5.0
@export var mountain_persistence := 0.5
@export var mountain_scale := 2.0
@export var mountain_power := 3.0
@export var mountain_elevation := 0.0
@export var mountain_gain := 1.0
@export var mountain_vertical_shift := 0.0
@export var mountain_offset := Vector3.ZERO
@export_group("Mountain Mask Noise")
@export var mask_num_layers := 5
@export var mask_lacunarity := 2.0
@export var mask_persistence := 0.5
@export var mask_scale := 2.0
@export var mask_elevation := 0.0
@export var mask_vertical_shift := 0.0
@export var mask_offset := Vector3.ZERO
@export_group("")
# This is an offset used for normal sampling
@export var d := 0.01
@export var ridge_smoothing_offset := 0.01
#endregion

var default_surface: Array
var sector_count: int
var lod_count: int
var lod_vertex_count: Array[int]
var sector_vertex_count: int
var v_count: int

var rd: RenderingDevice

var shader: RID
var base_uniform_set: RID
var mesh_out_uniform_set : RID
var v_out_buffer : RID
var n_out_buffer : RID

var avg_time_norm_pass := 0.0
var avg_time_gpu := 0.0
var avg_time_displace := 0.0
var avg_cycles := 0.0

# Stuff for handling craters
var terrain_material : ShaderMaterial
var craters_length := 0
var base_verts_bytes: PackedByteArray # The vertex array from default surface

var crater_processor_man: ProcessorManager
var craters_to_process_deferred: Array[Crater] # List of craters that need to be processed
var craters_ready_to_compute_queue: Array[Crater] # List of all craters that are ready for the compute step
var mutex_craters_compute: Mutex
var craters_to_prep: Array[Crater]
var mutex_craters_prep: Mutex
var crater_prep_thread: Thread # Used to prepare crater for the compute shader
var semaphore_crater_prep: Semaphore
var exit_thread := false
var mutex_exit : Mutex
var collate_worker_threads : Array[int]
var sector_worker_threads : Array[int]

# Explosion crater default settings
@export var global_radius := 0.05
@export var global_floor_height := -0.1
@export var global_rim_width := 0.6
@export var global_rim_steepness := 0.35
@export var global_max_results := 100 # If some sectors are not getting updated properly, increase this number

# loading screen stuff
var Loading = preload("res://LoadingBox.gd")

## Manages several GPU rendering devices
class ProcessorManager:
	var processors: Array[Processor]
	var processing: Array[bool]
	var count: int
	var _shader_spirv: RDShaderSPIRV
	var _free: int
	
	func _init(spirv: RDShaderSPIRV):
		_shader_spirv = spirv
		count = CRATER_PROCESSORS
		processors.resize(count)
		processing.resize(count)
		processing.fill(false)
		_free = processing.size()
		for i in range(count):
			var crd := RenderingServer.create_local_rendering_device()
			var c_shader := crd.shader_create_from_spirv(spirv)
			processors[i] = Processor.new(crd, c_shader)
	
	## Return number of free processors
	func free_processors() -> int:
		return _free
	
	## Returns if there are free processors
	func has_free() -> bool:
		return _free > 0
	
	## Returns if there are running processors
	func has_running() -> bool:
		return _free < count
	
	## Returns a list of currently running processors
	func get_running_processors() -> Array[Processor]:
		var running: Array[Processor]
		for i in range(count):
			if processing[i]:
				running.append(processors[i])
		return running
	
	## Returns a free processor and marks it as in use or null if no free processors
	func rent_processor(crater: Crater) -> Processor:
		var _old_free = _free
		var out = null
		for i in range(count):
			if !processing[i]:
				processing[i] = true
				_free -= 1
				out = processors[i]
				out.crater = crater
				break
		assert(_free == _old_free - 1 or out == null, "Processor did not get rented properly!")
		debug()
		return out
	
	## Sets the processor as free
	func return_processor(old: Processor) -> void:
		var _old_free = _free
		for i in range(count):
			if processors[i] == old:
				processing[i] = false
				_free += 1
				break
		assert(_free == _old_free + 1, "Processor did not get returned properly!")
		debug()
	
	func debug():
		print("GPU Processors | %d free, %d running." % [_free, count - _free])


## Holds data about a single GPU rendering device
class Processor:
	var rd: RenderingDevice
	var shader: RID
	var crater: Crater
	var exploded_v_count: int
	var vertex_buffer: RID
	var normal_buffer: RID
	var rids: Array[RID]
	var gpu_start_time: int 
	var gpu_end_time: int
	
	func _init(device: RenderingDevice, shader_rid: RID) -> void:
		rd = device
		shader = shader_rid
	
	# Frees up all RIDs in the array
	func free_rids():
		for rid: RID in rids:
			rd.free_rid(rid)
		rids.clear()


# Called when the node enters the scene tree for the first time.
func _ready():
	#id = global_id
	#global_id += 1
	# Basically just a bunch of initialization for crater handling
	mutex_craters_compute = Mutex.new()
	mutex_craters_prep = Mutex.new()
	semaphore_crater_prep = Semaphore.new()
	exit_thread = false
	mutex_exit = Mutex.new()
	
	crater_prep_thread = Thread.new()
	crater_prep_thread.start(_crater_prep_base_array_thread)
	
	# Crater device/shader pool
	var c_shader_file := load("res://Planet/explode_deform.glsl")
	var c_shader_spirv: RDShaderSPIRV = c_shader_file.get_spirv()
	crater_processor_man = ProcessorManager.new(c_shader_spirv)
	
	if not SAVE:
		print("Saving is disabled for terrain grid!")


func _process(delta):
	# Run the crater processing function at the end of each frame
	call_deferred("process_crater_queue")
	
	# Try to clear up any running worker threads
	while not collate_worker_threads.is_empty() and WorkerThreadPool.is_task_completed(collate_worker_threads.front()):
		WorkerThreadPool.wait_for_task_completion(collate_worker_threads.pop_front())
	while not sector_worker_threads.is_empty() and WorkerThreadPool.is_task_completed(sector_worker_threads.front()):
		WorkerThreadPool.wait_for_task_completion(sector_worker_threads.pop_front())
	
	# WARNING Waiting for just one frame for the GPU to finish should be alright
	# but increase frame delay if this leads to weird performance
	# Handle running GPU processors
	if crater_processor_man.has_running():
		for processor in crater_processor_man.get_running_processors():
			print("Retreiving processor data on frame #%d" % get_tree().get_frame())
			var crater = processor.crater
			var c_device = processor.rd
			var c_shader = processor.shader
			var vertex_bytes_out: PackedByteArray
			var normal_bytes_out: PackedByteArray
			var results = retreive_crater(processor)
			vertex_bytes_out = results[0]
			normal_bytes_out = results[1]
			var exploded_v_count = processor.exploded_v_count
			# Free processor
			crater_processor_man.return_processor(processor)
			# Start new thread to process results
			var callable := _crater_collate_data_thread.bind(vertex_bytes_out, normal_bytes_out, exploded_v_count, crater)
			var worker_id = WorkerThreadPool.add_task(callable, true, "Crater collate #%d" % crater.id)
			collate_worker_threads.append(worker_id)

	# Try to push craters from the compute queue onto a GPU processor
	while craters_ready_to_compute_queue.size() > 0 and crater_processor_man.has_free():
		print("Starting processor on frame #%d" % get_tree().get_frame())
		mutex_craters_compute.lock()
		var crater = craters_ready_to_compute_queue.pop_front()
		mutex_craters_compute.unlock()
		var processor := crater_processor_man.rent_processor(crater)
		process_crater(processor)


#region Planet creation
## Initialize data for deforming the planet
func data_initialize(sectors_list):	## Create a local rendering device.
	rd = RenderingServer.create_local_rendering_device()
	## Load GLSL shader
	var shader_file := load("res://Planet/deform.glsl")
	## SPIR-V is a standard intermediary language that ports shaders between languages
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	## Creates the actual shader on the device. Returns the resource ID of the shader
	shader = rd.shader_create_from_spirv(shader_spirv)
	
	# Real quick set up crater part of the material
	terrain_material = sectors_list[0].get_lods()[1].material_override as ShaderMaterial
	var default_crater_array = PackedFloat32Array()
	default_crater_array.resize(NUM_CRATERS * 4)
	terrain_material.set_shader_parameter("craters", default_crater_array)
	# Retreive sector information
	sector_count = sectors_list.size()
	lod_count = sectors_list[0].get_lods().size()
	lod_vertex_count.resize(lod_count)
	# stores the number of vertices in each lod mesh
	for i in range(lod_count):
		lod_vertex_count[i] = sectors_list[0].get_lods()[i].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	sector_vertex_count = lod_vertex_count.reduce(func(accum, n): return accum + n)
	# Concatenate all sector mesh data and save into the default surface array
	default_surface = []
	default_surface.resize(Mesh.ARRAY_MAX)
	var compiled_vertex := PackedVector3Array()
	var compiled_normal := PackedVector3Array()
	compiled_vertex.resize(sector_vertex_count * sector_count)
	compiled_normal.resize(sector_vertex_count * sector_count)
	for sector_idx in range(sector_count):
		var sector = sectors_list[sector_idx]
		var current_vector_offset := 0
		var lods = sector.get_lods()
		for lod_idx in range(lod_count):
			var lod_surf = lods[lod_idx].mesh.surface_get_arrays(0)
			for i in range(lod_surf[Mesh.ARRAY_VERTEX].size()):
				var index = sector_idx * sector_vertex_count + current_vector_offset + i
				compiled_vertex[index] = lod_surf[Mesh.ARRAY_VERTEX][i]
				compiled_normal[index] = lod_surf[Mesh.ARRAY_NORMAL][i]
			current_vector_offset += lod_vertex_count[lod_idx]
	default_surface[Mesh.ARRAY_VERTEX] = compiled_vertex
	default_surface[Mesh.ARRAY_NORMAL] = compiled_normal
	
	# Rest of this code should be agnostic, just give it the correct surface input
	v_count = default_surface[Mesh.ARRAY_VERTEX].size()
	print("Verts: %d (%d invocations)" % [v_count, ceil(v_count / float(INVOCATION_SIZE))])
	# Since the shape of the planet is determined at the start, we can put that in its own set and never modify it to save CPU ops
	# Because otherwise we have to data convert every time
	# Put all Vector3 data in Color (equi. Vector4) arrays
	var verts = default_surface[Mesh.ARRAY_VERTEX]
	var verts_vec4 := PackedColorArray()
	# Fill the end of the arraay with bogus data that we don't care about just so that it fills the last workgroup
	verts_vec4.resize(verts.size() + (v_count % INVOCATION_SIZE))
	for i in range(verts.size()):
		verts_vec4[i] = Color(verts[i].x, verts[i].y, verts[i].z, 0)
	var verts4_bytes := verts_vec4.to_byte_array()
	base_verts_bytes = verts4_bytes
	
	var v_in_buffer := rd.storage_buffer_create(verts4_bytes.size(), verts4_bytes)
	var v_uniform := RDUniform.new()
	v_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	v_uniform.binding = 0
	v_uniform.add_id(v_in_buffer)
	base_uniform_set = rd.uniform_set_create([v_uniform], shader, 0)
	
	# Set up blank mesh retrun buffers
	# Send blank mesh buffers to shader
	var verts_out_vec4 := PackedColorArray()
	# IMPORTANT we need the mesh arrays to have bogey data to fill the rest of the invokations on the last workgroup
	verts_out_vec4.resize(verts.size() + (v_count % INVOCATION_SIZE))
	var verts4_out_bytes := verts_out_vec4.to_byte_array()
	v_out_buffer = rd.storage_buffer_create(verts4_out_bytes.size(), verts4_out_bytes)
	var v_out_uniform := RDUniform.new()
	v_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	v_out_uniform.binding = 0
	v_out_uniform.add_id(v_out_buffer)
	
	var norms_out_vec4 := PackedColorArray()
	norms_out_vec4.resize(verts.size() + (v_count % INVOCATION_SIZE))
	var norms4_out_bytes := norms_out_vec4.to_byte_array()
	n_out_buffer = rd.storage_buffer_create(norms4_out_bytes.size(), norms4_out_bytes)
	var n_out_uniform := RDUniform.new()
	n_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	n_out_uniform.binding = 1
	n_out_uniform.add_id(n_out_buffer)
	
	mesh_out_uniform_set = rd.uniform_set_create([v_out_uniform, n_out_uniform], shader, 1)
	
	#var time_start = Time.get_ticks_usec()
	#if SAVE:
		## TODO this doesn't do anything
		## ResourceSaver.FLAG_COMPRESS argument doesn't seem do change the file size and takes twice as long
		#var scene = PackedScene.new()
		#scene.pack(self)
		#ResourceSaver.save(scene, "res://terraintest.tscn")
	#var time_end = Time.get_ticks_usec()
	#if TIMING:
		#print("Saving mesh took %d microseconds" % (time_end - time_start))
	
	# !!!! EXPLOSION SETUP !!!!
	# Connect signals from sectors to grid
	for sector in sectors_list:
		sector.connect("exploded", _on_sector_exploded)
	
	# Finally do displacement
	Loading.state = Loading.DISPLACEMENT
	get_tree().process_frame.connect(displace.bind(sectors_list), CONNECT_ONE_SHOT)
	#displace(sectors_list)


func random_on_unit_sphere () -> Vector3:
	return Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)).normalized()


func bias_function(x: float, bias: float) -> float:
	var k := pow(1 - bias, 3)
	return (x * k) / (x * k - x + 1)


## Send arguments to planet displacement compute shader
func displace(sectors_list):
	avg_cycles += 1
	var displace_time_start = Time.get_ticks_usec()
	seed("test".hash())
	
	# Send control variables to shader
	var settings_array := PackedFloat32Array([
		d, ridge_smoothing_offset,
		rim_width, rim_steepness, smoothness, num_craters,
		r_num_layers, r_scale, r_persistence, r_elevation, r_offset.x, r_offset.y, r_offset.z, r_lacunarity, r_power, r_gain, r_vertical_shift, r_peak_smoothing,
		s_num_layers, s_scale, s_persistence, s_elevation, s_offset.x, s_offset.y, s_offset.z, s_lacunarity, s_vertical_shift,
		det_r_num_layers, det_r_scale, det_r_persistence, det_r_elevation, det_r_offset.x, det_r_offset.y, det_r_offset.z, det_r_lacunarity, det_r_power, det_r_gain, det_r_vertical_shift,
		det_s_num_layers, det_s_scale, det_s_persistence, det_s_elevation, det_s_offset.x, det_s_offset.y, det_s_offset.z, det_s_lacunarity, det_s_vertical_shift,
		continent_num_layers, continent_scale, continent_persistence, continent_elevation, continent_offset.x, continent_offset.y, continent_offset.z, continent_lacunarity, continent_vertical_shift,
		ocean_floor_depth, ocean_floor_smoothing, ocean_depth_multiplier,
		mountain_num_layers, mountain_scale, mountain_persistence, mountain_elevation, mountain_offset.x, mountain_offset.y, mountain_offset.z, mountain_lacunarity, mountain_power, mountain_gain, mountain_vertical_shift,
		mask_num_layers, mask_scale, mask_persistence, mask_elevation, mask_offset.x, mask_offset.y, mask_offset.z, mask_lacunarity, mask_vertical_shift,
		mountain_blend
		])
		
	var settings_bytes := settings_array.to_byte_array()
	var settings_buffer := rd.storage_buffer_create(settings_bytes.size(), settings_bytes)
	var settings_uniform := RDUniform.new()
	settings_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	settings_uniform.binding = 0
	settings_uniform.add_id(settings_buffer)
	
	var craters_array := PackedColorArray()
	# If there are no craters, fill the array with nothing so that we can still make a buffer with it
	if num_craters == 0:
		craters_array.resize(1)
	for i in range(num_craters):
		var center := random_on_unit_sphere()
		var t := bias_function(randf(), size_distribution)
		var radius := lerpf(radius_min, radius_max, t)
		var floor_height := randf_range(-1.0, -0.1)
		craters_array.append(Color(center.x, center.y, center.z, radius))
		craters_array.append(Color(floor_height, 0, 0, 0))
	var craters_bytes := craters_array.to_byte_array()
	var craters_buffer := rd.storage_buffer_create(craters_bytes.size(), craters_bytes)
	var craters_uniform := RDUniform.new()
	craters_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	craters_uniform.binding = 1
	craters_uniform.add_id(craters_buffer)
	
	var settings_uniform_set := rd.uniform_set_create([settings_uniform, craters_uniform], shader, 2)
	
	## Create a compute pipeline for the shader. Returns an RID again
	var pipeline := rd.compute_pipeline_create(shader)
	## Begin a compute list. Returns an RID again
	var compute_list := rd.compute_list_begin()
	## Binds compute pipeline with compute list
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	# Bind the uniform set we made to the compute list. Third argument is the set index
	rd.compute_list_bind_uniform_set(compute_list, base_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, mesh_out_uniform_set, 1)
	#rd.compute_list_bind_uniform_set(compute_list, freq_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, settings_uniform_set, 2)
	## Dispatch the compute list. Last three arguments are workgroups
	rd.compute_list_dispatch(compute_list, ceil(v_count / float(INVOCATION_SIZE)), 1, 1)
	## End defining compute list
	rd.compute_list_end()
	
	
	var gpu_time_start = Time.get_ticks_usec()
	## Submit to GPU and wait for sync
	rd.submit()
	
	# Increment loading state to inform player
	Loading.state = Loading.COMMITTING
	get_tree().process_frame.connect(retreive_displace_results.bind(sectors_list, gpu_time_start), CONNECT_ONE_SHOT)
	
	var displace_time_end = Time.get_ticks_usec()
	avg_time_displace = avg_time_displace * (avg_cycles - 1) / avg_cycles + (displace_time_end - displace_time_start) / avg_cycles
	if TIMING:
		print("displace() took %d microseconds (%dus)" % [(displace_time_end - displace_time_start), avg_time_displace])


## Get results from planet displacement compute shader and apply them
func retreive_displace_results(sectors_list, gpu_time_start):
	var time_start = Time.get_ticks_usec()
	## Normally we would let the GPU work in parallel but we want the results now
	rd.sync()
	var gpu_time_end = Time.get_ticks_usec()
	avg_time_gpu = avg_time_gpu * (avg_cycles - 1) / avg_cycles + (gpu_time_end - gpu_time_start) / avg_cycles
	if TIMING:
		print("GPU took %d microseconds (%dus)" % [(gpu_time_end - gpu_time_start), avg_time_gpu])

	# Retreive mesh data
	# Vertex
	var verts4_output_bytes := rd.buffer_get_data(v_out_buffer)
	var verts4_output := verts4_output_bytes.to_float32_array()
	var verts_output := PackedVector3Array()
	verts_output.resize(v_count)
	for i in range(verts_output.size()):
		verts_output[i] = Vector3(verts4_output[i * 4], verts4_output[i * 4 + 1], verts4_output[i * 4 + 2])
	
	# Normal
	var norms4_output_bytes := rd.buffer_get_data(n_out_buffer)
	var norms4_output := norms4_output_bytes.to_float32_array()
	var norms_output := PackedVector3Array()
	norms_output.resize(v_count)
	for i in range(norms_output.size()):
		norms_output[i] = Vector3(norms4_output[i * 4], norms4_output[i * 4 + 1], norms4_output[i * 4 + 2])
	
	# Copy sector mesh data into the default surface array
	for sector_idx in range(sector_count):
		var sector := sectors_list[sector_idx] as Sector
		var lods = sector.get_lods()
		var off := sector_idx * sector_vertex_count
		for lod_idx in range(lod_count):
			var lod := lods[lod_idx] as SectorLOD
			var lod_vcount = lod.mesh.surface_get_array_len(0)
			var verts := verts_output.slice(off, off + lod_vcount)
			var norms := norms_output.slice(off, off + lod_vcount)
			off += lod_vertex_count[lod_idx]
			# We then need to compute the stitch data on the lod
			lod.fast_precompute_lod_stitch_array(verts, norms)
	
	# TODO we probably need to free RID's made in this function now.
	# In fact, it might be a good idea to not recreate all these buffers and reuse them between calls instead
	# TODO Experiment with RenderingDevice.get_memory_usage()
	# Increment loading state to inform player
	Loading.state = Loading.STATE_MAX
	
	var time_end = Time.get_ticks_usec()
	if TIMING:
		print("displace() retreival took %d microseconds" % [(time_end - time_start)])
#endregion 


#region Crater processing
## Processes the list of craters that were queued up this frame
func process_crater_queue():
	if craters_to_process_deferred.size() == 0: 
		return
	
	# Filter out craters that cover the same sectors as another, so that we only
	# process the craters that we need to. e.g. two craters that both cover
	# sectors 1 2 3 should be merged
	var final_craters_list := []
	for k in range(craters_to_process_deferred.size()):
		var crater = craters_to_process_deferred[k]
		var duplicate = false
		for i in range(k + 1, craters_to_process_deferred.size()):
			var other = craters_to_process_deferred[i]
			assert(!crater.equals(other))
			if other.affected_sectors.has_all(crater.affected_sectors.keys()):
				duplicate = true
				break
		if !duplicate:
			final_craters_list.append(crater)
	# TODO in addition to getting rid of craters that are subsets of other craters
	# we should tell craters not to process sectors that other craters in the
	# same batch are also processing.
	# Better yet, test if there is an advantage to processing all sectors
	# at once instead of going by craters
	
	# Send the processed list of craters to the prep thread
	mutex_craters_prep.lock()
	craters_to_prep.append_array(final_craters_list)
	mutex_craters_prep.unlock()
	for i in range(final_craters_list.size()):
		semaphore_crater_prep.post()
	
	# !VERY IMPORTANT! Clear the queue
	craters_to_process_deferred.clear()


## Producer-consumer thread that takes craters and creates base arrays for use
## in the compute shader.
func _crater_prep_base_array_thread():
	while true:
		# Basic consumer thread stuff
		semaphore_crater_prep.wait()
		
		mutex_exit.lock()
		var should_exit = exit_thread
		mutex_exit.unlock()
		
		if should_exit:
			break

		# Actual content
		mutex_craters_prep.lock()
		var crater := craters_to_prep.pop_front() as Crater
		mutex_craters_prep.unlock()
		
		#  Create a base array with all of its hit sectors
		var base_bytes = PackedByteArray()
		for sector in crater.affected_sectors.values():
			base_bytes.append_array(base_verts_bytes.slice((sector.sector_number * sector_vertex_count) * 4 * 4, ((sector.sector_number + 1) * sector_vertex_count) * 4 * 4))
		# Make sure the array is the right size for the compute shader (TODO this might be unnecessary)
		var exploded_v_count := sector_vertex_count * crater.affected_sectors.size()
		base_bytes.resize((exploded_v_count + (exploded_v_count % INVOCATION_SIZE)) * 4 * 4)
		
		# WARNING this isn't thread safe, but it shouldn't cause problems since
		# there is only one instance of this thread and this is the only place
		# this method is called
		crater.set_base_bytes(base_bytes)
		
		# Add prepared crater to the queue of craters that need to go to the GPU
		mutex_craters_compute.lock()
		craters_ready_to_compute_queue.push_back(crater)
		mutex_craters_compute.unlock()


## Interprets all the data from the GPU and sends it to the sectors for committing
func _crater_collate_data_thread(vertex_bytes: PackedByteArray, normal_bytes: PackedByteArray, exploded_v_count: int, crater_data: Crater):
	var hit_sectors := crater_data.affected_sectors.values()
	
	var time_start = Time.get_ticks_usec()
	
	var verts4_output := vertex_bytes.to_float32_array()
	var verts_output := PackedVector3Array()
	verts_output.resize(exploded_v_count)
	for i in range(verts_output.size()):
		verts_output[i] = Vector3(verts4_output[i * 4], verts4_output[i * 4 + 1], verts4_output[i * 4 + 2])
	
	var norms4_output := normal_bytes.to_float32_array()
	var norms_output := PackedVector3Array()
	norms_output.resize(exploded_v_count)
	for i in range(norms_output.size()):
		norms_output[i] = Vector3(norms4_output[i * 4], norms4_output[i * 4 + 1], norms4_output[i * 4 + 2])
	
	var time_end = Time.get_ticks_usec()
	# significant and threadable
	print("vec3ifying took %dus" % (time_end - time_start))
	time_start = Time.get_ticks_usec()
	
	# Send mesh data to sectors
	for sector_idx : int in range(hit_sectors.size()):
		var sector := hit_sectors[sector_idx] as Sector
		# Don't compute for this sector if a newer crater has already done so
		if sector.last_modified_by_crater_id > crater_data.id:
			continue
		var lods := sector.get_lods()
		var off := sector_idx * sector_vertex_count
		var sector_lod_verts : Array[PackedVector3Array]
		var sector_lod_norms : Array[PackedVector3Array]
		for lod_idx : int in range(lod_count):
			var lod := lods[lod_idx] as SectorLOD
			var lod_vcount = lod.vertex_count
			# TODO i could send this data to the lods, and they could assign it in their free time
			# with priority based on whether they are visible
			var verts := verts_output.slice(off, off + lod_vcount)
			var norms := norms_output.slice(off, off + lod_vcount)
			off += lod_vertex_count[lod_idx]
			# We then need to compute the stitch data on the lod
			#lod.fast_precompute_lod_stitch_array(verts, norms)
			sector_lod_verts.append(verts)
			sector_lod_norms.append(norms)
		var worker_id = sector.queue_new_mesh_data(sector_lod_verts, sector_lod_norms, crater_data.id)
		sector_worker_threads.append(worker_id)
	
	time_end = Time.get_ticks_usec()
	# EXTREMELY SLOW!
	print("Collating meshes took %dus" % (time_end - time_start))


## Send crater data to GPU on the specified processor
func process_crater(processor: Processor):
	var crater_data := processor.crater
	var device := processor.rd
	var c_shader := processor.shader
	
	var time_start = Time.get_ticks_usec()
	var hit_sectors := crater_data.affected_sectors.values()
	
	# Get a list of all the craters in the sectors in this crater
	var craters_to_process: Dictionary
	for sec: Sector in hit_sectors:
		craters_to_process.merge(sec.craters)
	
	# Make a buffer out of all of them
	var craters_array := PackedColorArray()
	print("Relevant craters: %d" % craters_to_process.size())
	for c: Crater in craters_to_process.values():
		var c_center := c.pos.normalized()
		var c_radius := c.radius
		var c_floor_height := c.floor_height
		var c_rim_width := c.rim_width
		var c_rim_steepness := c.rim_steepness
		craters_array.append(Color(c_center.x, c_center.y, c_center.z, c_radius))
		craters_array.append(Color(c_floor_height, c_rim_width, c_rim_steepness, 0))
	var craters_bytes := craters_array.to_byte_array()
	var craters_buffer := device.storage_buffer_create(craters_bytes.size(), craters_bytes)
	processor.rids.append(craters_buffer)
	var craters_uniform := RDUniform.new()
	craters_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	craters_uniform.binding = 1
	craters_uniform.add_id(craters_buffer)
	
	# Settings buffer
	var settings_array := PackedFloat32Array([
		d, ridge_smoothing_offset,
		rim_width, rim_steepness, smoothness, 
		craters_to_process.size(),
		r_num_layers, r_scale, r_persistence, r_elevation, r_offset.x, r_offset.y, r_offset.z, r_lacunarity, r_power, r_gain, r_vertical_shift, r_peak_smoothing,
		s_num_layers, s_scale, s_persistence, s_elevation, s_offset.x, s_offset.y, s_offset.z, s_lacunarity, s_vertical_shift,
		det_r_num_layers, det_r_scale, det_r_persistence, det_r_elevation, det_r_offset.x, det_r_offset.y, det_r_offset.z, det_r_lacunarity, det_r_power, det_r_gain, det_r_vertical_shift,
		det_s_num_layers, det_s_scale, det_s_persistence, det_s_elevation, det_s_offset.x, det_s_offset.y, det_s_offset.z, det_s_lacunarity, det_s_vertical_shift,
		continent_num_layers, continent_scale, continent_persistence, continent_elevation, continent_offset.x, continent_offset.y, continent_offset.z, continent_lacunarity, continent_vertical_shift,
		ocean_floor_depth, ocean_floor_smoothing, ocean_depth_multiplier,
		mountain_num_layers, mountain_scale, mountain_persistence, mountain_elevation, mountain_offset.x, mountain_offset.y, mountain_offset.z, mountain_lacunarity, mountain_power, mountain_gain, mountain_vertical_shift,
		mask_num_layers, mask_scale, mask_persistence, mask_elevation, mask_offset.x, mask_offset.y, mask_offset.z, mask_lacunarity, mask_vertical_shift,
		mountain_blend
		])
	var settings_bytes := settings_array.to_byte_array()
	var settings_buffer := device.storage_buffer_create(settings_bytes.size(), settings_bytes)
	processor.rids.append(settings_buffer)
	var settings_uniform := RDUniform.new()
	settings_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	settings_uniform.binding = 0
	settings_uniform.add_id(settings_buffer)
	
	var settings_uniform_set := device.uniform_set_create([settings_uniform, craters_uniform], c_shader, 2)
	#processor.rids.append(settings_uniform_set) # for some reason this isn't necessary
	
	var time_end = Time.get_ticks_usec()
	# insignificant
	print("First normal section took %dus" % (time_end - time_start))
	time_start = Time.get_ticks_usec()
	
	var exploded_v_count := sector_vertex_count * hit_sectors.size()
	print("Verts: %d (%d invocations)" % [exploded_v_count, ceil(exploded_v_count / float(EXPLODE_INVOCATION_SIZE))])
	
	# Send mesh data to shader
	# Put all Vector3 data in Color (equi. Vector4) arrays
	var verts_vec4 := PackedColorArray()
	# Fill the end of the array with bogus data that we don't care about just so that it fills the last workgroup
	verts_vec4.resize(exploded_v_count + (exploded_v_count % EXPLODE_INVOCATION_SIZE))
	var verts4_bytes := verts_vec4.to_byte_array()
	var vertex_buffer := device.storage_buffer_create(verts4_bytes.size(), verts4_bytes)
	processor.rids.append(vertex_buffer)
	var v_out_uniform := RDUniform.new()
	v_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	v_out_uniform.binding = 0
	v_out_uniform.add_id(vertex_buffer)
	
	var norms_vec4 := PackedColorArray()
	# Fill the end of the arraay with bogus data that we don't care about just so that it fills the last workgroup
	norms_vec4.resize(exploded_v_count + (exploded_v_count % EXPLODE_INVOCATION_SIZE))
	var norms4_bytes := norms_vec4.to_byte_array()
	var normal_buffer := device.storage_buffer_create(norms4_bytes.size(), norms4_bytes)
	processor.rids.append(normal_buffer)
	var n_out_uniform := RDUniform.new()
	n_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	n_out_uniform.binding = 1
	n_out_uniform.add_id(normal_buffer)
	
	var mesh_uniform_set := device.uniform_set_create([v_out_uniform, n_out_uniform], c_shader, 1)
	#processor.rids.append(mesh_uniform_set)
	
	time_end = Time.get_ticks_usec()
	# slightly significant and threadable
	print("vec4ifying took %dus" % (time_end - time_start))
	time_start = Time.get_ticks_usec()

	var base4_bytes := crater_data.get_and_clear_base_bytes()
	var v_in_buffer := device.storage_buffer_create(base4_bytes.size(), base4_bytes)
	processor.rids.append(v_in_buffer)
	var v_uniform := RDUniform.new()
	v_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	v_uniform.binding = 0
	v_uniform.add_id(v_in_buffer)
	var subset_base_uniform_set = device.uniform_set_create([v_uniform], c_shader, 0)
	#processor.rids.append(subset_base_uniform_set)
	
	time_end = Time.get_ticks_usec()
	# significant and threadable
	print("Base copying took %dus" % (time_end - time_start))
	time_start = Time.get_ticks_usec()
	
	## Create a compute pipeline for the shader. Returns an RID again
	var pipeline := device.compute_pipeline_create(c_shader)
	processor.rids.append(pipeline)
	## Begin a compute list. Returns an RID again
	var compute_list := device.compute_list_begin()
	## Binds compute pipeline with compute list
	device.compute_list_bind_compute_pipeline(compute_list, pipeline)
	# Bind the uniform set we made to the compute list. Thidevice argument is the set index
	device.compute_list_bind_uniform_set(compute_list, subset_base_uniform_set, 0)
	device.compute_list_bind_uniform_set(compute_list, mesh_uniform_set, 1)
	device.compute_list_bind_uniform_set(compute_list, settings_uniform_set, 2)
	## Dispatch the compute list. Last three arguments are workgroups
	device.compute_list_dispatch(compute_list, ceil(exploded_v_count / float(EXPLODE_INVOCATION_SIZE)), 1, 1)
	## End defining compute list
	device.compute_list_end()
	
	device.submit()
	
	# Save device data for later
	processor.exploded_v_count = exploded_v_count
	processor.vertex_buffer = vertex_buffer
	processor.normal_buffer = normal_buffer
	processor.gpu_start_time = Time.get_ticks_usec()


## Retreive compute shader results and returns them as an array [verts, norms]
func retreive_crater(processor: Processor):
	var crater_data := processor.crater
	var device := processor.rd
	var c_shader := processor.shader
	var exploded_v_count := processor.exploded_v_count
	var vertex_buffer := processor.vertex_buffer
	var normal_buffer := processor.normal_buffer
	var hit_sectors := crater_data.affected_sectors.values()
	device.sync()
	processor.gpu_end_time = Time.get_ticks_usec()
	print("Processor GPU took %dus" % (processor.gpu_end_time - processor.gpu_start_time))

	var time_end = Time.get_ticks_usec()
	var time_start = Time.get_ticks_usec()
	# Retreive mesh data
	var verts4_output_bytes := device.buffer_get_data(vertex_buffer)
	var norms4_output_bytes := device.buffer_get_data(normal_buffer)
	
	# Free memory
	processor.free_rids()
	
	return [verts4_output_bytes, norms4_output_bytes]


# TODO
# If too many explosions are happening per frame, prioritize processing ones on
# the planet the player is focused on.
## Called when an explosion creates a crater
func _on_sector_exploded(
	 pos: Vector3,
	 radius: float = global_radius,
	 floor_height: float = global_floor_height,
	 new_rim_width: float = global_rim_width,
	 new_rim_steepness: float = global_rim_steepness):
	
	explode(pos, radius, floor_height, new_rim_width, new_rim_steepness)


# WARNING this has only been tested with pos values on the unit sphere
func explode(
	 pos: Vector3,
	 radius: float = global_radius,
	 floor_height: float = global_floor_height,
	 new_rim_width: float = global_rim_width,
	 new_rim_steepness: float = global_rim_steepness):
	
	var time_start
	var time_end
	
	# Transform to local coordinates
	var local_pos = to_local(pos)

	var max_results := global_max_results
	# We could accumulate these and process them at the end of the frame to
	# avoid looping multiple times
	var random_sector := get_child(0) as Sector
	var params := PhysicsShapeQueryParameters3D.new()
	params.collide_with_areas = true
	params.collide_with_bodies = false
	#params.collision_mask = random_sector.get_collision_area().collision_layer
	params.collision_mask = collision_layer
	var shape := SphereShape3D.new()
	# VERY IMPORTANT! make sure the added rim radius is included in the search!
	# Width is expressed as a percentage of radius
	shape.radius = radius + radius * new_rim_width
	params.shape = shape
	var param_transform := Transform3D()
	param_transform.origin = pos
	params.transform = param_transform
	
	var pdss = get_world_3d().direct_space_state
	var results := pdss.intersect_shape(params, max_results)
	var hit_sector_numbers = []
	var hit_sectors : Array[Sector]
	for intersection in results:
		var owner_id = intersection.collider.shape_find_owner(intersection.shape)
		var uhh = intersection.collider.shape_owner_get_owner(owner_id)
		#var hit_sector := intersection.collider as Sector
		var hit_sector := uhh as Sector
		if hit_sector == null:
			printerr("TerrainGrid explosion query returned a non-sector!")
		hit_sector_numbers.append(hit_sector.sector_number)
		hit_sectors.append(hit_sector)
	print("Explosion on %d at %v (%v) r=%f hit sectors: %s" % [id, pos, local_pos, radius, hit_sector_numbers])
	
	# Shader update
	var craters := terrain_material.get_shader_parameter("craters") as PackedFloat32Array
	#var craters_length := terrain_material.get_shader_parameter("craters_length") as int
	if (craters_length == NUM_CRATERS):
		# TODO overwrite oldest crater if this happens. Think of it as nature reclaiming the destroyed earth
		printerr("Shader has too many craters, overriding!")
	craters[(craters_length % NUM_CRATERS) * 4 + 0] = local_pos.x
	craters[(craters_length % NUM_CRATERS) * 4 + 1] = local_pos.y
	craters[(craters_length % NUM_CRATERS) * 4 + 2] = local_pos.z
	craters[(craters_length % NUM_CRATERS) * 4 + 3] = radius
	craters_length += 1
	terrain_material.set_shader_parameter("craters", craters)
	terrain_material.set_shader_parameter("craters_length", craters_length)
	# Store crater in array for later calls to this function
	var crater_data := Crater.new(local_pos, radius, floor_height, new_rim_width, new_rim_steepness, hit_sectors)

	# Update hit sectors with this crater's id, this way every sector always
	# knows which craters are on it
	for sec : Sector in hit_sectors:
		sec.craters[crater_data.id] = crater_data
	
	# Add crater to queue
	craters_to_process_deferred.append(crater_data)

	# INFO we want to thread by crater as opposed to doing them all at once
	# because big craters will take way longer to process, but we can hide this 
	# with bigger FX
#endregion


func _exit_tree():
	# Clean up our threads
	mutex_exit.lock()
	exit_thread = true
	mutex_exit.unlock()
	
	semaphore_crater_prep.post()
	crater_prep_thread.wait_to_finish()
	
	# Clean up worker threads
	while not collate_worker_threads.is_empty():
		WorkerThreadPool.wait_for_task_completion(collate_worker_threads.pop_front())
	while not sector_worker_threads.is_empty():
		WorkerThreadPool.wait_for_task_completion(sector_worker_threads.pop_front())


func _on_input_event(camera, event, position, normal, shape_idx):
	# Sends the event to the sector whose shape was hit
	var owner_id = shape_find_owner(shape_idx)
	var shape = shape_owner_get_owner(owner_id)
	shape.grid_area_input_event(camera, event, position, normal, shape_idx)
	sector_input.emit(camera, event, position, normal, shape)
