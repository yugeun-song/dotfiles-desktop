#!/usr/bin/env python3
"""kde/default-editor.py: Neovim is named for what is edited as text, and a
default anyone set stays."""

import importlib.util
import pathlib
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("default_editor", HERE.parent.parent / "kde/default-editor.py")
editor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(editor)


class Defaults(unittest.TestCase):
    def test_an_empty_file_gets_the_section(self):
        text, added = editor.with_defaults("", ["text/plain"])
        self.assertEqual(text, "[Default Applications]\ntext/plain=nvim.desktop\n")
        self.assertEqual(added, 1)

    def test_a_choice_stays(self):
        text, added = editor.with_defaults("[Default Applications]\ntext/plain=code.desktop\n", ["text/plain", "text/x-csrc"])
        self.assertIn("text/plain=code.desktop", text)
        self.assertNotIn("text/plain=nvim.desktop", text)
        self.assertIn("text/x-csrc=nvim.desktop", text)
        self.assertEqual(added, 1)

    def test_the_second_run_adds_nothing(self):
        once, _ = editor.with_defaults("", ["text/plain", "text/x-csrc"])
        again, added = editor.with_defaults(once, ["text/plain", "text/x-csrc"])
        self.assertEqual(added, 0)
        self.assertEqual(again, once)

    def test_other_sections_are_untouched(self):
        start = "[Added Associations]\ntext/plain=kate.desktop\n\n[Default Applications]\nx-scheme-handler/http=b.desktop\n\n[Removed Associations]\ntext/plain=vim.desktop\n"
        text, added = editor.with_defaults(start, ["text/x-c"])
        self.assertEqual(added, 1)
        self.assertEqual(text, start.replace("x-scheme-handler/http=b.desktop\n", "x-scheme-handler/http=b.desktop\ntext/x-c=nvim.desktop\n"))

    def test_a_name_in_another_section_is_not_a_default(self):
        text, added = editor.with_defaults("[Added Associations]\ntext/plain=kate.desktop\n", ["text/plain"])
        self.assertEqual(added, 1)
        self.assertTrue(text.endswith("[Default Applications]\ntext/plain=nvim.desktop\n"))


class Kinds(unittest.TestCase):
    def kinds(self, types):
        with tempfile.TemporaryDirectory() as tmp:
            db = pathlib.Path(tmp)
            (db / "types").write_text(types)
            return editor.edited(db)

    def test_text_but_for_those_with_their_own_programs(self):
        self.assertEqual(self.kinds("text/plain\ntext/html\ntext/calendar\ntext/vcard\ntext/x-uri\ntext/x-csrc\n"),
                         ["text/plain", "text/x-csrc"])

    def test_application_types_only_by_name(self):
        self.assertEqual(self.kinds("application/json\napplication/rtf\napplication/x-subrip\nimage/svg+xml\n"),
                         ["application/json"])

    def test_a_name_that_is_no_type_is_refused(self):
        self.assertEqual(self.kinds("text/plain\ntext/a=b\ntext/x\ny\n"), ["text/plain", "text/x"])


if __name__ == "__main__":
    unittest.main(verbosity=0)
