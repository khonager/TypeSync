import Flutter
import UIKit
import XCTest

final class RunnerTests: XCTestCase {
  @MainActor
  func testFirstFlutterFrame() throws {
    let delegate = try XCTUnwrap(UIApplication.shared.delegate as? FlutterAppDelegate)
    let controller = try XCTUnwrap(delegate.window?.rootViewController as? FlutterViewController)
    let firstFrame = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in controller.isDisplayingFlutterUI },
      object: nil
    )
    wait(for: [firstFrame], timeout: 60)
  }
}
