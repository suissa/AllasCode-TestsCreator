# AllasCode TestsCreator

Automatic deterministic unit-test generation for every function/Action contract.

TestsCreator generates:

- one fully valid synthetic case;
- boundary cases from declared constraints;
- N isolated invalid cases, changing exactly one parameter/property at a time;
- reproducible values from a seed;
- ephemeral test execution metadata so payloads and business events are never persisted.

The canonical implementation targets Zig 0.16 and is designed to consume AllasCode Semantic AtomicBehavior Type constraints.

## Run

```bash
zig build test
zig build run
```

## Example

For:

```
CreateUser(
  name: String(min=1,max=80),
  age: Int(min=18,max=120)
)
```

the plan contains cases such as:

```
valid.default
boundary.name.min
invalid.name.too_short
boundary.name.max
invalid.name.too_long
boundary.age.min
invalid.age.below_min
boundary.age.max
invalid.age.above_max
```

Every negative case keeps all other arguments valid, so the cause of rejection is isolated.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Next integration layer

The next stage is source/Action discovery and language-specific lowering/execution adapters. The generator core intentionally stays runner-neutral.
