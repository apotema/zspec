//! Factory Example
//!
//! Demonstrates ZSpec's Factory module (FactoryBot-like test data generation):
//! - Factory.define() - Define factories with default values
//! - Factory.sequence() - Auto-incrementing numeric values
//! - Factory.sequenceFmt() - Formatted sequence strings
//! - Factory.lazy() - Computed values
//! - Factory.assoc() - Nested factory associations
//! - .trait() - Predefined variants
//! - .build() / .buildPtr() - Create instances
//!
//! NOTE: sequenceFmt allocates strings using the provided allocator.
//! When using std.testing.allocator, these will be reported as leaks
//! unless you use an arena allocator for tests that use sequenceFmt.

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const Factory = zspec.Factory;

test {
    zspec.runAll(@This());
}

// Use an arena for tests to avoid memory leak reports from sequenceFmt
var test_arena: std.heap.ArenaAllocator = undefined;
var test_alloc: std.mem.Allocator = undefined;

fn setupArena() void {
    test_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    test_alloc = test_arena.allocator();
}

fn teardownArena() void {
    test_arena.deinit();
}

// =============================================================================
// Model Definitions
// =============================================================================

const Address = struct {
    street: []const u8,
    city: []const u8,
    zip: []const u8,
};

const Company = struct {
    id: u32,
    name: []const u8,
    address: ?*Address,
};

const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    age: u8,
    active: bool,
    role: []const u8,
    company: ?*Company,
};

// =============================================================================
// Factory Definitions
// =============================================================================

const AddressFactory = Factory.define(Address, .{
    .street = "123 Main St",
    .city = "Springfield",
    .zip = "12345",
});

const CompanyFactory = Factory.define(Company, .{
    .id = Factory.sequence(u32),
    .name = "Acme Inc",
    .address = null, // Optional pointer defaults to null
});

const UserFactory = Factory.define(User, .{
    .id = Factory.sequence(u32),
    .name = "John Doe",
    .email = Factory.sequenceFmt("user{d}@example.com"),
    .age = 25,
    .active = true,
    .role = "user",
    .company = null,
});

// Traits - predefined variants
const AdminFactory = UserFactory.trait(.{
    .role = "admin",
});

const InactiveUserFactory = UserFactory.trait(.{
    .active = false,
});

const SeniorUserFactory = UserFactory.trait(.{
    .age = 65,
    .role = "senior",
});

// =============================================================================
// Tests
// =============================================================================

test "tests:beforeAll" {
    Factory.resetSequences();
}

pub const BasicUsage = struct {
    test "tests:before" {
        Factory.resetSequences();
        setupArena();
    }

    test "tests:after" {
        teardownArena();
    }

    test "build creates struct with defaults" {
        const user = UserFactory.buildWith(test_alloc, .{});

        try expect.equal(user.id, 1);
        try expect.toBeTrue(std.mem.eql(u8, user.name, "John Doe"));
        try expect.toBeTrue(std.mem.eql(u8, user.email, "user1@example.com"));
        try expect.equal(user.age, 25);
        try expect.toBeTrue(user.active);
        try expect.toBeTrue(std.mem.eql(u8, user.role, "user"));
        try expect.toBeNull(user.company);
    }

    test "build with overrides" {
        const user = UserFactory.buildWith(test_alloc, .{
            .name = "Jane Smith",
            .age = 30,
        });

        try expect.toBeTrue(std.mem.eql(u8, user.name, "Jane Smith"));
        try expect.equal(user.age, 30);
        // Other fields keep defaults
        try expect.toBeTrue(user.active);
    }

    test "buildPtr creates heap-allocated pointer" {
        const user_ptr = UserFactory.buildPtrWith(test_alloc, .{});
        // No need to free - arena handles it

        try expect.toBeTrue(std.mem.eql(u8, user_ptr.name, "John Doe"));
    }
};

pub const Sequences = struct {
    test "tests:before" {
        Factory.resetSequences();
        setupArena();
    }

    test "tests:after" {
        teardownArena();
    }

    test "sequence increments automatically" {
        const user1 = UserFactory.buildWith(test_alloc, .{});
        const user2 = UserFactory.buildWith(test_alloc, .{});
        const user3 = UserFactory.buildWith(test_alloc, .{});

        try expect.equal(user1.id, 1);
        try expect.equal(user2.id, 2);
        try expect.equal(user3.id, 3);
    }

    test "sequenceFmt formats strings" {
        const user1 = UserFactory.buildWith(test_alloc, .{});
        const user2 = UserFactory.buildWith(test_alloc, .{});

        try expect.toBeTrue(std.mem.eql(u8, user1.email, "user1@example.com"));
        try expect.toBeTrue(std.mem.eql(u8, user2.email, "user2@example.com"));
    }

    test "resetSequences resets all counters" {
        _ = UserFactory.buildWith(test_alloc, .{});
        _ = UserFactory.buildWith(test_alloc, .{});

        Factory.resetSequences();

        const user = UserFactory.buildWith(test_alloc, .{});
        try expect.equal(user.id, 1);
        try expect.toBeTrue(std.mem.eql(u8, user.email, "user1@example.com"));
    }
};

