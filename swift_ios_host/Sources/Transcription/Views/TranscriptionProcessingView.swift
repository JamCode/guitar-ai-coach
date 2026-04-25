import SwiftUI
import Core

struct TranscriptionProcessingView: View {
    let fileName: String
    let stepText: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(fileName)
                .font(.headline)
                .foregroundStyle(SwiftAppTheme.text)
                .multilineTextAlignment(.center)
            Text(AppL10n.t(stepText))
                .font(.subheadline)
                .foregroundStyle(SwiftAppTheme.muted)
            Button(LocalizedStringResource("transcribe_button_cancel", bundle: .main), action: onCancel)
                .appSecondaryButton()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(LocalizedStringResource("transcribe_processing_title", bundle: .main))
        .appPageBackground()
    }
}
