// UI harness for the iOS engine: a generic tab-bar app (flat floating bar, a
// full-screen pager home pushing a product screen with the hero zoom, a grid
// of cards with a context menu). Driven by UITests/HarnessUITests.swift.
//
//   cd Tests/UIHarness && python3 gen_fixture.py && xcodegen generate
//   xcodebuild test -project A8Harness.xcodeproj -scheme A8Harness -destination 'id=<simulator>'
//
import UIKit
import App8Engine

final class FixtureDataSource: App8DataSource, @unchecked Sendable {
    let bundle: [String: Any]
    init(tab: String?) throws {
        let url = Bundle.main.url(forResource: "fixture", withExtension: "json")!
        var b = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        if ProcessInfo.processInfo.environment["A8_NOTABS"] != nil {
            var app = b["app"] as! [String: Any]
            app["navigation"] = ["startFlow": "main", "flows": [["id": "main", "startScreen": "bag"]]]
            b["app"] = app
        }
        if let bar = ProcessInfo.processInfo.environment["A8_BAR"] {
            // A material bar background: a dark blur, with or without a 50% black tint.
            var layers: [[String: Any]] = [["id": "tabBarBlur", "type": "visualEffect", "content": ["blur": "systemMaterialDark"]]]
            if bar == "blurtint" { layers.append(["id": "tabBarTint", "type": "fill", "content": ["solid": "#00000080"]]) }
            b["styles"] = [[["id": "tabBarBg", "type": "material", "content": layers]]]
            var screens = b["screens"] as! [String: Any]
            var tabs = screens["tabs"] as! [String: Any]
            var content = tabs["content"] as! [String: Any]
            var style = content["barStyle"] as! [String: Any]
            style["background"] = "tabBarBg"; style["height"] = 50; style["cornerRadius"] = 0
            style["sideInset"] = 16; style["bottomOffset"] = 10
            content["barStyle"] = style; tabs["content"] = content; screens["tabs"] = tabs; b["screens"] = screens
        }
        if let tab {
            var screens = b["screens"] as! [String: Any]
            var tabs = screens["tabs"] as! [String: Any]
            var content = tabs["content"] as! [String: Any]
            content["initialTab"] = tab
            tabs["content"] = content; screens["tabs"] = tabs; b["screens"] = screens
        }
        bundle = b
    }
    private func d(_ v: Any) -> Data { try! JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]) }
    func getApp() async throws -> Data { d(bundle["app"]!) }
    func getStyles() async throws -> [Data] { (bundle["styles"] as! [Any]).map(d) }
    func getComponents() async throws -> [Data] { (bundle["components"] as! [Any]).map(d) }
    func getComponent(componentId: String) async throws -> Data { throw URLError(.fileDoesNotExist) }
    func getScreen(screenId: String) async throws -> Data {
        guard let s = (bundle["screens"] as! [String: Any])[screenId] else { throw URLError(.fileDoesNotExist) }
        return d(s)
    }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { throw URLError(.fileDoesNotExist) }
    func getAllScreenIds() async throws -> [String]? { Array((bundle["screens"] as! [String: Any]).keys) }
    /// Photos drawn on the fly: a tall coloured gradient with the name on it.
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? {
        let name = assetName ?? assetId ?? "x"
        let hue = CGFloat(abs(name.hashValue % 360)) / 360
        let size = CGSize(width: 600, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(hue: hue, saturation: 0.6, brightness: 0.9, alpha: 1).cgColor,
                          UIColor(hue: hue, saturation: 0.8, brightness: 0.4, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            UIColor.white.setStroke()
            let path = UIBezierPath(ovalIn: CGRect(x: 150, y: 300, width: 300, height: 300)); path.lineWidth = 12; path.stroke()
            (name as NSString).draw(at: CGPoint(x: 40, y: 60), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 64), .foregroundColor: UIColor.white])
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var instance: App8.Instance?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        if ProcessInfo.processInfo.arguments.contains("-slow") { window.layer.speed = 0.1 }
        let tab = ProcessInfo.processInfo.environment["A8_TAB"]
        Task { @MainActor in
            do {
                let instance = App8.instance(dataSource: try FixtureDataSource(tab: tab))
                self.instance = instance
                window.rootViewController = try await instance.startApp()
            } catch {
                print("HARNESS start failed: \(error)")
            }
        }
        return true
    }

}
