shader_type spatial;
render_mode depth_prepass_alpha;

uniform vec3 base_color : source_color;
uniform vec3 ocean_color : source_color;
uniform sampler2D depth_texture: source_color, hint_depth_texture;
uniform float ocean_radius;

// Returns dstToSphere, dstThroughSphere
// If inside sphere, dstToSphere will be 0
// If misses sphere, dstToSphere = approx float max, dstThroughSphere = 0
// rayDir must be normalized
vec2 ray_sphere(vec3 center, float radius, vec3 rayOrigin, vec3 rayDir) {
	vec3 offset = rayOrigin - center;
	//const float a = 1.0; // equal to dot(rayDir, rayDir) aka magnitude
	float a = dot(rayDir, rayDir);
	float b = 2.0 * dot(rayDir, offset);
	float c = dot(offset, offset) - (radius * radius);
	float discriminant = b * b - 4.0 * a * c;
	// < 0 : no intersections
	// = 0 : 1 intersection
	// > 0 : 2 intersections
	if (discriminant > 0.0) {
		float s = sqrt(discriminant);
		float dstToSphereNear = max(0, (-b - s) / (2.0 * a));
		float dstToSphereFar = (-b + s) / (2.0 * a);
		if (dstToSphereFar >= 0.0) {
			return vec2(dstToSphereNear, dstToSphereFar - dstToSphereNear);
		}
	}
	// ray did not intersect sphere
	return vec2(3.4028237e37, 0);
}

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// https://www.reddit.com/r/godot/comments/jpreaw/i_finally_figured_out_how_to_make_a_working_depth/
	// Called for every pixel the material is visible on.
	vec3 original_col = base_color;
	// https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html#depth-texture
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).x; // nonlinear between 0 and 1
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth); // vulkan z is between 0 and 1, if change to opengl z is between -1 and 1. x and y are always -1 to 1
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	// z value will be the distance to the point
	float linear_depth = -view.z; // camera faces -z so we have to negate it
	
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 world_pos = world.xyz / world.w;
	//vec3 ray_pos = CAMERA_POSITION_WORLD;
	vec3 ray_pos = (PROJECTION_MATRIX * VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 ray_dir = normalize(view.xyz); //Normalized vector from fragment position to camera (in view space).
	//vec3 ray_dir = -VIEW;
	vec2 hit_info = ray_sphere(NODE_POSITION_WORLD, ocean_radius, world_pos, ray_dir);
	float dst_to_ocean = hit_info.x;
	float dst_thru_ocean = hit_info.y;
	float ocean_view_depth = min(dst_thru_ocean, linear_depth - dst_to_ocean);
	
	if (dst_to_ocean < linear_depth) {
	//if (distance(world_pos, vec3(0, 0, 0)) <= ocean_radius) {
		ALBEDO = ocean_color;
	} else {
		ALBEDO = original_col;
	}
	
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
