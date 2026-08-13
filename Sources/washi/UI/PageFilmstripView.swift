import SwiftUI

/// Page navigation strip below the canvas (spec §5.4). Placeholder thumbnails
/// for M5 — real per-unit (cover/single/spread) rendering, drag-to-reorder,
/// and merge/split land in M6.
struct PageFilmstripView: View {
    var unitCount: Int
    var currentIndex: Int
    var onSelect: (Int) -> Void
    var onPrev: () -> Void
    var onNext: () -> Void
    var onAddPage: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
            }
            .disabled(currentIndex <= 0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<unitCount, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.25))
                            .frame(width: 56, height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(i == currentIndex ? Color.accentColor : .clear, lineWidth: 2)
                            )
                            .onTapGesture { onSelect(i) }
                    }
                    Button(action: onAddPage) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .frame(width: 40, height: 56)
                }
                .padding(.horizontal, 4)
            }

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .disabled(currentIndex >= unitCount - 1)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 80)
        .background(.bar)
    }
}
