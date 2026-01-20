# Testing Guide

## Overview

Dev-Control uses [bats-core](https://github.com/bats-core/bats-core) for testing. Tests are organized by component:

```
tests/
├── gc.bats           # Integration tests for main command
├── run_tests.sh      # Test runner script
├── lib/              # Unit tests for libraries
│   ├── common.bats
│   ├── config.bats
│   └── output.bats
└── test_helper/      # bats plugins (auto-installed)
    ├── bats/
    ├── bats-support/
    └── bats-assert/
```

## Running Tests

### All Tests

```bash
./tests/run_tests.sh
```

### Specific Tests

```bash
# Library tests only
./tests/run_tests.sh lib/

# Specific test file
./tests/run_tests.sh gc.bats

# Specific test by name
bats --filter "gc --help" tests/gc.bats
```

### With Coverage

```bash
# Install kcov first
sudo apt install kcov

# Run with coverage
kcov --include-path=./scripts coverage/ ./tests/run_tests.sh
```

## Writing Tests

### Basic Structure

```bash
#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    # Runs before each test
    source "$BATS_TEST_DIRNAME/../scripts/lib/common.sh"
}

teardown() {
    # Runs after each test
    rm -rf "$TEST_TEMP_DIR"
}

@test "description of what is being tested" {
    run my_function "arg1" "arg2"
    assert_success
    assert_output "expected output"
}
```

### Common Assertions

```bash
# Status assertions
assert_success           # Exit code 0
assert_failure           # Non-zero exit code

# Output assertions
assert_output "exact"    # Exact match
assert_output --partial "contains"  # Substring
assert_output --regexp "pattern.*"  # Regex

# Comparison
assert_equal "$actual" "expected"

# File assertions
assert [ -f "$file" ]    # File exists
assert [ -d "$dir" ]     # Directory exists
```

### Testing Functions

```bash
@test "trim removes whitespace" {
    result=$(trim "  hello  ")
    assert_equal "$result" "hello"
}
```

### Testing Commands

```bash
@test "gc init creates config" {
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    git init --quiet
    
    run "$GC" init
    assert_success
    assert [ -f ".dc-init.yaml" ]
    
    rm -rf "$temp_dir"
}
```

## CI Integration

Tests run automatically on push via GitHub Actions:

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: ./tests/run_tests.sh
```

## Best Practices

1. **Isolate tests**: Use temp directories, reset globals
2. **Test one thing**: Each test should verify a single behavior
3. **Use descriptive names**: `@test "gc init with --license creates LICENSE"`
4. **Clean up**: Always remove temp files in teardown
5. **Test edge cases**: Empty inputs, missing files, invalid args
