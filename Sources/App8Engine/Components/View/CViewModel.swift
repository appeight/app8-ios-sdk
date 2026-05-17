import UIKit
import Combine

class CViewModel: CBaseViewModel<DSL.Model.Component.View.C> {

    /// Background color resolved from properties; supports expressions.
    var resolvedBackgroundColor: AnyPublisher<UIColor?, Never> {
        propertiesWithVariables
            .map { [weak self] props -> UIColor? in
                guard let self = self,
                      let colorExpr = props.backgroundColor?.value else { return nil }
                let resolved = self.resolvePropertyToString(colorExpr)
                return UIColor(withHexString: resolved)
            }
            .eraseToAnyPublisher()
    }

    var cornerRadius: CGFloat? {
        currentProperties.cornerRadius
    }
}
