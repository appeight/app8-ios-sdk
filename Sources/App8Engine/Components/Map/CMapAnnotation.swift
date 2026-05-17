import MapKit
import UIKit

final class CMapAnnotation: NSObject, MKAnnotation {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let image: String?
    let color: UIColor?

    init(
        id: String,
        coordinate: CLLocationCoordinate2D,
        title: String? = nil,
        subtitle: String? = nil,
        image: String? = nil,
        color: UIColor? = nil
    ) {
        self.id = id
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.color = color
        super.init()
    }
}
