//! Simple game module demonstrating ECS usage
//!
//! This module shows a basic game with:
//! - Components: Position, Velocity, Health, Player, Enemy
//! - Systems: movement, combat
//! - Game world management

const std = @import("std");
const ecs = @import("zig-ecs");

// =============================================================================
// Components
// =============================================================================

pub const Position = struct {
    x: f32,
    y: f32,

    pub fn distance(self: Position, other: Position) f32 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return @sqrt(dx * dx + dy * dy);
    }
};

pub const Velocity = struct {
    dx: f32,
    dy: f32,
};

pub const Health = struct {
    current: i32,
    max: i32,

    pub fn isAlive(self: Health) bool {
        return self.current > 0;
    }

    pub fn isDead(self: Health) bool {
        return !self.isAlive();
    }

    pub fn damage(self: *Health, amount: i32) void {
        self.current = @max(0, self.current - amount);
    }

    pub fn heal(self: *Health, amount: i32) void {
        self.current = @min(self.max, self.current + amount);
    }
};

pub const Player = struct {
    name: []const u8,
};

pub const Enemy = struct {
    enemy_type: EnemyType,
};

pub const EnemyType = enum {
    slime,
    goblin,
    dragon,
};

// =============================================================================
// Game World
// =============================================================================

pub const GameWorld = struct {
    registry: *ecs.Registry,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !GameWorld {
        const registry = try allocator.create(ecs.Registry);
        registry.* = ecs.Registry.init(allocator);
        return .{
            .registry = registry,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GameWorld) void {
        self.registry.deinit();
        self.allocator.destroy(self.registry);
    }

    /// Create a player entity
    pub fn createPlayer(self: *GameWorld, name: []const u8, x: f32, y: f32) u32 {
        const entity = self.registry.create();
        self.registry.add(entity, Position{ .x = x, .y = y });
        self.registry.add(entity, Velocity{ .dx = 0, .dy = 0 });
        self.registry.add(entity, Health{ .current = 100, .max = 100 });
        self.registry.add(entity, Player{ .name = name });
        return entity;
    }

    /// Create an enemy entity
    pub fn createEnemy(self: *GameWorld, enemy_type: EnemyType, x: f32, y: f32) u32 {
        const entity = self.registry.create();
        self.registry.add(entity, Position{ .x = x, .y = y });
        self.registry.add(entity, Velocity{ .dx = 0, .dy = 0 });

        const health = switch (enemy_type) {
            .slime => Health{ .current = 20, .max = 20 },
            .goblin => Health{ .current = 50, .max = 50 },
            .dragon => Health{ .current = 200, .max = 200 },
        };
        self.registry.add(entity, health);
        self.registry.add(entity, Enemy{ .enemy_type = enemy_type });
        return entity;
    }

    /// Movement system - update positions based on velocities
    pub fn updateMovement(self: *GameWorld, dt: f32) void {
        var view = self.registry.view(.{ Position, Velocity }, .{});
        var iter = view.iterator();

        while (iter.next()) |entity| {
            const pos = self.registry.getConst(Position, entity);
            const vel = self.registry.getConst(Velocity, entity);

            self.registry.replace(entity, Position{
                .x = pos.x + vel.dx * dt,
                .y = pos.y + vel.dy * dt,
            });
        }
    }

    /// Count entities with a specific component
    pub fn count(self: *GameWorld, comptime T: type) usize {
        var view = self.registry.view(.{T}, .{});
        var iter = view.iterator();
        var c: usize = 0;
        while (iter.next()) |_| {
            c += 1;
        }
        return c;
    }

    /// Get all entities with a component
    pub fn getEntitiesWithComponent(self: *GameWorld, comptime T: type, buffer: []u32) []u32 {
        var view = self.registry.view(.{T}, .{});
        var iter = view.iterator();
        var i: usize = 0;
        while (iter.next()) |entity| {
            if (i >= buffer.len) break;
            buffer[i] = entity;
            i += 1;
        }
        return buffer[0..i];
    }
};

// =============================================================================
// Game Logic
// =============================================================================

/// Apply damage to an entity
pub fn dealDamage(registry: *ecs.Registry, entity: u32, amount: i32) bool {
    if (!registry.has(Health, entity)) return false;

    var health = registry.get(Health, entity);
    health.damage(amount);
    registry.replace(entity, health.*);

    return health.isAlive();
}

/// Heal an entity
pub fn healEntity(registry: *ecs.Registry, entity: u32, amount: i32) void {
    if (!registry.has(Health, entity)) return;

    var health = registry.get(Health, entity);
    health.heal(amount);
    registry.replace(entity, health.*);
}
