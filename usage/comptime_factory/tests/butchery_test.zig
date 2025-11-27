//! Butchery Tests using ZSpec
//!
//! Demonstrates how to test comptime-parameterized types with ZSpec's Factory module.
//! Key patterns shown:
//! - Creating factories for comptime-generic types
//! - Level-specific factory defaults
//! - Factory traits for test scenarios
//! - Cross-level comparison tests

const std = @import("std");
const zspec = @import("zspec");
const butchery = @import("butchery");

const expect = zspec.expect;
const Factory = zspec.Factory;

const Butchery = butchery.Butchery;
const RoomLevel = butchery.RoomLevel;
const MeatType = butchery.MeatType;

test {
    zspec.runAll(@This());
}

// =============================================================================
// Factory Definitions - One factory per level
// =============================================================================

/// Creates a ZSpec Factory for a specific room level.
/// This demonstrates how to wrap comptime-parameterized types in factories.
pub fn ButcheryFactory(comptime level: RoomLevel) type {
    const ButcheryType = Butchery(level);

    return Factory.define(ButcheryType, .{
        .name = switch (level) {
            .basic => "Basic Butchery",
            .standard => "Standard Butchery",
            .advanced => "Advanced Butchery",
            .master => "Master Butchery",
        },
        .capacity = ButcheryType.base_capacity,
        .efficiency = 1.0,
        .worker_count = 1,
        .stored_meat = 0,
    });
}

// Convenient factory aliases for each level
const BasicButcheryFactory = ButcheryFactory(.basic);
const StandardButcheryFactory = ButcheryFactory(.standard);
const AdvancedButcheryFactory = ButcheryFactory(.advanced);
const MasterButcheryFactory = ButcheryFactory(.master);

// Factory traits for common test scenarios
const LowEfficiencyFactory = BasicButcheryFactory.trait(.{ .efficiency = 0.5 });
const HighEfficiencyFactory = BasicButcheryFactory.trait(.{ .efficiency = 1.5 });
const FullStorageBasicFactory = BasicButcheryFactory.trait(.{ .stored_meat = 10 });
const HalfFullStandardFactory = StandardButcheryFactory.trait(.{ .stored_meat = 12 });

// =============================================================================
// Basic Level Tests
// =============================================================================

pub const BasicLevelTests = struct {
    test "tests:before" {
        Factory.resetSequences();
    }

    test "basic butchery has correct defaults" {
        const b = BasicButcheryFactory.build(.{});

        try expect.toBeTrue(std.mem.eql(u8, b.name, "Basic Butchery"));
        try expect.equal(b.capacity, 10);
        try expect.equal(b.worker_count, 1);
        try expect.equal(b.efficiency, 1.0);
        try expect.equal(b.stored_meat, 0);
    }

    test "basic butchery has level-specific constants" {
        const BasicType = Butchery(.basic);

        try expect.equal(BasicType.room_level, .basic);
        try expect.equal(BasicType.base_capacity, 10);
        try expect.equal(BasicType.max_workers, 1);
        try expect.toBeFalse(BasicType.has_cold_storage);
        try expect.toBeFalse(BasicType.has_automation);
    }

    test "basic butchery only processes beef" {
        const b = BasicButcheryFactory.build(.{});

        try expect.toBeTrue(b.canProcess(.beef));
        try expect.toBeFalse(b.canProcess(.pork));
        try expect.toBeFalse(b.canProcess(.lamb));
        try expect.toBeFalse(b.canProcess(.game));
    }

    test "basic butchery process capacity calculation" {
        const b = BasicButcheryFactory.build(.{});

        // Basic: 10 * 1.0 (level) * 1.0 (efficiency) * 1.0 (1 worker) = 10
        try expect.equal(b.processCapacity(), 10);
    }

    test "low efficiency reduces process capacity" {
        const b = LowEfficiencyFactory.build(.{});

        // 10 * 1.0 * 0.5 * 1.0 = 5
        try expect.equal(b.processCapacity(), 5);
    }

    test "high efficiency increases process capacity" {
        const b = HighEfficiencyFactory.build(.{});

        // 10 * 1.0 * 1.5 * 1.0 = 15
        try expect.equal(b.processCapacity(), 15);
    }

    test "basic butchery cannot add more workers" {
        var b = BasicButcheryFactory.build(.{});

        // Already at max (1 worker for basic)
        if (b.addWorker()) |_| {
            return error.ExpectedError;
        } else |err| {
            try expect.equal(err, error.MaxWorkersReached);
        }
    }
};

