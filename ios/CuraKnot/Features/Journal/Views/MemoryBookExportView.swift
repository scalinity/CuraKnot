import SwiftUI

// MARK: - Memory Book Export View

/// View for configuring and generating Memory Book PDF exports
struct MemoryBookExportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemoryBookViewModel

    init(circleId: String, journalService: JournalService) {
        _viewModel = StateObject(wrappedValue: MemoryBookViewModel(
            circleId: circleId,
            journalService: journalService
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .checkingAccess:
                    loadingView

                case .configuring:
                    configurationView

                case .generating:
                    generatingView

                case .ready(let url):
                    successView(url: url)

                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Memory Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.checkAccess()
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Checking access...")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Configuration View

    private var configurationView: some View {
        Form {
            Section("Date Range") {
                Picker("Range", selection: $viewModel.dateRangeOption) {
                    ForEach(MemoryBookViewModel.DateRangeOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)

                if viewModel.dateRangeOption == .custom {
                    DatePicker(
                        "From",
                        selection: $viewModel.customStartDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )

                    DatePicker(
                        "To",
                        selection: $viewModel.customEndDate,
                        in: viewModel.customStartDate...Date(),
                        displayedComponents: .date
                    )
                }

                Text(viewModel.formattedDateRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Include my private entries", isOn: $viewModel.includePrivateEntries)
            } footer: {
                Text("Only your own private entries will be included. Other members' private entries are never visible.")
            }

            Section {
                Button {
                    Task { await viewModel.generate() }
                } label: {
                    HStack {
                        Spacer()
                        Label("Generate Memory Book", systemImage: "book.fill")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!viewModel.isDateRangeValid)
            }
        }
    }

    // MARK: - Generating View

    private var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: 8) {
                Text("Creating your Memory Book")
                    .font(.headline)

                Text("This may take a moment...")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Success View

    private func successView(url: URL) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Memory Book Ready!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Your journal entries have been compiled into a beautiful PDF.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                ShareLink(item: url) {
                    Label("Share Memory Book", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    viewModel.reset()
                } label: {
                    Text("Create Another")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Button {
                viewModel.dismissError()
            } label: {
                Text("Try Again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}

// MARK: - Upgrade Prompt

/// Shown when user doesn't have Family tier access
struct MemoryBookUpgradePrompt: View {
    var onUpgrade: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "book.fill")
                .font(.system(size: 60))
                .foregroundStyle(.purple.gradient)

            VStack(spacing: 8) {
                Text("Memory Book")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Create beautiful PDF collections of your journal entries. Memory Book is available with a Family subscription.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button(action: onUpgrade) {
                    Text("Upgrade to Family")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: onDismiss) {
                    Text("Not Now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}

// Preview disabled - requires dependency injection
// To preview, use the app with DependencyContainer
