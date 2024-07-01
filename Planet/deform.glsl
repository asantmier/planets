#[compute]
#version 450

//
// Description : Array and textureless GLSL 2D/3D/4D simplex 
//               noise functions.
//      Author : Ian McEwan, Ashima Arts.
//  Maintainer : stegu
//     Lastmod : 20201014 (stegu)
//     License : Copyright (C) 2011 Ashima Arts. All rights reserved.
//               Distributed under the MIT License. See LICENSE file.
//               https://github.com/ashima/webgl-noise
//               https://github.com/stegu/webgl-noise
// 

vec3 mod289(vec3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289(vec4 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
     return mod289(((x*34.0)+10.0)*x);
}

vec4 taylorInvSqrt(vec4 r)
{
  return 1.79284291400159 - 0.85373472095314 * r;
}

float snoise(vec3 v)
{ 
  const vec2  C = vec2(1.0/6.0, 1.0/3.0) ;
  const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

  // First corner
  vec3 i  = floor(v + dot(v, C.yyy) );
  vec3 x0 =   v - i + dot(i, C.xxx) ;

  // Other corners
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min( g.xyz, l.zxy );
  vec3 i2 = max( g.xyz, l.zxy );

  //   x0 = x0 - 0.0 + 0.0 * C.xxx;
  //   x1 = x0 - i1  + 1.0 * C.xxx;
  //   x2 = x0 - i2  + 2.0 * C.xxx;
  //   x3 = x0 - 1.0 + 3.0 * C.xxx;
  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy; // 2.0*C.x = 1/3 = C.y
  vec3 x3 = x0 - D.yyy;      // -1.0+3.0*C.x = -0.5 = -D.y

  // Permutations
  i = mod289(i); 
  vec4 p = permute( permute( permute( 
              i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
            + i.y + vec4(0.0, i1.y, i2.y, 1.0 )) 
            + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));

  // Gradients: 7x7 points over a square, mapped onto an octahedron.
  // The ring size 17*17 = 289 is close to a multiple of 49 (49*6 = 294)
  float n_ = 0.142857142857; // 1.0/7.0
  vec3  ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);  //  mod(p,7*7)

  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_ );    // mod(j,N)

  vec4 x = x_ *ns.x + ns.yyyy;
  vec4 y = y_ *ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4( x.xy, y.xy );
  vec4 b1 = vec4( x.zw, y.zw );

  //vec4 s0 = vec4(lessThan(b0,0.0))*2.0 - 1.0;
  //vec4 s1 = vec4(lessThan(b1,0.0))*2.0 - 1.0;
  vec4 s0 = floor(b0)*2.0 + 1.0;
  vec4 s1 = floor(b1)*2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));

  vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
  vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

  vec3 p0 = vec3(a0.xy,h.x);
  vec3 p1 = vec3(a0.zw,h.y);
  vec3 p2 = vec3(a1.xy,h.z);
  vec3 p3 = vec3(a1.zw,h.w);

  //Normalise gradients
  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;

  // Mix final noise value
  vec4 m = max(0.5 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m;
  return 105.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1), 
                                dot(p2,x2), dot(p3,x3) ) );
}
// End glsl simplex code https://github.com/ashima/webgl-noise/blob/master/src/noise2D.glsl

// Invocations in the (x, y, z) dimension
// If, for example x and y were set to 2 and z to 1 the invocation IDs in each invocation would look like
// 1st: (0, 0, 0)
// 2nd: (1, 0, 0)
// 3rd: (0, 1, 0)
// 4th: (1, 1, 0)
// So basically each workgroup inokes n - 1 times in each dimension
// Since our y and z local sizes are 1, our workgroup is 1 dimensional
layout(local_size_x = 512, local_size_y = 1, local_size_z = 1) in;

// A binding to the buffer we create in our script
// To access the storage buffer we look in uniform set 0 at binding 0
// The storage buffer is like a struct and a struct is like a class that only contains properties.
//  So after the layout we type buffer and then the "class name" for the buffer (this is like typing struct ClassName)
layout(set = 0, binding = 0, std430) restrict buffer BaseVertexBuffer {
    // Uninitialized variable of type matching the type we created in GDScript
    vec4 data[];
}
base_vertex_buffer;

