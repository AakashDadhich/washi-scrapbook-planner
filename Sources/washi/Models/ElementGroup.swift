import Foundation

/// A persistent, named group (Cmd+G), distinct from an ad-hoc marquee
/// multi-selection — it survives selection changes and reopening the
/// project until explicitly ungrouped (spec §6.3).
struct ElementGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var elementIDs: [UUID]
}
