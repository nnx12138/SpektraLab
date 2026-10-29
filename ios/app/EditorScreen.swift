//  EditorScreen.swift — the editor, in the v4 layout, adapted to iOS.
//
//  iPad keeps the Mac's three-region composition — Film and Print on the
//  left, canvas and filmstrip in the middle, Parameters on the right —
//  reusing `LeftPanel` and `RightPanel` verbatim. iPhone stacks it: the
//  canvas takes the screen, and the two rails arrive as sheets, one per
//  region. The canvas ZStack is the macOS `CanvasArea`'s, with the same four
//  overlays in the same z-order.

import SwiftUI

struct EditorScreen: View {
    @Bindable var session: Session
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var showLeftSheet = false
    @State private var showRightSheet = false
    @State private var showExportSheet = false

    var body: some View {
        Group {
            if hSize == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .background(Theme.ground)
        .modifier(ImportMenu(session: session,
                             showFileImporter: $showFileImporter,
                             showPhotoPicker: $showPhotoPicker))
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(session: session)
        }
        .sheet(isPresented: $showLeftSheet) { leftSheet }
        .sheet(isPresented: $showRightSheet) { rightSheet }
    }

    // MARK: iPad — the Mac's printLayout, fixed rail widths

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            LeftPanel(session: session)
                .frame(width: Theme.Metric.leftPanelRange.standard)
                .overlay(alignment: .trailing) { VerticalHairline().allowsHitTesting(false) }
            VStack(spacing: 0) {
                canvas
                Hairline(tier: .region)
                FilmstripBar(session: session)
                    .frame(height: Theme.Metric.filmstripHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            RightPanel(session: session)
                .frame(width: Theme.Metric.rightPanelRange.standard)
                .environment(\.colorBalanceWidth,
                             ColorBalanceLayout.interior(panelWidth: Theme.Metric.rightPanelRange.standard))
                .overlay(alignment: .leading) { VerticalHairline().allowsHitTesting(false) }
        }
        .safeAreaInset(edge: .top) { toolbar }
    }

    // MARK: iPhone — canvas full-bleed, the rails as sheets

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            canvas
            Hairline(tier: .region)
            FilmstripBar(session: session)
                .frame(height: Theme.Metric.filmstripHeight)
        }
        .safeAreaInset(edge: .top) { toolbar }
    }

    private var leftSheet: some View {
        NavigationStack {
            ScrollView {
                LeftPanel(session: session)
            }
            .navigationTitle(L("Film and Print", zh: "胶片与相纸"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    private var rightSheet: some View {
        NavigationStack {
            ScrollView {
                RightPanel(session: session)
                    .environment(\.colorBalanceWidth,
                                 ColorBalanceLayout.interior(panelWidth: Theme.Metric.rightPanelRange.standard))
            }
            .navigationTitle(L("Parameters", zh: "参数"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    // MARK: the canvas — CanvasArea's ZStack, same overlays, same z-order

    private var canvas: some View {
        ZStack {
            MetalCanvasView(host: session)
            // Handles, thirds grid and the straighten line. The shader does
            // the dimming; this does the lines. On-canvas crop-handle
            // dragging is macOS-only for now (see `CanvasUIView`); the crop
            // section's controls edit the same `Geometry`.
            if session.tool == .crop {
                CropOverlay(session: session)
            } else if FeatureFlags.masks, session.selectedMask != nil {
                MaskOverlay(session: session)
            }
            CompareOverlay(session: session)
            if session.pair != nil { PairOverlay(session: session) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            Menu {
                Button { showPhotoPicker = true } label: {
                    Label(L("Photo Library", zh: "照片图库"), systemImage: "photo.on.rectangle")
                }
                Button { showFileImporter = true } label: {
                    Label(L("Files…", zh: "文件…"), systemImage: "folder")
                }
            } label: {
                Label(L("Import", zh: "导入"), systemImage: "plus")
            }

            Spacer()

            if hSize == .compact {
                Button { showLeftSheet = true } label: {
                    Label(L("Film and Print", zh: "胶片与相纸"), systemImage: "camera.filters")
                }
                Button { showRightSheet = true } label: {
                    Label(L("Parameters", zh: "参数"), systemImage: "slider.horizontal.3")
                }
            }

            Button { showExportSheet = true } label: {
                Label(L("Export", zh: "导出"), systemImage: "square.and.arrow.up")
            }
            .disabled(session.selection == nil)
        }
        .font(Theme.Font.value)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Hairline(tier: .region) }
    }
}
