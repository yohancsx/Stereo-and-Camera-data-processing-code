# Changelog

Notable changes to this repo, newest first.

## 2026-09-03 (Phase 1 reorg)

### Changed
- Reorganized the repo per `TODO.md` Phase 1, entirely via `git mv` so
  history is preserved: `calibration/` (generic DLT calibration +
  reconstruction, from the `3D tracking hull test code/` rewrite),
  `segmentation/` (video -> masks: `videoSegmentTool.m` was `crabROITool.m`,
  `colourThresholdProbe.m` was `colourProbe.m`, plus `probeChannel.m` and
  `syncByAudio.m`), `reconstruction3d/` (`+vh/` package, `visualHull.m` was
  `crabVisualHull.m`, `stereoPairReconstruct.m` was `stereoCrab.m`,
  `landmarkAnnotator.m` was `crabLegAnnotator.m`), and root-level
  `pipelineConfig.m` (was `crabConfig.m`).
- Every renamed function file had its internal `function ...` declaration
  line (and the small number of real cross-file calls to it) updated to
  match — required for MATLAB to resolve the new name. Cosmetic text
  (docstrings, printed banners, error-ID strings) was left alone; that is
  Phase 2 work.
- Consolidated both example datasets under `testdata/`:
  `testdata/calibration-example/` (was `Test Calibration and Data/`) and
  `testdata/reconstruction3d-example/` (was `3D tracking hull test code/testdata/`).

### Removed
- Duplicate root `Helpers/` folder (6 files byte-identical to the copy kept
  in `calibration/Helpers/`, plus the superseded `dltReconstruct.m` and the
  orphaned `undistortUVMatlab.m`).
- Superseded root duplicates: `gravity_align_points.m`,
  `main_calibration_reconstruction.mlx`.
- Dead/unreferenced code: `dlt_reconstruct_fast.m`,
  `MatlabStereoParamstoOPENCVStruct.m` (unfinished stub).
- MATLAB autosave junk: `DLT_quick_reconstruct.asv`,
  `MatlabManualStereoReconstruct.asv`, `VideoSlicer.asv`.

### Added
- `.gitignore` (`*.asv`, `*.autosave`, `codegen/`, `slprj/`).
- `archive/legacy/`, holding the pre-consolidation Squid/Nikon-era code:
  11 `.mlx` live scripts, `absor.m`, `fisheyeUndistort_v4.m`,
  `makefisheye_tform.m`, `fishUndistWATER_func.m`, and 4 one-off camera
  parameter converters — relocated only, not modified.

### Notes
- Correction to the original Phase 1 plan: `main_calibration_reconstruction.mlx`
  was deleted, not archived — it's the live-script twin of the legacy
  `Helpers/main_calibration_reconstruction.m` that got superseded, not a
  separate Squid/Nikon notebook.
- The old `README - stereo and regular camera calib and tracking workflow.txt`
  is intentionally still in place, untouched — it's the source material for
  the still-empty README Usage section.
- Splitting the flat folder into `calibration/`/`segmentation/`/
  `reconstruction3d/`/root means a couple of calls are now cross-folder
  (`pipelineConfig.m` -> `visualHull`/`stereoPairReconstruct`;
  `landmarkAnnotator.m` -> `pipelineConfig`). Add the whole repo to the
  MATLAB path (`addpath(genpath(...))`), not just one folder. Recorded in
  `TODO.md`.

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