pub const Traits = struct {
    test "tests:before" {
        Factory.resetSequences();
        setupArena();
    }

    test "tests:after" {
        teardownArena();
    }

    test "admin trait sets role" {
        const admin = AdminFactory.buildWith(test_alloc, .{});

        try expect.toBeTrue(std.mem.eql(u8, admin.role, "admin"));
        // Inherits other defaults
        try expect.toBeTrue(std.mem.eql(u8, admin.name, "John Doe"));
        try expect.toBeTrue(admin.active);
    }

    test "inactive trait sets active to false" {
        const inactive = InactiveUserFactory.buildWith(test_alloc, .{});

        try expect.toBeFalse(inactive.active);
    }

    test "senior trait sets multiple fields" {
        const senior = SeniorUserFactory.buildWith(test_alloc, .{});

        try expect.equal(senior.age, 65);
        try expect.toBeTrue(std.mem.eql(u8, senior.role, "senior"));
    }

    test "traits can be overridden" {
        const admin = AdminFactory.buildWith(test_alloc, .{
            .name = "Super Admin",
        });

        try expect.toBeTrue(std.mem.eql(u8, admin.role, "admin"));
        try expect.toBeTrue(std.mem.eql(u8, admin.name, "Super Admin"));
    }
};

pub const Associations = struct {
    test "tests:before" {
        Factory.resetSequences();
        setupArena();
    }

    test "tests:after" {
        teardownArena();
    }

    test "optional pointer defaults to null" {
        const user = UserFactory.buildWith(test_alloc, .{});
        try expect.toBeNull(user.company);
    }

    test "can override with associated factory" {
        const company = CompanyFactory.buildPtrWith(test_alloc, .{});

        const user = UserFactory.buildWith(test_alloc, .{
            .company = company,
        });

        try expect.notToBeNull(user.company);
        try expect.toBeTrue(std.mem.eql(u8, user.company.?.name, "Acme Inc"));
    }

    test "nested associations" {
        const address = AddressFactory.buildPtrWith(test_alloc, .{});

        const company = CompanyFactory.buildPtrWith(test_alloc, .{
            .address = address,
        });

        const user = UserFactory.buildWith(test_alloc, .{
            .company = company,
        });

        try expect.notToBeNull(user.company);
        try expect.notToBeNull(user.company.?.address);
        try expect.toBeTrue(std.mem.eql(u8, user.company.?.address.?.city, "Springfield"));
    }
};

pub const CustomAllocator = struct {
    test "tests:before" {
        Factory.resetSequences();
    }

    test "buildWith uses custom allocator" {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const user = UserFactory.buildWith(alloc, .{});
        try expect.toBeTrue(std.mem.eql(u8, user.name, "John Doe"));
    }

    test "buildPtrWith uses custom allocator" {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const user_ptr = UserFactory.buildPtrWith(alloc, .{});
        // No need to free - arena handles it
        try expect.toBeTrue(std.mem.eql(u8, user_ptr.name, "John Doe"));
    }
};

pub const PracticalExample = struct {
    test "tests:before" {
        Factory.resetSequences();
        setupArena();
    }

    test "tests:after" {
        teardownArena();
    }

    test "creating test data for user management" {
        // Create multiple users with different roles
        const regular_user = UserFactory.buildWith(test_alloc, .{});
        const admin = AdminFactory.buildWith(test_alloc, .{});
        const inactive = InactiveUserFactory.buildWith(test_alloc, .{});

        // Create a company with users
        const company = CompanyFactory.buildPtrWith(test_alloc, .{ .name = "Tech Corp" });

        const employee = UserFactory.buildWith(test_alloc, .{
            .company = company,
            .name = "Employee One",
        });

        // Verify test data
        try expect.toBeTrue(std.mem.eql(u8, regular_user.role, "user"));
        try expect.toBeTrue(std.mem.eql(u8, admin.role, "admin"));
        try expect.toBeFalse(inactive.active);
        try expect.notToBeNull(employee.company);
        try expect.toBeTrue(std.mem.eql(u8, employee.company.?.name, "Tech Corp"));
    }

    test "bulk user creation" {
        var users: [5]User = undefined;

        for (&users, 0..) |*user, i| {
            user.* = UserFactory.buildWith(test_alloc, .{
                .name = if (i == 0) "First User" else "Other User",
            });
        }

        // IDs are sequential
        try expect.equal(users[0].id, 1);
        try expect.equal(users[4].id, 5);

        // First user has custom name
        try expect.toBeTrue(std.mem.eql(u8, users[0].name, "First User"));
        try expect.toBeTrue(std.mem.eql(u8, users[1].name, "Other User"));
    }
};
