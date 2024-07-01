extends MeshInstance3D

# Geodesic polyhedra are the dual of corresponding Goldberg polyhedra
# Use the poly faces to construct the hexagons on the hex map.
# Do a kis on a copy of the structure to make the geodesic sphere
# Use this sphere for graphics and the other for code

const SAVE := false
const TIMING := true
const DEBUG_SECTORS := true # leave on for sanity checking

## These constants must always match how the terrain shader is made and are ised
## for debugging sanity checks
# WARNING CHANGE THESE IF THEY EVER CHANGE IN THE SHADER
const SECTOR_COUNT := 812
const STORED_LOD_COUNT := 4

static var pre_hex_mesh : ArrayMesh
static var pre_sector_data: Array

@onready var terrain_grid_node := $TerrainGrid
# INFO 5 lods looks really good
# 4 lods still looks plenty good
# 3 lods is noticably worse but still acceptable
var lod_count = 4
var vis_margin = 0.2
var vis_diff = 2
var _old_vis_margin
var _old_vis_diff
@export var terrain_material: ShaderMaterial
var _old_terrain_material: ShaderMaterial

# loading screen stuff
var Loading = preload("res://LoadingBox.gd")
static var global_id := 0
var id : int


class SectorData:
	var name
	var number
	var lods
	var shape

class LODData:
	var name
	var surface_array
	var number
	var edges : Array[Edge]

# Called when the node enters the scene tree for the first time.
func _ready():
	id = global_id
	global_id += 1
	$TerrainGrid.id = id
	
	_old_vis_margin = vis_margin
	_old_vis_diff = vis_diff
	_old_terrain_material = terrain_material
	if not SAVE:
		print("Saving is disabled for icosphere!")
	
	# Delay the rest of initialization until godot displays the first frame
	get_tree().process_frame.connect(gongaga, CONNECT_ONE_SHOT)
	

# We want to start this at the beginning of the *second* process frame since the
# beginning of the first process frame is when ready is being called already
func gongaga():
	# delays construction until the godot splashscreen goes away
	#get_tree().process_frame.connect(construct_planet, CONNECT_ONE_SHOT)
	
	var new_sector_list := []
	for data in pre_sector_data:
		var lod_list = []
		for lod_data in data.lods:
			var n = lod_data.number
			var lod = SectorLOD.new()
			lod.name = lod_data.name
			lod.setup(lod_data.surface_array, lod_data.number, terrain_material, lod_data.edges)
			if n != lod_count - 1:
				lod.begin = vis_diff * (lod_count - n - 1)
				lod.begin_margin = vis_margin
			if n != 0:
				lod.end = vis_diff * (lod_count - n)
				lod.end_margin = vis_margin
			lod_list.append(lod)
		var sector := preload("res://Planet/Sector.tscn").instantiate()
		sector.name = data.name
		sector.sector_number = data.number
		sector.add_lods(lod_list)
		sector.set_collision_shape(data.shape)
		new_sector_list.append(sector)
	
	get_tree().process_frame.connect(assign_data.bind(new_sector_list, pre_hex_mesh), CONNECT_ONE_SHOT)


func _process(_delta):
	if _old_vis_diff != vis_diff or _old_vis_margin != vis_margin:
		for sector in terrain_grid_node.get_children():
			var lod_parent = sector.get_child(0)
			lod_parent.get_child(0).visibility_range_begin = vis_diff * (lod_count - 1)
			lod_parent.get_child(0).visibility_range_begin_margin = vis_margin
			for n in range(1, lod_count):
				var lod = lod_parent.get_child(n)
				if n != lod_count - 1:
					lod.visibility_range_begin = vis_diff * (lod_count - n - 1)
					lod.visibility_range_begin_margin = vis_margin
				lod.visibility_range_end = vis_diff * (lod_count - n)
				lod.visibility_range_end_margin = vis_margin
		_old_vis_diff = vis_diff
		_old_vis_margin = vis_margin
	if _old_terrain_material != terrain_material:
		for sector in terrain_grid_node.get_children():
			var lod_parent = sector.get_child(0)
			for n in range(1, lod_count):
				var lod = lod_parent.get_child(n)
				lod.mesh.surface_set_material(0, terrain_material)
		_old_terrain_material = terrain_material


