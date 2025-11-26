//! ECS Integration Example
//!
//! Demonstrates how to use ZSpec with zig-ecs (https://github.com/prime31/zig-ecs)
//! for testing Entity Component Systems.
//!
//! Features:
//! - Factory-based component creation
//! - Registry setup/teardown in before/after hooks
//! - Creating entities with multiple components
//! - Batch entity creation
//! - Using Let for memoized registry
//! - ComponentFactory pattern
//!
//! NOTE: This example shows the integration pattern but does not actually
//! import zig-ecs since it's not a dependency. To use this pattern:
//!
//! 1. Add zspec and zig-ecs to your build.zig.zon:
//!    .dependencies = .{
//!        .zspec = .{
//!            .url = "https://github.com/apotema/zspec/archive/refs/heads/main.tar.gz",
//!            .hash = "...",
//!        },
//!        .ecs = .{
//!            .url = "https://github.com/prime31/zig-ecs/archive/refs/heads/master.tar.gz",
//!            .hash = "...",
//!        },
//!    },
//!
//! 2. In your build.zig, get both modules:
//!    const zspec_dep = b.dependency("zspec", .{ .target = target, .optimize = optimize });
//!    const zspec_mod = zspec_dep.module("zspec");
//!    const zspec_ecs_mod = zspec_dep.module("zspec-ecs");  // Optional ECS integration
//!    const ecs_dep = b.dependency("ecs", .{ .target = target, .optimize = optimize });
//!
//! 3. Add to your build.zig test imports:
//!    .imports = &.{
//!        .{ .name = "zspec", .module = zspec_mod },
//!        .{ .name = "zspec-ecs", .module = zspec_ecs_mod },
//!        .{ .name = "zig-ecs", .module = ecs_dep.module("zig-ecs") },
//!    },
//!
//! 4. Use the patterns shown below in your tests

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const Factory = zspec.Factory;

// Import the optional ECS integration module
// In your actual code: const ECS = @import("zspec-ecs");
// For this example, we use a mock since zig-ecs isn't a dependency
const ECS = struct {
    pub usingnamespace @import("../src/integrations/ecs.zig");
};

// Uncomment when you have zig-ecs as a dependency:
// const ecs = @import("zig-ecs");

test {
    zspec.runAll(@This());
}

// =============================================================================
// Mock ECS Types (for demonstration purposes)
// In real usage, these would come from @import("zig-ecs")
// =============================================================================

const MockRegistry = struct {
    allocator: std.mem.Allocator,
    next_entity: u32 = 0,
    positions: std.AutoHashMap(u32, Position) = undefined,
    velocities: std.AutoHashMap(u32, Velocity) = undefined,
    healths: std.AutoHashMap(u32, Health) = undefined,

    pub fn init(allocator: std.mem.Allocator) MockRegistry {
        return .{
            .allocator = allocator,
            .positions = std.AutoHashMap(u32, Position).init(allocator),
            .velocities = std.AutoHashMap(u32, Velocity).init(allocator),
            .healths = std.AutoHashMap(u32, Health).init(allocator),
        };
    }

    pub fn deinit(self: *MockRegistry) void {
        self.positions.deinit();
        self.velocities.deinit();
        self.healths.deinit();
    }

    pub fn create(self: *MockRegistry) u32 {
        const entity = self.next_entity;
        self.next_entity += 1;
        return entity;
    }

    pub fn add(self: *MockRegistry, entity: u32, component: anytype) void {
        const T = @TypeOf(component);
        if (T == Position) {
            self.positions.put(entity, component) catch unreachable;
        } else if (T == Velocity) {
            self.velocities.put(entity, component) catch unreachable;
        } else if (T == Health) {
            self.healths.put(entity, component) catch unreachable;
        }
    }

    pub fn get(self: *MockRegistry, comptime T: type, entity: u32) ?T {
        if (T == Position) {
            return self.positions.get(entity);
        } else if (T == Velocity) {
            return self.velocities.get(entity);
        } else if (T == Health) {
            return self.healths.get(entity);
        }
        return null;
    }
};

