import XCTest
@testable import orbit

/// Tests for mesh data models, API decoding, model classification, and discovery parsing.
final class MeshModelsTests: XCTestCase {

    // MARK: - MeshAPIStatus decoding

    func test_meshAPIStatus_decodesKnownFields() throws {
        let json = """
        {
          "node_id": "abc123",
          "node_state": "serving",
          "is_host": true,
          "is_client": false,
          "llama_ready": true,
          "token": "eyJpZCI6InRlc3QifQ==",
          "peers": [],
          "serving_models": ["unsloth/Qwen3-0.6B-GGUF:Q4_K_M"],
          "available_models": [],
          "hosted_models": ["unsloth/Qwen3-0.6B-GGUF:Q4_K_M"],
          "version": "0.65.1"
        }
        """
        let status = try JSONDecoder().decode(MeshAPIStatus.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(status.nodeId, "abc123")
        XCTAssertEqual(status.nodeState, "serving")
        XCTAssertEqual(status.isHost, true)
        XCTAssertEqual(status.isClient, false)
        XCTAssertEqual(status.llamaReady, true)
        XCTAssertEqual(status.inviteToken, "eyJpZCI6InRlc3QifQ==")
        XCTAssertEqual(status.peerCount, 0)
        XCTAssertEqual(status.servingModels, ["unsloth/Qwen3-0.6B-GGUF:Q4_K_M"])
    }

    func test_meshAPIStatus_toleratesMissingOptionals() throws {
        let json = """
        {
          "node_id": "x",
          "peers": [{"node_id": "peer1"}]
        }
        """
        let status = try JSONDecoder().decode(MeshAPIStatus.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(status.peerCount, 1)
        XCTAssertNil(status.nodeState)
        XCTAssertNil(status.inviteToken)
        XCTAssertNil(status.servingModels)
    }

    func test_meshAPIStatus_emptyJSON_doesNotCrash() {
        let result = try? JSONDecoder().decode(MeshAPIStatus.self, from: "{}".data(using: .utf8)!)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.peerCount, 0)
    }

    // MARK: - MeshAPIModels decoding

    func test_meshAPIModels_decodesKnownFields() throws {
        let json = """
        {
          "mesh_models": [
            {
              "name": "unsloth/Qwen3-8B-GGUF:Q4_K_M",
              "display_name": "unsloth/Qwen3-8B-GGUF:Q4_K_M",
              "node_count": 3,
              "active_nodes": ["mac1", "mac2", "mac3"],
              "status": "warm",
              "fit_label": "Likely comfortable",
              "fit_detail": "This machine has 12GB capacity",
              "size_gb": 5.1,
              "mesh_vram_gb": 36.0,
              "audio": false,
              "vision": false,
              "reasoning": false,
              "tool_use": false
            }
          ]
        }
        """
        let models = try JSONDecoder().decode(MeshAPIModels.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(models.meshModels.count, 1)
        let m = models.meshModels[0]
        XCTAssertEqual(m.name, "unsloth/Qwen3-8B-GGUF:Q4_K_M")
        XCTAssertEqual(m.nodeCount, 3)
        XCTAssertEqual(m.fitLabel, "Likely comfortable")
        XCTAssertEqual(m.sizeGB ?? 0, 5.1, accuracy: 0.01)
        XCTAssertEqual(m.shortName, "Q4_K_M")
    }

    func test_meshAPIModels_emptyMeshModels() throws {
        let json = #"{ "mesh_models": [] }"#
        let models = try JSONDecoder().decode(MeshAPIModels.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(models.meshModels.isEmpty)
    }

    func test_meshAPIModels_toleratesMissingMeshModelsKey() {
        let json = "{}"
        let result = try? JSONDecoder().decode(MeshAPIModels.self, from: json.data(using: .utf8)!)
        XCTAssertNil(result, "MeshAPIModels must fail gracefully when mesh_models key is absent")
    }

    func test_meshModelEntry_shortName_colonFormat() {
        let entry = MeshModelEntry(
            name: "unsloth/Qwen3-8B-GGUF:Q4_K_M",
            displayName: nil, nodeCount: nil, activeNodes: nil, status: nil,
            fitLabel: nil, sizeGB: nil, meshVRAMGB: nil,
            audio: nil, vision: nil, reasoning: nil, toolUse: nil
        )
        XCTAssertEqual(entry.shortName, "Q4_K_M")
    }

    func test_meshModelEntry_shortName_slashFormat() {
        let entry = MeshModelEntry(
            name: "Qwen/Qwen3-8B-GGUF",
            displayName: nil, nodeCount: nil, activeNodes: nil, status: nil,
            fitLabel: nil, sizeGB: nil, meshVRAMGB: nil,
            audio: nil, vision: nil, reasoning: nil, toolUse: nil
        )
        XCTAssertEqual(entry.shortName, "Qwen3-8B-GGUF")
    }

    // MARK: - RuntimeLaunchConfiguration

    func test_runtimeLaunchConfig_localOnly_args() {
        let config = RuntimeLaunchConfiguration.localOnly
        XCTAssertEqual(config.buildArguments(), ["serve", "--headless"])
    }

    func test_runtimeLaunchConfig_withModel_args() {
        let config = RuntimeLaunchConfiguration(
            modelRef: "unsloth/Qwen3-8B-GGUF:Q4_K_M",
            joinToken: nil,
            meshMode: .none,
            noEnumerateHost: false
        )
        XCTAssertTrue(config.buildArguments().contains("--model"))
        XCTAssertTrue(config.buildArguments().contains("unsloth/Qwen3-8B-GGUF:Q4_K_M"))
        XCTAssertFalse(config.buildArguments().contains("--join"))
        XCTAssertFalse(config.buildArguments().contains("--no-enumerate-host"))
    }

    func test_runtimeLaunchConfig_privateMesh_args() {
        let config = RuntimeLaunchConfiguration(
            modelRef: nil,
            joinToken: "test-token-123",
            meshMode: .private,
            noEnumerateHost: false
        )
        let args = config.buildArguments()
        XCTAssertTrue(args.contains("--join"))
        XCTAssertTrue(args.contains("test-token-123"))
        XCTAssertFalse(args.contains("--no-enumerate-host"))
    }

    func test_runtimeLaunchConfig_publicMesh_includesNoEnumerate() {
        let config = RuntimeLaunchConfiguration(
            modelRef: nil,
            joinToken: "pub-token",
            meshMode: .public,
            noEnumerateHost: true
        )
        let args = config.buildArguments()
        XCTAssertTrue(args.contains("--join"))
        XCTAssertTrue(args.contains("--no-enumerate-host"),
            "Public mesh must use --no-enumerate-host for privacy")
    }

    // MARK: - MeshConnectionState

    func test_meshConnectionState_disconnected_notConnected() {
        XCTAssertFalse(MeshConnectionState.disconnected.isConnected)
    }

    func test_meshConnectionState_connectedPrivate_isConnected() {
        XCTAssertTrue(MeshConnectionState.connectedPrivate(peerCount: 2).isConnected)
    }

    func test_meshConnectionState_connectedPublic_isConnected() {
        XCTAssertTrue(MeshConnectionState.connectedPublic(peerCount: 5).isConnected)
    }

    func test_meshConnectionState_connectedPublic_isPublic() {
        XCTAssertTrue(MeshConnectionState.connectedPublic(peerCount: 3).isPublic)
        XCTAssertFalse(MeshConnectionState.connectedPrivate(peerCount: 3).isPublic)
    }

    func test_meshConnectionState_peerCount() {
        XCTAssertEqual(MeshConnectionState.connectedPrivate(peerCount: 7).peerCount, 7)
        XCTAssertEqual(MeshConnectionState.disconnected.peerCount, 0)
    }

    // MARK: - Public mesh consent

    func test_publicMeshConsentKey_isNotSetByDefault() {
        UserDefaults.standard.removeObject(forKey: "publicMeshConsentAcknowledged")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "publicMeshConsentAcknowledged"))
    }

    // MARK: - MeshDiscoveryService parser

    func test_discoverParser_parsesRealOutput() {
        let svc = MeshDiscoveryService.shared
        let sampleOutput = """
        🔍 Searching Nostr relays for mesh-llm meshes...
        Found 2 mesh(es):

          [1] Test2  6 node(s), 768GB capacity  serving: Qwen3-8B-Q4_K_M, unsloth/Qwen3-32B-GGUF@main:Q4_K_M  wanted: unsloth/Qwen3-8B-GGUF@main:Q4_K_M (score: 265, fresh, 151 clients)
              on disk: DeepSeek-R1-Distill-Qwen-14B-Q4_K_M
              token: eyJpZCI6InRlc3QxIn0=

          [2] (unnamed)  6 node(s), 768GB capacity  serving: unsloth/Qwen3-32B-GGUF@main:Q4_K_M (score: 565, fresh, 409 clients)
              token: eyJpZCI6InRlc3QyIn0=
        """
        let results = svc.parse(output: sampleOutput)
        XCTAssertEqual(results.count, 2)

        let first = results[0]
        XCTAssertEqual(first.name, "Test2")
        XCTAssertEqual(first.inviteToken, "eyJpZCI6InRlc3QxIn0=")
        XCTAssertEqual(first.nodeCount, 6)
        XCTAssertEqual(first.clientCount, 151)
        XCTAssertEqual(first.totalVRAMGB, 768)
        XCTAssertFalse(first.modelNames.isEmpty)

        let second = results[1]
        XCTAssertTrue(second.isUnnamed)
        XCTAssertEqual(second.inviteToken, "eyJpZCI6InRlc3QyIn0=")
        XCTAssertEqual(second.clientCount, 409)
    }

    func test_discoverParser_emptyOutput_returnsEmpty() {
        let results = MeshDiscoveryService.shared.parse(output: "")
        XCTAssertTrue(results.isEmpty)
    }

    func test_discoverParser_noMeshesFound_returnsEmpty() {
        let output = "🔍 Searching Nostr relays for mesh-llm meshes...\nNo meshes found."
        let results = MeshDiscoveryService.shared.parse(output: output)
        XCTAssertTrue(results.isEmpty)
    }

    func test_discoverParser_missingToken_excludesMesh() {
        let output = """
        [1] Test  3 node(s), 192GB capacity  serving: Qwen3-8B (score: 100, fresh, 10 clients)
        """
        let results = MeshDiscoveryService.shared.parse(output: output)
        XCTAssertTrue(results.isEmpty, "Meshes without a token must be excluded")
    }

    func test_discoveredMesh_modelSummary_truncatesLongList() {
        let mesh = DiscoveredMesh(
            id: "1", name: "Test", inviteToken: "tok",
            modelNames: ["unsloth/Qwen3-8B-GGUF:Q4_K_M", "unsloth/Qwen3-32B-GGUF:Q4_K_M", "extra1", "extra2"],
            nodeCount: 2, clientCount: 10, totalVRAMGB: 24
        )
        let summary = mesh.modelSummary
        XCTAssertTrue(summary.contains("+2 more"))
    }
}
