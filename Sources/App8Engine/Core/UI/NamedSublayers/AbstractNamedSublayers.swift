import UIKit

protocol AbstractNamedSublayersProtocol: AnyObject {
    associatedtype LayerName: CustomStringConvertible
    
    var namedLayers: [String: CALayer] { get set }
    
    @discardableResult
    func setLayer<L: CALayer>(
        _ layer: L,
        named name: LayerName,
        superlayer: CALayer?,
        addToSublayers: Bool
    ) -> L
    
    @discardableResult
    func setLayers<S: Sequence, L: CALayer>(
        _ layers: S,
        named name: LayerName,
        superlayer: CALayer?,
        addToSublayers: Bool
    ) -> [L] where S.Element == L
    
    @discardableResult
    func setLayers<Rows: Sequence, Row: Sequence, L: CALayer>(
        _ matrix: Rows,
        named name: LayerName,
        superlayer: CALayer?,
        addToSublayers: Bool
    ) -> [[L]] where Rows.Element == Row, Row.Element == L
    
    subscript(name: LayerName, indices: Int...) -> CALayer? { get set }
    
    func layers1D(named name: LayerName) -> [CALayer]
    func layers2D(named name: LayerName) -> [[CALayer]]
}

extension AbstractNamedSublayersProtocol where Self: CALayer {

    private func fullName(_ base: LayerName, _ indices: [Int]) -> String {
        guard !indices.isEmpty else { return base.description }
        return base.description + indices.map { "_\($0)" }.joined()
    }
    
    @discardableResult
    private func _store<L: CALayer>(
        _ layer: L,
        base: LayerName,
        indices: [Int],
        superlayer: CALayer?,
        addToSublayers: Bool
    ) -> L {
        let key = fullName(base, indices)
        layer.name = key
        namedLayers[key] = layer
        if addToSublayers {
            (superlayer ?? self).addSublayer(layer)
        }
        return layer
    }
    
    @discardableResult
    func setLayer<L: CALayer>(
        _ layer: L,
        named name: LayerName,
        superlayer: CALayer? = nil,
        addToSublayers: Bool = true
    ) -> L {
        _store(layer, base: name, indices: [], superlayer: superlayer, addToSublayers: addToSublayers)
    }
    
    @discardableResult
    func setLayers<S: Sequence, L: CALayer>(
        _ layers: S,
        named name: LayerName,
        superlayer: CALayer? = nil,
        addToSublayers: Bool = true
    ) -> [L] where S.Element == L {
        layers.enumerated().map { (i, layer) in
            _store(layer, base: name, indices: [i], superlayer: superlayer, addToSublayers: addToSublayers)
        }
    }
    
    @discardableResult
    func setLayers<Rows: Sequence, Row: Sequence, L: CALayer>(
        _ matrix: Rows,
        named name: LayerName,
        superlayer: CALayer? = nil,
        addToSublayers: Bool = true
    ) -> [[L]] where Rows.Element == Row, Row.Element == L {
        matrix.enumerated().map { (i, row) in
            row.enumerated().map { (j, layer) in
                _store(layer, base: name, indices: [i, j], superlayer: superlayer, addToSublayers: addToSublayers)
            }
        }
    }
    
    subscript(name: LayerName, indices: Int...) -> CALayer? {
        get { namedLayers[fullName(name, indices)] }
        set { namedLayers[fullName(name, indices)] = newValue }
    }

    func layers1D(named base: LayerName) -> [CALayer] {
        var result: [CALayer] = []
        var i = 0
        while let l = self[base, i] {
            result.append(l)
            i += 1
        }
        return result
    }
    
    func layers2D(named base: LayerName) -> [[CALayer]] {
        var matrix: [[CALayer]] = []
        var i = 0
        
        while true {
            var row: [CALayer] = []
            var j = 0
            while let l = self[base, i, j] {
                row.append(l)
                j += 1
            }
            guard !row.isEmpty else { break }
            matrix.append(row)
            i += 1
        }
        return matrix
    }
    
    /// Returns the first sublayer whose name matches `base` plus optional indices (`base_0`, `base_0_1`, etc.).
    func findLayer(named base: LayerName, indices: Int...) -> CALayer? {
        let key = fullName(base, indices)
        return sublayers?.first { $0.name == key }
    }
    
    /// Returns a 1D list of sublayers named `base_0`, `base_1`, ... until a gap is found.
    func findLayers(named base: LayerName) -> [CALayer] {
        guard let subs = sublayers else { return [] }
        var result: [CALayer] = []
        var i = 0
        while let layer = subs.first(where: { $0.name == fullName(base, [i]) }) {
            result.append(layer)
            i += 1
        }
        return result
    }
    
    /// Returns a 2D matrix of sublayers named `base_i_j`. Stops when a whole row is missing.
    func findLayers2D(named base: LayerName) -> [[CALayer]] {
        guard let subs = sublayers else { return [] }
        var matrix: [[CALayer]] = []
        var i = 0
        
        while true {
            var row: [CALayer] = []
            var j = 0
            while let layer = subs.first(where: { $0.name == fullName(base, [i, j]) }) {
                row.append(layer)
                j += 1
            }
            guard !row.isEmpty else { break }
            matrix.append(row)
            i += 1
        }
        return matrix
    }
}
