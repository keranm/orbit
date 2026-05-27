import SpriteKit
import AppKit

final class LaunchSequenceScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Public interface

    let gameState = GameState()
    var input = InputState()
    var onExit: (() -> Void)?

    // MARK: - Private state

    private var player: PlayerNode!
    private var enemyContainer = SKNode()
    private var enemies: [[EnemyNode?]] = []   // [row][col]
    private var boss: BossNode?
    private var canFirePlayerBullet = true
    private var marchHigh = false
    private var enemyDX: CGFloat = 1           // lateral direction: +1 right, -1 left
    private var lastMarchTime: CFTimeInterval = 0
    private var marchInterval: TimeInterval = 0.75
    private var lastUpdateTime: CFTimeInterval = 0
    private var invincibleUntil: CFTimeInterval = 0
    private var bossTimer: CFTimeInterval = 0
    private var bossEntryComplete = false

    private let playerSpeed: CGFloat = 320      // pt/s
    private let bulletSpeed: CGFloat = 700
    private let enemyBulletSpeed: CGFloat = 360
    private let enemyColSpacing: CGFloat = 80
    private let enemyRowSpacing: CGFloat = 72
    private let enemyDropAmount: CGFloat = 22

    // MARK: - Scene setup

    // Game objects are built in didChangeSize, not didMove.
    // didMove fires before the view has its real frame; didChangeSize fires once
    // the SpriteView has laid out and .resizeFill has snapped the scene to actual size.
    private var didSetupGame = false

    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        // If size is already sensible (set externally), go ahead.
        if size.width > 50 && size.height > 50 {
            setupGame()
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 50, size.height > 50 else { return }

        if let bg = childNode(withName: "background") as? SKSpriteNode {
            bg.size = size
        }

        if !didSetupGame {
            setupGame()
        }
    }

    private func setupGame() {
        guard !didSetupGame else { return }
        didSetupGame = true
        setupBackground()
        setupPlayer()
        buildEnemyFormation()
        scheduleEnemyShooting()
        gameState.phase = .wave1
    }

    private func setupBackground() {
        let bg = SKSpriteNode(imageNamed: "background")
        bg.position = .zero
        bg.zPosition = -100
        bg.size = size
        bg.name = "background"
        addChild(bg)
    }

    private func setupPlayer() {
        player = PlayerNode()
        player.position = CGPoint(x: 0, y: -size.height / 2 + 60)
        player.zPosition = 10
        addChild(player)
    }

    private func buildEnemyFormation(baseInterval: TimeInterval = 0.75) {
        marchInterval = baseInterval
        enemyContainer.removeFromParent()
        enemyContainer = SKNode()
        enemies = []

        let rows = 4
        let cols = 5
        let startY = size.height / 2 - 110
        let startX = -CGFloat(cols - 1) * enemyColSpacing / 2

        for row in 0..<rows {
            var rowArr: [EnemyNode?] = []
            let type = EnemyType(rawValue: row) ?? .chatGPT
            for col in 0..<cols {
                let enemy = EnemyNode(type: type)
                enemy.position = CGPoint(
                    x: startX + CGFloat(col) * enemyColSpacing,
                    y: startY - CGFloat(row) * enemyRowSpacing
                )
                enemy.zPosition = 5
                enemyContainer.addChild(enemy)
                rowArr.append(enemy)
            }
            enemies.append(rowArr)
        }

        addChild(enemyContainer)
        enemyDX = 1
        lastMarchTime = 0
    }

    // MARK: - Update loop

    override func update(_ currentTime: CFTimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : min(currentTime - lastUpdateTime, 0.05)
        lastUpdateTime = currentTime

        guard gameState.phase == .wave1 || gameState.phase == .boss else { return }

        movePlayer(dt: dt)
        removeOffScreenBullets()

        if gameState.phase == .wave1 {
            marchEnemies(currentTime: currentTime)
            checkEnemiesReachedBottom()
        }

        if gameState.phase == .boss {
            updateBoss(currentTime: currentTime, dt: dt)
        }
    }

    // MARK: - Player movement

    private func movePlayer(dt: CFTimeInterval) {
        guard dt > 0 else { return }
        let halfW = size.width / 2 - 36

        if input.leftHeld {
            player.position.x = max(-halfW, player.position.x - playerSpeed * CGFloat(dt))
        }
        if input.rightHeld {
            player.position.x = min(halfW, player.position.x + playerSpeed * CGFloat(dt))
        }
    }

    // MARK: - Firing

    func fireIfReady() {
        guard canFirePlayerBullet,
              gameState.phase == .wave1 || gameState.phase == .boss else {
            if gameState.phase == .gameOver || gameState.phase == .victory {
                onExit?()
            }
            return
        }
        canFirePlayerBullet = false
        let bullet = BulletNode(owner: .player)
        bullet.position = CGPoint(x: player.position.x, y: player.position.y + 40)
        bullet.zPosition = 8
        bullet.physicsBody?.velocity = CGVector(dx: 0, dy: bulletSpeed)
        addChild(bullet)
        GameAudio.shared.laser()
    }

    // MARK: - Enemy marching

    private func marchEnemies(currentTime: CFTimeInterval) {
        guard currentTime - lastMarchTime >= marchInterval else { return }
        lastMarchTime = currentTime

        let aliveCount = aliveEnemyCount
        guard aliveCount > 0 else { return }

        // Speed ramp: goes from 0.75s → 0.1s as enemies die
        let progress = 1.0 - Double(aliveCount) / 20.0
        marchInterval = max(0.10, 0.75 * (1.0 - progress * 0.87))

        // Find the actual bounds of the alive enemy formation
        let halfW = size.width / 2 - 30
        let (minX, maxX) = formationXBounds()

        let stepX: CGFloat = 28
        let newContainerX = enemyContainer.position.x + enemyDX * stepX

        if enemyDX == 1 && (maxX + newContainerX - enemyContainer.position.x) >= halfW {
            // Hit right wall — drop and reverse
            enemyContainer.run(.moveBy(x: 0, y: -enemyDropAmount, duration: 0.08))
            enemyDX = -1
        } else if enemyDX == -1 && (minX + newContainerX - enemyContainer.position.x) <= -halfW {
            // Hit left wall — drop and reverse
            enemyContainer.run(.moveBy(x: 0, y: -enemyDropAmount, duration: 0.08))
            enemyDX = 1
        } else {
            enemyContainer.run(.moveBy(x: enemyDX * stepX, y: 0, duration: 0.08))
        }

        marchHigh = !marchHigh
        GameAudio.shared.march(high: marchHigh)
    }

    private func formationXBounds() -> (CGFloat, CGFloat) {
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        for row in enemies {
            for enemy in row {
                guard let e = enemy, e.isAlive else { continue }
                let worldX = enemyContainer.position.x + e.position.x
                minX = min(minX, worldX)
                maxX = max(maxX, worldX)
            }
        }
        return (minX, maxX)
    }

    private var aliveEnemyCount: Int {
        enemies.flatMap { $0 }.compactMap { $0 }.filter { $0.isAlive }.count
    }

    // MARK: - Enemy shooting

    private func scheduleEnemyShooting() {
        let delay = Double.random(in: 1.2...2.8)
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in
                self?.fireEnemyShot()
                self?.scheduleEnemyShooting()
            }
        ]))
    }

    private func fireEnemyShot() {
        guard gameState.phase == .wave1 else { return }
        // Pick a random alive enemy from the bottom of a random non-empty column
        let colCount = enemies.first?.count ?? 0
        var shooters: [EnemyNode] = []
        for col in 0..<colCount {
            // Bottom-most alive enemy in this column
            for row in stride(from: enemies.count - 1, through: 0, by: -1) {
                if let e = enemies[row][col], e.isAlive {
                    shooters.append(e)
                    break
                }
            }
        }
        guard let shooter = shooters.randomElement() else { return }

        let worldPos = enemyContainer.convert(shooter.position, to: self)
        let bullet = BulletNode(owner: .enemy)
        bullet.position = CGPoint(x: worldPos.x, y: worldPos.y - 28)
        bullet.zPosition = 8
        bullet.physicsBody?.velocity = CGVector(dx: 0, dy: -enemyBulletSpeed)
        addChild(bullet)
    }

    // MARK: - Bottom-line check (game over if enemies reach player)

    private func checkEnemiesReachedBottom() {
        let dangerY = player.position.y + 50
        for row in enemies {
            for enemy in row {
                guard let e = enemy, e.isAlive else { continue }
                let worldY = enemyContainer.position.y + e.position.y
                if worldY <= dangerY {
                    triggerGameOver()
                    return
                }
            }
        }
    }

    // MARK: - Off-screen bullet cleanup

    private func removeOffScreenBullets() {
        let margin = size.height / 2 + 40
        for child in children {
            guard let bullet = child as? BulletNode else { continue }
            if abs(bullet.position.y) > margin { bullet.removeFromParent() }
            if bullet.owner == .player { canFirePlayerBullet = true }
        }
    }

    // MARK: - Collision detection

    func didBegin(_ contact: SKPhysicsContact) {
        let maskA = contact.bodyA.categoryBitMask
        let maskB = contact.bodyB.categoryBitMask

        if (maskA == PhysicsCategory.playerBullet && maskB == PhysicsCategory.enemy) ||
           (maskA == PhysicsCategory.enemy && maskB == PhysicsCategory.playerBullet) {
            let bulletNode  = (maskA == PhysicsCategory.playerBullet ? contact.bodyA : contact.bodyB).node as? BulletNode
            let enemyNode   = (maskA == PhysicsCategory.enemy ? contact.bodyA : contact.bodyB).node
            bulletNode?.removeFromParent()
            canFirePlayerBullet = true
            if let enemy = enemyNode?.parent as? EnemyNode ?? enemyNode as? EnemyNode, enemy.isAlive {
                gameState.score += enemy.type.points
                gameState.highScore = gameState.score
                GameAudio.shared.explosion()
                enemy.die { [weak self] in self?.checkWaveCleared() }
            }
        }

        if (maskA == PhysicsCategory.playerBullet && maskB == PhysicsCategory.boss) ||
           (maskA == PhysicsCategory.boss && maskB == PhysicsCategory.playerBullet) {
            let bulletNode = (maskA == PhysicsCategory.playerBullet ? contact.bodyA : contact.bodyB).node as? BulletNode
            bulletNode?.removeFromParent()
            canFirePlayerBullet = true
            if let boss = boss {
                gameState.score += 25
                gameState.highScore = gameState.score
                GameAudio.shared.bossHit()
                gameState.bossHP = boss.hp - 8
                if boss.takeDamage(8) {
                    triggerVictory()
                }
                // Phase 3 adds boss shooting speed — handled in scheduleBossAttack via attackPhase
            }
        }

        if (maskA == PhysicsCategory.enemyBullet && maskB == PhysicsCategory.player) ||
           (maskA == PhysicsCategory.player && maskB == PhysicsCategory.enemyBullet) {
            let bulletNode = (maskA == PhysicsCategory.enemyBullet ? contact.bodyA : contact.bodyB).node as? BulletNode
            bulletNode?.removeFromParent()
            handlePlayerHit()
        }
    }

    // MARK: - Player hit

    private func handlePlayerHit() {
        guard lastUpdateTime > invincibleUntil else { return }
        invincibleUntil = lastUpdateTime + 2.0  // 2s invincibility

        gameState.lives -= 1
        GameAudio.shared.playerHit()
        player.flash()

        if gameState.lives <= 0 { triggerGameOver() }
    }

    // MARK: - Wave cleared → wave 2 → boss

    private func checkWaveCleared() {
        guard aliveEnemyCount == 0, gameState.phase == .wave1 else { return }
        gameState.phase = .waveCleared

        if gameState.wave < 2 {
            showOverlay(message: "WAVE \(gameState.wave) CLEARED!", color: .systemGreen, duration: 1.6) { [weak self] in
                self?.beginNextWave()
            }
        } else {
            showOverlay(message: "WAVE \(gameState.wave) CLEARED!", color: .systemGreen, duration: 1.6) { [weak self] in
                self?.beginBossIntro()
            }
        }
    }

    private func beginNextWave() {
        gameState.wave += 1
        // Clear leftover enemy bullets
        children.filter { ($0 as? BulletNode)?.owner == .enemy }.forEach { $0.removeFromParent() }
        // Wave 2 starts noticeably faster (0.42s base vs 0.75s for wave 1)
        buildEnemyFormation(baseInterval: 0.42)
        scheduleEnemyShooting()
        gameState.phase = .wave1
    }

    private func beginBossIntro() {
        gameState.phase = .bossIntro
        removeAction(forKey: "enemyShooting")
        // Remove any remaining enemy bullets
        children.filter { ($0 as? BulletNode)?.owner == .enemy }.forEach { $0.removeFromParent() }

        GameAudio.shared.bossIntro()

        let bossNode = BossNode()
        bossNode.position = CGPoint(x: 0, y: size.height / 2 + 140)
        bossNode.zPosition = 5
        addChild(bossNode)
        boss = bossNode

        // Slide in from top
        bossNode.run(.sequence([
            .moveTo(y: size.height / 2 - 160, duration: 1.2),
            .run { [weak self] in
                self?.gameState.phase = .boss
                self?.gameState.bossHP = 100
                self?.scheduleBossAttack()
                self?.scheduleLightningAttack()
            }
        ]))
    }

    // MARK: - Boss fight

    private func updateBoss(currentTime: CFTimeInterval, dt: CFTimeInterval) {
        guard let boss = boss else { return }
        bossTimer += dt
        // Sinusoidal drift
        let targetX = sin(bossTimer * 0.4) * (size.width / 2 - 160)
        boss.position.x = targetX
    }

    private func scheduleBossAttack() {
        guard let boss = boss, gameState.phase == .boss else { return }
        let phase = boss.attackPhase
        let interval: Double = phase == 1 ? 1.4 : phase == 2 ? 0.75 : 0.4

        boss.run(.sequence([
            .wait(forDuration: interval),
            .run { [weak self] in
                self?.fireBossAttack()
                self?.scheduleBossAttack()
            }
        ]), withKey: "bossAttack")
    }

    private func fireBossAttack() {
        guard let boss = boss, gameState.phase == .boss else { return }
        let phase = boss.attackPhase
        let origin = CGPoint(x: boss.position.x, y: boss.position.y - boss.size.height / 2 + 10)

        switch phase {
        case 1:
            spawnEnemyBullet(from: origin, direction: CGVector(dx: 0, dy: -enemyBulletSpeed))
        case 2:
            // 3-way spread
            for angle in [-0.3, 0.0, 0.3] {
                let dx = sin(angle) * enemyBulletSpeed
                let dy = -cos(angle) * enemyBulletSpeed
                spawnEnemyBullet(from: origin, direction: CGVector(dx: dx, dy: dy))
            }
        default:
            // Dense 5-way spray + occasional straight shot
            for i in -2...2 {
                let angle = Double(i) * 0.22
                let dx = sin(angle) * enemyBulletSpeed
                let dy = -cos(angle) * enemyBulletSpeed
                spawnEnemyBullet(from: origin, direction: CGVector(dx: dx, dy: dy))
            }
            // Lightning bolt (fast straight shot)
            if Int.random(in: 0...2) == 0 {
                spawnEnemyBullet(from: origin, direction: CGVector(dx: 0, dy: -enemyBulletSpeed * 1.8))
            }
        }
    }

    private func spawnEnemyBullet(from pos: CGPoint, direction: CGVector) {
        let bullet = BulletNode(owner: .enemy)
        bullet.position = pos
        bullet.zPosition = 8
        bullet.physicsBody?.velocity = direction
        addChild(bullet)
    }

    // MARK: - Lightning attack (periodic, independent of regular boss attacks)

    private func scheduleLightningAttack() {
        guard gameState.phase == .boss else { return }
        let delay = Double.random(in: 5.0...9.0)
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in
                guard self?.gameState.phase == .boss else { return }
                self?.fireLightning()
                self?.scheduleLightningAttack()
            }
        ]), withKey: "lightningAttack")
    }

    private func fireLightning() {
        guard let boss = boss else { return }

        // Charge-up flash on the boss — brief white → purple warning
        boss.run(.sequence([
            .wait(forDuration: 0.15),
            .colorize(with: NSColor(red: 0.85, green: 0.6, blue: 1.0, alpha: 1), colorBlendFactor: 0.9, duration: 0.12),
            .colorize(with: .white, colorBlendFactor: 1.0, duration: 0.08),
            .colorize(withColorBlendFactor: 0.0, duration: 0.18)
        ]))

        GameAudio.shared.lightning()

        // Fire after brief charge delay so the flash is visible first
        let origin = CGPoint(x: boss.position.x, y: boss.position.y - boss.size.height / 2 + 10)
        run(.sequence([
            .wait(forDuration: 0.25),
            .run { [weak self] in
                guard let self else { return }
                // Wide bright bolt — visually distinct from regular bullets
                let bolt = SKSpriteNode(color: NSColor(red: 0.75, green: 0.2, blue: 1.0, alpha: 1.0),
                                        size: CGSize(width: 14, height: 40))
                bolt.position = origin
                bolt.zPosition = 9
                // Glow effect
                let glow = SKSpriteNode(color: NSColor(red: 0.9, green: 0.6, blue: 1.0, alpha: 0.35),
                                        size: CGSize(width: 30, height: 46))
                glow.zPosition = -1
                bolt.addChild(glow)

                bolt.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 14, height: 40))
                bolt.physicsBody?.isDynamic = true
                bolt.physicsBody?.affectedByGravity = false
                bolt.physicsBody?.linearDamping = 0
                bolt.physicsBody?.categoryBitMask    = PhysicsCategory.enemyBullet
                bolt.physicsBody?.contactTestBitMask = PhysicsCategory.player
                bolt.physicsBody?.collisionBitMask   = 0
                bolt.physicsBody?.velocity = CGVector(dx: 0, dy: -self.enemyBulletSpeed * 2.4)
                self.addChild(bolt)
            }
        ]))
    }

    // MARK: - End states

    private func triggerGameOver() {
        guard gameState.phase != .gameOver else { return }
        gameState.phase = .gameOver
        player.physicsBody = nil
        GameAudio.shared.gameOver()
        showOverlay(message: "GAME OVER", color: .systemRed, subtitle: "Press any key to exit", duration: 999) { }
    }

    private func triggerVictory() {
        guard gameState.phase != .victory else { return }
        gameState.phase = .victory
        boss?.removeFromParent()
        boss = nil
        GameAudio.shared.victory()
        showOverlay(message: "YOU WIN!", color: .systemGreen,
                    subtitle: "The Cloud Overlord is defeated.\nAI stays private. 🛸\nPress any key to exit", duration: 999) { }
    }

    // MARK: - Overlay helper

    private func showOverlay(message: String, color: NSColor, subtitle: String? = nil, duration: TimeInterval, completion: @escaping () -> Void) {
        let overlay = SKNode()
        overlay.zPosition = 50

        // Background panel
        let panel = SKShapeNode(rectOf: CGSize(width: 380, height: subtitle != nil ? 140 : 90), cornerRadius: 14)
        panel.fillColor = NSColor(white: 0, alpha: 0.72)
        panel.strokeColor = color.withAlphaComponent(0.6)
        panel.lineWidth = 2
        overlay.addChild(panel)

        // Main message
        let label = SKLabelNode(text: message)
        label.fontName = "SFMono-Bold"
        label.fontSize = 28
        label.fontColor = color
        label.position = CGPoint(x: 0, y: subtitle != nil ? 28 : 0)
        label.verticalAlignmentMode = .center
        overlay.addChild(label)

        // Subtitle
        if let sub = subtitle {
            let subLabel = SKLabelNode(text: sub)
            subLabel.fontName = "SFMono-Regular"
            subLabel.fontSize = 12
            subLabel.fontColor = NSColor(white: 0.8, alpha: 1)
            subLabel.position = CGPoint(x: 0, y: -28)
            subLabel.verticalAlignmentMode = .center
            subLabel.numberOfLines = 3
            subLabel.preferredMaxLayoutWidth = 340
            overlay.addChild(subLabel)
        }

        addChild(overlay)

        if duration < 999 {
            overlay.run(.sequence([
                .wait(forDuration: duration),
                .fadeOut(withDuration: 0.3),
                .removeFromParent(),
                .run(completion)
            ]))
        }
    }

    // MARK: - Exit

    func requestExit() {
        onExit?()
    }
}
