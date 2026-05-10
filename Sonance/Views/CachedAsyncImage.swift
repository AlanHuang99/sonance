import SwiftUI

/// AsyncImage that fades in when the image loads, instead of flashing in.
/// The placeholder is a soft quaternary fill with a music-note glyph so empties
/// don't blink.
struct SmoothCoverImage: View {
    let url: URL?
    var corner: CGFloat = 6
    var glyph: String = "music.note"

    var body: some View {
        ZStack {
            placeholder
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .transition(.opacity)
                    default:
                        Color.clear
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(.quaternary)
            .overlay(
                Image(systemName: glyph)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            )
    }
}