layout(set = 1, binding = 0, std430) restrict buffer VertexBuffer {
    // Uninitialized variable of type matching the type we created in GDScript
    vec4 data[];
}
vertex_buffer;

layout(set = 1, binding = 1, std430) restrict buffer NormalBuffer {
    // Uninitialized variable of type matching the type we created in GDScript
    vec4 data[];
}
normal_buffer;

// This buffer should contain just a single float element
// layout(set = 2, binding = 0, std430) restrict buffer FrequencyBuffer {
//     // Uninitialized variable of type matching the type we created in GDScript
//     float data[];
// }
// frequency_buffer;
// float frequency = frequency_buffer.data[0];

layout(set = 2, binding = 0, std430) restrict buffer FloatSettingsBuffer {
    float d;
    float ridge_smoothing_offset;
    float rim_width;
    float rim_steepness;
    float smoothness;
    float num_craters;
    float ridge_layers; // secretly an int
    float ridge_scale;
    float ridge_persistence;
    float ridge_elevation;
    float ridge_offsetx;
    float ridge_offsety;
    float ridge_offsetz;
    float ridge_lacunarity;
    float ridge_power;
    float ridge_gain;
    float ridge_vertical_shift;
    float ridge_peak_smoothing;
    float shape_layers; // secretly an int
    float shape_scale;
    float shape_persistence;
    float shape_elevation;
    float shape_offsetx;
    float shape_offsety;
    float shape_offsetz;
    float shape_lacunarity;
    float shape_vertical_shift;
    float det_r_layers; // secretly an int
    float det_r_scale;
    float det_r_persistence;
    float det_r_elevation;
    float det_r_offsetx;
    float det_r_offsety;
    float det_r_offsetz;
    float det_r_lacunarity;
    float det_r_power;
    float det_r_gain;
    float det_r_vertical_shift;
    float det_s_layers; // secretly an int
    float det_s_scale;
    float det_s_persistence;
    float det_s_elevation;
    float det_s_offsetx;
    float det_s_offsety;
    float det_s_offsetz;
    float det_s_lacunarity;
    float det_s_vertical_shift;
    float continent_layers; // secretly an int
    float continent_scale;
    float continent_persistence;
    float continent_elevation;
    float continent_offsetx;
    float continent_offsety;
    float continent_offsetz;
    float continent_lacunarity;
    float continent_vertical_shift;
    float ocean_floor_depth;
    float ocean_floor_smoothing;
    float ocean_depth_multiplier;
    float mountain_layers; // secretly an int
    float mountain_scale;
    float mountain_persistence;
    float mountain_elevation;
    float mountain_offsetx;
    float mountain_offsety;
    float mountain_offsetz;
    float mountain_lacunarity;
    float mountain_power;
    float mountain_gain;
    float mountain_vertical_shift;
    float mask_layers; // secretly an int
    float mask_scale;
    float mask_persistence;
    float mask_elevation;
    float mask_offsetx;
    float mask_offsety;
    float mask_offsetz;
    float mask_lacunarity;
    float mask_vertical_shift;
    float mountain_blend;
} 
settings_buffer;

layout(set = 2, binding = 1, std430) restrict buffer CraterBuffer {
    vec4 data[];
    // this data cloaks a vec3 center, float radius, float floor height, and then 3 blank floats
} 
craters;

float rim_width = settings_buffer.rim_width;
float rim_steepness = settings_buffer.rim_steepness;
float smoothness = settings_buffer.smoothness;
float num_craters = settings_buffer.num_craters;

float d = settings_buffer.d;

int   ridge_layers = int(settings_buffer.ridge_layers);
float ridge_scale = settings_buffer.ridge_scale;
float ridge_persistence = settings_buffer.ridge_persistence;
float ridge_elevation = settings_buffer.ridge_elevation;
vec3  ridge_offset = vec3(settings_buffer.ridge_offsetx, settings_buffer.ridge_offsety, settings_buffer.ridge_offsetz);
float ridge_lacunarity = settings_buffer.ridge_lacunarity;
float ridge_power = settings_buffer.ridge_power;
float ridge_gain = settings_buffer.ridge_gain;
float ridge_vertical_shift = settings_buffer.ridge_vertical_shift;
float ridge_peak_smoothing = settings_buffer.ridge_peak_smoothing;

