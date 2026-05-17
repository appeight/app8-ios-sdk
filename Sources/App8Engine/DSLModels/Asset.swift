extension DSL.Model {

    struct Asset: Decodable, CustomDebugStringConvertible {
        let id: String?
        let name: String?
        let url: String?

        var debugDescription: String {
            "Asset id: \(id ?? "none"), name: \(name ?? "none"), url: \(url ?? "none")"
        }
    }
}
