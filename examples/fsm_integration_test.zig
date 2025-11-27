//! FSM Integration Example
//!
//! Demonstrates how to use ZSpec with zigfsm (https://github.com/cryptocode/zigfsm)
//! for testing finite state machines.
//!
//! Features:
//! - Factory-based state machine configuration
//! - Testing state transitions
//! - Testing event handling
//! - Verifying state sequences
//! - Using before/after hooks for FSM setup
//!
//! NOTE: This example shows the integration pattern but does not actually
//! import zigfsm since it's not a dependency. To use this pattern:
//!
//! 1. Add zigfsm to your build.zig.zon:
//!    .dependencies = .{
//!        .zspec = .{
//!            .url = "https://github.com/apotema/zspec/archive/refs/heads/main.tar.gz",
//!            .hash = "...",
//!        },
//!        .zigfsm = .{
//!            .url = "https://github.com/cryptocode/zigfsm/archive/refs/heads/main.tar.gz",
//!            .hash = "...",
//!        },
//!    },
//!
//! 2. In your build.zig, get modules:
//!    const zspec_dep = b.dependency("zspec", .{ .target = target, .optimize = optimize });
//!    const zspec_mod = zspec_dep.module("zspec");
//!    const zspec_fsm_mod = zspec_dep.module("zspec-fsm");
//!    const zigfsm_dep = b.dependency("zigfsm", .{ .target = target, .optimize = optimize });
//!
//! 3. Add to your build.zig test imports:
//!    .imports = &.{
//!        .{ .name = "zspec", .module = zspec_mod },
//!        .{ .name = "zspec-fsm", .module = zspec_fsm_mod },
//!        .{ .name = "zigfsm", .module = zigfsm_dep.module("zigfsm") },
//!    },

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const Factory = zspec.Factory;

// Import the optional FSM integration module
const FSM = @import("zspec-fsm");

// Mock zigfsm for demonstration
// In real usage: const zigfsm = @import("zigfsm");
const zigfsm = struct {
    pub fn StateMachine(comptime StateT: type, comptime EventT: type, comptime initial: StateT) type {
        return struct {
            state: StateT = initial,
            transitions: std.ArrayList(Transition),
            allocator: std.mem.Allocator,

            const Self = @This();
            pub const State = StateT;
            pub const Event = EventT;

            const Transition = struct {
                event: ?Event,
                from: State,
                to: State,
            };

            pub fn init() Self {
                return .{
                    .transitions = std.ArrayList(Transition).init(std.testing.allocator),
                    .allocator = std.testing.allocator,
                };
            }

            pub fn deinit(self: *Self) void {
                // Zig 0.15+ requires allocator parameter
                if (@hasDecl(std.ArrayList(Transition), "deinit")) {
                    if (@typeInfo(@TypeOf(std.ArrayList(Transition).deinit)).@"fn".params.len == 2) {
                        self.transitions.deinit(self.allocator);
                    } else {
                        self.transitions.deinit();
                    }
                } else {
                    self.transitions.deinit();
                }
            }

            pub fn addTransition(self: *Self, from: StateT, to: StateT) !void {
                // Zig 0.15+ requires allocator parameter
                if (@typeInfo(@TypeOf(std.ArrayList(Transition).append)).@"fn".params.len == 3) {
                    try self.transitions.append(self.allocator, .{ .event = null, .from = from, .to = to });
                } else {
                    try self.transitions.append(.{ .event = null, .from = from, .to = to });
                }
            }

            pub fn addEventAndTransition(self: *Self, event: EventT, from: StateT, to: StateT) !void {
                // Zig 0.15+ requires allocator parameter
                if (@typeInfo(@TypeOf(std.ArrayList(Transition).append)).@"fn".params.len == 3) {
                    try self.transitions.append(self.allocator, .{ .event = event, .from = from, .to = to });
                } else {
                    try self.transitions.append(.{ .event = event, .from = from, .to = to });
                }
            }

            pub fn do(self: *Self, event: EventT) !void {
                for (self.transitions.items) |t| {
                    if (t.event) |e| {
                        if (e == event and t.from == self.state) {
                            self.state = t.to;
                            return;
                        }
                    }
                }
                return error.InvalidTransition;
            }

            pub fn transitionTo(self: *Self, to: StateT) !void {
                for (self.transitions.items) |t| {
                    if (t.from == self.state and t.to == to) {
                        self.state = to;
                        return;
                    }
                }
                return error.InvalidTransition;
            }

            pub fn isCurrently(self: *const Self, state: StateT) bool {
                return self.state == state;
            }

            pub fn canTransitionTo(self: *const Self, to: StateT) bool {
                for (self.transitions.items) |t| {
                    if (t.from == self.state and t.to == to) {
                        return true;
                    }
                }
                return false;
            }
        };
    }
};