static func prep(num_lods):
	# Geodesic/Goldberg generation
	var time_start = Time.get_ticks_msec()
	# list of all vertices
	var poly_verts := []
	# list of faces containing their vertices in clockwise order
	var poly_faces := []
	# list of vertex normals
	var poly_normals := []
	setup_icosahedron(poly_verts, poly_faces)
	dual(poly_verts, poly_faces)
	#print("Goldberg 1 has %d faces." % poly_faces.size()) # 12
	kis(poly_verts, poly_faces)
	dual(poly_verts, poly_faces)
	#print("Goldberg 2 has %d faces." % poly_faces.size()) # 32
	kis(poly_verts, poly_faces)
	dual(poly_verts, poly_faces)
	#print("Goldberg 3 has %d faces." % poly_faces.size()) # 92
	kis(poly_verts, poly_faces)
	dual(poly_verts, poly_faces)
	#print("Goldberg 4 has %d faces." % poly_faces.size()) # 272
	kis(poly_verts, poly_faces)
	dual(poly_verts, poly_faces)
	#print("Goldberg 5 has %d faces." % poly_faces.size()) # 812
	# End of Goldberg generation
	#kis(poly_verts, poly_faces)
	# End of Geodesic generation
	
	var surface_array := []
	surface_array.resize(Mesh.ARRAY_MAX)
	# Arrays to construct the mesh
	var verts := PackedVector3Array()
	#var uvs = PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var gold_poly_verts := poly_verts.duplicate()
	var gold_poly_faces := poly_faces.duplicate()
	var gold_poly_normals := poly_normals.duplicate()
	geometrize(gold_poly_verts, gold_poly_faces, gold_poly_normals)
	# triangulate
	normals = PackedVector3Array(gold_poly_normals)
	verts = PackedVector3Array(gold_poly_verts)
	triangulate(verts, normals, indices, gold_poly_verts, gold_poly_faces)
	# commit to hex map
	# Assign arrays to surface array
	surface_array[Mesh.ARRAY_VERTEX] = verts
	#surface_array[Mesh.ARRAY_TEX_UV] = uvs
	surface_array[Mesh.ARRAY_NORMAL] = normals
	surface_array[Mesh.ARRAY_INDEX] = indices
	# Need to make mesh unique
	pre_hex_mesh = ArrayMesh.new()
	pre_hex_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	
	if SAVE:
		# Saves mesh to a .tres file with compression enabled. Compression flag removed since it doesn't seem to work
		ResourceSaver.save(pre_hex_mesh, "res://planetizehex.tres",)
	
	var time_end = Time.get_ticks_msec()
	print("Icosphere took %d milliseconds" % (time_end - time_start))

	time_start = Time.get_ticks_msec()
	
	pre_sector_data = []
	#separate(poly_verts, poly_faces, pre_sector_list)
	pre_separate(poly_verts, poly_faces, pre_sector_data, num_lods)
	
	time_end = Time.get_ticks_msec()
	print("Separate took %d milliseconds" % (time_end - time_start))


