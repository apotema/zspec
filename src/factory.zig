//! ZSpec Factory - FactoryBot-like test data generation for Zig
//!
//! Provides:
//! - Factory.define() - Define factories with default values
//! - Factory.sequence() - Auto-incrementing values
//! - Factory.sequenceFmt() - Formatted sequence strings
//! - Factory.lazy() - Computed values
//! - Factory.assoc() - Nested factory associations
//! - .trait() - Predefined variants
//! - .build() / .buildPtr() - Create instances

const std = @import("std");

/// Global sequence counters - reset with resetSequences()
/// Using a simple array-based approach for simplicity and to avoid hashmap issues
const MAX_SEQUENCES = 256;
var sequence_values: [MAX_SEQUENCES]u64 = [_]u64{0} ** MAX_SEQUENCES;

/// Reset all sequence counters to 0
pub fn resetSequences() void {
    sequence_values = [_]u64{0} ** MAX_SEQUENCES;
}

fn getNextSequence(id: usize) u64 {
    const index = id % MAX_SEQUENCES;
    sequence_values[index] += 1;
    return sequence_values[index];
}

/// Marker type for sequence fields
pub fn SequenceType(comptime T: type) type {
    return struct {
        pub const sequence_type = T;
        pub const is_sequence = true;
    };
}

/// Marker type for formatted sequence fields
pub fn SequenceFmtType(comptime fmt: []const u8) type {
    return struct {
        pub const format_string = fmt;
        pub const is_sequence_fmt = true;
    };
}

/// Marker type for lazy/computed fields
pub fn Lazy(comptime T: type, comptime func: fn () T) type {
    return struct {
        pub const lazy_type = T;
        pub const compute = func;
        pub const is_lazy = true;
    };
}

/// Marker type for lazy fields with allocator
pub fn LazyAlloc(comptime T: type, comptime func: fn (std.mem.Allocator) T) type {
    return struct {
        pub const lazy_type = T;
        pub const computeAlloc = func;
        pub const is_lazy_alloc = true;
    };
}

/// Marker type for associations
pub fn Assoc(comptime FactoryType: type) type {
    return struct {
        pub const factory = FactoryType;
        pub const is_assoc = true;
    };
}

/// Create a sequence marker for auto-incrementing numeric values.
pub fn sequence(comptime T: type) SequenceType(T) {
    return .{};
}

/// Create a formatted sequence marker for strings like "user{d}@example.com".
pub fn sequenceFmt(comptime fmt: []const u8) SequenceFmtType(fmt) {
    return .{};
}

/// Create a lazy marker for computed values
pub fn lazy(comptime func: anytype) Lazy(@typeInfo(@TypeOf(func)).@"fn".return_type.?, func) {
    return .{};
}

/// Create a lazy marker for computed values that need an allocator
pub fn lazyAlloc(comptime func: anytype) LazyAlloc(@typeInfo(@TypeOf(func)).@"fn".return_type.?, func) {
    return .{};
}

/// Create an association marker for nested factories
pub fn assoc(comptime FactoryType: type) Assoc(FactoryType) {
    return .{};
}

/// Define a factory for a given type with default values
pub fn define(comptime T: type, comptime defaults: anytype) type {
    return FactoryImpl(T, defaults, 0);
}

