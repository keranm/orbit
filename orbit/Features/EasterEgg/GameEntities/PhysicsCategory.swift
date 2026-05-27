import Foundation

enum PhysicsCategory {
    static let player:       UInt32 = 0x1
    static let enemy:        UInt32 = 0x2
    static let boss:         UInt32 = 0x4
    static let playerBullet: UInt32 = 0x8
    static let enemyBullet:  UInt32 = 0x10
}
