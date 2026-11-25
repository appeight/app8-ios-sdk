import UIKit

extension DSL.Model.Style {

    struct Picker: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        @Alpha var alpha: CGFloat?
        let transform: View.Transform?

        /// Text style for menu mode button label
        @Wrapped var text: TextModel?

        /// Tint color for the selected segment (segmented mode)
        let selectedSegmentTintColor: String?

        /// Menu mode: the pull-down button's title style. Opts into the plain
        /// pull-down look (title + indicator symbol, no background).
        @Wrapped var label: TextModel?
        /// Menu mode: SF Symbol after the title. Default `chevron.up.chevron.down`; `""` hides it.
        let indicator: String?
        /// Indicator tint. Default: the `label` color.
        @Wrapped var indicatorColor: Color.Themed?
        /// Indicator point size. Default: 0.8 × the `label` font size.
        let indicatorSize: CGFloat?
        /// Gap between title and indicator. Default 6.
        let indicatorSpacing: CGFloat?

        /// Whether the plain pull-down look applies.
        var usesPullDownLook: Bool { label != nil || indicator != nil }

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
            _text.resolvePointer(type: .key(.text), resolver: resolver)
            _label.resolvePointer(type: .key(.text), resolver: resolver)
            _indicatorColor.resolvePointer(type: .key(.color), resolver: resolver)
        }

        func isResolved() -> Bool {
            (material?.isResolved() ?? true) && (text?.isResolved() ?? true) && (label?.isResolved() ?? true)
        }
    }
}

extension DSL.Model.Style.Picker: DSL.Model.Style.AlphaExpressionHolder {
    var alphaSlot: DSL.Model.Style.Alpha {
        get { _alpha }
        set { _alpha = newValue }
    }
}