int   shape_layers = int(settings_buffer.shape_layers);
float shape_scale = settings_buffer.shape_scale;
float shape_persistence = settings_buffer.shape_persistence;
float shape_elevation = settings_buffer.shape_elevation;
vec3  shape_offset = vec3(settings_buffer.shape_offsetx, settings_buffer.shape_offsety, settings_buffer.shape_offsetz);
float shape_lacunarity = settings_buffer.shape_lacunarity;
float shape_vertical_shift = settings_buffer.shape_vertical_shift;

int   det_r_layers = int(settings_buffer.det_r_layers);
float det_r_scale = settings_buffer.det_r_scale;
float det_r_persistence = settings_buffer.det_r_persistence;
float det_r_elevation = settings_buffer.det_r_elevation;
vec3  det_r_offset = vec3(settings_buffer.det_r_offsetx, settings_buffer.det_r_offsety, settings_buffer.det_r_offsetz);
float det_r_lacunarity = settings_buffer.det_r_lacunarity;
float det_r_power = settings_buffer.det_r_power;
float det_r_gain = settings_buffer.det_r_gain;
float det_r_vertical_shift = settings_buffer.det_r_vertical_shift;

int   det_s_layers = int(settings_buffer.det_s_layers);
float det_s_scale = settings_buffer.det_s_scale;
float det_s_persistence = settings_buffer.det_s_persistence;
float det_s_elevation = settings_buffer.det_s_elevation;
vec3  det_s_offset = vec3(settings_buffer.det_s_offsetx, settings_buffer.det_s_offsety, settings_buffer.det_s_offsetz);
float det_s_lacunarity = settings_buffer.det_s_lacunarity;
float det_s_vertical_shift = settings_buffer.det_s_vertical_shift;

float ridge_smoothing_offset = settings_buffer.ridge_smoothing_offset;

// Continent
int   continent_layers = int(settings_buffer.continent_layers);
float continent_scale = settings_buffer.continent_scale;
float continent_persistence = settings_buffer.continent_persistence;
float continent_elevation = settings_buffer.continent_elevation;
vec3  continent_offset = vec3(settings_buffer.continent_offsetx, settings_buffer.continent_offsety, settings_buffer.continent_offsetz);
float continent_lacunarity = settings_buffer.continent_lacunarity;
float continent_vertical_shift = settings_buffer.continent_vertical_shift;
// Ocean
float ocean_floor_depth = settings_buffer.ocean_floor_depth;
float ocean_floor_smoothing = settings_buffer.ocean_floor_smoothing;
float ocean_depth_multiplier = settings_buffer.ocean_depth_multiplier;
// Mountains
int   mountain_layers = int(settings_buffer.mountain_layers);
float mountain_scale = settings_buffer.mountain_scale;
float mountain_persistence = settings_buffer.mountain_persistence;
float mountain_elevation = settings_buffer.mountain_elevation;
vec3  mountain_offset = vec3(settings_buffer.mountain_offsetx, settings_buffer.mountain_offsety, settings_buffer.mountain_offsetz);
float mountain_lacunarity = settings_buffer.mountain_lacunarity;
float mountain_power = settings_buffer.mountain_power;
float mountain_gain = settings_buffer.mountain_gain;
float mountain_vertical_shift = settings_buffer.mountain_vertical_shift;
// Mask
int   mask_layers = int(settings_buffer.mask_layers);
float mask_scale = settings_buffer.mask_scale;
float mask_persistence = settings_buffer.mask_persistence;
float mask_elevation = settings_buffer.mask_elevation;
vec3  mask_offset = vec3(settings_buffer.mask_offsetx, settings_buffer.mask_offsety, settings_buffer.mask_offsetz);
float mask_lacunarity = settings_buffer.mask_lacunarity;
float mask_vertical_shift = settings_buffer.mask_vertical_shift;

float mountain_blend = settings_buffer.mountain_blend;



float smooth_min(float a, float b, float k) {
    float h = clamp((b - a + k) / (2 * k), 0, 1);
    return a * h + b * (1 - h) - k * h * (1 - h);
}

float blend(float startHeight, float blendDst, float height) {
  return smoothstep(startHeight - blendDst / 2, startHeight + blendDst / 2, height);
}

