import Foundation

struct Album: Codable, Equatable {
    var pages: [Page]                        // ordered; see spec §3.2 for page roles
    var defaultPageSize: PageSize
}
