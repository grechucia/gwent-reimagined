// Metal 2D renderer: batched textured quads in a virtual 1920x1080 space, CoreText text and the title-screen shader.
import Metal
import MetalKit
import CoreText
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

let virtualWidth: Float = 1920, virtualHeight: Float = 1080
/// Size of a small card on the board, in virtual units.
let cardWidth: Float = 85, cardHeight: Float = 122

/// RGBA colour.
struct RGBA { var r, g, b, a: Float
    static let white = RGBA(r: 1, g: 1, b: 1, a: 1), black = RGBA(r: 0, g: 0, b: 0, a: 1)
    /// Grey colour.
    static func gray(_ value: Float, _ alpha: Float = 1) -> RGBA { RGBA(r: value, g: value, b: value, a: alpha) }
    /// Same colour with alpha multiplied.
    func alpha(_ factor: Float) -> RGBA { RGBA(r: r, g: g, b: b, a: a * factor) }
    static let gold = RGBA(r: 0.95, g: 0.80, b: 0.45, a: 1), goldDark = RGBA(r: 0.79, g: 0.63, b: 0.29, a: 1)
}

/// Rectangle in virtual 1920x1080 coordinates.
struct R: Equatable { var x, y, w, h: Float
    init(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { self.x = x; self.y = y; self.w = w; self.h = h }
    /// Whether a point lies inside the rectangle.
    func contains(_ point: SIMD2<Float>) -> Bool { point.x >= x && point.x <= x + w && point.y >= y && point.y <= y + h }
    /// Rectangle shrunk (positive) or grown (negative) on every side.
    func inset(_ amount: Float) -> R { R(x + amount, y + amount, w - 2 * amount, h - 2 * amount) }
    var mid: SIMD2<Float> { SIMD2(x + w / 2, y + h / 2) }
}

/// Vertex sent to the GPU.
struct Vtx { var pos: SIMD2<Float>; var uv: SIMD2<Float>; var color: SIMD4<Float>; var mode: Float; var pad: SIMD3<Float> = .zero }

/// Rendered text texture with its size in virtual units.
final class TextTex { let texture: MTLTexture; let w: Float; let h: Float
    init(texture: MTLTexture, w: Float, h: Float) { self.texture = texture; self.w = w; self.h = h } }

/// Batches textured quads into Metal draw calls, letterboxed to 16:9.
final class Renderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let bgPipeline: MTLRenderPipelineState
    let sampler: MTLSamplerState
    let loader: MTKTextureLoader
    var buffers: [MTLBuffer] = []
    var bufIndex = 0
    let inflight = DispatchSemaphore(value: 3)
    let maxVerts = 120_000
    var verts: UnsafeMutablePointer<Vtx>!
    var vcount = 0, flushedFrom = 0
    var curTex: MTLTexture?
    var encoder: MTLRenderCommandEncoder?
    var projection = matrix_identity_float4x4
    let white: MTLTexture
    private(set) var pxScale: Float = 1
    private(set) var viewportPx = R(0, 0, 1, 1)
    var texCache: [String: MTLTexture] = [:]
    var textCache: [String: (TextTex, Int)] = [:]
    var frameNo = 0
    let gameDir: URL

    init?(view: MTKView, gameDir: URL) {
        guard let metalDevice = MTLCreateSystemDefaultDevice(), let commandQueue = metalDevice.makeCommandQueue() else { return nil }
        device = metalDevice; queue = commandQueue; self.gameDir = gameDir
        view.device = metalDevice
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        loader = MTKTextureLoader(device: metalDevice)
        let library: MTLLibrary
        do { library = try metalDevice.makeLibrary(source: Renderer.shaderSource, options: nil) }
        catch { fatalError("Metal: \(error)") }
        /// Creates a render pipeline.
        func pipe(_ vertexFunction: String, _ fragmentFunction: String) -> MTLRenderPipelineState {
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library.makeFunction(name: vertexFunction); pipelineDescriptor.fragmentFunction = library.makeFunction(name: fragmentFunction)
            let attachment = pipelineDescriptor.colorAttachments[0]!
            attachment.pixelFormat = .bgra8Unorm
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add; attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha; attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one; attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try! metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        pipeline = pipe("vmain", "fmain")
        bgPipeline = pipe("vbg", "fbg")
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear; samplerDescriptor.magFilter = .linear; samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge; samplerDescriptor.tAddressMode = .clampToEdge
        sampler = metalDevice.makeSamplerState(descriptor: samplerDescriptor)!
        for _ in 0..<3 { buffers.append(metalDevice.makeBuffer(length: MemoryLayout<Vtx>.stride * maxVerts, options: .storageModeShared)!) }
        let whiteDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        white = metalDevice.makeTexture(descriptor: whiteDescriptor)!
        var pixels: [UInt8] = [255, 255, 255, 255]
        white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixels, bytesPerRow: 4)
    }

