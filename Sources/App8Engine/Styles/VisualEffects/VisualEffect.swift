extension DSL.Model.Style {

    struct VisualEffect: Decodable {
        typealias Entity = ConcreteEntity<Self>

        let blur: BackgroundBlur?
        let glass: Glass?
    }
}
