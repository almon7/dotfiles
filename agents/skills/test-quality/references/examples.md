# Judging test value

Use the requirement to decide whether an assertion is meaningful. These examples illustrate decisions; they do not require these test shapes in every project.

## Migration revisions and database behaviour

An assertion that the repository's latest migration is always `abc123` fails when a legitimate migration is added and does not prove that the schema is correct. Prefer checking the outcome the changed migration promises: apply it to a disposable database, retain representative existing data where relevant, and verify the required schema or data effect. For a uniqueness requirement, attempt the prohibited duplicate.

A release manifest explicitly requiring revision `abc123` is a different contract; an exact revision assertion can protect it. Comparing a database's applied revisions with the repository's current heads checks migration status, but does not prove schema or data correctness.

## Mocks and interactions

Setting a mock's response to `{"ok": true}` and asserting that response without exercising project behaviour checks the setup. Call the real project code and assert the result that the requirement promises.

An interaction assertion can be the right check: a cancellation must issue exactly one refund request with the correct account and amount. An assertion about which private helper performs that request usually freezes an implementation choice. If retries, transactions or serialisation are the risk, keep the relevant behaviour real.

## Source text and fixed values

Checking that a Python file contains a particular line does not establish that the line executes or produces the required effect. Exercise the script with controlled inputs and check its output, exit status or side effect.

Source structure can itself be a requirement. An architecture rule forbidding a dependency, a generated interface contract or a mandated configuration value may justify a static check. Check the relevant syntax or configuration semantics, rather than unrelated spelling or whitespace.

## Tests that look alike

Two tests reaching the same path with equivalent assertions may be consolidated. Similar setup does not make successful access and rejected access duplicates. Boundary values and different failure paths can each protect a distinct mistake even when the test bodies match.

Coverage percentages or overlapping executed lines do not establish redundancy.

## Existing coverage and refactors

If a refactor moves a private helper, retain the test's behavioural protection while removing private coupling; preserve valid expected outputs. An LLM-written specification inferred from the implementation is not an independent authority for correctness.

## Properties and mutations

A normaliser may promise idempotence: applying it twice has the same result as applying it once. That property needs inputs that exercise normalisation and, where required, examples of the correct canonical output; identity alone can pass idempotence.

A test that catches a changed migration identifier may still protect the wrong requirement. Establish the requirement first, then use a relevant mutation to probe whether the assertion detects a plausible defect. A surviving mutation may preserve observable behaviour and need no extra test.

## Sources

Original synthesis informed by the following public guidance, reviewed on 28 October 2026. The skill is maintained locally and does not require loading or installing these sources.

- [gregwebs — verify](https://github.com/gregwebs/skills-sdlc/blob/main/skills/verify/SKILL.md): requirement-derived expectations and fault detection.
- [shinpr — testing-strategy](https://github.com/shinpr/agentic-code/blob/main/.agents/skills/testing-strategy/SKILL.md): test selection and existing coverage.
- [MrZoyo — deslop](https://github.com/MrZoyo/deslop-GPT/blob/main/skills/deslop/SKILL.md): redundant tests and preservation of meaningful behaviour.
- [Superpowers — writing good tests](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/writing-good-tests.md): implementation coupling and library boundaries.
- [Trail of Bits — property-based testing](https://github.com/trailofbits/skills/blob/main/plugins/property-based-testing/skills/property-based-testing/SKILL.md) and [mutation testing](https://github.com/trailofbits/skills/blob/main/plugins/mutation-testing/skills/mutation-testing/SKILL.md): stronger checks when warranted.
