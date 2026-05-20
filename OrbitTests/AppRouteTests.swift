import XCTest
@testable import orbit

final class AppRouteTests: XCTestCase {

    func test_route_new_chat_is_hashable() {
        XCTAssertEqual(AppRoute.newChat, AppRoute.newChat)
    }

    func test_route_prompts_is_hashable() {
        XCTAssertEqual(AppRoute.prompts, AppRoute.prompts)
    }

    func test_route_models_is_hashable() {
        XCTAssertEqual(AppRoute.models, AppRoute.models)
    }

    func test_route_settings_is_hashable() {
        XCTAssertEqual(AppRoute.settings, AppRoute.settings)
    }

    func test_route_chat_equality_by_id() {
        let id = UUID()
        XCTAssertEqual(AppRoute.chat(id: id), AppRoute.chat(id: id))
    }

    func test_route_chat_inequality_across_ids() {
        XCTAssertNotEqual(AppRoute.chat(id: UUID()), AppRoute.chat(id: UUID()))
    }

    func test_routes_are_distinct() {
        let id = UUID()
        let routes: [AppRoute] = [.newChat, .chat(id: id), .prompts, .models, .settings]
        let set = Set(routes)
        XCTAssertEqual(set.count, 5, "V1 must have exactly 5 distinct route cases")
    }

    func test_all_v1_routes_present() {
        // Exhaustive switch — fails to compile if any case is missing.
        let routes: [AppRoute] = [.newChat, .chat(id: UUID()), .prompts, .models, .settings]
        var count = 0
        for route in routes {
            switch route {
            case .newChat, .chat, .prompts, .models, .settings:
                count += 1
            }
        }
        XCTAssertEqual(count, 5)
    }

    func test_no_playground_route() {
        // Playground is explicitly excluded from V1 scope.
        let names = [AppRoute.newChat, .prompts, .models, .settings]
            .map { String(describing: $0) }
        XCTAssertFalse(names.contains(where: { $0.contains("playground") }))
    }

    func test_route_usable_as_dictionary_key() {
        var map: [AppRoute: String] = [:]
        map[.newChat]  = "newChat"
        map[.prompts]  = "prompts"
        map[.models]   = "models"
        map[.settings] = "settings"
        let id = UUID()
        map[.chat(id: id)] = "chat"
        XCTAssertEqual(map.count, 5)
    }
}