#func construct_planet():
	## Geodesic/Goldberg generation
	#var time_start = Time.get_ticks_msec()
	## list of all vertices
	#var poly_verts := []
	## list of faces containing their vertices in clockwise order
	#var poly_faces := []
	## list of vertex normals
	#var poly_normals := []
	#setup_icosahedron(poly_verts, poly_faces)
	#dual(poly_verts, poly_faces)
	##print("Goldberg 1 has %d faces." % poly_faces.size()) # 12
	#kis(poly_verts, poly_faces)
	#dual(poly_verts, poly_faces)
	##print("Goldberg 2 has %d faces." % poly_faces.size()) # 32
	#kis(poly_verts, poly_faces)
	#dual(poly_verts, poly_faces)
	##print("Goldberg 3 has %d faces." % poly_faces.size()) # 92
	#kis(poly_verts, poly_faces)
	#dual(poly_verts, poly_faces)
	##print("Goldberg 4 has %d faces." % poly_faces.size()) # 272
	#kis(poly_verts, poly_faces)
	#dual(poly_verts, poly_faces)
	##print("Goldberg 5 has %d faces." % poly_faces.size()) # 812
	## End of Goldberg generation
	##kis(poly_verts, poly_faces)
	## End of Geodesic generation
	#
	#var surface_array := []
	#surface_array.resize(Mesh.ARRAY_MAX)
	## Arrays to construct the mesh
	#var verts := PackedVector3Array()
	##var uvs = PackedVector2Array()
	#var normals := PackedVector3Array()
	#var indices := PackedInt32Array()
	#var gold_poly_verts := poly_verts.duplicate()
	#var gold_poly_faces := poly_faces.duplicate()
	#var gold_poly_normals := poly_normals.duplicate()
	#geometrize(gold_poly_verts, gold_poly_faces, gold_poly_normals)
	## triangulate
	#normals = PackedVector3Array(gold_poly_normals)
	#verts = PackedVector3Array(gold_poly_verts)
	#triangulate(verts, normals, indices, gold_poly_verts, gold_poly_faces)
	## commit to hex map
	## Assign arrays to surface array
	#surface_array[Mesh.ARRAY_VERTEX] = verts
	##surface_array[Mesh.ARRAY_TEX_UV] = uvs
	#surface_array[Mesh.ARRAY_NORMAL] = normals
	#surface_array[Mesh.ARRAY_INDEX] = indices
	## Need to make mesh unique
	#var hex_mesh = ArrayMesh.new()
	#hex_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	##call_deferred("_set_hex_mesh", hex_mesh)
	#$HexGrid.mesh = hex_mesh
	#
	#if SAVE:
		## Saves mesh to a .tres file with compression enabled. Compression flag removed since it doesn't seem to work
		#ResourceSaver.save(hex_mesh, "res://planetizehex.tres",)
	## End of hex map updating
	#
	## Perform a kis operation as normal to spherize the mesh, but track which triangles belong to which face
	## Also duplicate the vertices that share an edge with another hex
	## Put each face in its own mesh
	## save that mesh
	## For LODs, simply triangulate increasing detail on each hex face of the spherized version
	#
	#var time_end = Time.get_ticks_msec()
	#print("Icosphere took %d milliseconds" % (time_end - time_start))
	#
	## Increment loading state to inform player
	#Loading.state = Loading.SEPARATION
	#get_tree().process_frame.connect(separate_step.bind(poly_verts, poly_faces), CONNECT_ONE_SHOT)


#func separate_step(poly_verts: Array, poly_faces: Array):
	#var time_start = Time.get_ticks_msec()
	#
	#var sectors_list : Array[Node3D] = []
	#separate(poly_verts, poly_faces, sectors_list)
	#
	## Sectors need to do some extra initialization work
	#for sector in sectors_list:
		#terrain_grid_node.add_child(sector)
	#commit_lod_data()
	#
	#var time_end = Time.get_ticks_msec()
	#print("Separate took %d milliseconds" % (time_end - time_start))
	#
	## Increment loading state to inform player
	#Loading.state = Loading.INITIALIZATION
	#
	##terrain_grid_node.data_initialize(sectors_list)
	#var callable = terrain_grid_node.data_initialize.bind(sectors_list)
	#get_tree().process_frame.connect(callable, CONNECT_ONE_SHOT)


func assign_data(sectors_list, hex_mesh):
	var time_start = Time.get_ticks_msec()
	$HexGrid.mesh = hex_mesh
	# Sectors need to do some extra initialization work
	for sector in sectors_list:
		terrain_grid_node.add_child(sector)
	commit_lod_data()
	
	var time_end = Time.get_ticks_msec()
	print("Assignment took %d milliseconds" % (time_end - time_start))
	
	# Increment loading state to inform player
	Loading.state = Loading.INITIALIZATION
	
	var callable = terrain_grid_node.data_initialize.bind(sectors_list)
	get_tree().process_frame.connect(callable, CONNECT_ONE_SHOT)


## Sends data used for LOD stuff to the terrain shader
func commit_lod_data():
	if DEBUG_SECTORS:
		lod_sanity_check()
	
	var sector_lods := PackedInt32Array()
	sector_lods.resize(SECTOR_COUNT)
	for s in range(terrain_grid_node.get_child_count()):
		var sector = terrain_grid_node.get_child(s)
		sector_lods[s] = sector.current_lod
	terrain_material.set_shader_parameter("sector_lods", sector_lods)