// =============================================================================
// Standard Level Tests
// =============================================================================

pub const StandardLevelTests = struct {
    test "tests:before" {
        Factory.resetSequences();
    }

    test "standard butchery has correct defaults" {
        const b = StandardButcheryFactory.build(.{});

        try expect.toBeTrue(std.mem.eql(u8, b.name, "Standard Butchery"));
        try expect.equal(b.capacity, 25);
        try expect.equal(b.worker_count, 1);
    }

    test "standard butchery has level-specific constants" {
        const StandardType = Butchery(.standard);

        try expect.equal(StandardType.room_level, .standard);
        try expect.equal(StandardType.base_capacity, 25);
        try expect.equal(StandardType.max_workers, 2);
        try expect.toBeFalse(StandardType.has_cold_storage);
    }

    test "standard butchery processes beef and pork" {
        const b = StandardButcheryFactory.build(.{});

        try expect.toBeTrue(b.canProcess(.beef));
        try expect.toBeTrue(b.canProcess(.pork));
        try expect.toBeFalse(b.canProcess(.lamb));
        try expect.toBeFalse(b.canProcess(.game));
    }

    test "standard has higher process capacity multiplier" {
        const b = StandardButcheryFactory.build(.{});

        // Standard: 25 * 1.5 (level) * 1.0 * 1.0 = 37
        try expect.equal(b.processCapacity(), 37);
    }

    test "standard butchery can add one more worker" {
        var b = StandardButcheryFactory.build(.{});

        try b.addWorker();
        try expect.equal(b.worker_count, 2);

        // Now at max
        if (b.addWorker()) |_| {
            return error.ExpectedError;
        } else |err| {
            try expect.equal(err, error.MaxWorkersReached);
        }
    }

    test "additional worker increases process capacity" {
        var b = StandardButcheryFactory.build(.{});

        const base_capacity = b.processCapacity();
        try b.addWorker();
        const boosted_capacity = b.processCapacity();

        // 2 workers: 25 * 1.5 * 1.0 * 1.25 = 46
        try expect.toBeTrue(boosted_capacity > base_capacity);
        try expect.equal(boosted_capacity, 46);
    }
};

// =============================================================================
// Advanced Level Tests
// =============================================================================

pub const AdvancedLevelTests = struct {
    test "tests:before" {
        Factory.resetSequences();
    }

    test "advanced butchery has cold storage" {
        const AdvancedType = Butchery(.advanced);

        try expect.toBeTrue(AdvancedType.has_cold_storage);
        try expect.toBeFalse(AdvancedType.has_automation);
        try expect.equal(AdvancedType.max_workers, 3);
    }

    test "advanced butchery processes three meat types" {
        const b = AdvancedButcheryFactory.build(.{});

        try expect.toBeTrue(b.canProcess(.beef));
        try expect.toBeTrue(b.canProcess(.pork));
        try expect.toBeTrue(b.canProcess(.lamb));
        try expect.toBeFalse(b.canProcess(.game));
    }

    test "advanced has 2x process multiplier" {
        const b = AdvancedButcheryFactory.build(.{});

        // Advanced: 50 * 2.0 * 1.0 * 1.0 = 100
        try expect.equal(b.processCapacity(), 100);
    }

    test "cold storage provides price bonus on sales" {
        var b = AdvancedButcheryFactory.build(.{ .stored_meat = 10 });

        // Sell 10 beef at 10 per unit = 100, with 20% cold storage bonus = 120
        const revenue = try b.sellMeat(.beef, 10);
        try expect.equal(revenue, 120);
    }
};

// =============================================================================
// Master Level Tests
// =============================================================================

