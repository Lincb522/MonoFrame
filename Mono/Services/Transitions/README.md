# Native transition engine

51 kernels (50 new plus dissolve) vendored unchanged from https://github.com/alexiscn/MTTransitions at `66531b19368f8cd49d55e892db6f273d3fea4205`. MIT license retained in Resources/ThirdParty and individual shader headers.

MTIShaderLib.h is a minimal vertex ABI adapter, not the MetalPetal framework. All shaders compile into the app default Metal library. Native AVVideoCompositing normalizes source frames and uses the same kernels for project preview and export. GPU and missing-frame errors propagate, never substitute another effect.

The shared MTTransitionLib.h compile guard accepts __METAL_VERSION__ to include the iOS Simulator. MTIShaderLib.h also supplies the GLSL-compatible mod helper required by the kernels. Individual .metal kernel bodies are unchanged.
