## An edge for triangle subdivision
# may be better to not register with class name and instead load resource everywhere that uses it to avoid cluttering global namespace
class_name Edge

var A: int # smaller indexed endpoint
var B: int # larger indexed endpoint
var divisions : Array[int] # midpoints ordered from A to B
var neighbor: int


# div is the number of intermediate points you want between a and b
func _init(a: int, b: int, verts: Array, normals: Array, div: int):
	# for consistency, A must always be the smaller number
	if a < b:
		A = a
		B = b
	else:
		A = b
		B = a
	subdivide(verts, normals, div)


# Subdivides the edge with its intermediate vertices
func subdivide(verts: Array, normals: Array, div: int) -> void:
	var vtx_A = verts[A]
	var vtx_B = verts[B]
	# for each division
	for d in range(div):
		# new vertex will be a fraction of the way along the edge
		# if there are three divisions and we're on the first one it cuts 1/4 of the for example
		var new_vtx = lerp(vtx_A, vtx_B, float(d + 1) / float(div + 1))
		# normalize the vertex to sphereize it
		verts.append(new_vtx.normalized())
		normals.append(new_vtx.normalized()) # project to unit sphere
		divisions.append(verts.size() - 1) # index in verts


# returns the ith closest point on the edge to the endpoint origin. origin should be your A.
# If i is 0, returns origin. If i is div + 1 returns the other endpoint
# If confused, will return A by default
func get_point(i: int, origin: int) -> int:
	if origin == A:
		if i == 0:
			return A
		elif i == divisions.size() + 1:
			return B
		else:
			return divisions[(i - 1)]
	# Not double checking that origin is B cost me 3 days of work...
	elif origin == B:
		if i == 0:
			return B
		elif i == divisions.size() + 1:
			return A
		else:
			return divisions[-1 - (i - 1)]
	else:
		printerr("Origin given for Edge.get_point is not an endpoint!")
		return A


# Returns true if this edge is between points a and b in any order
func same_edge(a: int, b: int) -> bool:
	return (A == a and B == b) or (A == b and B == a)

