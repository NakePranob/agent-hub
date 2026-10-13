import Foundation

// Project and branch of a session, from its folder's git files.
@main
enum SessionProjectTests {
    static func main() throws {
        var failures = 0
        func check(_ label: String, _ got: SessionProject.Info, _ want: SessionProject.Info) {
            if got == want { print("  ✓ \(label)") } else { print("  ✗ \(label): got \(got)"); failures += 1 }
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("session-project-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        // A checkout on a branch, entered from a subfolder.
        let repo = root.appendingPathComponent("agent-hub")
        try fm.createDirectory(at: repo.appendingPathComponent(".git/worktrees/wt"), withIntermediateDirectories: true)
        try fm.createDirectory(at: repo.appendingPathComponent("NotchBuddy/Sources"), withIntermediateDirectories: true)
        try "ref: refs/heads/feat/robot-3d\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        check("checkout", SessionProject.of(cwd: repo.path), .init(project: "agent-hub", branch: "feat/robot-3d"))
        check("subfolder", SessionProject.of(cwd: repo.appendingPathComponent("NotchBuddy/Sources").path),
              .init(project: "agent-hub", branch: "feat/robot-3d"))

        // A worktree elsewhere belongs to the repository it came from.
        let wt = root.appendingPathComponent("agent-hub-mail")
        try fm.createDirectory(at: wt, withIntermediateDirectories: true)
        try "gitdir: \(repo.path)/.git/worktrees/wt\n".write(to: wt.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/fix/mail-detail\n".write(to: repo.appendingPathComponent(".git/worktrees/wt/HEAD"), atomically: true, encoding: .utf8)
        check("worktree", SessionProject.of(cwd: wt.path), .init(project: "agent-hub", branch: "fix/mail-detail"))

        // A detached head reads as its short hash; a folder outside git as itself.
        try "0123456789abcdef\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        check("detached", SessionProject.of(cwd: repo.path), .init(project: "agent-hub", branch: "0123456"))
        let plain = root.appendingPathComponent("notes")
        try fm.createDirectory(at: plain, withIntermediateDirectories: true)
        check("no git", SessionProject.of(cwd: plain.path), .init(project: "notes", branch: nil))

        print(failures == 0 ? "\nAll tests passed." : "\n\(failures) test(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
