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
/// Returns a type with a `create(overrides)` method.
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
        /// Create an instance with optional field overrides
        pub fn create(overrides: anytype) T {
            return buildFixture(T, zon_data, overrides);
        }
    };
}

/// Build a fixture instance by merging .zon defaults with callsite overrides.
fn buildFixture(comptime T: type, comptime zon_data: anytype, overrides: anytype) T {
    var result: T = undefined;
    const OverridesType = @TypeOf(overrides);

    // Validate override fields exist in T (catch typos at compile time)
    if (OverridesType != @TypeOf(.{})) {
        inline for (std.meta.fields(OverridesType)) |override_field| {
            if (!@hasField(T, override_field.name)) {
                @compileError("Unknown override field '" ++ override_field.name ++ "'. " ++
                    "Type '" ++ @typeName(T) ++ "' has no such field.");
            }
        }
    }

    inline for (std.meta.fields(T)) |field| {
        // Check for callsite override first
        if (OverridesType != @TypeOf(.{}) and @hasField(OverridesType, field.name)) {
            const override_value = @field(overrides, field.name);
            const OverrideFieldType = @TypeOf(override_value);

            // If both override and .zon default are structs, and the target is a struct,
            // merge them field-by-field (partial nested override)
            if (@typeInfo(field.type) == .@"struct" and
                @typeInfo(OverrideFieldType) == .@"struct" and
                @hasField(@TypeOf(zon_data), field.name))
            {
                @field(result, field.name) = mergeOverride(field.type, @field(zon_data, field.name), override_value);
            } else {
                @field(result, field.name) = resolveFieldValue(field.type, override_value);
            }
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

/// Merge an override struct with .zon defaults field-by-field.
/// When both are structs, the override only replaces specified fields; unspecified
/// fields fall back to .zon defaults. This enables partial nested overrides like
/// `.create(.{ .user = .{ .name = "Jane" } })` preserving other user fields from .zon.
fn mergeOverride(comptime FieldType: type, comptime zon_default: anytype, override: anytype) FieldType {
    const OverrideType = @TypeOf(override);

    var result: FieldType = undefined;
    inline for (std.meta.fields(FieldType)) |field| {
        if (@hasField(OverrideType, field.name)) {
            // Override provides this field — use it (recursively merge if also struct)
            const override_value = @field(override, field.name);
            const OverrideFieldType = @TypeOf(override_value);

            if (@typeInfo(field.type) == .@"struct" and
                @typeInfo(OverrideFieldType) == .@"struct" and
                @hasField(@TypeOf(zon_default), field.name))
            {
                @field(result, field.name) = mergeOverride(field.type, @field(zon_default, field.name), override_value);
            } else {
                @field(result, field.name) = resolveFieldValue(field.type, override_value);
            }
        } else if (@hasField(@TypeOf(zon_default), field.name)) {
            // Fall back to .zon default
            @field(result, field.name) = resolveFieldValue(field.type, @field(zon_default, field.name));
        } else if (field.default_value_ptr) |default_ptr| {
            const default_typed: *const field.type = @ptrCast(@alignCast(default_ptr));
            @field(result, field.name) = default_typed.*;
        } else {
            @compileError("Fixture: no value for field '" ++ field.name ++ "'");
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
        if (!@typeInfo(ValueType).@"struct".is_tuple) {
            @compileError("Fixture: array field expects a tuple (.{ val1, val2, ... }), got a named struct");
        }
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

test "partial nested override preserves .zon defaults" {
    const User = struct { id: u32, name: []const u8, email: []const u8 };
    const Scenario = struct { user: User };

    const ScenarioFixture = define(Scenario, .{
        .user = .{ .id = 1, .name = "John", .email = "john@example.com" },
    });

    // Override only name — id and email should come from .zon defaults
    const s = ScenarioFixture.create(.{ .user = .{ .name = "Jane" } });
    try std.testing.expectEqualStrings("Jane", s.user.name);
    try std.testing.expectEqual(@as(u32, 1), s.user.id);
    try std.testing.expectEqualStrings("john@example.com", s.user.email);
}

test "fixture with []const u8 fields" {
    const Config = struct { host: []const u8, path: []const u8 };
    const ConfigFixture = define(Config, .{ .host = "localhost", .path = "/api" });

    const config = ConfigFixture.create(.{});
    try std.testing.expectEqualStrings("localhost", config.host);
    try std.testing.expectEqualStrings("/api", config.path);

    // Override with different string
    const custom = ConfigFixture.create(.{ .host = "example.com" });
    try std.testing.expectEqualStrings("example.com", custom.host);
    try std.testing.expectEqualStrings("/api", custom.path);
}
