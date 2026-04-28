#if os(macOS)
import Foundation

// MARK: - Types

struct ShippingPlan {
    let branchName: String
    let commitMessage: String
    let prTitle: String
    let prBody: String
}

enum GitError: LocalizedError {
    case commandFailed(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output): return "Git command failed: \(output)"
        case .parseFailed(let reason): return "Parse failed: \(reason)"
        }
    }
}

enum GitHubError: LocalizedError {
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status, let body): return "GitHub API \(status): \(body)"
        }
    }
}

// MARK: - Git Operations

/// Shared git operations and LLM response parsing.
/// Mirrors pyre_client's PyreClient.Actions.Git module.
enum GitHelper {

    /// Parse a shipping plan from LLM response text.
    /// Extracts: branch_name, commit_message, pr_title, pr_body.
    static func parseShippingPlan(_ text: String) -> ShippingPlan? {
        guard let branch = extractField(text, name: "branch_name"),
              let commitMsg = extractField(text, name: "commit_message"),
              let prTitle = extractField(text, name: "pr_title"),
              let prBody = extractField(text, name: "pr_body") else {
            return nil
        }
        return ShippingPlan(
            branchName: branch,
            commitMessage: commitMsg,
            prTitle: prTitle,
            prBody: prBody
        )
    }

    /// Parse an APPROVE/REJECT verdict from LLM review text.
    /// Returns "approve", "reject", or "unknown".
    static func parseVerdict(_ text: String) -> String {
        var verdict = "unknown"
        for line in text.components(separatedBy: "\n") {
            let upper = line.uppercased()
            if upper.contains("APPROVE") { verdict = "approve" }
            if upper.contains("REJECT") { verdict = "reject" }
        }
        return verdict
    }

    /// Remove pyre artifact paths from .gitignore.
    static func editGitignore(workingDir: String) {
        let path = (workingDir as NSString).appendingPathComponent(".gitignore")
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        let updated = content
            .components(separatedBy: "\n")
            .filter { !$0.contains("priv/pyre/features/") && !$0.contains("priv/pyre/runs/") }
            .joined(separator: "\n")

        try? updated.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// `git checkout -b name`, falls back to `git checkout name` if branch exists.
    static func checkoutOrCreateBranch(_ name: String, workingDir: String) async throws {
        let esc = ClaudeCLIHelper.shellEscape(name)
        let result = try await runGit("checkout -b \(esc)", workingDir: workingDir)
        if !result.isSuccess {
            let fallback = try await runGit("checkout \(esc)", workingDir: workingDir)
            guard fallback.isSuccess else {
                throw GitError.commandFailed(fallback.output)
            }
        }
    }

    /// `git checkout -b name` — fails if branch already exists.
    static func checkoutBranch(_ name: String, workingDir: String) async throws {
        let esc = ClaudeCLIHelper.shellEscape(name)
        let result = try await runGit("checkout -b \(esc)", workingDir: workingDir)
        guard result.isSuccess else {
            throw GitError.commandFailed(result.output)
        }
    }

    /// `git add -A`
    static func addAll(workingDir: String) async throws {
        let result = try await runGit("add -A", workingDir: workingDir)
        guard result.isSuccess else {
            throw GitError.commandFailed(result.output)
        }
    }

    /// `git commit -m "message"` — silently succeeds on "nothing to commit".
    static func commit(message: String, workingDir: String) async throws {
        let esc = ClaudeCLIHelper.shellEscape(message)
        let result = try await runGit("commit -m \(esc)", workingDir: workingDir)
        if !result.isSuccess {
            if result.output.contains("nothing to commit") {
                return  // Not an error
            }
            throw GitError.commandFailed(result.output)
        }
    }

    /// `git push -u origin branch_name`
    static func push(branch: String, workingDir: String) async throws {
        let esc = ClaudeCLIHelper.shellEscape(branch)
        let result = try await runGit("push -u origin \(esc)", workingDir: workingDir)
        guard result.isSuccess else {
            throw GitError.commandFailed(result.output)
        }
    }

    /// `git push origin <current branch>`
    static func pushCurrentBranch(workingDir: String) async throws {
        let branchResult = try await runGit("rev-parse --abbrev-ref HEAD", workingDir: workingDir)
        guard branchResult.isSuccess else {
            throw GitError.commandFailed(branchResult.output)
        }
        let branch = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let esc = ClaudeCLIHelper.shellEscape(branch)
        let pushResult = try await runGit("push origin \(esc)", workingDir: workingDir)
        guard pushResult.isSuccess else {
            throw GitError.commandFailed(pushResult.output)
        }
    }

    // MARK: - Private

    private static func runGit(_ args: String, workingDir: String) async throws -> ShellExecutor.CommandResult {
        let dir = ClaudeCLIHelper.shellEscape(workingDir)
        return try await ShellExecutor.run("cd \(dir) && git \(args)")
    }

    private static func extractField(_ text: String, name: String) -> String? {
        let pattern = "\(name):\\s*(.+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - GitHub API

/// Lightweight GitHub API client.
/// Mirrors pyre_client's PyreClient.Actions.GitHub module.
enum GitHubHelper {

    private static let apiBase = "https://api.github.com"

    /// Create a pull request. Returns (html_url, number).
    static func createPullRequest(
        config: [String: Any],
        plan: ShippingPlan,
        draft: Bool
    ) async throws -> (url: String, number: Int) {
        let owner = config["owner"] as! String
        let repo = config["repo"] as! String
        let token = config["token"] as! String

        let body: [String: Any] = [
            "title": plan.prTitle,
            "body": plan.prBody,
            "head": plan.branchName,
            "base": "main",
            "draft": draft
        ]

        let json = try await post(
            path: "/repos/\(owner)/\(repo)/pulls",
            body: body,
            token: token
        )

        guard let url = json["html_url"] as? String,
              let number = json["number"] as? Int else {
            throw GitHubError.requestFailed(0, "Unexpected response shape")
        }

        return (url: url, number: number)
    }

    /// Post a comment on a PR.
    static func createComment(
        config: [String: Any],
        prNumber: Any,
        body: String
    ) async throws {
        let owner = config["owner"] as! String
        let repo = config["repo"] as! String
        let token = config["token"] as! String

        let _ = try await post(
            path: "/repos/\(owner)/\(repo)/issues/\(prNumber)/comments",
            body: ["body": body],
            token: token
        )
    }

    /// Mark a PR as ready for review (remove draft status) via GraphQL.
    static func markReadyForReview(
        config: [String: Any],
        prNumber: Any
    ) async throws {
        let token = config["token"] as! String

        let query = """
        mutation {
          markPullRequestReadyForReview(input: {pullRequestId: "\(prNumber)"}) {
            pullRequest { number }
          }
        }
        """

        let _ = try await post(
            path: "/graphql",
            body: ["query": query],
            token: token
        )
    }

    // MARK: - Private

    private static func post(
        path: String,
        body: [String: Any],
        token: String
    ) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: apiBase + path)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        guard statusCode >= 200 && statusCode < 300 else {
            throw GitHubError.requestFailed(statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return json
    }
}
#endif
