import SwiftData
import Foundation

@Model
final class SessionRecord {
    var id: UUID
    var date: Date
    var compositeScore: Int
    @Relationship(deleteRule: .cascade) var exerciseResults: [ExerciseResult]

    init(date: Date, compositeScore: Int, exerciseResults: [ExerciseResult]) {
        self.id = UUID()
        self.date = date
        self.compositeScore = compositeScore
        self.exerciseResults = exerciseResults
    }
}

@Model
final class ExerciseResult {
    var exerciseId: String
    var exerciseName: String
    var systemImage: String
    var repScores: [Int]
    var averageScore: Int

    init(exerciseId: String, exerciseName: String, systemImage: String, repScores: [Int]) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.systemImage = systemImage
        self.repScores = repScores
        self.averageScore = repScores.isEmpty ? 0 : repScores.reduce(0, +) / repScores.count
    }
}
