import AppKit
import Metal
import MetalKit
import SwiftUI

struct MetalShaderWallpaperView: NSViewRepresentable {
    let preset: ShaderPreset
    let isPaused: Bool
    let frameRateLimit: Int
    let playbackRate: Double
    let reactiveLevel: Double
    let reactiveBeatPulse: Double
    let musicReactiveEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = true
        view.preferredFramesPerSecond = max(5, min(frameRateLimit, 120))
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)

        context.coordinator.attach(view: view)
        context.coordinator.configure(
            preset: preset,
            isPaused: isPaused,
            frameRateLimit: frameRateLimit,
            playbackRate: playbackRate,
            reactiveLevel: reactiveLevel,
            reactiveBeatPulse: reactiveBeatPulse,
            musicReactiveEnabled: musicReactiveEnabled
        )

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.attach(view: nsView)
        context.coordinator.configure(
            preset: preset,
            isPaused: isPaused,
            frameRateLimit: frameRateLimit,
            playbackRate: playbackRate,
            reactiveLevel: reactiveLevel,
            reactiveBeatPulse: reactiveBeatPulse,
            musicReactiveEnabled: musicReactiveEnabled
        )
    }

    @MainActor
    final class Coordinator {
        private let renderer = ShaderRenderer()

        func attach(view: MTKView) {
            renderer.attach(to: view)
        }

        func configure(
            preset: ShaderPreset,
            isPaused: Bool,
            frameRateLimit: Int,
            playbackRate: Double,
            reactiveLevel: Double,
            reactiveBeatPulse: Double,
            musicReactiveEnabled: Bool
        ) {
            renderer.update(
                styleIndex: preset.styleIndex,
                speed: Float(max(0.1, min(playbackRate, 3.0)) * preset.baseSpeed),
                isPaused: isPaused,
                frameRateLimit: frameRateLimit,
                reactiveLevel: Float(max(0, min(reactiveLevel, 1))),
                reactiveBeatPulse: Float(max(0, min(reactiveBeatPulse, 1))),
                musicReactiveEnabled: musicReactiveEnabled
            )
        }
    }
}

@MainActor
private final class ShaderRenderer: NSObject, MTKViewDelegate {
    private weak var view: MTKView?

    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?

    private var styleIndex: UInt32 = 0
    private var speed: Float = 1.0
    private var isPaused = false
    private var reactiveLevel: Float = 0
    private var reactiveBeatPulse: Float = 0
    private var reactiveEnabled: UInt32 = 0
    private var startTime = CACurrentMediaTime()

    func attach(to view: MTKView) {
        if self.view !== view {
            self.view = view
            view.delegate = self
            preparePipelineIfNeeded(for: view)
        }
    }

