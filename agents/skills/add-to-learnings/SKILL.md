---
name: add-to-learnings
description: Save a concept or explanation from the conversation to ~/drive/areas/learnings.md as a concise learning note with a practical example. Use when the user asks to add something to their learnings or save an explanation there.
---

# Add to learnings

Save the requested explanation to `~/drive/areas/learnings.md`, using the conversation to resolve what “this” refers to. Keep the substance and roughly the length of an explanation the user has already accepted; make it understandable when read later without the chat.

## File handling

- Read the file before editing. If it does not exist, create it with `# learnings` as its title.
- Append each new topic under a descriptive `##` heading, separated from existing content by a blank line. Preserve existing notes and the single file title.
- If the same topic is already present, avoid an identical duplicate; update that section for a requested correction or extension.
- Write directly when the user asks to save the note, subject to filesystem permissions. Read back the affected content to verify the edit and return a brief confirmation with a file link.

## Explanation style

- Open with a short paragraph stating what the concept does and why it is useful. Bold the key idea sparingly.
- Follow with a small, concrete example when useful. For code, use a fenced block with a language tag and brief comments explaining the behavior or inferred types.
- Explain how the example works in a short paragraph. Include a relevant limitation or common misconception only when it helps understanding.
- Use familiar names from the conversation, introducing enough context that the reader need not open the project or revisit the chat.
- Retain useful source links from the explanation. Research only when needed to fill a factual gap or check a claim, rather than expanding a straightforward save request.
- Keep the note concise and close to the example below. Do not add dates, metadata, exercises, a table of contents, or extra subsections unless requested. Adapt the shape to the topic; code is optional for nontechnical concepts.
- Keep each prose paragraph on a single source line; preserve code formatting and Markdown spacing.

## Good example

The following is the user's accepted note. Use it as a model for tone, length, and the balance of explanation and example; do not insert it for unrelated topics.

~~~~markdown
## Python’s `@overload` decorator

Python’s `@overload` lets you describe **how a function’s return type depends on its arguments**, so your editor and type checker can infer the correct type. ([Python docs](https://docs.python.org/3/library/typing.html#typing.overload))

For example, a `generate` method can declare two cases:

```python
# With a response model → returns an instance of that model
result = await generator.generate(messages=messages, response_model=MyModel)
# Type checker knows: result is MyModel

# Without a response model → returns text
text = await generator.generate(messages=messages)
# Type checker knows: text is str
```

The `@overload` definitions ending in `...` describe these cases. The final `generate` definition without the decorator contains the actual code and handles both.

**It doesn’t select an implementation at runtime or enforce types.** Its benefit is more precise autocomplete and type checking: without these overloads, both calls would be typed as `ResponseModelT | str`.
~~~~
