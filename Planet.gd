extends Node3D

# on mouse pick is hooked up to PlanetClick through Space on instantiation
signal on_mouse_pick(event: InputEvent, remote: RemoteTransform3D, planet)
signal sector_hovered(sector: Sector, focused: bool)
signal sector_clicked(sector: Sector, focused: bool)

@export var rotate_speed := 0.01
@export var orbit_radius := 1.5
var focused := false
var refresh_rate := 0.25
var refresh_timer := 0.0
var _rotation = 0.0
@onready var terrain_grid := $Earth/TerrainGrid

# Called when the node enters the scene tree for the first time.
func _ready():
	randomize()
	refresh_timer += randf_range(0, refresh_rate)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	#rotate_object_local(Vector3.UP, rotate_speed * delta)
	#position += Vector3.FORWARD * rotate_speed * delta
	_rotation += delta * rotate_speed
	transform.basis = Basis(Quaternion.from_euler(Vector3(0, _rotation, 0)))
	pass


func _physics_process(delta):
	if focused:
		if refresh_timer <= refresh_rate:
			refresh_timer += delta
			return
		refresh_timer = 0.0
		var sector_lods : PackedInt32Array
		sector_lods.resize($Earth/TerrainGrid.get_child_count())
		for sector: Sector in $Earth/TerrainGrid.get_children():
			sector.update_lod()
			sector_lods[sector.sector_number] = sector.current_lod
		
		var material := $Earth/TerrainGrid.get_child(0).get_lods()[0].material_override as ShaderMaterial
		material.set_shader_parameter("sector_lods", sector_lods)


func _on_area_3d_input_event(camera, event, position, normal, shape_idx):
	on_mouse_pick.emit(event, $RemoteTransform3D, self)


# TODO Very slow
func set_focused(value):
	focused = value
	var sector_lods : PackedInt32Array
	sector_lods.resize($Earth/TerrainGrid.get_child_count())
	for sector: Sector in $Earth/TerrainGrid.get_children():
		if value:
			sector.set_normal_quality()
			sector.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			sector.set_low_quality()
			sector.process_mode = Node.PROCESS_MODE_DISABLED
		sector_lods[sector.sector_number] = sector.current_lod
	var material := $Earth/TerrainGrid.get_child(0).get_lods()[0].material_override as ShaderMaterial
	material.set_shader_parameter("sector_lods", sector_lods)


func _on_terrain_grid_sector_input(camera, event, position, normal, sector):
	if event is InputEventMouseMotion:
		sector_hovered.emit(sector as Sector, focused)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			sector_clicked.emit(sector as Sector, focused)
		if not focused and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			on_mouse_pick.emit(event, $RemoteTransform3D, self)
