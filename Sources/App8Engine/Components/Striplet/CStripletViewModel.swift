/*
///
protocol StripletViewModelProtocol {
    var prefixIcon: Icon.ViewModel? { get }
    var label: (any LabelViewModelProocol)? { get }
    var suffixIcon: Icon.ViewModel? { get }
    var forceNonAnimatedChange: Bool { get }
}

///
extension Striplet {
    
    ///
    struct ViewModel: StripletViewModelProtocol {
        private(set) var prefixIcon: Icon.ViewModel?
        private(set) var label: (any LabelViewModelProocol)?
        private(set) var suffixIcon: Icon.ViewModel?
        let forceNonAnimatedChange: Bool
        
        init(model: Model,
             forceNonAnimatedChange: Bool = false) {
            if let prefixIcon = model.prefixIcon {
                self.prefixIcon = Icon.ViewModel(model: prefixIcon)
            }
            if let text = model.text {
                self.label = Label.ViewModel(model: text)
            }
            if let suffixIcon = model.suffixIcon {
                self.suffixIcon = Icon.ViewModel(model: suffixIcon)
            }
            self.forceNonAnimatedChange = forceNonAnimatedChange
        }
        
        ///
        init(prefixIcon: Icon.ViewModel? = nil, text: (any LabelViewModelProocol), suffixIcon: Icon.ViewModel? = nil, forceNonAnimatedChange: Bool = false) {
            self.prefixIcon = prefixIcon
            self.label = text
            self.suffixIcon = suffixIcon
            self.forceNonAnimatedChange = forceNonAnimatedChange
        }
        
        ///
        static func text(_ text: String) -> Self {
            return .init(prefixIcon: nil, text: text, suffixIcon: nil, forceNonAnimatedChange: false)
        }
        
        ///
        static func text(_ text: String, forceNonAnimatedChange: Bool) -> Self {
            return .init(prefixIcon: nil, text: text, suffixIcon: nil, forceNonAnimatedChange: forceNonAnimatedChange)
        }
        
        ///
        static func symbol(_ symbol: SFSymbol, style: Icon.ViewModel.SymbolStyle?, forceNonAnimatedChange: Bool = false) -> Self {
            return .init(prefixIcon: nil, text: "", suffixIcon: .symbol(symbol, style: style), forceNonAnimatedChange: forceNonAnimatedChange)
        }
        
        ///
        var description: String {
            let components: [String?] = [
                prefixIcon?.description,
                label?.string,
                suffixIcon?.description
            ]
            return components.compactMap { $0 }.joined(separator: "_")
        }
        
        ///
        func hash(into hasher: inout Hasher) {
            hasher.combine("Striplet.ViewModel")
            if let prefixIcon {
                hasher.combine(prefixIcon)
            } else {
                hasher.combine("Striplet.noPrefixIcon")
            }
            if let label {
                hasher.combine(label.string)
                if let style = label.style {
                    hasher.combine(style)
                }
            }
            
            if let suffixIcon {
                hasher.combine(suffixIcon)
            } else {
                hasher.combine("Striplet.noSuffixIcon")
            }
        }
    }
}
*/
