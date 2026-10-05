#!/usr/bin/env python3
"""Load the real WezTerm config; check its regex rules with Python's regex engine."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


DIR = Path(__file__).resolve().parent
WEZTERM = shutil.which("wezterm") or shutil.which("/Applications/WezTerm.app/Contents/MacOS/wezterm")


@unittest.skipUnless(WEZTERM, "WezTerm is required to load the hyperlink rules")
class HyperlinkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="wezterm-hyperlinks-") as temporary:
            root = Path(temporary)
            output = root / "rules.json"
            config = root / "config.lua"
            config.write_text(
                "local wezterm = require 'wezterm'\n"
                f"local config = dofile({json.dumps(str(DIR / '.wezterm.lua'))})\n"
                f"local output = assert(io.open({json.dumps(str(output))}, 'w'))\n"
                "output:write(wezterm.json_encode(config.hyperlink_rules or wezterm.default_hyperlink_rules()))\n"
                "output:close()\n"
                "return config\n"
            )
            subprocess.run(
                [WEZTERM, "--config-file", str(config), "show-keys"],
                capture_output=True, text=True, check=True,
            )
            cls.rules = json.loads(output.read_text())

    def assert_link(self, text, expected):
        position = text.index(expected)
        matches = []
        for rule in self.rules:
            for match in re.finditer(rule["regex"], text):
                start, end = match.span(rule.get("highlight", 0))
                if start <= position < end:
                    url = re.sub(r"\$(\d+)", lambda group: match[int(group[1])] or "", rule["format"])
                    matches.append((end - start, url))
        self.assertTrue(matches, f"No hyperlink in {text!r}")
        # WezTerm gives the longest highlighted match priority, even over earlier rules.
        self.assertEqual(max(matches, key=lambda match: match[0])[1], expected, text)

    def test_bracketed_links(self):
        for text in (
            "(https://example.com/path)",
            "[https://example.com/path]",
            "<https://example.com/path>",
            "[label](https://example.com/path)",
        ):
            with self.subTest(text=text):
                self.assert_link(text, "https://example.com/path")

    def test_url_contents_are_preserved(self):
        for url in (
            "https://example.com/path",
            "https://example.com/Function_(mathematics)",
            "https://example.com/search?q=a%20b&lang=en#results",
            "http://[::1]:8080/path",
            "file:///tmp/example.txt",
        ):
            for text in (url, f"({url})"):
                with self.subTest(text=text):
                    self.assert_link(text, url)

    def test_unclosed_parenthesis(self):
        self.assert_link("(https://example.com/path", "https://example.com/path")

    def test_parenthetical_sentences_preserve_url_parentheses(self):
        for url in (
            "https://example.com/Function_(mathematics)",
            "https://example.com/Function_(mathematics)/examples",
        ):
            for text in (f"({url} is useful)", f"({url}"):
                with self.subTest(text=text):
                    self.assert_link(text, url)


if __name__ == "__main__":
    unittest.main()
