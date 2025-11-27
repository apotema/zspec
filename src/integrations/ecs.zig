//! ZSpec ECS Integration - Helpers for using ZSpec with zig-ecs
//!
//! Provides utilities for creating entities and components using ZSpec factories
//! in your zig-ecs tests. This module works with prime31/zig-ecs.
//!
//! Features:
//! - createEntity() - Create entities with factory-generated components
//! - createEntities() - Batch create multiple entities
//! - ComponentFactory() - Wrapper for component-specific factories
//! - Registry helpers for setup/teardown in before/after hooks
//!
//! Example usage:
//! ```zig
//! const zspec = @import("zspec");
//! const ecs = @import("zig-ecs");
//! const EcsHelpers = zspec.ECS;
//!
//! const PositionFactory = Factory.define(Position, .{
//!     .x = 0.0,
//!     .y = 0.0,
//! });
//!
//! pub const EntityTests = struct {
//!     var registry: *ecs.Registry = undefined;
//!
//!     test "tests:before" {
//!         registry = EcsHelpers.createRegistry(ecs.Registry);
//!     }
//!
//!     test "tests:after" {
//!         EcsHelpers.destroyRegistry(registry);
//!     }
//!
//!     test "creates entity with components" {
//!         const entity = EcsHelpers.createEntity(registry, .{
//!             .position = PositionFactory.build(.{ .x = 10.0 }),
//!         });
//!         // entity is created with Position component
//!     }
//! };
//! ```

const std = @import("std");

/// Create a registry instance for testing
/// Usage in before hook:
/// ```zig
/// test "tests:before" {
///     registry = ECS.createRegistry(ecs.Registry);
/// }
/// ```
pub fn createRegistry(comptime RegistryType: type) *RegistryType {
    const registry = std.testing.allocator.create(RegistryType) catch @panic("failed to create registry");
    registry.* = RegistryType.init(std.testing.allocator);
    return registry;
}

/// Create a registry instance with a custom allocator
pub fn createRegistryWith(comptime RegistryType: type, allocator: std.mem.Allocator) *RegistryType {
    const registry = allocator.create(RegistryType) catch @panic("failed to create registry");
    registry.* = RegistryType.init(allocator);
    return registry;
}

/// Destroy a registry instance (for use in after hook)
/// Usage in after hook:
/// ```zig
/// test "tests:after" {
///     ECS.destroyRegistry(registry);
/// }
/// ```
pub fn destroyRegistry(registry: anytype) void {
    registry.deinit();

    // Get the allocator that was used to create the registry
    // We assume it's std.testing.allocator by default
    std.testing.allocator.destroy(registry);
}

/// Destroy a registry instance with a custom allocator
pub fn destroyRegistryWith(registry: anytype, allocator: std.mem.Allocator) void {
    registry.deinit();
    allocator.destroy(registry);
}

/// Component data for entity creation
/// Pass an anonymous struct with component field names and their data
pub fn ComponentSet(comptime T: type) type {
    return T;
}

/// Create a single entity with components from an anonymous struct
///
/// Example:
/// ```zig
/// const entity = ECS.createEntity(registry, .{
///     .position = PositionFactory.build(.{}),
///     .velocity = VelocityFactory.build(.{ .dx = 5.0 }),
/// });
/// ```
pub fn createEntity(registry: anytype, components: anytype) EntityType(@TypeOf(registry)) {
    const entity = registry.create();

    inline for (std.meta.fields(@TypeOf(components))) |field| {
        const component = @field(components, field.name);
        registry.add(entity, component);
    }

    return entity;
}

/// Helper to extract Entity type from a registry pointer type
fn EntityType(comptime RegistryPtrType: type) type {
    // Get the underlying struct type from the pointer
    const RegistryType = std.meta.Child(RegistryPtrType);
    // Get the create function and extract its return type
    const create_fn = @field(RegistryType, "create");
    const create_fn_info = @typeInfo(@TypeOf(create_fn));
    return create_fn_info.@"fn".return_type.?;
}

/// Create multiple entities with the same component configuration
/// Returns a slice of entity IDs (allocated with std.testing.allocator)
///
/// Example:
/// ```zig
/// const entities = ECS.createEntities(registry, 5, .{
///     .position = PositionFactory.build(.{}),
/// });
/// defer std.testing.allocator.free(entities);
/// ```
pub fn createEntities(registry: anytype, count: usize, components: anytype) []EntityType(@TypeOf(registry)) {
    return createEntitiesWith(registry, count, components, std.testing.allocator);
}

/// Create multiple entities with custom allocator
pub fn createEntitiesWith(registry: anytype, count: usize, components: anytype, allocator: std.mem.Allocator) []EntityType(@TypeOf(registry)) {
    const Entity = EntityType(@TypeOf(registry));
    const entities = allocator.alloc(Entity, count) catch @panic("failed to allocate entities array");

    for (entities) |*entity| {
        entity.* = createEntity(registry, components);
    }

    return entities;
}

