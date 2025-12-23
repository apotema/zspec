//! Tests for Factory with union type fields
//! Related to issue #29

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const Factory = zspec.Factory;

test {
    zspec.runAll(@This());
}

const Shape = union(enum) {
    circle: struct { radius: f32 },
    rectangle: struct { width: f32, height: f32 },
};

const ShapeVisual = struct {
    shape: Shape,
    z_index: u8,
};

pub const FACTORY_UNION_EXPLICIT_SYNTAX = struct {
    test "factory with union field" {
        const ShapeVisualFactory = Factory.define(ShapeVisual, .{
            .shape = Shape{ .circle = .{ .radius = 10.0 } },
            .z_index = 128,
        });

        const visual = ShapeVisualFactory.build(.{});
        try expect.equal(visual.z_index, 128);

        switch (visual.shape) {
            .circle => |c| try expect.equal(c.radius, 10.0),
            .rectangle => return error.UnexpectedShape,
        }
    }

    test "factory with union field override" {
        const ShapeVisualFactory = Factory.define(ShapeVisual, .{
            .shape = Shape{ .circle = .{ .radius = 10.0 } },
            .z_index = 128,
        });

        // Override with rectangle
        const visual = ShapeVisualFactory.build(.{
            .shape = Shape{ .rectangle = .{ .width = 20.0, .height = 30.0 } },
        });

        switch (visual.shape) {
            .rectangle => |r| {
                try expect.equal(r.width, 20.0);
                try expect.equal(r.height, 30.0);
            },
            .circle => return error.UnexpectedShape,
        }
    }
};

pub const FACTORY_UNION_ANONYMOUS_SYNTAX = struct {
    test "factory with union field using anonymous struct syntax" {
        // Using anonymous struct syntax for union initialization
        const ShapeVisualFactory = Factory.define(ShapeVisual, .{
            .shape = .{ .circle = .{ .radius = 10.0 } },
            .z_index = 128,
        });

        const visual = ShapeVisualFactory.build(.{});
        try expect.equal(visual.z_index, 128);

        switch (visual.shape) {
            .circle => |c| try expect.equal(c.radius, 10.0),
            .rectangle => return error.UnexpectedShape,
        }
    }

    test "factory with union field override using anonymous struct syntax" {
        const ShapeVisualFactory = Factory.define(ShapeVisual, .{
            .shape = .{ .circle = .{ .radius = 10.0 } },
            .z_index = 128,
        });

        // Override with rectangle using anonymous struct syntax
        const visual = ShapeVisualFactory.build(.{
            .shape = .{ .rectangle = .{ .width = 20.0, .height = 30.0 } },
        });

        switch (visual.shape) {
            .rectangle => |r| {
                try expect.equal(r.width, 20.0);
                try expect.equal(r.height, 30.0);
            },
            .circle => return error.UnexpectedShape,
        }
    }

    test "factory trait with union field using anonymous struct syntax" {
        const ShapeVisualFactory = Factory.define(ShapeVisual, .{
            .shape = .{ .circle = .{ .radius = 10.0 } },
            .z_index = 128,
        });

        // Trait that changes the default shape to rectangle
        const RectangleVisualFactory = ShapeVisualFactory.trait(.{
            .shape = .{ .rectangle = .{ .width = 50.0, .height = 25.0 } },
        });

        const visual = RectangleVisualFactory.build(.{});
        try expect.equal(visual.z_index, 128);

        switch (visual.shape) {
            .rectangle => |r| {
                try expect.equal(r.width, 50.0);
                try expect.equal(r.height, 25.0);
            },
            .circle => return error.UnexpectedShape,
        }
    }
};
