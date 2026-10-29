//  ImportPicker.swift — getting photographs into the session on iOS.
//
//  Two doors, matching the Mac's `Library.chooseFilesOrFolder`:
//
//    * the document picker (`fileImporter`) for files the app can reach —
//      including RAW files handed over by other apps through Open in Place;
//    * `PHPickerViewController` for the photo library, which copies the picked
//      images (originals, not derivatives) into the app's own Imports folder,
//      because the engine needs a file URL it can reopen later.
//
//  Both land in `Session.dropped(files:)`, which is the one door for files
//  from outside (`Library.frames(from:)` expands folders there) — the same
//  call the Mac's drop handler makes.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImportMenu: ViewModifier {
    @Bindable var session: Session
    @Binding var showFileImporter: Bool
    @Binding var showPhotoPicker: Bool

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: ImportMenu.importTypes,
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                // Open in Place hands out a security-scoped URL; the engine
                // reopens the file later, so access is taken now and held for
                // the session's lifetime (`hold`, bounded).
                for u in urls { _ = ImportMenu.hold(u) }
                if !urls.isEmpty { session.dropped(files: urls) }
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoLibraryPicker { urls in
                    guard !urls.isEmpty else { return }
                    session.dropped(files: urls)
                }
            }
    }

    static let importTypes: [UTType] = {
        var t: [UTType] = [.image, .tiff, .png, .jpeg, .heic]
        if let raw = UTType("public.camera-raw-image") { t.append(raw) }
        return t
    }()

    /// Security-scoped URLs kept open for the session's lifetime. There are
    /// normally a handful; a runaway list would be an app-level leak either
    /// way, so it is bounded and older scopes are released past the cap.
    static var heldScopes: [URL] = []
    static let scopeCap = 32

    static func hold(_ url: URL) -> Bool {
        if heldScopes.count >= scopeCap {
            heldScopes.removeFirst().stopAccessingSecurityScopedResource()
        }
        guard url.startAccessingSecurityScopedResource() else { return false }
        heldScopes.append(url)
        return true
    }
}

/// The photo-library door. Items arrive as data (PHPicker gives no file URL
/// and no scope); originals are written into `Documents/Imports/` and those
/// URLs go on to the session.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var onPicked: ([URL]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([URL]) -> Void
        init(onPicked: @escaping ([URL]) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let providers = results.map(\.itemProvider)
            guard !providers.isEmpty else { onPicked([]); return }

            Task { @MainActor in
                let urls = await Self.materialise(providers)
                onPicked(urls)
            }
        }

        /// Copy each provider's original data to a file in Imports/. The
        /// identifier (when the library offers one) is the filename stem, so
        /// reopening the same photograph lands beside its earlier copy and
        /// the sidecar survives the round trip.
        private static func materialise(_ providers: [NSItemProvider]) async -> [URL] {
            let dir = importsDirectory()
            var urls: [URL] = []
            for (i, provider) in providers.enumerated() {
                if let url = await copy(provider, index: i, directory: dir) {
                    urls.append(url)
                }
            }
            return urls
        }

        private static func copy(_ provider: NSItemProvider, index: Int,
                                 directory: URL) async -> URL? {
            for type in [UTType.heic, UTType.jpeg, UTType.png, UTType.tiff, UTType.image] {
                if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                    let data: Data? = await withCheckedContinuation { cont in
                        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { d, _ in
                            cont.resume(returning: d)
                        }
                    }
                    guard let data else { continue }
                    let stem = provider.suggestedName.map {
                        $0.replacingOccurrences(of: "/", with: "_")
                    } ?? "IMG_\(String(format: "%04d", index + 1))"
                    let url = directory.appending(path: stem)
                        .appendingPathExtension(type.preferredFilenameExtension ?? "img")
                    do {
                        try data.write(to: url, options: Data.WritingOptions.atomic)
                        return url
                    } catch { continue }
                }
            }
            return nil
        }
    }
}

@MainActor
func importsDirectory() -> URL {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appending(path: "Imports", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
