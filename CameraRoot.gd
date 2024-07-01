extends Node3D

@export var focused_remote : RemoteTransform3D
@export var focused_planet : Node3D

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _input(event):
	if event.is_action_pressed("open_map"):
		focused_remote.update_position = !focused_remote.update_position
		focused_remote.update_rotation = !focused_remote.update_position
		focused_planet.set_focused(focused_remote.update_position)


func focus_planet(remote, planet):
	if focused_remote != null:
		focused_remote.update_position = false
		focused_remote.update_rotation = false
	remote.update_position = true
	remote.update_rotation = true
	remote.remote_path = remote.get_path_to(self)
	
	if focused_planet != null:
		focused_planet.set_focused(false)
	planet.set_focused(true)
	
	focused_remote = remote
	focused_planet = planet


func _on_planet_click_focused_planet(remote, planet):
	focus_planet(remote, planet)


func _on_zoom_unfocus_meter_filled():
	if focused_remote != null:
		focused_remote.update_position = false
		focused_remote.update_rotation = false
		focused_planet.set_focused(false)
