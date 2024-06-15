
#include "SpatialRenderer.h"
#include "Mesh.h"
#include "ShaderTypes.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Spatial/Spatial.h>

static simd_float4x4 matrix_float4x4_from_double4x4(simd_double4x4 m) {
    return simd_matrix(simd_make_float4(m.columns[0][0], m.columns[0][1], m.columns[0][2], m.columns[0][3]),
                       simd_make_float4(m.columns[1][0], m.columns[1][1], m.columns[1][2], m.columns[1][3]),
                       simd_make_float4(m.columns[2][0], m.columns[2][1], m.columns[2][2], m.columns[2][3]),
                       simd_make_float4(m.columns[3][0], m.columns[3][1], m.columns[3][2], m.columns[3][3]));
}

SpatialRenderer::SpatialRenderer(cp_layer_renderer_t layerRenderer) :
    _layerRenderer { layerRenderer },
    _sceneTime(0.0),
    _lastRenderTime(CACurrentMediaTime())
{
    _device = cp_layer_renderer_get_device(layerRenderer);
    _commandQueue = [_device newCommandQueue];
       bool b =  [_device supportsFamily: MTLGPUFamilyMac1 ] || [_device supportsFamily: MTLGPUFamilyApple5];
    makeResources();

    cp_layer_renderer_configuration_t layerConfiguration = cp_layer_renderer_get_configuration(layerRenderer);
    _layout = cp_layer_renderer_configuration_get_layout(layerConfiguration);
    makeRenderPipelines();


}

void SpatialRenderer::makeResources() {
    MTKMeshBufferAllocator *bufferAllocator = [[MTKMeshBufferAllocator alloc] initWithDevice:_device];
    MDLMesh *sphereMesh = [MDLMesh newEllipsoidWithRadii:simd_make_float3(0.5, 0.5, 0.5)
                                          radialSegments:24
                                        verticalSegments:24
                                            geometryType:MDLGeometryTypeTriangles
                                           inwardNormals:NO
                                              hemisphere:NO
                                               allocator:bufferAllocator];
    _globeMesh = std::make_unique<TexturedMesh>(sphereMesh, @"bluemarble.png", _device);

    _environmentMesh = std::make_unique<SpatialEnvironmentMesh>(@"studio.hdr", 3.0, _device);

    MTLTextureDescriptor * desc = [MTLTextureDescriptor new];
	desc.width = 2732;
	desc.height = 2048;
	desc.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
	desc.textureType = MTLTextureType2DArray;
	desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	desc.arrayLength = 2;
	_colorTexture = [_device newTextureWithDescriptor : desc];

	desc.pixelFormat = MTLPixelFormatDepth32Float_Stencil8;
	desc.usage = MTLTextureUsageRenderTarget;
	desc.arrayLength = 2;
	desc.storageMode = MTLStorageModePrivate;
	_depthTexture = [_device newTextureWithDescriptor : desc];
}

void SpatialRenderer::makeRenderPipelines() {
    NSError *error = nil;
    cp_layer_renderer_configuration_t layerConfiguration = cp_layer_renderer_get_configuration(_layerRenderer);
    
    MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.colorAttachments[0].pixelFormat = cp_layer_renderer_configuration_get_color_format(layerConfiguration);
    pipelineDescriptor.depthAttachmentPixelFormat = cp_layer_renderer_configuration_get_depth_format(layerConfiguration);
    pipelineDescriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
    id<MTLLibrary> library = [_device newDefaultLibrary];
    id<MTLFunction> vertexFunction, fragmentFunction;
    
    {
        vertexFunction = [library newFunctionWithName:@"vertex_main"];
        fragmentFunction = [library newFunctionWithName:@"fragment_main"];
        pipelineDescriptor.vertexFunction = vertexFunction;
        pipelineDescriptor.fragmentFunction = fragmentFunction;
        pipelineDescriptor.vertexDescriptor = _globeMesh->vertexDescriptor();
		if(_layout == cp_layer_renderer_layout_layered)
		{
			pipelineDescriptor.maxVertexAmplificationCount = 2;
		}

        _contentRenderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    }
    {
        vertexFunction = [library newFunctionWithName:@"vertex_environment"];
        fragmentFunction = [library newFunctionWithName:@"fragment_environment"];
        pipelineDescriptor.vertexFunction = vertexFunction;
        pipelineDescriptor.fragmentFunction = fragmentFunction;
        pipelineDescriptor.vertexDescriptor = _environmentMesh->vertexDescriptor();
		if(_layout == cp_layer_renderer_layout_layered)
		{
			pipelineDescriptor.maxVertexAmplificationCount = 2;
		}
        _environmentRenderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    }
    
    MTLDepthStencilDescriptor *depthDescriptor = [MTLDepthStencilDescriptor new];
    depthDescriptor.depthWriteEnabled = YES;
    depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    _contentDepthStencilState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];

    depthDescriptor.depthWriteEnabled = NO;
    depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    _backgroundDepthStencilState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];
}