## Makes sure the values we're basing the terrain shader off match what we've created
func lod_sanity_check():
	var sector_count = terrain_grid_node.get_child_count()
	var sector0 = terrain_grid_node.get_child(0)
	if sector0.get_lods()[1].edges.size() != 6:
		printerr("SECTOR 0 IS NOT A HEX!")
	print("Planet made with %d sectors." % sector_count)
	assert(sector_count == SECTOR_COUNT, "Sector count does not match shader constant!")
	var lods_count = sector0.get_lods().size()
	print("Sectors contain %d lods." % lods_count)
	#assert(lods_count - 1 == STORED_LOD_COUNT, "LOD count does not match shader design!")
	if lods_count - 1 != STORED_LOD_COUNT:
		printerr("LOD count does not match shader design! This may cause problems.")
		push_warning("LOD count does not match shader design! This may cause problems.")


static func pre_separate(poly_verts: Array, poly_faces: Array, sector_data_list: Array, num_lods: int):
	var ctr := 0
	for face in poly_faces:
		# 1. Construct a poly from just this one face
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var new_face := []
		new_face.resize(face.size())
		var new_poly_faces := [new_face]
		verts.resize(face.size())
		normals.resize(face.size())
		
		# For perimeter verts edge detection later
		var perimeter_verts_indices = range(face.size())
		for vtx in range(face.size()):
			# Set vertex in new array to vertex pointed to in the face
			verts[vtx] = poly_verts[face[vtx]]
			# Set normals to normalized position
			normals[vtx] = verts[vtx].normalized()
			# Set vertex index in new face to current vertex index
			new_face[vtx] = vtx
		# Save polygon for collision shape later
		var poly_shape := ConvexPolygonShape3D.new()
		poly_shape.points = verts.duplicate()
		
		# 2. Set up surface arrays for lods
		var lod_list := []
		var final_verts := PackedVector3Array(verts)
		var final_normals := PackedVector3Array(normals)
		var final_indices := PackedInt32Array()
		# For the lowest lod, we just want the triangulated hex, which puts a
		# single point in the center and cuts the hex like a pizza
		triangulate(final_verts, final_normals, final_indices, verts, new_poly_faces)
		# Project verts onto a sphere
		for vtx in range(final_verts.size()):
			final_verts[vtx] = final_verts[vtx].normalized()
		
		# Now commit it to LOD0
		var low_surface_array := []
		low_surface_array.resize(Mesh.ARRAY_MAX)
		low_surface_array[Mesh.ARRAY_VERTEX] = final_verts
		low_surface_array[Mesh.ARRAY_NORMAL] = final_normals
		low_surface_array[Mesh.ARRAY_INDEX] = final_indices
		var low_lod := LODData.new()
		low_lod.name = "LOD%d" % 0
		
		#low_lod.setup(low_surface_array, 0, terrain_material)
		low_lod.surface_array = low_surface_array
		low_lod.number = 0
		lod_list.append(low_lod)
		
		# 3. For each lod, subdivide the face, copy it to a new mesh, then prepare the next lod if applicable
		for n in range(1, num_lods):
			var lod := LODData.new()
			lod.name = "LOD%d" % n
			var lod_verts := []
			lod_verts.assign(final_verts)
			var lod_normals := []
			lod_normals.assign(final_normals)
			var lod_indices := []
			lod_indices.assign(final_indices)
			var perimeter_edges : Array[Edge]
			# Perform midpoint subdivision
			subdivide_triangles(lod_verts, lod_normals, lod_indices, int(pow(2, n) - 1), perimeter_verts_indices, perimeter_edges)
			# commit mesh
			var surface_array := []
			surface_array.resize(Mesh.ARRAY_MAX)
			surface_array[Mesh.ARRAY_VERTEX] = PackedVector3Array(lod_verts)
			surface_array[Mesh.ARRAY_NORMAL] = PackedVector3Array(lod_normals)
			surface_array[Mesh.ARRAY_INDEX] = PackedInt32Array(lod_indices)
			
			# Find which sector the LOD's edges share
			var e_found = 0
			for e_face_idx in range(poly_faces.size()):
				var e_face = poly_faces[e_face_idx]
				if e_face == face:
					continue
				# because there are a LOT of faces, we can probably whittle down the numbers 
				# a bit if we filter out faces whose min vertex index is greater
				# than our max and vice versa or filter by centroid distance
				for e_edge: Edge in perimeter_edges:
					# our local vertex indices point to an index in the face index array
					if face[e_edge.A] in e_face and face[e_edge.B] in e_face:
						e_edge.neighbor = e_face_idx
						e_found += 1
						break
				if e_found == perimeter_edges.size():
					break
			
			#lod.setup(surface_array, n, terrain_material, perimeter_edges)
			lod.surface_array = surface_array
			lod.number = n
			lod.edges = perimeter_edges
			lod_list.append(lod)
		
		# 4. Construct sector
		var sector := SectorData.new()
		sector.name = "Sector%d" % ctr
		sector.number = ctr
		ctr += 1
		sector.lods = lod_list
		sector.shape = poly_shape
		
		# 5. Send sector to terrain grid
		#terrain_grid_node.add_child(sector)
		sector_data_list.append(sector)


