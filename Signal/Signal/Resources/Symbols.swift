import SwiftUI

enum Symbol: String, CaseIterable {
    case heartVariability = "waveform.path.ecg"
    case recovery = "bolt.heart"
    case sleep = "bed.double"
    case energy = "flame"
    case workout = "dumbbell"
    case coach = "brain.head.profile"
    case bodyMass = "scalemass"
    case steps = "figure.walk"
    case nutrition = "fork.knife"

    var image: Image {
        Image(systemName: rawValue)
    }

    func hierarchicalImage(tint: Color = Color("Primary")) -> some View {
        image
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
    }
}
