extension DSL.Model.Style {

    struct Material: Decodable, StylePointerResolvable {
        typealias Entity = ConcreteEntity<Self>

        private(set) var layers: [`Any`]

        /// JSON value is a flat array of `any Style.Protocol`, e.g.
        /// `[ { "id":"a", "type":"fill", "content":{...} }, ... ]`.
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let allLayers = try container.decode([FailableDecodable<`Any`>].self).resolve()
            layers = allLayers.filter(\.isMaterial)
        }

        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            for i in 0 ..< layers.count {
                layers[i].resolveStylePointers(resolver: resolver)
            }
        }
        
        func isResolved() -> Bool {
            layers.allSatisfy { layer in
                layer.isResolved()
            }
        }

        func unresolvedPointerIds() -> [String] {
            layers.flatMap { $0.unresolvedPointerIds() }
        }
    }
}
