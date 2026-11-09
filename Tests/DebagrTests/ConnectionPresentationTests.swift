import XCTest

@testable import Debagr

final class ConnectionPresentationTests: XCTestCase {
  func testBackendLogsStayInDiagnosticsRatherThanThePrimaryStatus() throws {
    let name = "ConnectionPresentationTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let request = folder.appendingPathComponent("request.json")
    defaults.set(request.path, forKey: "usbip-session-request")
    try JSONEncoder().encode(
      USBIPSessionState(supervisorPID: 0, phase: "failed", message: "Exit status 13")
    )
    .write(to: folder.appendingPathComponent("state.json"))
    try Data("TECHNICAL_BACKEND_LOG".utf8).write(to: folder.appendingPathComponent("output.log"))
    let session = USBIPSessionController(defaults: defaults)
    var message = ""
    session.onChange = { text, active in
      message = text
      XCTAssertFalse(active)
    }
    session.poll()
    XCTAssertTrue(message.contains("Diagnostics"))
    XCTAssertFalse(message.contains("TECHNICAL_BACKEND_LOG"))
    XCTAssertTrue(session.diagnostics.contains("TECHNICAL_BACKEND_LOG"))
  }
}
