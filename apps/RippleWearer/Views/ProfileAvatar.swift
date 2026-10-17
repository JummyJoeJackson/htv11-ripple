import PhotosUI
import RippleKit
import SwiftUI
import UIKit

/// The wearer's profile photo, kept only on this iPhone as a small JPEG in
/// Application Support. It is never sent to the server or to contacts.
enum AvatarStorage {
    private static var fileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("profile-avatar.jpg")
    }

    static func load() -> UIImage? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Shrinks the photo to a 400 pt square before saving, so it stays small.
    static func save(_ image: UIImage) {
        guard let url = fileURL else { return }
        let side: CGFloat = 400
        let scale = side / min(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let square = renderer.image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        try? square.jpegData(compressionQuality: 0.85)?.write(to: url, options: .atomic)
    }

    static func remove() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Bumped whenever the photo changes, so every avatar on screen reloads.
private let avatarVersionKey = "ripple.avatarVersion"

/// The profile photo in a circle, or a person icon when there isn't one.
struct ProfileAvatar: View {
    var size: CGFloat = 60
    @AppStorage(avatarVersionKey) private var version = 0

    var body: some View {
        let _ = version
        Group {
            if let image = AvatarStorage.load() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.iconTint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .accessibilityHidden(true)
    }
}

/// "Add photo" / "Change photo" from the photo library, plus "Remove photo".
struct AvatarPicker: View {
    var size: CGFloat = 88
    @AppStorage(avatarVersionKey) private var version = 0
    @State private var item: PhotosPickerItem?

    var body: some View {
        let _ = version
        let hasPhoto = AvatarStorage.load() != nil
        HStack(spacing: Theme.spacing) {
            ProfileAvatar(size: size)
            VStack(alignment: .leading, spacing: 4) {
                PhotosPicker(selection: $item, matching: .images) {
                    Label(hasPhoto ? "Change photo" : "Add a photo", systemImage: "photo")
                        .font(Theme.labelBold)
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityHint("Picks a profile photo from your library. It stays on this iPhone.")
                if hasPhoto {
                    Button("Remove photo", role: .destructive) {
                        AvatarStorage.remove()
                        version += 1
                    }
                    .font(Theme.label)
                    .frame(minHeight: 44, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    AvatarStorage.save(image)
                    version += 1
                }
                item = nil
            }
        }
    }
}

#Preview("Avatar picker") {
    AvatarPicker()
        .padding()
        .rippleScreen()
}
