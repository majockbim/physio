import SwiftUI

struct ExerciseSelectionView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var selected: Set<String> = []
    @State private var showFlow = false

    private var selectedExercises: [Exercise] {
        Exercise.catalog.filter { selected.contains($0.id) }
    }

    private var deviceConnected: Bool { ble.connectionState == .connected }

    var body: some View {
        Form {
            Section("Range of Motion") {
                ForEach(Exercise.romExercises) { exercise in
                    exerciseRow(exercise)
                }
            }

            Section {
                ForEach(Exercise.adlExercises) { exercise in
                    exerciseRow(exercise)
                }
            } header: {
                Text("Activities of Daily Living")
            } footer: {
                Text("Choose up to 3 exercises. You can mix categories.")
            }
        }
        .navigationTitle("Choose Exercises")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            beginButton
        }
        .navigationDestination(isPresented: $showFlow) {
            ExerciseFlowView(exercises: selectedExercises)
        }
    }

    private var beginButton: some View {
        let canBegin = !selected.isEmpty && deviceConnected
        let label: String = {
            if !deviceConnected { return "Connect a Device to Begin" }
            if selected.isEmpty { return "Begin Session" }
            return "Begin Session (\(selected.count))"
        }()
        return Button {
            showFlow = true
        } label: {
            Label(label, systemImage: deviceConnected ? "play.circle.fill" : "antenna.radiowaves.left.and.right.slash")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .background(canBegin ? Color.accentColor : Color.gray.opacity(0.3),
                            in: .rect(cornerRadius: 14))
                .foregroundStyle(canBegin ? Color.white : Color.secondary)
        }
        .disabled(!canBegin)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func exerciseRow(_ exercise: Exercise) -> some View {
        let isSelected = selected.contains(exercise.id)
        let atMax = selected.count >= 3 && !isSelected

        Button {
            if isSelected {
                selected.remove(exercise.id)
            } else if !atMax {
                selected.insert(exercise.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: exercise.systemImage)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.headline)
                        .foregroundStyle(atMax ? Color.secondary : Color.primary)
                    Text(exercise.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : (atMax ? Color.gray.opacity(0.35) : Color.secondary))
                    .font(.title3)
            }
        }
        .disabled(atMax)
    }
}

#Preview {
    NavigationStack {
        ExerciseSelectionView()
    }
}
