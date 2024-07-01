## Tracks the current progress of the scene as it loads so that the player knows
## the game is actually doing something
extends Control

signal done_loading

static var state:
	get:
		return state
	set(value):
		state = value
enum {GOLDBERG, SEPARATION, INITIALIZATION, DISPLACEMENT, COMMITTING, 
	STATE_MAX}
@onready var description := $PanelContainer/MarginContainer/VBoxContainer/Description
@onready var slider := $PanelContainer/MarginContainer/VBoxContainer/Slider


# Called when the node enters the scene tree for the first time.
func _ready():
	state = GOLDBERG


func _process(delta):
	update()


func update():
	if !visible:
		return
	match state:
		GOLDBERG:
			description.text = "Generating goldberg sphere."
		SEPARATION:
			description.text = "Separating sectors."
		INITIALIZATION:
			description.text = "Initializing displacement."
		DISPLACEMENT:
			description.text = "Shaping planet."
		COMMITTING:
			description.text = "Committing planet mesh data."
		STATE_MAX:
			description.text = "Done."
			done_loading.emit()
			visible = false
	slider.value = state / float(STATE_MAX)
