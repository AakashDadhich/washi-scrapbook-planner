import SwiftUI

/// Visually groups a cluster of related controls (e.g. "Border", "Effects")
/// inside a labeled card, so panels read as organized sections rather than a
/// flat row of controls separated only by thin dividers (issue #27).
struct ControlGroupBox<Content: View>: View {
    var label: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.4)
            }
            HStack(spacing: 12) {
                content
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// A boolean control styled as an icon-above-label pill, replacing the old
/// small checkbox + text label toggles — highlights when on, matching the
/// reference app's spaced, deliberate button style (issue #27).
struct IconToggleButton: View {
    var icon: String
    var label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .fixedSize()
            }
            .frame(minWidth: 52, minHeight: 40)
            .padding(.horizontal, 6)
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

/// A non-toggling action button (e.g. "Reset Crop") styled to match
/// `IconToggleButton`'s icon-above-label pill so action and toggle controls
/// read as one consistent family within a group (issue #27).
struct IconActionButton: View {
    var icon: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .fixedSize()
            }
            .frame(minWidth: 52, minHeight: 40)
            .padding(.horizontal, 6)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
