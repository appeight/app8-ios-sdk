//
//  ClearPersistedDataTests.swift
//  App8EngineTests
//

import Foundation
import Testing
@testable import App8Engine

@MainActor
struct ClearPersistedDataTests {

    @Test func removesEveryAppSuite() {
        let suites = ["app8.clear-test-a", "app8.clear-test-b"]
        for name in suites {
            let d = UserDefaults(suiteName: name)!
            d.set("[1]", forKey: "var.cart")
            d.synchronize()
        }
        let other = UserDefaults(suiteName: "other.clear-test")!
        other.set("keep", forKey: "k")
        other.synchronize()

        App8.clearPersistedData()

        for name in suites { #expect(UserDefaults(suiteName: name)!.string(forKey: "var.cart") == nil) }
        #expect(other.string(forKey: "k") == "keep")
        UserDefaults.standard.removePersistentDomain(forName: "other.clear-test")
    }
}
