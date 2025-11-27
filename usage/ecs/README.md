# ZSpec Usage Example with ECS

This directory contains a complete example project demonstrating how to use ZSpec with zig-ecs for testing game code.

**Note**: This example uses the patterns from ZSpec's ECS integration module. The `zspec-ecs` module provides helpers that may need to be adapted based on your specific zig-ecs version, as the entity type and API can vary. The code shows the intended usage patterns - you may need to adjust type signatures to match your ECS library.

## Project Structure

```
usage/
├── build.zig           # Build configuration
├── build.zig.zon       # Dependencies
├── src/
│   └── game.zig        # Game module with components and systems
└── tests/
    └── game_test.zig   # Comprehensive tests using ZSpec + ECS integration
```

## What This Example Demonstrates

### Game Module (`src/game.zig`)

A simple ECS-based game with:

**Components:**
- `Position` - 2D position with distance calculation
- `Velocity` - Movement delta per frame
- `Health` - Current/max health with damage/heal logic
- `Player` - Player marker with name
- `Enemy` - Enemy marker with type (slime, goblin, dragon)

**Systems:**
- `updateMovement()` - Updates positions based on velocities
- `dealDamage()` - Applies damage to entities
- `healEntity()` - Heals entities

**Game World:**
- `GameWorld` - Wraps ECS registry and provides high-level entity creation

### Test Suite (`tests/game_test.zig`)

Comprehensive tests showing:

1. **Component Factories**
   - Factory definitions for all components
   - Traits for common archetypes (player spawn, enemy spawn, damaged health, etc.)

2. **Component Tests**
   - Pure component logic tests (distance, damage, healing)
   - No ECS setup needed for simple component tests

3. **Entity Creation Tests**
   - Using `ECS.createEntity()` to create entities with components
   - Batch entity creation with `ECS.createEntities()`
   - Registry setup/teardown in before/after hooks
   - Factory trait usage for entity archetypes

4. **Game World Tests**
   - High-level entity creation through `GameWorld`
   - System testing (movement, counting entities)
   - Multiple entities interacting

5. **Combat System Tests**
   - Damage application
   - Health state changes
   - Death conditions

6. **Integration Tests**
   - Realistic game scenarios
   - Player vs enemy combat
   - Multiple enemy waves
   - Movement tracking over multiple frames

## Running the Tests

From the `usage/` directory:

```bash
zig build test
```

You should see output from ZSpec's custom test runner showing all tests passing.

## Key Patterns Demonstrated

### 1. Factory Definitions

```zig
const PositionFactory = Factory.define(game.Position, .{
    .x = 0.0,
    .y = 0.0,
});
```

### 2. Factory Traits for Archetypes

```zig
const PlayerSpawnFactory = PositionFactory.trait(.{ .x = 0.0, .y = 0.0 });
const EnemySpawnFactory = PositionFactory.trait(.{ .x = 100.0, .y = 100.0 });
const DamagedHealthFactory = HealthFactory.trait(.{ .current = 50 });
```

### 3. Registry Setup in Hooks

```zig
pub const MyTests = struct {
    var registry: *ecs.Registry = undefined;

    test "tests:before" {
        Factory.resetSequences();
        registry = ECS.createRegistry(ecs.Registry);
    }

    test "tests:after" {
        ECS.destroyRegistry(registry);
    }

    test "my test" {
        const entity = ECS.createEntity(registry, .{
            .position = PositionFactory.build(.{}),
        });
    }
};
```

### 4. Creating Entities with Components

```zig
const player = ECS.createEntity(registry, .{
    .position = PlayerSpawnFactory.build(.{}),
    .velocity = VelocityFactory.build(.{}),
    .health = HealthFactory.build(.{}),
    .player = PlayerFactory.build(.{}),
});
```

### 5. Batch Entity Creation

```zig
const enemies = ECS.createEntities(registry, 5, .{
    .position = EnemySpawnFactory.build(.{}),
    .health = HealthFactory.build(.{ .current = 20, .max = 20 }),
    .enemy = EnemyFactory.build(.{ .enemy_type = .slime }),
});
defer std.testing.allocator.free(enemies);
```

### 6. Testing Systems

```zig
test "movement system updates positions" {
    const entity = ECS.createEntity(world.registry, .{
        .position = PositionFactory.build(.{ .x = 0, .y = 0 }),
        .velocity = VelocityFactory.build(.{ .dx = 10, .dy = 5 }),
    });

    world.updateMovement(1.0);

    const pos = world.registry.getConst(game.Position, entity);
    try expect.equal(pos.x, 10.0);
    try expect.equal(pos.y, 5.0);
}
```

## Benefits of This Approach

1. **Clean Test Setup** - Before/after hooks handle registry lifecycle
2. **Reusable Factories** - Define component data once, use everywhere
3. **Expressive Tests** - Factory traits make test intent clear
4. **Fast Test Writing** - Batch creation for spawning multiple entities
5. **Isolated Tests** - Each test gets a fresh registry
6. **Type-Safe** - All the benefits of Zig's compile-time checks

## Learning More

- **ZSpec Documentation**: See [main README](../README.md)
- **ECS Integration Guide**: See [wiki](https://github.com/apotema/zspec/wiki/ECS-Integration)
- **Factory Guide**: See [wiki](https://github.com/apotema/zspec/wiki/Factory-Guide)
- **zig-ecs**: See [zig-ecs documentation](https://github.com/prime31/zig-ecs)

## Adapting for Your Project

1. Copy the `build.zig` and `build.zig.zon` pattern
2. Define factories for your components
3. Create traits for your common entity archetypes
4. Use `ECS.createRegistry()` in before hooks
5. Use `ECS.createEntity()` to build test entities
6. Write tests for your systems

This example serves as a template for structuring your own ECS game tests with ZSpec!
