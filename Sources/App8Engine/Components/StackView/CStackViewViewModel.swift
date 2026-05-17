//
//  CStackViewViewModel.swift
//  App8Engine
//

import UIKit
import Combine

class CStackViewViewModel: CBaseViewModel<DSL.Model.Component.StackView.C> {

    var resolvedBackgroundColor: AnyPublisher<UIColor?, Never> {
        propertiesWithVariables
            .map { [weak self] props -> UIColor? in
                guard let self = self,
                      let colorExpr = props.backgroundColor else { return nil }
                let resolved = self.resolvePropertyToString(colorExpr)
                return UIColor(withHexString: resolved)
            }
            .eraseToAnyPublisher()
    }

    var cornerRadius: CGFloat? {
        currentProperties.cornerRadius
    }

    var stackAxis: NSLayoutConstraint.Axis {
        switch currentProperties.axis {
        case "horizontal": return .horizontal
        default: return .vertical
        }
    }

    var stackAlignment: UIStackView.Alignment {
        switch currentProperties.alignment {
        case "center": return .center
        case "top": return .top
        case "bottom": return .bottom
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .fill
        }
    }

    var stackDistribution: UIStackView.Distribution {
        switch currentProperties.distribution {
        case "fillEqually": return .fillEqually
        case "fillProportionally": return .fillProportionally
        case "equalSpacing": return .equalSpacing
        case "equalCentering": return .equalCentering
        default: return .fill
        }
    }
}
