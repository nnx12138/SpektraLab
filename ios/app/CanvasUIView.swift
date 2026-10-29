//  CanvasUIView.swift — the MTKView and its gestures, iOS.
//
//  The macOS counterpart (`Canvas/MetalCanvasView.swift`) carries the drawing
//  notes; this file keeps only what changes for UIKit:
//
//    * the drawable is sized from `traitCollection.displayScale`, always up,
//      for the same rounded-down-sliver reason the Mac file documents;
//    * the viewport sync is the same arithmetic (`ViewportState`), fed the
//      same bounds;
//    * gestures: one-finger drag pans (or drives a mask grip / a pair
//      placement, in the priority the Mac's mouse path uses), pinch zooms
//      about the pinch, double-tap toggles fit ↔ 100 %, a tap picks when a
//      picker is active and clicks the pair's hole otherwise. The crop
//      tool's on-canvas handle dragging is macOS-only for now — the crop
//      section's sliders edit the same `Geometry`.
//
//  `Session` implements `CanvasHost` once for both platforms; every method
//  this view calls exists in the shared protocol.

#if os(iOS)
import UIKit
import MetalKit
import SwiftUI

@MainActor
final class CanvasUIView: MTKView, MTKViewDelegate {
    weak var host: (any CanvasHost)?
    private var drawScheduled = false

    /// A pan in flight: where it started, and what it is driving — the
    /// priority ladder is the macOS `mouseDown` one: mask grip, pair
    /// placement, plain pan.
    private enum PanDrive {
        case none
        case maskGrip(MaskHandle)
        case placement
        case viewport(last: CGPoint)
    }
    private var panDrive: PanDrive = .none
    private var panStart: CGPoint = .zero

    var renderer: Renderer? { host?.renderer }

    init(host: CanvasHost) {
        self.host = host
        super.init(frame: .zero, device: host.renderer.device)
        delegate = self
        isPaused = true
        enableSetNeedsDisplay = true
        colorPixelFormat = Renderer.drawableFormat
        framebufferOnly = true
        // **Not `autoResizeDrawable`** — sized in `layoutSubviews`, always up.
        autoResizeDrawable = false
        let g = CGFloat(CanvasGround.value)
        clearColor = MTLClearColor(red: Double(g), green: Double(g), blue: Double(g), alpha: 1)
        if let layer = layer as? CAMetalLayer {
            // The layer is tagged with the working space; the renderer draws
            // ProPhoto and the system converts for the display (RFC-018 D2).
            layer.colorspace = ImageDecoder.workingSpace
        }
        backgroundColor = UIColor(red: 0x5F / 255.0, green: 0x5F / 255.0, blue: 0x5F / 255.0, alpha: 1)
        host.renderer.needsDraw = { [weak self] in self?.scheduleDraw() }
        installGestures()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not from a nib") }

    // MARK: layout / draw

    override func layoutSubviews() {
        super.layoutSubviews()
        sizeDrawable()
        syncViewport()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        sizeDrawable()
        syncViewport()
    }

    /// Drawable **cover** the layer, never under it — see the macOS file for
    /// the measured seam a rounded-down drawable leaves.
    private func sizeDrawable() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let bs = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        let want = CGSize(width: ceil(bounds.width * bs), height: ceil(bounds.height * bs))
        if drawableSize != want { drawableSize = want }
    }