void SpatialRenderer::drawAndPresent(cp_frame_t frame, cp_drawable_t drawable) {
    CFTimeInterval renderTime = CACurrentMediaTime();
    CFTimeInterval timestep = MIN(renderTime - _lastRenderTime, 1.0 / 60.0);
    _sceneTime += timestep;
    _sceneTime = 0;

    float c = cos(_sceneTime * 0.5f);
    float s = sin(_sceneTime * 0.5f);
    simd_float4x4 modelTransform = simd_matrix(simd_make_float4(   c, 0.0f,    -s, 0.0f),
                                               simd_make_float4(0.0f, 1.0f,  0.0f, 0.0f),
                                               simd_make_float4(   s, 0.0f,     c, 0.0f),
                                               simd_make_float4(0.0f, 0.0f, -1.5f, 1.0f));
    _globeMesh->setModelMatrix(modelTransform);

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    MTLVertexAmplificationViewMapping Mapping0;
    MTLVertexAmplificationViewMapping Mapping1;

    // Set each mapping's index offset for a render target array.
    Mapping0.renderTargetArrayIndexOffset = 0;
    Mapping1.renderTargetArrayIndexOffset = 1;

    // Set each mapping's index offset for a viewport array.
    Mapping0.viewportArrayIndexOffset = 0;
    Mapping1.viewportArrayIndexOffset = 0;

    // Create an array of the two mappings.
    MTLVertexAmplificationViewMapping Mappings[] = {Mapping0, Mapping1};
    
    
	MTLRenderPassDescriptor *renderPassDescriptor = createRenderPassDescriptor1(drawable, 0);
	id<MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

	[renderCommandEncoder setCullMode:MTLCullModeBack];

	PoseConstants poseConstants = poseConstantsForViewIndex(drawable, (int)0);

	[renderCommandEncoder setFrontFacingWinding:MTLWindingClockwise];
	[renderCommandEncoder setDepthStencilState:_backgroundDepthStencilState];
	[renderCommandEncoder setRenderPipelineState:_environmentRenderPipelineState];

	_environmentMesh->draw(renderCommandEncoder, poseConstants);

	[renderCommandEncoder endEncoding];
	


    for (int i = 0; i < (_layout == cp_layer_renderer_layout_layered ? 1 : cp_drawable_get_view_count(drawable)); ++i) {
        MTLRenderPassDescriptor *renderPassDescriptor = createRenderPassDescriptor(drawable, i);
        id<MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        [renderCommandEncoder setCullMode:MTLCullModeBack];
        
        [renderCommandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderCommandEncoder setDepthStencilState:_contentDepthStencilState];
        [renderCommandEncoder setRenderPipelineState:_contentRenderPipelineState];
		_globeMesh->_texture = _colorTexture;

		if(_layout == cp_layer_renderer_layout_layered)
		{
			[renderCommandEncoder setVertexAmplificationCount:2 viewMappings:Mappings];
			PoseConstants poseConstants[2];
			poseConstantsForViewIndex(drawable, poseConstants);
			_globeMesh->draw(renderCommandEncoder, poseConstants);
		}
		else
		{
			PoseConstants poseConstants = poseConstantsForViewIndex(drawable, i);
			_globeMesh->draw(renderCommandEncoder, poseConstants);
		}

        [renderCommandEncoder endEncoding];
    }

    cp_drawable_encode_present(drawable, commandBuffer);

    [commandBuffer commit];
}

MTLRenderPassDescriptor* SpatialRenderer::createRenderPassDescriptor(cp_drawable_t drawable, size_t index) {
    MTLRenderPassDescriptor *passDescriptor = [[MTLRenderPassDescriptor alloc] init];

    passDescriptor.colorAttachments[0].texture = cp_drawable_get_color_texture(drawable, index);
    passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1);
    passDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;

    passDescriptor.depthAttachment.texture = cp_drawable_get_depth_texture(drawable, index);
    passDescriptor.depthAttachment.storeAction = MTLStoreActionStore;
    passDescriptor.depthAttachment.loadAction = MTLLoadActionClear;

	if(_layout == cp_layer_renderer_layout_layered)
	{
		passDescriptor.renderTargetArrayLength = 2;
	}
	else
	{
		passDescriptor.renderTargetArrayLength = 1;
	}

	MTLRasterizationRateMapDescriptor *descriptor = [[MTLRasterizationRateMapDescriptor alloc] init];

	MTLSize screenSize = MTLSizeMake(passDescriptor.colorAttachments[0].texture.width, passDescriptor.colorAttachments[0].texture.height, 1);
	descriptor.screenSize = screenSize;


	MTLSize zoneCounts = MTLSizeMake(8, 4, 1);
	MTLRasterizationRateLayerDescriptor *layerDescriptor = [[MTLRasterizationRateLayerDescriptor alloc] initWithSampleCount:zoneCounts];

	for (int row = 0; row < zoneCounts.height; row++)
	{
		layerDescriptor.verticalSampleStorage[row] = 0.1;    
	}
	for (int column = 0; column < zoneCounts.width; column++)
	{
		layerDescriptor.horizontalSampleStorage[column] = 0.1;
	}