### Separates a goldberg sphere into sectors that contain a face and its spherized lods.
### Also adds the collision enabled hex to each face for raycasting
#func separate(poly_verts: Array, poly_faces: Array, sectors_list: Array[Node3D]):
	#var ctr := 0
	#for face in poly_faces:
		## 1. Construct a poly from just this one face
		#var verts := PackedVector3Array()
		#var normals := PackedVector3Array()
		#var new_face := []
		#new_face.resize(face.size())
		#var new_poly_faces := [new_face]
		#verts.resize(face.size())
		#normals.resize(face.size())
		#
		## For perimeter verts edge detection later
		#var perimeter_verts_indices = range(face.size())
		#for vtx in range(face.size()):
			## Set vertex in new array to vertex pointed to in the face
			#verts[vtx] = poly_verts[face[vtx]]
			## Set normals to normalized position
			#normals[vtx] = verts[vtx].normalized()
			## Set vertex index in new face to current vertex index
			#new_face[vtx] = vtx
		## Save polygon for collision shape later
		#var poly_shape := ConvexPolygonShape3D.new()
		#poly_shape.points = verts.duplicate()
		#
		## 2. Set up surface arrays for lods
		#var lod_list := []
		#var final_verts := PackedVector3Array(verts)
		#var final_normals := PackedVector3Array(normals)
		#var final_indices := PackedInt32Array()
		## For the lowest lod, we just want the triangulated hex, which puts a
		## single point in the center and cuts the hex like a pizza
		#triangulate(final_verts, final_normals, final_indices, verts, new_poly_faces)
		## Project verts onto a sphere
		#for vtx in range(final_verts.size()):
			#final_verts[vtx] = final_verts[vtx].normalized()
		#
		## Now commit it to LOD0
		#var low_surface_array := []
		#low_surface_array.resize(Mesh.ARRAY_MAX)
		#low_surface_array[Mesh.ARRAY_VERTEX] = final_verts
		#low_surface_array[Mesh.ARRAY_NORMAL] = final_normals
		#low_surface_array[Mesh.ARRAY_INDEX] = final_indices
		#var low_lod := SectorLOD.new()
		#low_lod.name = "LOD%d" % 0
		#low_lod.begin = vis_diff * (lod_count - 1)
		#low_lod.begin_margin = vis_margin
		#
		#low_lod.setup(low_surface_array, 0, terrain_material)
		#lod_list.append(low_lod)
		#
		## 3. For each lod, subdivide the face, copy it to a new mesh, then prepare the next lod if applicable
		#for n in range(1, lod_count):
			#var lod := SectorLOD.new()
			#lod.name = "LOD%d" % n
			#var lod_verts := []
			#lod_verts.assign(final_verts)
			#var lod_normals := []
			#lod_normals.assign(final_normals)
			#var lod_indices := []
			#lod_indices.assign(final_indices)
			#var perimeter_edges : Array[Edge]
			## Perform midpoint subdivision
			#subdivide_triangles(lod_verts, lod_normals, lod_indices, int(pow(2, n) - 1), perimeter_verts_indices, perimeter_edges)
			## commit mesh
			#var surface_array := []
			#surface_array.resize(Mesh.ARRAY_MAX)
			#surface_array[Mesh.ARRAY_VERTEX] = PackedVector3Array(lod_verts)
			#surface_array[Mesh.ARRAY_NORMAL] = PackedVector3Array(lod_normals)
			#surface_array[Mesh.ARRAY_INDEX] = PackedInt32Array(lod_indices)
			#
			## Find which sector the LOD's edges share
			#var e_found = 0
			#for e_face_idx in range(poly_faces.size()):
				#var e_face = poly_faces[e_face_idx]
				#if e_face == face:
					#continue
				## because there are a LOT of faces, we can probably whittle down the numbers 
				## a bit if we filter out faces whose min vertex index is greater
				## than our max and vice versa or filter by centroid distance
				#for e_edge: Edge in perimeter_edges:
					## our local vertex indices point to an index in the face index array
					#if face[e_edge.A] in e_face and face[e_edge.B] in e_face:
						#e_edge.neighbor = e_face_idx
						#e_found += 1
						#break
				#if e_found == perimeter_edges.size():
					#break
			## HLOD ranges
			#if n != lod_count - 1:
				#lod.begin = vis_diff * (lod_count - n - 1)
				#lod.begin_margin = vis_margin
			#lod.end = vis_diff * (lod_count - n)
			#lod.end_margin = vis_margin
			#
			#lod.setup(surface_array, n, terrain_material, perimeter_edges)
			#lod_list.append(lod)
		#
		## 4. Construct sector
		#var sector := preload("res://Planet/Sector.tscn").instantiate()
		#sector.name = "Sector%d" % ctr
		#sector.sector_number = ctr
		#ctr += 1
		#sector.add_lods(lod_list)
		#sector.set_collision_shape(poly_shape)
		## 5. Send sector to terrain grid
		##terrain_grid_node.add_child(sector)
		#sectors_list.append(sector)