test {
    zspec.runAll(@This());
}

// =============================================================================
// State and Event Definitions
// =============================================================================

const DoorState = enum {
    closed,
    open,
    locked,
};

const DoorEvent = enum {
    open_door,
    close_door,
    lock_door,
    unlock_door,
};

const TrafficLightState = enum {
    red,
    yellow,
    green,
};

const TrafficLightEvent = enum {
    timer,
};

const PlayerState = enum {
    idle,
    walking,
    running,
    jumping,
    falling,
};

const PlayerEvent = enum {
    walk,
    run,
    jump,
    land,
    stop,
};

// =============================================================================
// Basic FSM Tests
// =============================================================================

pub const BasicFSMTests = struct {
    const DoorFSM = zigfsm.StateMachine(DoorState, DoorEvent, .closed);
    var fsm: DoorFSM = undefined;

    test "tests:before" {
        fsm = DoorFSM.init();
        try fsm.addEventAndTransition(.open_door, .closed, .open);
        try fsm.addEventAndTransition(.close_door, .open, .closed);
        try fsm.addEventAndTransition(.lock_door, .closed, .locked);
        try fsm.addEventAndTransition(.unlock_door, .locked, .closed);
    }

    test "tests:after" {
        fsm.deinit();
    }

    test "initial state is closed" {
        try expect.toBeTrue(fsm.isCurrently(.closed));
    }

    test "can open door from closed" {
        try fsm.do(.open_door);
        try expect.toBeTrue(fsm.isCurrently(.open));
    }

    test "can close door from open" {
        try fsm.do(.open_door);
        try fsm.do(.close_door);
        try expect.toBeTrue(fsm.isCurrently(.closed));
    }

    test "can lock and unlock door" {
        try fsm.do(.lock_door);
        try expect.toBeTrue(fsm.isCurrently(.locked));

        try fsm.do(.unlock_door);
        try expect.toBeTrue(fsm.isCurrently(.closed));
    }

    test "cannot open locked door" {
        try fsm.do(.lock_door);
        const result = fsm.do(.open_door);
        try expect.toBeTrue(std.meta.isError(result));
    }
};

// =============================================================================
// FSM Helper Tests
// =============================================================================

pub const FSMHelperTests = struct {
    const TrafficFSM = zigfsm.StateMachine(TrafficLightState, TrafficLightEvent, .red);
    var fsm: TrafficFSM = undefined;

    test "tests:before" {
        fsm = TrafficFSM.init();
        try FSM.addTransitions(TrafficFSM, &fsm, &.{
            .{ .event = .timer, .from = .red, .to = .green },
            .{ .event = .timer, .from = .green, .to = .yellow },
            .{ .event = .timer, .from = .yellow, .to = .red },
        });
    }

    test "tests:after" {
        fsm.deinit();
    }

    test "addTransitions helper sets up FSM" {
        try expect.toBeTrue(fsm.isCurrently(.red));
        try expect.toBeTrue(fsm.canTransitionTo(.green));
    }

    test "applyEventsAndVerify validates event sequence" {
        try FSM.applyEventsAndVerify(TrafficFSM, &fsm, &.{
            .timer,
            .timer,
            .timer,
        }, .red);

        // Should be back to red after full cycle
        try expect.toBeTrue(fsm.isCurrently(.red));
    }

    test "expectValidNextStates checks valid transitions" {
        try FSM.expectValidNextStates(TrafficFSM, &fsm, &.{.green});
    }

    test "expectInvalidNextStates checks invalid transitions" {
        try FSM.expectInvalidNextStates(TrafficFSM, &fsm, &.{ .yellow, .red });
    }
};

