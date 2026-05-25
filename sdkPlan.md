# Plan: Migrate Orbit to MeshLLM Swift SDK

## Current state

Mesh-LLM is bundled as a Rust binary — downloaded from GitHub Releases via
`ci/fetch-meshllm.sh`, placed in `orbit/Resources/`, copied into the app bundle
by an Xcode build phase script, then managed as a subprocess. Orbit communicates
with it via raw HTTP on localhost:9337 (OpenAI-compatible API) and
localhost:3131 (Management API). This involves ~10 custom services totaling
~3,400 lines.

Files involved:

| Service | Lines | Role |
|---------|-------|------|
| `RuntimeManager.swift` | 1260 | Process lifecycle, binary resolution, health checks, model catalog, mesh state |
| `ChatService.swift` | 272 | Raw HTTP POST to `/v1/chat/completions` with SSE streaming |
| `ModelDownloadService.swift` | 408 | Direct HF download + cache structure setup |
| `MeshDiscoveryService.swift` | 209 | Text parser for `mesh-llm discover` subprocess output |
| `RuntimeUpdateService.swift` | 154 | GitHub release polling + tarball extraction |
| `ModelService.swift` | 247 | CLI subprocess for `models delete` + cache cleanup |
| `MeshLLMClient.swift` | ~60 | HTTP health check client |
| `MeshManagementClient.swift` | ~120 | HTTP management API client (status, models, peers) |
| `MeshModels.swift` | 319 | Domain types mirroring management API responses |
| `CatalogModel.swift` | 42 | Domain types for recommended model catalog |

Build infrastructure:

| File | Role |
|------|------|
| `ci/fetch-meshllm.sh` | Downloads pinned mesh-llm binary + verifies checksum |
| `project.pbxproj` — "Embed mesh-llm binary" phase | Copies 5 binaries into app bundle |

---

## Target state: MeshLLM Swift SDK (PR #634, branch `jd/sdk`)

The SDK is a Swift Package at the mesh-llm repo root. Tagged releases resolve a
prebuilt `MeshLLMFFI.xcframework` through SwiftPM automatically.

SPM integration:

```swift
.package(url: "https://github.com/Mesh-LLM/mesh-llm", from: "0.66.0")

// product:
.product(name: "MeshLLM", package: "mesh-llm")
```

### `Node` API

| Surface | Key methods |
|---------|-------------|
| `node.inference` | `listModels()`, `chat(ChatRequest)` → `AsyncThrowingStream<Event, Error>`, `responses()`, `cancel()` |
| `node.models` | `recommended()`, `search()`, `show()`, `installed()`, `download()`, `delete()`, `cacheStatus()`, `cleanup()`, `pruneDerivedCache()` |
| `node.serving` | `status()`, `servedModels()`, `load()`, `unload()`, `unloadModel()`, `unloadInstance()`, `setDevicePolicy()` |

Static methods: `Node.discoverPublicMeshes()`, `Node.connectPublic()`

### Native runtime

The SDK resolves a platform-specific `meshllm-native-*` artifact (e.g.
`meshllm-native-darwin-aarch64-metal`) via `NativeRuntime.prepare()`. The
artifact contains `libmeshllm_ffi.dylib` with a verified checksum manifest.

Resolution priority: `MESHLLM_NATIVE_RUNTIME_ARTIFACT_DIR` env var, then
`MESHLLM_NATIVE_RUNTIME_DIR`, then `MESH_SDK_NATIVE_RUNTIME_DIR`, then an
explicit URL.

---

## Prerequisite

Wait for PR #634 to merge to `main` and tag v0.66.0 (or the version that ships
the Swift SDK). Do not start until a tagged release is available.

---

## Migration steps

### Phase A — Build & dependency changes

| # | File | Action |
|---|------|--------|
| A1 | `project.pbxproj` | Add SPM dependency: `MeshLLM` product from `mesh-llm` repo |
| A2 | `project.pbxproj` | Remove "Embed mesh-llm binary" build phase (shell script copying `mesh-llm`, `rpc-server-metal`, `llama-server-metal`, `llama-moe-analyze`, `llama-moe-split`) |
| A3 | `Info.plist` | Add `ITSAppUsesNonExemptEncryption = YES` (QUIC uses TLS 1.3) |
| A4 | `ci/fetch-meshllm.sh` | Remove — no longer needed |
| A5 | `orbit/Resources/mesh-llm` + 4 companions | Remove from repo — SDK resolves native runtime artifact |

