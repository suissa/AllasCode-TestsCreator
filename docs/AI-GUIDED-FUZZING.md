# AI-Guided Fuzzing

TestsCreator uses a deterministic adaptive evolutionary fuzzing primitive. It is provider-free: candidates are selected by a fitness function and mutated around the highest-value frontier rather than sampled uniformly.

The population is scored by proximity to declared minimum/maximum constraints and evolved across bounded generations. Novel fingerprints are retained as generated test cases.

This is the first intelligent-search layer, not a claim of semantic AI. It currently has no execution oracle, branch-coverage feedback, crash classifier, or learned policy.

## Evolution loop

Seed → population → score → elite selection → mutation → score → novelty filter → next generation.

The fitness function is the extension point. A future execution adapter can reward new trajectory/state coverage, distance to an uncovered branch, invariant violations, crash/error novelty, latency/resource anomalies, or an AI judge's semantic feedback.

## Combination with trajectory coverage

Trajectory Coverage identifies reachable terminal paths. Adaptive fuzzing can then use execution feedback to prioritize inputs that reach trajectories or transitions that remain uncovered. This turns the pipeline into targeted exploration rather than blind Cartesian-product enumeration.

## Reproducibility and isolation

Runs have explicit seeds and bounded population/generation/mutation parameters. Generated payloads remain ephemeral under the existing execution policy; production side effects must be isolated by the execution adapter.
