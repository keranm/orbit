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

    func test_v1_routes_are_distinct() {
        let id = UUID()
        let routes: [AppRoute] = [.newChat, .chat(id: id), .prompts, .models, .settings]
        let set = Set(routes)
        XCTAssertEqual(set.count, 5)
    }

    func test_pro_routes_are_distinct_from_v1() {
        let routes: [AppRoute] = [.dashboard, .coding, .playground]
        let set = Set(routes)
        XCTAssertEqual(set.count, 3)
    }

    func test_all_v1_cases_exhaustive() {
        var count = 0
        let routes: [AppRoute] = [.newChat, .chat(id: UUID()), .prompts, .models, .settings]
        for route in routes {
            switch route {
            case .newChat, .chat, .prompts, .models, .settings:
                count += 1
            case .dashboard, .coding, .playground:
                break
            }
        }
        XCTAssertEqual(count, 5)
    }

    func test_all_pro_cases_exhaustive() {
        var count = 0
        let routes: [AppRoute] = [.dashboard, .coding, .playground]
        for route in routes {
            switch route {
            case .newChat, .chat, .prompts, .models, .settings:
                break
            case .dashboard, .coding, .playground:
                count += 1
            }
        }
        XCTAssertEqual(count, 3)
    }

    func test_route_usable_as_dictionary_key() {
        var map: [AppRoute: String] = [:]
        map[.newChat]    = "newChat"
        map[.prompts]    = "prompts"
        map[.models]     = "models"
        map[.settings]   = "settings"
        map[.dashboard]  = "dashboard"
        map[.coding]     = "coding"
        map[.playground] = "playground"
        let id = UUID()
        map[.chat(id: id)] = "chat"
        XCTAssertEqual(map.count, 8)
    }

    func test_playground_is_pro_only_route() {
        // Playground should not appear in V1-only lists
        let v1Routes: [AppRoute] = [.newChat, .prompts, .models, .settings]
        let names = v1Routes.map { String(describing: $0) }
        XCTAssertFalse(names.contains(where: { $0.contains("playground") }))
    }
}