fn FactoryImpl(comptime T: type, comptime defaults: anytype, comptime depth: usize) type {
    if (depth > 3) {
        @compileError("Factory associations cannot be nested more than 3 levels deep");
    }

    return struct {
        const Self = @This();
        pub const Target = T;
        pub const default_values = defaults;
        pub const nesting_depth = depth;

        /// Build an instance using std.testing.allocator
        pub fn build(overrides: anytype) T {
            return buildWith(std.testing.allocator, overrides);
        }

        /// Build a pointer instance using std.testing.allocator
        pub fn buildPtr(overrides: anytype) *T {
            return buildPtrWith(std.testing.allocator, overrides);
        }

        /// Build an instance using a custom allocator
        pub fn buildWith(alloc: std.mem.Allocator, overrides: anytype) T {
            return buildInternal(alloc, overrides);
        }

        /// Build a pointer instance using a custom allocator
        pub fn buildPtrWith(alloc: std.mem.Allocator, overrides: anytype) *T {
            const ptr = alloc.create(T) catch @panic("factory allocation failed");
            ptr.* = buildInternal(alloc, overrides);
            return ptr;
        }

        fn buildInternal(alloc: std.mem.Allocator, overrides: anytype) T {
            var result: T = undefined;
            const target_fields = std.meta.fields(T);

            inline for (target_fields) |field| {
                const field_name = field.name;
                @field(result, field_name) = resolveField(field.type, field_name, alloc, overrides);
            }

            return result;
        }

        fn resolveField(comptime FieldType: type, comptime field_name: []const u8, alloc: std.mem.Allocator, overrides: anytype) FieldType {
            const OverridesType = @TypeOf(overrides);

            // Check if field is overridden
            if (OverridesType != @TypeOf(.{})) {
                if (@hasField(OverridesType, field_name)) {
                    const override_value = @field(overrides, field_name);
                    return processOverride(FieldType, override_value, alloc);
                }
            }

            // Use default value
            if (@hasField(@TypeOf(defaults), field_name)) {
                const default_value = @field(defaults, field_name);
                return resolveDefaultWithField(FieldType, field_name, default_value, alloc);
            }

            // Handle optional pointer - default to null
            if (comptime isOptionalPointer(FieldType)) {
                return null;
            }

            @compileError("No default value provided for field: " ++ field_name);
        }

        fn processOverride(comptime FieldType: type, override_value: anytype, alloc: std.mem.Allocator) FieldType {
            const OverrideType = @TypeOf(override_value);

            // Direct value assignment
            if (OverrideType == FieldType) {
                return override_value;
            }

            // Handle struct overrides for nested types
            if (@typeInfo(OverrideType) == .@"struct" and @typeInfo(FieldType) == .pointer) {
                const ChildType = @typeInfo(FieldType).pointer.child;
                if (@typeInfo(ChildType) == .@"struct") {
                    const ptr = alloc.create(ChildType) catch @panic("factory allocation failed");
                    ptr.* = buildNestedStruct(ChildType, override_value, alloc);
                    return ptr;
                }
            }

            // Coerce compatible types
            return @as(FieldType, override_value);
        }

        fn buildNestedStruct(comptime TargetType: type, source: anytype, alloc: std.mem.Allocator) TargetType {
            var result: TargetType = undefined;
            const SourceType = @TypeOf(source);

            inline for (std.meta.fields(TargetType)) |field| {
                if (@hasField(SourceType, field.name)) {
                    @field(result, field.name) = @field(source, field.name);
                } else if (field.default_value) |default_ptr| {
                    const default_typed: *const field.type = @ptrCast(@alignCast(default_ptr));
                    @field(result, field.name) = default_typed.*;
                } else {
                    _ = alloc;
                    @compileError("Missing field in nested override: " ++ field.name);
                }
            }

            return result;
        }

        fn computeFieldHash(comptime field_name: []const u8) usize {
            // Create a unique ID based on type name and field name
            var hash: usize = 0;
            for (@typeName(T)) |c| {
                hash = hash *% 31 +% c;
            }
            for (field_name) |c| {
                hash = hash *% 31 +% c;
            }
            return hash;
        }

        fn resolveDefaultWithField(comptime FieldType: type, comptime field_name: []const u8, default_value: anytype, alloc: std.mem.Allocator) FieldType {
            const DefaultType = @TypeOf(default_value);

            // Handle sequence markers
            if (@typeInfo(DefaultType) == .@"struct" and @hasDecl(DefaultType, "is_sequence")) {
                const seq_id = comptime computeFieldHash(field_name);
                const seq_num = getNextSequence(seq_id);
                return @as(FieldType, @intCast(seq_num));
            }

            // Handle sequence format markers
            if (@typeInfo(DefaultType) == .@"struct" and @hasDecl(DefaultType, "is_sequence_fmt")) {
                const seq_id = comptime computeFieldHash(field_name);
                const seq_num = getNextSequence(seq_id);
                return std.fmt.allocPrint(alloc, DefaultType.format_string, .{seq_num}) catch @panic("sequence format failed");
            }

            // Handle lazy markers
            if (@typeInfo(DefaultType) == .@"struct" and @hasDecl(DefaultType, "is_lazy")) {
                return DefaultType.compute();
            }

            // Handle lazy alloc markers
            if (@typeInfo(DefaultType) == .@"struct" and @hasDecl(DefaultType, "is_lazy_alloc")) {
                return DefaultType.computeAlloc(alloc);
            }

            // Handle association markers
            if (@typeInfo(DefaultType) == .@"struct" and @hasDecl(DefaultType, "is_assoc")) {
                const AssocFactory = DefaultType.factory;
                return AssocFactory.buildPtrWith(alloc, .{});
            }

            // Handle null for optional pointers
            if (DefaultType == @TypeOf(null) and comptime isOptionalPointer(FieldType)) {
                return null;
            }

            // Direct value
            if (DefaultType == FieldType) {
                return default_value;
            }

            // Try coercion
            return @as(FieldType, default_value);
        }

        fn isOptionalPointer(comptime FieldType: type) bool {
            if (@typeInfo(FieldType) != .optional) return false;
            const child = @typeInfo(FieldType).optional.child;
            return @typeInfo(child) == .pointer;
        }

        /// Create a new factory with additional/overridden defaults (trait)
        pub fn trait(comptime trait_values: anytype) type {
            return TraitFactoryImpl(T, defaults, trait_values, depth);
        }
    };
}