    /// Loads (and caches) an image from the game folder as a texture.
    func texture(_ path: String) -> MTLTexture? {
        if let cached = texCache[path] { return cached }
        let url = gameDir.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let texture = decode(url) else { return nil }
        texCache[path] = texture
        return texture
    }
    /// Loads textures in advance.
    func preload(_ paths: [String]) { for path in paths { _ = texture(path) } }
    /// Decodes an image file into a mipmapped texture.
    func decode(_ url: URL) -> MTLTexture? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let w = image.width, h = image.height
        guard w > 0, h > 0, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        if image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst {
            for i in 0..<(w * h) {
                let alpha = Int(pixels[i * 4 + 3])
                if alpha > 0 && alpha < 255 { for channel in 0..<3 { pixels[i * 4 + channel] = UInt8(min(255, Int(pixels[i * 4 + channel]) * 255 / alpha)) } }
            }
        }
        let levels = Int(floor(log2(Double(max(w, h))))) + 1
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: levels > 1)
        textureDescriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixels, bytesPerRow: w * 4)
        if levels > 1, let mipmapCommands = queue.makeCommandBuffer(), let blit = mipmapCommands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture); blit.endEncoding(); mipmapCommands.commit(); mipmapCommands.waitUntilCompleted()
        }
        return texture
    }

    /// Starts a frame: computes the letterboxed viewport and opens a render pass.
    func begin(view: MTKView) -> MTLCommandBuffer? {
        inflight.wait()
        guard let passDescriptor = view.currentRenderPassDescriptor, let commandBuffer = queue.makeCommandBuffer() else { inflight.signal(); return nil }
        let drawableSize = view.drawableSize
        let drawableWidth = Float(drawableSize.width), drawableHeight = Float(drawableSize.height)
        var w = drawableWidth, h = drawableWidth * virtualHeight / virtualWidth
        if h > drawableHeight { h = drawableHeight; w = drawableHeight * virtualWidth / virtualHeight }
        viewportPx = R(((drawableWidth - w) / 2).rounded(), ((drawableHeight - h) / 2).rounded(), w.rounded(), h.rounded())
        pxScale = viewportPx.w / virtualWidth
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { inflight.signal(); return nil }
        encoder = renderEncoder
        renderEncoder.setViewport(MTLViewport(originX: Double(viewportPx.x), originY: Double(viewportPx.y), width: Double(viewportPx.w), height: Double(viewportPx.h), znear: 0, zfar: 1))
        projection = float4x4(rows: [SIMD4(2 / virtualWidth, 0, 0, -1), SIMD4(0, -2 / virtualHeight, 0, 1), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)])
        verts = buffers[bufIndex].contents().bindMemory(to: Vtx.self, capacity: maxVerts)
        vcount = 0; flushedFrom = 0; curTex = nil
        renderEncoder.setRenderPipelineState(pipeline)
        renderEncoder.setFragmentSamplerState(sampler, index: 0)
        frameNo += 1
        return commandBuffer
    }
    /// Finishes the frame and presents it.
    func end(_ commandBuffer: MTLCommandBuffer, view: MTKView) {
        flush()
        encoder?.endEncoding(); encoder = nil
        if let drawable = view.currentDrawable { commandBuffer.present(drawable) }
        let semaphore = inflight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
        commandBuffer.commit()
        bufIndex = (bufIndex + 1) % 3
        if frameNo % 600 == 0 { trimTextCache() }
    }
    /// Sends the queued quads to the GPU.
    func flush() {
        guard let encoder = encoder, vcount > flushedFrom, let batchTexture = curTex else { return }
        encoder.setVertexBuffer(buffers[bufIndex], offset: 0, index: 0)
        encoder.setVertexBytes(&projection, length: MemoryLayout<float4x4>.stride, index: 1)
        encoder.setFragmentTexture(batchTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: flushedFrom, vertexCount: vcount - flushedFrom)
        flushedFrom = vcount
    }

    /// Queues a textured quad.
    func quad(_ texture: MTLTexture, _ rect: R, uv: R = R(0, 0, 1, 1), color tint: RGBA = .white, mode: Float = 0, rotation: Float = 0) {
        if vcount + 6 > maxVerts { return }
        if texture !== curTex { flush(); curTex = texture }
        let vertexColor = SIMD4<Float>(tint.r, tint.g, tint.b, tint.a)
        var corners = [SIMD2<Float>(rect.x, rect.y), SIMD2(rect.x + rect.w, rect.y), SIMD2(rect.x, rect.y + rect.h), SIMD2(rect.x + rect.w, rect.y + rect.h)]
        if rotation != 0 {
            let center = rect.mid, cs = cos(rotation), sn = sin(rotation)
            corners = corners.map { corner in let offset = corner - center; return center + SIMD2(offset.x * cs - offset.y * sn, offset.x * sn + offset.y * cs) }
        }
        let texCoords = [SIMD2<Float>(uv.x, uv.y), SIMD2(uv.x + uv.w, uv.y), SIMD2(uv.x, uv.y + uv.h), SIMD2(uv.x + uv.w, uv.y + uv.h)]
        for i in [0, 1, 2, 1, 3, 2] { verts[vcount] = Vtx(pos: corners[i], uv: texCoords[i], color: vertexColor, mode: mode); vcount += 1 }
    }
    /// Draws an image stretched into a rectangle.
    func image(_ path: String, _ rect: R, color: RGBA = .white, rotation: Float = 0) {
        guard let loadedTexture = texture(path) else { return }
        quad(loadedTexture, rect, color: color, rotation: rotation)
    }
    /// Draws an image filling a rectangle, cropping to keep its aspect ratio.
    func imageCover(_ path: String, _ rect: R, color: RGBA = .white) {
        guard let loadedTexture = texture(path) else { return }
        let textureAspect = Float(loadedTexture.width) / Float(loadedTexture.height), ra = rect.w / rect.h
        var uv = R(0, 0, 1, 1)
        if textureAspect > ra { uv.w = ra / textureAspect; uv.x = (1 - uv.w) / 2 } else { uv.h = textureAspect / ra; uv.y = (1 - uv.h) / 2 }
        quad(loadedTexture, rect, uv: uv, color: color)
    }
    /// Draws an image fitted inside a rectangle.
    func imageContain(_ path: String, _ rect: R, color: RGBA = .white, alignTop: Bool = false) {
        guard let loadedTexture = texture(path) else { return }
        let textureAspect = Float(loadedTexture.width) / Float(loadedTexture.height), ra = rect.w / rect.h
        var destination = rect
        if textureAspect > ra { destination.h = rect.w / textureAspect; if !alignTop { destination.y = rect.y + (rect.h - destination.h) / 2 } } else { destination.w = rect.h * textureAspect; destination.x = rect.x + (rect.w - destination.w) / 2 }
        quad(loadedTexture, destination, color: color)
    }
    /// Restricts drawing to a rectangle (nil removes the clip).
    func clip(_ rect: R?) {
        flush()
        guard let encoder = encoder else { return }
        let viewport = viewportPx
        if let rect = rect {
            let x = max(0, Int(viewport.x + rect.x * pxScale)), y = max(0, Int(viewport.y + rect.y * pxScale))
            let w = max(1, Int(rect.w * pxScale)), h = max(1, Int(rect.h * pxScale))
            encoder.setScissorRect(MTLScissorRect(x: x, y: y, width: w, height: h))
        } else {
            encoder.setScissorRect(MTLScissorRect(x: Int(viewport.x), y: Int(viewport.y), width: Int(viewport.w), height: Int(viewport.h)))
        }
    }
    /// Draws a filled rectangle.
    func rect(_ rect: R, _ color: RGBA) { quad(white, rect, color: color) }
    /// Draws a rectangle outline.
    func frame(_ area: R, _ color: RGBA, _ thickness: Float = 2) {
        let t = thickness
        rect(R(area.x, area.y, area.w, t), color); rect(R(area.x, area.y + area.h - t, area.w, t), color)
        rect(R(area.x, area.y + t, t, area.h - 2 * t), color); rect(R(area.x + area.w - t, area.y + t, t, area.h - 2 * t), color)
    }
    /// Draws a vertical gradient.
    func gradient(_ area: R, _ top: RGBA, _ bottom: RGBA, steps: Int = 24) {
        let stepCount = max(1, steps)
        for i in 0..<stepCount {
            let startFraction = Float(i) / Float(stepCount), endFraction = Float(i + 1) / Float(stepCount)
            let midFraction = (startFraction + endFraction) / 2
            let color = RGBA(r: top.r + (bottom.r - top.r) * midFraction, g: top.g + (bottom.g - top.g) * midFraction,
                             b: top.b + (bottom.b - top.b) * midFraction, a: top.a + (bottom.a - top.a) * midFraction)
            rect(R(area.x, area.y + area.h * startFraction, area.w, area.h * (endFraction - startFraction) + 0.5), color)
        }
    }

    /// Font description: family, size and style.
    struct Font: Hashable { let name: String; let size: Float; let bold: Bool; let italic: Bool
        /// System sans-serif font.
        static func ui(_ size: Float, bold: Bool = false) -> Font { Font(name: "Helvetica Neue", size: size, bold: bold, italic: false) }
        /// Serif font (Georgia).
        static func serif(_ size: Float, bold: Bool = false, italic: Bool = false) -> Font { Font(name: "Georgia", size: size, bold: bold, italic: italic) }
        /// The Gwent logo font.
        static func gwent(_ size: Float) -> Font { Font(name: "GWENT-ExtraBold", size: size, bold: false, italic: false) }
    }
    /// Text alignment.
    enum Align { case left, center, right }

    /// Creates the CoreText font for a given pixel scale.
    func ctFont(_ style: Font, scale: Float) -> CTFont {
        var font = CTFontCreateWithName(style.name as CFString, CGFloat(style.size * scale), nil)
        var traits: CTFontSymbolicTraits = []
        if style.bold { traits.insert(.traitBold) }
        if style.italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let styled = CTFontCreateCopyWithSymbolicTraits(font, 0, nil, traits, traits) { font = styled }
        return font
    }
    /// Renders text into a cached greyscale texture.
    func textTex(_ text: String, _ font: Font, maxWidth: Float = 0, align: Align = .left, lineSpacing: Float = 0) -> TextTex? {
        if text.isEmpty { return nil }
        let scale = max(0.5, pxScale)
        let key = "\(text)|\(font.name)|\(font.size)|\(font.bold)|\(font.italic)|\(maxWidth)|\(align)|\(lineSpacing)|\(scale)"
        if let cached = textCache[key] { textCache[key] = (cached.0, frameNo); return cached.0 }
        let font = ctFont(font, scale: scale)
        let para = NSMutableParagraphStyle()
        para.alignment = align == .center ? .center : (align == .right ? .right : .left)
        para.lineSpacing = CGFloat(lineSpacing * scale)
        para.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1), .paragraphStyle: para])
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let constraintW = maxWidth > 0 ? CGFloat(maxWidth * scale) : CGFloat.greatestFiniteMagnitude
        var size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, CGSize(width: constraintW, height: .greatestFiniteMagnitude), nil)
        if maxWidth > 0 && align != .left { size.width = constraintW }
        let padding: CGFloat = 2
        let pixelWidth = Int(ceil(size.width + padding * 2)), pixelHeight = Int(ceil(size.height + padding * 2))
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth < 16384, pixelHeight < 16384,
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 0, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.setAllowsFontSmoothing(false); context.setShouldAntialias(true)
        let path = CGPath(rect: CGRect(x: padding, y: padding, width: CGFloat(pixelWidth) - padding * 2, height: CGFloat(pixelHeight) - padding * 2), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.setFillColor(gray: 1, alpha: 1)
        CTFrameDraw(frame, context)
        let textDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: pixelWidth, height: pixelHeight, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: textDescriptor), let data = context.data else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0, withBytes: data, bytesPerRow: pixelWidth)
        let textTexture = TextTex(texture: texture, w: Float(pixelWidth) / scale, h: Float(pixelHeight) / scale)
        textCache[key] = (textTexture, frameNo)
        return textTexture
    }
    /// Drops text textures that were not used recently.
    func trimTextCache() { textCache = textCache.filter { frameNo - $0.value.1 < 600 } }

    @discardableResult
    /// Draws text and returns its size.
    func text(_ string: String, _ font: Font, x: Float, y: Float, color: RGBA = .white, maxWidth: Float = 0, align: Align = .left,
              shadow: RGBA? = RGBA(r: 0, g: 0, b: 0, a: 0.85), lineSpacing: Float = 0) -> (w: Float, h: Float) {
        guard let textTexture = textTex(string, font, maxWidth: maxWidth, align: align, lineSpacing: lineSpacing) else { return (0, 0) }
        var x0 = x
        if maxWidth <= 0 || align == .left {
            if align == .center { x0 = x - textTexture.w / 2 } else if align == .right { x0 = x - textTexture.w }
        } else if align == .center { x0 = x - textTexture.w / 2 } else if align == .right { x0 = x - textTexture.w }
        if let shadowColor = shadow {
            let shadowOffset = max(1, font.size * 0.06)
            quad(textTexture.texture, R(x0 + shadowOffset, y + shadowOffset, textTexture.w, textTexture.h), color: shadowColor, mode: 1)
        }
        quad(textTexture.texture, R(x0, y, textTexture.w, textTexture.h), color: color, mode: 1)
        return (textTexture.w, textTexture.h)
    }
    /// Measures text without drawing it.
    func measure(_ text: String, _ font: Font, maxWidth: Float = 0) -> (w: Float, h: Float) {
        guard let textTexture = textTex(text, font, maxWidth: maxWidth) else { return (0, 0) }
        return (textTexture.w, textTexture.h)
    }

    /// Uniforms for the title-screen shader.
    struct BgParams { var time: Float; var mouse: SIMD2<Float>; var texel: SIMD2<Float>; var pad: Float = 0 }
    /// An animated region of the title background (position/size and motion).
    struct BgRegion { var bounds: SIMD4<Float>; var motion: SIMD4<Float> }
    /// Draws the animated title background with the dedicated shader.
    func titleBackground(_ path: String, time: Float, mouse: SIMD2<Float>, regions: [BgRegion], glints: [SIMD2<Float>], candles: [SIMD2<Float>]) {
        guard let loadedTexture = texture(path), let encoder = encoder else { return }
        flush()
        encoder.setRenderPipelineState(bgPipeline)
        var params = BgParams(time: time, mouse: mouse, texel: SIMD2(1 / Float(loadedTexture.width), 1 / Float(loadedTexture.height)))
        var regs = regions; while regs.count < 48 { regs.append(BgRegion(bounds: .zero, motion: .zero)) }
        var glintPositions = glints; while glintPositions.count < 2 { glintPositions.append(.zero) }
        var candlePositions = candles; while candlePositions.count < 3 { candlePositions.append(SIMD2(-1, -1)) }
        encoder.setFragmentBytes(&params, length: MemoryLayout<BgParams>.stride, index: 0)
        encoder.setFragmentBytes(&regs, length: MemoryLayout<BgRegion>.stride * 48, index: 1)
        encoder.setFragmentBytes(&glintPositions, length: MemoryLayout<SIMD2<Float>>.stride * 2, index: 2)
        encoder.setFragmentBytes(&candlePositions, length: MemoryLayout<SIMD2<Float>>.stride * 3, index: 3)
        encoder.setFragmentTexture(loadedTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.setRenderPipelineState(pipeline)
        curTex = nil
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vtx { float2 pos; float2 uv; float4 color; float mode; float3 pad; };
    struct VO { float4 pos [[position]]; float2 uv; float4 color; float mode; };
    vertex VO vmain(const device Vtx* v [[buffer(0)]], constant float4x4& m [[buffer(1)]], uint id [[vertex_id]]) {
        VO o; o.pos = m * float4(v[id].pos, 0, 1); o.uv = v[id].uv; o.color = v[id].color; o.mode = v[id].mode; return o;
    }
    fragment float4 fmain(VO in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {
        float4 c = t.sample(s, in.uv);
        if (in.mode > 0.5) return float4(in.color.rgb, in.color.a * c.r);
        return c * in.color;
    }

    struct BVO { float4 pos [[position]]; float2 uv; };
    vertex BVO vbg(uint id [[vertex_id]]) {
        float2 p = float2((id & 1) ? 1.0 : -1.0, (id & 2) ? -1.0 : 1.0);
        BVO o; o.pos = float4(p, 0, 1); o.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5); return o;
    }
    struct BgParams { float time; float2 mouse; float2 texel; float pad; };
    struct BgRegion { float4 reg; float4 mot; };
    static float hash2(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
    static float flick(float t) { return 0.5*sin(t*7.3) + 0.3*sin(t*13.1+1.7) + 0.2*sin(t*23.7+4.1); }
    static float gauss(float2 uv, float4 r) { float2 d = (uv - r.xy) / r.zw; return exp(-dot(d, d) * 2.2); }
    fragment float4 fbg(BVO in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]],
                        constant BgParams& P [[buffer(0)]], constant BgRegion* regs [[buffer(1)]],
                        constant float2* glint [[buffer(2)]], constant float2* candle [[buffer(3)]]) {
        float t = P.time;
        float2 uv = in.uv;
        float z = 1.03 + 0.012 * sin(t * 0.045);
        uv = (uv - 0.5) / z + 0.5 + float2(sin(t * 0.031), cos(t * 0.027)) * 0.003;
        float depth = 0.25 + 0.45 * smoothstep(0.12, 0.35, uv.y)
            + 0.6 * gauss(uv, float4(0.25, 0.86, 0.13, 0.17)) + 0.6 * gauss(uv, float4(0.855, 0.89, 0.09, 0.15));
        uv -= P.mouse * depth * float2(1.8 / 1920.0, 1.8 / 1080.0);
        float2 disp = 0;
        for (int i = 0; i < 48; i++) {
            float4 R = regs[i].reg, M = regs[i].mot;
            if (R.z <= 0) continue;
            float w = gauss(uv, R);
            if (w < 0.002) continue;
            float sn = sin(t * 6.2831853 / M.z + M.w);
            if (M.x < 0.5) {
                float b = 0.5 + 0.5 * sn; b = b * b * (3.0 - 2.0 * b);
                disp -= (uv - R.xy) * (M.y * 0.014 * b) * w;
                disp.y += M.y * (2.4 / 1080.0) * b * w;
            } else {
                float s2 = sin(t * 6.2831853 / (M.z * 1.37) + M.w * 1.7);
                disp += float2(sn * M.y * 1.5 / 1920.0, s2 * M.y * 0.9 / 1080.0) * w;
            }
        }
        uv += disp;
        uv = clamp(uv, P.texel, 1.0 - P.texel);
        float3 c = tex.sample(s, uv).rgb;
        float f = flick(t);
        float warm = gauss(uv, float4(0.47, 0.62, 0.45, 0.5)) * 0.55;
        for (int k = 0; k < 3; k++) if (candle[k].x >= 0) warm += gauss(uv, float4(candle[k], 0.08, 0.1)) * 0.8;
        for (int g = 0; g < 2; g++) warm += gauss(uv, float4(glint[g], 0.04, 0.06)) * 0.7;
        c *= 1.0 + warm * (0.05 + 0.045 * f) * float3(1.0, 0.86, 0.62);
        for (int k = 0; k < 3; k++) if (candle[k].x >= 0) {
            float fk = flick(t * 1.07 + float(k) * 3.1);
            c += float3(1.0, 0.58, 0.22) * gauss(uv, float4(candle[k], 0.035, 0.06)) * (0.07 + 0.04 * fk);
        }
        for (int g = 0; g < 2; g++) {
            float2 d = (uv - glint[g]) * float2(1920.0, 1080.0);
            float tw = pow(max(0.0, sin(t * (0.9 + 0.4 * float(g)) + float(g) * 2.3)), 24.0);
            float star = exp(-dot(d, d) / 60.0) + 0.35 * exp(-abs(d.x) * 0.6) * exp(-d.y * d.y / 3.0) + 0.35 * exp(-abs(d.y) * 0.6) * exp(-d.x * d.x / 3.0);
            c += float3(1.0, 0.9, 0.7) * star * tw * 0.55;
        }
        float rx = uv.x * 0.85 + uv.y * 0.45;
        float ray = pow(0.5 + 0.5 * sin(rx * 26.0 + sin(t * 0.11) * 2.0), 6.0) * 0.6 + pow(0.5 + 0.5 * sin(rx * 11.0 - t * 0.07), 8.0) * 0.4;
        c += float3(1.0, 0.82, 0.55) * ray * smoothstep(0.85, 0.0, uv.y) * 0.045;
        float2 q = in.uv;
        c *= 1.0 - 0.42 * smoothstep(0.30, 0.0, q.y) - 0.5 * smoothstep(0.74, 1.0, q.y);
        c *= mix(0.5, 1.0, smoothstep(1.15, 0.35, length((q - 0.5) * float2(1.25, 1.0))));
        c += (hash2(q * float2(1920.0, 1080.0) + fract(t * 0.73) * 91.0) - 0.5) * 0.016;
        return float4(c, 1.0);
    }
    """
}
