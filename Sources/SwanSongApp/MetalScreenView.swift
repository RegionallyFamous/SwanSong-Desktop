import Metal
import MetalKit
import SwanSongKit
import SwiftUI

struct MetalScreenView: NSViewRepresentable {
    let frame: EngineVideoFrame
    let profile: DisplayProfile
    let responseScale: Float

    func makeNSView(context: Context) -> SwanMetalView {
        let view = SwanMetalView()
        view.update(frame: frame, profile: profile, responseScale: responseScale)
        return view
    }

    func updateNSView(_ nsView: SwanMetalView, context: Context) {
        nsView.update(frame: frame, profile: profile, responseScale: responseScale)
    }
}

final class SwanMetalView: MTKView, MTKViewDelegate {
    private struct DisplayUniforms {
        var adjustments: SIMD4<Float>
        var tint: SIMD4<Float>
        var geometry: SIMD4<Float>
    }

    private var commandQueue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var gameTexture: MTLTexture?
    private var previousTexture: MTLTexture?
    private var previousFramePixels: Data?
    private var textureSize = SIMD2<Int>(repeating: 0)
    private var displayProfile = DisplayProfile.purePixels
    private var responseScale: Float = 1

    init() {
        let metalDevice = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: metalDevice)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        preferredFramesPerSecond = 75
        clearColor = MTLClearColorMake(0.025, 0.03, 0.04, 1)
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        delegate = self

        guard let metalDevice else { return }
        commandQueue = metalDevice.makeCommandQueue()
        pipeline = try? Self.makePipeline(device: metalDevice, format: colorPixelFormat)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(frame: EngineVideoFrame, profile: DisplayProfile, responseScale: Float) {
        guard let device else { return }
        displayProfile = profile
        self.responseScale = responseScale
        let requestedSize = SIMD2(frame.width, frame.height)
        if gameTexture == nil || requestedSize != textureSize {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: frame.width,
                height: frame.height,
                mipmapped: false
            )
            descriptor.usage = .shaderRead
            gameTexture = device.makeTexture(descriptor: descriptor)
            previousTexture = device.makeTexture(descriptor: descriptor)
            previousFramePixels = nil
            textureSize = requestedSize
        }

        let priorPixels = previousFramePixels ?? frame.pixels
        priorPixels.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            previousTexture?.replace(
                region: MTLRegionMake2D(0, 0, frame.width, frame.height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: frame.strideBytes
            )
        }
        frame.pixels.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            gameTexture?.replace(
                region: MTLRegionMake2D(0, 0, frame.width, frame.height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: frame.strideBytes
            )
        }
        previousFramePixels = frame.pixels
        needsDisplay = true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let pipeline,
            let gameTexture,
            let previousTexture,
            let commandQueue,
            let descriptor = currentRenderPassDescriptor,
            let drawable = currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(gameTexture, index: 0)
        encoder.setFragmentTexture(previousTexture, index: 1)
        var uniforms = makeDisplayUniforms()
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<DisplayUniforms>.stride,
            index: 0
        )
        encoder.setViewport(integerScaleViewport())
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeDisplayUniforms() -> DisplayUniforms {
        let parameters = displayProfile.parameters
        return DisplayUniforms(
            adjustments: SIMD4(
                parameters.saturation,
                parameters.contrast,
                parameters.brightness,
                parameters.pixelGridStrength
            ),
            tint: SIMD4(
                parameters.tintRed,
                parameters.tintGreen,
                parameters.tintBlue,
                min(max(parameters.responsePersistence * responseScale, 0), 0.45)
            ),
            geometry: SIMD4(
                Float(textureSize.x),
                Float(textureSize.y),
                0,
                0
            )
        )
    }

    private func integerScaleViewport() -> MTLViewport {
        let sourceWidth = Double(max(textureSize.x, 1))
        let sourceHeight = Double(max(textureSize.y, 1))
        let availableWidth = Double(drawableSize.width)
        let availableHeight = Double(drawableSize.height)
        let availableScale = min(
            availableWidth / sourceWidth,
            availableHeight / sourceHeight
        )
        let scale = availableScale >= 1 ? floor(availableScale) : availableScale
        let width = sourceWidth * max(scale, 0.01)
        let height = sourceHeight * max(scale, 0.01)
        return MTLViewport(
            originX: floor((availableWidth - width) / 2),
            originY: floor((availableHeight - height) / 2),
            width: width,
            height: height,
            znear: 0,
            zfar: 1
        )
    }

    private static func makePipeline(
        device: MTLDevice,
        format: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct RasterData {
            float4 position [[position]];
            float2 textureCoordinate;
        };

        struct DisplayUniforms {
            float4 adjustments;
            float4 tint;
            float4 geometry;
        };

        vertex RasterData swanVertex(uint vertexID [[vertex_id]]) {
            const float2 positions[4] = {
                float2(-1.0, -1.0), float2(1.0, -1.0),
                float2(-1.0,  1.0), float2(1.0,  1.0)
            };
            const float2 coordinates[4] = {
                float2(0.0, 1.0), float2(1.0, 1.0),
                float2(0.0, 0.0), float2(1.0, 0.0)
            };
            RasterData output;
            output.position = float4(positions[vertexID], 0.0, 1.0);
            output.textureCoordinate = coordinates[vertexID];
            return output;
        }

        fragment float4 swanFragment(
            RasterData input [[stage_in]],
            texture2d<float> game [[texture(0)]],
            texture2d<float> previousGame [[texture(1)]],
            constant DisplayUniforms &display [[buffer(0)]]) {
            constexpr sampler nearestSampler(
                mag_filter::nearest,
                min_filter::nearest,
                address::clamp_to_edge
            );
            float3 currentColor = game.sample(nearestSampler, input.textureCoordinate).rgb;
            float3 previousColor = previousGame.sample(nearestSampler, input.textureCoordinate).rgb;
            float3 color = mix(currentColor, previousColor, display.tint.w);
            float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
            color = mix(float3(luminance), color, display.adjustments.x);
            color = (color - 0.5) * display.adjustments.y + 0.5;
            color += display.adjustments.z;
            color *= display.tint.rgb;

            float2 sourcePixel = input.textureCoordinate * display.geometry.xy;
            float2 distanceFromCenter = abs(fract(sourcePixel) - 0.5) * 2.0;
            float pixelEdge = smoothstep(0.76, 1.0, max(distanceFromCenter.x, distanceFromCenter.y));
            color *= 1.0 - display.adjustments.w * pixelEdge;
            return float4(clamp(color, 0.0, 1.0), 1.0);
        }
        """

        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "swanVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "swanFragment")
        descriptor.colorAttachments[0].pixelFormat = format
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
