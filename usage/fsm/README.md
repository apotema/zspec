# ZSpec Usage Example with zigfsm

This directory contains a complete example project demonstrating how to use ZSpec with zigfsm for testing finite state machines in game systems.

## Project Structure

```
usage-fsm/
├── build.zig           # Build configuration
├── build.zig.zon       # Dependencies
├── src/
│   └── menu.zig        # Game menu system with multiple FSMs
└── tests/
    └── menu_test.zig   # Comprehensive tests using ZSpec + FSM integration
```

## What This Example Demonstrates

### Source Module (`src/menu.zig`)

A game menu system using finite state machines for:

**Menu FSM:**
- States: main_menu, settings, graphics_settings, audio_settings, gameplay, paused, game_over, loading
- Events: start_game, open_settings, pause, resume, etc.
- Complete menu navigation system

**Player FSM:**
- States: alive, invincible, dead
- Events: take_damage, collect_powerup, die, respawn, powerup_expired
- Player state management during gameplay

**Connection FSM:**
- States: disconnected, connecting, connected, reconnecting, failed
- Events: connect, disconnect, connection_lost, retry, etc.
- Network connection state management

### Test Suite (`tests/menu_test.zig`)

Comprehensive tests (~350 lines) showing:

1. **Menu Navigation Tests**
   - Main menu to settings navigation
   - Sub-menu navigation (graphics, audio)
   - Back button navigation
   - Game start/pause/resume flows

2. **Player State Tests**
   - Taking damage while alive
   - Death and respawn
   - Powerup collection and expiration
   - Invincibility mechanics

3. **Connection State Tests**
   - Connection establishment
   - Connection failures and retries
   - Reconnection logic
   - Graceful disconnection

4. **FSM Helper Tests**
   - Using `FSM.addTransitions()` for bulk setup
   - Using `FSM.FSMBuilder` for fluent configuration
   - Using `FSM.applyEventsAndVerify()` for sequence testing
   - State validation helpers

5. **Integration Tests**
   - Complete game flows
   - Multiple FSMs interacting
   - Complex state sequences

## Running the Tests

From the `usage-fsm/` directory:

```bash
zig build test
```

You should see output from ZSpec's custom test runner showing all tests passing.

## Key Patterns Demonstrated

### 1. FSM Factory Functions

```zig
pub fn createMenuFSM() !MenuFSM {
    var fsm = MenuFSM.init();
    try fsm.addEventAndTransition(.start_game, .main_menu, .loading);
    try fsm.addEventAndTransition(.open_settings, .main_menu, .settings);
    // ... more transitions
    return fsm;
}
```

### 2. FSM Setup in Before Hooks

```zig
pub const MyTests = struct {
    var fsm: MenuFSM = undefined;

    test "tests:before" {
        fsm = createMenuFSM() catch unreachable;
    }

    test "tests:after" {
        fsm.deinit();
    }

    test "navigation test" {
        try fsm.do(.start_game);
        try expect.toBeTrue(fsm.isCurrently(.loading));
    }
};
```

### 3. Using FSM Helpers

```zig
// Bulk transition setup
try FSM.addTransitions(MenuFSM, &fsm, &.{
    .{ .event = .start_game, .from = .main_menu, .to = .loading },
    .{ .event = .pause, .from = .gameplay, .to = .paused },
});

// Event sequence testing
try FSM.applyEventsAndVerify(MenuFSM, &fsm, &.{
    .start_game,
    .pause,
    .resume,
}, .gameplay);

// State validation
try FSM.expectValidNextStates(MenuFSM, &fsm, &.{ .loading, .settings });
try FSM.expectInvalidNextStates(MenuFSM, &fsm, &.{ .gameplay, .paused });
```

### 4. FSM Builder Pattern

```zig
const Builder = FSM.FSMBuilder(MenuFSM);

var builder = Builder.init();
_ = try builder.withEvent(.start_game, .main_menu, .loading);
_ = try builder.withEvent(.pause, .gameplay, .paused);

var fsm = builder.build();
defer fsm.deinit();
```

### 5. Testing State Sequences

```zig
test "complete navigation flow" {
    try FSM.applyEventsAndVerify(MenuFSM, &fsm, &.{
        .open_settings,
        .open_graphics,
        .back,
        .back,
    }, .main_menu);
}
```

### 6. Integration Testing

```zig
test "menu and player FSMs together" {
    // Start game
    try menu_system.navigate(.start_game);
    try menu_system.fsm.transitionTo(.gameplay);

    // Player dies
    try player_fsm.do(.die);

    // Game over
    try menu_system.navigate(.game_over);
    try menu_system.navigate(.quit_to_menu);
}
```

## Benefits of This Approach

1. **Clear State Management** - FSMs make game states explicit and validated
2. **Easy Testing** - ZSpec helpers make FSM testing straightforward
3. **Reusable Patterns** - FSM factory functions and builders
4. **Integration Testing** - Test multiple FSMs interacting
5. **Readable Tests** - Event sequences clearly show state flows
6. **Type Safety** - Compile-time validation of states and events

## Common FSM Patterns

### Toggle Pattern
```zig
// States: on, off
// Events: toggle
// on -> toggle -> off -> toggle -> on
```

### Linear Progression
```zig
// States: step1, step2, step3, done
// Events: next
// step1 -> next -> step2 -> next -> step3 -> next -> done
```

### Cycle Pattern
```zig
// States: a, b, c
// Events: advance
// a -> advance -> b -> advance -> c -> advance -> a
```

### Hierarchical Menus
```zig
// States: main, settings, graphics, audio
// Events: open_*, back
// main -> open_settings -> settings -> open_graphics -> graphics -> back -> settings -> back -> main
```

## Learning More

- **ZSpec Documentation**: See [main README](../README.md)
- **FSM Integration Guide**: See [wiki](https://github.com/apotema/zspec/wiki/FSM-Integration) (when published)
- **zigfsm Documentation**: See [zigfsm](https://github.com/cryptocode/zigfsm)
- **ECS Integration**: See [usage/](../usage/) for ECS example

## Adapting for Your Project

1. Define your state and event enums
2. Create factory functions for FSM setup
3. Use before/after hooks for initialization/cleanup
4. Write tests using FSM helpers for common patterns
5. Test invalid transitions to ensure state integrity
6. Use integration tests for complex flows

This example serves as a template for structuring your own FSM tests with ZSpec!
