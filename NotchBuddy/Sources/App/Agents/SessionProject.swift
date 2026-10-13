import Foundation

/// A session's project and branch, read from the git files in its folder: no `git` call,
/// no network. A worktree belongs to the repository it was made from, so two sessions in
/// two worktrees of one repository read as one project on two branches.
enum SessionProject {
    struct Info: Equatable {
        var project: String
        var branch: String?
    }

    static func of(cwd: String, fileManager fm: FileManager = .default) -> Info {
        let folder = URL(fileURLWithPath: cwd).standardizedFileURL
        var dir = folder
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    return Info(project: dir.lastPathComponent, branch: branch(head: dotGit))
                }
                // A worktree: ".git" is a file, "gitdir: <repo>/.git/worktrees/<name>".
                if let text = try? String(contentsOf: dotGit, encoding: .utf8),
                   let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) {
                    let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                    let gitDir = URL(fileURLWithPath: path, relativeTo: dir).standardizedFileURL
                    let parts = gitDir.pathComponents
                    let repo = parts.lastIndex(of: ".git").map { parts[$0 - 1] } ?? dir.lastPathComponent
                    return Info(project: repo, branch: branch(head: gitDir))
                }
                return Info(project: dir.lastPathComponent, branch: nil)
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return Info(project: folder.lastPathComponent, branch: nil)
    }

    /// "ref: refs/heads/feat/x" → "feat/x"; a detached head → its short hash.
    private static func branch(head gitDir: URL) -> String? {
        guard let text = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref: refs/heads/") { return String(head.dropFirst("ref: refs/heads/".count)) }
        return head.isEmpty ? nil : String(head.prefix(7))
    }
}
