# Windows Search indexing

A common tip is "untick *Allow files on this drive to have contents indexed*" on the dev
drive. Usually it gains nothing:

- The indexer only crawls the locations listed in **Indexing Options** (by default the
  Start menu and the user profile folders under `C:\Users`). A second drive such as a Dev
  Drive is **not** indexed unless someone added it. The audit reads this scope from the
  registry and shows whether each data drive is in it.
- The checkbox doesn't stop a crawler; it sets the `NotContentIndexed` attribute on **every
  file and folder** on the drive. On a drive with millions of files (`target`,
  `node_modules`) that takes a long time, touches every file's metadata, and has to be
  repeated for new files (the attribute is inherited by new files in marked folders, but not
  reliably by tools that create files in other ways).
- If the drive *is* in the index scope, the right fix is to **remove it from the indexed
  locations** (Indexing Options > Modify, untick the folder) or add exclusions for build
  folders there - a quick, reversible setting, rather than rewriting attributes.

How to check (read-only):

```powershell
Get-Service WSearch
# Indexing Options UI:  control.exe srchadmin.dll
```

If the user relies on Start/Explorer search for their code, leave the index alone - IDEs
and `ripgrep` don't use it anyway.

When it *does* matter: the indexer re-crawling a huge, busy folder that was explicitly added
(high `SearchIndexer.exe` / `SearchProtocolHost.exe` CPU or disk during builds). Then remove
that folder from the scope. Undo: add it back in the same dialog.

macOS equivalent (Spotlight): see `mac.md`.
