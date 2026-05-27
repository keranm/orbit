import SpriteKit

enum EnemyType: Int, CaseIterable {
    case xai = 0, gemini, claude, chatGPT

    var textureName: String {
        switch self {
        case .xai:    return "xai"
        case .gemini: return "gemini"
        case .claude: return "claude"
        case .chatGPT: return "chatGPT"
        }
    }

    var points: Int {
        switch self {
        case .xai:    return 30
        case .gemini: return 20
        case .claude: return 15
        case .chatGPT: return 10
        }
    }
}

final class EnemyNode: SKNode {
    let type: EnemyType
    var isAlive = true
    private let sprite: SKSpriteNode
    private var healthBar: SKShapeNode

    init(type: EnemyType, size: CGFloat = 44) {
        self.type = type
        let tex = SKTexture(imageNamed: type.textureName)
        sprite = SKSpriteNode(texture: tex, color: .clear, size: CGSize(width: size, height: size))

        let bar = SKShapeNode(rectOf: CGSize(width: size, height: 3), cornerRadius: 1)
        bar.fillColor = .systemRed
        bar.strokeColor = .clear
        bar.position = CGPoint(x: 0, y: -size / 2 - 5)
        healthBar = bar

        super.init()
        addChild(sprite)
        addChild(bar)

        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size, height: size))
        physicsBody?.isDynamic = false
        physicsBody?.affectedByGravity = false
        physicsBody?.categoryBitMask    = PhysicsCategory.enemy
        physicsBody?.contactTestBitMask = PhysicsCategory.playerBullet
        physicsBody?.collisionBitMask   = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    func die(completion: @escaping () -> Void) {
        isAlive = false
        physicsBody = nil
        run(.sequence([
            .group([
                .scale(to: 1.5, duration: 0.12),
                .fadeOut(withDuration: 0.12)
            ]),
            .removeFromParent(),
            .run(completion)
        ]))
    }
}
