import SpriteKit

final class PlayerNode: SKSpriteNode {
    static let nodeSize = CGSize(width: 70, height: 70)

    init() {
        let tex = SKTexture(imageNamed: "shuttle")
        super.init(texture: tex, color: .clear, size: PlayerNode.nodeSize)
        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 52, height: 60))
        physicsBody?.isDynamic = false
        physicsBody?.affectedByGravity = false
        physicsBody?.categoryBitMask    = PhysicsCategory.player
        physicsBody?.contactTestBitMask = PhysicsCategory.enemyBullet
        physicsBody?.collisionBitMask   = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    func flash() {
        run(.sequence([
            .repeat(.sequence([
                .fadeAlpha(to: 0.2, duration: 0.1),
                .fadeAlpha(to: 1.0, duration: 0.1)
            ]), count: 5)
        ]))
    }
}
