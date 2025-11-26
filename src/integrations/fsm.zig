//! ZSpec FSM Integration - Helpers for using ZSpec with zigfsm
//!
//! Provides utilities for testing finite state machines using ZSpec factories.
//! This module works with cryptocode/zigfsm (https://github.com/cryptocode/zigfsm).
//!
//! Features:
//! - FSM factory patterns for common state machine configurations
//! - Transition builders for readable test setup
//! - State verification helpers
//! - Event testing utilities
//!
//! Example usage:
//! ```zig
//! const zspec = @import("zspec");
//! const zigfsm = @import("zigfsm");
//! const FSMHelpers = zspec.FSM;
//!
//! const State = enum { idle, running, stopped };
//! const Event = enum { start, stop };
//!
//! pub const FSMTests = struct {
//!     const FSM = zigfsm.StateMachine(State, Event, .idle);
//!     var fsm: FSM = undefined;
//!
//!     test "tests:before" {
//!         fsm = FSM.init();
//!         try FSMHelpers.addTransitions(FSM, &fsm, &.{
//!             .{ .event = .start, .from = .idle, .to = .running },
//!             .{ .event = .stop, .from = .running, .to = .stopped },
//!         });
//!     }
//!
//!     test "state transitions work" {
//!         try fsm.do(.start);
//!         try expect.toBeTrue(fsm.isCurrently(.running));
//!     }
//! };
//! ```

const std = @import("std");

/// Transition definition for test setup
pub fn Transition(comptime State: type, comptime Event: type) type {
    return struct {
        event: ?Event = null,
        from: State,
        to: State,
    };
}

/// Add multiple transitions to a state machine for test setup
/// This is a helper to make test setup more concise
pub fn addTransitions(
    comptime FSMType: type,
    fsm: *FSMType,
    transitions: []const Transition(@TypeOf(fsm.*.state), @TypeOf(@as(?FSMType.Event, null) orelse unreachable)),
) !void {
    for (transitions) |t| {
        if (t.event) |event| {
            try fsm.addEventAndTransition(event, t.from, t.to);
        } else {
            try fsm.addTransition(t.from, t.to);
        }
    }
}

/// Builder pattern for setting up state machines in tests
/// Allows fluent configuration of FSMs
pub fn FSMBuilder(comptime FSMType: type) type {
    return struct {
        fsm: FSMType,

        const Self = @This();

        pub fn init() Self {
            return .{ .fsm = FSMType.init() };
        }

        /// Add a transition between states
        pub fn withTransition(self: *Self, from: @TypeOf(self.fsm.state), to: @TypeOf(self.fsm.state)) !*Self {
            try self.fsm.addTransition(from, to);
            return self;
        }

        /// Add an event-based transition
        pub fn withEvent(
            self: *Self,
            event: FSMType.Event,
            from: @TypeOf(self.fsm.state),
            to: @TypeOf(self.fsm.state),
        ) !*Self {
            try self.fsm.addEventAndTransition(event, from, to);
            return self;
        }

        /// Build and return the configured FSM
        pub fn build(self: Self) FSMType {
            return self.fsm;
        }

        /// Get a mutable reference to the FSM
        pub fn get(self: *Self) *FSMType {
            return &self.fsm;
        }
    };
}

/// Verify a sequence of state transitions
/// Useful for testing complex state flows
pub fn verifySequence(
    comptime FSMType: type,
    fsm: *FSMType,
    expected_states: []const @TypeOf(fsm.*.state),
) !void {
    for (expected_states) |expected_state| {
        if (!fsm.isCurrently(expected_state)) {
            std.debug.print(
                "\nExpected state: {any}\nActual state: {any}\n",
                .{ expected_state, fsm.state },
            );
            return error.StateSequenceMismatch;
        }
    }
}

/// Apply a sequence of events and verify the FSM ends in the expected state
pub fn applyEventsAndVerify(
    comptime FSMType: type,
    fsm: *FSMType,
    events: []const FSMType.Event,
    expected_final_state: @TypeOf(fsm.*.state),
) !void {
    for (events) |event| {
        try fsm.do(event);
    }

    if (!fsm.isCurrently(expected_final_state)) {
        std.debug.print(
            "\nExpected final state: {any}\nActual state: {any}\n",
            .{ expected_final_state, fsm.state },
        );
        return error.FinalStateMismatch;
    }
}

/// Test helper to verify valid next states
pub fn expectValidNextStates(
    comptime FSMType: type,
    fsm: *FSMType,
    expected_states: []const @TypeOf(fsm.*.state),
) !void {
    for (expected_states) |state| {
        if (!fsm.canTransitionTo(state)) {
            std.debug.print(
                "\nExpected valid transition to: {any}\nBut transition is not valid\n",
                .{state},
            );
            return error.InvalidTransition;
        }
    }
}

/// Test helper to verify invalid next states
pub fn expectInvalidNextStates(
    comptime FSMType: type,
    fsm: *FSMType,
    invalid_states: []const @TypeOf(fsm.*.state),
) !void {
    for (invalid_states) |state| {
        if (fsm.canTransitionTo(state)) {
            std.debug.print(
                "\nExpected invalid transition to: {any}\nBut transition is valid\n",
                .{state},
            );
            return error.UnexpectedValidTransition;
        }
    }
}

// =============================================================================
// Testing Patterns
// =============================================================================

/// Example pattern for setting up FSM tests with before/after hooks
///
/// ```zig
/// pub const MyFSMTests = struct {
///     const State = enum { idle, active, done };
///     const Event = enum { start, finish };
///     const FSM = zigfsm.StateMachine(State, Event, .idle);
///
///     var fsm: FSM = undefined;
///
///     test "tests:before" {
///         fsm = FSM.init();
///         try fsm.addEventAndTransition(.start, .idle, .active);
///         try fsm.addEventAndTransition(.finish, .active, .done);
///     }
///
///     test "state transitions" {
///         try fsm.do(.start);
///         try expect.toBeTrue(fsm.isCurrently(.active));
///     }
/// };
/// ```
pub const TestPattern = struct {
    // This is just documentation - see examples/fsm_integration_test.zig
};