### Phase B — Remove custom HTTP & subprocess management

| # | File | Action |
|---|------|--------|
| B1 | `RuntimeManager.swift` | Replace with thin `RuntimeAdapter` (~150 lines). SDK `Node` handles lifecycle internally. Adapter wraps `node.status()`, `node.serving.status()` as `@Observable` properties for existing UI bindings. |
| B2 | `ChatService.swift` | Replace with `node.inference.chatStream()`. The raw HTTP SSE parser goes away. `ChatServiceProtocol` can remain if injection is needed, but the implementation becomes a thin SDK wrapper. |
| B3 | `MeshLLMClient.swift` | Remove — health check via SDK |
| B4 | `MeshManagementClient.swift` | Remove — management API calls via SDK |
| B5 | `MeshDiscoveryService.swift` | Replace with `Node.discoverPublicMeshes()`. The text parser for subprocess output goes away. |
| B6 | `ModelDownloadService.swift` | Replace with `node.models.download()`. Direct HF cache setup (`resolveRef`, symlinks) becomes SDK responsibility. |
| B7 | `RuntimeUpdateService.swift` | Simplify or remove. SDK versions map to SPM version bumps. Remove GitHub release polling, tarball download, /usr/bin/tar extraction, atomic file replacement. |
| B8 | `ModelService.swift` | Replace `remove()` with `node.models.delete()`. `uninstallAll()` becomes `node.stop()` + cache cleanup via SDK. |

### Phase C — Domain model alignment

| # | File | Action |
|---|------|--------|
| C1 | `MeshModels.swift` | Replace `MeshConnectionState`, `MeshMode`, `RuntimeLaunchConfiguration`, `MeshAPIStatus`, `MeshModelEntry`, `DiscoveredMesh` with SDK types. Keep Orbit-specific display helpers (diagnosticsLabel, modelSummary) if they wrap SDK types. |
| C2 | `CatalogModel.swift` | Replace with SDK's `ModelSummary`, `ModelDetails`. Keep Orbit-specific display formatting. |

### Phase D — UI and feature integration

| # | File | Action |
|---|------|--------|
| D1 | `AboutSection.swift` | Replace `runtimeManager.installedVersion` with SDK version query |
| D2 | `ResetSection.swift` | Replace "Remove Mesh-LLM runtime" destructive row — SDK has no standalone binary to remove |
| D3 | `OnboardingViewModel.swift` | Replace `RuntimeManager` start/health check with `node.start()` async call |
| D4 | `AgentExecutionService.swift` | Replace `ChatService()` instantiation with `node.inference.chatStream()` — SDK returns typed `Event.tokenDelta` instead of raw SSE parsing |

### Phase E — Validation

| # | Step |
|---|------|
| E1 | Build project, verify `MeshLLM` resolves through SPM |
| E2 | Run onboarding flow — node start, model download |
| E3 | Run a Think-step agent — verify inference streaming |
| E4 | Run a data-source agent (read mail → think → output) — verify multi-step works |
| E5 | Run an agent with local serving — verify `node.serving.load()` / unload |
| E6 | Test runtime lifecycle — stop, restart, reconnection |
| E7 | Check reset/uninstall — cache cleanup via SDK |
| E8 | Smoke test CI — confirm no `ci/fetch-meshllm.sh` dependency remains |

---

## Risks & open questions

1. **PR #634 is not merged yet** — written against branch `jd/sdk`. The API
   surface may change before release to `main`.
2. **Native runtime artifact bundling** — the SDK expects a
   `meshllm-native-darwin-aarch64-metal` directory. Orbit currently ships a raw
   `mesh-llm` binary. Decide whether to:
   - (a) Bundle the native runtime artifact in the app (replacing the current
     binary in `Resources/`)
   - (b) Let the SDK download it at first launch
   - (c) Set `MESHLLM_NATIVE_RUNTIME_ARTIFACT_DIR` via CI at build time
3. **Encryption declaration** — SDK docs say `ITSAppUsesNonExemptEncryption =
   YES` is required. Confirm this doesn't affect existing App Store compliance.
4. **Version coupling** — Orbit currently pins `mesh-llm` to v0.65.1. With SPM,
   version is managed at the package level. Establish a policy for when to bump
   the SDK dependency.
5. **Mesh-only mode (no local serving)** — the SDK supports client-only
   inference without a native runtime artifact. Orbit's current architecture
   assumes a local process. The migration could be staged: first replace
   subprocess management, then add local serving via SDK's `ServingController`.
