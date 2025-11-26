//! Menu system tests using ZSpec with FSM integration
//!
//! This demonstrates real-world usage of zspec and zspec-fsm for testing
//! finite state machines in game menu systems.

const std = @import("std");
const zspec = @import("zspec");
const zigfsm = @import("zigfsm");
const FSM = @import("zspec-fsm");
const menu = @import("menu");

const expect = zspec.expect;
const Factory = zspec.Factory;

test {
    zspec.runAll(@This());
}

// =============================================================================
// Menu State Machine Tests
// =============================================================================

pub const MenuFSMTests = struct {
    var fsm: menu.MenuFSM = undefined;

    test "tests:before" {
        Factory.resetSequences();
        fsm = menu.createMenuFSM() catch unreachable;
    }

    test "tests:after" {
        fsm.deinit();
    }

    test "starts at main menu" {
        try expect.toBeTrue(fsm.isCurrently(.main_menu));
    }

    test "can navigate to settings" {
        try fsm.do(.open_settings);
        try expect.toBeTrue(fsm.isCurrently(.settings));
    }

    test "can navigate back from settings" {
        try fsm.do(.open_settings);
        try fsm.do(.back);
        try expect.toBeTrue(fsm.isCurrently(.main_menu));
    }

    test "can start game from main menu" {
        try fsm.do(.start_game);
        try expect.toBeTrue(fsm.isCurrently(.loading));
    }

    test "transitions from loading to gameplay" {
        try fsm.do(.start_game);
        try fsm.transitionTo(.gameplay);
        try expect.toBeTrue(fsm.isCurrently(.gameplay));
    }

    test "can pause and resume game" {
        try fsm.do(.start_game);
        try fsm.transitionTo(.gameplay);
        try fsm.do(.pause);
        try expect.toBeTrue(fsm.isCurrently(.paused));

        try fsm.do(.resume);
        try expect.toBeTrue(fsm.isCurrently(.gameplay));
    }

    test "can quit to main menu from pause" {
        try fsm.do(.start_game);
        try fsm.transitionTo(.gameplay);
        try fsm.do(.pause);
        try fsm.do(.quit_to_menu);
        try expect.toBeTrue(fsm.isCurrently(.main_menu));
    }

    test "handles game over flow" {
        try fsm.do(.start_game);
        try fsm.transitionTo(.gameplay);
        try fsm.do(.game_over);
        try expect.toBeTrue(fsm.isCurrently(.game_over));
    }

    test "can restart from game over" {
        try fsm.do(.start_game);
        try fsm.transitionTo(.gameplay);
        try fsm.do(.game_over);
        try fsm.do(.restart);
        try expect.toBeTrue(fsm.isCurrently(.loading));
    }

    test "can quit to main menu from game over" {
        try fsm.do(.start_game);
        try fsm.transitionTo(.gameplay);
        try fsm.do(.game_over);
        try fsm.do(.quit_to_menu);
        try expect.toBeTrue(fsm.isCurrently(.main_menu));
    }
};

// =============================================================================
// Settings Navigation Tests
// =============================================================================

pub const SettingsNavigationTests = struct {
    var fsm: menu.MenuFSM = undefined;

    test "tests:before" {
        fsm = menu.createMenuFSM() catch unreachable;
    }

    test "tests:after" {
        fsm.deinit();
    }

    test "can navigate to graphics settings" {
        try fsm.do(.open_settings);
        try fsm.do(.open_graphics);
        try expect.toBeTrue(fsm.isCurrently(.graphics_settings));
    }

    test "can navigate to audio settings" {
        try fsm.do(.open_settings);
        try fsm.do(.open_audio);
        try expect.toBeTrue(fsm.isCurrently(.audio_settings));
    }

    test "can navigate back from graphics settings" {
        try fsm.do(.open_settings);
        try fsm.do(.open_graphics);
        try fsm.do(.back);
        try expect.toBeTrue(fsm.isCurrently(.settings));
    }

    test "navigating back from settings returns to main menu" {
        try fsm.do(.open_settings);
        try fsm.do(.open_graphics);
        try fsm.do(.back);
        try fsm.do(.back);
        try expect.toBeTrue(fsm.isCurrently(.main_menu));
    }

    test "complete settings navigation flow" {
        try FSM.applyEventsAndVerify(menu.MenuFSM, &fsm, &.{
            .open_settings,
            .open_graphics,
            .back,
            .open_audio,
            .back,
            .back,
        }, .main_menu);
    }
};

// =============================================================================
// Menu System Tests
// =============================================================================

