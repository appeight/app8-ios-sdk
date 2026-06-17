extension DSL.Model.Style {

    struct VisualEffect: Decodable {
        typealias Entity = ConcreteEntity<Self>

        let blur: BackgroundBlur?
        let glass: Glass?
        /// When `true` on an iOS 26 glass effect, the owning view's content is
        /// hosted *inside* the glass (`UIVisualEffectView.contentView`) so it
        /// refracts/morphs with the glass, and the glass is made interactive.
        /// Defaults to `false` — glass stays a background layer with content
        /// layered above it (unchanged behaviour). No effect on blur effects or
        /// below iOS 26.
        let container: Bool?
    }
}
