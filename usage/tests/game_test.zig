//! Game tests using ZSpec with ECS integration
//!
//! This demonstrates real-world usage of zspec and zspec-ecs for testing
//! an ECS-based game.

const std = @import("std");
const zspec = @import("zspec");
const ecs = @import("zig-ecs");
const ECS = @import("zspec-ecs");
const game = @import("game");

const expect = zspec.expect;
const Factory = zspec.Factory;

test {
    zspec.runAll(@This());
}

// =============================================================================
// Component Factories
// =============================================================================

const PositionFactory = Factory.define(game.Position, .{
    .x = 0.0,
    .y = 0.0,
});

const VelocityFactory = Factory.define(game.Velocity, .{
    .dx = 0.0,
    .dy = 0.0,
});

const HealthFactory = Factory.define(game.Health, .{
    .current = 100,
    .max = 100,
});

const PlayerFactory = Factory.define(game.Player, .{
    .name = "Player",
});

const EnemyFactory = Factory.define(game.Enemy, .{
    .enemy_type = .slime,
});

// Factory traits for common entity archetypes
const PlayerSpawnFactory = PositionFactory.trait(.{ .x = 0.0, .y = 0.0 });
const EnemySpawnFactory = PositionFactory.trait(.{ .x = 100.0, .y = 100.0 });
const DamagedHealthFactory = HealthFactory.trait(.{ .current = 50 });
const LowHealthFactory = HealthFactory.trait(.{ .current = 10 });
const MovingVelocityFactory = VelocityFactory.trait(.{ .dx = 5.0, .dy = 3.0 });

// =============================================================================
// Component Tests
// =============================================================================

pub const ComponentTests = struct {
    test "Position calculates distance correctly" {
        const pos1 = game.Position{ .x = 0, .y = 0 };
        const pos2 = game.Position{ .x = 3, .y = 4 };
        const dist = pos1.distance(pos2);
        try expect.equal(dist, 5.0);
    }

    test "Health damage reduces current health" {
        var health = game.Health{ .current = 100, .max = 100 };
        health.damage(30);
        try expect.equal(health.current, 70);
    }

    test "Health damage cannot go below zero" {
        var health = game.Health{ .current = 20, .max = 100 };
        health.damage(50);
        try expect.equal(health.current, 0);
        try expect.toBeTrue(health.isDead());
    }

    test "Health heal increases current health" {
        var health = game.Health{ .current = 50, .max = 100 };
        health.heal(30);
        try expect.equal(health.current, 80);
    }

    test "Health heal cannot exceed max" {
        var health = game.Health{ .current = 90, .max = 100 };
        health.heal(50);
        try expect.equal(health.current, 100);
    }
};

// =============================================================================
// Entity Creation Tests with ECS Integration
// =============================================================================

pub const EntityCreationTests = struct {
    var registry: *ecs.Registry = undefined;

    test "tests:beforeAll" {
        Factory.resetSequences();
    }

    test "tests:before" {
        registry = ECS.createRegistry(ecs.Registry);
    }

    test "tests:after" {
        ECS.destroyRegistry(registry);
    }

    test "creates player entity with all components" {
        const player = ECS.createEntity(registry, .{
            .position = PlayerSpawnFactory.build(.{}),
            .velocity = VelocityFactory.build(.{}),
            .health = HealthFactory.build(.{}),
            .player = PlayerFactory.build(.{}),
        });

        try expect.toBeTrue(registry.has(game.Position, player));
        try expect.toBeTrue(registry.has(game.Velocity, player));
        try expect.toBeTrue(registry.has(game.Health, player));
        try expect.toBeTrue(registry.has(game.Player, player));

        const pos = registry.getConst(game.Position, player);
        try expect.equal(pos.x, 0.0);
        try expect.equal(pos.y, 0.0);
    }

    test "creates enemy entity with position and health" {
        const enemy = ECS.createEntity(registry, .{
            .position = EnemySpawnFactory.build(.{}),
            .health = HealthFactory.build(.{ .current = 50, .max = 50 }),
            .enemy = EnemyFactory.build(.{ .enemy_type = .goblin }),
        });

        try expect.toBeTrue(registry.has(game.Position, enemy));
        try expect.toBeTrue(registry.has(game.Health, enemy));
        try expect.toBeTrue(registry.has(game.Enemy, enemy));

        const health = registry.getConst(game.Health, enemy);
        try expect.equal(health.current, 50);

        const enemy_comp = registry.getConst(game.Enemy, enemy);
        try expect.equal(enemy_comp.enemy_type, .goblin);
    }

    test "creates multiple enemies in batch" {
        const enemies = ECS.createEntities(registry, 5, .{
            .position = EnemySpawnFactory.build(.{}),
            .health = HealthFactory.build(.{ .current = 20, .max = 20 }),
            .enemy = EnemyFactory.build(.{ .enemy_type = .slime }),
        });
        defer std.testing.allocator.free(enemies);

        try expect.toHaveLength(enemies, 5);

        for (enemies) |enemy| {
            try expect.toBeTrue(registry.has(game.Position, enemy));
            try expect.toBeTrue(registry.has(game.Health, enemy));

            const health = registry.getConst(game.Health, enemy);
            try expect.equal(health.current, 20);
        }
    }

    test "uses factory traits for damaged entities" {
        const damaged_enemy = ECS.createEntity(registry, .{
            .position = EnemySpawnFactory.build(.{}),
            .health = DamagedHealthFactory.build(.{}),
            .enemy = EnemyFactory.build(.{}),
        });

        const health = registry.getConst(game.Health, damaged_enemy);
        try expect.equal(health.current, 50);
        try expect.toBeTrue(health.isAlive());
    }
};

