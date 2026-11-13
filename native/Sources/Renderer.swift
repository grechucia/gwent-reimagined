import Metal
import MetalKit
import CoreText
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

let VW: Float = 1920, VH: Float = 1080

struct RGBA { var r, g, b, a: Float
    static let white = RGBA(r: 1, g: 1, b: 1, a: 1), black = RGBA(r: 0, g: 0, b: 0, a: 1)
    static func gray(_ v: Float, _ a: Float = 1) -> RGBA { RGBA(r: v, g: v, b: v, a: a) }
    func alpha(_ m: Float) -> RGBA { RGBA(r: r, g: g, b: b, a: a * m) }
    static let gold = RGBA(r: 0.95, g: 0.80, b: 0.45, a: 1), goldDark = RGBA(r: 0.79, g: 0.63, b: 0.29, a: 1)
}

struct R: Equatable { var x, y, w, h: Float
    init(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { self.x = x; self.y = y; self.w = w; self.h = h }
    func contains(_ p: SIMD2<Float>) -> Bool { p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h }
    func inset(_ d: Float) -> R { R(x + d, y + d, w - 2 * d, h - 2 * d) }
    var mid: SIMD2<Float> { SIMD2(x + w / 2, y + h / 2) }
}

private struct Vtx { var pos: SIMD2<Float>; var uv: SIMD2<Float>; var color: SIMD4<Float>; var mode: Float; var pad: SIMD3<Float> = .zero }

final class TextTex { let tex: MTLTexture; let w: Float; let h: Float
    init(tex: MTLTexture, w: Float, h: Float) { self.tex = tex; self.w = w; self.h = h } }

final class Renderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let bgPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let loader: MTKTextureLoader
    private var buffers: [MTLBuffer] = []
    private var bufIndex = 0
    private let inflight = DispatchSemaphore(value: 3)
    private let maxVerts = 120_000
    private var verts: UnsafeMutablePointer<Vtx>!
    private var vcount = 0, flushedFrom = 0
    private var curTex: MTLTexture?
    private var enc: MTLRenderCommandEncoder?
    private var projection = matrix_identity_float4x4
    let white: MTLTexture
    private(set) var pxScale: Float = 1
    private(set) var viewportPx = R(0, 0, 1, 1)
    private var texCache: [String: MTLTexture] = [:]
    private var textCache: [String: (TextTex, Int)] = [:]
    private var frameNo = 0
    let gameDir: URL

    init?(view: MTKView, gameDir: URL) {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
        device = d; queue = q; self.gameDir = gameDir
        view.device = d
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        loader = MTKTextureLoader(device: d)
        let lib: MTLLibrary
        do { lib = try d.makeLibrary(source: Renderer.shaderSource, options: nil) }
        catch { fatalError("Metal: \(error)") }
        func pipe(_ v: String, _ f: String) -> MTLRenderPipelineState {
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = lib.makeFunction(name: v); p.fragmentFunction = lib.makeFunction(name: f)
            let a = p.colorAttachments[0]!
            a.pixelFormat = .bgra8Unorm
            a.isBlendingEnabled = true
            a.rgbBlendOperation = .add; a.alphaBlendOperation = .add
            a.sourceRGBBlendFactor = .sourceAlpha; a.destinationRGBBlendFactor = .oneMinusSourceAlpha
            a.sourceAlphaBlendFactor = .one; a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try! d.makeRenderPipelineState(descriptor: p)
        }
        pipeline = pipe("vmain", "fmain")
        bgPipeline = pipe("vbg", "fbg")
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear; sd.mipFilter = .linear
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        sampler = d.makeSamplerState(descriptor: sd)!
        for _ in 0..<3 { buffers.append(d.makeBuffer(length: MemoryLayout<Vtx>.stride * maxVerts, options: .storageModeShared)!) }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        white = d.makeTexture(descriptor: td)!
        var px: [UInt8] = [255, 255, 255, 255]
        white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
    }

