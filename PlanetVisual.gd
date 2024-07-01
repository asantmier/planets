extends MeshInstance3D

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
#         - Run this code multithreaded in the background by not syncing the shader immediately
#         - Generate mesh LODs
#         - Increase vertex complexity based on distance from camera
#         - Do the hex map hover thingamajig
#           - Tell you tile info when you click (mountain, flat, etc)
#         - Camera orbit
#         - Explosions to displace terrain
#         - Progress bar and multithread
# We can probably do the entire displace() function in a separate thread, that way that thread
# can wait on RenderingDevice.sync() while the main thread does its thing. then it can set a flag
# with a mutex that the main thread can check for to update the mesh when it's done.
# Do HLODs for lod since the arraymesh lod feature doesn't seem to work.
# Generate lod variations of the icosphere then use those to generate variations of the displaced sphere
# The use visibility range to switch between them.
# This will run like ass at first but once we divide the planet up into hexes it should be alright

# Beleive it or not the data we're running is so simple that changing this does nothing
const INVOCATION_SIZE := 512
const SAVE := false
const TIMING := true
const UPDATE_EVERY_FRAME := false

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
@export var d := 0.01
@export var ridge_smoothing_offset := 0.01

var default_surface
var v_count
var tri_count

var rd: RenderingDevice

var shader: RID
var base_uniform_set: RID
var v_buffer: RID
var mesh_out_uniform_set : RID
var v_out_buffer : RID
var n_out_buffer : RID

var normal_shader : RID
var index_buffer : RID
var face_out_buffer : RID
var mesh_out_uniform_set_normal_pass : RID

var avg_time_norm_pass := 0.0
var avg_time_gpu := 0.0
var avg_time_displace := 0.0
var avg_cycles := 0.0

# Called when the node enters the scene tree for the first time.
func _ready():
	if not SAVE:
		print("Saving is disabled for planet visuals!")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if UPDATE_EVERY_FRAME:
		displace()
	pass


func data_initialize():	## Create a local rendering device.
	rd = RenderingServer.create_local_rendering_device()
	## Load GLSL shader
	var shader_file := load("res://deform.glsl")
	## SPIR-V is a standard intermediary language that ports shaders between languages
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	## Creates the actual shader on the device. Returns the resource ID of the shader
	shader = rd.shader_create_from_spirv(shader_spirv)
	
	shader_file = load("res://comp_normals.glsl")
	shader_spirv = shader_file.get_spirv()
	normal_shader = rd.shader_create_from_spirv(shader_spirv)
	
	# Now prepare the normal compute shader
	default_surface = mesh.surface_get_arrays(0)
	v_count = default_surface[Mesh.ARRAY_VERTEX].size()
	tri_count = default_surface[Mesh.ARRAY_INDEX].size() / 3
	print("Verts: %d (%d)" % [v_count, ceil(v_count / float(INVOCATION_SIZE))])
	print("Tris: %d (%d)" % [tri_count, ceil(tri_count / float(INVOCATION_SIZE))])
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
	
	v_buffer = rd.storage_buffer_create(verts4_bytes.size(), verts4_bytes)
	var v_uniform := RDUniform.new()
	v_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	v_uniform.binding = 0
	v_uniform.add_id(v_buffer)
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
	
	# And for the normal pass
	# each invocation handles one face, so the number of invocations is
	# number of faces + number of faces % INVOCATION_SIZE
	# invocation index is only used to access the index buffer, so the vertex and normal buffers can be normal sized
	var indices = default_surface[Mesh.ARRAY_INDEX]
	var index_array := PackedInt32Array(indices)
	index_array.resize((tri_count + tri_count % INVOCATION_SIZE) * 3)
	var index_bytes := index_array.to_byte_array()
	index_buffer = rd.storage_buffer_create(index_bytes.size(), index_bytes)
	var index_uniform := RDUniform.new()
	index_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	index_uniform.binding = 1
	index_uniform.add_id(index_buffer)
	
	var face_out_vec4 := PackedColorArray()
	face_out_vec4.resize(tri_count + (tri_count % INVOCATION_SIZE))
	var face4_out_bytes := face_out_vec4.to_byte_array()
	face_out_buffer = rd.storage_buffer_create(face4_out_bytes.size(), face4_out_bytes)
	var face_out_uniform := RDUniform.new()
	face_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	face_out_uniform.binding = 2
	face_out_uniform.add_id(face_out_buffer)
	
	mesh_out_uniform_set_normal_pass = rd.uniform_set_create([v_out_uniform, index_uniform, face_out_uniform], normal_shader, 0)
	# In real gameplay any changes to shape are permanent, so we don't have to recalculate everything
	# Also in real gameplay we can run the shader, wait some frames, and then display the result since there won't be a change necessary instantly every frame
	# So in gameplay just update the mesh on the gpu every once in a while
	# The code the generate the shape can be run once, in here, and then never again
	# While other code to plasticly deform the shape later can permanently write its results to the buffer
	# We only need these complications because of testing
	displace()
	
	var time_start = Time.get_ticks_usec()
	if SAVE:
		# ResourceSaver.FLAG_COMPRESS argument doesn't seem do change the file size and takes twice as long
		ResourceSaver.save(mesh, "res://planetizedisplace.tres")
	var time_end = Time.get_ticks_usec()
	if TIMING:
		print("Saving mesh took %d microseconds" % (time_end - time_start))