/// Create multiple entities with unique components using a callback
/// This allows each entity to have unique component values (e.g., sequences)
///
/// Example:
/// ```zig
/// const EntityBuilder = struct {
///     pub fn build() @TypeOf(.{
///         .position = PositionFactory.build(.{}),
///     }) {
///         return .{
///             .position = PositionFactory.build(.{}),
///             .id = IdFactory.build(.{}), // uses sequence for unique IDs
///         };
///     }
/// };
///
/// const entities = ECS.createEntitiesUnique(registry, 5, EntityBuilder);
/// defer std.testing.allocator.free(entities);
/// ```
pub fn createEntitiesUnique(
    registry: anytype,
    count: usize,
    comptime Builder: type,
) []EntityType(@TypeOf(registry)) {
    return createEntitiesUniqueWith(registry, count, Builder, std.testing.allocator);
}

/// Create multiple entities with unique components using a builder type and custom allocator
pub fn createEntitiesUniqueWith(
    registry: anytype,
    count: usize,
    comptime Builder: type,
    allocator: std.mem.Allocator,
) []EntityType(@TypeOf(registry)) {
    const Entity = EntityType(@TypeOf(registry));
    const entities = allocator.alloc(Entity, count) catch @panic("failed to allocate entities array");

    for (entities) |*entity| {
        const components = Builder.build();
        entity.* = createEntity(registry, components);
    }

    return entities;
}

/// Helper to create a Let-style memoized registry
///
/// Example:
/// ```zig
/// pub const MyTests = struct {
///     fn initRegistry() *ecs.Registry {
///         return ECS.createRegistry(ecs.Registry);
///     }
///
///     const registry = zspec.LetAlloc(*ecs.Registry, initRegistry);
///
///     test "tests:after" {
///         ECS.destroyRegistry(registry.get());
///         registry.reset();
///     }
/// };
/// ```
pub fn RegistryLet(comptime RegistryType: type) type {
    return struct {
        pub fn init() *RegistryType {
            return createRegistry(RegistryType);
        }
    };
}

// =============================================================================
// Component Factory Pattern
// =============================================================================

/// Wrapper for a factory that produces component data
/// Useful for creating reusable component builders
///
/// Example:
/// ```zig
/// const PositionComponent = ECS.ComponentFactory(Position, PositionFactory);
///
/// const entity = registry.create();
/// PositionComponent.attach(registry, entity, .{ .x = 10.0 });
/// ```
pub fn ComponentFactory(comptime ComponentType: type, comptime Factory: type) type {
    return struct {
        /// Build component data with overrides
        pub fn build(overrides: anytype) ComponentType {
            return Factory.build(overrides);
        }

        /// Build component data with custom allocator
        pub fn buildWith(allocator: std.mem.Allocator, overrides: anytype) ComponentType {
            return Factory.buildWith(allocator, overrides);
        }

        /// Create and attach component to an existing entity
        pub fn attach(registry: anytype, entity: anytype, overrides: anytype) void {
            const component = build(overrides);
            registry.add(entity, component);
        }

        /// Create and attach component with custom allocator
        pub fn attachWith(registry: anytype, entity: anytype, allocator: std.mem.Allocator, overrides: anytype) void {
            const component = buildWith(allocator, overrides);
            registry.add(entity, component);
        }

        /// Create a new entity with this component
        pub fn createEntityWith(registry: anytype, overrides: anytype) EntityType(@TypeOf(registry)) {
            const entity = registry.create();
            attach(registry, entity, overrides);
            return entity;
        }

        /// Create multiple entities with this component
        pub fn createEntitiesWith(registry: anytype, count: usize, overrides: anytype) []EntityType(@TypeOf(registry)) {
            const Entity = EntityType(@TypeOf(registry));
            const entities = std.testing.allocator.alloc(Entity, count) catch @panic("failed to allocate entities");

            for (entities) |*e| {
                e.* = createEntityWith(registry, overrides);
            }

            return entities;
        }
    };
}

// =============================================================================
// Testing Patterns
// =============================================================================

/// Example pattern for setting up ECS tests with Let
///
/// ```zig
/// pub const MyECSTests = struct {
///     // Use Let for lazy registry creation
///     fn createTestRegistry() *ecs.Registry {
///         return ECS.createRegistry(ecs.Registry);
///     }
///
///     const registry = zspec.LetAlloc(*ecs.Registry, createTestRegistry);
///
///     test "tests:after" {
///         ECS.destroyRegistry(registry.get());
///         registry.reset();
///     }
///
///     test "my test" {
///         const entity = ECS.createEntity(registry.get(), .{
///             .position = PositionFactory.build(.{}),
///         });
///         // test code...
///     }
/// };
/// ```
pub const TestPattern = struct {
    // This is just documentation - see examples/ecs_integration_test.zig
};
