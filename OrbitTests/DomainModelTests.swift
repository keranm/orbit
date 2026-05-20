import XCTest
@testable import orbit

/// Tests for Domain model decoding — verifies JSON shapes confirmed against real CLI output.
final class DomainModelTests: XCTestCase {

    // MARK: - InstalledModelsResponse

    func test_installedModels_decodesEmptyResults() throws {
        let json = """
        {
          "cache_dir": "/Users/test/.cache/huggingface/hub",
          "delete_example": null,
          "results": []
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(InstalledModelsResponse.self, from: data)
        XCTAssertEqual(response.cacheDir, "/Users/test/.cache/huggingface/hub")
        XCTAssertTrue(response.results.isEmpty)
        XCTAssertFalse(response.hasModels)
    }

    func test_installedModels_hasModels_trueWhenNonEmpty() throws {
        // Real JSON shape confirmed against mesh-llm 0.65.1+skippy (2026-05-19)
        let json = """
        {
          "cache_dir": "/tmp",
          "results": [{
            "name": "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF:qwen2.5-coder-7b-instruct-q4_k_m",
            "ref": "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/qwen2.5-coder-7b-instruct-q4_k_m.gguf",
            "size": "4.7GB",
            "type": "gguf",
            "path": "/Users/test/.cache/huggingface/hub/model.gguf"
          }]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(InstalledModelsResponse.self, from: data)
        XCTAssertTrue(response.hasModels)
        let entry = try XCTUnwrap(response.results.first)
        XCTAssertEqual(entry.name, "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF:qwen2.5-coder-7b-instruct-q4_k_m")
        XCTAssertEqual(entry.size, "4.7GB")
        XCTAssertEqual(entry.displayName, "qwen2.5-coder-7b-instruct-q4_k_m")
    }

    func test_installedModel_id_usesRefWhenPresent() throws {
        let ref = "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/qwen2.5-coder-7b-instruct-q4_k_m.gguf"
        let entry = InstalledModelEntry(name: "org/repo:stem", ref: ref)
        XCTAssertEqual(entry.id, ref)
    }

    func test_installedModel_id_fallsBackToName() throws {
        let entry = InstalledModelEntry(name: "Qwen3-8B")
        XCTAssertEqual(entry.id, "Qwen3-8B")
    }

    // MARK: - CatalogModelsResponse

    func test_catalogModel_decodesKnownFields() throws {
        let json = """
        {
          "results": [
            {
              "name": "Qwen2.5-0.5B-Instruct-Q4_K_M",
              "ref": "Qwen/Qwen2.5-0.5B-Instruct-GGUF@main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
              "description": "Draft for Qwen2.5 models",
              "size": "491MB",
              "type": "gguf",
              "capabilities": {
                "audio": "none",
                "multimodal": "none",
                "reasoning": "likely",
                "text": true,
                "tool_use": "none",
                "vision": "none"
              },
              "download": "mesh-llm models download ...",
              "draft": null,
              "show": "mesh-llm models show ..."
            }
          ],
          "source": "catalog"
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(CatalogModelsResponse.self, from: data)
        XCTAssertEqual(response.source, "catalog")
        XCTAssertEqual(response.results.count, 1)

        let model = response.results[0]
        XCTAssertEqual(model.name, "Qwen2.5-0.5B-Instruct-Q4_K_M")
        XCTAssertEqual(model.size, "491MB")
        XCTAssertEqual(model.type, "gguf")
        XCTAssertTrue(model.capabilities?.supportsReasoning == true)
        XCTAssertFalse(model.capabilities?.supportsToolUse == true)
        XCTAssertEqual(model.id, model.ref)
    }

    func test_catalogModel_id_equalsRef() throws {
        let json = """
        {"results": [{"name": "M", "ref": "org/repo@branch/file.gguf",
          "capabilities": {"audio":"none","multimodal":"none","reasoning":"none","text":true,"tool_use":"none","vision":"none"}}],
          "source": "catalog"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(CatalogModelsResponse.self, from: data)
        XCTAssertEqual(response.results[0].id, "org/repo@branch/file.gguf")
    }

    func test_catalogModel_capabilities_supportsVision_false_for_none() throws {
        let cap = try JSONDecoder().decode(
            CatalogModelCapabilities.self,
            from: #"{"reasoning":"none","tool_use":"none","text":true,"vision":"none"}"#.data(using: .utf8)!
        )
        XCTAssertFalse(cap.supportsVision)
        XCTAssertFalse(cap.supportsToolUse)
        XCTAssertFalse(cap.supportsReasoning)
    }

    func test_catalogModel_capabilities_supportsToolUse_true_for_likely() throws {
        let cap = try JSONDecoder().decode(
            CatalogModelCapabilities.self,
            from: #"{"reasoning":"none","tool_use":"likely","text":true,"vision":"none"}"#.data(using: .utf8)!
        )
        XCTAssertTrue(cap.supportsToolUse)
    }

    func test_catalogModel_hashable() throws {
        let json = """
        {"results": [
          {"name": "A", "ref": "ref-a", "capabilities": {"audio":"none","multimodal":"none","reasoning":"none","text":true,"tool_use":"none","vision":"none"}},
          {"name": "B", "ref": "ref-b", "capabilities": {"audio":"none","multimodal":"none","reasoning":"none","text":true,"tool_use":"none","vision":"none"}}
        ], "source": "catalog"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(CatalogModelsResponse.self, from: data)
        let set = Set(response.results)
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - MeshLLMClient

    func test_client_checkLiveness_returnsFalseWhenNotRunning() async {
        // Use a port that will never be open in a test environment.
        // Port 9337 is the real runtime port and may be open if the runtime is running.
        let client = MeshLLMClient(apiPort: 19991)
        let alive = await client.checkLiveness()
        XCTAssertFalse(alive, "Liveness must be false when nothing is listening on port 19991")
    }

    func test_client_checkReadiness_returnsFalseWhenNotRunning() async {
        let client = MeshLLMClient(apiPort: 19991)
        let ready = await client.checkReadiness()
        XCTAssertFalse(ready, "Readiness must be false when nothing is listening on port 19991")
    }

    func test_client_checkLiveness_doesNotThrow() async {
        let client = MeshLLMClient(apiPort: 19991)
        _ = await client.checkLiveness()
    }
}
