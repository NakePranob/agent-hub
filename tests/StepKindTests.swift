import Foundation

// The session card reads a step's kind back from the verb the hook server wrote.
@main
enum StepKindTests {
    static func main() {
        var failures = 0
        func check(_ label: String, _ got: StepKind?, _ want: StepKind?) {
            if got == want { print("  ✓ \(label)") } else { print("  ✗ \(label): got \(String(describing: got))"); failures += 1 }
        }
        check("a tool's verb", StepKind.of("Reads · App.swift"), .read)
        check("a verb alone", StepKind.of("Agent"), .agent)
        check("the web, not a search", StepKind.of("Searches the web · swift 6"), .web)
        check("a shell search", StepKind.of("\(StepKind.shell("rg foo").verb) · rg foo"), .search)
        check("a test run", StepKind.of("\(StepKind.shell("swift test").verb) · swift test"), .test)
        check("a diff", StepKind.of(String.makeDiffStep(filename: "a.swift", added: 1, removed: 0, diffId: 0)), .edit)
        check("a failure", StepKind.of(StepKind.failedStep), .fail)
        check("an answer starting like a verb", StepKind.of("Reads fine now"), nil)
        check("an MCP tool", StepKind.of("Claude_Browser · find"), nil)
        print(failures == 0 ? "\nAll tests passed." : "\n\(failures) test(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