pub const MenuSystemTests = struct {
    var system: menu.MenuSystem = undefined;

    test "tests:before" {
        Factory.resetSequences();
        system = menu.MenuSystem.init(std.testing.allocator) catch unreachable;
    }

    test "tests:after" {
        system.deinit();
    }

    test "starts at main menu" {
        try expect.toBeTrue(system.getCurrentState() == .main_menu);
    }

    test "isInMenu returns true for menu states" {
        try expect.toBeTrue(system.isInMenu());

        try system.navigate(.open_settings);
        try expect.toBeTrue(system.isInMenu());
    }

    test "isInGame returns false in menu" {
        try expect.toBeFalse(system.isInGame());
    }

    test "isInGame returns true during gameplay" {
        try system.navigate(.start_game);
        try system.fsm.transitionTo(.gameplay);
        try expect.toBeTrue(system.isInGame());
    }

    test "isInGame returns true when paused" {
        try system.navigate(.start_game);
        try system.fsm.transitionTo(.gameplay);
        try system.navigate(.pause);
        try expect.toBeTrue(system.isInGame());
    }

    test "canNavigate checks valid transitions" {
        try expect.toBeTrue(system.canNavigate(.start_game));
        try expect.toBeTrue(system.canNavigate(.open_settings));
        try expect.toBeFalse(system.canNavigate(.pause));
    }

    test "state descriptions are human readable" {
        const desc = menu.getMenuStateDescription(system.getCurrentState());
        try expect.toBeTrue(std.mem.eql(u8, desc, "Main Menu"));
    }
};

// =============================================================================
// Player State Machine Tests
// =============================================================================

pub const PlayerFSMTests = struct {
    var fsm: menu.PlayerFSM = undefined;

    test "tests:before" {
        fsm = menu.createPlayerFSM() catch unreachable;
    }

    test "tests:after" {
        fsm.deinit();
    }

    test "starts alive" {
        try expect.toBeTrue(fsm.isCurrently(.alive));
    }

    test "can take damage while alive" {
        try fsm.do(.take_damage);
        try expect.toBeTrue(fsm.isCurrently(.alive));
    }

    test "can die from alive" {
        try fsm.do(.die);
        try expect.toBeTrue(fsm.isCurrently(.dead));
    }

    test "can respawn from dead" {
        try fsm.do(.die);
        try fsm.do(.respawn);
        try expect.toBeTrue(fsm.isCurrently(.alive));
    }

    test "collecting powerup makes player invincible" {
        try fsm.do(.collect_powerup);
        try expect.toBeTrue(fsm.isCurrently(.invincible));
    }

    test "powerup expires returns to alive" {
        try fsm.do(.collect_powerup);
        try fsm.do(.powerup_expired);
        try expect.toBeTrue(fsm.isCurrently(.alive));
    }

    test "can still die when invincible" {
        try fsm.do(.collect_powerup);
        try fsm.do(.die);
        try expect.toBeTrue(fsm.isCurrently(.dead));
    }

    test "death and respawn cycle" {
        try FSM.applyEventsAndVerify(menu.PlayerFSM, &fsm, &.{
            .take_damage,
            .take_damage,
            .die,
            .respawn,
        }, .alive);
    }

    test "powerup flow" {
        try FSM.applyEventsAndVerify(menu.PlayerFSM, &fsm, &.{
            .collect_powerup,
            .powerup_expired,
        }, .alive);
    }
};

// =============================================================================
// Connection State Machine Tests
// =============================================================================

pub const ConnectionFSMTests = struct {
    var fsm: menu.ConnectionFSM = undefined;

    test "tests:before" {
        fsm = menu.createConnectionFSM() catch unreachable;
    }

    test "tests:after" {
        fsm.deinit();
    }

    test "starts disconnected" {
        try expect.toBeTrue(fsm.isCurrently(.disconnected));
    }

    test "can initiate connection" {
        try fsm.do(.connect);
        try expect.toBeTrue(fsm.isCurrently(.connecting));
    }

    test "successful connection flow" {
        try FSM.applyEventsAndVerify(menu.ConnectionFSM, &fsm, &.{
            .connect,
            .connection_established,
        }, .connected);
    }

    test "connection failure flow" {
        try FSM.applyEventsAndVerify(menu.ConnectionFSM, &fsm, &.{
            .connect,
            .connection_failed,
        }, .failed);
    }

    test "can retry after failure" {
        try fsm.do(.connect);
        try fsm.do(.connection_failed);
        try fsm.do(.retry);
        try expect.toBeTrue(fsm.isCurrently(.connecting));
    }

    test "connection lost triggers reconnecting" {
        try fsm.do(.connect);
        try fsm.do(.connection_established);
        try fsm.do(.connection_lost);
        try expect.toBeTrue(fsm.isCurrently(.reconnecting));
    }

    test "successful reconnection" {
        try fsm.do(.connect);
        try fsm.do(.connection_established);
        try fsm.do(.connection_lost);
        try fsm.do(.connection_established);
        try expect.toBeTrue(fsm.isCurrently(.connected));
    }

    test "can disconnect while reconnecting" {
        try fsm.do(.connect);
        try fsm.do(.connection_established);
        try fsm.do(.connection_lost);
        try fsm.do(.disconnect);
        try expect.toBeTrue(fsm.isCurrently(.disconnected));
    }

    test "complete connection lifecycle" {
        // Connect -> disconnect -> reconnect -> fail -> retry -> success
        try FSM.applyEventsAndVerify(menu.ConnectionFSM, &fsm, &.{
            .connect,
            .connection_established,
            .disconnect,
        }, .disconnected);
    }
};

