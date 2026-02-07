import SwiftUI

// MARK: - Financial Disclaimer View

struct FinancialDisclaimerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Important", systemImage: "info.circle")
                .font(.caption)
                .fontWeight(.semibold)

            Text("This is not financial advice. Consult a qualified financial professional for personalized guidance. Cost estimates are based on regional averages and your reported expenses.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Important disclaimer: This is not financial advice. Consult a qualified financial professional for personalized guidance. Cost estimates are based on regional averages and your reported expenses.")
    }
}

// MARK: - Preview

#Preview {
    FinancialDisclaimerView()
        .padding()
}
