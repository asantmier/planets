extends Control

signal focused_planet(remote: RemoteTransform3D, planet)

var picked_remote : RemoteTransform3D
var picked_planet

# Called when the node enters the scene tree for the first time.
func _ready():
	visible = false


func _input(event):
	if not visible:
		return
	
	# Close panel if clicked outside of it
	if event is InputEventMouseButton and event.pressed:
		var ev_local := make_input_local(event)
		if !Rect2(Vector2(0, 0), get_rect().size).has_point(ev_local.position):
			visible = false


func _on_button_pressed():
	visible = false
	focused_planet.emit(picked_remote, picked_planet)


func _on_planet_pick(event, remote, planet):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		self.position = event.position
		visible = true
		picked_remote = remote
		picked_planet = planet
