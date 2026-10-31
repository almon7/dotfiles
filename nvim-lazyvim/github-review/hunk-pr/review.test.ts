import assert from "node:assert/strict";
import test from "node:test";
import { addGitHubComments, type Conversation } from "./review.ts";

const changeset = {
  id: "review", sourceLabel: "", title: "",
  files: [{
    id: "file", path: "new.ts", previousPath: "old.ts",
    patch: "@@ -10,3 +20,4 @@\n unchanged\n-old\n+new\n+extra\n last\n",
    metadata: {}, stats: { additions: 2, deletions: 1 }, agent: null,
  }],
};
const thread: Conversation = {
  id: "thread", kind: "thread", path: "new.ts", side: "RIGHT", line: 21,
  comments: [{ id: "one", author: "alice", createdAt: "2026-10-20", body: "Check this line." }],
};
const notes = (items: Conversation[], source = changeset) =>
  addGitHubComments(source, items).files.flatMap((file) => file.agent?.annotations ?? []);

test("current threads attach to exact ranges on either side, including renames", () => {
  assert.deepEqual(notes([thread])[0].newRange, [21, 21]);
  const old = notes([{ ...thread, path: "old.ts", side: "LEFT", line: 12, startLine: 10, startSide: "LEFT" }])[0];
  assert.deepEqual(old.oldRange, [10, 12]);
  assert.equal(old.newRange, undefined);
});

test("a replacement at a renamed file's old path keeps its own RIGHT comments", () => {
  const replacement = { ...changeset.files[0], id: "replacement", path: "old.ts", previousPath: undefined };
  const result = addGitHubComments({ ...changeset, files: [...changeset.files, replacement] }, [{ ...thread, path: "old.ts" }]);
  assert.equal(result.files[0].agent, null);
  assert.equal(result.files[1].agent?.annotations.length, 1);
  assert.deepEqual(notes([{ ...thread, path: "old.ts" }]), []);
});

test("outdated, missing, invalid, wrong-side and off-hunk ranges have no false placement", () => {
  for (const change of [
    { isOutdated: true }, { path: "missing.ts" }, { line: null }, { line: 0 }, { line: 19 },
    { side: "LEFT" as const }, { line: 24 },
    { startLine: 22, startSide: "RIGHT" as const }, { startLine: 19, startSide: "RIGHT" as const },
  ]) assert.deepEqual(notes([{ ...thread, ...change }]), []);
});

test("a cross-side range attaches to its exact final line without inventing a same-side range", () => {
  assert.deepEqual(notes([{ ...thread, startLine: 10, startSide: "LEFT" }])[0].newRange, [21, 21]);
});

test("PR discussions, reviews and file-level comments do not invent line locations", () => {
  for (const kind of ["discussion", "review"] as const) assert.deepEqual(notes([{ ...thread, kind }]), []);
  assert.deepEqual(notes([{ ...thread, subjectType: "FILE", line: null }]), []);
});

test("hunks with zero lines on one side do not accept a comment on that side", () => {
  const source = { ...changeset, files: [{ ...changeset.files[0], patch: "@@ -10,0 +20 @@\n+new\n" }] };
  assert.deepEqual(notes([{ ...thread, side: "LEFT", line: 10 }], source), []);
  assert.deepEqual(notes([{ ...thread, line: 20 }], source)[0].newRange, [20, 20]);
});

test("raw bodies, replies and resolved state remain read-only and explicitly GitHub-labelled", () => {
  const body = "> quoted text\n**bold** <text> & `code`\n```diff\n+ added\n```";
  const [annotation] = notes([{
    ...thread, isResolved: true,
    comments: [
      { ...thread.comments[0], body },
      { id: "two", author: "bob", createdAt: "2026-10-21", body: "Reply\r\n> still quoted" },
    ],
  }]);
  assert.equal(annotation.author, "GitHub @alice");
  assert.equal(annotation.source, "github");
  assert.equal(annotation.editable, false);
  assert.equal(annotation.markup, undefined);
  assert.equal(annotation.summary, `Resolved thread\n\n@alice · 2026-10-20\n${body}\n\n@bob · 2026-10-21\nReply\n> still quoted`);
});

test("multiple threads retain their independent anchors and existing annotations", () => {
  const existing = { summary: "Existing annotation", newRange: [20, 20] as [number, number] };
  const source = { ...changeset, files: [{ ...changeset.files[0], agent: { path: "new.ts", annotations: [existing] } }] };
  const result = addGitHubComments(source, [thread, { ...thread, id: "other", line: 23 }]);
  assert.deepEqual(result.files[0].agent?.annotations.map((note) => note.newRange), [[20, 20], [21, 21], [23, 23]]);
  assert.equal(source.files[0].agent.annotations.length, 1);
  assert.equal(result.files[0].metadata, source.files[0].metadata);
});