## Uniformly subdivides triangles into (div + 1)^2 triangles
## div is number of divisions to make aka the number of points added to each edge
## Perimeter verts is used to detect which newly created edges should be stored in perimeter edges
## This uses what I call midpoint subdivision, so if you provide div with pow(2, n) - 1
## where n is the number of subdivisions, it essentially takes each triangle and
## splits each edge in half n times (creating 4 new triangles like a triforce inside of
## it each time)
static func subdivide_triangles(verts: Array, normals: Array, indices: Array, div: int, perimeter_verts: Array, perimeter_edges: Array[Edge]):
	var indices_out = []
	# A running list of edges we've created to avoid duplication
	var edges = []
	for tri_idx in range(indices.size() / 3):
		var idx_A = indices[tri_idx * 3]
		var idx_B = indices[tri_idx * 3 + 1]
		var idx_C = indices[tri_idx * 3 + 2]
		
		# 1. Get or create midpoints along each edge
		var AB: Edge
		for edge in edges:
			if edge.same_edge(idx_A, idx_B):
				AB = edge
				break
		if AB == null:
			AB = Edge.new(idx_A, idx_B, verts, normals, div)
			edges.append(AB)
		
		var AC: Edge
		for edge in edges:
			if edge.same_edge(idx_A, idx_C):
				AC = edge
				break
		if AC == null:
			AC = Edge.new(idx_A, idx_C, verts, normals, div)
			edges.append(AC)
		
		var BC: Edge
		for edge in edges:
			if edge.same_edge(idx_B, idx_C):
				BC = edge
				break
		if BC == null:
			BC = Edge.new(idx_B, idx_C, verts, normals, div)
			edges.append(BC)
		
		# Find which of these edges is the perimeter one and store it
		if idx_A in perimeter_verts and idx_B in perimeter_verts:
			perimeter_edges.append(AB)
		elif idx_A in perimeter_verts and idx_C in perimeter_verts:
			perimeter_edges.append(AC)
		elif idx_B in perimeter_verts and idx_C in perimeter_verts:
			perimeter_edges.append(BC)
		else:
			printerr("No perimeter edge found in triangle!")
		
		# 2. For every point along AB, starting with A, excepting B, make a triangle strip
		var old_U
		var old_UV: Edge
		# r is our index along the edge AB
		# Each strip has 2r + 1 triangles
		for r in range(div + 1):
			var origin_point = AB.get_point(r, idx_A)
			# C
			# | \
			# |   +
			# |   | \
			# |   |   V
			# |   |   | \
			# B---+---U--A
			# U is the current midpoint along AB
			var U = AB.get_point(r + 1, idx_A)
			# V is the current midpoint along AC
			var V = AC.get_point(r + 1, idx_A)
			var UV: Edge
			if r < div:
				# make a new edge, UV, with r divisions. Should not add any verts on first loop
				UV = Edge.new(U, V, verts, normals, r)
			else:
				# on the last loop UV is BC so we skip edge creation
				UV = BC
			var J = origin_point
			var K = U
			var L
			# t is our index on the triangle strip we're creating
			for t in range(2 * r + 1):
				if t % 2 == 0:
					L = UV.get_point((t / 2) + 1, U)
				else:
					L = old_UV.get_point((t + 1) / 2, old_U)
				indices_out.append_array([J, K, L])
				if t % 2 == 0:
					K = L
				else:
					J = L
			# Prepare old UV stuff for the next strip
			old_U = U
			old_UV = UV
	# Send the new indices back out
	indices.assign(indices_out)


