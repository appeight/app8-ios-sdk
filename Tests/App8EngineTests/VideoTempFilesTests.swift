import Foundation
import Testing
@testable import App8Engine

/// Two apps can both name a video "launch-reel"; their spilled files must not collide.
struct VideoTempFilesTests {

    private final class FakeSource {}

    @Test func eachDataSourceGetsItsOwnFolder() {
        let first = FakeSource()
        let second = FakeSource()
        let a = VideoTempFiles.directory(for: first)
        let b = VideoTempFiles.directory(for: second)
        #expect(a != b)
        #expect(VideoTempFiles.directory(for: first) == a)
        #expect(FileManager.default.fileExists(atPath: a.path))
    }
}