// =============================================================================
// Component Definitions
// =============================================================================

const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    dx: f32,
    dy: f32,
};

const Health = struct {
    current: i32,
    max: i32,
};

const Tag = struct {
    name: []const u8,
};

// =============================================================================
// Factory Definitions
// =============================================================================

const PositionFactory = Factory.define(Position, .{
    .x = 0.0,
    .y = 0.0,
});

const VelocityFactory = Factory.define(Velocity, .{
    .dx = 0.0,
    .dy = 0.0,
});

const HealthFactory = Factory.define(Health, .{
    .current = 100,
    .max = 100,
});

const TagFactory = Factory.define(Tag, .{
    .name = Factory.sequenceFmt("Entity-{d}"),
});

// Factory traits for common entity archetypes
const MovingPositionFactory = PositionFactory.trait(.{
    .x = 10.0,
    .y = 10.0,
});

const FastVelocityFactory = VelocityFactory.trait(.{
    .dx = 100.0,
    .dy = 100.0,
});

const DamagedHealthFactory = HealthFactory.trait(.{
    .current = 50,
});

// =============================================================================
// Pattern 1: Basic Registry Setup with before/after hooks
// =============================================================================

pub const BasicRegistrySetup = struct {
    var registry: *MockRegistry = undefined;

    test "tests:before" {
        Factory.resetSequences();
        registry = ECS.createRegistry(MockRegistry);
    }

    test "tests:after" {
        ECS.destroyRegistry(registry);
    }

    test "creates entity with single component" {
        const entity = ECS.createEntity(registry, .{
            .position = PositionFactory.build(.{}),
        });

        const pos = registry.get(Position, entity);
        try expect.notToBeNull(pos);
        try expect.equal(pos.?.x, 0.0);
        try expect.equal(pos.?.y, 0.0);
    }

    test "creates entity with multiple components" {
        const entity = ECS.createEntity(registry, .{
            .position = PositionFactory.build(.{ .x = 5.0, .y = 10.0 }),
            .velocity = VelocityFactory.build(.{ .dx = 1.0, .dy = 2.0 }),
            .health = HealthFactory.build(.{}),
        });

        const pos = registry.get(Position, entity);
        const vel = registry.get(Velocity, entity);
        const health = registry.get(Health, entity);

        try expect.notToBeNull(pos);
        try expect.notToBeNull(vel);
        try expect.notToBeNull(health);
        try expect.equal(pos.?.x, 5.0);
        try expect.equal(vel.?.dx, 1.0);
        try expect.equal(health.?.current, 100);
    }

    test "uses factory traits for common archetypes" {
        const entity = ECS.createEntity(registry, .{
            .position = MovingPositionFactory.build(.{}),
            .velocity = FastVelocityFactory.build(.{}),
        });

        const pos = registry.get(Position, entity);
        const vel = registry.get(Velocity, entity);

        try expect.equal(pos.?.x, 10.0);
        try expect.equal(vel.?.dx, 100.0);
    }
};

// =============================================================================
// Pattern 2: Using Let for Memoized Registry
// =============================================================================

pub const LetBasedRegistry = struct {
    var arena: std.heap.ArenaAllocator = undefined;
    var test_alloc: std.mem.Allocator = undefined;

    fn createTestRegistry() *MockRegistry {
        return ECS.createRegistryWith(MockRegistry, test_alloc);
    }

    const registry = zspec.Let(*MockRegistry, createTestRegistry);

    test "tests:before" {
        Factory.resetSequences();
        arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        test_alloc = arena.allocator();
    }

    test "tests:after" {
        ECS.destroyRegistryWith(registry.get(), test_alloc);
        registry.reset();
        arena.deinit();
    }

    test "registry is created lazily" {
        const reg = registry.get();
        const entity = ECS.createEntity(reg, .{
            .position = PositionFactory.build(.{}),
        });

        try expect.notToBeNull(reg.get(Position, entity));
    }

    test "registry is shared between operations" {
        const reg = registry.get();
        const entity1 = ECS.createEntity(reg, .{
            .position = PositionFactory.build(.{ .x = 1.0 }),
        });
        const entity2 = ECS.createEntity(reg, .{
            .position = PositionFactory.build(.{ .x = 2.0 }),
        });

        try expect.equal(registry.get().get(Position, entity1).?.x, 1.0);
        try expect.equal(registry.get().get(Position, entity2).?.x, 2.0);
    }
};

