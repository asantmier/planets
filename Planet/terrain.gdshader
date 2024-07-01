shader_type spatial;

#define SECTOR_COUNT 812
#define NUM_CRATERS 200

uniform float snow_height;
uniform float mountain_height;
uniform float grass_height;
uniform float shore_height;
// biome blending radius
uniform float biome_blend: hint_range(0.0, 0.1, 0.001);
uniform float biome_smooth_start = 0.0;
uniform float biome_smooth_end = 1.0;
// triplanar mapping blend
uniform float triplanar_blend_offset: hint_range(0.0, 0.5);
uniform float triplanar_blend_exponent: hint_range(1.0, 8.0);
// cliff constraints
uniform float cliff_steepness: hint_range(0.0, 1.0);
uniform float cliff_radius;
uniform bool smooth_cliffs;
uniform float cliff_biome_color_tweak: hint_range(0.0, 1.0) = 1.0;
// Texture input
group_uniforms Grass;
uniform vec3 mountain_color: source_color;
uniform vec3 grass_color: source_color;
uniform sampler2D grass_tex: source_color;
uniform sampler2D grass_normal_map: hint_normal;
uniform sampler2D grass_roughness;
uniform sampler2D grass_ao_map;
uniform float grass_scale;
group_uniforms Sand;
uniform vec3 shore_color: source_color;
uniform sampler2D sand_tex: source_color;
uniform sampler2D sand_normal_map: hint_normal;
uniform sampler2D sand_roughness;
uniform sampler2D sand_ao_map;
uniform float sand_scale;
group_uniforms Snow;
uniform vec3 snow_color: source_color;
uniform sampler2D snow_tex: source_color;
uniform sampler2D snow_normal_map: hint_normal;
uniform sampler2D snow_roughness;
uniform sampler2D snow_ao_map;
uniform float snow_scale;
group_uniforms Bedrock;
uniform vec3 bedrock_color: source_color;
uniform sampler2D bedrock_tex: source_color;
uniform sampler2D bedrock_normal_map: hint_normal;
uniform sampler2D bedrock_roughness;
uniform sampler2D bedrock_ao_map;
uniform float bedrock_scale;
group_uniforms Cliffs;
uniform vec3 cliff_color: source_color;
uniform sampler2D cliff_tex: source_color;
uniform sampler2D cliff_normal_map: hint_normal;
uniform sampler2D cliff_roughness_map;
uniform sampler2D cliff_ao_map;
uniform float cliff_scale;
group_uniforms;

group_uniforms Craters;
uniform vec3 crater_color: source_color;
uniform sampler2D crater_tex: source_color;
uniform sampler2D crater_normal_map: hint_normal;
uniform sampler2D crater_roughness_map;
uniform sampler2D crater_ao_map;
uniform float crater_scale;
group_uniforms;
uniform float crater_border;
// TODO crater textures and shit

// Per-instance uniforms
instance uniform int lod;
// List of sector lods indexed by their id
uniform int[SECTOR_COUNT] sector_lods;
// We could use sector_lods as a vec2 and use the second element to store
// where a sector's position in the following array begins if we sort it
// Hard limit of 1000 craters, more than this number will be colored wrong
uniform vec4[NUM_CRATERS] craters;
//uniform int craters_length = 0;

// Performs triplanar mapping with the given texture and scale
// Blending is precomputed by the caller
vec3 trimap(sampler2D tex, float scale, vec3 blending, vec3 pos) {
	// triplanar mapping
	// https://catlikecoding.com/unity/tutorials/advanced-rendering/triplanar-mapping/
	vec4 albedo_x = texture(tex, pos.zy * vec2(-1.0, 1.0) * scale);
	vec4 albedo_y = texture(tex, pos.xz * scale);
	vec4 albedo_z = texture(tex, pos.xy * scale);
	//vec3 blending = abs(world_norm);
	//blending = clamp(blending - triplanar_blend_offset, 0.0, 1.0);
	//blending = pow(blending, vec3(triplanar_blend_exponent));
	//blending /= (blending.x + blending.y + blending.z);
	vec4 tribedo = albedo_x * blending.x + albedo_y * blending.y + albedo_z * blending.z;
	return tribedo.xyz;
}

