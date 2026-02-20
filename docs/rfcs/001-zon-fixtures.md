# RFC 001: .zon Fixture Files for Multi-Struct Instantiation

- **Issue**: [#38](https://github.com/apotema/zspec/issues/38)
- **Status**: Draft
- **Branch**: `feat/zon-fixture-files`

## Summary

Add a `Fixture` module to ZSpec — separate from `Factory` — that provides a FactoryBot-inspired workflow: **define fixtures once in `.zon` files, call `create` anywhere in tests.** Fixtures handle static, pre-defined test data while Factory handles dynamic generation (sequences, lazy values, traits).

## Motivation

### The problem

Tests that exercise real-world scenarios need several related objects. Today this requires defining a factory per type, importing each `.zon` entry separately, and calling `.build()` in every test:

```zig
// Repeated in every test file that needs this data
const factory_defs = @import("fixtures.zon");

const UserFactory = Factory.defineFrom(User, factory_defs.user);
const ProductFactory = Factory.defineFrom(Product, factory_defs.product);
const OrderFactory = Factory.defineFrom(Order, factory_defs.order);

const user = UserFactory.build(.{});
const product = ProductFactory.build(.{});
const order = OrderFactory.build(.{});
```

Problems:

1. **Boilerplate scales linearly** with the number of types in the scenario.
2. **Relationships are implicit** — `order.user_id == user.id` is only visible if you read the `.zon` file.
3. **No single entry point** — each test repeats the same factory definitions and build calls.
4. **Factories are overkill** when you just want static test data with no sequences or traits.

### FactoryBot comparison

In Ruby's FactoryBot, the workflow is:

```ruby
# spec/factories/users.rb — define once
FactoryBot.define do
  factory :user do
    name { "John Doe" }
    email { "john@example.com" }
  end
end

# spec/models/user_spec.rb — any test, just call create
user = create(:user)
order = create(:order)  # auto-creates associated user too
```

The magic: **centralized definitions, minimal callsite ceremony, automatic associations.**

Zig can't do runtime registries or auto-discovery, but we can achieve the same workflow with comptime imports and a dedicated Fixture module.

### When to use Fixture vs Factory

| Use case | Tool |
|---|---|
| Static, known-good scenario data | **Fixture** |
| Dynamic data (sequences, computed values) | **Factory** |
| Many variants of the same type | **Factory** with traits |
| Complete multi-type test scenario in one call | **Fixture** |
| Single type, multiple tests with overrides | **Factory** |

They complement each other. A fixture gives you a snapshot; a factory gives you a generator.

## Proposed API

### The FactoryBot-inspired workflow

#### Step 1: Define fixtures in `.zon` files (one per fixture)

Each `.zon` file is a self-contained fixture definition, like a FactoryBot factory file:

```zig
// tests/fixtures/user.zon
.{
    .id = 0,
    .name = "John Doe",
    .email = "john@example.com",
}
```

```zig
// tests/fixtures/admin.zon
.{
    .id = 0,
    .name = "Admin User",
    .email = "admin@example.com",
    .role = "admin",
}
```

```zig
// tests/fixtures/product.zon
.{
    .id = 0,
    .name = "Widget",
    .price = 29.99,
    .seller_id = 0,
}
```

#### Step 2: Create a registry file (the "factory directory")

One file maps names to types and `.zon` data — like FactoryBot's `spec/factories/` directory:

```zig
// tests/fixtures.zig
const zspec = @import("zspec");
const Fixture = zspec.Fixture;
const User = @import("../src/models.zig").User;
const Product = @import("../src/models.zig").Product;
const Order = @import("../src/models.zig").Order;

// Single-struct fixtures
pub const user = Fixture.define(User, @import("fixtures/user.zon"));
pub const admin = Fixture.define(User, @import("fixtures/admin.zon"));
pub const product = Fixture.define(Product, @import("fixtures/product.zon"));

// Multi-struct scenario fixture
const CheckoutScenario = struct {
    user: User,
    product: Product,
    order: Order,
};
pub const checkout = Fixture.define(CheckoutScenario, @import("fixtures/checkout.zon"));
```

#### Step 3: Tests just call `create` (minimal ceremony)

```zig
// tests/checkout_test.zig
const f = @import("fixtures.zig");
const expect = @import("zspec").expect;

pub const CheckoutTests = struct {
    test "create a user with defaults" {
        const user = f.user.create(.{});
        try expect.equal(user.name, "John Doe");
    }

    test "create a user with overrides" {
        const user = f.user.create(.{ .name = "Jane", .email = "jane@example.com" });
        try expect.equal(user.name, "Jane");
    }

    test "create a full checkout scenario" {
        const s = f.checkout.create(.{});
        try expect.equal(s.order.user_id, s.user.id);
        try expect.equal(s.order.product_id, s.product.id);
    }
};
```

Compare with FactoryBot:

| FactoryBot | ZSpec Fixture |
|---|---|
| `create(:user)` | `f.user.create(.{})` |
| `create(:user, name: "Jane")` | `f.user.create(.{ .name = "Jane" })` |
| `create(:order)` (auto-creates user) | `f.checkout.create(.{})` (scenario) |

### Alternative: All fixtures in one `.zon` file

Instead of one file per fixture, group related definitions in a single file:

```zig
// tests/fixtures/all.zon
.{
    .user = .{ .id = 0, .name = "John Doe", .email = "john@example.com" },
    .admin = .{ .id = 0, .name = "Admin", .email = "admin@example.com", .role = "admin" },
    .product = .{ .id = 0, .name = "Widget", .price = 29.99 },
}
```

```zig
// tests/fixtures.zig
const data = @import("fixtures/all.zon");

pub const user = Fixture.define(User, data.user);
pub const admin = Fixture.define(User, data.admin);
pub const product = Fixture.define(Product, data.product);
```

Both approaches work. One-file-per-fixture is cleaner for large projects; single-file is simpler for small ones.

## .zon File Format by Example

The `.zon` format is standard Zig anonymous struct literals — no new syntax.

### Single-struct fixture

```zig
// fixtures/user.zon
.{
    .id = 0,
    .name = "John Doe",
    .email = "john@example.com",
}
```

### Scenario with cross-references

Relationships are expressed through matching values — `seller_id = 1` points to the entry with `.id = 1`. No special syntax.

```zig
// fixtures/marketplace.zon
.{
    .seller = .{ .id = 1, .name = "Alice", .email = "alice@shop.com" },
    .buyer = .{ .id = 2, .name = "Bob", .email = "bob@mail.com" },
    .product = .{ .id = 10, .name = "Widget", .price = 29.99, .seller_id = 1 },
    .order = .{ .id = 100, .user_id = 2, .product_id = 10, .quantity = 3 },
}
```

### Arrays

Tuples (`.{ .{...}, .{...} }`) map to fixed-size arrays in the schema.

```zig
// fixtures/store.zon
.{
    .seller = .{ .id = 1, .name = "Alice", .email = "alice@shop.com" },
    .products = .{
        .{ .id = 10, .name = "Widget", .price = 9.99, .seller_id = 1 },
        .{ .id = 11, .name = "Gadget", .price = 19.99, .seller_id = 1 },
        .{ .id = 12, .name = "Doohickey", .price = 49.99, .seller_id = 1 },
    },
    .orders = .{
        .{ .id = 100, .user_id = 2, .product_id = 10, .quantity = 2 },
        .{ .id = 101, .user_id = 2, .product_id = 11, .quantity = 1 },
    },
}
```

Schema:

```zig
const StoreScenario = struct {
    seller: User,
    products: [3]Product,
    orders: [2]Order,
};
pub const store = Fixture.define(StoreScenario, @import("fixtures/store.zon"));
```

### Nested structs (grouped by entity)

```zig
// fixtures/battle.zon
.{
    .player = .{
        .pos = .{ .x = 0.0, .y = 0.0 },
        .health = .{ .current = 100, .max = 100 },
    },
    .enemies = .{
        .{
            .pos = .{ .x = 50.0, .y = 30.0 },
            .health = .{ .current = 20, .max = 20 },
            .kind = .slime,
        },
        .{
            .pos = .{ .x = 80.0, .y = 60.0 },
            .health = .{ .current = 50, .max = 50 },
            .kind = .goblin,
        },
        .{
            .pos = .{ .x = 120.0, .y = 10.0 },
            .health = .{ .current = 200, .max = 200 },
            .kind = .dragon,
        },
    },
}
```

Schema:

```zig
const PlayerData = struct { pos: Position, health: Health };
const EnemyData = struct { pos: Position, health: Health, kind: enum { slime, goblin, dragon } };

const BattleScenario = struct {
    player: PlayerData,
    enemies: [3]EnemyData,
};
pub const battle = Fixture.define(BattleScenario, @import("fixtures/battle.zon"));
```

### Multiple scenarios in one file

```zig
// fixtures/scenarios.zon
.{
    .happy_path = .{
        .user = .{ .id = 1, .name = "John", .email = "john@example.com" },
        .order = .{ .id = 1, .user_id = 1, .product_id = 10, .quantity = 1 },
    },
    .bulk_order = .{
        .user = .{ .id = 2, .name = "Warehouse", .email = "warehouse@co.com" },
        .order = .{ .id = 2, .user_id = 2, .product_id = 10, .quantity = 500 },
    },
}
```

```zig
const scenarios = @import("fixtures/scenarios.zon");
pub const happy = Fixture.define(CheckoutScenario, scenarios.happy_path);
pub const bulk = Fixture.define(CheckoutScenario, scenarios.bulk_order);
```

## Detailed Design

### `Fixture.define`

`define` is the core function. It takes a type and `.zon` data, and returns a fixture handle with a `create` method:

```zig
pub fn define(comptime T: type, comptime zon_data: anytype) type {
    // 1. Validate zon_data fields against T (compile-time typo detection)
    // 2. Return a type with create/createWith methods

    return struct {
        /// Create an instance with optional field overrides
        pub fn create(overrides: anytype) T {
            // Merge zon_data defaults with overrides
            // Coerce anonymous structs to named types
            // Return fully typed T
        }

        /// Create an instance with a custom allocator (for string fields, etc.)
        pub fn createWith(alloc: std.mem.Allocator, overrides: anytype) T {
            // Same as create but uses allocator for any alloc-requiring fields
        }
    };
}
```

### How `create` works

For **single-struct fixtures** (e.g., `Fixture.define(User, .{ .id = 0, .name = "John" })`):

1. Start with the `.zon` defaults.
2. Apply any overrides from the `create(.{})` call.
3. Coerce anonymous structs to named types where needed.
4. Return the typed struct.

For **scenario fixtures** (e.g., `Fixture.define(CheckoutScenario, @import("checkout.zon"))`):

1. Iterate over each field in the schema struct.
2. For each field, coerce the corresponding `.zon` entry to the target type.
3. For array fields, iterate the `.zon` tuple and coerce each element.
4. Return the fully populated schema struct.

### Validation

Reuse and extend the existing `validateZonFields()` from `factory.zig`:

- Every key in the `.zon` must correspond to a field in `T`.
- Recursively validate nested struct fields.
- Report compile errors with clear messages: `"Fixture field 'user' contains unknown field 'nme'. Type 'User' has no such field."`

### Coercion

Reuse `buildTypedPayload()` from `factory.zig`:

- Anonymous struct -> named struct coercion
- Nested struct coercion (recursive, any depth)
- Union coercion (`.{ .circle = .{ .radius = 10 } }` -> `Shape{ .circle = ... }`)

### Overrides at callsite

`create` supports field-level overrides, just like `Factory.build`:

```zig
// Single-struct: override individual fields
const user = f.user.create(.{ .name = "Jane", .email = "jane@example.com" });

// Scenario: override nested entries
const s = f.checkout.create(.{
    .user = .{ .name = "Custom User" },
});
```

For scenarios, overrides are **merged per-entry** — only the specified fields are overridden, the rest keep their `.zon` defaults.

### Cross-references between fixture entries

#### Value-based foreign keys (recommended)

The most common case: one struct holds the ID of another. The `.zon` file expresses this with matching values:

```zig
// fixtures/checkout.zon
.{
    .user = .{ .id = 1, .name = "John", .email = "john@example.com" },
    .product = .{ .id = 10, .name = "Widget", .price = 29.99, .seller_id = 1 },
    .order = .{ .id = 100, .user_id = 1, .product_id = 10, .quantity = 2 },
}
```

Relationships are visible by reading matching IDs. The `.zon` file is the single source of truth. If an ID becomes inconsistent, the test that asserts the relationship will catch it:

```zig
const s = f.checkout.create(.{});
try expect.equal(s.order.user_id, s.user.id);       // verifiable
try expect.equal(s.order.product_id, s.product.id); // verifiable
```

#### Embedded structs (no pointers)

When a struct contains another struct by value (not pointer), just embed it in the `.zon`:

```zig
// Product embeds User as owner
.{
    .product = .{
        .id = 10,
        .name = "Widget",
        .owner = .{ .id = 1, .name = "Alice" },
    },
}
```

This works with `buildTypedPayload`'s recursive coercion.

#### Pointer-based references

`.zon` files cannot express pointer relationships. For structs with pointer fields like `owner: *const User`, use one of:

1. **Post-load wiring** — load the fixture, then wire pointers in `tests:before`:

```zig
const raw = f.checkout.create(.{});

pub const Tests = struct {
    var product: Product = undefined;

    test "tests:before" {
        product = .{ .id = raw.product.id, .name = raw.product.name, .owner = &raw.user };
    }
};
```

2. **Use Factory instead** — `Factory.assoc()` handles pointer associations natively.

Automatic pointer resolution (`Fixture.createAlloc`) is deferred to a future RFC due to ambiguity when multiple entries share the same type.

### Arrays and lists

#### Fixed-size arrays

The schema declares `[N]T`. The `.zon` provides a tuple of matching length:

```zig
const TeamScenario = struct {
    manager: User,
    members: [3]User,
};
```

```zig
// fixtures/team.zon
.{
    .manager = .{ .id = 1, .name = "Alice", .email = "alice@co.com" },
    .members = .{
        .{ .id = 2, .name = "Bob", .email = "bob@co.com" },
        .{ .id = 3, .name = "Carol", .email = "carol@co.com" },
        .{ .id = 4, .name = "Dave", .email = "dave@co.com" },
    },
}
```

Implementation: detect `[N]T`, iterate the `.zon` tuple, coerce each element, compile error if lengths don't match.

#### Arrays with cross-references

Arrays combine naturally with value-based foreign keys:

```zig
// fixtures/store.zon
.{
    .seller = .{ .id = 1, .name = "Alice", .email = "alice@co.com" },
    .products = .{
        .{ .id = 10, .name = "Widget", .price = 9.99, .seller_id = 1 },
        .{ .id = 11, .name = "Gadget", .price = 19.99, .seller_id = 1 },
    },
}
```

```zig
const s = f.store.create(.{});
for (s.products) |product| {
    try expect.equal(product.seller_id, s.seller.id);
}
```

#### Comptime slices (future)

`[]const T` fields with length inferred from `.zon` tuple. Deferred to a later phase — comptime slice lifetime semantics need validation.

### Partial loading

`create` only requires that the `.zon` has **at least** the fields the schema declares:

```zig
// full_scenario.zon has .user, .product, .order, .address, .payment
// This schema only needs user and order:
const QuickCheck = struct { user: User, order: Order };
pub const quick = Fixture.define(QuickCheck, @import("fixtures/full_scenario.zon"));
```

This is the natural behavior when iterating over schema fields (not `.zon` fields) during construction.

### Composability with Factory

Fixtures produce static data. Factories produce dynamic data. They combine naturally:

```zig
// Use fixture as base, add dynamic behavior via Factory
const scenario = f.checkout.create(.{});

const UserFactory = Factory.define(User, .{
    .id = Factory.sequence(u32),
    .name = scenario.user.name,
    .email = Factory.sequenceFmt("user{d}@example.com"),
});
```

## Fixture vs Factory: side-by-side

```zig
// ┌─────────────────────────────────┬─────────────────────────────────────┐
// │          FIXTURE                │           FACTORY                   │
// ├─────────────────────────────────┼─────────────────────────────────────┤
// │ // Define (once, in registry)   │ // Define (per test file)           │
// │ pub const user =                │ const UserFactory =                 │
// │   Fixture.define(User,          │   Factory.define(User, .{           │
// │     @import("user.zon"));       │     .id = Factory.sequence(u32),    │
// │                                 │     .name = "John",                 │
// │                                 │     .email = sequenceFmt("..."),    │
// │                                 │   });                               │
// ├─────────────────────────────────┼─────────────────────────────────────┤
// │ // Use                          │ // Use                              │
// │ f.user.create(.{})              │ UserFactory.build(.{})              │
// │ f.user.create(.{.name="Jane"})  │ UserFactory.build(.{.name="Jane"}) │
// ├─────────────────────────────────┼─────────────────────────────────────┤
// │ // Scenarios (multi-struct)     │ // N/A — must call build() N times │
// │ f.checkout.create(.{})          │                                     │
// │ // -> .user, .product, .order   │                                     │
// ├─────────────────────────────────┼─────────────────────────────────────┤
// │ Static data from .zon files     │ Dynamic data (sequences, lazy, etc) │
// │ Centralized registry            │ Defined per-file or per-test        │
// │ One call for multi-struct       │ One call per struct                 │
// └─────────────────────────────────┴─────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: Core `Fixture.define` + `create`

1. Create `src/fixture.zig` with `define` function returning a type with `create`/`createWith`.
2. Reuse (or extract to shared module) `validateZonFields` and `buildTypedPayload` from `factory.zig`.
3. Handle single-struct fixtures (`Fixture.define(User, data)`).
4. Handle scenario fixtures (`Fixture.define(ScenarioStruct, data)`).
5. Support field-level overrides in `create(.{ .name = "Custom" })`.
6. Re-export from `src/zspec.zig` as `zspec.Fixture`.

### Phase 2: Arrays and nested structs

7. Support fixed-size array fields (`[N]T`) — iterate `.zon` tuples and coerce each element.
8. Support nested struct coercion (already handled by `buildTypedPayload`).
9. Support union fields (already handled by `coerceToUnion`).
10. Compile-time error on array length mismatch.

### Phase 3: Scenario overrides

11. Support per-entry overrides in scenario `create`: `f.checkout.create(.{ .user = .{ .name = "Jane" } })`.
12. Merge semantics: override only specified fields, keep `.zon` defaults for the rest.

### Phase 4: Documentation and examples

13. Add `examples/fixture_test.zig` with complete usage examples.
14. Add `examples/fixtures/` directory with sample `.zon` files.
15. Add `tests/fixture_test.zig` with unit tests.
16. Update CLAUDE.md with Fixture patterns and API reference.

### Future extensions (not in initial scope)

- `Fixture.createAlloc()` for automatic pointer-based cross-reference resolution.
- Comptime slices (`[]const T`) with length inferred from `.zon` tuple.
- Integration with `Factory.assoc()` for hybrid fixture+factory workflows.

## File structure

```
src/
  fixture.zig          # New: Fixture module
  factory.zig          # Existing: may extract shared coercion utils
  zspec.zig            # Existing: add Fixture re-export
examples/
  fixture_test.zig     # New: example usage
  fixtures/
    user.zon           # New: single-struct fixture
    admin.zon          # New: single-struct variant
    checkout.zon       # New: scenario fixture
    store.zon          # New: scenario with arrays
    battle.zon         # New: nested struct scenario
tests/
  fixture_test.zig     # New: unit tests for Fixture module
```

## Alternatives Considered

### 1. Extend Factory instead of a separate module

Add `Factory.loadFixture()` to the existing module.

Rejected because Fixture and Factory have different responsibilities. Factory is a generator (dynamic, stateful — sequences, lazy values, traits). Fixture is a loader (static, pure data from `.zon`). Mixing them muddies both APIs. Separate modules keep each focused.

### 2. No `create` method — just `Fixture.load` returning a value

```zig
const checkout = Fixture.load(CheckoutScenario, @import("checkout.zon"));
```

Rejected because it doesn't support overrides at the callsite — you get the exact `.zon` data every time. The `define` + `create` pattern allows the `.zon` to serve as defaults while still permitting test-specific customization.

### 3. Pattern guide only (no new code)

Document the "registry + `.zon`" pattern using existing `Factory.defineFrom()`.

Rejected because `Factory.defineFrom` doesn't support multi-struct scenarios. And reusing Factory for static data brings unnecessary baggage (sequence counters, lazy evaluation machinery). A dedicated module is simpler and more intentional.

### 4. Convention-based type inference

Infer the target type from a `_type` field in the `.zon`:

```zig
.{ .user = .{ ._type = "User", .id = 1, .name = "John" } }
```

Rejected because Zig's comptime system can't resolve type names from strings, and it would break the ergonomics of plain `.zon` data files.

## Open Questions

1. **Shared coercion utilities**: Should `buildTypedPayload`, `validateZonFields`, and `coerceToUnion` be extracted from `factory.zig` into a shared `comptime_utils.zig`, or should `fixture.zig` import them from `factory.zig` directly?

2. **Scenario override semantics**: When `f.checkout.create(.{ .user = .{ .name = "Jane" } })` is called, should it be a full replacement of the `.user` entry, or a merge (only `.name` changes, rest keeps `.zon` defaults)? Merge is more ergonomic but harder to implement.

3. **Naming**: `Fixture.define` + `.create` vs `Fixture.register` + `.build` vs `Fixture.from` + `.get` — which names best communicate the intent?

4. **Comptime vs runtime**: Should `create` be purely comptime (the returned value is comptime-known) or should it support runtime overrides? Comptime is simpler and sufficient for static fixtures.

5. **Array length enforcement**: Should mismatched array lengths (schema says `[3]User` but `.zon` has 2 entries) be a compile error or silently zero-fill? Compile error is safer and recommended.

6. **Pointer cross-references**: Is the "defer to future RFC" stance on automatic pointer wiring the right call, or should we prototype a simple version in the initial implementation?