func random_on_unit_sphere () -> Vector3:
	return Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)).normalized()


func bias_function(x: float, bias: float) -> float:
	var k := pow(1 - bias, 3)
	return (x * k) / (x * k - x + 1)


func displace():
	avg_cycles += 1
	var displace_time_start = Time.get_ticks_usec()
	seed("test".hash())
	var surface_array := mesh.surface_get_arrays(0)
	var verts := PackedVector3Array(surface_array[Mesh.ARRAY_VERTEX])
	var indices := PackedInt32Array(surface_array[Mesh.ARRAY_INDEX])
	var normals := PackedVector3Array()
	normals.resize(surface_array[Mesh.ARRAY_NORMAL].size())
	
	# Feed buffer containing random position and radius for each crater and the other settings
	# Craters are made of 3 shapes.
	#  Cavity parabola y = x*x-1
	#  Rim parabola y = steepness * ((|x|-1-width))^2
	#  Floor line y = height
	
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
	
	## displace vertices
	#for vid in range(verts.size()):
		#verts[vid] = default_surface[Mesh.ARRAY_VERTEX][vid] * ((sin(default_surface[Mesh.ARRAY_VERTEX][vid].y * 20.0 + Time.get_ticks_msec() / 1000.0) / 10 ) + 1.0)
	
	var gpu_time_start = Time.get_ticks_usec()
	## Submit to GPU and wait for sync
	rd.submit()
	## Normally we would let the GPU work in parallel but we want the results now
	rd.sync()
	var gpu_time_end = Time.get_ticks_usec()
	avg_time_gpu = avg_time_gpu * (avg_cycles - 1) / avg_cycles + (gpu_time_end - gpu_time_start) / avg_cycles
	if TIMING:
		print("GPU took %d microseconds (%dus)" % [(gpu_time_end - gpu_time_start), avg_time_gpu])
	
	## THIS IS EXTREMELY SLOW ~8MS
	## calculate vertex normals. see opengl wiki
	#for i in range(0, indices.size(), 3):
		#var a_idx = indices[i]
		#var b_idx = indices[i + 1]
		#var c_idx = indices[i + 2]
		#var a = verts[a_idx]
		#var b = verts[b_idx]
		#var c = verts[c_idx]
		## two vectors
		#var u = b - a
		#var v = c - a
		## calculate face normal
		#var n = v.cross(u).normalized()
		#normals[a_idx] += n
		#normals[b_idx] += n
		#normals[c_idx] += n
	#
	#for i in range(normals.size()):
		#normals[i] = normals[i].normalized()
	#
	#surface_array[Mesh.ARRAY_NORMAL] = normals
	
	## Prepare normal shader compute list
	#pipeline = rd.compute_pipeline_create(normal_shader)
	#compute_list = rd.compute_list_begin()
	#rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	## Bind the uniform set we made to the compute list. Third argument is the set index
	#rd.compute_list_bind_uniform_set(compute_list, mesh_out_uniform_set_normal_pass, 0)
	### Dispatch the compute list. Last three arguments are workgroups
	#rd.compute_list_dispatch(compute_list, ceil(tri_count / float(INVOCATION_SIZE)), 1, 1)
	#rd.compute_list_end()
	#
	## Send normal shader
	#var norm_pass_time_start = Time.get_ticks_usec()
	### Submit to GPU and wait for sync
	#rd.submit()
	### Normally we would let the GPU work in parallel but we want the results now
	#rd.sync()
	#var norm_pass_time_end = Time.get_ticks_usec()
	#avg_time_norm_pass = avg_time_norm_pass * (avg_cycles - 1) / avg_cycles + (norm_pass_time_end - norm_pass_time_start) / avg_cycles
	#if TIMING:
		#print("GPU normal pass took %d microseconds (%dus)" % [(norm_pass_time_end - norm_pass_time_start), avg_time_norm_pass])

	# Retreive mesh data -- this is slow ~1ms
	# Vertex
	var verts4_output_bytes := rd.buffer_get_data(v_out_buffer)
	var verts4_output := verts4_output_bytes.to_float32_array()
	var verts_output := PackedVector3Array()
	verts_output.resize(verts.size())
	for i in range(verts_output.size()):
		verts_output[i] = Vector3(verts4_output[i * 4], verts4_output[i * 4 + 1], verts4_output[i * 4 + 2])
	surface_array[Mesh.ARRAY_VERTEX] = verts_output
	
	## Normal
	#var face4_output_bytes := rd.buffer_get_data(face_out_buffer)
	#var face4_output := face4_output_bytes.to_float32_array()
	#for i in range(tri_count):
		## Add the face normal to each vertex belonging to that faace
		#var n := Vector3(face4_output[i * 4], face4_output[i * 4 + 1], face4_output[i * 4 + 2])
		#normals[indices[i * 3]] += n
		#normals[indices[i * 3 + 1]] += n
		#normals[indices[i * 3 + 2]] += n
	## Normalize the summed vertex normals
	#for i in range(normals.size()):
		#normals[i] = normals[i].normalized()
	#surface_array[Mesh.ARRAY_NORMAL] = normals
	
	# New Normal. This one does it all in one shader
	var norms4_output_bytes := rd.buffer_get_data(n_out_buffer)
	var norms4_output := norms4_output_bytes.to_float32_array()
	var norms_output := PackedVector3Array()
	norms_output.resize(verts.size())
	for i in range(norms_output.size()):
		norms_output[i] = Vector3(norms4_output[i * 4], norms4_output[i * 4 + 1], norms4_output[i * 4 + 2])
	surface_array[Mesh.ARRAY_NORMAL] = norms_output
	
	# TODO we probably need to free RID's made in this function now.
	# In fact, it might be a good idea to not recreate all these buffers and reuse them between calls instead
	# TODO Experiment with RenderingDevice.get_memory_usage()
	
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	
	var displace_time_end = Time.get_ticks_usec()
	avg_time_displace = avg_time_displace * (avg_cycles - 1) / avg_cycles + (displace_time_end - displace_time_start) / avg_cycles
	if TIMING:
		print("displace() took %d microseconds (%dus)" % [(displace_time_end - displace_time_start), avg_time_displace])
