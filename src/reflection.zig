// Keep the field projection used by factories/fixtures stable across Zig's
// 0.17 split into field_names, field_types and field_attrs.
pub const Field = struct {
    name: [:0]const u8,
    type: type,
    default_value_ptr: ?*const anyopaque = null,
    is_comptime: bool = false,
    alignment: ?usize,
};

pub inline fn fields(comptime T: type) []const Field {
    return comptime blk: {
        const info = @field(@typeInfo(T), @tagName(@typeInfo(T)));
        const split = @hasField(@TypeOf(info), "field_names");
        const len = if (split) info.field_names.len else info.fields.len;
        var result: [len]Field = undefined;
        for (0..len) |i| {
            if (split) {
                const attrs = info.field_attrs[i];
                result[i] = .{
                    .name = info.field_names[i],
                    .type = info.field_types[i],
                    .alignment = attrs.@"align",
                    .is_comptime = if (@hasField(@TypeOf(attrs), "comptime")) attrs.@"comptime" else false,
                    .default_value_ptr = if (@hasField(@TypeOf(attrs), "default_value_ptr")) attrs.default_value_ptr else null,
                };
            } else {
                const field = info.fields[i];
                result[i] = .{
                    .name = field.name,
                    .type = field.type,
                    .alignment = field.alignment,
                    .is_comptime = if (@hasField(@TypeOf(field), "is_comptime")) field.is_comptime else false,
                    .default_value_ptr = if (@hasField(@TypeOf(field), "default_value_ptr")) field.default_value_ptr else null,
                };
            }
        }
        const copy = result;
        break :blk &copy;
    };
}
