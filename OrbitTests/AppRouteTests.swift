import XCTest
@testable import orbit

final class AppRouteTests: XCTestCase {

    func test_route_new_chat_is_hashable() {
        XCTAssertEqual(AppRoute.newChat, AppRoute.newChat)
    }

    func test_route_explore_is_hashable() {
        XCTAssertEqual(AppRoute.explore, AppRoute.explore)
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

    func test_all_routes_are_distinct() {
        let id = UUID()
        let routes: [AppRoute] = [.newChat, .chat(id: id), .agents, .agentBuilder(id: id), .explore, .prompts, .models, .settings]
        let set = Set(routes)
        XCTAssertEqual(set.count, 8)
    }

    func test_all_cases_exhaustive() {
        var count = 0
        let routes: [AppRoute] = [.newChat, .chat(id: UUID()), .agents, .agentBuilder(id: UUID()), .explore, .prompts, .models, .settings]
        for route in routes {
            switch route {
            case .newChat, .chat, .agents, .agentBuilder, .explore, .prompts, .models, .settings:
                count += 1
            }
        }
        XCTAssertEqual(count, 8)
    }

    func test_agents_route_is_hashable() {
        XCTAssertEqual(AppRoute.agents, AppRoute.agents)
    }

    func test_agentBuilder_equality_by_id() {
        let id = UUID()
        XCTAssertEqual(AppRoute.agentBuilder(id: id), AppRoute.agentBuilder(id: id))
    }

    func test_agentBuilder_inequality_across_ids() {
        XCTAssertNotEqual(AppRoute.agentBuilder(id: UUID()), AppRoute.agentBuilder(id: UUID()))
    }

    func test_route_usable_as_dictionary_key() {
        var map: [AppRoute: String] = [:]
        map[.newChat]    = "newChat"
        map[.explore]    = "explore"
        map[.prompts]    = "prompts"
        map[.models]     = "models"
        map[.settings]   = "settings"
        map[.agents]     = "agents"
        let id = UUID()
        map[.chat(id: id)]         = "chat"
        map[.agentBuilder(id: id)] = "agentBuilder"
        XCTAssertEqual(map.count, 8)
    }
}
