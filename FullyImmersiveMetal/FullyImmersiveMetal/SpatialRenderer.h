#pragma once

#include "ShaderTypes.h"
#include "Mesh.h"

#include <memory>

#import <CompositorServices/CompositorServices.h>
#import <Metal/Metal.h>

class SpatialRenderer {
public:
    SpatialRenderer(cp_layer_renderer_t layerRenderer);
    void drawAndPresent(cp_frame_t frame, cp_drawable_t drawable);

private:
    void makeResources();
    void makeRenderPipelines();
    MTLRenderPassDescriptor* createRenderPassDescriptor(cp_drawable_t drawable, size_t index);
    MTLRenderPassDescriptor* createRenderPassDescriptor1(cp_drawable_t drawable, size_t index);
    PoseConstants poseConstantsForViewIndex(cp_drawable_t drawable, size_t index);

    id<MTLTexture> _colorTexture, _colorTexture1, _depthTexture;
    id<MTLTexture> _cpColorTextures[2];
    id<MTLTexture> _cpDepthTextures[2];
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _environmentRenderPipelineState;
    id<MTLRenderPipelineState> _contentRenderPipelineState;
    id<MTLDepthStencilState> _contentDepthStencilState;
    id<MTLDepthStencilState> _backgroundDepthStencilState;
    cp_layer_renderer_t _layerRenderer;
    std::unique_ptr<TexturedMesh> _globeMesh;
    std::unique_ptr<TexturedMesh> _globeMesh1;
    std::unique_ptr<SpatialEnvironmentMesh> _environmentMesh;
    CFTimeInterval _sceneTime;
    CFTimeInterval _lastRenderTime;
    cp_layer_renderer_layout _layout;
	double _countFPSStart = 0;
	double _fps = 0;
	double _totalGPUTime = 0;
	double _totalCPUDrawTime = 0;
};