pub const MasterLevelTests = struct {
    test "tests:before" {
        Factory.resetSequences();
    }

    test "master butchery has all features" {
        const MasterType = Butchery(.master);

        try expect.toBeTrue(MasterType.has_cold_storage);
        try expect.toBeTrue(MasterType.has_automation);
        try expect.equal(MasterType.max_workers, 4);
        try expect.equal(MasterType.base_capacity, 100);
    }

    test "master butchery processes all meat types" {
        const b = MasterButcheryFactory.build(.{});

        try expect.toBeTrue(b.canProcess(.beef));
        try expect.toBeTrue(b.canProcess(.pork));
        try expect.toBeTrue(b.canProcess(.lamb));
        try expect.toBeTrue(b.canProcess(.game));
    }

    test "master has highest process capacity" {
        const b = MasterButcheryFactory.build(.{});

        // Master: 100 * 3.0 * 1.0 * 1.0 = 300
        try expect.equal(b.processCapacity(), 300);
    }

    test "master with full workers has massive capacity" {
        var b = MasterButcheryFactory.build(.{});

        // Add 3 more workers (4 total)
        try b.addWorker();
        try b.addWorker();
        try b.addWorker();

        // 100 * 3.0 * 1.0 * 1.75 (4 workers) = 525
        try expect.equal(b.processCapacity(), 525);
    }
};

// =============================================================================
// Cross-Level Comparison Tests
// =============================================================================

pub const CrossLevelTests = struct {
    test "tests:before" {
        Factory.resetSequences();
    }

    test "capacity increases with level" {
        const basic = BasicButcheryFactory.build(.{});
        const standard = StandardButcheryFactory.build(.{});
        const advanced = AdvancedButcheryFactory.build(.{});
        const master = MasterButcheryFactory.build(.{});

        try expect.toBeTrue(basic.capacity < standard.capacity);
        try expect.toBeTrue(standard.capacity < advanced.capacity);
        try expect.toBeTrue(advanced.capacity < master.capacity);
    }

    test "process capacity scales with level" {
        const basic = BasicButcheryFactory.build(.{});
        const standard = StandardButcheryFactory.build(.{});
        const advanced = AdvancedButcheryFactory.build(.{});
        const master = MasterButcheryFactory.build(.{});

        const basic_cap = basic.processCapacity();
        const standard_cap = standard.processCapacity();
        const advanced_cap = advanced.processCapacity();
        const master_cap = master.processCapacity();

        try expect.toBeTrue(standard_cap > basic_cap);
        try expect.toBeTrue(advanced_cap > standard_cap);
        try expect.toBeTrue(master_cap > advanced_cap);
    }

    test "meat type support expands with level" {
        try expect.toHaveLength(Butchery(.basic).supported_meats, 1);
        try expect.toHaveLength(Butchery(.standard).supported_meats, 2);
        try expect.toHaveLength(Butchery(.advanced).supported_meats, 3);
        try expect.toHaveLength(Butchery(.master).supported_meats, 4);
    }

    test "comptime room level is accessible for type introspection" {
        try expect.equal(Butchery(.basic).room_level, .basic);
        try expect.equal(Butchery(.standard).room_level, .standard);
        try expect.equal(Butchery(.advanced).room_level, .advanced);
        try expect.equal(Butchery(.master).room_level, .master);
    }
};

// =============================================================================
// Meat Processing Tests
// =============================================================================

pub const MeatProcessingTests = struct {
    test "tests:before" {
        Factory.resetSequences();
    }

    test "can process supported meat type" {
        var b = BasicButcheryFactory.build(.{});

        const processed = try b.processMeat(.beef, 5);

        try expect.equal(processed, 5);
        try expect.equal(b.stored_meat, 5);
    }

    test "cannot process unsupported meat type" {
        var b = BasicButcheryFactory.build(.{});

        if (b.processMeat(.pork, 5)) |_| {
            return error.ExpectedError;
        } else |err| {
            try expect.equal(err, error.UnsupportedMeatType);
        }
        try expect.equal(b.stored_meat, 0);
    }

    test "processing is limited by capacity" {
        var b = BasicButcheryFactory.build(.{ .stored_meat = 8 });

        // Try to process 5, but only 2 capacity remaining
        const processed = try b.processMeat(.beef, 5);

        try expect.equal(processed, 2);
        try expect.equal(b.stored_meat, 10);
        try expect.toBeTrue(b.isFull());
    }

    test "cannot process when full" {
        var b = FullStorageBasicFactory.build(.{});

        const processed = try b.processMeat(.beef, 5);

        try expect.equal(processed, 0);
    }

    test "utilization percentage calculation" {
        const half_full = HalfFullStandardFactory.build(.{});

        // 12 / 25 * 100 = 48%
        try expect.equal(half_full.utilizationPercent(), 48.0);
    }
};

