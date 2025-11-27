# Code Coverage for ZSpec

Zig doesn't have built-in code coverage support yet, but you can use external tools like **kcov** (Linux) or **grindcov** to generate coverage reports.

## Using kcov (Recommended for Linux)

[kcov](https://github.com/SimonKagworthy/kcov) uses DWARF debugging data from compiled programs to generate coverage information without requiring special compiler flags.

### Installation

```bash
# Ubuntu/Debian
sudo apt-get install kcov

# Arch Linux
sudo pacman -S kcov

# From source
git clone https://github.com/SimonKagstrom/kcov.git
cd kcov && mkdir build && cd build
cmake .. && make && sudo make install
```

### Basic Usage

Run your tests through kcov:

```bash
# Run ZSpec tests with coverage
kcov --include-pattern=/src/ coverage-output zig-out/bin/test

# Or use zig test directly with --test-cmd
zig build test --test-cmd kcov --test-cmd coverage-output --test-cmd-bin
```

### With ZSpec Projects

For projects using ZSpec, add a coverage step to your `build.zig`:

```bash
# Build tests first
zig build test

# Run with kcov
kcov --include-pattern=/src/ ./coverage ./zig-out/bin/test
```

### Viewing Results

kcov generates an HTML report in the output directory:

```bash
# Open the coverage report
open coverage/index.html  # macOS
xdg-open coverage/index.html  # Linux
```

## Using grindcov (Alternative)

[grindcov](https://github.com/ryanliptak/grindcov) uses Valgrind's Callgrind for instrumentation. It's slower but provides detailed coverage information.

### Installation

```bash
# Install Valgrind first
sudo apt-get install valgrind

# Install grindcov
cargo install grindcov
```

### Usage

```bash
zig build test --test-cmd grindcov --test-cmd -- --test-cmd-bin
```

## CI Integration

### GitHub Actions with kcov

```yaml
name: Coverage

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Zig
        uses: mlugg/setup-zig@v2
        with:
          version: '0.15.1'

      - name: Install kcov
        run: sudo apt-get install -y kcov

      - name: Build tests
        run: zig build test

      - name: Run coverage
        run: |
          kcov --include-pattern=/src/ coverage ./zig-out/bin/test

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v4
        with:
          directory: ./coverage
          fail_ci_if_error: false
```

## Caveats

### Unused Functions

Zig only compiles functions that are actually called/referenced. Completely unused functions don't contribute to the 'executable lines' total. This means:

- A file with one used function and many unused functions could show 100% coverage
- Results only indicate coverage of *used* functions

### Ignoring Lines

You can exclude specific lines from coverage:

```bash
# Using kcov's exclude option
kcov --exclude-line=//coverage:ignore coverage-output ./test
```

Then in your code:

```zig
fn myFunction() void {
    unreachable; //coverage:ignore
}
```

### Modified kcov for Zig

A [modified fork of kcov](https://zig.news/liyu1981/tiny-change-to-kcov-for-better-covering-zig-hjm) exists that automatically ignores Zig's `unreachable` and `@panic` statements.

## References

- [Code Coverage for Zig - Zig NEWS](https://zig.news/squeek564/code-coverage-for-zig-1dk1)
- [Code Coverage for Zig with Callgrind](https://www.ryanliptak.com/blog/code-coverage-zig-callgrind/)
- [kcov GitHub Repository](https://github.com/SimonKagstrom/kcov)
- [grindcov GitHub Repository](https://github.com/ryanliptak/grindcov)