//	layerDescriptor.horizontalSampleStorage[0] = 0.1;
//	layerDescriptor.horizontalSampleStorage[7] = 0.1;
//	layerDescriptor.verticalSampleStorage[0] = 0.1;
//	layerDescriptor.verticalSampleStorage[3] = 0.1;

	[descriptor setLayer:layerDescriptor atIndex:0];
	//id<MTLRasterizationRateMap> rateMap = [_device newRasterizationRateMapWithDescriptor: descriptor];

    //passDescriptor.rasterizationRateMap = rateMap;
//    passDescriptor.rasterizationRateMap = cp_drawable_get_rasterization_rate_map(drawable, index);

    return passDescriptor;
}

MTLRenderPassDescriptor* SpatialRenderer::createRenderPassDescriptor1(cp_drawable_t drawable, size_t index) {
    MTLRenderPassDescriptor *passDescriptor = [[MTLRenderPassDescriptor alloc] init];

    passDescriptor.colorAttachments[0].texture = cp_drawable_get_color_texture(drawable, index);
    passDescriptor.colorAttachments[0].texture = _colorTexture;
    passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 0, 1);
    passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
//    passDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    passDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;

    passDescriptor.depthAttachment.texture = cp_drawable_get_depth_texture(drawable, index);
	passDescriptor.depthAttachment.texture = _depthTexture;
    passDescriptor.depthAttachment.storeAction = MTLStoreActionStore;
    passDescriptor.depthAttachment.loadAction = MTLLoadActionDontCare;

    passDescriptor.renderTargetArrayLength = 2;
//      passDescriptor.renderTargetArrayLength = cp_drawable_get_view_count(drawable);
    //passDescriptor.rasterizationRateMap = cp_drawable_get_rasterization_rate_map(drawable, index);

    return passDescriptor;
}

void SpatialRenderer::poseConstantsForViewIndex(cp_drawable_t drawable, PoseConstants* outPose) {

    ar_device_anchor_t anchor = cp_drawable_get_device_anchor(drawable);

    simd_float4x4 poseTransform = ar_anchor_get_origin_from_anchor_transform(anchor);
    poseTransform = matrix_identity_float4x4;

	for(int i = 0; i < 2; i++)
	{
		cp_view_t view = cp_drawable_get_view(drawable, i);
		simd_float4 tangents = cp_view_get_tangents(view);
		simd_float2 depth_range = cp_drawable_get_depth_range(drawable);
		SPProjectiveTransform3D projectiveTransform = SPProjectiveTransform3DMakeFromTangents(tangents[0], tangents[1],
				tangents[2], tangents[3],
				depth_range[1], depth_range[0],
				true);
		outPose[i].projectionMatrix = matrix_float4x4_from_double4x4(projectiveTransform.matrix);

		simd_float4x4 cameraMatrix = simd_mul(poseTransform, cp_view_get_transform(view));
		outPose[i].viewMatrix = simd_inverse(cameraMatrix);
	}
}

PoseConstants SpatialRenderer::poseConstantsForViewIndex(cp_drawable_t drawable, size_t index) {
    PoseConstants outPose;

    ar_device_anchor_t anchor = cp_drawable_get_device_anchor(drawable);

    simd_float4x4 poseTransform = ar_anchor_get_origin_from_anchor_transform(anchor);
    poseTransform = matrix_identity_float4x4;

    cp_view_t view = cp_drawable_get_view(drawable, index);
    simd_float4 tangents = cp_view_get_tangents(view);
    simd_float2 depth_range = cp_drawable_get_depth_range(drawable);
    SPProjectiveTransform3D projectiveTransform = SPProjectiveTransform3DMakeFromTangents(tangents[0], tangents[1],
                                                                                          tangents[2], tangents[3],
                                                                                          depth_range[1], depth_range[0],
                                                                                          true);
    outPose.projectionMatrix = matrix_float4x4_from_double4x4(projectiveTransform.matrix);

    simd_float4x4 cameraMatrix = simd_mul(poseTransform, cp_view_get_transform(view));
    outPose.viewMatrix = simd_inverse(cameraMatrix);
    return outPose;
}