// =============================================================================
// Sales Tests
// =============================================================================

pub const SalesTests = struct {
    test "tests:before" {
        Factory.resetSequences();
    }

    test "can sell stored meat" {
        var b = BasicButcheryFactory.build(.{ .stored_meat = 10 });

        // Sell 5 beef at 10 per unit = 50 (no cold storage bonus)
        const revenue = try b.sellMeat(.beef, 5);

        try expect.equal(revenue, 50);
        try expect.equal(b.stored_meat, 5);
    }

    test "cannot sell more than stored" {
        var b = BasicButcheryFactory.build(.{ .stored_meat = 3 });

        if (b.sellMeat(.beef, 5)) |_| {
            return error.ExpectedError;
        } else |err| {
            try expect.equal(err, error.InsufficientStock);
        }
        try expect.equal(b.stored_meat, 3);
    }

    test "different meat types have different prices" {
        var advanced = AdvancedButcheryFactory.build(.{ .stored_meat = 10 });

        // Beef: 10 * 10 * 1.2 = 120
        const beef_revenue = try advanced.sellMeat(.beef, 10);
        try expect.equal(beef_revenue, 120);

        // Reset storage for next test
        advanced.stored_meat = 10;

        // Lamb: 10 * 15 * 1.2 = 180
        const lamb_revenue = try advanced.sellMeat(.lamb, 10);
        try expect.equal(lamb_revenue, 180);
    }

    test "cold storage bonus only applies to advanced and master" {
        var basic = BasicButcheryFactory.build(.{ .stored_meat = 10 });
        var advanced = AdvancedButcheryFactory.build(.{ .stored_meat = 10 });

        const basic_revenue = try basic.sellMeat(.beef, 10);
        const advanced_revenue = try advanced.sellMeat(.beef, 10);

        // Basic: 10 * 10 = 100 (no bonus)
        // Advanced: 10 * 10 * 1.2 = 120 (20% bonus)
        try expect.equal(basic_revenue, 100);
        try expect.equal(advanced_revenue, 120);
    }
};

// =============================================================================
// Override Tests - Customizing factory output
// =============================================================================

pub const OverrideTests = struct {
    test "tests:before" {
        Factory.resetSequences();
    }

    test "can override name at build time" {
        const b = BasicButcheryFactory.build(.{
            .name = "My Custom Butchery",
        });

        try expect.toBeTrue(std.mem.eql(u8, b.name, "My Custom Butchery"));
        // Other defaults remain
        try expect.equal(b.capacity, 10);
    }

    test "can override multiple fields" {
        const b = StandardButcheryFactory.build(.{
            .name = "High-Efficiency Butchery",
            .efficiency = 1.5,
            .worker_count = 2,
        });

        try expect.toBeTrue(std.mem.eql(u8, b.name, "High-Efficiency Butchery"));
        try expect.equal(b.efficiency, 1.5);
        try expect.equal(b.worker_count, 2);

        // 25 * 1.5 * 1.5 * 1.25 = 70
        try expect.equal(b.processCapacity(), 70);
    }

    test "can start with pre-filled storage" {
        const b = BasicButcheryFactory.build(.{
            .stored_meat = 5,
        });

        try expect.equal(b.stored_meat, 5);
        try expect.equal(b.utilizationPercent(), 50.0);
    }

    test "trait creates reusable variant" {
        const b = FullStorageBasicFactory.build(.{});

        try expect.equal(b.stored_meat, 10);
        try expect.toBeTrue(b.isFull());
        // Still has basic level characteristics
        try expect.equal(b.capacity, 10);
    }

    test "trait can be further overridden" {
        const b = FullStorageBasicFactory.build(.{
            .name = "Full Custom Butchery",
        });

        try expect.toBeTrue(std.mem.eql(u8, b.name, "Full Custom Butchery"));
        try expect.equal(b.stored_meat, 10);
    }
};
