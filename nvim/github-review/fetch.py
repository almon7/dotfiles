#!/usr/bin/env python3
"""Read pull request inline threads through the authenticated gh CLI."""

from datetime import datetime, timezone
import json
import re
import signal
import subprocess
import sys


COMMAND_TIMEOUT = 30
COMMENT_FIELDS = "id url body createdAt author { login }"
PAGE_INFO = "pageInfo { hasNextPage endCursor }"
PR_FIELDS = """
number title url baseRefName headRefName baseRefOid headRefOid
"""
PR_QUERY = """
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) { %s }
  }
}
""" % PR_FIELDS
THREAD_FIELDS = """
id path diffSide line startLine startDiffSide isResolved isOutdated subjectType
comments(first: 100) {
  nodes { %s }
  %s
}
""" % (COMMENT_FIELDS, PAGE_INFO)
REPLIES_QUERY = """
query($id: ID!, $cursor: String) {
  node(id: $id) {
    ... on PullRequestReviewThread {
      comments(first: 100, after: $cursor) {
        nodes { %s }
        %s
      }
    }
  }
}
""" % (COMMENT_FIELDS, PAGE_INFO)


class FetchError(Exception):
    """An error safe to report without a traceback."""


def parse_url(url):
    match = re.fullmatch(
        r"https://([A-Za-z0-9.-]+)/([A-Za-z0-9_.-]+)/"
        r"([A-Za-z0-9_.-]+)/pull/([1-9][0-9]*)/?",
        url,
    )
    if not match:
        raise FetchError("Expected a full HTTPS pull request URL.")
    host, owner, repo, number = match.groups()
    if (
        not all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?", label)
                for label in host.split("."))
        or owner in (".", "..")
        or repo in (".", "..")
        or int(number) > 2147483647
    ):
        raise FetchError("Invalid pull request URL.")
    return host.lower(), {"owner": owner, "repo": repo, "number": int(number)}


def graphql(host, query, variables):
    try:
        process = subprocess.Popen(
            ["gh", "api", "graphql", "--hostname", host, "--method", "POST", "--input", "-"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            encoding="utf-8",
        )
        try:
            stdout, stderr = process.communicate(
                input=json.dumps({"query": query, "variables": variables}),
                timeout=COMMAND_TIMEOUT,
            )
        except BaseException:
            process.kill()
            process.communicate()
            raise
    except FileNotFoundError as error:
        raise FetchError("GitHub CLI (gh) is required.") from error
    except subprocess.TimeoutExpired as error:
        raise FetchError(f"GitHub request timed out after {COMMAND_TIMEOUT} seconds.") from error
    except OSError as error:
        raise FetchError(f"Cannot run GitHub CLI: {error}") from error
    if process.returncode:
        message = " ".join(stderr.split())[:600] or f"exit status {process.returncode}"
        raise FetchError(f"GitHub request failed: {message}")
    try:
        response = json.loads(stdout)
    except json.JSONDecodeError as error:
        raise FetchError("GitHub CLI returned invalid JSON.") from error
    if not isinstance(response, dict):
        raise FetchError("GitHub returned an incomplete or unexpected response.")
    if response.get("errors"):
        message = " ".join("; ".join(error["message"] for error in response["errors"]).split())
        raise FetchError(f"GitHub request failed: {message[:600]}")
    return response["data"]


def pull_request(host, variables, query=PR_QUERY):
    repository = graphql(host, query, variables)["repository"]
    if not repository or not repository["pullRequest"]:
        raise FetchError("Pull request was not found or is not accessible.")
    return repository["pullRequest"]


def next_cursor(connection, seen):
    if not connection["pageInfo"]["hasNextPage"]:
        return None
    cursor = connection["pageInfo"]["endCursor"]
    if not cursor or cursor in seen:
        raise FetchError("GitHub returned an invalid pagination cursor.")
    seen.add(cursor)
    return cursor


def review_threads(host, variables):
    query = """
    query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100, after: $cursor) {
            nodes { %s }
            %s
          }
        }
      }
    }
    """ % (THREAD_FIELDS, PAGE_INFO)
    nodes, seen = [], set()
    cursor = None
    while True:
        connection = pull_request(host, dict(variables, cursor=cursor), query)["reviewThreads"]
        nodes.extend(connection["nodes"])
        cursor = next_cursor(connection, seen)
        if cursor is None:
            return nodes


def thread_comments(host, thread):
    connection = thread["comments"]
    comments, seen = [], set()
    while True:
        comments.extend(connection["nodes"])
        cursor = next_cursor(connection, seen)
        if cursor is None:
            return sorted(comments, key=lambda comment: comment["createdAt"])
        node = graphql(host, REPLIES_QUERY, {"id": thread["id"], "cursor": cursor})["node"]
        if not node:
            raise FetchError("A review thread disappeared while loading. Refresh the review.")
        connection = node["comments"]


def author(node):
    return (node.get("author") or {}).get("login") or "unknown"


def comment(node):
    return {key: node[key] for key in ("id", "url", "createdAt", "body")} | {"author": author(node)}


def fetch(url):
    host, variables = parse_url(url)
    initial = pull_request(host, variables)
    items = []
    for thread in review_threads(host, variables):
        comments = thread_comments(host, thread)
        first = comments[0] if comments else None
        items.append({
            "id": thread["id"],
            "kind": "thread",
            "url": first["url"] if first else initial["url"],
            "createdAt": first["createdAt"] if first else "",
            "path": thread["path"],
            "side": thread["diffSide"],
            "line": thread["line"],
            "startLine": thread["startLine"],
            "startSide": thread["startDiffSide"],
            "isResolved": thread["isResolved"],
            "isOutdated": thread["isOutdated"],
            "subjectType": thread["subjectType"],
            "comments": [comment(node) for node in comments],
        })
    items.sort(key=lambda item: (item["isResolved"], item["createdAt"]))
    latest = pull_request(host, variables)
    if any(initial[key] != latest[key] for key in (
        "baseRefName", "headRefName", "baseRefOid", "headRefOid",
    )):
        raise FetchError("Pull request base or head changed while loading. Refresh the review.")
    return {
        "pr": latest,
        "items": items,
        "fetchedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }


def main():
    if len(sys.argv) != 2:
        print("Usage: fetch.py https://HOST/OWNER/REPO/pull/NUMBER", file=sys.stderr)
        return 2
    try:
        result = fetch(sys.argv[1])
    except FetchError as error:
        print(str(error), file=sys.stderr)
        return 1
    except (KeyError, TypeError, ValueError):
        print("GitHub returned an incomplete or unexpected response.", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


def terminate(signum, _frame):
    raise SystemExit(128 + signum)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, terminate)
    sys.exit(main())
