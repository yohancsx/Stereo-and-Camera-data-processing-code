# Changelog

Notable changes to this repo, newest first.

## 2026-09-03

### Added
- `README.md`, `TODO.md`, `CHANGELOG.md` — documented the target file
  structure and the reorganization plan (see `TODO.md`) before starting the
  actual code moves.

### Notes
- Full inventory taken this session: identified two generations of the same
  calibration/reconstruction pipeline (root-level legacy scripts vs. the
  `3D tracking hull test code/` rewrite), a duplicated `Helpers/` folder,
  several dead/superseded functions (`dlt_reconstruct_fast.m`,
  `Helpers/undistortUVMatlab.m`, `MatlabStereoParamstoOPENCVStruct.m`, and
  more — see `TODO.md` Phase 1), and ~130MB of committed test data with no
  `.gitignore`. No source files moved yet.
