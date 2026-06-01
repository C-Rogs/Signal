import SwiftUI

enum Symbol: String, CaseIterable {
    case heartVariability = "heart.rate"
    case recovery = "bolt.heart"
    case sleep = "bed.double"
    case energy = "flame"
    case workout = "dumbbell"
    case coach = "brain.head.profile"

    var image: Image {
        Image(systemName: rawValue)
    }

    func hierarchicalImage(tint: Color = Color("Primary")) -> some View {
        image
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
    }
}
