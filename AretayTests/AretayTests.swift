//
//  AretayTests.swift
//  AretayTests
//

import Foundation
import Testing
@testable import Aretay

struct AretayTests {

    @Test func itemStoresTimestamp() async throws {
        let now = Date()
        let item = Item(timestamp: now)
        #expect(item.timestamp == now)
    }
}
