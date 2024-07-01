shader_type spatial;
render_mode shadows_disabled, unshaded;

uniform vec3 albedo: source_color;
uniform float start = 0.05;
uniform float max_height = 0.1;
uniform float alpha_multiplier = 1.0;
uniform float power = 1.0;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	vec3 pos = (inverse(MODEL_MATRIX) * (INV_VIEW_MATRIX * vec4(VERTEX, 1.0))).xyz;
	ALBEDO = albedo;
	ALPHA = pow(1.0 - (clamp(abs(pos.z) - start, 0.0, 1.0) / max_height), power) * alpha_multiplier;
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
