//  FilmstripBar.swift — the strip, iOS.
//
//  The macOS `Filmstrip` (`Panels/Filmstrip.swift`) carries the strip's
//  drag-reorder and its Finder affordances; both are desktop gestures. This
//  is the same strip without them: `FilmstripCell`'s drawing lives in the
//  macOS file, so the cell is re-declared here against the shared
//  `CropMaskedThumbnail`, and the context menu keeps the three actions that
//  make sense without a Finder.

import SwiftUI

struct FilmstripBar: View {
    @Bindable var session: Session

    var body: some View {
        HStack(spacing: 0) {
            edgeButton("chevron.left") { session.selectRelative(-1) }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(session.frames) { frame in
                            iOSFilmstripCell(frame: frame,
                                             geometry: session.thumbnailGeometry(for: frame.id),
                                             framing: session.framing(of: frame.id))
                                .id(frame.id)
                                .onTapGesture { session.click(frame.id) }
                                .contextMenu { cellMenu(for: frame) }
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: Theme.Metric.filmstripHeight)
                }
                .onChange(of: session.selection) { _, new in
                    if let new { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) } }
                }
            }
            edgeButton("chevron.right") { session.selectRelative(1) }
        }
    }

    @ViewBuilder
    private func cellMenu(for frame: Frame) -> some View {
        if HalfFramePair.isPair(frame.id) {
            Button(L("Delete Pair", zh: "删除半格拼接"), role: .destructive) {
                session.deletePair(frame.id)
            }
        } else {
            Button(L("New Half-Frame Pair", zh: "新建半格拼接")) {
                if !session.isPicked(frame.id) { session.click(frame.id) }
                session.newPair()
            }
            .disabled(!session.canMakePair)
        }
        Button(L(.helpResetDefaults)) {
            if frame.id == session.selection {
                session.resetParams(); session.resetAdjustments()
            } else {
                Sidecar.remove(for: frame.id); session.refreshState(for: frame.id)
            }
        }
    }

    private func edgeButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 18, height: Theme.Metric.filmstripHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.frames.isEmpty)
    }
}

/// `FilmstripCell`'s drawing, re-declared so the macOS file (with its drag
/// reorder and `NSWorkspace` menu) can stay out of the iOS target.
struct iOSFilmstripCell: View {
    let frame: Frame
    var geometry: Geometry
    let framing: FrameFraming

    var body: some View {
        CropMaskedThumbnail(url: frame.id, geometry: geometry) { image in
            ZStack {
                Group {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.well)
                            .aspectRatio(3 / 2, contentMode: .fit)
                            .overlay(Image(systemName: "photo").foregroundStyle(Theme.dim))
                    }
                }
                .frame(height: Theme.Metric.thumbHeight)
                .overlay(RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.selectionFrame, lineWidth: framing.lineWidth)
                    .opacity(framing.opacity))
            }
        }
    }
}
