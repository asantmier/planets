extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func create_missle():
	var missile = preload("res://missile.tscn").instantiate()
	add_child(missile)
	print("Added missile.")
	return missile
