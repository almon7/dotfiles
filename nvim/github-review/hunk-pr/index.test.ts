import assert from "node:assert/strict";
import childProcess from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import test from "node:test";
import extension from "./index.ts";

const context = {
  repo: "/review", url: "https://github.com/example/repo/pull/1",
  base: "a".repeat(40), head: "b".repeat(40), python: "python3", reader: "/fetch.py",
};
const changeset = {
  id: "review", sourceLabel: "", title: "",
  files: [{
    id: "file", path: "file.ts", patch: "@@ -1 +1 @@\n-old\n+new\n",
    metadata: {}, stats: { additions: 1, deletions: 1 }, agent: null,
  }],
};
const snapshot = {
  pr: { url: context.url, headRefOid: context.head, baseRefOid: context.base },
  items: [{
    id: "one", kind: "thread", path: "file.ts", side: "RIGHT", line: 1,
    comments: [{ id: "comment", author: "alice", createdAt: "", body: "> literal" }],
  }],
};

async function harness(run: (h: any) => Promise<void>) {
  const original = childProcess.execFile;
  const environment = process.env.DOTFILES_GITHUB_REVIEW_CONTEXT;
  const pending: any[] = [];
  const notices: string[] = [];
  let transform: any, shutdown: () => void;
  childProcess.execFile = ((command: string, args: string[], options: any, callback: any) => {
    const request = { command, args, options, callback, killed: false };
    pending.push(request);
    return { kill() { request.killed = true; } };
  }) as typeof childProcess.execFile;
  syncBuiltinESMExports();
  process.env.DOTFILES_GITHUB_REVIEW_CONTEXT = JSON.stringify(context);
  extension({
    transformChangeset(fn: any) { transform = fn; },
    on(event: string, fn: () => void) { assert.equal(event, "shutdown"); shutdown = fn; },
  } as any);
  const settle = () => new Promise<void>((resolve) => setImmediate(resolve));
  const answer = async (stdout = "", error: string | null = null) => {
    const request = pending.shift();
    assert.ok(request, "A subprocess was expected");
    request.callback(error ? new Error(error) : null, stdout, error ?? "");
    await settle();
    return request;
  };
  try {
    await run({
      pending, notices, answer, settle, shutdown: () => shutdown(),
      transform: () => transform(changeset, { notify: (message: string) => notices.push(message) }),
      load: async (data = snapshot, base: string | null = context.base) => {
        const result = transform(changeset, { notify: (message: string) => notices.push(message) });
        assert.deepEqual(pending[0].args, [context.reader, context.url]);
        assert.equal(pending[0].options.cwd, context.repo);
        await answer(JSON.stringify(data));
        assert.equal(pending[0].command, "git");
        await answer(base ?? "", base === null ? "Missing Git object" : null);
        return result;
      },
    });
  } finally {
    childProcess.execFile = original;
    syncBuiltinESMExports();
    if (environment === undefined) delete process.env.DOTFILES_GITHUB_REVIEW_CONTEXT;
    else process.env.DOTFILES_GITHUB_REVIEW_CONTEXT = environment;
  }
}

test("entrypoint annotates only the matching PR URL, head and merge base", async () => {
  await harness(async (h) => {
    const matched = await h.load();
    assert.equal(matched.files[0].agent.annotations[0].summary, "@alice · \n> literal");
    for (const pr of [
      { ...snapshot.pr, url: context.url.replace("/1", "/2") },
      { ...snapshot.pr, headRefOid: "c".repeat(40) },
    ]) assert.equal(await h.load({ ...snapshot, pr }), changeset);
    assert.equal(await h.load(snapshot, "c".repeat(40)), changeset);
    assert.equal(await h.load(snapshot, null), changeset);
    assert.equal(h.notices.length, 4);
  });
});

test("failed refresh retains validated comments, but mismatch clears the snapshot", async () => {
  await harness(async (h) => {
    await h.load();
    let result = h.transform();
    await h.answer("", "Network unavailable");
    assert.equal((await result).files[0].agent.annotations.length, 1);
    assert.match(h.notices.at(-1), /showing the previous snapshot/);
    await h.load({ ...snapshot, pr: { ...snapshot.pr, headRefOid: "c".repeat(40) } });
    result = h.transform();
    await h.answer("", "Still unavailable");
    assert.equal(await result, changeset);
    assert.doesNotMatch(h.notices.at(-1), /previous snapshot/);
    assert.equal((await h.load()).files[0].agent.annotations.length, 1);
  });
});

test("shutdown cancels the reader and cannot launch another process from a late completion", async () => {
  await harness(async (h) => {
    const result = h.transform();
    const reader = h.pending[0];
    h.shutdown();
    assert.ok(reader.killed, "The pending reader was not cancelled");
    await h.answer(JSON.stringify(snapshot));
    assert.equal(h.pending.length, 0, "A late reader result launched another child after shutdown");
    assert.equal(await result, changeset);
    assert.deepEqual(h.notices, []);
  });
});

test("shutdown cancels a pending merge-base check without publishing late annotations", async () => {
  await harness(async (h) => {
    const result = h.transform();
    await h.answer(JSON.stringify(snapshot));
    const lookup = h.pending[0];
    h.shutdown();
    assert.ok(lookup.killed);
    await h.answer(context.base);
    assert.equal(await result, changeset);
    assert.deepEqual(h.notices, []);
  });
});
