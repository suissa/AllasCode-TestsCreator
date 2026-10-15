---
name: native-smith-semantic-fuzzing
description: Use Zig 0.16 std.testing.Smith to generate constraint-aware inputs for AllasCode contracts and fuzz the canonical case generator.
---

# Native Smith Semantic Fuzzing

1. Use Zig 0.16 `std.testing.fuzz` and `std.testing.Smith`; do not implement a competing mutation engine.
2. Derive typed candidate inputs from `FunctionSpec` and its constraints.
3. Bias generated candidates toward declared boundaries and adjacent values while preserving bounded allocation.
4. Assert that generated values respect the constraints before passing them to the existing canonical test generator.
5. Run ordinary tests with `zig build test` and bounded native fuzzing with `zig build test-fuzz`.
6. Treat any discovered failure as a regression candidate and preserve a minimized reproducer/corpus according to Zig's native workflow.
7. Do not claim runtime Action coverage until an isolated execution adapter and explicit behavioral oracle exist.
8. Keep payloads ephemeral and isolate all side effects.
