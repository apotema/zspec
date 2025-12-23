//! Factory.defineFrom() Example
//!
//! Demonstrates loading factory definitions from .zon files using Factory.defineFrom().
//! This pattern offers several benefits:
//!
//! - **Separation of concerns**: Test data lives in data files, test logic in test files
//! - **Reusability**: Share factory definitions across multiple test files
//! - **Maintainability**: Update test data without touching test code
//! - **Type safety**: Full compile-time type checking via Zig's comptime system
//!
//! Usage:
//!   zig build examples-factory-zon

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const Factory = zspec.Factory;

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
    role: []const u8,
    active: bool,
};

const Product = struct {
    id: u32,
    name: []const u8,
    description: []const u8,
    price: f32,
    in_stock: bool,
    quantity: u32,
};

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

const Shape = union(enum) {
    circle: struct { radius: f32 },
    rectangle: struct { width: f32, height: f32 },
};

const ShapeVisual = struct {
    shape: Shape,
    color: Color,
    visible: bool,
};

// =============================================================================
// Load Factory Definitions from .zon File
// =============================================================================

// Import the .zon file at compile time - no runtime parsing needed!
const factory_defs = @import("factory_zon_example.zon");

// Define factories using defineFrom() - makes intent clear
const UserFactory = Factory.defineFrom(User, factory_defs.user);
const AdminFactory = Factory.defineFrom(User, factory_defs.admin);
const ProductFactory = Factory.defineFrom(Product, factory_defs.product);
const OutOfStockProductFactory = Factory.defineFrom(Product, factory_defs.out_of_stock_product);

// Note: Nested struct coercion (like Color) requires explicit type in .zon
// For simpler cases, unions work directly with anonymous syntax

// =============================================================================
// Example Tests
// =============================================================================

pub const BASIC_USAGE = struct {
    test "create user with defaults from .zon" {
        const user = UserFactory.build(.{});

        try std.testing.expectEqualStrings("John Doe", user.name);
        try std.testing.expectEqualStrings("john@example.com", user.email);
        try std.testing.expectEqualStrings("member", user.role);
        try expect.toBeTrue(user.active);
    }

    test "create admin with different .zon definition" {
        const admin = AdminFactory.build(.{});

        try std.testing.expectEqualStrings("Admin User", admin.name);
        try std.testing.expectEqualStrings("admin@example.com", admin.email);
        try std.testing.expectEqualStrings("admin", admin.role);
    }

    test "override .zon defaults at build time" {
        const user = UserFactory.build(.{
            .name = "Jane Smith",
            .email = "jane@example.com",
        });

        // Overridden values
        try std.testing.expectEqualStrings("Jane Smith", user.name);
        try std.testing.expectEqualStrings("jane@example.com", user.email);

        // Defaults from .zon
        try std.testing.expectEqualStrings("member", user.role);
        try expect.toBeTrue(user.active);
    }
};

pub const PRODUCT_VARIANTS = struct {
    test "in-stock product from .zon" {
        const product = ProductFactory.build(.{});

        try std.testing.expectEqualStrings("Widget", product.name);
        try expect.equal(product.price, 29.99);
        try expect.toBeTrue(product.in_stock);
        try expect.equal(product.quantity, 100);
    }

    test "out-of-stock product variant" {
        const product = OutOfStockProductFactory.build(.{});

        try std.testing.expectEqualStrings("Rare Item", product.name);
        try expect.toBeTrue(!product.in_stock);
        try expect.equal(product.quantity, 0);
    }
};

pub const TRAITS_WITH_ZON = struct {
    test "apply traits on top of .zon defaults" {
        // Create an inactive user trait
        const InactiveUserFactory = UserFactory.trait(.{
            .active = false,
        });

        const user = InactiveUserFactory.build(.{});

        // From .zon
        try std.testing.expectEqualStrings("John Doe", user.name);
        // From trait
        try expect.toBeTrue(!user.active);
    }

    test "chain multiple traits" {
        const VIPUserFactory = UserFactory
            .trait(.{ .role = "vip" })
            .trait(.{ .active = true });

        const user = VIPUserFactory.build(.{});

        try std.testing.expectEqualStrings("vip", user.role);
        try expect.toBeTrue(user.active);
    }
};

pub const EQUIVALENCE = struct {
    test "defineFrom is equivalent to inline define" {
        // Inline factory definition
        const InlineUserFactory = Factory.define(User, .{
            .id = 0,
            .name = "John Doe",
            .email = "john@example.com",
            .role = "member",
            .active = true,
        });

        const from_inline = InlineUserFactory.build(.{});
        const from_zon = UserFactory.build(.{});

        try std.testing.expectEqualStrings(from_inline.name, from_zon.name);
        try std.testing.expectEqualStrings(from_inline.email, from_zon.email);
        try std.testing.expectEqualStrings(from_inline.role, from_zon.role);
        try expect.equal(from_inline.active, from_zon.active);
    }
};
