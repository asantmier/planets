extends Control

# Aimed hooks up to Space, which does all the lifting
signal aimed(value: bool, turret)

var active_sector: Sector
var aiming = false

# Called when the node enters the scene tree for the first time.
func _ready():
	hide()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_sector_clicked(sector: Sector, focused: bool):
	# INFO ignoring unfocused sectors
	if not focused: return
	
	active_sector = sector
	refresh()
	show()


func refresh():
	$PanelContainer/MarginContainer/VBoxContainer/Label.text = active_sector.name
	if active_sector.building:
		$PanelContainer/MarginContainer/VBoxContainer/AddTurret.hide()
		$PanelContainer/MarginContainer/VBoxContainer/AddMissile.hide()
		$PanelContainer/MarginContainer/VBoxContainer/AddPD.hide()
		$PanelContainer/MarginContainer/VBoxContainer/AddFactory.hide()
		if not aiming and active_sector.building.is_turret:
			$PanelContainer/MarginContainer/VBoxContainer/AimTurret.show()
		else:
			$PanelContainer/MarginContainer/VBoxContainer/AimTurret.hide()
	else:
		$PanelContainer/MarginContainer/VBoxContainer/AddTurret.show()
		$PanelContainer/MarginContainer/VBoxContainer/AddMissile.show()
		$PanelContainer/MarginContainer/VBoxContainer/AddPD.show()
		$PanelContainer/MarginContainer/VBoxContainer/AddFactory.show()
		$PanelContainer/MarginContainer/VBoxContainer/AimTurret.hide()
	$PanelContainer/MarginContainer/VBoxContainer/CancelAim.visible = aiming


func construct_sector_transform():
	var sector = active_sector
	var points = []
	var center = sector.center
	for p in sector.shape.points:
		points.append(p + sector.global_position)
	var outer_points = []
	var inner_points = []
	var normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var x = (points[1] - points[0]).normalized()
	var y = x.cross(normal).normalized()
	var local_basis = Basis(x, -normal, y)
	return Transform3D(local_basis, center)


func _on_add_turret_pressed():
	var sector_transform = construct_sector_transform()
	var turret = load("res://turret.tscn").instantiate()
	active_sector.set_building(turret)
	var new_transform = sector_transform * turret.transform
	turret.transform = new_transform
	
	refresh()


func _on_add_missile_pressed():
	var sector_transform = construct_sector_transform()
	var turret = load("res://missile_silo.tscn").instantiate()
	active_sector.set_building(turret)
	var new_transform = sector_transform * turret.transform
	turret.transform = new_transform
	
	refresh()


func _on_add_pd_pressed():
	var sector_transform = construct_sector_transform()
	var turret = load("res://point_defense.tscn").instantiate()
	active_sector.set_building(turret)
	var new_transform = sector_transform * turret.transform
	turret.transform = new_transform
	
	refresh()


func _on_add_factory_pressed():
	var sector_transform = construct_sector_transform()
	var turret = load("res://factory.tscn").instantiate()
	active_sector.set_building(turret)
	var new_transform = sector_transform * turret.transform
	turret.transform = new_transform
	
	refresh()


func _on_aim_turret_pressed():
	aiming = true
	aimed.emit(true, active_sector.building)
	
	refresh()


func _on_cancel_aim_pressed():
	aiming = false
	aimed.emit(false, active_sector.building)
	
	refresh()


func _on_space_ended_aiming():
	aiming = false
	
	refresh()