// =============================================================================
// Pattern 3: Batch Entity Creation
// =============================================================================

pub const BatchCreation = struct {
    var registry: *MockRegistry = undefined;

    test "tests:before" {
        Factory.resetSequences();
        registry = ECS.createRegistry(MockRegistry);
    }

    test "tests:after" {
        ECS.destroyRegistry(registry);
    }

    test "creates multiple entities with same components" {
        const entities = ECS.createEntities(registry, 5, .{
            .position = PositionFactory.build(.{ .x = 10.0 }),
        });
        defer std.testing.allocator.free(entities);

        try expect.toHaveLength(entities, 5);

        for (entities) |entity| {
            const pos = registry.get(Position, entity);
            try expect.notToBeNull(pos);
            try expect.equal(pos.?.x, 10.0);
        }
    }

    test "creates entities with unique sequential components" {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        // Create factory function that generates unique components per call
        const createComponents = struct {
            fn create() @TypeOf(.{
                .position = PositionFactory.build(.{}),
                .tag = TagFactory.buildWith(std.testing.allocator, .{}),
            }) {
                return .{
                    .position = PositionFactory.build(.{}),
                    .tag = TagFactory.buildWith(std.testing.allocator, .{}),
                };
            }
        }.create;

        _ = alloc;
        // Note: createEntitiesFromFactory not fully demonstrated here
        // as it requires compile-time function evaluation
    }
};

// =============================================================================
// Pattern 4: ComponentFactory Pattern
// =============================================================================

pub const ComponentFactoryPattern = struct {
    var registry: *MockRegistry = undefined;

    // Define component factories for reusable component builders
    const PositionComponent = ECS.ComponentFactory(Position, PositionFactory);
    const VelocityComponent = ECS.ComponentFactory(Velocity, VelocityFactory);
    const HealthComponent = ECS.ComponentFactory(Health, HealthFactory);

    test "tests:before" {
        Factory.resetSequences();
        registry = ECS.createRegistry(MockRegistry);
    }

    test "tests:after" {
        ECS.destroyRegistry(registry);
    }

    test "ComponentFactory builds component data" {
        const pos = PositionComponent.build(.{ .x = 5.0 });
        try expect.equal(pos.x, 5.0);
    }

    test "ComponentFactory attaches to existing entity" {
        const entity = registry.create();

        PositionComponent.attach(registry, entity, .{ .x = 10.0, .y = 20.0 });
        VelocityComponent.attach(registry, entity, .{ .dx = 1.0, .dy = 2.0 });

        const pos = registry.get(Position, entity);
        const vel = registry.get(Velocity, entity);

        try expect.equal(pos.?.x, 10.0);
        try expect.equal(vel.?.dx, 1.0);
    }

    test "ComponentFactory creates entity with component" {
        const entity = PositionComponent.createEntityWith(registry, .{
            .x = 15.0,
            .y = 25.0,
        });

        const pos = registry.get(Position, entity);
        try expect.equal(pos.?.x, 15.0);
        try expect.equal(pos.?.y, 25.0);
    }

    test "ComponentFactory creates multiple entities" {
        const entities = HealthComponent.createEntitiesWith(registry, 3, .{
            .current = 75,
            .max = 100,
        });
        defer std.testing.allocator.free(entities);

        try expect.toHaveLength(entities, 3);

        for (entities) |entity| {
            const health = registry.get(Health, entity);
            try expect.equal(health.?.current, 75);
            try expect.equal(health.?.max, 100);
        }
    }
};

// =============================================================================
// Pattern 5: Practical Game Testing Example
// =============================================================================

