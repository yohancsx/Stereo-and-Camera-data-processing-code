# Changelog

Notable changes to this repo, newest first.

## 2026-09-04 (Phase 4: video/track mode)

### Added
- `landmarkAnnotator.m` can now track a part across a continuous range of
  video frames instead of only digitising a single instant. Supply
  `cfg.videoFiles` + `cfg.frameRange`, or run with neither image nor video
  cfg set to get a "single image / video range" prompt. New frame-nav bar
  (slider, edit field, -+1/-+10 buttons) funneled through `gotoFrame(n)`.
  Every frame is digitised fresh - no carry-forward or auto-tracking
  between frames, and no new arbitrary two-point distance type - confirmed
  directly rather than assumed; segment tracking stays scoped to the
  existing named "part" (base->tip) via `vh.segmentMetrics`.
- New "export track" button / `onExportTrack()`: writes
  `landmarks_track.csv` and `partMetrics_track.csv` (both long-format, one
  row per frame) across every frame visited. The existing "export csv" /
  `onExport()` is unchanged - still single-instant, no schema change.
- `vh.undistortFrame.m` and `vh.sniffCalib.m` - extracted from
  `+vh/loadMasks.m`'s existing inline logic (same calls, same arguments, no
  behavior change) so the same undistortion applied to static masks/textures
  can also undistort a video frame decoded on the fly.
- `pipelineConfig.m`: `videoFiles`, `videoPattern`, `frameRange`,
  `objectSize` defaults for `landmarkAnnotator`.

### Notes
- No silhouette mask exists in video mode: `cropToMask` is forced off
  (not just defaulted - the alternative would error on the empty
  placeholder mask), `showCloud`/`computeCloud`/`showBox` default off but
  stay user-overridable, and the ray-clip/axis-limit working-volume box
  (never used for triangulation itself) falls back to half the active
  pair's camera baseline, or `cfg.objectSize/2` if set.
- `onSave()`/`tryLoadSession()` persist/restore the per-frame track archive
  too, so a long tracking session survives closing and reopening MATLAB.
- **Not yet run in MATLAB** (no runtime available in this environment) -
  verified statically only (call sites, structural function/end counts,
  every video-only state reference traced to confirm it's unreachable
  outside video mode). Test against a real video pair before relying on it,
  particularly the frame-nav bar's absolute-position layout, which was
  never checked against a running figure.

## 2026-09-03 (Phase 2 de-branding)

### Changed
- Generalized every remaining "crab"-specific identifier, string, and
  comment across `pipelineConfig.m`, `visualHull.m`,
  `stereoPairReconstruct.m`, `landmarkAnnotator.m`, `videoSegmentTool.m`,
  `colourThresholdProbe.m`, `probeChannel.m`, `syncByAudio.m`, and
  `+vh/carve.m`. A final repo-wide grep confirms zero remaining "crab"
  occurrences in any `.m` file.
- `+vh/legMetrics.m` -> `+vh/segmentMetrics.m` (function, docstring, and its
  crab-anatomy example generalized to a general articulated-body note).
- `pipelineConfig.m`'s tool key `'legAnnotator'` -> `'landmarkAnnotator'`,
  including the local `legAnnotatorDefaults()` helper.
- `landmarkAnnotator.m`'s internal "leg" vocabulary generalized to "part" -
  the struct field `S.legs` -> `S.parts`, 8 nested functions/handle arrays,
  every UI label and status string, and the output filenames
  (`legLandmarks.csv` -> `landmarks.csv`, `legMetrics.csv` ->
  `partMetrics.csv`, default session file `legAnnotation.mat` ->
  `landmarkAnnotation.mat`). 202 occurrences across this 1281-line file,
  renamed in dependency order (longest/most-specific identifiers first) and
  verified by grep after each batch.
- `colourThresholdProbe.m` no longer hardcodes a `Test Data/Test Screenshots`
  path outside the repo - it now prompts with `uigetdir`, matching every
  other tool. Default class list `'crab'` -> `'subject'`. Fixed a dangling
  reference to two scripts that never existed in this repo
  (`t03_wand_detect_single.m`, `t04_crab_segment_colour.m`), pointing
  instead at `videoSegmentTool.m`.
- `camOrder = [4 1 3 2]` defaults in `visualHull.m` and
  `stereoPairReconstruct.m` documented as rig-specific examples, not
  requirements - both already auto-resolve pairing from data when left `[]`.
  `stereoPairReconstruct.m`'s docstring now states the general
  hull-vs-stereo principle before the 4-camera/2-pair worked example.

### Compatibility note
- The saved-session `.mat` format changed (`session.legs` -> `session.parts`
  field). `landmarkAnnotator.m`'s `tryLoadSession()` reads either field name,
  so existing session files - including
  `testdata/reconstruction3d-example/*/legAnnotation.mat` - still load. This
  was the one deliberate exception to a text-only pass: everything else in
  Phase 2 changed no behavior.

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
