import AppKit
import Metal
import MetalPerformanceShaders
import QuartzCore
import simd
import LidFoldModel

/// Everything the shader needs for one frame, derived from the current
/// lid angle and the adjustable `FoldAppearanceModel`.
public struct FrameParameters {
    public var quad: [ScreenPoint]
    public var blurStrength: Double
    public var dimStrength: Double
    public var topEdge: Double
    public var maxBlurRadius: Double
    public var maxDim: Double

    /// Derives the whole per-frame look from the lid angle and settings.
    public static func make(angle: Double, screenSize: CGSize, settings: FoldAppearanceModel) -> FrameParameters {
        let width = Double(screenSize.width)
        let height = Double(screenSize.height)
        let curve = FoldCurve(startAngle: settings.startAngle, span: FoldPhysicsConstants.span)
        let progress = curve.progress(at: angle)
        let geometry = FoldGeometry(screenWidth: width, screenHeight: height, freezeAngle: settings.startAngle,
                                    eyeDistance: FoldPhysicsConstants.eyeDistance, depth: FoldPhysicsConstants.depth)
        let quad = geometry.project(at: angle)
        return FrameParameters(
            quad: quad,
            blurStrength: curve.blurStrength(at: progress),
            dimStrength: curve.dimStrength(at: progress),
            topEdge: quad[2].y,
            maxBlurRadius: settings.blurRadius,
            maxDim: settings.dimAmount
        )
    }
}

/// Draws the fold with Metal. The captured picture sits on a black margin
/// inside one mipmapped texture; each frame is a single full-screen pass.
@MainActor
public final class FoldRenderer {

    /// Black margin around the picture, in points — kept above the widest
    /// possible blur so frost always runs out to true black.
    nonisolated private static let padding: CGFloat = 176

    private struct Uniforms {
        var column0: SIMD4<Float>
        var column1: SIMD4<Float>
        var column2: SIMD4<Float>
        var screenAndOrigin: SIMD4<Float>
        var paddedAndBlur: SIMD4<Float>
        var shape: SIMD4<Float>
        var more: SIMD4<Float>
    }

    public struct Picture {
        let texture: MTLTexture
        let colourSpace: CGColorSpace
        let screenSize: CGSize
        let pixelScale: CGFloat
        let maxLevel: Float
    }

    private var layer = CAMetalLayer()
    nonisolated private let device: MTLDevice
    nonisolated private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let padPipeline: MTLRenderPipelineState

    private var texture: MTLTexture?
    private var screenSize: CGSize = .zero
    private var pixelScale: CGFloat = 2
    private var paddedSize: CGSize = .zero
    private var maxLevel: Float = 0

