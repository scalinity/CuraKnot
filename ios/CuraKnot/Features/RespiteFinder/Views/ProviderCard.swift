import SwiftUI

// MARK: - Provider Card

struct ProviderCard: View {
    let provider: RespiteProvider
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(provider.name)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if let icon = provider.verificationStatus.icon {
                                Image(systemName: icon)
                                    .font(.caption)
                                    .foregroundStyle(provider.verificationStatus == .featured ? .yellow : .blue)
                            }
                        }

                        HStack(spacing: 4) {
                            Image(systemName: provider.providerType.icon)
                                .font(.caption2)
                            Text(provider.providerType.displayName)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let distance = provider.formattedDistance {
                        Text(distance)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                    }
                }

                // Rating & Price
                HStack(spacing: 12) {
                    if provider.reviewCount > 0 {
                        HStack(spacing: 4) {
                            RatingStars(rating: Int(provider.avgRating.rounded()), maxRating: 5, size: 12)
                            Text("(\(provider.reviewCount))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let price = provider.formattedPriceRange {
                        Text(price)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                // Financial assistance badges
                if provider.hasFinancialAssistance {
                    HStack(spacing: 6) {
                        if provider.acceptsMedicaid {
                            assistanceBadge(String(localized: "Medicaid"))
                        }
                        if provider.acceptsMedicare {
                            assistanceBadge(String(localized: "Medicare"))
                        }
                        if provider.scholarshipsAvailable {
                            assistanceBadge(String(localized: "Scholarships"))
                        }
                    }
                }

                // Services (first 3)
                if !provider.services.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(provider.services.prefix(3), id: \.self) { svc in
                            Text(svc)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        if provider.services.count > 3 {
                            Text("+\(provider.services.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Address
                if let city = provider.city, let state = provider.state {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.caption2)
                        Text("\(city), \(state)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provider.name), \(provider.providerType.displayName)")
        .accessibilityHint(String(localized: "Tap to view details"))
    }

    private func assistanceBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.1))
            .foregroundStyle(.green)
            .clipShape(Capsule())
    }
}
