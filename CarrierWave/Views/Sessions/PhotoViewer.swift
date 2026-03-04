import CarrierWaveData
import SwiftUI

/// Full-screen photo viewer with pinch-to-zoom and close button.
struct PhotoViewer: View {
    // MARK: Internal

    let url: URL

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = min(max(value.magnification, 1.0), 4.0)
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.3)) {
                                    if scale < 1.2 {
                                        scale = 1.0
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3)) {
                            scale = scale > 1.0 ? 1.0 : 2.0
                        }
                    }
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.3))
            }
            .accessibilityLabel("Close")
            .padding()
        }
        .statusBarHidden()
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
}
