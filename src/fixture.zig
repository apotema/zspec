//! ZSpec Fixture - Static test data instantiation from .zon files
//!
//! Provides a FactoryBot-inspired workflow for static test data:
//! - Define fixtures once in .zon files
//! - Call `create()` anywhere in tests with optional overrides
//!
//! Unlike Factory (which handles dynamic generation with sequences, lazy values,
//! and traits), Fixture is designed for static, pre-defined test data — complete
//! snapshots of known-good state.
//!
//! Supports:
//! - Single struct fixtures: `Fixture.define(User, @import("user.zon"))`
//! - Scenario fixtures: `Fixture.define(CheckoutScenario, @import("checkout.zon"))`
//! - Fixed-size arrays: `[3]Product` fields populated from .zon tuples
//! - Nested structs and unions: recursive coercion from anonymous structs

const std = @import("std");
const coerce = @import("coerce.zig");

/// Define a fixture for a given type with .zon data defaults.
///
/// Returns a type with `create(overrides)` and `createWith(alloc, overrides)` methods.
/// All fields in `zon_data` are validated against `T` at compile time.
///
/// Example:
/// ```zig
/// const UserFixture = Fixture.define(User, @import("fixtures/user.zon"));
/// const user = UserFixture.create(.{});
/// const custom = UserFixture.create(.{ .name = "Jane" });
/// ```
pub fn define(comptime T: type, comptime zon_data: anytype) type {
    validateFixtureData(T, zon_data);

    return struct {
        /// Create an instance with optional field overrides (uses std.testing.allocator)
        pub fn create(overrides: anytype) T {
            return buildFixture(T, zon_data, overrides);
        }

        /// Create an instance with a custom allocator
        pub fn createWith(_: std.mem.Allocator, overrides: anytype) T {
            return buildFixture(T, zon_data, overrides);
        }
    };
}

/// Build a fixture instance by merging .zon defaults with callsite overrides.
fn buildFixture(comptime T: type, comptime zon_data: anytype, overrides: anytype) T {
    var result: T = undefined;
    const OverridesType = @TypeOf(overrides);

    inline for (std.meta.fields(T)) |field| {
        // Check for callsite override first
        if (OverridesType != @TypeOf(.{}) and @hasField(OverridesType, field.name)) {
            @field(result, field.name) = resolveFieldValue(field.type, @field(overrides, field.name));
        }
        // Use .zon default
        else if (@hasField(@TypeOf(zon_data), field.name)) {
            @field(result, field.name) = resolveFieldValue(field.type, @field(zon_data, field.name));
        }
        // Use the type's default value if available
        else if (field.default_value_ptr) |default_ptr| {
            const default_typed: *const field.type = @ptrCast(@alignCast(default_ptr));
            @field(result, field.name) = default_typed.*;
        } else {
            @compileError("Fixture: no value for field '" ++ field.name ++ "' in type '" ++ @typeName(T) ++ "'. " ++
                "Provide it in the .zon data or add a default value to the type.");
        }
    }

    return result;
}

/// Resolve a single field value, handling type coercion for structs, unions, and arrays.
fn resolveFieldValue(comptime FieldType: type, value: anytype) FieldType {
    const ValueType = @TypeOf(value);

    // Already the right type
    if (ValueType == FieldType) {
        return value;
    }

    // Fixed-size array: [N]T from a .zon tuple
    if (@typeInfo(FieldType) == .array) {
        return resolveArrayField(FieldType, value);
    }

    // Union from anonymous struct
    if (@typeInfo(FieldType) == .@"union" and @typeInfo(ValueType) == .@"struct") {
        return coerce.coerceToUnion(FieldType, value);
    }

    // Struct from anonymous struct (recursive coercion)
    if (@typeInfo(FieldType) == .@"struct" and @typeInfo(ValueType) == .@"struct") {
        return coerce.buildTypedPayload(FieldType, value);
    }

    // Direct coercion
    return @as(FieldType, value);
}

/// Resolve a fixed-size array field from a .zon tuple.
fn resolveArrayField(comptime ArrayType: type, value: anytype) ArrayType {
    const array_info = @typeInfo(ArrayType).array;
    const ElemType = array_info.child;
    const ValueType = @TypeOf(value);

    // If already the right type, return directly
    if (ValueType == ArrayType) {
        return value;
    }

    // Handle tuple (anonymous struct with numeric fields)
    if (@typeInfo(ValueType) == .@"struct") {
        const value_fields = std.meta.fields(ValueType);
        if (value_fields.len != array_info.len) {
            @compileError(std.fmt.comptimePrint(
                "Fixture: array field expects {d} elements but .zon tuple has {d}",
                .{ array_info.len, value_fields.len },
            ));
        }

        var result: ArrayType = undefined;
        inline for (0..array_info.len) |i| {
            result[i] = resolveFieldValue(ElemType, value[i]);
        }
        return result;
    }

    @compileError("Fixture: cannot coerce value to array type '" ++ @typeName(ArrayType) ++ "'");
}