// Offset the point you're sampling the noise at with more noise to get a warp effect
// 1 - |noise| gives you a ridge-like appearance
// Power gives you steeper slopes
float ridge_noise(
  vec3 pos, vec3 offset, int layers, float persistence, float lacunarity, float scale,
   float multiplier, float power, float gain, float v_shift) {
  float noise_sum = 0;
  float amplitude = 1;
  float frequency = scale;
  float ridge_weight = 1;

  for (int i = 0; i < layers; i++) {
    // Sample noise function and add to the result  
    float noise_val = 1 - abs(snoise(pos * frequency + offset));
    noise_val = pow(abs(noise_val), power);
    noise_val *= ridge_weight;
    ridge_weight = clamp(noise_val * gain, 0, 1.0);

    noise_sum += noise_val * amplitude;
    // Make each layer increaasingly detailed
    frequency *= lacunarity;
    // Make each layer contribute increasingly less to the result
    amplitude *= persistence;
  }

  return noise_sum * multiplier + v_shift;
}

// Samples the noise at small offsets from the center and averages
float smooth_ridge_noise(
  vec3 pos, vec3 offset, int layers, float persistence, float lacunarity, float scale,
   float multiplier, float power, float gain, float v_shift) {
    vec3 sphere_normal = normalize(pos);
    vec3 A = cross(sphere_normal, vec3(0, 1, 0));
    vec3 B = cross(sphere_normal, A);

    float sum = 0.0;
    sum += ridge_noise(pos, offset, layers, persistence, lacunarity, scale, multiplier, power, gain, v_shift);
    sum += ridge_noise(pos - A * ridge_smoothing_offset, offset, layers, persistence, lacunarity, scale, multiplier, power, gain, v_shift);
    sum += ridge_noise(pos + A * ridge_smoothing_offset, offset, layers, persistence, lacunarity, scale, multiplier, power, gain, v_shift);
    sum += ridge_noise(pos - B * ridge_smoothing_offset, offset, layers, persistence, lacunarity, scale, multiplier, power, gain, v_shift);
    sum += ridge_noise(pos + B * ridge_smoothing_offset, offset, layers, persistence, lacunarity, scale, multiplier, power, gain, v_shift);

    return sum / 5;
}

// Basic fractal noise like shown in the video
float simple_noise(
  vec3 pos, vec3 offset, int layers, float persistence, float lacunarity, float scale,
   float multiplier, float v_shift) {
    float noise_sum = 0;
    float amplitude = 1;
    float frequency = scale;
    for (int i = 0; i < layers; i++) {
      noise_sum += snoise(pos * frequency + offset) * amplitude;
      amplitude *= persistence;
      frequency *= lacunarity;
    }
    return noise_sum * multiplier + v_shift;
}

float get_height(vec3 vertex) {
    float crater_height = 0.0;

    for (int i = 0; i < num_craters; i++) {
        // craters.data[i].xyz is the crater's center, craters.data[i].w is its radius
        float x = length(vertex.xyz - craters.data[i*2].xyz) / craters.data[i*2].w;

        float cavity = x * x - 1;
        float rimX = min(x - 1 - rim_width, 0);
        float rim = rim_steepness * rimX * rimX;

        // craters.data[i*2+1].x is floor height
        float crater_shape = smooth_min(cavity, craters.data[i*2+1].x, -smoothness);
        crater_shape = smooth_min(crater_shape, rim, smoothness);
        crater_height += crater_shape * craters.data[i*2].w;
    }

    // Moon
    // Apparently "multiplier" is ridge elevation
    float r_noise = smooth_ridge_noise(vertex, ridge_offset, ridge_layers, ridge_persistence,
       ridge_lacunarity, ridge_scale, ridge_elevation, ridge_power, ridge_gain, ridge_vertical_shift);
    float shape_noise = simple_noise(vertex, shape_offset, shape_layers, shape_persistence,
      shape_lacunarity, shape_scale, shape_elevation, shape_vertical_shift);
    float detail_ridge_noise = smooth_ridge_noise(vertex, det_r_offset, det_r_layers, det_r_persistence,
       det_r_lacunarity, det_r_scale, det_r_elevation, det_r_power, det_r_gain, det_r_vertical_shift);
    float detail_shape_noise = simple_noise(vertex, det_s_offset, det_s_layers, det_s_persistence,
      det_s_lacunarity, det_s_scale, det_s_elevation, det_s_vertical_shift);
    // Earth
    float continent_shape = simple_noise(vertex, continent_offset, continent_layers, continent_persistence,
      continent_lacunarity, continent_scale, continent_elevation, continent_vertical_shift);
    continent_shape = smooth_min(continent_shape, -ocean_floor_depth, -ocean_floor_smoothing);
    if (continent_shape < 0) {
      continent_shape *= 1 + ocean_depth_multiplier;
    }
    float mountain_shape = smooth_ridge_noise(vertex, mountain_offset, mountain_layers, mountain_persistence,
       mountain_lacunarity, mountain_scale, mountain_elevation, mountain_power, mountain_gain, mountain_vertical_shift);
    float mask = blend(0, mountain_blend, simple_noise(vertex, mask_offset, mask_layers, mask_persistence,
      mask_lacunarity, mask_scale, mask_elevation, mask_vertical_shift));

    // 1 is just some elevation multiplier
    float noise_height = (r_noise + shape_noise + detail_ridge_noise + detail_shape_noise + continent_shape + mountain_shape * mask) * 1;

    float height = 1 + crater_height + noise_height;
    return height;
}

