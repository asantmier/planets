shader_type spatial;

// Needs to know angle of the sun to draw specular highlight in waves
global uniform vec3 sun_dir;

uniform vec3 deepCol : source_color;
uniform vec3 shallowCol : source_color;
uniform float depthMultiplier;
uniform float alpha_multiplier;
//uniform vec3 dir_to_sun;
uniform float smoothness : hint_range(0.0, 1.0);
uniform vec3 specular_color : source_color;
uniform sampler2D depth_texture: source_color, hint_depth_texture;
uniform sampler2D normal_a: hint_normal;
uniform sampler2D normal_b: hint_normal;
uniform float wave_scale;
uniform float wave_speed;
uniform vec2 wave_a_mult;
uniform vec2 wave_b_mult;
uniform float wave_strength: hint_range(0.0, 1.0);
uniform float min_diffuse;

varying vec3 v_norm;

void vertex() {
	// Called for every vertex the material is visible on.
	v_norm = normalize(VERTEX);
}

void fragment() {
	// Called for every pixel the material is visible on.
	//ALBEDO = albedo;
	
	// https://www.reddit.com/r/godot/comments/jpreaw/i_finally_figured_out_how_to_make_a_working_depth/
	// https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html#depth-texture
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).x; // nonlinear between 0 and 1
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth); // vulkan z is between 0 and 1, if change to opengl z is between -1 and 1. x and y are always -1 to 1
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	// z value will be the distance to the point
	float linear_depth = -view.z; // camera faces -z so we have to negate it
	
	// Vertex.z is in view space, and camera looks towards -z axis in view space
	float surface_depth = linear_depth + VERTEX.z;
	//ALBEDO = surface_depth * vec3(1, 1, 1);
	float optical_depth = 1.0 - exp(-surface_depth * depthMultiplier);
	vec3 oceanColor = mix(shallowCol, deepCol, optical_depth);
	float alpha = 1.0 - exp(-surface_depth * alpha_multiplier);
	
	vec3 ocean_norm = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD);
	
	vec2 wave_offset_a = vec2(TIME * wave_speed * wave_a_mult.x, TIME * wave_speed * wave_a_mult.y);
	vec2 wave_offset_b = vec2(TIME * wave_speed * wave_b_mult.x, TIME * wave_speed * wave_b_mult.y);
	vec3 wave_norm = texture(normal_a, UV * wave_scale + wave_offset_a).xyz;
	wave_norm += texture(normal_b, UV * wave_scale + wave_offset_b).xyz;
	wave_norm = normalize(mix(ocean_norm, wave_norm, wave_strength));
	
	vec3 dir_to_sun = -sun_dir;
	// https://paroj.github.io/gltut/Illumination/Tut11%20BlinnPhong%20Model.html
	// Model used here is guassian based on wikipedia article on specular highlights
	vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 1.0)).xyz);
	//vec3 h = normalize(dir_to_sun + ((dir_to_sun - view_dir) / 2.0));
	vec3 h = normalize(dir_to_sun + view_dir);
	float specular_angle = acos(dot(h, wave_norm));
	float specular_exponent = specular_angle / smoothness;
	float specular_highlight = exp(-specular_exponent * specular_exponent);
	float diffuse_component = clamp(dot(ocean_norm, dir_to_sun), min_diffuse, 1.0);
	oceanColor = oceanColor * diffuse_component + specular_highlight * specular_color;
	
	ALBEDO = oceanColor;
	ALPHA = alpha;
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
