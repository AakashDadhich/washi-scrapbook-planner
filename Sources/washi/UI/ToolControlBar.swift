import SwiftUI

/// Bottom-center contextual bar (spec §5.5). Placeholder sizing/position for
/// M5; per-tool/per-selection subviews (`UI/ToolControlBar/`) are wired in M10.
struct ToolControlBar: View {
    var body: some View {
        HStack {
            Spacer()
            Text("Tool Control Bar")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(height: 76)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