/// Factory implementation for traits - stores both base defaults and trait overrides
fn TraitFactoryImpl(comptime T: type, comptime base_defaults: anytype, comptime trait_overrides: anytype, comptime depth: usize) type {
    if (depth > 3) {
        @compileError("Factory associations cannot be nested more than 3 levels deep");
    }

    return struct {
        const Self = @This();
        pub const Target = T;
        pub const nesting_depth = depth;

        /// Build an instance using std.testing.allocator
        pub fn build(overrides: anytype) T {
            return buildWith(std.testing.allocator, overrides);
        }

        /// Build a pointer instance using std.testing.allocator
        pub fn buildPtr(overrides: anytype) *T {
            return buildPtrWith(std.testing.allocator, overrides);
        }

        /// Build an instance using a custom allocator
        pub fn buildWith(alloc: std.mem.Allocator, overrides: anytype) T {
            return buildInternal(alloc, overrides);
        }

        /// Build a pointer instance using a custom allocator
        pub fn buildPtrWith(alloc: std.mem.Allocator, overrides: anytype) *T {
            const ptr = alloc.create(T) catch @panic("factory allocation failed");
            ptr.* = buildInternal(alloc, overrides);
            return ptr;
        }

        fn buildInternal(alloc: std.mem.Allocator, overrides: anytype) T {
            var result: T = undefined;
            const target_fields = std.meta.fields(T);

            inline for (target_fields) |field| {
                const field_name = field.name;
                @field(result, field_name) = resolveField(field.type, field_name, alloc, overrides);
            }

            return result;
        }

        fn resolveField(comptime FieldType: type, comptime field_name: []const u8, alloc: std.mem.Allocator, overrides: anytype) FieldType {
            const OverridesType = @TypeOf(overrides);

            // Check if field is overridden at call site
            if (OverridesType != @TypeOf(.{})) {
                if (@hasField(OverridesType, field_name)) {
                    const override_value = @field(overrides, field_name);
                    return processOverride(FieldType, override_value, alloc);
                }
            }

            // Check if field is in trait overrides
            if (@hasField(@TypeOf(trait_overrides), field_name)) {
                const trait_value = @field(trait_overrides, field_name);
                return resolveDefaultWithField(FieldType, field_name, trait_value, alloc);
            }

            // Use base default value
            if (@hasField(@TypeOf(base_defaults), field_name)) {
                const default_value = @field(base_defaults, field_name);
                return resolveDefaultWithField(FieldType, field_name, default_value, alloc);
            }

            // Handle optional pointer - default to null
            if (comptime isOptionalPointer(FieldType)) {
                return null;
            }

            @compileError("No default value provided for field: " ++ field_name);
        }

        fn processOverride(comptime FieldType: type, override_value: anytype, _: std.mem.Allocator) FieldType {
            const OverrideType = @TypeOf(override_value);

            // Direct value assignment
            if (OverrideType == FieldType) {
                return override_value;
            }

            // Coerce compatible types
            return @as(FieldType, override_value);
        }

        fn computeFieldHash(comptime field_name: []const u8) usize {
            var hash: usize = 0;
            for (@typeName(T)) |c| {
                hash = hash *% 31 +% c;
            }
            for (field_name) |c| {
                hash = hash *% 31 +% c;
            }
            return hash;
        }

        fn resolveDefaultWithField(comptime FieldType: type, comptime field_name: []const u8, default_value: anytype, alloc: std.mem.Allocator) FieldType {
            const DefaultType = @TypeOf(default_value);

            // Handle sequence markers
            if (@typeInfo(DefaultType) == .@"struct" and @hasDecl(DefaultType, "is_sequence")) {
                const seq_id = comptime computeFieldHash(field_name);
                const seq_num = getNextSequence(seq_id);
                return @as(FieldType, @intCast(seq_num));
            }

            // Handle sequence format markers
            if (@typeInfo(DefaultType) == .@"struct" and @hasDecl(DefaultType, "is_sequence_fmt")) {
                const seq_id = comptime computeFieldHash(field_name);
                const seq_num = getNextSequence(seq_id);
                return std.fmt.allocPrint(alloc, DefaultType.format_string, .{seq_num}) catch @panic("sequence format failed");
            }

            // Handle lazy markers
            if (@typeInfo(DefaultType) == .@"struct" and @hasDecl(DefaultType, "is_lazy")) {
                return DefaultType.compute();
            }

            // Handle lazy alloc markers
            if (@typeInfo(DefaultType) == .@"struct" and @hasDecl(DefaultType, "is_lazy_alloc")) {
                return DefaultType.computeAlloc(alloc);
            }

            // Handle association markers
            if (@typeInfo(DefaultType) == .@"struct" and @hasDecl(DefaultType, "is_assoc")) {
                const AssocFactory = DefaultType.factory;
                return AssocFactory.buildPtrWith(alloc, .{});
            }

            // Handle null for optional pointers
            if (DefaultType == @TypeOf(null) and comptime isOptionalPointer(FieldType)) {
                return null;
            }

            // Direct value
            if (DefaultType == FieldType) {
                return default_value;
            }

            // Try coercion
            return @as(FieldType, default_value);
        }

        fn isOptionalPointer(comptime FieldType: type) bool {
            if (@typeInfo(FieldType) != .optional) return false;
            const child = @typeInfo(FieldType).optional.child;
            return @typeInfo(child) == .pointer;
        }

        /// Create a new factory with additional/overridden defaults (trait)
        pub fn trait(comptime new_trait_values: anytype) type {
            // Chain traits by creating a new trait factory with combined overrides
            return TraitFactoryImpl(T, base_defaults, mergeTrait(trait_overrides, new_trait_values), depth);
        }

        fn mergeTrait(comptime base: anytype, comptime overlay: anytype) MergedTraitType(base, overlay) {
            var result: MergedTraitType(base, overlay) = undefined;
            inline for (std.meta.fields(@TypeOf(base))) |field| {
                @field(result, field.name) = @field(base, field.name);
            }
            inline for (std.meta.fields(@TypeOf(overlay))) |field| {
                @field(result, field.name) = @field(overlay, field.name);
            }
            return result;
        }

        fn MergedTraitType(comptime base: anytype, comptime overlay: anytype) type {
            const BaseType = @TypeOf(base);
            const OverlayType = @TypeOf(overlay);
            const base_fields = std.meta.fields(BaseType);
            const overlay_fields = std.meta.fields(OverlayType);

            var fields: [base_fields.len + overlay_fields.len]std.builtin.Type.StructField = undefined;
            var count: usize = 0;

            // Add base fields (that are not in overlay)
            inline for (base_fields) |field| {
                if (!@hasField(OverlayType, field.name)) {
                    fields[count] = field;
                    count += 1;
                }
            }

            // Add all overlay fields
            inline for (overlay_fields) |field| {
                fields[count] = field;
                count += 1;
            }

            return @Type(.{
                .@"struct" = .{
                    .layout = .auto,
                    .fields = fields[0..count],
                    .decls = &.{},
                    .is_tuple = false,
                },
            });
        }
    };
}

