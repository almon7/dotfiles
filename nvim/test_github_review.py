#!/usr/bin/env python3
"""Offline regression tests for the shared read-only GitHub PR reader."""

from copy import deepcopy
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch


SCRIPT = Path(__file__).resolve().parent / "github-review" / "fetch.py"
SPEC = importlib.util.spec_from_file_location("github_review_fetch", SCRIPT)
FETCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FETCH)
URL = "https://github.com/example/repo/pull/42"
PR = {
    "number": 42, "title": "A review", "url": URL,
    "baseRefName": "main", "headRefName": "feature",
    "baseRefOid": "a" * 40, "headRefOid": "b" * 40,
}


def comment(identifier, created=1, body="Comment", **values):
    return {
        "id": identifier, "url": URL + "#discussion-" + identifier,
        "createdAt": f"2026-10-20T00:{created // 60:02}:{created % 60:02}Z",
        "body": body, "author": {"login": "reviewer"},
        **values,
    }


def connection(nodes, cursor=None):
    return {"nodes": nodes, "pageInfo": {"hasNextPage": cursor is not None, "endCursor": cursor}}


def thread(identifier, created=1, **values):
    return {
        "id": identifier, "path": "src/app.py", "diffSide": "RIGHT", "line": 12,
        "startLine": 10, "startDiffSide": "RIGHT", "isResolved": False,
        "isOutdated": False, "subjectType": "LINE",
        "comments": connection([comment(identifier + "-comment", created)]), **values,
    }


class GitHubFixture:
    """Serve GraphQL pages at the subprocess boundary without network or gh."""

    def __init__(self, pr=None, threads=None, replies=None):
        self.pr = deepcopy(pr or PR)
        self.latest = deepcopy(self.pr)
        self.pages = threads or [connection([])]
        self.replies = replies or {}
        self.calls = []
        self.metadata_reads = 0

    def run(self, args, **options):
        request = json.loads(options["input"])
        query, variables = request["query"], request["variables"]
        self.calls.append((args, options, query, variables))
        if "node(id: $id)" in query:
            page = self.replies[(variables["id"], variables["cursor"])]
            data = {"node": {"comments": deepcopy(page)}}
        elif "$cursor" not in query:
            self.metadata_reads += 1
            pr = self.pr if self.metadata_reads == 1 else self.latest
            data = {"repository": {"pullRequest": deepcopy(pr)}}
        else:
            if "reviewThreads(first: 100, after: $cursor)" not in query:
                raise AssertionError("Only inline review threads should be requested")
            pages = self.pages
            cursor = variables["cursor"]
            index = 0 if cursor is None else next(
                index + 1 for index, page in enumerate(pages)
                if page["pageInfo"]["endCursor"] == cursor
            )
            data = {"repository": {"pullRequest": {"reviewThreads": deepcopy(pages[index])}}}
        return subprocess.CompletedProcess(args, 0, json.dumps({"data": data}), "")


