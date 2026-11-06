# Third-party notices

This repository's own work is under the BSD Zero Clause License (`LICENSE`).
The files below come from others and stay under their own licences, whose full
texts travel with them. Installing the repository copies them with their texts.

| What | Where | Licence | Full text |
|---|---|---|---|
| [Lucide](https://github.com/lucide-icons/lucide) icons, recoloured for KDE; Copyright (c) 2026 Lucide Icons and Contributors | `kde/icons/SpaceduckLines/` | ISC | `kde/icons/SpaceduckLines/LICENSE` |
| [Feather](https://github.com/feathericons/feather) icons, on which Lucide builds; Copyright (c) 2013-present Cole Bemis | `kde/icons/SpaceduckLines/` | MIT | `kde/icons/SpaceduckLines/LICENSE` |
| Wayland protocol descriptions (virtual pointer, virtual keyboard); Copyright Kristian Høgsberg, Intel, Collabora, Purism, Josef Gajdusek, for the tests only | `tests/e2e/vinput/*.xml` | MIT | at the top of each file |

`kde/icons/upstream.lock` pins the Lucide commit the icons are built from, and
`install.sh` checks them against it before installing them (`kde/icons/verify.py`).

The file manager's file icons are not in this repository. `install.sh`
fetches them from the official repository of
[Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)
(MIT; Copyright (c) 2025 Material Extensions), at the commit `kde/icons/files.lock`
pins, checks them by hash, and writes them with that licence's text under the
user's own icon directory (`kde/icons/files.py`). Many of them are the logos of
languages and tools. Those marks belong to their owners, the MIT licence does not
cover them, and no endorsement is implied.

Colour values, font glyphs named by code point and distribution marks are not
copied works here; `README.md` credits them.
