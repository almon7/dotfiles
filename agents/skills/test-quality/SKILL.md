---
name: test-quality
description: Choose useful tests and review test changes for regression value. Use when adding or changing tests, assessing missing coverage, or auditing redundant or brittle tests. Not for merely running an existing suite.
---

# Test quality

Keep tests that protect required behaviour against realistic mistakes. More tests or higher coverage are not goals by themselves. Apply this judgement within the requested implementation, review or cleanup; do not impose a new development workflow.

## Select the useful check

For each behaviour or related group of tests, establish:

- The observable requirement and its source: user instruction, accepted contract, specification or independently checked example.
- A plausible mistake that would violate the requirement.
- What existing tests or other checks already protect, and the relevant gap a new test would close.

Inspect the relevant existing coverage before adding tests. Choose the narrowest interface that can expose the failure. A mocked database cannot establish that a database constraint works; a unit test can be sufficient for an isolated calculation. Prefer extending a clear existing test when it covers the same risk.

No new test is a valid outcome when existing checks suffice or the change creates no meaningful regression risk. Run the relevant checks and explain the decision briefly. Do not invent requirements, mandatory coverage percentages or a test for every changed function.

## Make assertions earn their place

Derive expected results independently of the implementation being checked. Avoid reusing the same helper or algorithm to produce both actual and expected results. Characterisation tests may preserve reviewed existing behaviour during a refactor; identify that purpose rather than treating the baseline as proof of correctness.

Exercise real project behaviour through an appropriate interface. Replace external or costly dependencies only where the replacement preserves the behaviour under test. Assert a required result or externally meaningful interaction, not the mock's own configured response.

Exact values, call counts, ordering and snapshots are appropriate when they express a real contract. Assertions that merely freeze incidental constants, private structure or source spelling should be redesigned around the behaviour they were meant to protect. Test our use of libraries where configuration, data or integration can break our contract; avoid duplicating the library's own guarantees.

For ambiguous cases involving migrations, mocks, source inspection or apparently duplicate tests, read [examples.md](references/examples.md).

## Establish that the test can detect the defect

For a bug fix, reproduce the intended failure before the fix and confirm the test passes afterwards. A collection error, missing dependency or unrelated exception is not that evidence. If reproducing the broken version is unavailable, report the limit; do not claim a failing run occurred.

For important logic with uncertain test strength, consider a targeted mutation: introduce a plausible fault and check that a relevant assertion fails. Use a disposable isolated copy of the exact code and tests being assessed, including relevant uncommitted changes. Keep the shared checkout untouched. Distinguish genuine test gaps from equivalent mutations and inconclusive timeouts; a mutation score cannot validate the requirement itself.

Consider property-based tests when a specified invariant across many inputs would expose gaps that examples miss. Reuse existing tools; a new dependency or broad mutation campaign needs its own justification. Neither technique is compulsory for ordinary changes.

## Review the tests in scope

Review requests produce findings. Keep test edits within the authorised implementation or cleanup. Test cleanup alone does not authorise changes to production behaviour.

- Keep coverage for distinct outputs, rejection paths, persistence effects and supported compatibility, even when setup looks similar.
- Consolidate or remove a redundant test only after identifying the surviving check that protects its meaningful behaviour, or evidence that the behaviour is obsolete.
- Replace implementation-coupled assertions with a useful behavioural check where a real protection gap remains.
- Change an existing expectation only when the requirement changed or the test was demonstrably wrong; explain the evidence. Never weaken or skip a legitimate assertion merely to make the suite pass.
- Run checks appropriate to the change and required repository checks. After removals, account for unexpected collection changes or skips.

Report the behaviour protected, meaningful test additions or removals, checks actually run and remaining gaps. Group the reasoning by behaviour; do not create a justification document for every test case.
