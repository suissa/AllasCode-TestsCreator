# AI-Guided Fuzzing

TestsCreator now has a deterministic adaptive fuzzing primitive. It is intentionally provider-free: the search policy behaves like a lightweight evolutionary algorithm and can later consume execution feedback from an LLM, coverage engine, or reinforcement-learning policy.

The generator maintains a population of candidate inputs. Each generation selects the highest-scoring candidates and mutates them. The score rewards proximity to declared minimum and maximum constraints, concentrating search around likely behavioral boundaries instead of enumerating the Cartesian product of all inputs.

The current implementation is structural and model-driven. It does not claim semantic intelligence: it has no execution oracle, branch coverage feedback, crash classifier, or learned policy yet.

## Evolution loop

Seed → population → score → elite selection → mutation → score → novelty filter → next generation.

The important extension point is the fitness function. Today it uses constraint-frontier proximity. A future execution adapter can add:

- new branch/state coverage;
- distance to an uncovered trajectory;
- invariant violations;
- error/crash novelty;
- latency/resource anomalies;
- semantic feedback from an AI judge.

## Why this is preferable to blind fuzzing

Blind fuzzing spends most of its budget in the already-well-explored interior of a valid input space. Adaptive fuzzing allocates more mutations to candidates close to modeled boundaries and to candidates that produce novel fingerprints. This is especially useful when combined with Trajectory Coverage: the next fitness function can explicitly reward inputs that reach previously uncovered behavioral branches.

## Safety and reproducibility

Every run has an explicit seed and bounded population/generation/mutation parameters. Test payloads remain ephemeral under the existing execution policy. The generator should be treated as a test-case producer; production side effects must be isolated by the execution adapter.