pub const GameScenarios = struct {
    var registry: *MockRegistry = undefined;
    var arena: std.heap.ArenaAllocator = undefined;
    var test_alloc: std.mem.Allocator = undefined;

    test "tests:beforeAll" {
        Factory.resetSequences();
    }

    test "tests:before" {
        registry = ECS.createRegistry(MockRegistry);
        arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        test_alloc = arena.allocator();
    }

    test "tests:after" {
        ECS.destroyRegistry(registry);
        arena.deinit();
    }

    test "player entity setup" {
        const player = ECS.createEntity(registry, .{
            .position = PositionFactory.build(.{ .x = 0.0, .y = 0.0 }),
            .velocity = VelocityFactory.build(.{ .dx = 0.0, .dy = 0.0 }),
            .health = HealthFactory.build(.{ .current = 100, .max = 100 }),
        });

        // Simulate movement
        const pos = registry.get(Position, player);
        try expect.equal(pos.?.x, 0.0);

        // Health check
        const health = registry.get(Health, player);
        try expect.equal(health.?.current, 100);
    }

    test "enemy spawning" {
        const enemies = ECS.createEntities(registry, 10, .{
            .position = MovingPositionFactory.build(.{}),
            .velocity = FastVelocityFactory.build(.{}),
            .health = HealthFactory.build(.{}),
        });
        defer std.testing.allocator.free(enemies);

        try expect.toHaveLength(enemies, 10);

        // All enemies have the expected components
        for (enemies) |enemy| {
            try expect.notToBeNull(registry.get(Position, enemy));
            try expect.notToBeNull(registry.get(Velocity, enemy));
            try expect.notToBeNull(registry.get(Health, enemy));
        }
    }

    test "damaged entity scenario" {
        const damaged_entity = ECS.createEntity(registry, .{
            .position = PositionFactory.build(.{}),
            .health = DamagedHealthFactory.build(.{}),
        });

        const health = registry.get(Health, damaged_entity);
        try expect.equal(health.?.current, 50);
        try expect.equal(health.?.max, 100);
    }

    test "complex battle scenario" {
        // Create player
        const player = ECS.createEntity(registry, .{
            .position = PositionFactory.build(.{ .x = 0.0, .y = 0.0 }),
            .health = HealthFactory.build(.{}),
        });

        // Create enemies at different positions
        const enemy1 = ECS.createEntity(registry, .{
            .position = PositionFactory.build(.{ .x = 10.0, .y = 10.0 }),
            .health = HealthFactory.build(.{}),
        });

        const enemy2 = ECS.createEntity(registry, .{
            .position = PositionFactory.build(.{ .x = -10.0, .y = 10.0 }),
            .health = DamagedHealthFactory.build(.{}),
        });

        // Verify setup
        try expect.equal(registry.get(Position, player).?.x, 0.0);
        try expect.equal(registry.get(Position, enemy1).?.x, 10.0);
        try expect.equal(registry.get(Position, enemy2).?.x, -10.0);
        try expect.equal(registry.get(Health, enemy2).?.current, 50);

        // Your game logic tests would go here...
    }
};

// =============================================================================
// Summary
// =============================================================================

// Key patterns demonstrated:
//
// 1. Registry Setup:
//    - Use ECS.createRegistry() in before hooks
//    - Use ECS.destroyRegistry() in after hooks
//    - Or use Let for memoized registry creation
//
// 2. Entity Creation:
//    - ECS.createEntity(registry, .{ .comp = Factory.build(.{}) })
//    - ECS.createEntities() for batch creation
//    - ComponentFactory pattern for reusable builders
//
// 3. Factory Patterns:
//    - Define component factories with Factory.define()
//    - Use .trait() for common archetypes (player, enemy, etc.)
//    - Use Factory.sequence() for unique IDs
//    - Use Factory.sequenceFmt() for unique names
//
// 4. Memory Management:
//    - Use arena allocator in tests to avoid leak reports
//    - Reset sequences in beforeAll or before hooks
//    - Clean up registry in after hooks
