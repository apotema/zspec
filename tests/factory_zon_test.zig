//! Tests for Factory.defineFrom() with .zon file loading
//! Related to issue #31

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const Factory = zspec.Factory;

test {
    zspec.runAll(@This());
}

// Type definitions for testing
const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    age: u8,
    active: bool,
};

const Product = struct {
    id: u32,
    name: []const u8,
    price: f32,
    in_stock: bool,
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

// Load factory definitions from .zon file
const factory_defs = @import("factory_definitions.zon");

// Define factories using defineFrom
const UserFactory = Factory.defineFrom(User, factory_defs.user);
const AdminUserFactory = Factory.defineFrom(User, factory_defs.admin_user);
const ProductFactory = Factory.defineFrom(Product, factory_defs.product);
const CircleShapeFactory = Factory.defineFrom(ShapeVisual, factory_defs.circle_shape);
const RectangleShapeFactory = Factory.defineFrom(ShapeVisual, factory_defs.rectangle_shape);

pub const DEFINE_FROM_BASIC = struct {
    test "defineFrom creates factory with defaults from .zon" {
        const user = UserFactory.build(.{});

        try std.testing.expectEqualStrings("John Doe", user.name);
        try std.testing.expectEqualStrings("john@example.com", user.email);
        try expect.equal(user.age, 25);
        try expect.toBeTrue(user.active);
    }

    test "defineFrom allows overriding fields" {
        const user = UserFactory.build(.{
            .name = "Jane Doe",
            .age = 30,
        });

        try std.testing.expectEqualStrings("Jane Doe", user.name);
        try std.testing.expectEqualStrings("john@example.com", user.email); // default from .zon
        try expect.equal(user.age, 30);
    }

    test "defineFrom with different factory definitions" {
        const admin = AdminUserFactory.build(.{});

        try std.testing.expectEqualStrings("Admin User", admin.name);
        try std.testing.expectEqualStrings("admin@example.com", admin.email);
        try expect.equal(admin.age, 30);
    }

    test "defineFrom works with product type" {
        const product = ProductFactory.build(.{});

        try std.testing.expectEqualStrings("Widget", product.name);
        try expect.equal(product.price, 9.99);
        try expect.toBeTrue(product.in_stock);
    }

    test "defineFrom with product override" {
        const product = ProductFactory.build(.{
            .name = "Gadget",
            .price = 19.99,
            .in_stock = false,
        });

        try std.testing.expectEqualStrings("Gadget", product.name);
        try expect.equal(product.price, 19.99);
        try expect.toBeTrue(!product.in_stock);
    }
};

pub const DEFINE_FROM_UNION = struct {
    test "defineFrom with union type (circle)" {
        const visual = CircleShapeFactory.build(.{});

        try expect.toBeTrue(visual.visible);
        try expect.equal(visual.z_index, 128);

        switch (visual.shape) {
            .circle => |c| try expect.equal(c.radius, 50.0),
            .rectangle => return error.UnexpectedShape,
        }
    }

    test "defineFrom with union type (rectangle)" {
        const visual = RectangleShapeFactory.build(.{});

        try expect.toBeTrue(visual.visible);
        try expect.equal(visual.z_index, 64);

        switch (visual.shape) {
            .rectangle => |r| {
                try expect.equal(r.width, 100.0);
                try expect.equal(r.height, 50.0);
            },
            .circle => return error.UnexpectedShape,
        }
    }

    test "defineFrom with union override" {
        // Start with circle, override to rectangle
        const visual = CircleShapeFactory.build(.{
            .shape = .{ .rectangle = .{ .width = 200.0, .height = 100.0 } },
        });

        switch (visual.shape) {
            .rectangle => |r| {
                try expect.equal(r.width, 200.0);
                try expect.equal(r.height, 100.0);
            },
            .circle => return error.UnexpectedShape,
        }
    }
};

pub const DEFINE_FROM_TRAITS = struct {
    test "defineFrom factory supports traits" {
        const InactiveUserFactory = UserFactory.trait(.{
            .active = false,
        });

        const user = InactiveUserFactory.build(.{});

        try std.testing.expectEqualStrings("John Doe", user.name); // from .zon
        try expect.toBeTrue(!user.active); // from trait
    }

    test "defineFrom factory with chained traits" {
        const CustomUserFactory = UserFactory.trait(.{
            .active = false,
        }).trait(.{
            .age = 40,
        });

        const user = CustomUserFactory.build(.{});

        try expect.toBeTrue(!user.active);
        try expect.equal(user.age, 40);
        try std.testing.expectEqualStrings("John Doe", user.name); // from .zon
    }
};

pub const DEFINE_FROM_EQUIVALENCE = struct {
    test "defineFrom produces same result as define" {
        // Factory defined inline
        const InlineFactory = Factory.define(User, .{
            .id = 0,
            .name = "John Doe",
            .email = "john@example.com",
            .age = 25,
            .active = true,
        });

        const from_inline = InlineFactory.build(.{});
        const from_zon = UserFactory.build(.{});

        try std.testing.expectEqualStrings(from_inline.name, from_zon.name);
        try std.testing.expectEqualStrings(from_inline.email, from_zon.email);
        try expect.equal(from_inline.age, from_zon.age);
        try expect.equal(from_inline.active, from_zon.active);
    }
};

// Types for nested struct tests (issue #33)
const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

const SpriteVisual = struct {
    tint: Color,
    scale: f32,
};

// Simulates data from a .zon file (anonymous struct)
const sprite_zon_data = .{
    .tint = .{ .r = 255, .g = 128, .b = 64, .a = 255 },
    .scale = 1.5,
};

const SpriteVisualFactory = Factory.defineFrom(SpriteVisual, sprite_zon_data);

pub const DEFINE_FROM_NESTED_STRUCT = struct {
    test "defineFrom with nested struct coerces anonymous struct to named struct" {
        const sprite = SpriteVisualFactory.build(.{});

        try expect.equal(sprite.tint.r, 255);
        try expect.equal(sprite.tint.g, 128);
        try expect.equal(sprite.tint.b, 64);
        try expect.equal(sprite.tint.a, 255);
        try expect.equal(sprite.scale, 1.5);
    }

    test "defineFrom with nested struct allows overrides" {
        // Override the nested struct with a properly typed Color
        const sprite = SpriteVisualFactory.build(.{
            .tint = Color{ .r = 0, .g = 0, .b = 0, .a = 128 },
        });

        try expect.equal(sprite.tint.r, 0);
        try expect.equal(sprite.tint.a, 128);
    }

    test "trait with nested struct from defineFrom" {
        // Create a trait with a different tint (using anonymous struct)
        const RedTintFactory = SpriteVisualFactory.trait(.{
            .tint = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        });

        const sprite = RedTintFactory.build(.{});

        try expect.equal(sprite.tint.r, 255);
        try expect.equal(sprite.tint.g, 0);
        try expect.equal(sprite.tint.b, 0);
    }

    test "callsite override with anonymous nested struct" {
        // Override using anonymous struct syntax at build() callsite
        const sprite = SpriteVisualFactory.build(.{
            .tint = .{ .r = 0, .g = 255, .b = 0, .a = 128 },
        });

        try expect.equal(sprite.tint.r, 0);
        try expect.equal(sprite.tint.g, 255);
        try expect.equal(sprite.tint.b, 0);
        try expect.equal(sprite.tint.a, 128);
    }

    test "callsite override with anonymous nested struct on trait factory" {
        const RedTintFactory = SpriteVisualFactory.trait(.{
            .tint = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        });

        // Override the trait's tint with anonymous struct at callsite
        const sprite = RedTintFactory.build(.{
            .tint = .{ .r = 0, .g = 0, .b = 255, .a = 64 },
        });

        try expect.equal(sprite.tint.r, 0);
        try expect.equal(sprite.tint.g, 0);
        try expect.equal(sprite.tint.b, 255);
        try expect.equal(sprite.tint.a, 64);
    }
};

// Types for deeply nested struct tests (issue #35)
const Inner = struct {
    value: u8,
    name: []const u8,
};

const Middle = struct {
    inner: Inner,
    count: u32,
};

const Outer = struct {
    middle: Middle,
    label: []const u8,
};

// Deeply nested .zon data
const deeply_nested_zon = .{
    .middle = .{
        .inner = .{ .value = 42, .name = "nested" },
        .count = 100,
    },
    .label = "outer",
};

const OuterFactory = Factory.defineFrom(Outer, deeply_nested_zon);

pub const DEFINE_FROM_DEEPLY_NESTED = struct {
    test "defineFrom with deeply nested structs coerces all levels" {
        const outer = OuterFactory.build(.{});

        try std.testing.expectEqualStrings("outer", outer.label);
        try expect.equal(outer.middle.count, 100);
        try expect.equal(outer.middle.inner.value, 42);
        try std.testing.expectEqualStrings("nested", outer.middle.inner.name);
    }

    test "deeply nested struct override at middle level" {
        const outer = OuterFactory.build(.{
            .middle = .{
                .inner = .{ .value = 99, .name = "overridden" },
                .count = 200,
            },
        });

        try expect.equal(outer.middle.count, 200);
        try expect.equal(outer.middle.inner.value, 99);
        try std.testing.expectEqualStrings("overridden", outer.middle.inner.name);
    }

    test "deeply nested struct with trait" {
        const CustomOuterFactory = OuterFactory.trait(.{
            .middle = .{
                .inner = .{ .value = 77, .name = "from trait" },
                .count = 50,
            },
        });

        const outer = CustomOuterFactory.build(.{});

        try expect.equal(outer.middle.inner.value, 77);
        try std.testing.expectEqualStrings("from trait", outer.middle.inner.name);
        try expect.equal(outer.middle.count, 50);
    }
};

// Types for union with nested struct validation (issue #36)
const Position = struct {
    x: f32,
    y: f32,
};

const CircleData = struct {
    center: Position,
    radius: f32,
};

const RectData = struct {
    origin: Position,
    width: f32,
    height: f32,
};

const ComplexShape = union(enum) {
    circle: CircleData,
    rect: RectData,
};

const Canvas = struct {
    shape: ComplexShape,
    name: []const u8,
};

const canvas_circle_zon = .{
    .shape = .{ .circle = .{ .center = .{ .x = 10.0, .y = 20.0 }, .radius = 5.0 } },
    .name = "my circle",
};

const canvas_rect_zon = .{
    .shape = .{ .rect = .{ .origin = .{ .x = 0.0, .y = 0.0 }, .width = 100.0, .height = 50.0 } },
    .name = "my rect",
};

const CircleCanvasFactory = Factory.defineFrom(Canvas, canvas_circle_zon);
const RectCanvasFactory = Factory.defineFrom(Canvas, canvas_rect_zon);

pub const DEFINE_FROM_UNION_WITH_NESTED = struct {
    test "union with deeply nested struct (circle)" {
        const canvas = CircleCanvasFactory.build(.{});

        try std.testing.expectEqualStrings("my circle", canvas.name);
        switch (canvas.shape) {
            .circle => |c| {
                try expect.equal(c.center.x, 10.0);
                try expect.equal(c.center.y, 20.0);
                try expect.equal(c.radius, 5.0);
            },
            .rect => return error.UnexpectedShape,
        }
    }

    test "union with deeply nested struct (rect)" {
        const canvas = RectCanvasFactory.build(.{});

        try std.testing.expectEqualStrings("my rect", canvas.name);
        switch (canvas.shape) {
            .rect => |r| {
                try expect.equal(r.origin.x, 0.0);
                try expect.equal(r.origin.y, 0.0);
                try expect.equal(r.width, 100.0);
                try expect.equal(r.height, 50.0);
            },
            .circle => return error.UnexpectedShape,
        }
    }

    test "override union with deeply nested anonymous struct" {
        const canvas = CircleCanvasFactory.build(.{
            .shape = .{ .rect = .{ .origin = .{ .x = 5.0, .y = 5.0 }, .width = 200.0, .height = 100.0 } },
        });

        switch (canvas.shape) {
            .rect => |r| {
                try expect.equal(r.origin.x, 5.0);
                try expect.equal(r.origin.y, 5.0);
                try expect.equal(r.width, 200.0);
            },
            .circle => return error.UnexpectedShape,
        }
    }
};
