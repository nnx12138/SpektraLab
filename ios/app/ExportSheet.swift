//  ExportSheet.swift — the export door, iOS.
//
//  The Mac's export page (three cards, a soft proof, batch) stays a desktop
//  composition; this sheet exports the open frame with a picked recipe, then
//  hands the written file to the photo library (or the share sheet). The
//  writer is the same `Exporter.export` the Mac uses — the file, its colour
//  tag and the job log beside it are identical — and the recipe's own
//  destination policy runs untouched inside the app's Documents, because on
//  iOS every imported photograph already lives there.

import SwiftUI
import Photos

struct ExportSheet: View {
    @Bindable var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var recipeIndex = 0
    @State private var running = false
    @State private var result: String?
    @State private var writtenURLs: [URL] = []
    @State private var savedToLibrary = false
    @State private var showShare = false

    private var recipes: [ExportRecipe] { ExportRecipe.defaults }
    private var recipe: ExportRecipe { recipes[min(recipeIndex, recipes.count - 1)] }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Recipe", zh: "配方")) {
                    Picker(L("Recipe", zh: "配方"), selection: $recipeIndex) {
                        ForEach(Array(recipes.enumerated()), id: \.offset) { i, r in
                            Text("\(r.name) · \(r.format.ext.uppercased())").tag(i)
                        }
                    }
                }

                Section(L("Destination", zh: "去向")) {
                    Label(L("Exported files are saved to the Photo Library.",
                            zh: "导出结果会存入照片图库。"),
                          systemImage: "photo.badge.arrow.down")
                        .font(Theme.Font.value)
                        .foregroundStyle(Theme.secondaryText)
                    if savedToLibrary, let first = writtenURLs.first {
                        ShareLink(item: first) {
                            Label(L("Share or Save File", zh: "分享或存文件"), systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if running {
                    Section { HStack { ProgressView(); Text(L("Exporting…", zh: "正在导出…")) } }
                }
                if let result {
                    Section { Text(result).font(Theme.Font.value).foregroundStyle(Theme.secondaryText) }
                }

                Section {
                    Button(L("Export", zh: "导出")) { Task { await run() } }
                        .disabled(running || session.selection == nil)
                }
            }
            .navigationTitle(L("Export", zh: "导出"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Done", zh: "完成")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func run() async {
        guard let sel = session.selection else { return }
        running = true; result = nil; savedToLibrary = false; writtenURLs = []
        defer { running = false }

        var r = recipe
        // The recipe's destination policy runs, but pinned inside the app's
        // own Documents (an export must land where this process can read it
        // back for the library write).
        r.folder = .fixed(path: importsDirectory().appending(path: "_prints").path)

        let context = NamingRule.Context(
            originalName: sel.deletingPathExtension().lastPathComponent,
            filmStock: session.params.filmStock,
            printStock: session.params.printStock,
            pixelSize: session.printPixelSize,
            counter: 1, date: Date())

        do {
            let outcome = try await Exporter.export(
                session: session, recipe: r, context: context,
                sessionID: session.serviceSessionIDForExport ?? "")
            switch outcome {
            case .wrote(let urls, let note, _):
                writtenURLs = urls
                result = (note.map { $0 + "\n" } ?? "")
                    + urls.map(\.lastPathComponent).joined(separator: "\n")
                if let first = urls.first {
                    savedToLibrary = await saveToLibrary(first)
                }
            case .skipped(let url):
                writtenURLs = [url]
                result = L("Already exported — file kept.", zh: "已导出过——保留了原文件。")
                savedToLibrary = await saveToLibrary(url)
            }
        } catch {
            result = error.localizedDescription
        }
    }

    /// The written file becomes a library asset, additions-only: the
    /// permission is `NSPhotoLibraryAddUsageDescription`, not the full
    /// library grant.
    private func saveToLibrary(_ url: URL) async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        var authorized = (status == .authorized || status == .limited)
        if status == .notDetermined {
            authorized = await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
                    cont.resume(returning: s == .authorized || s == .limited)
                }
            }
        }
        guard authorized else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            }
            return true
        } catch {
            return false
        }
    }
}
