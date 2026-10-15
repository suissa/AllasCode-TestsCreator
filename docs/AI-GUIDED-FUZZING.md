# AI-Guided Fuzzing: Implementation Status

The original proposal used a standalone evolutionary engine. That implementation has been superseded by Zig 0.16's native `std.testing.Smith` integration in [NATIVE-SMITH-SEMANTIC-FUZZING.md](NATIVE-SMITH-SEMANTIC-FUZZING.md).

The canonical implementation is now `src/smith_fuzz.zig`. It uses typed Smith values, emphasizes declared constraint boundaries, and relies on Zig's own fuzzing engine for mutation, corpus handling, and coverage feedback. Do not add a second genetic algorithm alongside Smith.

AI-guided planning and runtime behavior feedback are future extensions: an isolated execution adapter may prioritize trajectories, branches, invariants, and crash novelty. No AI provider is required for the native fuzzer.

Run `zig build test` for ordinary tests and `zig build test-fuzz` for a bounded native fuzz pass. The actual build and fuzz run still need verification in Zig 0.16 CI before merging.
