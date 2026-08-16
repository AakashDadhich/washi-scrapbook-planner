import Foundation
import CoreGraphics

enum PageRole: Codable, Equatable {
    case cover
    case singlePage                          // e.g. the first page, not part of a spread
    case spreadLeft(spreadID: UUID)
    case spreadRight(spreadID: UUID)
}

struct Page: Codable, Identifiable, Equatable {
    var id: UUID
    var role: PageRole
    var size: PageSize
    var background: PageBackground
    var elements: [PageElement]
    var groups: [ElementGroup]               // persistent named groups, see spec §6.3
    var pageNumber: Int?                     // nil for cover; auto-assigned, user-editable

    var boundsCm: CGRect {
        CGRect(x: 0, y: 0, width: size.widthCm, height: size.heightCm)
    }

    func isElementFullyOffPage(_ element: PageElement) -> Bool {
        !boundsCm.intersects(element.transform.unrotatedRect)
    }
}
