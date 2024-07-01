#[compute]
#version 450

// Invocations in the (x, y, z) dimension
// If, for example x and y were set to 2 and z to 1 the invocation IDs in each invocation would look like
// 1st: (0, 0, 0)
// 2nd: (1, 0, 0)
// 3rd: (0, 1, 0)
// 4th: (1, 1, 0)
// So basically each workgroup inokes n - 1 times in each dimension
// Since our y and z local sizes are 1, our workgroup is 1 dimensional
layout(local_size_x = 2, local_size_y = 1, local_size_z = 1) in;

// A binding to the buffer we create in our script
// To access the storage buffer we look in uniform set 0 at binding 0
// The storage buffer is like a struct and a struct is like a class that only contains properties.
//  So after the layout we type buffer and then the "class name" for the buffer (this is like typing struct ClassName)
layout(set = 0, binding = 0, std430) restrict buffer MyDataBuffer {
    // Uninitialized variable of type matching the type we created in GDScript
    float data[];
}
my_data_buffer;

layout(set = 0, binding = 1, std430) restrict buffer BindingTestBuffer {
    // Uninitialized variable of type matching the type we created in GDScript
    float data[];
}
binding_test_buffer;

layout(set = 1, binding = 0, std430) restrict buffer VertexBuffer {
    // Uninitialized variable of type matching the type we created in GDScript
    vec4 data[];
}
vertex_buffer;
// After the curly brackets we type an instance name we use to reference the storage buffer in the main function
//  Notice that all of that is one line of code (semicolons!)

// The code we want to execute in each invocation
void main() {
    // gl_GlobalInvocationID.x uniquely identifies this invocation across all work groups
    // We use x since that is the only value that changes in a 1 dimensional workgroup
    // The invocation ID is unique for each workgroup, so if you had a buffer of size 10 and 2 workgroups of size 5
    //  each workgroup would only go through IDs [0, 1, 2, 3, 4] so you would only touch the first half of your buffer twice here
    //  This only happens if we used local ids, so we should use global ones instead
    vertex_buffer.data[gl_GlobalInvocationID.x] *= 2.0;
    my_data_buffer.data[gl_GlobalInvocationID.x] *= 2.0;
    binding_test_buffer.data[gl_GlobalInvocationID.x] *= 3.0;
    // Workgroups are like a bunch of cubes that make up one big one and each group is made up of a bunch of smaller cubes (invocations).
    //  Rectangular prisms are a more apt image
    // Each invocation has a 3d index within that workgroup cube -- LocalInvocationID
    // Each invocation ALSO has a 3d index in the cube that contains all the workgroups -- GlobalInvocationID
}