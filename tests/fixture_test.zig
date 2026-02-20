//! Tests for Fixture module
//! Related to RFC 001 (issue #38)

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const Fixture = zspec.Fixture;

test {
    zspec.runAll(@This());
}

// =============================================================================
// Type Definitions
// =============================================================================

const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    active: bool = true,
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

const CheckoutScenario = struct {
    user: User,
    product: Product,
    order: Order,
};

const BattleScenario = struct {
    player: PlayerData,
    enemies: [3]EnemyData,
};

const Shape = union(enum) {
    circle: struct { radius: f32 },
    rectangle: struct { width: f32, height: f32 },
};

const ShapeVisual = struct {
    shape: Shape,
    z_index: u8,
    visible: bool,
};

const Color = struct { r: u8, g: u8, b: u8, a: u8 };
const SpriteVisual = struct { tint: Color, scale: f32 };

const Inner = struct { value: u8, name: []const u8 };
const Middle = struct { inner: Inner, count: u32 };
const Outer = struct { middle: Middle, label: []const u8 };

// =============================================================================
// Fixture Definitions
// =============================================================================

// Single-struct fixture from .zon file
const UserFixture = Fixture.define(User, @import("fixtures/user.zon"));

// Scenario fixture from .zon file
const CheckoutFixture = Fixture.define(CheckoutScenario, @import("fixtures/checkout.zon"));

// Nested structs + arrays from .zon file
const BattleFixture = Fixture.define(BattleScenario, @import("fixtures/battle.zon"));

// Inline fixture definitions (for testing without .zon files)
const InlineUserFixture = Fixture.define(User, .{
    .id = 1,
    .name = "John Doe",
    .email = "john@example.com",
    .active = true,
});

const ShapeFixture = Fixture.define(ShapeVisual, .{
    .shape = .{ .circle = .{ .radius = 25.0 } },
    .z_index = 10,
    .visible = true,
});

const SpriteFixture = Fixture.define(SpriteVisual, .{
    .tint = .{ .r = 255, .g = 128, .b = 64, .a = 255 },
    .scale = 1.5,
});

const NestedFixture = Fixture.define(Outer, .{
    .middle = .{
        .inner = .{ .value = 42, .name = "nested" },
        .count = 100,
    },
    .label = "outer",
});

// =============================================================================
// Tests
// =============================================================================

pub const SINGLE_STRUCT = struct {
    test "create with defaults" {
        const user = InlineUserFixture.create(.{});

        try std.testing.expectEqualStrings("John Doe", user.name);
        try std.testing.expectEqualStrings("john@example.com", user.email);
        try expect.equal(user.id, 1);
        try expect.toBeTrue(user.active);
    }

    test "create with overrides" {
        const user = InlineUserFixture.create(.{
            .name = "Jane Smith",
            .email = "jane@example.com",
        });

        try std.testing.expectEqualStrings("Jane Smith", user.name);
        try std.testing.expectEqualStrings("jane@example.com", user.email);
        // Defaults preserved
        try expect.equal(user.id, 1);
        try expect.toBeTrue(user.active);
    }

    test "create with all fields overridden" {
        const user = InlineUserFixture.create(.{
            .id = 99,
            .name = "Custom",
            .email = "custom@test.com",
            .active = false,
        });

        try expect.equal(user.id, 99);
        try std.testing.expectEqualStrings("Custom", user.name);
        try expect.toBeTrue(!user.active);
    }
};

pub const SCENARIO = struct {
    test "create multi-struct scenario" {
        const s = CheckoutFixture.create(.{});

        try expect.equal(s.user.id, 1);
        try std.testing.expectEqualStrings("John Doe", s.user.name);
        try expect.equal(s.product.id, 10);
        try std.testing.expectEqualStrings("Widget", s.product.name);
        try expect.equal(s.order.id, 100);
        try expect.equal(s.order.quantity, 2);
    }

    test "cross-references are consistent" {
        const s = CheckoutFixture.create(.{});

        try expect.equal(s.order.user_id, s.user.id);
        try expect.equal(s.order.product_id, s.product.id);
        try expect.equal(s.product.seller_id, s.user.id);
    }

    test "scenario with overrides" {
        const s = CheckoutFixture.create(.{
            .order = .{ .id = 200, .user_id = 1, .product_id = 10, .quantity = 5 },
        });

        try expect.equal(s.order.id, 200);
        try expect.equal(s.order.quantity, 5);
        // Other structs unchanged
        try std.testing.expectEqualStrings("John Doe", s.user.name);
    }

    test "partial nested override in scenario" {
        // Override only user name — other user fields and other structs preserved
        const s = CheckoutFixture.create(.{
            .user = .{ .name = "Jane" },
        });

        try std.testing.expectEqualStrings("Jane", s.user.name);
        // Other user fields from .zon
        try expect.equal(s.user.id, 1);
        try std.testing.expectEqualStrings("john@example.com", s.user.email);
        // Other structs unchanged
        try expect.equal(s.product.id, 10);
        try expect.equal(s.order.quantity, 2);
    }
};