    func texture(_ rel: String) -> MTLTexture? {
        if let t = texCache[rel] { return t }
        let url = gameDir.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let t = decode(url) else { return nil }
        texCache[rel] = t
        return t
    }
    func preload(_ rels: [String]) { for r in rels { _ = texture(r) } }
    private func decode(_ url: URL) -> MTLTexture? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let w = img.width, h = img.height
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        if img.alphaInfo != .none && img.alphaInfo != .noneSkipLast && img.alphaInfo != .noneSkipFirst {
            for i in 0..<(w * h) {
                let a = Int(px[i * 4 + 3])
                if a > 0 && a < 255 { for k in 0..<3 { px[i * 4 + k] = UInt8(min(255, Int(px[i * 4 + k]) * 255 / a)) } }
            }
        }
        let levels = Int(floor(log2(Double(max(w, h))))) + 1
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: levels > 1)
        td.usage = [.shaderRead]
        guard let t = device.makeTexture(descriptor: td) else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: px, bytesPerRow: w * 4)
        if levels > 1, let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: t); blit.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        }
        return t
    }

    func begin(view: MTKView) -> MTLCommandBuffer? {
        inflight.wait()
        guard let rpd = view.currentRenderPassDescriptor, let cb = queue.makeCommandBuffer() else { inflight.signal(); return nil }
        let ds = view.drawableSize
        let dw = Float(ds.width), dh = Float(ds.height)
        var w = dw, h = dw * VH / VW
        if h > dh { h = dh; w = dh * VW / VH }
        viewportPx = R(((dw - w) / 2).rounded(), ((dh - h) / 2).rounded(), w.rounded(), h.rounded())
        pxScale = viewportPx.w / VW
        guard let e = cb.makeRenderCommandEncoder(descriptor: rpd) else { inflight.signal(); return nil }
        enc = e
        e.setViewport(MTLViewport(originX: Double(viewportPx.x), originY: Double(viewportPx.y), width: Double(viewportPx.w), height: Double(viewportPx.h), znear: 0, zfar: 1))
        projection = float4x4(rows: [SIMD4(2 / VW, 0, 0, -1), SIMD4(0, -2 / VH, 0, 1), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)])
        verts = buffers[bufIndex].contents().bindMemory(to: Vtx.self, capacity: maxVerts)
        vcount = 0; flushedFrom = 0; curTex = nil
        e.setRenderPipelineState(pipeline)
        e.setFragmentSamplerState(sampler, index: 0)
        frameNo += 1
        return cb
    }
    func end(_ cb: MTLCommandBuffer, view: MTKView) {
        flush()
        enc?.endEncoding(); enc = nil
        if let d = view.currentDrawable { cb.present(d) }
        let sem = inflight
        cb.addCompletedHandler { _ in sem.signal() }
        cb.commit()
        bufIndex = (bufIndex + 1) % 3
        if frameNo % 600 == 0 { trimTextCache() }
    }
    private func flush() {
        guard let e = enc, vcount > flushedFrom, let t = curTex else { return }
        e.setVertexBuffer(buffers[bufIndex], offset: 0, index: 0)
        e.setVertexBytes(&projection, length: MemoryLayout<float4x4>.stride, index: 1)
        e.setFragmentTexture(t, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: flushedFrom, vertexCount: vcount - flushedFrom)
        flushedFrom = vcount
    }

    func quad(_ t: MTLTexture, _ r: R, uv: R = R(0, 0, 1, 1), color c: RGBA = .white, mode: Float = 0, rotation: Float = 0) {
        if vcount + 6 > maxVerts { return }
        if t !== curTex { flush(); curTex = t }
        let col = SIMD4<Float>(c.r, c.g, c.b, c.a)
        var p = [SIMD2<Float>(r.x, r.y), SIMD2(r.x + r.w, r.y), SIMD2(r.x, r.y + r.h), SIMD2(r.x + r.w, r.y + r.h)]
        if rotation != 0 {
            let m = r.mid, cs = cos(rotation), sn = sin(rotation)
            p = p.map { q in let d = q - m; return m + SIMD2(d.x * cs - d.y * sn, d.x * sn + d.y * cs) }
        }
        let u = [SIMD2<Float>(uv.x, uv.y), SIMD2(uv.x + uv.w, uv.y), SIMD2(uv.x, uv.y + uv.h), SIMD2(uv.x + uv.w, uv.y + uv.h)]
        for i in [0, 1, 2, 1, 3, 2] { verts[vcount] = Vtx(pos: p[i], uv: u[i], color: col, mode: mode); vcount += 1 }
    }
    func image(_ rel: String, _ r: R, color: RGBA = .white, rotation: Float = 0) {
        guard let t = texture(rel) else { return }
        quad(t, r, color: color, rotation: rotation)
    }
    func imageCover(_ rel: String, _ r: R, color: RGBA = .white) {
        guard let t = texture(rel) else { return }
        let ta = Float(t.width) / Float(t.height), ra = r.w / r.h
        var uv = R(0, 0, 1, 1)
        if ta > ra { uv.w = ra / ta; uv.x = (1 - uv.w) / 2 } else { uv.h = ta / ra; uv.y = (1 - uv.h) / 2 }
        quad(t, r, uv: uv, color: color)
    }
    func imageContain(_ rel: String, _ r: R, color: RGBA = .white, alignTop: Bool = false) {
        guard let t = texture(rel) else { return }
        let ta = Float(t.width) / Float(t.height), ra = r.w / r.h
        var d = r
        if ta > ra { d.h = r.w / ta; if !alignTop { d.y = r.y + (r.h - d.h) / 2 } } else { d.w = r.h * ta; d.x = r.x + (r.w - d.w) / 2 }
        quad(t, d, color: color)
    }
    func clip(_ r: R?) {
        flush()
        guard let e = enc else { return }
        let vp = viewportPx
        if let r = r {
            let x = max(0, Int(vp.x + r.x * pxScale)), y = max(0, Int(vp.y + r.y * pxScale))
            let w = max(1, Int(r.w * pxScale)), h = max(1, Int(r.h * pxScale))
            e.setScissorRect(MTLScissorRect(x: x, y: y, width: w, height: h))
        } else {
            e.setScissorRect(MTLScissorRect(x: Int(vp.x), y: Int(vp.y), width: Int(vp.w), height: Int(vp.h)))
        }
    }
    func rect(_ r: R, _ c: RGBA) { quad(white, r, color: c) }
    func frame(_ r: R, _ c: RGBA, _ t: Float = 2) {
        rect(R(r.x, r.y, r.w, t), c); rect(R(r.x, r.y + r.h - t, r.w, t), c)
        rect(R(r.x, r.y + t, t, r.h - 2 * t), c); rect(R(r.x + r.w - t, r.y + t, t, r.h - 2 * t), c)
    }
    func gradient(_ r: R, _ top: RGBA, _ bottom: RGBA, steps: Int = 24) {
        let n = max(1, steps)
        for i in 0..<n {
            let f0 = Float(i) / Float(n), f1 = Float(i + 1) / Float(n)
            let fm = (f0 + f1) / 2
            let c = RGBA(r: top.r + (bottom.r - top.r) * fm, g: top.g + (bottom.g - top.g) * fm, b: top.b + (bottom.b - top.b) * fm, a: top.a + (bottom.a - top.a) * fm)
            rect(R(r.x, r.y + r.h * f0, r.w, r.h * (f1 - f0) + 0.5), c)
        }
    }

    struct Font: Hashable { let name: String; let size: Float; let bold: Bool; let italic: Bool
        static func ui(_ s: Float, bold: Bool = false) -> Font { Font(name: "Helvetica Neue", size: s, bold: bold, italic: false) }
        static func serif(_ s: Float, bold: Bool = false, italic: Bool = false) -> Font { Font(name: "Georgia", size: s, bold: bold, italic: italic) }
        static func gwent(_ s: Float) -> Font { Font(name: "GWENT-ExtraBold", size: s, bold: false, italic: false) }
    }
    enum Align { case left, center, right }

    private func ctFont(_ f: Font, scale: Float) -> CTFont {
        var font = CTFontCreateWithName(f.name as CFString, CGFloat(f.size * scale), nil)
        var traits: CTFontSymbolicTraits = []
        if f.bold { traits.insert(.traitBold) }
        if f.italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let t = CTFontCreateCopyWithSymbolicTraits(font, 0, nil, traits, traits) { font = t }
        return font
    }
    func textTex(_ s: String, _ f: Font, maxWidth: Float = 0, align: Align = .left, lineSpacing: Float = 0) -> TextTex? {
        if s.isEmpty { return nil }
        let scale = max(0.5, pxScale)
        let key = "\(s)|\(f.name)|\(f.size)|\(f.bold)|\(f.italic)|\(maxWidth)|\(align)|\(lineSpacing)|\(scale)"
        if let c = textCache[key] { textCache[key] = (c.0, frameNo); return c.0 }
        let font = ctFont(f, scale: scale)
        let para = NSMutableParagraphStyle()
        para.alignment = align == .center ? .center : (align == .right ? .right : .left)
        para.lineSpacing = CGFloat(lineSpacing * scale)
        para.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1), .paragraphStyle: para])
        let fs = CTFramesetterCreateWithAttributedString(attr)
        let constraintW = maxWidth > 0 ? CGFloat(maxWidth * scale) : CGFloat.greatestFiniteMagnitude
        var size = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(location: 0, length: 0), nil, CGSize(width: constraintW, height: .greatestFiniteMagnitude), nil)
        if maxWidth > 0 && align != .left { size.width = constraintW }
        let pad: CGFloat = 2
        let W = Int(ceil(size.width + pad * 2)), H = Int(ceil(size.height + pad * 2))
        guard W > 0, H > 0, W < 16384, H < 16384,
              let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setAllowsFontSmoothing(false); ctx.setShouldAntialias(true)
        let path = CGPath(rect: CGRect(x: pad, y: pad, width: CGFloat(W) - pad * 2, height: CGFloat(H) - pad * 2), transform: nil)
        let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), path, nil)
        ctx.setFillColor(gray: 1, alpha: 1)
        CTFrameDraw(frame, ctx)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: W, height: H, mipmapped: false)
        guard let t = device.makeTexture(descriptor: td), let data = ctx.data else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0, withBytes: data, bytesPerRow: W)
        let tt = TextTex(tex: t, w: Float(W) / scale, h: Float(H) / scale)
        textCache[key] = (tt, frameNo)
        return tt
    }
    private func trimTextCache() { textCache = textCache.filter { frameNo - $0.value.1 < 600 } }

    @discardableResult
    func text(_ s: String, _ f: Font, x: Float, y: Float, color: RGBA = .white, maxWidth: Float = 0, align: Align = .left,
              shadow: RGBA? = RGBA(r: 0, g: 0, b: 0, a: 0.85), lineSpacing: Float = 0) -> (w: Float, h: Float) {
        guard let t = textTex(s, f, maxWidth: maxWidth, align: align, lineSpacing: lineSpacing) else { return (0, 0) }
        var x0 = x
        if maxWidth <= 0 || align == .left {
            if align == .center { x0 = x - t.w / 2 } else if align == .right { x0 = x - t.w }
        } else if align == .center { x0 = x - t.w / 2 } else if align == .right { x0 = x - t.w }
        if let s = shadow {
            let o = max(1, f.size * 0.06)
            quad(t.tex, R(x0 + o, y + o, t.w, t.h), color: s, mode: 1)
        }
        quad(t.tex, R(x0, y, t.w, t.h), color: color, mode: 1)
        return (t.w, t.h)
    }
    func measure(_ s: String, _ f: Font, maxWidth: Float = 0) -> (w: Float, h: Float) {
        guard let t = textTex(s, f, maxWidth: maxWidth) else { return (0, 0) }
        return (t.w, t.h)
    }

    struct BgParams { var time: Float; var mouse: SIMD2<Float>; var texel: SIMD2<Float>; var pad: Float = 0 }
    struct BgRegion { var reg: SIMD4<Float>; var mot: SIMD4<Float> }
    func titleBackground(_ rel: String, time: Float, mouse: SIMD2<Float>, regions: [BgRegion], glints: [SIMD2<Float>], candles: [SIMD2<Float>]) {
        guard let t = texture(rel), let e = enc else { return }
        flush()
        e.setRenderPipelineState(bgPipeline)
        var p = BgParams(time: time, mouse: mouse, texel: SIMD2(1 / Float(t.width), 1 / Float(t.height)))
        var regs = regions; while regs.count < 48 { regs.append(BgRegion(reg: .zero, mot: .zero)) }
        var gl = glints; while gl.count < 2 { gl.append(.zero) }
        var cd = candles; while cd.count < 3 { cd.append(SIMD2(-1, -1)) }
        e.setFragmentBytes(&p, length: MemoryLayout<BgParams>.stride, index: 0)
        e.setFragmentBytes(&regs, length: MemoryLayout<BgRegion>.stride * 32, index: 1)
        e.setFragmentBytes(&gl, length: MemoryLayout<SIMD2<Float>>.stride * 2, index: 2)
        e.setFragmentBytes(&cd, length: MemoryLayout<SIMD2<Float>>.stride * 3, index: 3)
        e.setFragmentTexture(t, index: 0)
        e.setFragmentSamplerState(sampler, index: 0)
        e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        e.setRenderPipelineState(pipeline)
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
