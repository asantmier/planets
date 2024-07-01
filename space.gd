extends Node3D

signal ended_aiming

@export var planet_count := 4
var planets = []
var aiming = false
var active_turret
@onready var hover_ring = $HoverRing
@onready var selection_ring = $SelectionRing
@onready var aim_reticle = $AimReticle

# TODO
# Make sector just an area3d and remove the lods list and instead manage them
# internally. This will remove 2 more nodes from each sector
# The solution to rotating is to reduce the number of nodes in the scene as much as possible

# Called when the node enters the scene tree for the first time.
func _ready():
	var p = preload("res://planet_scene.tscn").instantiate()
	var num_lods = p.get_child(0).lod_count
	preload("res://Planet/Icosphere.gd").prep(num_lods)
	add_child(p)
	#p.on_mouse_pick.connect($GUI/PlanetClick._on_planet_pick)
	#p.sector_hovered.connect(selection_ring._on_sector_hover)
	planets.append(p)
	for i in range(planet_count - 1):
		var new_planet = preload("res://planet_scene.tscn").instantiate()
		add_child(new_planet)
		#new_planet.on_mouse_pick.connect($GUI/PlanetClick._on_planet_pick)
		#new_planet.sector_hovered.connect(selection_ring._on_sector_hover)
		planets.append(new_planet)
	for i in range(planets.size()):
		planets[i].on_mouse_pick.connect($GUI/PlanetClick._on_planet_pick)
		planets[i].sector_hovered.connect(hover_ring._on_sector_selected)
		planets[i].sector_clicked.connect(selection_ring._on_sector_selected)
		planets[i].sector_clicked.connect($GUI/SectorPanel._on_sector_clicked)
		planets[i].sector_hovered.connect(aim_reticle._on_sector_selected)
		match i:
			0: planets[i].position = Vector3(-4, 0, 0)
			1: planets[i].position = Vector3(4, 0, 0)
			2: planets[i].position = Vector3(0, 0, -4)
			3: planets[i].position = Vector3(0, 0, 4)


func _unhandled_input(event):
	if aiming:
		# Fire the turret on click
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				active_turret.fire(aim_reticle.global_position, aim_reticle.on_planet)
				set_aim_mode(false)
				get_viewport().set_input_as_handled()


## Handles turret aiming
func set_aim_mode(value: bool):
	aiming = value
	if value:
		aim_reticle.show()
		# Turn off all interaction with planets outside of aiming
		hover_ring.hide()
		for i in range(planets.size()):
			if planets[i].sector_hovered.is_connected(hover_ring._on_sector_selected):
				planets[i].sector_hovered.disconnect(hover_ring._on_sector_selected)
			if planets[i].sector_clicked.is_connected(selection_ring._on_sector_selected):
				planets[i].sector_clicked.disconnect(selection_ring._on_sector_selected)
			if planets[i].sector_clicked.is_connected($GUI/SectorPanel._on_sector_clicked):
				planets[i].sector_clicked.disconnect($GUI/SectorPanel._on_sector_clicked)
	else:
		# Emit signal to tell the GUI aiming has stopped
		ended_aiming.emit()
		aim_reticle.hide()
		hover_ring.show()
		for i in range(planets.size()):
			if not planets[i].sector_hovered.is_connected(hover_ring._on_sector_selected):
				planets[i].sector_hovered.connect(hover_ring._on_sector_selected)
			if not planets[i].sector_clicked.is_connected(selection_ring._on_sector_selected):
				planets[i].sector_clicked.connect(selection_ring._on_sector_selected)
			if not planets[i].sector_clicked.is_connected($GUI/SectorPanel._on_sector_clicked):
				planets[i].sector_clicked.connect($GUI/SectorPanel._on_sector_clicked)


func _on_loading_box_done_loading():
	$CameraRoot.focus_planet(planets[0].get_node("RemoteTransform3D"), planets[0])
	for i in range(1, planets.size()):
		planets[i].set_focused(false)


func _on_sector_panel_aimed(value, turret):
	set_aim_mode(value)
	active_turret = turret
