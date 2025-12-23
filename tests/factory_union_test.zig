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

// Edge case: void union payload
pub const FACTORY_UNION_VOID_PAYLOAD = struct {
    const State = union(enum) {
        idle: void,
        running: struct { speed: f32 },
        stopped: void,
    };

    const Entity = struct {
        state: State,
        id: u32,
    };

    test "factory with void union payload" {
        const EntityFactory = Factory.define(Entity, .{
            .state = .{ .idle = {} },
            .id = 1,
        });

        const entity = EntityFactory.build(.{});
        try expect.equal(entity.id, 1);
        try expect.toBeTrue(entity.state == .idle);
    }

    test "factory with void union payload override" {
        const EntityFactory = Factory.define(Entity, .{
            .state = .{ .idle = {} },
            .id = 1,
        });

        const entity = EntityFactory.build(.{
            .state = .{ .stopped = {} },
        });
        try expect.toBeTrue(entity.state == .stopped);
    }

    test "factory switching from void to struct payload" {
        const EntityFactory = Factory.define(Entity, .{
            .state = .{ .idle = {} },
            .id = 1,
        });

        const entity = EntityFactory.build(.{
            .state = .{ .running = .{ .speed = 5.0 } },
        });

        switch (entity.state) {
            .running => |r| try expect.equal(r.speed, 5.0),
            else => return error.UnexpectedState,
        }
    }
};

// Edge case: optional union fields
pub const FACTORY_UNION_OPTIONAL = struct {
    const OptionalShapeEntity = struct {
        shape: ?Shape,
        name: []const u8,
    };

    test "factory with optional union field null" {
        const EntityFactory = Factory.define(OptionalShapeEntity, .{
            .shape = null,
            .name = "empty",
        });

        const entity = EntityFactory.build(.{});
        try expect.toBeTrue(entity.shape == null);
        try std.testing.expectEqualStrings("empty", entity.name);
    }

    test "factory with optional union field set" {
        const EntityFactory = Factory.define(OptionalShapeEntity, .{
            .shape = Shape{ .circle = .{ .radius = 5.0 } },
            .name = "circle",
        });

        const entity = EntityFactory.build(.{});
        try expect.toBeTrue(entity.shape != null);

        if (entity.shape) |shape| {
            switch (shape) {
                .circle => |c| try expect.equal(c.radius, 5.0),
                .rectangle => return error.UnexpectedShape,
            }
        }
    }

    test "factory override optional union from null to value" {
        const EntityFactory = Factory.define(OptionalShapeEntity, .{
            .shape = null,
            .name = "empty",
        });

        const entity = EntityFactory.build(.{
            .shape = Shape{ .rectangle = .{ .width = 10.0, .height = 20.0 } },
        });

        try expect.toBeTrue(entity.shape != null);
    }
};

// Edge case: payload struct with default values
pub const FACTORY_UNION_DEFAULTED_PAYLOAD = struct {
    const Config = struct {
        enabled: bool = true,
        priority: u8 = 10,
        name: []const u8,
    };

    const Setting = union(enum) {
        custom: Config,
        preset: []const u8,
    };

    const SettingHolder = struct {
        setting: Setting,
        id: u32,
    };

    test "factory with payload struct omitting defaulted fields" {
        const SettingFactory = Factory.define(SettingHolder, .{
            // Only provide required field 'name', rely on defaults for enabled/priority
            .setting = .{ .custom = .{ .name = "test" } },
            .id = 1,
        });

        const holder = SettingFactory.build(.{});
        try expect.equal(holder.id, 1);

        switch (holder.setting) {
            .custom => |c| {
                try std.testing.expectEqualStrings("test", c.name);
                try expect.toBeTrue(c.enabled); // default value
                try expect.equal(c.priority, 10); // default value
            },
            .preset => return error.UnexpectedSetting,
        }
    }
};

// Edge case: trait chaining with mixed types
pub const FACTORY_TRAIT_CHAINING = struct {
    const Item = struct {
        name: []const u8,
        value: u32,
        active: bool,
    };

    test "trait chaining preserves all fields" {
        const ItemFactory = Factory.define(Item, .{
            .name = "default",
            .value = 0,
            .active = false,
        });

        const ActiveFactory = ItemFactory.trait(.{
            .active = true,
        });

        const NamedActiveFactory = ActiveFactory.trait(.{
            .name = "named",
        });

        const item = NamedActiveFactory.build(.{});
        try std.testing.expectEqualStrings("named", item.name);
        try expect.equal(item.value, 0); // from base
        try expect.toBeTrue(item.active); // from first trait
    }

    test "trait chaining with union field type changes" {
        const ShapeVisualFactory = Factory.define(ShapeVisual, .{
            .shape = .{ .circle = .{ .radius = 10.0 } },
            .z_index = 128,
        });

        // First trait: change shape to rectangle
        const RectFactory = ShapeVisualFactory.trait(.{
            .shape = .{ .rectangle = .{ .width = 20.0, .height = 30.0 } },
        });

        // Second trait: change z_index only
        const HighZRectFactory = RectFactory.trait(.{
            .z_index = 255,
        });

        const visual = HighZRectFactory.build(.{});
        try expect.equal(visual.z_index, 255);

        switch (visual.shape) {
            .rectangle => |r| {
                try expect.equal(r.width, 20.0);
                try expect.equal(r.height, 30.0);
            },
            .circle => return error.UnexpectedShape,
        }
    }
};