// =============================================================================
// Game World Tests
// =============================================================================

pub const GameWorldTests = struct {
    var world: game.GameWorld = undefined;

    test "tests:before" {
        Factory.resetSequences();
        world = game.GameWorld.init(std.testing.allocator) catch unreachable;
    }

    test "tests:after" {
        world.deinit();
    }

    test "creates player through game world" {
        const player = world.createPlayer("Hero", 10, 20);

        try expect.toBeTrue(world.registry.has(game.Player, player));
        try expect.toBeTrue(world.registry.has(game.Position, player));
        try expect.toBeTrue(world.registry.has(game.Health, player));

        const pos = world.registry.getConst(game.Position, player);
        try expect.equal(pos.x, 10.0);
        try expect.equal(pos.y, 20.0);

        const player_comp = world.registry.getConst(game.Player, player);
        try expect.toBeTrue(std.mem.eql(u8, player_comp.name, "Hero"));
    }

    test "creates different enemy types" {
        const slime = world.createEnemy(.slime, 50, 50);
        const goblin = world.createEnemy(.goblin, 100, 100);
        const dragon = world.createEnemy(.dragon, 200, 200);

        const slime_health = world.registry.getConst(game.Health, slime);
        const goblin_health = world.registry.getConst(game.Health, goblin);
        const dragon_health = world.registry.getConst(game.Health, dragon);

        try expect.equal(slime_health.max, 20);
        try expect.equal(goblin_health.max, 50);
        try expect.equal(dragon_health.max, 200);
    }

    test "counts entities with component" {
        _ = world.createPlayer("P1", 0, 0);
        _ = world.createPlayer("P2", 10, 10);
        _ = world.createEnemy(.slime, 50, 50);

        const player_count = world.count(game.Player);
        const enemy_count = world.count(game.Enemy);
        const health_count = world.count(game.Health);

        try expect.equal(player_count, 2);
        try expect.equal(enemy_count, 1);
        try expect.equal(health_count, 3); // all entities have health
    }

    test "movement system updates positions" {
        const entity = ECS.createEntity(world.registry, .{
            .position = PositionFactory.build(.{ .x = 0, .y = 0 }),
            .velocity = VelocityFactory.build(.{ .dx = 10, .dy = 5 }),
        });

        world.updateMovement(1.0);

        const pos = world.registry.getConst(game.Position, entity);
        try expect.equal(pos.x, 10.0);
        try expect.equal(pos.y, 5.0);
    }

    test "movement system with multiple entities" {
        _ = ECS.createEntity(world.registry, .{
            .position = PositionFactory.build(.{ .x = 0, .y = 0 }),
            .velocity = MovingVelocityFactory.build(.{}),
        });

        _ = ECS.createEntity(world.registry, .{
            .position = PositionFactory.build(.{ .x = 100, .y = 100 }),
            .velocity = VelocityFactory.build(.{ .dx = -2, .dy = -2 }),
        });

        world.updateMovement(1.0);

        // Both entities should have moved
        const moving_count = world.count(game.Position);
        try expect.equal(moving_count, 2);
    }
};