static func setup_icosahedron(verts: Array, faces: Array) -> void:
	const phi := 1.618033988749
	const icosahedron_verts := [
		Vector3 ( 1.0,  0.0,   phi),
		Vector3 ( 1.0,  0.0,  -phi),
		Vector3 (-1.0,  0.0,   phi),
		Vector3 (-1.0,  0.0,  -phi),
		Vector3 (  phi,  1.0,  0.0),
		Vector3 (  phi, -1.0,  0.0),
		Vector3 ( -phi,  1.0,  0.0),
		Vector3 ( -phi, -1.0,  0.0),
		Vector3 ( 0.0,   phi,  1.0),
		Vector3 ( 0.0,   phi, -1.0),
		Vector3 ( 0.0,  -phi,  1.0),
		Vector3 ( 0.0,  -phi, -1.0)
	]
	const icosahedronTris := [
		[10,  2, 0],
		[5, 10,  0],
		[4,  5,  0],
		[8,  4,  0],
		[2,  8,  0],
		[11,  1, 3],
		[7, 11,  3],
		[6,  7,  3],
		[9,  6,  3],
		[1,  9,  3],
		[7,  6,  2],
		[10,  7, 2],
		[11,  7, 10],
		[5, 11,  10],
		[1, 11,  5],
		[4,  1,  5],
		[9,  1,  4],
		[8,  9,  4],
		[6,  9,  8],
		[2,  6,  8]
	]
	# Normalize vertices to a circle of radius 1
	for vtx in icosahedron_verts:
		verts.append(vtx.normalized())
	faces.append_array(icosahedronTris)


static func dual(poly_verts: Array, poly_faces: Array) -> void:
	## the vertices of the dual correspond to the faces of the other and vice versa
	# empty list of new vertices of size of old faces
	var new_verts := []
	new_verts.resize(poly_faces.size())
	# dictionary between vertices and faces
	var new_faces := []
	new_faces.resize(poly_verts.size())
	for i in range(new_faces.size()):
		new_faces[i] = []
	# for each face
	for face_idx in range(poly_faces.size()):
	#  calculate the centroid
		var centroid := comp_centroid(poly_verts, poly_faces[face_idx])
		# add this face to its vertices' dictionary
		# the new faces will be composed of the vertices formed by the faces that share a particular vertex
		for vtx in poly_faces[face_idx]:
			if face_idx not in new_faces[vtx]:
				new_faces[vtx].append(face_idx)
	#  add a new point at the centroid, normalized to the circumsphere's radius
		new_verts[face_idx] = centroid.normalized() ## assuming radius of 1
	#  the index of this point should correspond to the index of its face
	# now make new faces out of the new vertices
	## store for each vertex a list of triangles its in
	## the new faces are made of those triangle's centroids
	## new_faces IS new_faces BUT its not clockwise
	# sort the vertices of the face clockwise based on their angle to an arbitrary point (index 0 here)
	# angle is determined based on the centroid of the face (the vertex it was made from, roughly. its not coplanar but thats fine)
	for face_idx in range(new_faces.size()):
		#var face_center = centroid(new_verts, new_faces[face_idx])
		var face_center = poly_verts[face_idx]
		var comp = new_verts[new_faces[face_idx][0]]
		var sort_clockwise = func(a: int, b: int) -> bool:
			return new_verts[a].signed_angle_to(comp, face_center) < new_verts[b].signed_angle_to(comp, face_center)
		new_faces[face_idx].sort_custom(sort_clockwise)
		
	poly_verts.assign(new_verts)
	poly_faces.assign(new_faces)


