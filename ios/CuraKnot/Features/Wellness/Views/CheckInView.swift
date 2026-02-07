import SwiftUI

// MARK: - Check-In View

/// Weekly wellness check-in flow designed for < 30 second completion
struct CheckInView: View {
    @StateObject private var viewModel: CheckInViewModel
    @Environment(\.dismiss) private var dismiss

    init(wellnessService: WellnessService, onComplete: @escaping (WellnessCheckIn) -> Void) {
        _viewModel = StateObject(wrappedValue: CheckInViewModel(
            wellnessService: wellnessService,
            onComplete: onComplete
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                ProgressView(value: viewModel.progress)
                    .tint(.blue)
                    .padding(.horizontal)

                // Step content
                TabView(selection: Binding(
                    get: { viewModel.currentStep },
                    set: { viewModel.jumpToStep($0) }
                )) {
                    stressStep
                        .tag(CheckInViewModel.CheckInStep.stress)

                    sleepStep
                        .tag(CheckInViewModel.CheckInStep.sleep)

                    capacityStep
                        .tag(CheckInViewModel.CheckInStep.capacity)

                    notesStep
                        .tag(CheckInViewModel.CheckInStep.notes)

                    reviewStep
                        .tag(CheckInViewModel.CheckInStep.review)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: viewModel.currentStep)

                // Navigation buttons
                HStack {
                    if viewModel.canGoBack {
                        Button("Back") {
                            viewModel.goBack()
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if viewModel.isOnReviewStep {
                        Button {
                            Task {
                                await viewModel.submit()
                            }
                        } label: {
                            if viewModel.isSubmitting {
                                ProgressView()
                            } else {
                                Text("Submit")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isSubmitting)
                    } else if viewModel.canGoNext {
                        Button("Next") {
                            viewModel.goNext()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle(viewModel.currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip Week") {
                        Task {
                            await viewModel.skip()
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Stress Step

    private var stressStep: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(viewModel.stressEmoji)
                .font(.system(size: 80))

            Text(viewModel.stressDescription)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                HStack {
                    Text("Low")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("High")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Stress Level", selection: $viewModel.stressLevel) {
                    ForEach(1...5, id: \.self) { level in
                        Text("\(level)").tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    // MARK: - Sleep Step

    private var sleepStep: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(viewModel.sleepEmoji)
                .font(.system(size: 80))

            Text(viewModel.sleepDescription)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                HStack {
                    Text("Poor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Excellent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Sleep Quality", selection: $viewModel.sleepQuality) {
                    ForEach(1...5, id: \.self) { level in
                        Text("\(level)").tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    // MARK: - Capacity Step

    private var capacityStep: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(viewModel.capacityEmoji)
                .font(.system(size: 80))

            Text(viewModel.capacityDescription)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                HStack {
                    Text("Empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Full")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Capacity Level", selection: $viewModel.capacityLevel) {
                    ForEach(1...4, id: \.self) { level in
                        Text("\(level)").tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    // MARK: - Notes Step

    private var notesStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.title)
                .foregroundStyle(.secondary)

            Text("Add private notes about your week")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.notes)
                .frame(height: 150)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Your notes are encrypted and only visible to you")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Review Step

    private var reviewStep: some View {
        VStack(spacing: 24) {
            Text("Review your check-in")
                .font(.headline)

            VStack(spacing: 16) {
                ReviewRow(
                    title: "Stress",
                    emoji: viewModel.stressEmoji,
                    value: "\(viewModel.stressLevel)/5",
                    description: viewModel.stressDescription
                )

                Divider()

                ReviewRow(
                    title: "Sleep",
                    emoji: viewModel.sleepEmoji,
                    value: "\(viewModel.sleepQuality)/5",
                    description: viewModel.sleepDescription
                )

                Divider()

                ReviewRow(
                    title: "Capacity",
                    emoji: viewModel.capacityEmoji,
                    value: "\(viewModel.capacityLevel)/4",
                    description: viewModel.capacityDescription
                )

                if !viewModel.notes.isEmpty {
                    Divider()

                    HStack(alignment: .top) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                        Text("Notes added")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
    }
}

// MARK: - Review Row

private struct ReviewRow: View {
    let title: String
    let emoji: String
    let value: String
    let description: String

    var body: some View {
        HStack {
            Text(emoji)
                .font(.title2)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(description)
                    .font(.headline)
            }

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