// =============================================================================
// FSM Builder Pattern Tests
// =============================================================================

pub const FSMBuilderTests = struct {
    test "FSM builder creates configured state machine" {
        const SimpleFSM = zigfsm.StateMachine(enum { a, b, c }, enum { next }, .a);
        const Builder = FSM.FSMBuilder(SimpleFSM);

        var builder = Builder.init();
        _ = try builder.withEvent(.next, .a, .b);
        _ = try builder.withEvent(.next, .b, .c);
        _ = try builder.withTransition(.c, .a);

        var fsm = builder.build();
        defer fsm.deinit();

        try expect.toBeTrue(fsm.isCurrently(.a));
        try fsm.do(.next);
        try expect.toBeTrue(fsm.isCurrently(.b));
    }
};

// =============================================================================
// Complex Game State Machine Tests
// =============================================================================

pub const PlayerStateMachineTests = struct {
    const PlayerFSM = zigfsm.StateMachine(PlayerState, PlayerEvent, .idle);
    var fsm: PlayerFSM = undefined;

    test "tests:beforeAll" {
        Factory.resetSequences();
    }

    test "tests:before" {
        fsm = PlayerFSM.init();
        // Idle transitions
        try fsm.addEventAndTransition(.walk, .idle, .walking);
        try fsm.addEventAndTransition(.run, .idle, .running);
        try fsm.addEventAndTransition(.jump, .idle, .jumping);

        // Walking transitions
        try fsm.addEventAndTransition(.run, .walking, .running);
        try fsm.addEventAndTransition(.stop, .walking, .idle);
        try fsm.addEventAndTransition(.jump, .walking, .jumping);

        // Running transitions
        try fsm.addEventAndTransition(.walk, .running, .walking);
        try fsm.addEventAndTransition(.stop, .running, .idle);
        try fsm.addEventAndTransition(.jump, .running, .jumping);

        // Jumping transitions
        try fsm.addEventAndTransition(.land, .jumping, .idle);

        // Falling transitions (automatic from jumping)
        try fsm.addTransition(.jumping, .falling);
        try fsm.addEventAndTransition(.land, .falling, .idle);
    }

    test "tests:after" {
        fsm.deinit();
    }

    test "player starts idle" {
        try expect.toBeTrue(fsm.isCurrently(.idle));
    }

    test "player can walk from idle" {
        try fsm.do(.walk);
        try expect.toBeTrue(fsm.isCurrently(.walking));
    }

    test "player can run from idle or walking" {
        try fsm.do(.walk);
        try fsm.do(.run);
        try expect.toBeTrue(fsm.isCurrently(.running));
    }

    test "player can jump from any ground state" {
        try fsm.do(.walk);
        try fsm.do(.jump);
        try expect.toBeTrue(fsm.isCurrently(.jumping));
    }

    test "player returns to idle after landing" {
        try fsm.do(.jump);
        try fsm.do(.land);
        try expect.toBeTrue(fsm.isCurrently(.idle));
    }

    test "complex movement sequence" {
        // Start idle -> walk -> run -> jump -> land -> idle
        try FSM.applyEventsAndVerify(PlayerFSM, &fsm, &.{
            .walk,
            .run,
            .jump,
            .land,
        }, .idle);
    }

    test "verify valid next states from idle" {
        try FSM.expectValidNextStates(PlayerFSM, &fsm, &.{
            .walking,
            .running,
            .jumping,
        });
    }

    test "verify invalid transitions from jumping" {
        try fsm.do(.jump);
        try FSM.expectInvalidNextStates(PlayerFSM, &fsm, &.{
            .walking,
            .running,
            .jumping,
        });
    }
};