// Tests
test "basic factory" {
    const User = struct {
        name: []const u8,
        age: u8,
        active: bool,
    };

    const UserFactory = define(User, .{
        .name = "John Doe",
        .age = 25,
        .active = true,
    });

    const user = UserFactory.build(.{});
    try std.testing.expectEqualStrings("John Doe", user.name);
    try std.testing.expectEqual(@as(u8, 25), user.age);
    try std.testing.expect(user.active);
}

test "factory with overrides" {
    const User = struct {
        name: []const u8,
        age: u8,
    };

    const UserFactory = define(User, .{
        .name = "John",
        .age = 25,
    });

    const user = UserFactory.build(.{ .name = "Jane", .age = 30 });
    try std.testing.expectEqualStrings("Jane", user.name);
    try std.testing.expectEqual(@as(u8, 30), user.age);
}

test "factory sequence" {
    resetSequences();

    const User = struct {
        id: u32,
        name: []const u8,
    };

    const UserFactory = define(User, .{
        .id = sequence(u32),
        .name = "User",
    });

    const user1 = UserFactory.build(.{});
    const user2 = UserFactory.build(.{});
    const user3 = UserFactory.build(.{});

    try std.testing.expectEqual(@as(u32, 1), user1.id);
    try std.testing.expectEqual(@as(u32, 2), user2.id);
    try std.testing.expectEqual(@as(u32, 3), user3.id);
}

