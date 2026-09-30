import Foundation

enum TestFailure: Error { case missingValue }
private var failures: [String] = []
private var assertions = 0

private func check(_ condition: Bool, _ message: String, file: String, line: Int) {
    assertions += 1
    if !condition { failures.append("\(URL(fileURLWithPath: file).lastPathComponent):\(line): \(message)") }
}
func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #filePath, line: Int = #line) { check(a == b, "Expected \(a) == \(b). \(message)", file: file, line: line) }
func expectNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #filePath, line: Int = #line) { check(a != b, "Expected different values. \(message)", file: file, line: line) }
func expectTrue(_ value: Bool, _ message: String = "", file: String = #filePath, line: Int = #line) { check(value, "Expected true. \(message)", file: file, line: line) }
func expectFalse(_ value: Bool, _ message: String = "", file: String = #filePath, line: Int = #line) { check(!value, "Expected false. \(message)", file: file, line: line) }
func expectNil<T>(_ value: T?, _ message: String = "", file: String = #filePath, line: Int = #line) { check(value == nil, "Expected nil. \(message)", file: file, line: line) }
func expectLessThanOrEqual<T: Comparable>(_ a: T, _ b: T, file: String = #filePath, line: Int = #line) { check(a <= b, "\(a) exceeds \(b)", file: file, line: line) }
func expectGreaterThanOrEqual<T: Comparable>(_ a: T, _ b: T, file: String = #filePath, line: Int = #line) { check(a >= b, "\(a) is less than \(b)", file: file, line: line) }
func expectThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: String = #filePath, line: Int = #line) {
    do { _ = try expression(); check(false, "Expected an error. \(message)", file: file, line: line) }
    catch { check(true, "", file: file, line: line) }
}
func require<T>(_ value: T?, file: String = #filePath, line: Int = #line) throws -> T {
    guard let value else { check(false, "Required value is missing", file: file, line: line); throw TestFailure.missingValue }
    return value
}

@main enum CoreTestRunner {
    static func main() async {
        let core = CoreTests()
        let tests: [(String, () throws -> Void)] = [
            ("bundled layout and transparency", core.testBundledLayoutAndNullTransparencyMatchGeneratedFirmware),
            ("current action labels", core.testAllCurrentActionsHaveKnownLabels),
            ("stacked inheritance", core.testInheritanceDoesNotAssumeOnlyBaseIsActive),
            ("disabled and unknown keys", core.testDisabledUnknownAndTransparentStayDistinct),
            ("unknown-field round trip", core.testUnknownFieldsSurviveSnapshotRoundTrip),
            ("macros and gestures", core.testMacroAndGestureDetailsArePreserved),
            ("URL and identity validation", core.testURLParsingAndCacheIdentitySafety),
            ("HID frame validation", core.testProtocolRejectsTruncatedInvalidAndKeystrokeReports),
            ("stale fetch rejection", core.testDisconnectAndRevisionChangeRejectStaleFetches),
            ("visibility transitions", core.testVisibilityAndDuplicateLayers),
            ("physical geometry", core.testGeometryCovers72UniquePositionsAndThumbsFit),
            ("remote revision validation", core.testRemoteRevisionMismatchAndMalformedGeometryAreRejected)
        ]
        for (name, test) in tests {
            let before = failures.count
            do { try test() } catch { failures.append("\(name): \(error)") }
            print("\(failures.count == before ? "PASS" : "FAIL") \(name)")
        }
        do { try await RepositoryTests().testBundledAndCachedLayoutAvoidNetworkAndRefreshDoesNotReplaceIdentity() }
        catch { failures.append("Repository checks: \(error)") }
        if failures.isEmpty { print("PASS — \(tests.count + 1) tests, \(assertions) assertions") }
        else { for failure in failures { fputs(failure + "\n", stderr) }; fputs("\(failures.count) checks failed.\n", stderr) }
        exit(failures.isEmpty ? 0 : 1)
    }
}