// Calculates a biome's color contribution by height
float get_contribution(float height, float biome_height) {
	// return (height - (biome_height - biome_blend)) / biome_blend;
	return smoothstep(biome_smooth_start, biome_smooth_end, (height - (biome_height - biome_blend)) / biome_blend);
}

void vertex() {
	// Called for every vertex the material is visible on.
	// We have all of the data, next step is to do the do
	if (lod != 0) {
		int adj_sector = int(UV2.r);
		if (adj_sector != -1) {
			int adj_lod = sector_lods[adj_sector];
			if (adj_lod < lod) {
				switch(adj_lod) {
					case 0:
						VERTEX = CUSTOM0.xyz;
						break;
					case 1:
						VERTEX = CUSTOM1.xyz;
						break;
					case 2:
						VERTEX = CUSTOM2.xyz;
						break;
					case 3:
						VERTEX = CUSTOM3.xyz;
						break;
				}
			}
		}
	}
}

void fragment() {
	// Called for every pixel the material is visible on.
	// The following gets coordinates in world space
	//vec3 pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD;
	//vec3 w_norm = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// The following gets coordinates in object space
	vec3 pos = (inverse(MODEL_MATRIX) * (INV_VIEW_MATRIX * vec4(VERTEX, 1.0))).xyz;
	vec3 w_norm =(inverse(MODEL_MATRIX) * (INV_VIEW_MATRIX * vec4(NORMAL, 0.0))).xyz;
	float height = length(pos);
	// Blending precompute
	vec3 blending = abs(w_norm);
	blending = clamp(blending - triplanar_blend_offset, 0.0, 1.0);
	blending = pow(blending, vec3(triplanar_blend_exponent));
	blending /= (blending.x + blending.y + blending.z);
	// 2 ways to blend. do it by height. or do it by sampling nearby points
	// we could calculate steepness by sampling nearby points and use that to color steep areas different
	// since we would be sampling points we can use that for more accurate height sampling too
	// it might be better to output a high resolution heightmap from the compute shader
	
	// 1. biome contribution
	// What if instead we do very little of the sort of blending we have now and instead
	// we used noise on the region border to determine whether something should be one biome
	// or another? Remember this won't be nearly as noticable once there are props on the map
	float bedrock_contrib = 0.0;
	float shore_contrib = 0.0;
	float grass_contrib = 0.0;
	float mountain_contrib = 0.0;
	float snow_contrib = 0.0;
	float remaining = 1.0; // tracks unallocated biome contribution
	snow_contrib = remaining * get_contribution(height, snow_height);
	remaining -= snow_contrib;
	mountain_contrib = remaining * get_contribution(height, mountain_height);
	remaining -= mountain_contrib;
	grass_contrib = remaining * get_contribution(height, grass_height);
	remaining -= grass_contrib;
	shore_contrib = remaining * get_contribution(height, shore_height);
	remaining -= shore_contrib;
	bedrock_contrib = remaining;
	// 2. biome colors
	vec3 height_color = (bedrock_contrib * trimap(bedrock_tex, bedrock_scale, blending, pos) * bedrock_color) 
		+ (shore_contrib * trimap(sand_tex, sand_scale, blending, pos) * shore_color) 
		+ (grass_contrib * trimap(grass_tex, grass_scale, blending, pos) * grass_color) 
		+ (mountain_contrib * trimap(grass_tex, grass_scale, blending, pos) * mountain_color) 
		+ (snow_contrib * trimap(snow_tex, snow_scale, blending, pos) * snow_color);
	vec3 height_normal = (bedrock_contrib * trimap(bedrock_normal_map, bedrock_scale, blending, pos)) 
		+ (shore_contrib * trimap(sand_normal_map, sand_scale, blending, pos)) 
		+ (grass_contrib * trimap(grass_normal_map, grass_scale, blending, pos)) 
		+ (mountain_contrib * trimap(grass_normal_map, grass_scale, blending, pos)) 
		+ (snow_contrib * trimap(snow_normal_map, snow_scale, blending, pos));
	float height_roughness = length((bedrock_contrib * trimap(bedrock_roughness, bedrock_scale, blending, pos)) 
		+ (shore_contrib * trimap(sand_roughness, sand_scale, blending, pos)) 
		+ (grass_contrib * trimap(grass_roughness, grass_scale, blending, pos)) 
		+ (mountain_contrib * trimap(grass_roughness, grass_scale, blending, pos)) 
		+ (snow_contrib * trimap(snow_roughness, snow_scale, blending, pos)));
	float height_ao = length((bedrock_contrib * trimap(bedrock_ao_map, bedrock_scale, blending, pos)) 
		+ (shore_contrib * trimap(sand_ao_map, sand_scale, blending, pos)) 
		+ (grass_contrib * trimap(grass_ao_map, grass_scale, blending, pos)) 
		+ (mountain_contrib * trimap(grass_ao_map, grass_scale, blending, pos)) 
		+ (snow_contrib * trimap(snow_ao_map, snow_scale, blending, pos)));
		
	// 3. cliff factor
	vec3 sphere_norm = normalize(pos);
	// angle will be 0 when the surface normal is perpendicular to the sphere normal
	float angle = dot(w_norm, sphere_norm);
	float cliff_factor = 0.0;
	// checks if angle is more perpendicular to the sphere than the specified constraint
	if (angle < cliff_steepness) {
		float x = cliff_steepness - angle; // > r = 1, < r = something <1
		// can change the clamp's max to force biome to always affect cliff color
		cliff_factor = clamp(pow(((1.0 / cliff_radius) * x), 2.0), 0.0, cliff_biome_color_tweak);
		if (smooth_cliffs) {
			cliff_factor = smoothstep(0.0, 1.0, cliff_factor); // sharpens cliffs
		}
	}
	// TODO could try multiplying cliff albedo with biome color modifier
	vec3 cliff_albedo = trimap(cliff_tex, cliff_scale, blending, pos) * cliff_color;
	vec3 cliff_normal = trimap(cliff_normal_map, cliff_scale, blending, pos);
	float cliff_roughness = length(trimap(cliff_roughness_map, cliff_scale, blending, pos));
	float cliff_ao = length(trimap(cliff_ao_map, cliff_scale, blending, pos));
	
	// NOW! Since conditionals don't make shader execution faster, we can check
	// if we're in a crater and how to handle that
	int closest_crater = -1;
	for (int i = 0; i < NUM_CRATERS; i++) {
		// Instead of .w being radius, make it a combination of radius and rim width
		// Then sort of blur it in this shader
		if (length(normalize(craters[i].xyz) - normalize(pos)) < craters[i].w) {
			closest_crater = i;
		}
	}
	vec3 crater_albedo = trimap(crater_tex, crater_scale, blending, pos) * crater_color;
	vec3 crater_normal = trimap(crater_normal_map, crater_scale, blending, pos);
	float crater_roughness = length(trimap(crater_roughness_map, crater_scale, blending, pos));
	float crater_ao = length(trimap(crater_ao_map, crater_scale, blending, pos));
	
	// 4. output
	if (closest_crater == -1) {
		// Normal output
		ALBEDO = height_color * (1.0 - cliff_factor) + cliff_albedo * cliff_factor;
		NORMAL_MAP = height_normal * (1.0 - cliff_factor) + cliff_normal * cliff_factor;
		ROUGHNESS = height_roughness * (1.0 - cliff_factor) + cliff_roughness * cliff_factor;
		AO = height_ao * (1.0 - cliff_factor) + cliff_ao * cliff_factor;
	} else {
		// Crater output
		// We will base the final color on the closest crater to the fragment
		ALBEDO = crater_albedo;
		NORMAL_MAP = crater_normal;
		ROUGHNESS = crater_roughness;
		AO = crater_ao;
	}
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