class GitHubReviewTests(unittest.TestCase):
    def popen(self, run):
        run = Mock(side_effect=run)

        def start(args, **options):
            process = Mock()

            def communicate(input=None, timeout=None):
                if input is None:
                    return "", ""
                result = run(args, input=input, timeout=timeout, **options)
                process.returncode = result.returncode
                return result.stdout, result.stderr

            process.communicate.side_effect = communicate
            return process

        return start

    def read(self, fixture, url=URL):
        with patch.object(FETCH.subprocess, "Popen", side_effect=self.popen(fixture.run)):
            return FETCH.fetch(url)

    def cli(self, args, run):
        with (
            patch.object(FETCH.sys, "argv", [str(SCRIPT), *args]),
            patch.object(FETCH.subprocess, "Popen", side_effect=self.popen(run)),
            patch.object(FETCH.sys, "stdout", new_callable=io.StringIO) as stdout,
            patch.object(FETCH.sys, "stderr", new_callable=io.StringIO) as stderr,
        ):
            status = FETCH.main()
        return status, stdout.getvalue(), stderr.getvalue()

    def test_empty_pr_has_latest_metadata_and_timestamp(self):
        fixture = GitHubFixture()
        fixture.latest["title"] = "Updated title"
        result = self.read(fixture)
        self.assertEqual(result["items"], [])
        self.assertEqual(result["pr"], fixture.latest)
        self.assertRegex(result["fetchedAt"], r"^\d{4}-\d\d-\d\dT.*Z$")
        self.assertEqual(fixture.metadata_reads, 2)
        self.assertEqual(len(fixture.calls), 3)
        self.assertEqual(set(FETCH.PR_FIELDS.split()), set(PR))

    def test_thread_anchors_and_unresolved_first_order(self):
        fixture = GitHubFixture(
            threads=[connection([
                thread("resolved", 1, isResolved=True),
                thread("new", 4),
                thread("old", 2, diffSide="LEFT", startDiffSide="LEFT", isOutdated=True),
            ])],
        )
        result = self.read(fixture)
        self.assertEqual(
            [item["id"] for item in result["items"]],
            ["old", "new", "resolved"],
        )
        old = result["items"][0]
        self.assertEqual(old["side"], "LEFT")
        self.assertEqual(old["startSide"], "LEFT")
        self.assertEqual((old["line"], old["startLine"]), (12, 10))
        self.assertTrue(old["isOutdated"])
        self.assertTrue(result["items"][2]["isResolved"])
        self.assertTrue(all(item["kind"] == "thread" for item in result["items"]))

    def test_paginates_threads_and_all_nested_replies(self):
        threads = [thread(f"t{i}", i) for i in range(101)]
        replies = [comment(f"reply-{i}", i) for i in range(205)]
        threads[0]["comments"] = connection(replies[:100], "reply-page-2")
        fixture = GitHubFixture(
            threads=[connection(threads[:100], "thread-2"), connection(threads[100:])],
            replies={
                ("t0", "reply-page-2"): connection(replies[100:200], "reply-page-3"),
                ("t0", "reply-page-3"): connection(replies[200:]),
            },
        )
        result = self.read(fixture)
        self.assertEqual(len(result["items"]), 101)
        self.assertEqual(
            [node["id"] for node in result["items"][0]["comments"]],
            [node["id"] for node in replies],
        )
        self.assertEqual(sum(item["kind"] == "thread" for item in result["items"]), 101)
        self.assertEqual(len(fixture.calls), 6)

    def test_preserves_literal_text_and_deleted_authors_in_json_output(self):
        body = '> quote\nAuthored &gt; &amp; <tag>\nLiteral \\n \\u00e9 \\" `x > 1`\n£ café 日本語 🐈\r\n'
        fixture = GitHubFixture(
            threads=[connection([thread(
                "thread", comments=connection([comment("reply", body=body, author=None)]),
            )])],
        )
        status, output, error = self.cli([URL], fixture.run)
        self.assertEqual((status, error), (0, ""))
        result = json.loads(output)
        for item in result["items"]:
            self.assertEqual(item["comments"][0]["body"], body)
            self.assertEqual(item["comments"][0]["author"], "unknown")
        self.assertIn("日本語", output)

    def test_thread_url_and_created_at_use_earliest_comment(self):
        early, late = comment("early", 1), comment("late", 2)
        fixture = GitHubFixture(threads=[connection([thread(
            "thread", comments=connection([late, early]),
        )])])
        item = self.read(fixture)["items"][0]
        self.assertEqual(item["url"], early["url"])
        self.assertEqual(item["createdAt"], early["createdAt"])
        self.assertEqual([node["id"] for node in item["comments"]], ["early", "late"])

    def test_empty_and_file_threads_have_no_invented_line(self):
        fixture = GitHubFixture(threads=[connection([thread(
            "empty", comments=connection([]), line=None, startLine=None,
            startDiffSide=None, subjectType="FILE",
        )])])
        item = self.read(fixture)["items"][0]
        self.assertEqual(item["comments"], [])
        self.assertEqual(item["url"], URL)
        self.assertEqual(item["createdAt"], "")
        self.assertIsNone(item["line"])
        self.assertIsNone(item["startLine"])
        self.assertIsNone(item["startSide"])
        self.assertEqual(item["subjectType"], "FILE")

    def test_enterprise_host_is_explicit_and_requests_are_read_only(self):
        fixture = GitHubFixture()
        self.read(fixture, "https://GitHub.Example.org/team/repo-name/pull/42/")
        for args, options, query, variables in fixture.calls:
            self.assertEqual(args, [
                "gh", "api", "graphql", "--hostname", "github.example.org",
                "--method", "POST", "--input", "-",
            ])
            self.assertTrue(query.lstrip().startswith("query("))
            self.assertNotIn("mutation", query)
            self.assertEqual(options["timeout"], 30)
            self.assertEqual(options["encoding"], "utf-8")
            self.assertNotIn("shell", options)
            self.assertNotIn("cwd", options)
            self.assertEqual(variables["owner"], "team")
            self.assertEqual(variables["repo"], "repo-name")
            self.assertEqual(variables["number"], 42)

    def test_invalid_urls_fail_before_running_gh(self):
        urls = [
            "42", "example/repo#42", "http://github.com/example/repo/pull/42",
            "https://user:pass@github.com/example/repo/pull/42",
            "https://github.com:443/example/repo/pull/42",
            "https://github.com/example/repo/pull/0",
            "https://github.com/example/repo/pull/-1",
            "https://github.com/example/repo/pull/2147483648",
            "https://github.com/example/repo/pull/42/files",
            "https://github.com/example/repo/pull/42?x=1",
            "https://github.com/example/repo/pull/42#comment",
            "https://github.com/example/../pull/42",
            "https://github.com/./repo/pull/42",
            "https://-github.com/example/repo/pull/42",
            "https://github..com/example/repo/pull/42",
            "https://github.com/example/repo/pull/42\n",
            "https://github.com/example/$(touch bad)/pull/42",
        ]
        with patch.object(FETCH.subprocess, "Popen") as run:
            for url in urls:
                with self.subTest(url=url), self.assertRaises(FETCH.FetchError):
                    FETCH.fetch(url)
            run.assert_not_called()

    def test_changed_head_base_or_branch_names_fail_without_json(self):
        for field in ("headRefOid", "baseRefOid", "headRefName", "baseRefName"):
            with self.subTest(field=field):
                fixture = GitHubFixture()
                fixture.latest[field] = "changed"
                status, output, error = self.cli([URL], fixture.run)
                self.assertEqual((status, output), (1, ""))
                self.assertIn("changed while loading", error)

    def test_cli_reports_request_failures_concisely(self):
        cases = [
            (FileNotFoundError(), "GitHub CLI (gh) is required"),
            (subprocess.TimeoutExpired("gh", 30), "timed out after 30 seconds"),
            (PermissionError("permission denied"), "Cannot run GitHub CLI"),
            (subprocess.CompletedProcess([], 1, "", "gh: authentication failed\n"), "authentication failed"),
            (subprocess.CompletedProcess([], 1, "", ""), "exit status 1"),
            (subprocess.CompletedProcess([], 0, "not JSON", ""), "invalid JSON"),
            (subprocess.CompletedProcess([], 0, "[]", ""), "incomplete or unexpected"),
            (subprocess.CompletedProcess([], 0, '{"errors":[{"message":"rate limit exceeded"}]}', ""),
             "rate limit exceeded"),
            (subprocess.CompletedProcess([], 0, '{"data":{"repository":null}}', ""), "not accessible"),
            (subprocess.CompletedProcess([], 0, '{"data":{"repository":{"pullRequest":null}}}', ""),
             "not accessible"),
            (subprocess.CompletedProcess([], 0, '{"data":{}}', ""), "incomplete or unexpected"),
        ]
        for response, message in cases:
            with self.subTest(message=message):
                run = response if isinstance(response, Exception) else lambda *args, **kwargs: response
                status, output, error = self.cli([URL], run)
                self.assertEqual((status, output), (1, ""))
                self.assertIn(message, error)
                self.assertEqual(len(error.splitlines()), 1)

    def test_partial_graphql_errors_fail_instead_of_showing_partial_results(self):
        response = {"data": {"repository": {"pullRequest": PR}}, "errors": [{"message": "Forbidden"}]}
        run = lambda *args, **kwargs: subprocess.CompletedProcess([], 0, json.dumps(response), "")
        status, output, error = self.cli([URL], run)
        self.assertEqual((status, output), (1, ""))
        self.assertIn("Forbidden", error)

    def test_repeated_or_missing_pagination_cursor_fails(self):
        for cursor in ("same", None):
            page = connection([thread("thread")], cursor)
            page["pageInfo"]["hasNextPage"] = True
            fixture = GitHubFixture(threads=[page, page])
            with self.subTest(cursor=cursor), self.assertRaisesRegex(FETCH.FetchError, "pagination cursor"):
                self.read(fixture)

    def test_missing_argument_prints_usage(self):
        status, output, error = self.cli([], lambda *args, **kwargs: self.fail("gh must not run"))
        self.assertEqual((status, output), (2, ""))
        self.assertIn("Usage:", error)

    def test_timeout_kills_and_reaps_active_gh(self):
        process = Mock()
        process.communicate.side_effect = [subprocess.TimeoutExpired("gh", 30), ("", "")]
        with patch.object(FETCH.subprocess, "Popen", return_value=process):
            with self.assertRaisesRegex(FETCH.FetchError, "timed out"):
                FETCH.fetch(URL)
        process.kill.assert_called_once_with()
        self.assertEqual(process.communicate.call_count, 2)

    def test_sigterm_stops_reader_and_active_gh(self):
        with tempfile.TemporaryDirectory(prefix="github-review-") as directory:
            root = Path(directory)
            child_pid = root / "gh-pid"
            gh = root / "gh"
            gh.write_text(
                f"#!{sys.executable}\n"
                "import os, pathlib, time\n"
                "pathlib.Path(os.environ['TEST_GH_PID']).write_text(str(os.getpid()))\n"
                "time.sleep(60)\n"
            )
            gh.chmod(0o700)
            environment = dict(
                os.environ, PATH=f"{root}{os.pathsep}{os.environ['PATH']}",
                TEST_GH_PID=str(child_pid),
            )
            process = subprocess.Popen(
                [sys.executable, "-B", str(SCRIPT), URL],
                env=environment, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            try:
                deadline = time.monotonic() + 5
                while not child_pid.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(child_pid.exists(), "gh did not start")
                process.terminate()
                stdout, stderr = process.communicate(timeout=5)
                self.assertEqual((stdout, stderr), ("", ""))
                self.assertEqual(process.returncode, 128 + signal.SIGTERM)
                with self.assertRaises(ProcessLookupError):
                    os.kill(int(child_pid.read_text()), 0)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
                if child_pid.exists():
                    try:
                        os.kill(int(child_pid.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_quitting_neovim_reaps_its_reader_and_gh(self):
        with tempfile.TemporaryDirectory(prefix="github-review-exit-") as directory:
            root = Path(directory)
            pids = root / "pids.json"
            gh = root / "gh"
            gh.write_text(
                f"#!{sys.executable}\n"
                "import json, os, pathlib, time\n"
                "pathlib.Path(os.environ['TEST_GH_PID']).write_text("
                "json.dumps({'reader': os.getppid(), 'gh': os.getpid()}))\n"
                "time.sleep(60)\n"
            )
            gh.chmod(0o700)
            script = root / "quit.lua"
            script.write_text(
                "vim.opt.rtp:prepend(vim.env.TEST_NVIM_CONFIG)\n"
                "local view = { tabpage = vim.api.nvim_get_current_tabpage(),\n"
                "  emitter = { on = function() end, off = function() end } }\n"
                "package.loaded['diffview.lib'] = { get_current_view = function() return view end }\n"
                "require('config.github_review').attach(vim.env.TEST_REPO, "
                "'https://github.com/example/repo/pull/42', string.rep('a',40)..'..'..string.rep('b',40))\n"
                "assert(vim.wait(5000, function() return vim.uv.fs_stat(vim.env.TEST_GH_PID) ~= nil end))\n"
                "vim.cmd('qall!')\n"
            )
            environment = dict(
                os.environ, PATH=f"{root}{os.pathsep}{os.environ['PATH']}",
                TEST_GH_PID=str(pids), TEST_REPO=str(root),
                TEST_NVIM_CONFIG=str(SCRIPT.parent.parent),
                NVIM_LOG_FILE=str(root / "nvim.log"),
            )
            try:
                result = subprocess.run(
                    ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(script)],
                    cwd=root, env=environment, capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(pids.exists(), "The real reader/gh subprocesses did not start")
                for name, pid in json.loads(pids.read_text()).items():
                    with self.subTest(process=name), self.assertRaises(ProcessLookupError):
                        os.kill(pid, 0)
            finally:
                if pids.exists():
                    for pid in json.loads(pids.read_text()).values():
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass


if __name__ == "__main__":
    unittest.main()
