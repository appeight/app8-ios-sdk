import UIKit

protocol NamedSublayersLayerName: RawRepresentable, CaseIterable, CustomStringConvertible {}
extension NamedSublayersLayerName where RawValue == String {
    var description: String { rawValue }
}

protocol NamedSublayersProtocol: AbstractNamedSublayersProtocol where LayerName: NamedSublayersLayerName, LayerName.RawValue == String {
    func rebindNamedLayers()
}

extension NamedSublayersProtocol where Self: CALayer {

    /// Rebuilds `namedLayers` by decoding current `sublayers` names (`title`, `row_0`,
    /// `grid_0_0`, ...). Sublayers whose base doesn't map to `LayerName` are ignored.
    func rebindNamedLayers() {
        namedLayers.removeAll(keepingCapacity: true)
        
        guard let subs = sublayers else { return }
        
        for layer in subs {
            guard let raw = layer.name,
                  let (name, indices) = decode(raw) else { continue }
            bind(layer, to: name, indices: indices)
        }
    }
}

private extension NamedSublayersProtocol where Self: CALayer {

    /// Split a raw string like "myName_2_3" into (LayerName, [2, 3]).
    /// Returns nil if the base isn't a valid `LayerName` or any index isn't an Int.
    func decode(_ raw: String) -> (LayerName, [Int])? {
        let parts = raw.split(separator: "_", omittingEmptySubsequences: false)
        guard let base = parts.first,
              let name = LayerName(rawValue: String(base)) else {
            return nil
        }
        let idxStrings = parts.dropFirst()
        var indices: [Int] = []
        indices.reserveCapacity(idxStrings.count)
        for s in idxStrings {
            guard let i = Int(s) else { return nil }
            indices.append(i)
        }
        return (name, indices)
    }
    
    /// Store a layer under the given key and indices.
    func bind(_ layer: CALayer, to name: LayerName, indices: [Int]) {
        switch indices.count {
        case 0:
            self[name] = layer
        case 1:
            self[name, indices[0]] = layer
        case 2:
            self[name, indices[0], indices[1]] = layer
        default:
            set(layer: layer, name: name, indices: indices)
        }
    }

    /// Fallback setter for N-dimensional indices (the subscript only covers 0-2).
    func set(layer: CALayer, name: LayerName, indices: [Int]) {
        let key = name.description + indices.map { "_\($0)" }.joined()
        layer.name = key
        namedLayers[key] = layer
    }
}
