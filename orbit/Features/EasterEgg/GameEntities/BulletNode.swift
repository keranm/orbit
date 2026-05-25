import SpriteKit

enum BulletOwner { case player, enemy }

final class BulletNode: SKSpriteNode {
    let owner: BulletOwner

    init(owner: BulletOwner) {
        self.owner = owner
        let color: NSColor = owner == .player ? NSColor(red: 0.27, green: 0.6, blue: 1.0, alpha: 1) : NSColor(red: 1, green: 0.55, blue: 0.1, alpha: 1)
        super.init(texture: nil, color: color, size: CGSize(width: 4, height: 18))
        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 4, height: 18))
        physicsBody?.isDynamic = true
        physicsBody?.affectedByGravity = false
        physicsBody?.linearDamping = 0
        physicsBody?.angularDamping = 0
        physicsBody?.categoryBitMask    = owner == .player ? PhysicsCategory.playerBullet : PhysicsCategory.enemyBullet
        physicsBody?.contactTestBitMask = owner == .player ? (PhysicsCategory.enemy | PhysicsCategory.boss) : PhysicsCategory.player
        physicsBody?.collisionBitMask   = 0
    }

    required init?(coder: NSCoder) { fatalError() }
}
