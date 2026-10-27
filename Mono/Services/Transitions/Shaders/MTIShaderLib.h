// Minimal stage-input ABI adapter. Shader algorithms remain from MTTransitions (MIT).
#pragma once
#include <metal_stdlib>
#define METAL_FUNC static inline
namespace metalpetal {
using namespace metal;
template<typename T> METAL_FUNC T mod(T x, T y) { return x - y * floor(x / y); }
struct VertexOut { metal::float4 position [[position]]; metal::float2 textureCoordinate; };
}
