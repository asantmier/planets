extends Node3D

signal zoom_exceeded()

@export var rotation_speed := 1.0
@export var zoom_speed := 1.0
@export var move_speed := 1.0
@export var min_space_distance := 0.0
@export var max_space_distance := 100.0
@export var min_planet_distance := 1.2
@export var max_planet_distance := 3.0
var orbit_speed: Vector2
var _rotation: Vector3
var _scroll_dir := 0
var _move_dir : Vector2
@onready var camera := $Camera3D as Node3D

var mode := PLANET
enum { PLANET, SPACE }

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	# Rotate
	orbit_speed *= delta * rotation_speed * -1
	if Input.is_action_pressed("orbit_camera"):
		_rotation.x = clampf(_rotation.x + orbit_speed.y, -PI/2, PI/2)
		_rotation.y += orbit_speed.x
		transform.basis = Basis(Quaternion.from_euler(_rotation))
	orbit_speed = Vector2.ZERO
	
	# Zoom
	# TODO if zoom affects scale, then it will indirectly affect movement and rotation which is desirable
	var min_distance
	var max_distance
	match mode:
		PLANET:
			min_distance = min_planet_distance
			max_distance = max_planet_distance
		SPACE:
			min_distance = min_space_distance
			max_distance = max_space_distance
	# TODO smooth zooming and zoom acceleration on continuous scrolling
	camera.position.z = clampf(camera.position.z + _scroll_dir * zoom_speed, min_distance, max_distance)
	if camera.position.z + _scroll_dir * zoom_speed > max_distance:
		zoom_exceeded.emit()
	_scroll_dir = 0
	
	# Move
	if mode == SPACE:
		if Input.is_action_pressed("move_forward"):
			_move_dir.y = 1
		elif Input.is_action_pressed("move_backward"):
			_move_dir.y = -1
		if Input.is_action_pressed("move_right"):
			_move_dir.x = 1
		elif Input.is_action_pressed("move_left"):
			_move_dir.x = -1
		var movement = _move_dir * move_speed * delta
		translate_object_local(Vector3(movement.x, 0, 0))
		global_translate(basis * Vector3.FORWARD * movement.y * Vector3(1, 0, 1))
		_move_dir = Vector2.ZERO


func _input(event):
	if event is InputEventMouseMotion:
		orbit_speed = event.relative
	if event is InputEventMouseButton:
		if Input.is_action_pressed("zoom_in"):
			_scroll_dir = -1
		elif Input.is_action_pressed("zoom_out"):
			_scroll_dir = 1
	if event.is_action_pressed("open_map"):
		match mode:
			SPACE: 
				mode = PLANET
				position = Vector3.ZERO
			PLANET: 
				mode = SPACE


func _on_zoom_unfocus_meter_filled():
	mode = SPACE


func _on_planet_click_focused_planet(_remote, _planet):
	mode = PLANET
	position = Vector3.ZERO
