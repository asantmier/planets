#[compute]
#version 450

layout(local_size_x = 512, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer VertexBuffer {
    vec4 data[];
}
vertex_buffer;

layout(set = 0, binding = 1, std430) restrict buffer IndexBuffer {
    int data[];
}
index_buffer;

layout(set = 0, binding = 2, std430) restrict buffer FaceNormalBuffer {
    vec4 data[];
}
face_normal_buffer;

// The code we want to execute in each invocation
void main() {
    // https://www.khronos.org/opengl/wiki/Calculating_a_Surface_Normal
    int a = index_buffer.data[gl_GlobalInvocationID.x * 3];
    int b = index_buffer.data[gl_GlobalInvocationID.x * 3 + 1];
    int c = index_buffer.data[gl_GlobalInvocationID.x * 3 + 2];
    vec4 p1 = vertex_buffer.data[a];
    vec4 p2 = vertex_buffer.data[b];
    vec4 p3 = vertex_buffer.data[c];
    vec3 u = p2.xyz - p1.xyz;
    vec3 v = p3.xyz - p1.xyz;
    vec3 n3 = normalize(cross(v, u));
    vec4 n = vec4(n3.x, n3.y, n3.z, 0);
    face_normal_buffer.data[gl_GlobalInvocationID.x] = n;
}
