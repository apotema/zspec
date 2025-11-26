//! Game Menu System using Finite State Machines
//!
//! This module demonstrates using FSMs for game menu navigation and state management.

const std = @import("std");
const zigfsm = @import("zigfsm");

// =============================================================================
// Menu State Machine
// =============================================================================

pub const MenuState = enum {
    main_menu,
    settings,
    graphics_settings,
    audio_settings,
    gameplay,
    paused,
    game_over,
    loading,
};

pub const MenuEvent = enum {
    start_game,
    open_settings,
    open_graphics,
    open_audio,
    back,
    pause,
    resume,
    quit_to_menu,
    game_over,
    restart,
};

pub const MenuFSM = zigfsm.StateMachine(MenuState, MenuEvent, .main_menu);

/// Create a standard menu FSM with typical game menu transitions
pub fn createMenuFSM() !MenuFSM {
    var fsm = MenuFSM.init();
    errdefer fsm.deinit();

    // Main menu transitions
    try fsm.addEventAndTransition(.start_game, .main_menu, .loading);
    try fsm.addEventAndTransition(.open_settings, .main_menu, .settings);

    // Loading transitions
    try fsm.addTransition(.loading, .gameplay);

    // Settings menu transitions
    try fsm.addEventAndTransition(.open_graphics, .settings, .graphics_settings);
    try fsm.addEventAndTransition(.open_audio, .settings, .audio_settings);
    try fsm.addEventAndTransition(.back, .settings, .main_menu);

    // Sub-settings transitions
    try fsm.addEventAndTransition(.back, .graphics_settings, .settings);
    try fsm.addEventAndTransition(.back, .audio_settings, .settings);

    // Gameplay transitions
    try fsm.addEventAndTransition(.pause, .gameplay, .paused);
    try fsm.addEventAndTransition(.game_over, .gameplay, .game_over);

    // Paused menu transitions
    try fsm.addEventAndTransition(.resume, .paused, .gameplay);
    try fsm.addEventAndTransition(.quit_to_menu, .paused, .main_menu);

    // Game over transitions
    try fsm.addEventAndTransition(.restart, .game_over, .loading);
    try fsm.addEventAndTransition(.quit_to_menu, .game_over, .main_menu);

    return fsm;
}

// =============================================================================
// Menu System
// =============================================================================

pub const MenuSystem = struct {
    fsm: MenuFSM,
    menu_stack: std.ArrayList(MenuState),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !MenuSystem {
        return .{
            .fsm = try createMenuFSM(),
            .menu_stack = std.ArrayList(MenuState).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MenuSystem) void {
        self.fsm.deinit();
        self.menu_stack.deinit();
    }

    pub fn getCurrentState(self: *const MenuSystem) MenuState {
        return self.fsm.state;
    }

    pub fn isInGame(self: *const MenuSystem) bool {
        return self.fsm.isCurrently(.gameplay) or self.fsm.isCurrently(.paused);
    }

    pub fn isInMenu(self: *const MenuSystem) bool {
        return self.fsm.isCurrently(.main_menu) or
            self.fsm.isCurrently(.settings) or
            self.fsm.isCurrently(.graphics_settings) or
            self.fsm.isCurrently(.audio_settings);
    }

    pub fn navigate(self: *MenuSystem, event: MenuEvent) !void {
        try self.fsm.do(event);
    }

    pub fn canNavigate(self: *const MenuSystem, event: MenuEvent) bool {
        // Check if event can be applied from current state
        for (self.fsm.transitions.items) |t| {
            if (t.event) |e| {
                if (e == event and t.from == self.fsm.state) {
                    return true;
                }
            }
        }
        return false;
    }
};

// =============================================================================
// Player State Machine (for gameplay)
// =============================================================================

pub const PlayerState = enum {
    alive,
    invincible,
    dead,
};

pub const PlayerEvent = enum {
    take_damage,
    collect_powerup,
    die,
    respawn,
    powerup_expired,
};

pub const PlayerFSM = zigfsm.StateMachine(PlayerState, PlayerEvent, .alive);

pub fn createPlayerFSM() !PlayerFSM {
    var fsm = PlayerFSM.init();
    errdefer fsm.deinit();

    // Alive transitions
    try fsm.addEventAndTransition(.take_damage, .alive, .alive); // Can take damage while alive
    try fsm.addEventAndTransition(.die, .alive, .dead);
    try fsm.addEventAndTransition(.collect_powerup, .alive, .invincible);

    // Invincible transitions
    try fsm.addEventAndTransition(.powerup_expired, .invincible, .alive);
    try fsm.addEventAndTransition(.die, .invincible, .dead); // Can still die from fall damage, etc.

    // Dead transitions
    try fsm.addEventAndTransition(.respawn, .dead, .alive);

    return fsm;
}

// =============================================================================
// Connection State Machine
// =============================================================================

pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    reconnecting,
    failed,
};

pub const ConnectionEvent = enum {
    connect,
    connection_established,
    disconnect,
    connection_lost,
    retry,
    connection_failed,
};

pub const ConnectionFSM = zigfsm.StateMachine(ConnectionState, ConnectionEvent, .disconnected);

pub fn createConnectionFSM() !ConnectionFSM {
    var fsm = ConnectionFSM.init();
    errdefer fsm.deinit();

    // Disconnected transitions
    try fsm.addEventAndTransition(.connect, .disconnected, .connecting);

    // Connecting transitions
    try fsm.addEventAndTransition(.connection_established, .connecting, .connected);
    try fsm.addEventAndTransition(.connection_failed, .connecting, .failed);

    // Connected transitions
    try fsm.addEventAndTransition(.disconnect, .connected, .disconnected);
    try fsm.addEventAndTransition(.connection_lost, .connected, .reconnecting);

    // Reconnecting transitions
    try fsm.addEventAndTransition(.connection_established, .reconnecting, .connected);
    try fsm.addEventAndTransition(.connection_failed, .reconnecting, .failed);
    try fsm.addEventAndTransition(.disconnect, .reconnecting, .disconnected);

    // Failed transitions
    try fsm.addEventAndTransition(.retry, .failed, .connecting);
    try fsm.addEventAndTransition(.disconnect, .failed, .disconnected);

    return fsm;
}

// =============================================================================
// Utility Functions
// =============================================================================

pub fn getMenuStateDescription(state: MenuState) []const u8 {
    return switch (state) {
        .main_menu => "Main Menu",
        .settings => "Settings",
        .graphics_settings => "Graphics Settings",
        .audio_settings => "Audio Settings",
        .gameplay => "Playing",
        .paused => "Paused",
        .game_over => "Game Over",
        .loading => "Loading...",
    };
}

pub fn getPlayerStateDescription(state: PlayerState) []const u8 {
    return switch (state) {
        .alive => "Alive",
        .invincible => "Invincible",
        .dead => "Dead",
    };
}