// =============================================================================
// State Machine Pattern Tests
// =============================================================================

pub const PatternTests = struct {
    test "toggle pattern" {
        const ToggleFSM = zigfsm.StateMachine(enum { on, off }, enum { toggle }, .off);
        var fsm = ToggleFSM.init();
        defer fsm.deinit();

        try fsm.addEventAndTransition(.toggle, .off, .on);
        try fsm.addEventAndTransition(.toggle, .on, .off);

        // Toggle on
        try fsm.do(.toggle);
        try expect.toBeTrue(fsm.isCurrently(.on));

        // Toggle off
        try fsm.do(.toggle);
        try expect.toBeTrue(fsm.isCurrently(.off));

        // Toggle on again
        try fsm.do(.toggle);
        try expect.toBeTrue(fsm.isCurrently(.on));
    }

    test "linear progression pattern" {
        const ProgressFSM = zigfsm.StateMachine(
            enum { step1, step2, step3, done },
            enum { next },
            .step1,
        );
        var fsm = ProgressFSM.init();
        defer fsm.deinit();

        try FSM.addTransitions(ProgressFSM, &fsm, &.{
            .{ .event = .next, .from = .step1, .to = .step2 },
            .{ .event = .next, .from = .step2, .to = .step3 },
            .{ .event = .next, .from = .step3, .to = .done },
        });

        try FSM.applyEventsAndVerify(ProgressFSM, &fsm, &.{ .next, .next, .next }, .done);
    }

    test "cycle pattern" {
        const CycleFSM = zigfsm.StateMachine(
            enum { a, b, c },
            enum { advance },
            .a,
        );
        var fsm = CycleFSM.init();
        defer fsm.deinit();

        try fsm.addEventAndTransition(.advance, .a, .b);
        try fsm.addEventAndTransition(.advance, .b, .c);
        try fsm.addEventAndTransition(.advance, .c, .a);

        // Complete two full cycles
        for (0..2) |_| {
            try fsm.do(.advance);
            try expect.toBeTrue(fsm.isCurrently(.b));
            try fsm.do(.advance);
            try expect.toBeTrue(fsm.isCurrently(.c));
            try fsm.do(.advance);
            try expect.toBeTrue(fsm.isCurrently(.a));
        }
    }
};

// =============================================================================
// Summary
// =============================================================================

// Key patterns demonstrated:
//
// 1. Basic FSM Setup:
//    - Define states and events as enums
//    - Create StateMachine type with initial state
//    - Add transitions and events in before hooks
//    - Clean up in after hooks
//
// 2. Testing Transitions:
//    - Use fsm.do(event) to trigger transitions
//    - Use fsm.isCurrently(state) to verify current state
//    - Use fsm.canTransitionTo(state) to check valid transitions
//
// 3. FSM Helpers:
//    - FSM.addTransitions() for bulk transition setup
//    - FSM.applyEventsAndVerify() for sequence testing
//    - FSM.expectValidNextStates() for validation
//    - FSM.FSMBuilder for fluent configuration
//
// 4. Common Patterns:
//    - Toggle (on/off, open/closed)
//    - Linear progression (step1 -> step2 -> done)
//    - Cycle (a -> b -> c -> a)
//    - Complex state graphs (player movement)
//
// 5. Best Practices:
//    - Set up FSM in before hooks for test isolation
//    - Clean up in after hooks
//    - Use helper functions for common assertion patterns
//    - Test invalid transitions to ensure state machine integrity
