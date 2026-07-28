# Changelog

All notable changes to WinMole are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-28

First tagged release.

### Changed

- **License is now GPL-3.0, previously stated as MIT.** WinMole is a derivative
  work of [Mole](https://github.com/tw93/Mole), which is GPL-3.0 licensed, so
  WinMole must carry the same license. See [LICENSE](LICENSE) and the Credits
  section of the README.

### Fixed

- `clean` no longer fails on most of its flags. Six calls in `bin/clean.ps1`
  named functions that do not exist or passed parameters that were never
  declared, which broke `-Browsers`, `-Apps`, `-Dev`, `-System`,
  `-WindowsUpdate` and `-All`. (#14, via #11 and #12)
- The Recycle Bin is actually emptied now. `Clear-RecycleBin` shadowed the
  built-in cmdlet of the same name and called itself instead, recursing
  thousands of levels deep and reporting success without deleting anything.
  The call is now module-qualified. (#17)
- `clean -System` and `clean -All` no longer abort partway through on machines
  where the `wuauserv` service is unavailable. A property was read from a
  possibly-null service object outside any `try`, which terminated the run
  under StrictMode after earlier deletions had already been committed. (#19)
- `Get-InstalledPrograms` no longer throws on registry entries that have no
  `DisplayName`. (#11)

### Added

- `Clear-UserCaches`, so `clean -User` works. (#12)
- A Pester regression test for `Get-InstalledPrograms` under StrictMode. (#11)

### Known issues

- `analyze` under-reports directory sizes and omits some directories. A fix is
  open in #15 and will ship in the next release. (#13)
- Progress bars in `purge` and `uninstall` are stuck at 0%, because a helper in
  `lib/core/log.ps1` shadows the built-in `Write-Progress` with an incompatible
  signature. (#18)

[0.1.0]: https://github.com/bhadraagada/winmole/releases/tag/v0.1.0