test "factory sequenceFmt" {
    resetSequences();

    const User = struct {
        email: []const u8,
    };

    const UserFactory = define(User, .{
        .email = sequenceFmt("user{d}@example.com"),
    });

    const user1 = UserFactory.build(.{});
    const user2 = UserFactory.build(.{});

    try std.testing.expectEqualStrings("user1@example.com", user1.email);
    try std.testing.expectEqualStrings("user2@example.com", user2.email);
}

test "factory trait" {
    const User = struct {
        name: []const u8,
        role: []const u8,
        active: bool,
    };

    const UserFactory = define(User, .{
        .name = "John",
        .role = "user",
        .active = true,
    });

    const AdminFactory = UserFactory.trait(.{
        .role = "admin",
    });

    const user = UserFactory.build(.{});
    const admin = AdminFactory.build(.{});

    try std.testing.expectEqualStrings("user", user.role);
    try std.testing.expectEqualStrings("admin", admin.role);
    try std.testing.expectEqualStrings("John", admin.name); // inherited
}

test "factory buildPtr" {
    const User = struct {
        name: []const u8,
    };

    const UserFactory = define(User, .{
        .name = "John",
    });

    const user_ptr = UserFactory.buildPtr(.{});
    defer std.testing.allocator.destroy(user_ptr);

    try std.testing.expectEqualStrings("John", user_ptr.name);
}

test "factory optional pointer defaults to null" {
    const Company = struct {
        name: []const u8,
    };

    const User = struct {
        name: []const u8,
        company: ?*Company,
    };

    const UserFactory = define(User, .{
        .name = "John",
        .company = null,
    });

    const user = UserFactory.build(.{});
    try std.testing.expectEqualStrings("John", user.name);
    try std.testing.expect(user.company == null);
}

test "factory lazy value" {
    var counter: u32 = 0;

    const Item = struct {
        value: u32,
    };

    const getCounter = struct {
        fn get() u32 {
            return 42;
        }
    }.get;

    const ItemFactory = define(Item, .{
        .value = lazy(getCounter),
    });

    _ = &counter;

    const item = ItemFactory.build(.{});
    try std.testing.expectEqual(@as(u32, 42), item.value);
}

test "resetSequences resets counters" {
    resetSequences();

    const Item = struct {
        id: u32,
    };

    const ItemFactory = define(Item, .{
        .id = sequence(u32),
    });

    _ = ItemFactory.build(.{});
    _ = ItemFactory.build(.{});
    const before_reset = ItemFactory.build(.{});
    try std.testing.expectEqual(@as(u32, 3), before_reset.id);

    resetSequences();

    const after_reset = ItemFactory.build(.{});
    try std.testing.expectEqual(@as(u32, 1), after_reset.id);
}
