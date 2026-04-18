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
            Text(stepText)
                .font(.subheadline)
                .foregroundStyle(SwiftAppTheme.muted)
            Button("取消", action: onCancel)
                .appSecondaryButton()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("正在识别")
        .appPageBackground()
    }
}
