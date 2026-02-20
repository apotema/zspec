//! Fixture Module Example
//!
//! Demonstrates the Fixture module — a FactoryBot-inspired workflow for static
//! test data defined in .zon files.
//!
//! Key differences from Factory:
//! - **Fixture**: Static, pre-defined test data. Call `create()` to instantiate.
//! - **Factory**: Dynamic generation with sequences, lazy values, traits, associations.
//!
//! Use Fixture when you want a snapshot of known-good test data.
//! Use Factory when you need generators that produce unique data each time.
//!
//! Usage:
//!   zig build examples-fixture

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const Fixture = zspec.Fixture;

test {
    zspec.runAll(@This());
}

// =============================================================================
// Model Definitions
// =============================================================================

const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
};

const Product = struct {
    id: u32,
    name: []const u8,
    price: f32,
    seller_id: u32,
};

const Order = struct {
    id: u32,
    user_id: u32,
    product_id: u32,
    quantity: u32,
};

const Position = struct { x: f32, y: f32 };
const Health = struct { current: u32, max: u32 };
const EnemyKind = enum { slime, goblin, dragon };

const PlayerData = struct {
    pos: Position,
    health: Health,
};

const EnemyData = struct {
    pos: Position,
    health: Health,
    kind: EnemyKind,
};

// =============================================================================
// Fixture Definitions
// =============================================================================

// Load fixture data from a .zon file
const fixture_data = @import("fixture_example.zon");

// Single-struct fixtures: one call to define, then create anywhere
const UserFixture = Fixture.define(User, fixture_data.user);
const AdminFixture = Fixture.define(User, fixture_data.admin);
const ProductFixture = Fixture.define(Product, fixture_data.product);

// Scenario fixture: multiple related structs in one definition
const CheckoutScenario = struct {
    user: User,
    product: Product,
    order: Order,
};

const CheckoutFixture = Fixture.define(CheckoutScenario, .{
    .user = .{ .id = 1, .name = "John Doe", .email = "john@example.com" },
    .product = .{ .id = 10, .name = "Widget", .price = 29.99, .seller_id = 1 },
    .order = .{ .id = 100, .user_id = 1, .product_id = 10, .quantity = 2 },
});

// Battle scenario with arrays and nested structs
const BattleScenario = struct {
    player: PlayerData,
    enemies: [3]EnemyData,
};

const BattleFixture = Fixture.define(BattleScenario, .{
    .player = .{
        .pos = .{ .x = 0.0, .y = 0.0 },
        .health = .{ .current = 100, .max = 100 },
    },
    .enemies = .{
        .{
            .pos = .{ .x = 50.0, .y = 30.0 },
            .health = .{ .current = 20, .max = 20 },
            .kind = .slime,
        },
        .{
            .pos = .{ .x = 80.0, .y = 60.0 },
            .health = .{ .current = 50, .max = 50 },
            .kind = .goblin,
        },
        .{
            .pos = .{ .x = 120.0, .y = 10.0 },
            .health = .{ .current = 200, .max = 200 },
            .kind = .dragon,
        },
    },
});

// =============================================================================
// Example Tests
// =============================================================================

pub const BASIC_USAGE = struct {
    test "create a user with defaults" {
        const user = UserFixture.create(.{});

        try std.testing.expectEqualStrings("John Doe", user.name);
        try std.testing.expectEqualStrings("john@example.com", user.email);
        try expect.equal(user.id, 1);
    }

    test "create an admin with different fixture" {
        const admin = AdminFixture.create(.{});

        try std.testing.expectEqualStrings("Admin User", admin.name);
        try expect.equal(admin.id, 2);
    }

    test "override fields at create time" {
        const user = UserFixture.create(.{
            .name = "Jane Smith",
            .email = "jane@example.com",
        });

        try std.testing.expectEqualStrings("Jane Smith", user.name);
        try std.testing.expectEqualStrings("jane@example.com", user.email);
        // Default from .zon preserved
        try expect.equal(user.id, 1);
    }
};

pub const SCENARIO_USAGE = struct {
    test "create a complete checkout scenario" {
        const s = CheckoutFixture.create(.{});

        try expect.equal(s.user.id, 1);
        try std.testing.expectEqualStrings("Widget", s.product.name);
        try expect.equal(s.order.quantity, 2);
    }

    test "verify cross-references in scenario" {
        const s = CheckoutFixture.create(.{});

        // The order references the user and product by ID
        try expect.equal(s.order.user_id, s.user.id);
        try expect.equal(s.order.product_id, s.product.id);
        try expect.equal(s.product.seller_id, s.user.id);
    }

    test "override one struct in scenario" {
        const s = CheckoutFixture.create(.{
            .order = .{ .id = 200, .user_id = 1, .product_id = 10, .quantity = 10 },
        });

        try expect.equal(s.order.quantity, 10);
        try expect.equal(s.order.id, 200);
        // Other structs unchanged
        try std.testing.expectEqualStrings("John Doe", s.user.name);
    }
};

pub const ARRAYS_AND_NESTED = struct {
    test "battle scenario with array of enemies" {
        const battle = BattleFixture.create(.{});

        try expect.equal(battle.player.health.current, 100);
        try expect.equal(battle.player.pos.x, 0.0);

        try expect.equal(battle.enemies[0].kind, .slime);
        try expect.equal(battle.enemies[0].health.current, 20);

        try expect.equal(battle.enemies[1].kind, .goblin);
        try expect.equal(battle.enemies[1].health.current, 50);

        try expect.equal(battle.enemies[2].kind, .dragon);
        try expect.equal(battle.enemies[2].health.current, 200);
    }

    test "nested struct positions are correct" {
        const battle = BattleFixture.create(.{});

        try expect.equal(battle.enemies[0].pos.x, 50.0);
        try expect.equal(battle.enemies[0].pos.y, 30.0);
        try expect.equal(battle.enemies[1].pos.x, 80.0);
        try expect.equal(battle.enemies[2].pos.x, 120.0);
    }
};

pub const COMPARISON_WITH_FACTORY = struct {
    test "Fixture.create vs Factory.build produce equivalent results" {
        const Factory = zspec.Factory;

        // Factory approach (inline definition)
        const UserFactory = Factory.define(User, .{
            .id = 1,
            .name = "John Doe",
            .email = "john@example.com",
        });

        const from_factory = UserFactory.build(.{});
        const from_fixture = UserFixture.create(.{});

        try std.testing.expectEqualStrings(from_factory.name, from_fixture.name);
        try std.testing.expectEqualStrings(from_factory.email, from_fixture.email);
        try expect.equal(from_factory.id, from_fixture.id);
    }
};