static func kis(poly_verts: Array, poly_faces: Array) -> void:
	# raise a pyramid in the center of each face
	# very similar to current triangulation algorithm
	# empty array of new verts of size old_verts + old_faces
	var new_verts := []
	new_verts.assign(poly_verts)
	new_verts.resize(poly_verts.size() + poly_faces.size())
	# empty array of new faces dunno what size
	var new_faces := []
	# for each face
	for face_idx in range(poly_faces.size()):
	#  find its centroid and put a vertex there
		var centroid := comp_centroid(poly_verts, poly_faces[face_idx])
	#  normalize that vertex and put it in the new array
		var centroid_idx := poly_verts.size() + face_idx;
		new_verts[centroid_idx] = centroid.normalized()
	#  add new faces using the triangulation algorithm from before
		for v_idx in range(poly_faces[face_idx].size()):
			new_faces.append([centroid_idx, poly_faces[face_idx][v_idx], poly_faces[face_idx][(v_idx + 1) % poly_faces[face_idx].size()]])
	
	poly_verts.assign(new_verts)
	poly_faces.assign(new_faces)


static func geometrize(poly_verts: Array, poly_faces: Array, poly_normals: Array) -> void:
	# Duplicates every face's vertices and set their normals to their centroid's
	# Turns the sphere into a ball with flat sides basically
	var new_verts := []
	var new_faces := []
	new_faces.resize(poly_faces.size())
	var new_normals := []
	# for each face, copy all of its vertices and use them to make a new face
	for face_idx in range(poly_faces.size()):
		var new_face := []
		new_face.resize(poly_faces[face_idx].size())
		# calculate the centroid alongside loop
		var centroid := Vector3.ZERO
		for v_idx in range(poly_faces[face_idx].size()):
			new_verts.append(poly_verts[poly_faces[face_idx][v_idx]])
			new_face[v_idx] = new_verts.size() - 1
			centroid += poly_verts[poly_faces[face_idx][v_idx]]
		new_faces[face_idx] = new_face
		# set the vertex normals to the centroid
		centroid /= poly_faces[face_idx].size()
		var normals := []
		normals.resize(poly_faces[face_idx].size())
		normals.fill(centroid.normalized())
		new_normals.append_array(normals)
	
	poly_verts.assign(new_verts)
	poly_faces.assign(new_faces)
	poly_normals.assign(new_normals)


static func triangulate(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, poly_verts: Array, poly_faces: Array, skip_triangles = true) -> void:
	## todo for the fancy shapes where every face is not a triangle, resize verts to be +poly_faces.size() bigger and insert, instead of append
	for face in poly_faces:
		## todo unnecessary for non triangular faces again
		if skip_triangles and face.size() == 3: 
			for v in face:
				indices.append(v)
			continue
		# add new vert at centroid
		var centroid := comp_centroid(poly_verts, face)
		verts.append(centroid)
		# add new vertex's normal. this is equal to the face normal in geometrized setups too so its fine
		normals.append(centroid.normalized())
		var centroid_idx := verts.size() - 1
		# loop around vertices in clockwise fashion to wind triangles on face
		## todo don't append here, we know how big this will be for the fancy shapes
		for v_idx in range(1, face.size()):
			indices.append(centroid_idx)
			indices.append(face[v_idx - 1])
			indices.append(face[v_idx])
		# add face that goes from last vert to first vert. this is faster than checking modulo every time
		indices.append(centroid_idx)
		indices.append(face[face.size() - 1])
		indices.append(face[0])


## Returns the centroid of a face
static func comp_centroid(verts: Array, indices: Array) -> Vector3:
	var centroid := Vector3.ZERO
	for idx in indices:
		centroid += verts[idx]
	centroid /= indices.size()
	return centroid
