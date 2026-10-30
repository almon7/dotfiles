import { execFile, type ChildProcess } from "node:child_process";
import type { HunkExtensionAPI } from "hunkdiff/extension";
import { addGitHubComments, type PullRequestData, type ReviewContext } from "./review.ts";

export default function (hunk: HunkExtensionAPI) {
  const context: ReviewContext = JSON.parse(process.env.DOTFILES_GITHUB_REVIEW_CONTEXT || "null");
  if (!context?.repo || !context.url || !context.reader || !context.python || !context.base || !context.head) {
    throw new Error("GitHub comments need DOTFILES_GITHUB_REVIEW_CONTEXT from the Neovim PR launcher.");
  }
  const children = new Set<ChildProcess>();
  let alive = true;
  let initialLoad = true;
  let previousItems: PullRequestData["items"] | null = null;

  function run(command: string, args: string[]): Promise<string> {
    return new Promise((resolve, reject) => {
      const child = execFile(command, args, {
        cwd: context.repo,
        encoding: "utf8",
        timeout: 60_000,
        maxBuffer: 32 * 1024 * 1024,
      }, (error, stdout, stderr) => {
        children.delete(child);
        if (error) reject(new Error(stderr.trim() || error.message));
        else resolve(stdout);
      });
      children.add(child);
    });
  }

  hunk.transformChangeset(async (changeset, ctx) => {
    if (!alive) return changeset;
    if (initialLoad) {
      process.stderr.write("Loading GitHub comments…\n");
      initialLoad = false;
    }
    try {
      const data: PullRequestData = JSON.parse(await run(context.python, [context.reader, context.url]));
      if (!alive) return changeset;
      if (!data.pr || !Array.isArray(data.items)) throw new Error("The GitHub reader returned an invalid response.");
      let mergeBase: string | null = null;
      if (/^[0-9a-f]{40,64}$/.test(data.pr.baseRefOid) && /^[0-9a-f]{40,64}$/.test(data.pr.headRefOid)) {
        try {
          mergeBase = (await run("git", ["merge-base", data.pr.baseRefOid, data.pr.headRefOid])).trim();
        } catch {
          // A moved PR may name objects absent from this immutable local review.
        }
      }
      if (!alive) return changeset;
      if (data.pr.url.replace(/\/$/, "") !== context.url.replace(/\/$/, "")
        || data.pr.headRefOid !== context.head || mergeBase !== context.base) {
        previousItems = null;
        ctx.notify("GitHub's PR revisions differ from this diff or cannot be verified; reopen the PR review to see comments.", "warning");
        return changeset;
      }
      previousItems = data.items;
      return addGitHubComments(changeset, data.items);
    } catch (error) {
      if (!alive) return changeset;
      ctx.notify(`GitHub comments could not be loaded${previousItems ? "; showing the previous snapshot" : ""}: ${String(error)}. Press r to retry.`, "warning");
      return previousItems ? addGitHubComments(changeset, previousItems) : changeset;
    }
  });
  hunk.on("shutdown", () => {
    alive = false;
    children.forEach((child) => child.kill());
    children.clear();
  });
}
