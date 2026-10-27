#include "MTIShaderLib.h"
using namespace metal;
vertex metalpetal::VertexOut monoTransitionVertex(uint id [[vertex_id]]) {
    const float2 positions[] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
    metalpetal::VertexOut out;
    out.position = float4(positions[id],0,1);
    out.textureCoordinate = (positions[id]+1.0)*0.5;
    return out;
}