// =============================================================================
// Combat System Tests
// =============================================================================

pub const CombatTests = struct {
    var registry: *ecs.Registry = undefined;

    test "tests:before" {
        Factory.resetSequences();
        registry = ECS.createRegistry(ecs.Registry);
    }

    test "tests:after" {
        ECS.destroyRegistry(registry);
    }

    test "dealing damage reduces health" {
        const enemy = ECS.createEntity(registry, .{
            .health = HealthFactory.build(.{}),
        });

        const is_alive = game.dealDamage(registry, enemy, 30);

        try expect.toBeTrue(is_alive);

        const health = registry.getConst(game.Health, enemy);
        try expect.equal(health.current, 70);
    }

    test "dealing fatal damage kills entity" {
        const enemy = ECS.createEntity(registry, .{
            .health = LowHealthFactory.build(.{}),
        });

        const is_alive = game.dealDamage(registry, enemy, 50);

        try expect.toBeFalse(is_alive);

        const health = registry.getConst(game.Health, enemy);
        try expect.equal(health.current, 0);
        try expect.toBeTrue(health.isDead());
    }

    test "healing increases health" {
        const entity = ECS.createEntity(registry, .{
            .health = DamagedHealthFactory.build(.{}),
        });

        game.healEntity(registry, entity, 30);

        const health = registry.getConst(game.Health, entity);
        try expect.equal(health.current, 80);
    }

    test "healing does not exceed max health" {
        const entity = ECS.createEntity(registry, .{
            .health = HealthFactory.build(.{ .current = 90, .max = 100 }),
        });

        game.healEntity(registry, entity, 50);

        const health = registry.getConst(game.Health, entity);
        try expect.equal(health.current, 100);
    }
};

// =============================================================================
// Integration Tests - Realistic Game Scenarios
// =============================================================================

pub const IntegrationTests = struct {
    var world: game.GameWorld = undefined;

    test "tests:before" {
        Factory.resetSequences();
        world = game.GameWorld.init(std.testing.allocator) catch unreachable;
    }

    test "tests:after" {
        world.deinit();
    }

    test "player fights slime" {
        const player = world.createPlayer("Hero", 0, 0);
        const slime = world.createEnemy(.slime, 5, 5);

        // Player attacks slime
        _ = game.dealDamage(world.registry, slime, 15);

        const slime_health = world.registry.getConst(game.Health, slime);
        try expect.equal(slime_health.current, 5);
        try expect.toBeTrue(slime_health.isAlive());

        // Slime attacks player
        _ = game.dealDamage(world.registry, player, 10);

        const player_health = world.registry.getConst(game.Health, player);
        try expect.equal(player_health.current, 90);
    }

    test "spawning multiple enemy waves" {
        const player = world.createPlayer("Hero", 0, 0);

        // Wave 1: Slimes
        const slimes = ECS.createEntities(world.registry, 3, .{
            .position = EnemySpawnFactory.build(.{}),
            .health = HealthFactory.build(.{ .current = 20, .max = 20 }),
            .enemy = EnemyFactory.build(.{ .enemy_type = .slime }),
        });
        defer std.testing.allocator.free(slimes);

        // Wave 2: Goblins
        const goblins = ECS.createEntities(world.registry, 2, .{
            .position = PositionFactory.build(.{ .x = 150, .y = 150 }),
            .health = HealthFactory.build(.{ .current = 50, .max = 50 }),
            .enemy = EnemyFactory.build(.{ .enemy_type = .goblin }),
        });
        defer std.testing.allocator.free(goblins);

        const total_enemies = world.count(game.Enemy);
        try expect.equal(total_enemies, 5);

        const total_entities = world.count(game.Health);
        try expect.equal(total_entities, 6); // 1 player + 5 enemies
        _ = player;
    }

    test "player movement and position tracking" {
        const player = world.createPlayer("Hero", 0, 0);

        // Set velocity
        world.registry.replace(player, game.Velocity{ .dx = 10, .dy = 0 });

        // Update 3 frames
        world.updateMovement(1.0);
        world.updateMovement(1.0);
        world.updateMovement(1.0);

        const pos = world.registry.getConst(game.Position, player);
        try expect.equal(pos.x, 30.0);
        try expect.equal(pos.y, 0.0);
    }
};
