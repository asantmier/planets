extends Control

signal filled

@export var required_distance := 10

var increment := false
var current_distance := 0

@onready var slider = $PanelContainer/MarginContainer/HSlider

# Called when the node enters the scene tree for the first time.
func _ready():
	hide()


func _physics_process(delta):
	if increment:
		show()
		$Timer.start()
		current_distance += 1
		increment = false
		slider.value = current_distance
		slider.max_value = required_distance
		slider.tick_count = required_distance + 1
		if current_distance >= required_distance:
			hide()
			$Timer.stop()
			filled.emit()
			_reset()


func _reset():
	current_distance = 0
	slider.value = current_distance


func _on_camera_orbit_zoom_exceeded():
	increment = true


func _on_timer_timeout():
	_reset()
	hide()
