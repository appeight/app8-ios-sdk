import Foundation

/// Tracks the source location of a documentation example for error reporting
struct ExampleLocation: CustomStringConvertible {
    let file: String
    let line: Int

    var description: String {
        "\(file):\(line)"
    }
}

/// Represents a JSON example extracted from markdown documentation
struct ExtractedExample {
    let json: String
    let location: ExampleLocation
    let annotation: Annotation?

    enum Annotation {
        case type(String)       // @dsl-type: Component
        case skip(String)       // @dsl-skip: reason
    }
}
