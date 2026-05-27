import SpriteKit

final class BossNode: SKSpriteNode {
    private(set) var hp: Int
    private let maxHP: Int

    init(hp: Int = 100, size: CGSize = CGSize(width: 280, height: 220)) {
        self.hp = hp
        self.maxHP = hp
        let tex = SKTexture(imageNamed: "bigBoss")
        super.init(texture: tex, color: .clear, size: size)

        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 0.6, height: size.height * 0.55))
        physicsBody?.isDynamic = false
        physicsBody?.affectedByGravity = false
        physicsBody?.categoryBitMask    = PhysicsCategory.boss
        physicsBody?.contactTestBitMask = PhysicsCategory.playerBullet
        physicsBody?.collisionBitMask   = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Returns true if boss is dead.
    @discardableResult
    func takeDamage(_ amount: Int = 8) -> Bool {
        hp = max(0, hp - amount)
        run(.sequence([
            .colorize(with: .systemRed, colorBlendFactor: 0.9, duration: 0.05),
            .colorize(withColorBlendFactor: 0.0, duration: 0.12)
        ]))
        return hp <= 0
    }

    var hpPercent: Double { Double(hp) / Double(maxHP) }

    /// Current attack phase based on HP.
    var attackPhase: Int {
        if hp > 50 { return 1 }
        if hp > 25 { return 2 }
        return 3
    }
}
