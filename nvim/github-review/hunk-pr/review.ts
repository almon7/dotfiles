import type { AgentAnnotation, ExtensionChangeset, ExtensionDiffFile } from "hunkdiff/extension";

export interface ReviewContext {
  repo: string;
  url: string;
  base: string;
  head: string;
  python: string;
  reader: string;
}

export interface Conversation {
  id: string;
  kind: "thread" | "discussion" | "review";
  path?: string;
  side?: "LEFT" | "RIGHT";
  line?: number | null;
  startLine?: number | null;
  startSide?: "LEFT" | "RIGHT" | null;
  isResolved?: boolean;
  isOutdated?: boolean;
  subjectType?: string;
  comments: { id: string; author: string; createdAt: string; body: string }[];
}

export interface PullRequestData {
  pr: { url: string; baseRefOid: string; headRefOid: string };
  items: Conversation[];
}

function threadAnnotation(item: Conversation, file: ExtensionDiffFile): AgentAnnotation | null {
  if (item.kind !== "thread" || item.isOutdated || item.subjectType === "FILE" || !item.comments.length) return null;
  const first = item.startSide === item.side ? (item.startLine ?? item.line) : item.line;
  const last = item.line;
  if (typeof first !== "number" || typeof last !== "number"
    || !Number.isInteger(first) || !Number.isInteger(last) || first < 1 || last < first
    || !["LEFT", "RIGHT"].includes(item.side ?? "")) return null;

  // Changeset transforms receive the patch; public hunk summaries exist only after transforms.
  const visible = [...file.patch.matchAll(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/gm)].some((hunk) => {
    const offset = item.side === "LEFT" ? 1 : 3;
    const start = Number(hunk[offset]);
    const count = Number(hunk[offset + 1] ?? 1);
    return first >= start && last < start + count;
  });
  if (!visible) return null;

  const body = item.comments.map((comment) =>
    `@${comment.author} · ${comment.createdAt}\n${comment.body || "(No comment body)"}`
  ).join("\n\n").replace(/\r\n/g, "\n");
  const range: [number, number] = [first, last];
  return {
    id: `github:${item.id}`,
    ...(item.side === "LEFT" ? { oldRange: range } : { newRange: range }),
    author: `GitHub @${item.comments[0].author}`,
    source: "github",
    summary: `${item.isResolved ? "Resolved thread\n\n" : ""}${body}`,
    editable: false,
  };
}

export function addGitHubComments(changeset: ExtensionChangeset, items: readonly Conversation[]): ExtensionChangeset {
  const annotations = new Map<string, AgentAnnotation[]>();
  for (const item of items) {
    const file = changeset.files.find((candidate) => candidate.path === item.path)
      ?? (item.side === "LEFT" ? changeset.files.find((candidate) => candidate.previousPath === item.path) : undefined);
    if (!file) continue;
    const annotation = threadAnnotation(item, file);
    if (annotation) annotations.set(file.id, [...(annotations.get(file.id) ?? []), annotation]);
  }
  return {
    ...changeset,
    files: changeset.files.map((file) => {
      const comments = annotations.get(file.id);
      return comments ? {
        ...file,
        agent: {
          ...file.agent,
          path: file.path,
          annotations: [...(file.agent?.annotations ?? []), ...comments],
        },
      } : file;
    }),
  };
}
