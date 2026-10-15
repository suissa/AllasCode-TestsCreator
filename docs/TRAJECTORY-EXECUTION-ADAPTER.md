# Trajectory Execution Feedback Adapter

The structural generator in `src/trajectory.zig` produces terminal paths and structural edge coverage. The adapter in `src/trajectory_executor.zig` executes those paths through caller-supplied test callbacks and reports runtime feedback separately from structural coverage.

## Contract

- Every edge in a generated trajectory is passed to an `ActionRunner` in path order.
- A failed Action marks that edge as failed and stops only the current trajectory; subsequent trajectories still run.
- Terminal invariants are checked only when every Action in that terminal trajectory passes.
- The report distinguishes attempted edges, passed edges, failed edges, unattempted edges, passed trajectories, and invariant failures.
- Payloads and business events are not serialized or persisted by this adapter. Test callbacks must use ephemeral fixtures, fakes, or isolated test services and must not invoke production side effects.

## API sketch

The adapter accepts a generated `trajectory.Plan`, the graph used to create it, an opaque test context, an Action callback, and a terminal invariant oracle. The callback layer is intentionally runtime-neutral: a repository-specific harness can connect it to Zig functions, a local process, or a test service without coupling the trajectory generator to a transport or production runtime.

## Run

```sh
zig build test
```

CI includes tests for successful terminal paths, Action failure short-circuiting, and invariant failures. This is an execution-feedback interface, not an OS process sandbox: callers are responsible for enforcing process/container isolation when testing untrusted Actions.