// =============================================================================
// FSM Helper Integration Tests
// =============================================================================

pub const FSMHelperTests = struct {
    test "FSMBuilder creates configured menu FSM" {
        const Builder = FSM.FSMBuilder(menu.MenuFSM);

        var builder = Builder.init();
        _ = try builder.withEvent(.start_game, .main_menu, .loading);
        _ = try builder.withEvent(.open_settings, .main_menu, .settings);
        _ = try builder.withEvent(.back, .settings, .main_menu);

        var fsm = builder.build();
        defer fsm.deinit();

        try expect.toBeTrue(fsm.isCurrently(.main_menu));
        try fsm.do(.start_game);
        try expect.toBeTrue(fsm.isCurrently(.loading));
    }

    test "addTransitions helper bulk setup" {
        var fsm = menu.MenuFSM.init();
        defer fsm.deinit();

        try FSM.addTransitions(menu.MenuFSM, &fsm, &.{
            .{ .event = .start_game, .from = .main_menu, .to = .loading },
            .{ .event = .pause, .from = .gameplay, .to = .paused },
            .{ .event = .resume, .from = .paused, .to = .gameplay },
        });

        try fsm.do(.start_game);
        try expect.toBeTrue(fsm.isCurrently(.loading));
    }

    test "expectValidNextStates verifies menu transitions" {
        var fsm = menu.MenuFSM.init();
        defer fsm.deinit();

        try FSM.addTransitions(menu.MenuFSM, &fsm, &.{
            .{ .event = .start_game, .from = .main_menu, .to = .loading },
            .{ .event = .open_settings, .from = .main_menu, .to = .settings },
        });

        // From main menu, can go to loading or settings
        try fsm.transitionTo(.loading);
        try expect.toBeTrue(fsm.isCurrently(.loading));
    }
};

// =============================================================================
// Integration Tests
// =============================================================================

pub const IntegrationTests = struct {
    var menu_system: menu.MenuSystem = undefined;
    var player_fsm: menu.PlayerFSM = undefined;

    test "tests:before" {
        Factory.resetSequences();
        menu_system = menu.MenuSystem.init(std.testing.allocator) catch unreachable;
        player_fsm = menu.createPlayerFSM() catch unreachable;
    }

    test "tests:after" {
        menu_system.deinit();
        player_fsm.deinit();
    }

    test "complete game flow: menu -> play -> die -> retry" {
        // Start game
        try menu_system.navigate(.start_game);
        try menu_system.fsm.transitionTo(.gameplay);
        try expect.toBeTrue(menu_system.isInGame());

        // Player takes damage and dies
        try player_fsm.do(.take_damage);
        try player_fsm.do(.die);
        try expect.toBeTrue(player_fsm.isCurrently(.dead));

        // Game over and return to menu
        try menu_system.navigate(.game_over);
        try menu_system.navigate(.quit_to_menu);
        try expect.toBeTrue(menu_system.isInMenu());
    }

    test "pause -> settings -> resume flow" {
        // Start and pause game
        try menu_system.navigate(.start_game);
        try menu_system.fsm.transitionTo(.gameplay);
        try menu_system.navigate(.pause);

        try expect.toBeTrue(menu_system.isInGame());
        try expect.toBeTrue(menu_system.getCurrentState() == .paused);

        // Resume game
        try menu_system.navigate(.resume);
        try expect.toBeTrue(menu_system.getCurrentState() == .gameplay);
    }

    test "player powerup during gameplay" {
        // Start game
        try menu_system.navigate(.start_game);
        try menu_system.fsm.transitionTo(.gameplay);

        // Collect powerup
        try player_fsm.do(.collect_powerup);
        try expect.toBeTrue(player_fsm.isCurrently(.invincible));

        // Powerup expires
        try player_fsm.do(.powerup_expired);
        try expect.toBeTrue(player_fsm.isCurrently(.alive));

        // Still in gameplay
        try expect.toBeTrue(menu_system.isInGame());
    }
};
