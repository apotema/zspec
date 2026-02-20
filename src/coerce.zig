//! Shared comptime utilities for struct coercion and validation.
//!
//! Used by both Factory and Fixture modules to:
//! - Validate .zon data fields against target types
//! - Coerce anonymous structs to named types (recursive)
//! - Handle union payloads from anonymous struct syntax

const std = @import("std");

/// Validate that all fields in zon_data exist in the target type T (recursive for nested structs).
/// This catches typos in .zon files at compile time.
pub fn validateZonFields(comptime T: type, comptime zon_data: anytype) void {
    const ZonType = @TypeOf(zon_data);
    const zon_fields = std.meta.fields(ZonType);
    const target_fields = std.meta.fields(T);

    inline for (zon_fields) |zon_field| {
        if (!@hasField(T, zon_field.name)) {
            @compileError("Unknown field '" ++ zon_field.name ++ "' in .zon data. " ++
                "Type '" ++ @typeName(T) ++ "' has no such field. " ++
                "Check for typos in your .zon file.");
        }

        // Find the target field type and recursively validate nested structs
        inline for (target_fields) |target_field| {
            if (comptime std.mem.eql(u8, target_field.name, zon_field.name)) {
                const zon_field_value = @field(zon_data, zon_field.name);
                const ZonFieldType = @TypeOf(zon_field_value);

                // If both are structs, recursively validate
                if (@typeInfo(target_field.type) == .@"struct" and @typeInfo(ZonFieldType) == .@"struct") {
                    validateZonFields(target_field.type, zon_field_value);
                }
                // If target is union and source is struct, validate the union payload
                else if (@typeInfo(target_field.type) == .@"union" and @typeInfo(ZonFieldType) == .@"struct") {
                    validateUnionPayload(target_field.type, zon_field_value);
                }
                break;
            }
        }
    }
}

/// Validate that a union payload struct has valid fields
pub fn validateUnionPayload(comptime UnionType: type, comptime zon_data: anytype) void {
    const ZonType = @TypeOf(zon_data);
    const zon_fields = std.meta.fields(ZonType);

    if (zon_fields.len != 1) {
        @compileError("Union value must have exactly one field matching a union tag");
    }

    const tag_name = zon_fields[0].name;
    const union_info = @typeInfo(UnionType).@"union";

    // Find the union field and validate its payload
    inline for (union_info.fields) |union_field| {
        if (comptime std.mem.eql(u8, union_field.name, tag_name)) {
            const payload_value = @field(zon_data, tag_name);
            const PayloadZonType = @TypeOf(payload_value);

            // If payload is a struct, validate its fields
            if (@typeInfo(union_field.type) == .@"struct" and @typeInfo(PayloadZonType) == .@"struct") {
                validateZonFields(union_field.type, payload_value);
            }
            return;
        }
    }

    @compileError("Unknown union tag '" ++ tag_name ++ "' in .zon data. " ++
        "Union '" ++ @typeName(UnionType) ++ "' has no such variant.");
}

/// Coerce an anonymous struct to a union type
/// e.g., .{ .circle = .{ .radius = 10 } } -> Shape{ .circle = ... }
pub fn coerceToUnion(comptime UnionType: type, default_value: anytype) UnionType {
    const DefaultType = @TypeOf(default_value);
    const default_fields = std.meta.fields(DefaultType);

    // Anonymous struct must have exactly one field
    if (default_fields.len != 1) {
        @compileError("Union default value must be a struct with exactly one field matching a union tag");
    }

    const tag_name = default_fields[0].name;
    const union_info = @typeInfo(UnionType).@"union";

    // Find the expected payload type for this tag
    inline for (union_info.fields) |union_field| {
        if (comptime std.mem.eql(u8, union_field.name, tag_name)) {
            const PayloadType = union_field.type;
            const source_payload = @field(default_value, tag_name);

            // Build the correctly-typed payload
            const typed_payload = buildTypedPayload(PayloadType, source_payload);
            return @unionInit(UnionType, tag_name, typed_payload);
        }
    }

    @compileError("No union field named '" ++ tag_name ++ "' in union type");
}

/// Build a nested struct from an anonymous source struct (for pointer-to-struct overrides)
pub fn buildNestedStruct(comptime TargetType: type, source: anytype) TargetType {
    var result: TargetType = undefined;
    const SourceType = @TypeOf(source);

    inline for (std.meta.fields(TargetType)) |field| {
        if (@hasField(SourceType, field.name)) {
            @field(result, field.name) = @field(source, field.name);
        } else if (field.default_value_ptr) |default_ptr| {
            const default_typed: *const field.type = @ptrCast(@alignCast(default_ptr));
            @field(result, field.name) = default_typed.*;
        } else {
            @compileError("Missing field in nested override: " ++ field.name);
        }
    }

    return result;
}

/// Build a typed value from an anonymous source value (recursive for nested structs)
pub fn buildTypedPayload(comptime TargetType: type, source: anytype) TargetType {
    const SourceType = @TypeOf(source);

    // If already the right type, return directly
    if (SourceType == TargetType) {
        return source;
    }

    // If both are structs, copy fields (with support for default values and recursive coercion)
    if (@typeInfo(TargetType) == .@"struct" and @typeInfo(SourceType) == .@"struct") {
        var result: TargetType = undefined;
        inline for (std.meta.fields(TargetType)) |field| {
            if (@hasField(SourceType, field.name)) {
                const source_value = @field(source, field.name);
                const SourceFieldType = @TypeOf(source_value);

                // If field types match, assign directly
                if (SourceFieldType == field.type) {
                    @field(result, field.name) = source_value;
                }
                // If both are structs but different types, recursively coerce
                else if (@typeInfo(field.type) == .@"struct" and @typeInfo(SourceFieldType) == .@"struct") {
                    @field(result, field.name) = buildTypedPayload(field.type, source_value);
                }
                // If target is union and source is struct, coerce to union
                else if (@typeInfo(field.type) == .@"union" and @typeInfo(SourceFieldType) == .@"struct") {
                    @field(result, field.name) = coerceToUnion(field.type, source_value);
                }
                // Otherwise try direct coercion
                else {
                    @field(result, field.name) = source_value;
                }
            } else if (field.default_value_ptr) |default_ptr| {
                // Use the field's default value if not provided
                const default_typed: *const field.type = @ptrCast(@alignCast(default_ptr));
                @field(result, field.name) = default_typed.*;
            } else {
                @compileError("Missing field '" ++ field.name ++ "' in struct (no default value)");
            }
        }
        return result;
    }

    // For non-struct types, try explicit coercion
    return @as(TargetType, source);
}
