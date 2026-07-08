import SwiftUI
import MetalKit
import QuartzCore

/// A small animated radar scope (Metal) shown while waiting for the app.
/// Ported from the provided ShaderToy shader (concentric rings + crosshair),
/// with a rotating sweep added so it reads as a loading indicator.
struct RadarView: NSViewRepresentable {
    func makeCoordinator() -> Renderer { Renderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.layer?.isOpaque = false
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        context.coordinator.setup(view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    struct Uniforms { var resolution: SIMD2<Float>; var time: Float }

    final class Renderer: NSObject, MTKViewDelegate {
        private var pipeline: MTLRenderPipelineState?
        private var queue: MTLCommandQueue?
        private let start = CACurrentMediaTime()

        func setup(_ view: MTKView) {
            guard let device = view.device else { return }
            queue = device.makeCommandQueue()
            guard let library = try? device.makeLibrary(source: Self.source, options: nil) else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "radar_vtx")
            descriptor.fragmentFunction = library.makeFunction(name: "radar_frag")
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = view.colorPixelFormat
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .sourceAlpha
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipeline, let queue,
                  let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            var uniforms = Uniforms(
                resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                time: Float(CACurrentMediaTime() - start)
            )
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }

        static let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct Uniforms { float2 resolution; float time; };

        vertex float4 radar_vtx(uint vid [[vertex_id]]) {
            float2 p[3] = { float2(-1.0,-1.0), float2(3.0,-1.0), float2(-1.0,3.0) };
            return float4(p[vid], 0.0, 1.0);
        }

        static inline float2 rot2(float2 v, float a) {
            float c = cos(a), s = sin(a);
            return float2(c * v.x - s * v.y, s * v.x + c * v.y);
        }

        fragment float4 radar_frag(float4 pos [[position]], constant Uniforms& u [[buffer(0)]]) {
            const float TAU = 6.2831853;
            float2 res = u.resolution;
            float SF = 1.0 / min(res.x, res.y);
            float2 uv = (pos.xy - 0.5 * res) / res.y;
            float l = length(uv);
            float sweep = u.time * 2.0;

            // Rings + crosshair (dim).
            float grid = 0.0;
            float ir = 0.1 * round(l / 0.1);
            grid += smoothstep(SF * 2.0, 0.0, abs(ir - l));
            grid += smoothstep(SF, 0.0, abs(uv.x));
            grid += smoothstep(SF, 0.0, abs(uv.y));

            // Blips that light up as the sweep passes, then fade.
            float2 blips[6] = { float2(0.25,0.25), float2(-0.15,0.13), float2(0.12,-0.20),
                                float2(0.28,-0.30), float2(0.05,0.30), float2(-0.30,-0.30) };
            float radii[6] = { 0.05, 0.08, 0.10, 0.13, 0.18, 0.30 };
            float blip = 0.0;
            for (int i = 0; i < 6; i++) {
                float glow = smoothstep(radii[i], 0.0, length(uv - blips[i]));
                float ba = atan2(blips[i].y, blips[i].x);
                float since = fmod(sweep - ba + TAU * 8.0, TAU);
                float ping = exp(-since * 2.0);
                blip += glow * (0.12 + 0.9 * ping);
            }

            // Rotating sweep beam + a faint afterglow wedge behind it.
            float2 suv = rot2(uv, sweep);
            float beam = smoothstep(0.025, 0.0, abs(suv.y))
                       * smoothstep(0.0, 0.1, suv.x)
                       * smoothstep(0.51, 0.49, suv.x);
            float ang = atan2(uv.y, uv.x);
            float since = fmod(sweep - ang + TAU * 8.0, TAU);
            float trail = smoothstep(1.1, 0.0, since) * 0.10;

            float inside = step(l, 0.51);
            float3 green = float3(0.0, 1.0, 0.0);
            float3 col = green * (0.04)                        // faint disc glow
                       + green * grid * 0.22                   // rings + crosshair
                       + green * clamp(blip, 0.0, 1.0) * 0.6   // blips
                       + green * trail                         // sweep afterglow
                       + green * beam;                         // sweep beam
            col *= inside;
            return float4(col, inside);
        }
        """
    }
}
