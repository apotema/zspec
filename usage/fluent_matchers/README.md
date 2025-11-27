# ZSpec Fluent Matchers Usage Example

This example demonstrates ZSpec's fluent matcher DSL, providing RSpec/Jest-like assertion syntax for Zig.

## Fluent Syntax

Instead of traditional assertion functions:
```zig
try expect.equal(value, 42);
try expect.toBeTrue(condition);
```

ZSpec fluent matchers provide a more readable, chainable syntax:
```zig
try expect(value).to().equal(42);
try expect(condition).to().beTrue();
try expect(value).notTo().beNull();
```

## Available Matchers

### Equality
```zig
try expect(@as(i32, 42)).to().equal(42);
try expect(value).notTo().equal(0);
try expect(slice).to().eql(other_slice);  // Deep equality
```

### Boolean
```zig
try expect(condition).to().beTrue();
try expect(condition).to().beFalse();
try expect(condition).notTo().beTrue();
```

### Comparison
```zig
try expect(@as(i32, 10)).to().beGreaterThan(5);
try expect(@as(i32, 5)).to().beLessThan(10);
try expect(@as(i32, 10)).to().beGreaterThanOrEqual(10);
try expect(@as(i32, 10)).to().beLessThanOrEqual(10);
try expect(@as(i32, 50)).to().beBetween(1, 100);
```

### Null/Optional
```zig
const opt: ?i32 = null;
try expect(opt).to().beNull();

const value: ?i32 = 42;
try expect(value).notTo().beNull();
```

### String/Slice
```zig
try expect(@as([]const u8, "hello world")).to().contain("world");
try expect(@as([]const u8, "/usr/local")).to().startWith("/usr");
try expect(@as([]const u8, "file.zig")).to().endWith(".zig");
try expect(@as([]const u8, "hello")).to().haveLength(5);
try expect(@as([]const u8, "")).to().beEmpty();
try expect(@as([]const u8, "content")).notTo().beEmpty();
```

### Type
```zig
try expect(value).to().beOfType(i32);
```

## Negation with `.notTo()`

All matchers support negation via `.notTo()`:
```zig
try expect(@as(i32, 42)).notTo().equal(0);
try expect(false).notTo().beTrue();
try expect(value).notTo().beNull();
try expect(@as([]const u8, "hello")).notTo().contain("goodbye");
try expect(@as([]const u8, "text")).notTo().beEmpty();
```

## Running the Example

```bash
cd usage/fluent_matchers
zig build test
```

## Project Structure

```
fluent_matchers/
├── build.zig           # Build configuration
├── build.zig.zon       # Dependencies (references parent zspec)
├── README.md           # This file
├── src/
│   └── calculator.zig  # Example module under test
└── tests/
    └── calculator_test.zig  # Tests using fluent matchers
```

## Integration

To use fluent matchers in your project, import from zspec:

```zig
const zspec = @import("zspec");
const expect = zspec.expectFluent;

test "my test" {
    try expect(@as(i32, 2 + 2)).to().equal(4);
}
```

Or import the matchers module directly:
```zig
const matchers = @import("zspec").matchers;
const expect = matchers.expect;
```

## Syntax Notes

The syntax uses method calls for both `.to()` and `.notTo()`:

- `expect(x).to().equal(y)` - positive assertion
- `expect(x).notTo().equal(y)` - negated assertion

This design works within Zig's type system constraints while providing a fluent API.
