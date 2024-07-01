extends Node3D

# ## comments are required to simply run a compute shader
# # comments are normal comments

# Called when the node enters the scene tree for the first time.
func _ready():
	## Create a local rendering device.
	var rd := RenderingServer.create_local_rendering_device()
	## Load GLSL shader
	var shader_file := load("res://compute_example.glsl")
	## SPIR-V is a standard intermediary language that ports shaders between languages
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	## Creates the actual shader on the device. Returns the resource ID of the shader
	var shader := rd.shader_create_from_spirv(shader_spirv)
	
	# Prepare our data. We use floats in the shader, so we need 32 bit.
	var input := PackedFloat32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	# Data must be sent to the GPU as an array of bytes
	var input_bytes := input.to_byte_array()
	# Create a storage buffer that can hold our float values.
	# Each float has 4 bytes (32 bit) so 10 x 4 = 40 bytes
	# And remember, this returns an RID as per usual
	var buffer := rd.storage_buffer_create(input_bytes.size(), input_bytes)
	# Create a uniform to assign the buffer to the rendering device
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	# Binding is an index used to acces the buffer from a uniform set in the shader script
	uniform.binding = 0 # this needs to match the "binding" in our shader file
	# Add the RID of the storage buffer we created to the uniform
	uniform.add_id(buffer)
	
	## You should group shader bindings by update frequency. 
	##  So in our case, the values we send every frame are in one set
	##  while values that stay constant are in another
	# Binding  test
	var input3 := PackedFloat32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	var input3_bytes := input3.to_byte_array()
	var buffer3 := rd.storage_buffer_create(input3_bytes.size(), input3_bytes)
	var uniform3 := RDUniform.new()
	uniform3.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform3.binding = 1 # this needs to match the "binding" in our shader file
	uniform3.add_id(buffer3)
	
	# First argument is an array containing all the uniforms that will be in this set, second is the RID of the shader, third is used to reference the set in the shader
	var uniform_set := rd.uniform_set_create([uniform, uniform3], shader, 0) # the last parameter (the 0) needs to match the "set" in our shader file
	# Basically we just created set "0" on the shader. The set contains binding "0" that contains the RID of our buffer
	
	# Vector3 test
	# Convert our vector3 data into vector4 (color) data
	var vector_data := PackedVector3Array([
		1 * Vector3.ONE, 2 * Vector3.ONE, 3 * Vector3.ONE, 4 * Vector3.ONE, 5 * Vector3.ONE, 6 * Vector3.ONE, 7 * Vector3.ONE, 8 * Vector3.ONE, 9 * Vector3.ONE, 10 * Vector3.ONE])
	var input2 := PackedColorArray()
	input2.resize(vector_data.size())
	for i in range(vector_data.size()):
		input2[i] = Color(vector_data[i].x, vector_data[i].y, vector_data[i].z, vector_data[i].z)
		
	var input2_bytes := input2.to_byte_array()
	var buffer2 := rd.storage_buffer_create(input2_bytes.size(), input2_bytes)
	var uniform2 := RDUniform.new()
	uniform2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform2.binding = 0
	uniform2.add_id(buffer2)
	var uniform2_set := rd.uniform_set_create([uniform2], shader, 1)
	
	## Create a compute pipeline for the shader. Returns an RID again
	var pipeline := rd.compute_pipeline_create(shader)
	## Begin a compute list. Returns an RID again
	var compute_list := rd.compute_list_begin()
	## Binds compute pipeline with compute list
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	# Bind the uniform set we made to the compute list. Third argument is the set index
	# So the set know which index it is in the compute list
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	rd.compute_list_bind_uniform_set(compute_list, uniform2_set, 1)
	## Dispatch the compute list. Last three arguments are workgroups
	rd.compute_list_dispatch(compute_list, 5, 1, 1)
	## End defining compute list
	rd.compute_list_end()
	
	## Submit to GPU and wait for sync
	rd.submit()
	## Normally we would let the GPU work in parallel but we want the results now
	rd.sync()
	
	# Read back the data from the buffer
	var output_bytes := rd.buffer_get_data(buffer)
	var output := output_bytes.to_float32_array()
	print("Input: ", input)
	print("Output: ", output)
	
	# Binding test
	var output3_bytes := rd.buffer_get_data(buffer3)
	var output3 := output3_bytes.to_float32_array()
	print("Input3: ", input3)
	print("Output3: ", output3)
	
	
	# Vector3 test
	var output2_bytes := rd.buffer_get_data(buffer2)
	var output2 := output2_bytes.to_float32_array()
	print("Input vec4: ", input2)
	print("Output vec4: ", output2)
	var vector_output := PackedVector3Array()
	vector_output.resize(vector_data.size())
	for i in range(vector_output.size()):
		var out_i = i * 4
		vector_output[i] = Vector3(output2[out_i], output2[out_i + 1], output2[out_i + 2])
	print("Input vec3: ", vector_data)
	print("Output vec3: ", vector_output)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