/// Validate fixture data against the target type at compile time.
/// Extends coerce.validateZonFields with array-aware validation.
fn validateFixtureData(comptime T: type, comptime zon_data: anytype) void {
    const ZonType = @TypeOf(zon_data);
    const zon_fields = std.meta.fields(ZonType);

    inline for (zon_fields) |zon_field| {
        if (!@hasField(T, zon_field.name)) {
            @compileError("Unknown field '" ++ zon_field.name ++ "' in fixture data. " ++
                "Type '" ++ @typeName(T) ++ "' has no such field. " ++
                "Check for typos in your .zon file.");
        }

        // Find the target field and recursively validate
        inline for (std.meta.fields(T)) |target_field| {
            if (comptime std.mem.eql(u8, target_field.name, zon_field.name)) {
                const zon_field_value = @field(zon_data, zon_field.name);
                const ZonFieldType = @TypeOf(zon_field_value);

                // Array fields: validate each element
                if (@typeInfo(target_field.type) == .array) {
                    const elem_type = @typeInfo(target_field.type).array.child;
                    if (@typeInfo(ZonFieldType) == .@"struct") {
                        // Validate each tuple element against the array element type
                        if (@typeInfo(elem_type) == .@"struct") {
                            inline for (0..std.meta.fields(ZonFieldType).len) |i| {
                                const elem = zon_field_value[i];
                                if (@typeInfo(@TypeOf(elem)) == .@"struct") {
                                    validateFixtureData(elem_type, elem);
                                }
                            }
                        }
                    }
                }
                // Nested struct fields
                else if (@typeInfo(target_field.type) == .@"struct" and @typeInfo(ZonFieldType) == .@"struct") {
                    coerce.validateZonFields(target_field.type, zon_field_value);
                }
                // Union fields
                else if (@typeInfo(target_field.type) == .@"union" and @typeInfo(ZonFieldType) == .@"struct") {
                    coerce.validateUnionPayload(target_field.type, zon_field_value);
                }
                break;
            }
        }
    }
}

// =============================================================================
// Tests
// =============================================================================

test "basic fixture create" {
    const User = struct {
        name: []const u8,
        age: u8,
        active: bool,
    };

    const UserFixture = define(User, .{
        .name = "John Doe",
        .age = 25,
        .active = true,
    });

    const user = UserFixture.create(.{});
    try std.testing.expectEqualStrings("John Doe", user.name);
    try std.testing.expectEqual(@as(u8, 25), user.age);
    try std.testing.expect(user.active);
}

test "fixture create with overrides" {
    const User = struct {
        name: []const u8,
        age: u8,
    };

    const UserFixture = define(User, .{
        .name = "John",
        .age = 25,
    });

    const user = UserFixture.create(.{ .name = "Jane", .age = 30 });
    try std.testing.expectEqualStrings("Jane", user.name);
    try std.testing.expectEqual(@as(u8, 30), user.age);
}

test "fixture with nested struct coercion" {
    const Color = struct { r: u8, g: u8, b: u8 };
    const Sprite = struct { tint: Color, scale: f32 };

    const SpriteFixture = define(Sprite, .{
        .tint = .{ .r = 255, .g = 128, .b = 64 },
        .scale = 1.5,
    });

    const sprite = SpriteFixture.create(.{});
    try std.testing.expectEqual(@as(u8, 255), sprite.tint.r);
    try std.testing.expectEqual(@as(u8, 128), sprite.tint.g);
    try std.testing.expectEqual(@as(u8, 64), sprite.tint.b);
}

test "fixture with array field" {
    const Item = struct { id: u32, name: []const u8 };
    const Inventory = struct {
        owner: []const u8,
        items: [2]Item,
    };

    const InvFixture = define(Inventory, .{
        .owner = "Alice",
        .items = .{
            .{ .id = 1, .name = "Sword" },
            .{ .id = 2, .name = "Shield" },
        },
    });

    const inv = InvFixture.create(.{});
    try std.testing.expectEqualStrings("Alice", inv.owner);
    try std.testing.expectEqual(@as(u32, 1), inv.items[0].id);
    try std.testing.expectEqualStrings("Sword", inv.items[0].name);
    try std.testing.expectEqual(@as(u32, 2), inv.items[1].id);
    try std.testing.expectEqualStrings("Shield", inv.items[1].name);
}

test "fixture scenario (struct of structs)" {
    const User = struct { id: u32, name: []const u8 };
    const Product = struct { id: u32, name: []const u8, seller_id: u32 };
    const Scenario = struct { user: User, product: Product };

    const CheckoutFixture = define(Scenario, .{
        .user = .{ .id = 1, .name = "John" },
        .product = .{ .id = 10, .name = "Widget", .seller_id = 1 },
    });

    const s = CheckoutFixture.create(.{});
    try std.testing.expectEqual(@as(u32, 1), s.user.id);
    try std.testing.expectEqualStrings("John", s.user.name);
    try std.testing.expectEqual(@as(u32, 10), s.product.id);
    try std.testing.expectEqual(s.product.seller_id, s.user.id);
}
