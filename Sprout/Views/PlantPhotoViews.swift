import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PlantThumbnail: View {
    let photoData: Data?
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 0) {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                PlantSymbol()
            }
        }
        .accessibilityHidden(true)
        .task(id: photoData) {
            image = nil
            guard let photoData else { return }
            let pixels = Int(48 * displayScale)
            let preview = await Task.detached(priority: .userInitiated) {
                PlantPhotoProcessor.preview(from: photoData, maximumDimension: pixels)
            }.value
            guard !Task.isCancelled else { return }
            image = preview
        }
    }
}

struct PlantPhotoView: View {
    let data: Data
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                PlantSymbol()
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .task(id: data) {
            image = nil
            let preview = await Task.detached(priority: .userInitiated) {
                PlantPhotoProcessor.preview(from: data, maximumDimension: PlantPhotoProcessor.maximumDimension)
            }.value
            guard !Task.isCancelled else { return }
            image = preview
        }
    }
}

struct PlantPhotoEditor: View {
    @ObservedObject var draft: PlantPhotoDraft
    var dismissKeyboard: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingLibrary = false
    @State private var showingCamera = false
    @State private var requestingCamera = false
    @State private var permissionTask: Task<Void, Never>?

    var body: some View {
        Section("Photo") {
            if let data = draft.photoData {
                PlantPhotoView(data: data)
                    .accessibilityLabel("Photo de la plante")
                    .accessibilityIdentifier("editor.photo.preview")
            }
            if draft.isLoading {
                ProgressView("Chargement de la photo…")
                    .accessibilityIdentifier("editor.photo.loading")
            }
            libraryButton
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Prendre une photo", systemImage: "camera", action: requestCamera)
                    .accessibilityIdentifier("editor.photo.camera")
            }
            if draft.photoData != nil {
                Button("Supprimer la photo", role: .destructive, action: draft.remove)
                    .accessibilityIdentifier("editor.photo.remove")
            }
        }
        .disabled(requestingCamera)
    }

    // Present from a concrete row; Form flattens Section and can discard its presentation modifiers.
    private var libraryButton: some View {
        Button("Choisir une photo", systemImage: "photo.on.rectangle") {
            dismissKeyboard()
            draft.cancelLoading()
            selectedPhoto = nil
            showingLibrary = true
        }
        .accessibilityIdentifier("editor.photo.choose")
        .photosPicker(isPresented: $showingLibrary, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            draft.load {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw PlantPhotoProcessor.ProcessingError.invalidImage
                }
                return try await Task.detached(priority: .userInitiated) {
                    try PlantPhotoProcessor.jpegData(from: data)
                }.value
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            PlantCameraPicker { image in
                showingCamera = false
                guard let image else { return }
                draft.load {
                    try await Task.detached(priority: .userInitiated) {
                        try PlantPhotoProcessor.jpegData(from: image)
                    }.value
                }
            }
            .ignoresSafeArea()
        }
        .alert("Photo indisponible", isPresented: Binding(
            get: { draft.alert != nil }, set: { if !$0 { draft.alert = nil } }
        ), presenting: draft.alert) { alert in
            if alert == .cameraDenied {
                Button("Ouvrir les réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Annuler", role: .cancel) { }
            } else {
                Button("OK", role: .cancel) { }
            }
        } message: { alert in
            switch alert {
            case .importFailed:
                Text("Impossible de charger cette photo. La photo précédente est conservée ; réessayez ou choisissez une autre image.")
            case .cameraDenied:
                Text("Autorisez Sprout à utiliser l’appareil photo dans les réglages pour photographier votre plante.")
            case .cameraUnavailable:
                Text("L’appareil photo est indisponible. Choisissez une image dans votre photothèque.")
            }
        }
        .onDisappear {
            permissionTask?.cancel()
            requestingCamera = false
        }
    }

    private func requestCamera() {
        dismissKeyboard()
        draft.cancelLoading()
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            draft.alert = .cameraUnavailable
            return
        }
        requestingCamera = true
        permissionTask = Task { @MainActor in
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard !Task.isCancelled else { return }
            requestingCamera = false
            if allowed { showingCamera = true }
            else { draft.alert = .cameraDenied }
        }
    }
}

private struct PlantCameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
    }
}
