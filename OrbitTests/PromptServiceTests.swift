import XCTest
import SwiftData
@testable import orbit

final class PromptServiceTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = try? ModelContainer(
            for: PromptTemplate.self, PromptVariable.self, PromptVersion.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
    }

    // MARK: - Render

    func test_render_replacesSimpleVariable() {
        let service = PromptService(container: container!)
        let result = service.render(body: "Hello {{name}}!", variables: ["name": "World"])
        XCTAssertEqual(result, "Hello World!")
    }

    func test_render_replacesMultipleVariables() {
        let service = PromptService(container: container!)
        let result = service.render(body: "{{greeting}}, {{name}}!", variables: ["greeting": "Hi", "name": "Alice"])
        XCTAssertEqual(result, "Hi, Alice!")
    }

    func test_render_unknownVariable_unchanged() {
        let service = PromptService(container: container!)
        let result = service.render(body: "Hello {{name}}!", variables: [:])
        XCTAssertEqual(result, "Hello {{name}}!")
    }

    func test_render_noVariables_unchanged() {
        let service = PromptService(container: container!)
        let result = service.render(body: "Hello world!", variables: ["unused": "x"])
        XCTAssertEqual(result, "Hello world!")
    }

    func test_render_emptyBody_returnsEmpty() {
        let service = PromptService(container: container!)
        let result = service.render(body: "", variables: ["a": "b"])
        XCTAssertEqual(result, "")
    }

    func test_render_replacesSameVariableMultipleTimes() {
        let service = PromptService(container: container!)
        let result = service.render(
            body: "{{x}} + {{x}} = {{y}}",
            variables: ["x": "1", "y": "2"]
        )
        XCTAssertEqual(result, "1 + 1 = 2")
    }

    // MARK: - Fetch/Save

    func test_fetchAll_initiallyEmpty() async throws {
        let service = PromptService(container: container!)
        let results = try await service.fetchAll()
        XCTAssertTrue(results.isEmpty)
    }

    func test_save_and_fetchById() async throws {
        let service = PromptService(container: container!)
        let template = PromptTemplate(name: "Test", description: "Desc", body: "Hello {{name}}")
        try await service.save(template)

        let fetched = try await service.fetch(id: template.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Test")
        XCTAssertEqual(fetched?.body, "Hello {{name}}")
    }

    func test_save_and_fetchAll() async throws {
        let service = PromptService(container: container!)
        try await service.save(PromptTemplate(name: "A"))
        try await service.save(PromptTemplate(name: "B"))

        let results = try await service.fetchAll()
        XCTAssertEqual(results.count, 2)
    }

    func test_delete_removesFromStore() async throws {
        let service = PromptService(container: container!)
        let template = PromptTemplate(name: "ToDelete")
        try await service.save(template)
        try await service.delete(template)

        let fetched = try await service.fetch(id: template.id)
        XCTAssertNil(fetched)
    }

    func test_fetch_nonexistentId_returnsNil() async throws {
        let service = PromptService(container: container!)
        let result = try await service.fetch(id: UUID())
        XCTAssertNil(result)
    }

    // MARK: - Versioning

    func test_createVersion_incrementsVersion() async throws {
        let service = PromptService(container: container!)
        let template = PromptTemplate(name: "V", body: "v1 body")
        try await service.save(template)
        XCTAssertEqual(template.version, 1)

        try await service.createVersion(for: template, body: "v2 body", changeDescription: "Improved")
        XCTAssertEqual(template.version, 2)
        XCTAssertEqual(template.body, "v2 body")

        let versions = template.versions
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(versions[0].versionNumber, 2)
        XCTAssertEqual(versions[0].changeDescription, "Improved")
    }

    // MARK: - Mock Service

    func test_mock_saveAndFetch() async throws {
        let mock = MockPromptService()
        let template = PromptTemplate(name: "Mock Test")
        try await mock.save(template)

        let results = try await mock.fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Mock Test")
    }

    func test_mock_render() {
        let mock = MockPromptService()
        let result = mock.render(body: "Hi {{name}}", variables: ["name": "Mock"])
        XCTAssertEqual(result, "Hi Mock")
    }
}
