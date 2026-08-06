import SwiftUI

enum OverlayState {
    case recording
    case transcribing
}

struct DictationOverlayView: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject private var loc = LocalizationManager.shared
    var state: OverlayState

    var body: some View {
        HStack(spacing: 12) {
            if state == .recording {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 24, height: 24)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                }

                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { index in
                        let factor = Float(index + 1) / 4.0
                        let height = CGFloat(max(4, min(18, Double(recorder.audioLevel) * 20.0 * Double(factor))))
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.red)
                            .frame(width: 3, height: height)
                            .animation(.easeOut(duration: 0.08), value: recorder.audioLevel)
                    }
                }
                .frame(width: 20, height: 18)

                Text(loc.string("menu_recording"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            } else {
                ProgressView()
                    .controlSize(.small)

                Text(loc.string("menu_transcribing"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
    }
}
