#include <metal_stdlib>
using namespace metal;

// MARK: - 2D stroke rendering (existing)

struct StrokeVertexOut {
    float4 position [[position]];
    float4 color;
};

struct StrokeUniforms {
    float4x4 mvpMatrix;
};

vertex StrokeVertexOut stroke_vertex(const device float2 *positions [[buffer(0)]],
                                      const device float4 *colors [[buffer(1)]],
                                      constant StrokeUniforms &uniforms [[buffer(2)]],
                                      uint vid [[vertex_id]]) {
    StrokeVertexOut out;
    out.position = uniforms.mvpMatrix * float4(positions[vid], 0.0, 1.0);
    out.color = colors[vid];
    return out;
}

fragment float4 stroke_fragment(StrokeVertexOut in [[stage_in]]) {
    return in.color;
}

// MARK: - 3D mesh rendering

struct MeshVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct MeshVertexOut {
    float4 position [[position]];
    float3 normal;
};

struct MeshUniforms {
    float4x4 mvpMatrix;
    float3 lightDirection;
    float3 baseColor;
};

vertex MeshVertexOut mesh_vertex(MeshVertexIn in [[stage_in]],
                                  constant MeshUniforms &uniforms [[buffer(2)]]) {
    MeshVertexOut out;
    out.position = uniforms.mvpMatrix * float4(in.position, 1.0);
    out.normal = in.normal;
    return out;
}

fragment float4 mesh_fragment(MeshVertexOut in [[stage_in]],
                               constant MeshUniforms &uniforms [[buffer(2)]]) {
    float3 n = normalize(in.normal);
    float3 l = normalize(uniforms.lightDirection);
    float diffuse = max(dot(n, l), 0.0);
    float ambient = 0.4;
    float3 color = uniforms.baseColor * (ambient + diffuse * 0.6);
    return float4(color, 1.0);
}
