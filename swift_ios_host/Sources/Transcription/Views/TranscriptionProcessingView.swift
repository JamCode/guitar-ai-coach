import SwiftUI
import Core

struct TranscriptionProcessingView: View {
    let fileName: String
    let progressState: TranscriptionProgressState
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            if progressState.isFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.orange)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            Text(fileName)
                .font(.headline)
                .foregroundStyle(SwiftAppTheme.text)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ProgressView(value: progressState.clampedProgress)
                    .progressViewStyle(.linear)
                HStack {
                    Text(progressState.message)
                        .font(.subheadline)
                        .foregroundStyle(progressState.isFailed ? .orange : SwiftAppTheme.muted)
                    Spacer()
                    Text("\(progressState.percentage)%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                }
            }
            if progressState.isFailed {
                Button("重试", action: onRetry)
                    .appPrimaryButton()
            }
            Button(LocalizedStringResource("transcribe_button_cancel", bundle: .main), action: onCancel)
                .appSecondaryButton()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(LocalizedStringResource("transcribe_processing_title", bundle: .main))
        .appPageBackground()
    }
}