pub const ARRAYS = struct {
    test "fixed-size array from .zon tuple" {
        const battle = BattleFixture.create(.{});

        try expect.equal(battle.enemies[0].kind, .slime);
        try expect.equal(battle.enemies[0].health.current, 20);
        try expect.equal(battle.enemies[0].pos.x, 50.0);

        try expect.equal(battle.enemies[1].kind, .goblin);
        try expect.equal(battle.enemies[1].health.current, 50);

        try expect.equal(battle.enemies[2].kind, .dragon);
        try expect.equal(battle.enemies[2].health.current, 200);
    }

    test "array elements have correct nested struct coercion" {
        const battle = BattleFixture.create(.{});

        // Verify deeply nested values in array elements
        try expect.equal(battle.enemies[0].pos.y, 30.0);
        try expect.equal(battle.enemies[1].pos.x, 80.0);
        try expect.equal(battle.enemies[2].health.max, 200);
    }

    test "inline array fixture" {
        const Item = struct { id: u32, name: []const u8 };
        const Inventory = struct {
            owner: []const u8,
            items: [2]Item,
        };

        const InvFixture = Fixture.define(Inventory, .{
            .owner = "Alice",
            .items = .{
                .{ .id = 1, .name = "Sword" },
                .{ .id = 2, .name = "Shield" },
            },
        });

        const inv = InvFixture.create(.{});
        try std.testing.expectEqualStrings("Alice", inv.owner);
        try expect.equal(inv.items[0].id, 1);
        try std.testing.expectEqualStrings("Sword", inv.items[0].name);
        try expect.equal(inv.items[1].id, 2);
        try std.testing.expectEqualStrings("Shield", inv.items[1].name);
    }
};

pub const NESTED_STRUCTS = struct {
    test "deeply nested struct coercion" {
        const outer = NestedFixture.create(.{});

        try std.testing.expectEqualStrings("outer", outer.label);
        try expect.equal(outer.middle.count, 100);
        try expect.equal(outer.middle.inner.value, 42);
        try std.testing.expectEqualStrings("nested", outer.middle.inner.name);
    }

    test "override nested struct fields" {
        const outer = NestedFixture.create(.{
            .middle = .{
                .inner = .{ .value = 99, .name = "overridden" },
                .count = 200,
            },
        });

        try expect.equal(outer.middle.count, 200);
        try expect.equal(outer.middle.inner.value, 99);
        try std.testing.expectEqualStrings("overridden", outer.middle.inner.name);
    }

    test "sprite nested struct coercion" {
        const sprite = SpriteFixture.create(.{});

        try expect.equal(sprite.tint.r, 255);
        try expect.equal(sprite.tint.g, 128);
        try expect.equal(sprite.tint.b, 64);
        try expect.equal(sprite.tint.a, 255);
        try expect.equal(sprite.scale, 1.5);
    }

    test "override nested struct at callsite" {
        const sprite = SpriteFixture.create(.{
            .tint = .{ .r = 0, .g = 255, .b = 0, .a = 128 },
        });

        try expect.equal(sprite.tint.r, 0);
        try expect.equal(sprite.tint.g, 255);
        try expect.equal(sprite.tint.b, 0);
        try expect.equal(sprite.tint.a, 128);
    }

    test "partial nested override preserves defaults" {
        // Override only one field in nested struct — others preserved from .zon
        const sprite = SpriteFixture.create(.{
            .tint = .{ .r = 0 },
        });

        try expect.equal(sprite.tint.r, 0); // overridden
        try expect.equal(sprite.tint.g, 128); // from .zon default
        try expect.equal(sprite.tint.b, 64); // from .zon default
        try expect.equal(sprite.tint.a, 255); // from .zon default
        try expect.equal(sprite.scale, 1.5); // from .zon default
    }
};

pub const UNIONS = struct {
    test "union field from anonymous struct" {
        const visual = ShapeFixture.create(.{});

        try expect.toBeTrue(visual.visible);
        try expect.equal(visual.z_index, 10);

        switch (visual.shape) {
            .circle => |c| try expect.equal(c.radius, 25.0),
            .rectangle => return error.UnexpectedShape,
        }
    }

    test "override union field" {
        const visual = ShapeFixture.create(.{
            .shape = .{ .rectangle = .{ .width = 100.0, .height = 50.0 } },
        });

        switch (visual.shape) {
            .rectangle => |r| {
                try expect.equal(r.width, 100.0);
                try expect.equal(r.height, 50.0);
            },
            .circle => return error.UnexpectedShape,
        }
    }
};

pub const ZON_FILE_LOADING = struct {
    test "load single struct from .zon file" {
        const user = UserFixture.create(.{});

        try expect.equal(user.id, 1);
        try std.testing.expectEqualStrings("John Doe", user.name);
        try std.testing.expectEqualStrings("john@example.com", user.email);
        try expect.toBeTrue(user.active);
    }

    test "load single struct with override" {
        const user = UserFixture.create(.{ .name = "Jane" });

        try std.testing.expectEqualStrings("Jane", user.name);
        // Defaults from .zon
        try std.testing.expectEqualStrings("john@example.com", user.email);
    }

    test "load scenario from .zon file" {
        const s = CheckoutFixture.create(.{});

        try expect.equal(s.order.user_id, s.user.id);
        try expect.equal(s.order.product_id, s.product.id);
    }

    test "load battle scenario from .zon file" {
        const battle = BattleFixture.create(.{});

        try expect.equal(battle.player.pos.x, 0.0);
        try expect.equal(battle.player.health.current, 100);
        try expect.equal(battle.enemies[0].kind, .slime);
        try expect.equal(battle.enemies[2].kind, .dragon);
    }
};
