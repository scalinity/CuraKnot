import SwiftUI

// MARK: - Rating Stars

struct RatingStars: View {
    let rating: Int
    let maxRating: Int
    let size: CGFloat
    var onTap: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...maxRating, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(star <= rating ? .yellow : Color(.systemGray4))
                    .onTapGesture {
                        onTap?(star)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating) out of \(maxRating) stars")
        .accessibilityValue(onTap != nil ? "\(rating)" : "")
        .accessibilityAdjustableAction { direction in
            guard let onTap = onTap else { return }
            switch direction {
            case .increment:
                if rating < maxRating { onTap(rating + 1) }
            case .decrement:
                if rating > 1 { onTap(rating - 1) }
            @unknown default:
                break
            }
        }
    }
}
