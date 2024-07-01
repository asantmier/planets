extends DirectionalLight3D
# This just updates the sun_dir shader global for use in the ocean shader's specular highlight

var rotation_cache

# Called when the node enters the scene tree for the first time.
func _ready():
	rotation_cache = rotation.normalized()
	var facing = quaternion * Vector3.FORWARD
	RenderingServer.global_shader_parameter_set("sun_dir", facing.normalized())


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	if rotation_cache != rotation.normalized():
		rotation_cache = rotation.normalized()
		var facing = quaternion * Vector3.FORWARD
		RenderingServer.global_shader_parameter_set("sun_dir", facing.normalized())
