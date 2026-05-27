import Foundation

enum GamePhase: Equatable {
    case waiting        // pre-start / between lives
    case wave1          // Space Invaders grid
    case waveCleared    // brief celebration overlay
    case bossIntro      // boss slide-in animation
    case boss           // boss fight
    case victory
    case gameOver
}

@Observable
final class GameState {
    var score: Int = 0
    var lives: Int = 3
    var wave: Int = 1
    var bossHP: Int = 100
    var phase: GamePhase = .waiting

    var highScore: Int {
        get { UserDefaults.standard.integer(forKey: "launchSequenceHighScore") }
        set {
            if newValue > UserDefaults.standard.integer(forKey: "launchSequenceHighScore") {
                UserDefaults.standard.set(newValue, forKey: "launchSequenceHighScore")
            }
        }
    }

    var bossHPPercent: Double { max(0, Double(bossHP) / 100.0) }
}

struct InputState {
    var leftHeld = false
    var rightHeld = false
}