    func update(
        styleIndex: UInt32,
        speed: Float,
        isPaused: Bool,
        frameRateLimit: Int,
        reactiveLevel: Float,
        reactiveBeatPulse: Float,
        musicReactiveEnabled: Bool
    ) {
        self.styleIndex = styleIndex
        self.speed = speed
        self.isPaused = isPaused
        self.reactiveLevel = reactiveLevel
        self.reactiveBeatPulse = reactiveBeatPulse
        reactiveEnabled = musicReactiveEnabled ? 1 : 0

        let clampedFPS = max(5, min(frameRateLimit, 120))
        view?.preferredFramesPerSecond = clampedFPS
        view?.isPaused = isPaused

        if !isPaused {
            view?.draw()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // No-op.
    }

    func draw(in view: MTKView) {
        guard !isPaused else { return }
        guard
            let pipelineState,
            let commandQueue,
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else {
            return
        }

        var uniforms = ShaderUniforms(
            time: Float(CACurrentMediaTime() - startTime),
            resolution: SIMD2<Float>(Float(max(1, view.drawableSize.width)), Float(max(1, view.drawableSize.height))),
            styleIndex: styleIndex,
            speed: speed,
            reactiveLevel: reactiveLevel,
            reactiveBeatPulse: reactiveBeatPulse,
            reactiveEnabled: reactiveEnabled
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func preparePipelineIfNeeded(for view: MTKView) {
        guard pipelineState == nil else { return }
        guard let device = view.device else { return }

        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vertex = library.makeFunction(name: "vertex_main"),
                  let fragment = library.makeFunction(name: "fragment_main") else {
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            commandQueue = device.makeCommandQueue()
            startTime = CACurrentMediaTime()
        } catch {
            fputs("[LumenDesk] Metal shader compile failed: \(error)\n", stderr)
        }
    }

    private struct ShaderUniforms {
        var time: Float
        var resolution: SIMD2<Float>
        var styleIndex: UInt32
        var speed: Float
        var reactiveLevel: Float
        var reactiveBeatPulse: Float
        var reactiveEnabled: UInt32
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VSOut {
        float4 position [[position]];
        float2 uv;
    };

    struct ShaderUniforms {
        float time;
        float2 resolution;
        uint styleIndex;
        float speed;
        float reactiveLevel;
        float reactiveBeatPulse;
        uint reactiveEnabled;
    };

    vertex VSOut vertex_main(uint vid [[vertex_id]]) {
        float2 positions[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };

        float2 uvs[4] = {
            float2(0.0, 0.0),
            float2(1.0, 0.0),
            float2(0.0, 1.0),
            float2(1.0, 1.0)
        };

        VSOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        out.uv = uvs[vid];
        return out;
    }

    float3 palette(float t, float3 a, float3 b, float3 c, float3 d) {
        return a + b * cos(6.2831853 * (c * t + d));
    }

    fragment float4 fragment_main(VSOut in [[stage_in]], constant ShaderUniforms& u [[buffer(0)]]) {
        float2 uv = in.uv;
        float2 p = uv * 2.0 - 1.0;
        p.x *= u.resolution.x / max(1.0, u.resolution.y);

        float t = u.time * u.speed;
        float reactiveMix = u.reactiveEnabled == 1 ? clamp(u.reactiveLevel * 1.2 + u.reactiveBeatPulse * 0.9, 0.0, 1.5) : 0.0;
        float3 color;

        if (u.styleIndex == 0) {
            float v = sin(p.x * 2.5 + t * 0.8) + cos(p.y * 3.3 - t * 0.7);
            v += reactiveMix * 0.7;
            color = palette(v * 0.2 + t * 0.05,
                            float3(0.32, 0.30, 0.55),
                            float3(0.35, 0.25, 0.45),
                            float3(1.0, 1.0, 1.0),
                            float3(0.0, 0.3, 0.6));
        } else if (u.styleIndex == 1) {
            float r = length(p);
            float a = atan2(p.y, p.x);
            float wave = sin(r * (12.0 + reactiveMix * 5.0) - t * 3.0 + sin(a * 5.0 + t));
            color = palette(wave * 0.25 + r * 0.3,
                            float3(0.45, 0.10, 0.18),
                            float3(0.50, 0.35, 0.30),
                            float3(1.0, 1.0, 1.0),
                            float3(0.2, 0.15, 0.0));
        } else if (u.styleIndex == 2) {
            float d = sin((p.x + t * 0.25) * (8.0 + reactiveMix * 4.0)) * cos((p.y - t * 0.2) * (8.0 + reactiveMix * 3.0));
            float glow = exp(-3.5 * length(p));
            color = float3(0.08, 0.16, 0.30) + float3(0.2, 0.55, 0.75) * (d * 0.5 + 0.5) + glow * 0.45;
        } else if (u.styleIndex == 3) {
            float2 grid = abs(fract(p * 6.0 + t * 0.08) - 0.5);
            float line = min(grid.x, grid.y);
            float pulse = 1.0 - smoothstep(0.02, 0.08, line);
            float sweep = smoothstep(-0.6, 0.6, sin((p.x + p.y) * 6.0 - t * 2.0));
            color = float3(0.03, 0.08, 0.13) + float3(0.15, 0.7, 0.9) * pulse + float3(0.8, 0.9, 1.0) * sweep * (0.25 + reactiveMix * 0.4);
        } else {
            float r = length(p);
            float a = atan2(p.y, p.x);
            float swirl = sin(a * (7.0 + reactiveMix * 4.0) + t * 2.0 - r * 10.0);
            float ring = smoothstep(0.75, 0.05, abs(r - 0.45 + swirl * 0.06));
            color = palette(swirl * 0.2 + r + t * 0.03,
                            float3(0.25, 0.2, 0.35),
                            float3(0.4, 0.25, 0.35),
                            float3(1.0, 1.0, 1.0),
                            float3(0.3, 0.15, 0.65));
            color += ring * float3(0.7, 0.6, 0.95);
        }

        color += u.reactiveBeatPulse * float3(0.22, 0.22, 0.28);
        color = clamp(color, 0.0, 1.0);
        return float4(color, 1.0);
    }
    """
}