// The code we want to execute in each invocation
void main() {
    // gl_GlobalInvocationID.x uniquely identifies this invocation across all work groups
    // We use x since that is the only value that changes in a 1 dimensional workgroup
    // The invocation ID is unique for each workgroup, so if you had a buffer of size 10 and 2 workgroups of size 5
    //  each workgroup would only go through IDs [0, 1, 2, 3, 4] so you would only touch the first half of your buffer twice here
    //  This only happens if we used local ids, so we should use global ones instead
    // Ignore the w component, it doesn't matter
    
    vec4 vertex = base_vertex_buffer.data[gl_GlobalInvocationID.x];

    // float crater_height = 0.0;

    // for (int i = 0; i < num_craters; i++) {
    //     // craters.data[i].xyz is the crater's center, craters.data[i].w is its radius
    //     float x = length(vertex.xyz - craters.data[i].xyz) / craters.data[i].w;

    //     float cavity = x * x - 1;
    //     float rimX = min(x - 1 - rim_width, 0);
    //     float rim = rim_steepness * rimX * rimX;

    //     float crater_shape = smooth_min(cavity, floor_height, -smoothness);
    //     crater_shape = smooth_min(crater_shape, rim, smoothness);
    //     crater_height += crater_shape * craters.data[i].w;
    // }

    // float height = 1 + crater_height;
    float height = get_height(vec3(vertex));
    vec4 h = base_vertex_buffer.data[gl_GlobalInvocationID.x] * height;
    // vec3 h = vertex * height;
    vertex_buffer.data[gl_GlobalInvocationID.x] = base_vertex_buffer.data[gl_GlobalInvocationID.x] * height;
    // vertex_buffer.data[gl_GlobalInvocationID.x] = vec4(h, 0.0);

    // Perform the same calculations for u and v
    // Using a heightmap function of the form h(x, y), compute tangents U and V where
    // U = h(x + d, y) - h(x, y) and V = h(x, y + d) - h(x, y) 
    // where d is a small number that makes sense for your sampling size
    // Their cross product, UxV is an approximate normal
    
    // This method calculates vertex normals using the tangents
    // Convert vertex position into polar coordinates
    // Get U and V from polar transformations
    float theta = atan(vertex.y, vertex.x);
    float phi = acos(vertex.z);
    vec3 U = vec3(cos(theta + d) * sin(phi), sin(theta + d) * sin(phi), cos(phi));
    U = (U * get_height(U)) - h.xyz;
    vec3 V = vec3(cos(theta) * sin(phi + d), sin(theta) * sin(phi + d), cos(phi + d));
    V = (V * get_height(V)) - h.xyz;
    vec3 n = normalize(cross(V, U));
    // Try doing this for the -d direction in both axes as well and aveage the results
    normal_buffer.data[gl_GlobalInvocationID.x] = vec4(n.x, n.y, n.z, 0);

    // Workgroups are like a bunch of cubes that make up one big one and each group is made up of a bunch of smaller cubes (invocations).
    //  Rectangular prisms are a more apt image
    // Each invocation has a 3d index within that workgroup cube -- LocalInvocationID
    // Each invocation ALSO has a 3d index in the cube that contains all the workgroups -- GlobalInvocationID
}