    public var isReady: Bool { texture != nil }

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: FoldShaders.source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            let pad = MTLRenderPipelineDescriptor()
            pad.vertexFunction = library.makeFunction(name: "foldVertex")
            pad.fragmentFunction = library.makeFunction(name: "padFragment")
            pad.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            padPipeline = try device.makeRenderPipelineState(descriptor: pad)
        } catch {
            return nil
        }
        configure(layer)
    }

    public func makeLayer() -> CAMetalLayer {
        let fresh = CAMetalLayer()
        configure(fresh)
        layer = fresh
        return fresh
    }

    private func configure(_ target: CAMetalLayer) {
        target.device = device
        target.pixelFormat = .bgra8Unorm_srgb
        target.framebufferOnly = true
        // An opaque full-screen layer makes the window server hide
        // everything underneath; the shader always writes alpha 1, so
        // blending produces the same picture while keeping apps drawing.
        target.isOpaque = false
        target.displaySyncEnabled = false
        target.needsDisplayOnBoundsChange = true
    }

    /// Builds the padded, mipmapped texture for one captured still. Safe
    /// to call off the main thread.
    nonisolated public func makePicture(from image: CGImage, screenSize: CGSize, pixelScale: CGFloat) -> Picture? {
        let padding = Self.padding
        let padded = CGSize(width: screenSize.width + 2 * padding, height: screenSize.height + 2 * padding)
        let width = Int((padded.width * pixelScale).rounded())
        let height = Int((padded.height * pixelScale).rounded())
        let frameWidth = Int((screenSize.width * pixelScale).rounded())
        let frameHeight = Int((screenSize.height * pixelScale).rounded())
        guard width > 0, height > 0, frameWidth > 0, frameHeight > 0 else { return nil }

        let bytesPerRow = frameWidth * 4
        guard let staging = device.makeBuffer(length: bytesPerRow * frameHeight, options: .storageModeShared) else { return nil }
        let space = CGColorSpace(name: Self.colourSpace) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: staging.contents(), width: frameWidth, height: frameHeight, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight))

        let frameDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: frameWidth, height: frameHeight, mipmapped: false)
        frameDescriptor.usage = [.shaderRead]
        frameDescriptor.storageMode = .private
        let levels = Int(floor(log2(Double(max(width, height))))) + 1
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: true)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard let frame = device.makeTexture(descriptor: frameDescriptor),
              var texture = device.makeTexture(descriptor: descriptor),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerRow * frameHeight,
                  sourceSize: MTLSize(width: frameWidth, height: frameHeight, depth: 1),
                  to: frame, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        encodePad(frame: frame, into: texture, pixelScale: pixelScale, commands: commands)
        MPSImageGaussianPyramid(device: device, centerWeight: 0.375)
            .encode(commandBuffer: commands, inPlaceTexture: &texture, fallbackCopyAllocator: nil)
        commands.commit()
        commands.waitUntilCompleted()
        return Picture(texture: texture, colourSpace: space, screenSize: screenSize, pixelScale: pixelScale, maxLevel: Float(levels - 1))
    }

    /// Draws `frame` into level 0 of `target`: the frame centred, its edge
    /// pixels stretched across the surrounding margin.
    nonisolated private func encodePad(frame: MTLTexture, into target: MTLTexture, pixelScale: CGFloat, commands: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        let inset = Float((Self.padding * pixelScale).rounded())
        var uniforms = SIMD4<Float>(inset, inset, Float(frame.width), Float(frame.height))
        encoder.setRenderPipelineState(padPipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentTexture(frame, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    public func adopt(_ picture: Picture) {
        texture = picture.texture
        screenSize = picture.screenSize
        pixelScale = picture.pixelScale
        paddedSize = CGSize(width: picture.screenSize.width + 2 * Self.padding, height: picture.screenSize.height + 2 * Self.padding)
        maxLevel = picture.maxLevel
        layer.colorspace = picture.colourSpace
        layer.drawableSize = CGSize(width: picture.screenSize.width * picture.pixelScale, height: picture.screenSize.height * picture.pixelScale)
    }

    public func release() {
        texture = nil
    }

    /// Draws one frame to the on-screen layer.
    public func render(_ p: FrameParameters) {
        guard let texture, screenSize.width > 0, screenSize.height > 0,
              let commands = queue.makeCommandBuffer(), let drawable = layer.nextDrawable() else { return }
        encode(p, texture: texture, target: drawable.texture, into: commands)
        commands.present(drawable)
        commands.commit()
    }

    private func encode(_ p: FrameParameters, texture: MTLTexture, target: MTLTexture, into commands: MTLCommandBuffer) {
        let forward = Homography.matrix(width: Double(screenSize.width), height: Double(screenSize.height), to: p.quad)
        let inverse = forward.inverse
        func column(_ i: Int) -> SIMD4<Float> {
            let c = inverse[i]
            return SIMD4(Float(c.x), Float(c.y), Float(c.z), 0)
        }
        var uniforms = Uniforms(
            column0: column(0), column1: column(1), column2: column(2),
            screenAndOrigin: SIMD4(Float(screenSize.width), Float(screenSize.height), Float(-Self.padding), Float(-Self.padding)),
            paddedAndBlur: SIMD4(Float(paddedSize.width), Float(paddedSize.height), Float(p.maxBlurRadius * Double(pixelScale)), Float(p.blurStrength)),
            shape: SIMD4(Float(p.maxDim), Float(pixelScale), maxLevel, Float(p.dimStrength)),
            more: SIMD4(Float(FoldPhysicsConstants.dimReach), Float(p.topEdge), 0, 0)
        )
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// The colour space captured stills are handed over in. Display P3
    /// shares sRGB's transfer curve, so an sRGB texture view decodes it
    /// correctly without a separate conversion pass.
    nonisolated public static let colourSpace = CGColorSpace.displayP3
}
