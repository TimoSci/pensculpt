#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct Uniforms {
    float4x4 mvpMatrix;
};

vertex VertexOut vertex_main(const device float2 *positions [[buffer(0)]],
                             const device float4 *colors [[buffer(1)]],
                             constant Uniforms &uniforms [[buffer(2)]],
                             uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = uniforms.mvpMatrix * float4(positions[vid], 0.0, 1.0);
    out.color = colors[vid];
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
