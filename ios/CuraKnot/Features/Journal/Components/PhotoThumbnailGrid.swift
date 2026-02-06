import SwiftUI

// MARK: - Photo Thumbnail Grid

/// A grid displaying photo thumbnails for journal entries
struct PhotoThumbnailGrid: View {
    let photos: [UIImage]
    var onRemove: ((Int) -> Void)?
    var isEditing: Bool = false

    private let spacing: CGFloat = 8
    private let cornerRadius: CGFloat = 8

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: spacing
        ) {
            ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                PhotoThumbnail(
                    image: image,
                    isEditing: isEditing,
                    onRemove: onRemove != nil ? { onRemove?(index) } : nil
                )
            }
        }
    }
}

// MARK: - Photo Thumbnail

/// A single photo thumbnail with optional remove button
struct PhotoThumbnail: View {
    let image: UIImage
    var isEditing: Bool = false
    var onRemove: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if isEditing, let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .background(
                            SwiftUI.Circle()
                                .fill(Color.black.opacity(0.5))
                        )
                }
                .offset(x: 4, y: -4)
            }
        }
    }
}

// MARK: - Photo Add Button

/// A button to add photos to a journal entry
struct PhotoAddButton: View {
    let canAdd: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: canAdd ? "photo.badge.plus" : "lock.fill")
                    .font(.title2)

                Text(canAdd ? "Add Photo" : "Plus Feature")
                    .font(.caption)
            }
            .foregroundStyle(canAdd ? Color.accentColor : Color.secondary)
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        canAdd ? Color.accentColor : Color.secondary,
                        style: StrokeStyle(lineWidth: 2, dash: [6])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Photo Counter

/// Shows photo count with limit
struct PhotoCounter: View {
    let count: Int
    let limit: Int = 3

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "photo")
                .font(.caption)

            Text("\(count)/\(limit)")
                .font(.caption)
        }
        .foregroundStyle(count >= limit ? .orange : .secondary)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Grid with mock images
        PhotoThumbnailGrid(
            photos: [
                UIImage(systemName: "photo")!,
                UIImage(systemName: "photo.fill")!
            ],
            onRemove: { index in
                print("Remove photo at \(index)")
            },
            isEditing: true
        )

        // Add button
        HStack {
            PhotoAddButton(canAdd: true) {
                print("Add photo")
            }
            .frame(width: 100, height: 100)

            PhotoAddButton(canAdd: false) {
                print("Upgrade")
            }
            .frame(width: 100, height: 100)
        }

        // Counter
        HStack {
            PhotoCounter(count: 1)
            PhotoCounter(count: 3)
        }
    }
    .padding()
}