    /// One draw per runloop turn, via `MTKView.draw()` — `setNeedsDisplay`
    /// alone does not fire the delegate (measured on the Mac; the iOS recipe
    /// is the same MTKView, so the same mechanism is used unconditionally).
    func scheduleDraw() {
        setNeedsDisplay()
        guard !drawScheduled else { return }
        drawScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.drawScheduled = false
            guard self.window != nil, self.bounds.width > 0, self.bounds.height > 0 else { return }
            self.draw()
        }
    }

    func syncViewport() {
        guard let renderer, bounds.width > 0, bounds.height > 0 else { return }
        let bs = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        var vp = renderer.viewport
        vp.backingScale = bs
        if vp.viewport != bounds.size {
            vp.resize(viewport: bounds.size)
        }
        if vp != renderer.viewport {
            renderer.viewport = vp
            if renderer.editingCrop { renderer.fitRotatedPhoto() }
            host?.viewportChanged()
        }
        scheduleDraw()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { syncViewport() }

    func draw(in view: MTKView) { host?.renderer.draw(in: view) }

    // MARK: gestures

    private func installGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        addGestureRecognizer(tap)

        let double = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        // A double-tap must not also deliver two single taps.
        tap.require(toFail: double)
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard let renderer, let host else { return }
        let p = g.location(in: self)
        switch g.state {
        case .began:
            // The crop tool locks the view; a pan there does nothing rather
            // than fighting the lock (the Mac's scroll rule).
            guard host.tool != .crop else { return }
            if let h = maskHandle(near: p) { panDrive = .maskGrip(h); return }
            if host.placementBegan(at: unclampedNormalised(atView: p)) {
                panDrive = .placement
                return
            }
            panDrive = .viewport(last: p)
        case .changed:
            switch panDrive {
            case .maskGrip(let handle):
                // Through the crop: the grip is anchored to the source and
                // the canvas is showing the output — the macOS drag's
                // conversion, verbatim.
                if let out = renderer.viewport.normalised(atView: p) {
                    host.maskHandleDragged(handle, to: host.geometry.sourcePoint(
                        forOutput: out, imageSize: host.sourceImageSize))
                }
            case .placement:
                host.placementMoved(to: unclampedNormalised(atView: p))
            case .viewport(let last):
                let d = CGPoint(x: p.x - last.x, y: p.y - last.y)
                renderer.viewport.pan(by: CGSize(width: d.x, height: d.y))
                panDrive = .viewport(last: p)
                host.viewportChanged()
                scheduleDraw()
            case .none:
                break
            }
        default:
            if case .placement = panDrive { host.placementEnded() }
            panDrive = .none
        }
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        guard let renderer, let host, host.tool != .crop else { return }
        guard g.state == .changed else { return }
        let p = g.location(in: self)
        if host.placementZoomed(by: Double(g.magnification), at: unclampedNormalised(atView: p)) {
            return
        }
        renderer.viewport.zoom(by: g.magnification, about: p)
        host.viewportChanged()
        scheduleDraw()
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        guard let renderer, let host else { return }
        let p = g.location(in: self)
        if host.pickerActive, let n = renderer.viewport.normalised(atView: p) {
            host.picked(normalised: n)
            return
        }
        host.clicked(normalised: unclampedNormalised(atView: p))
    }

    @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
        guard let renderer, let host, host.tool != .crop else { return }
        renderer.viewport.toggleHundred(about: g.location(in: self))
        host.viewportChanged()
        scheduleDraw()
    }

    // MARK: shared point arithmetic (mirrors the macOS view's helpers)

    /// The image-normalised point under a view point, without the 0…1 guard:
    /// a drag that leaves the picture is still a drag.
    private func unclampedNormalised(atView p: CGPoint) -> CGPoint {
        guard let renderer else { return .zero }
        let v = renderer.viewport
        let ip = v.imagePoint(atView: p)
        return CGPoint(x: ip.x / max(v.image.width, 1), y: ip.y / max(v.image.height, 1))
    }

    /// The mask grip under a view point, positions from the host so this and
    /// `MaskOverlay` cannot disagree.
    private func maskHandle(near p: CGPoint) -> MaskHandle? {
        guard let host, let renderer else { return nil }
        let handles = host.maskHandles
        guard !handles.isEmpty else { return nil }
        let size = host.sourceImageSize
        let v = renderer.viewport
        var best: (MaskHandle, CGFloat)?
        for h in handles {
            let o = host.geometry.outputPoint(forSource: h.position, imageSize: size)
            let q = CGPoint(x: v.offset.x + o.x * v.image.width * v.scale,
                            y: v.offset.y + o.y * v.image.height * v.scale)
            let d = hypot(q.x - p.x, q.y - p.y)
            if d <= Self.handleGrab, best == nil || d < best!.1 { best = (h, d) }
        }
        return best?.0
    }

    static let handleGrab: CGFloat = 22   // a finger, not a cursor: 22 pt

    private func log(_ message: @autoclosure () -> String) {
        guard Renderer.logDraws else { return }
        FileHandle.standardError.write(Data("canvasview: \(message())\n".utf8))
    }
}

// MARK: SwiftUI bridge

struct MetalCanvasView: UIViewRepresentable {
    let host: CanvasHost

    func makeUIView(context: Context) -> CanvasUIView {
        CanvasUIView(host: host)
    }

    func updateUIView(_ view: CanvasUIView, context: Context) {
        view.host = host
        view.scheduleDraw()
    }
}
#endif // os(iOS)
