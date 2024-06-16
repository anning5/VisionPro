
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float2 texCoords [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 viewNormal;
    float2 texCoords;
    uint view
//		[[render_target_array_index]]
		;
};

struct PoseConstants {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
};

struct InstanceConstants {
    float4x4 modelMatrix;
};

[[vertex]]
VertexOut vertex_main(VertexIn in [[stage_in]],
                      uint viewID [[amplification_id]],
                      uint instanceID [[instance_id]],
                             constant PoseConstants *pose [[buffer(1)]],
                             constant InstanceConstants &instance [[buffer(2)]])
{
    VertexOut out;

//    out.position = pose[viewID].projectionMatrix * pose[viewID].viewMatrix * instance.modelMatrix * float4(in.position, 1.0f);
//    out.viewNormal = (pose[viewID].viewMatrix * instance.modelMatrix * float4(in.normal, 0.0f)).xyz;

    out.position = pose[0].projectionMatrix * pose[0].viewMatrix * instance.modelMatrix * float4(in.position, 1.0f);
    out.viewNormal = (pose[0].viewMatrix * instance.modelMatrix * float4(in.normal, 0.0f)).xyz;

//    out.position = pose[instanceID].projectionMatrix * pose[instanceID].viewMatrix * instance.modelMatrix * float4(in.position, 1.0f);
//    out.viewNormal = (pose[instanceID].viewMatrix * instance.modelMatrix * float4(in.normal, 0.0f)).xyz;

    out.texCoords = in.texCoords;
    out.texCoords.x = 1.0f - out.texCoords.x; // Flip uvs horizontally to match Model I/O
    out.view = instanceID;
    return out;
}

[[fragment]]
float4 fragment_main(VertexOut in [[stage_in]],
                     uint viewID [[amplification_id]],
                            texture2d_array<float> texture [[texture(0)]])
{
    constexpr sampler environmentSampler(coord::normalized,
                                         filter::linear,
                                         mip_filter::none,
                                         address::repeat);

    float4 color = texture.sample(environmentSampler, in.texCoords, 0);
    return color;
}
