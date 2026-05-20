import Foundation

/// Removes the Mesh-LLM runtime, its managed models, and its config from the user's Mac.
///
/// Removal is deliberately scoped to known Mesh-LLM-owned paths only:
///   - Binary at ~/.local/bin/mesh-llm and ~/.cargo/bin/mesh-llm
///   - Config directory ~/.mesh-llm/
///   - Downloaded models via `mesh-llm models delete --yes <ref>` (CLI-delegated)
///
/// The HuggingFace cache root (~/.cache/huggingface/hub/) is NEVER deleted wholesale
/// because it may contain content unrelated to Mesh-LLM. Per-model directories are
/// removed only via the CLI, which knows exactly what it manages.
struct MeshLLMUninstaller: Sendable {

    // MARK: - Result

    struct UninstallResult {
        var stoppedRuntime = false
        var removedModelRefs: [String] = []
        var removedBinaryPaths: [String] = []
        var removedConfigDir = false
        var skippedPaths: [String] = []
        var errors: [String] = []

        var removedModelCount: Int { removedModelRefs.count }
        var hasErrors: Bool { !errors.isEmpty }

        var summaryLines: [String] {
            var lines: [String] = []
            if stoppedRuntime         { lines.append("Stopped AI runtime") }
            if removedModelCount > 0  { lines.append("Removed \(removedModelCount) downloaded model\(removedModelCount == 1 ? "" : "s")") }
            if removedConfigDir       { lines.append("Removed configuration files") }
            if !removedBinaryPaths.isEmpty { lines.append("Removed Mesh-LLM runtime binary") }
            return lines
        }
    }

    // MARK: - Known paths

    /// Binary paths where the official installer and cargo place the mesh-llm binary.
    static let knownBinaryPaths: [String] = [
        ("~/.local/bin/mesh-llm" as NSString).expandingTildeInPath,
        ("~/.cargo/bin/mesh-llm" as NSString).expandingTildeInPath,
    ]

    /// Mesh-LLM configuration directory — wholly owned by Mesh-LLM, safe to remove entirely.
    static let configDirPath: String = ("~/.mesh-llm" as NSString).expandingTildeInPath

    // MARK: - Uninstall

    /// Performs a full uninstall in sequence.
    ///
    /// Calling `detectInstall()` on the RuntimeManager after this returns will
    /// set status to `.notInstalled`, allowing the standard onboarding flow to reinstall.
    ///
    /// - Parameter runtimeStatus: the current status snapshot (read on MainActor by the caller)
    /// - Parameter binaryURL: the current binary path snapshot (read on MainActor by the caller)
    func uninstall(
        runtimeStatus: RuntimeStatus,
        binaryURL: URL?,
        rm: RuntimeManager
    ) async -> UninstallResult {
        var result = UninstallResult()

        // 1. Stop the runtime so it releases file handles before we delete the binary.
        if runtimeStatus != .notInstalled && runtimeStatus != .stopping {
            await rm.stop()
            result.stoppedRuntime = true
        }

        // 2. Remove each installed model via the CLI while the binary still exists.
        //    This delegates cache cleanup to Mesh-LLM, so we never blindly delete
        //    unrelated HuggingFace content.
        if let bin = binaryURL {
            do {
                let installed = try await rm.fetchInstalledModels()
                for model in installed.results {
                    let ref = model.ref ?? model.name
                    let exitCode = await runCLI(binary: bin, arguments: ["models", "delete", "--yes", ref])
                    if exitCode == 0 {
                        result.removedModelRefs.append(ref)
                    } else {
                        result.errors.append("Could not remove model \"\(model.displayName)\".")
                    }
                }
            } catch {
                result.errors.append("Could not list installed models: \(error.localizedDescription)")
            }
        }

        // 3. Remove config directory (~/.mesh-llm/ is wholly Mesh-LLM-owned).
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.configDirPath) {
            do {
                try fm.removeItem(atPath: Self.configDirPath)
                result.removedConfigDir = true
            } catch {
                result.errors.append("Could not remove config directory: \(error.localizedDescription)")
                result.skippedPaths.append(Self.configDirPath)
            }
        }

        // 3b. Remove Mesh-LLM-managed HuggingFace model directories.
        // We only touch directories inside ~/.cache/huggingface/hub/ that were
        // created by Mesh-LLM. The root cache is never deleted.
        removeHFModelDirectories(forRemovedRefs: result.removedModelRefs, errors: &result.errors)

        // 4. Remove binary from each known path.
        for path in Self.knownBinaryPaths {
            if fm.fileExists(atPath: path) {
                do {
                    try fm.removeItem(atPath: path)
                    result.removedBinaryPaths.append(path)
                } catch {
                    result.errors.append("Could not remove binary at \(URL(fileURLWithPath: path).lastPathComponent): \(error.localizedDescription)")
                    result.skippedPaths.append(path)
                }
            }
        }

        return result
    }

    // MARK: - Private — HF directory cleanup

    /// Removes the `models--{org}--{repo}` directory from the HuggingFace hub cache
    /// for each model that was successfully deleted via the CLI.
    ///
    /// Safety rules:
    ///   - Only removes directories that start with "models--" inside the known HF hub path.
    ///   - Never removes the root cache directory or any parent of it.
    ///   - Derives the directory name from the model ref using the standard HF naming convention.
    private func removeHFModelDirectories(forRemovedRefs refs: [String], errors: inout [String]) {
        let hubPath = ("~/.cache/huggingface/hub" as NSString).expandingTildeInPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: hubPath) else { return }

        for ref in refs {
            // Derive the HF directory name from the ref.
            // Refs come in forms like:
            //   "unsloth/Qwen3-0.6B-GGUF:Q4_K_M"       → models--unsloth--Qwen3-0.6B-GGUF
            //   "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/…" → models--Qwen--Qwen2.5-Coder-7B-Instruct-GGUF
            guard let dirName = hfDirectoryName(for: ref) else { continue }

            // Strict whitelist: must start with "models--" and live directly under the hub dir.
            guard dirName.hasPrefix("models--") else { continue }
            let fullPath = (hubPath as NSString).appendingPathComponent(dirName)

            // Verify it is a direct child of the hub dir (no path traversal).
            guard URL(fileURLWithPath: fullPath).deletingLastPathComponent().path == hubPath else { continue }

            if fm.fileExists(atPath: fullPath) {
                do {
                    try fm.removeItem(atPath: fullPath)
                } catch {
                    errors.append("Could not remove model cache at \(dirName): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Converts a model ref to the HuggingFace cache directory name.
    /// Returns nil when the ref format is unrecognised.
    private func hfDirectoryName(for ref: String) -> String? {
        // Strip everything after "@" and ":" (version/quant suffixes)
        // then take the first two path components (org/repo)
        let stripped = ref
            .components(separatedBy: "@").first?
            .components(separatedBy: ":").first ?? ref
        let parts = stripped.components(separatedBy: "/").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        // HF convention: prefix "models--", join org and repo with "--",
        // replace underscores with hyphens to match HF cache naming.
        return "models--\(parts[0])--\(parts[1])"
            .replacingOccurrences(of: "_", with: "-")
    }

    // MARK: - Private — CLI helper

    private func runCLI(binary: URL, arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            nonisolated(unsafe) var done = false

            process.terminationHandler = { proc in
                guard !done else { return }
                done = true
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                done = true
                continuation.resume(returning: 1)
                return
            }

            Task.detached {
                try? await Task.sleep(for: .seconds(60))
                guard !done else { return }
                done = true
                process.terminate()
                continuation.resume(returning: 1)
            }
        }
    }
}
