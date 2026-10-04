import Darwin
import XCTest
@testable import ViperCore

final class ProcessInventoryTests: XCTestCase {
    /// proc_listallpids must return nearly every process on the Mac; a 4×-off count would silently
    /// hide processes from both the memory advisor and the isInUse safety check.
    func testAllPIDsAndSampleCoverTheProcessTable() throws {
        let sleep = Process()
        sleep.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleep.arguments = ["30"]
        try sleep.run()
        defer { if sleep.isRunning { sleep.terminate() } }

        let pids = OpenFiles.allPIDs()
        XCTAssertTrue(pids.contains(getpid()))
        XCTAssertTrue(pids.contains(sleep.processIdentifier))

        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-A", "-o", "pid="]
        let out = Pipe()
        ps.standardOutput = out
        try ps.run()
        let psCount = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(whereSeparator: \.isNewline).count
        XCTAssertGreaterThanOrEqual(pids.count, Int(Double(psCount) * 0.9),
                                    "allPIDs saw \(pids.count) of \(psCount) processes")

        let (processes, _) = ProcessInventory.sample()
        let sample = processes.first { $0.pid == sleep.processIdentifier }
        XCTAssertNotNil(sample)
        XCTAssertTrue(sample!.path.hasSuffix("/sleep"))
    }
}
