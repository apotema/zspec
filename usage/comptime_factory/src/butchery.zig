//! Butchery - A comptime-parameterized room type
//!
//! Demonstrates a common Zig pattern where a type's capabilities
//! vary based on a comptime parameter (room level).

const std = @import("std");

pub const RoomLevel = enum(u8) {
    basic = 1,
    standard = 2,
    advanced = 3,
    master = 4,

    pub fn toMultiplier(self: RoomLevel) f32 {
        return switch (self) {
            .basic => 1.0,
            .standard => 1.5,
            .advanced => 2.0,
            .master => 3.0,
        };
    }
};

pub const MeatType = enum {
    beef,
    pork,
    lamb,
    game,

    pub fn basePricePerUnit(self: MeatType) u32 {
        return switch (self) {
            .beef => 10,
            .pork => 8,
            .lamb => 15,
            .game => 25,
        };
    }
};

/// A Butchery room whose capabilities vary by level.
/// Higher levels unlock more meat types, storage, and automation.
pub fn Butchery(comptime level: RoomLevel) type {
    return struct {
        const Self = @This();

        /// The comptime room level - accessible for type introspection
        pub const room_level = level;

        /// Level-specific constants
        pub const base_capacity: u32 = switch (level) {
            .basic => 10,
            .standard => 25,
            .advanced => 50,
            .master => 100,
        };

        pub const max_workers: u8 = switch (level) {
            .basic => 1,
            .standard => 2,
            .advanced => 3,
            .master => 4,
        };

        pub const supported_meats: []const MeatType = switch (level) {
            .basic => &[_]MeatType{.beef},
            .standard => &[_]MeatType{ .beef, .pork },
            .advanced => &[_]MeatType{ .beef, .pork, .lamb },
            .master => &[_]MeatType{ .beef, .pork, .lamb, .game },
        };

        pub const has_cold_storage: bool = level == .advanced or level == .master;
        pub const has_automation: bool = level == .master;

        // Instance fields
        name: []const u8,
        capacity: u32,
        efficiency: f32,
        worker_count: u8,
        stored_meat: u32,

        /// Create a new butchery with default values for this level
        pub fn init(name: []const u8) Self {
            return .{
                .name = name,
                .capacity = base_capacity,
                .efficiency = 1.0,
                .worker_count = 1,
                .stored_meat = 0,
            };
        }

        /// Calculate the effective processing capacity
        pub fn processCapacity(self: Self) u32 {
            const base: f32 = @floatFromInt(self.capacity);
            const worker_bonus: f32 = 1.0 + @as(f32, @floatFromInt(self.worker_count - 1)) * 0.25;
            const level_mult = level.toMultiplier();
            return @intFromFloat(base * level_mult * self.efficiency * worker_bonus);
        }

        /// Check if this butchery can process a given meat type
        pub fn canProcess(_: Self, meat: MeatType) bool {
            for (supported_meats) |mt| {
                if (mt == meat) return true;
            }
            return false;
        }

        /// Process meat and add to storage (returns amount actually processed)
        pub fn processMeat(self: *Self, meat: MeatType, amount: u32) !u32 {
            if (!self.canProcess(meat)) {
                return error.UnsupportedMeatType;
            }

            const capacity_remaining = self.capacity - self.stored_meat;
            const to_process = @min(amount, capacity_remaining);

            self.stored_meat += to_process;
            return to_process;
        }

        /// Sell stored meat and return revenue
        pub fn sellMeat(self: *Self, meat: MeatType, amount: u32) !u32 {
            if (amount > self.stored_meat) {
                return error.InsufficientStock;
            }

            self.stored_meat -= amount;
            const base_price = meat.basePricePerUnit();

            // Cold storage provides 20% price bonus
            const storage_bonus: f32 = if (has_cold_storage) 1.2 else 1.0;

            return @intFromFloat(@as(f32, @floatFromInt(amount * base_price)) * storage_bonus);
        }

        /// Add a worker (up to max for this level)
        pub fn addWorker(self: *Self) !void {
            if (self.worker_count >= max_workers) {
                return error.MaxWorkersReached;
            }
            self.worker_count += 1;
        }

        /// Check if storage is full
        pub fn isFull(self: Self) bool {
            return self.stored_meat >= self.capacity;
        }

        /// Get storage utilization as a percentage
        pub fn utilizationPercent(self: Self) f32 {
            return @as(f32, @floatFromInt(self.stored_meat)) / @as(f32, @floatFromInt(self.capacity)) * 100.0;
        }
    };
}

// Type aliases for convenience
pub const BasicButchery = Butchery(.basic);
pub const StandardButchery = Butchery(.standard);
pub const AdvancedButchery = Butchery(.advanced);
pub const MasterButchery = Butchery(.master);
