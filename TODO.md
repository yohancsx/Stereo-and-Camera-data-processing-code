# TODO — codebase reorganization

Tracks the reorg discussed in-session. See [README.md](README.md) for the
target file structure and [CHANGELOG.md](CHANGELOG.md) for what has actually
landed so far.

## Phase 0 — Documentation scaffolding
- [x] Add TODO.md, CHANGELOG.md, README.md (this)

## Phase 1 — Mechanical reorg (no behavior change) — DONE 2026-09-03
Moved files into the target structure with `git mv` (history preserved),
deduped, dropped dead code. Every rename that touched a `function` file also
got its internal `function ...` line (and any real callers) updated to match
— required for MATLAB to resolve the new name — but cosmetic text
(docstrings, printed banners, error-ID strings, "leg" vocabulary) was left
alone on purpose; that is Phase 2.

- [x] Create `/calibration/`, `/segmentation/`, `/reconstruction3d/`, `/archive/legacy/`
- [x] **Calibration**
  - [x] Kept the `3D tracking hull test code/main_calibration_reconstruction.m`
        version (more complete); moved to `/calibration/calibrateAndReconstruct.m`
        (also fixed 2 stale filename comments inside it: crabROITool.m ->
        videoSegmentTool.m, gravity_align_points.m -> alignToGravity.m)
  - [x] Deleted the root `Helpers/main_calibration_reconstruction.m` and root
        `main_calibration_reconstruction.mlx` (both superseded by the above)
  - [x] Kept the `3D tracking hull test code/gravity_align_points.m` version
        (prompts for input instead of a hardcoded path); moved to
        `/calibration/alignToGravity.m`
  - [x] Deleted the root `gravity_align_points.m`
  - [x] Moved `3D tracking hull test code/Helpers/` -> `/calibration/Helpers/`
        (kept the cleaned-up `dltReconstruct.m` from that copy)
  - [x] Deleted the root `Helpers/` (byte-identical duplicates, plus the
        superseded `dltReconstruct.m` and `undistortUVMatlab.m`)
- [x] **Segmentation**
  - [x] Moved `crabROITool.m` -> `/segmentation/videoSegmentTool.m`
        (renamed the `function crabROITool(...)` line to match)
  - [x] Moved `colourProbe.m` -> `/segmentation/colourThresholdProbe.m`
  - [x] Moved `probeChannel.m` -> `/segmentation/probeChannel.m`
  - [x] Moved `sync_by_audio.m` -> `/segmentation/syncByAudio.m`
- [x] **3D reconstruction**
  - [x] Moved `+vh/` -> `/reconstruction3d/+vh/` (untouched, 19 files)
  - [x] Moved `crabVisualHull.m` -> `/reconstruction3d/visualHull.m`
        (renamed the `function` line; updated `pipelineConfig.m`'s call to it)
  - [x] Moved `stereoCrab.m` -> `/reconstruction3d/stereoPairReconstruct.m`
        (renamed the `function` line; updated `pipelineConfig.m`'s call to it)
  - [x] Moved `crabLegAnnotator.m` -> `/reconstruction3d/landmarkAnnotator.m`
        (renamed the `function` line and its call into `crabConfig`/`pipelineConfig`)
- [x] Moved `crabConfig.m` -> `/pipelineConfig.m` (renamed the `function` line)
- [x] Moved both test datasets under one `/testdata/`:
      `Test Calibration and Data/` -> `testdata/calibration-example/`,
      `3D tracking hull test code/testdata/` -> `testdata/reconstruction3d-example/`
      (this is the "decide during the move" call from the original plan —
      revisit under Open Questions below if a different split is wanted)
- [x] **Archive** (moved to `/archive/legacy/`, relocated only, no renames)
  - [x] 11 of the 12 root `.mlx` live scripts: `CompileUnpairedPoints`,
        `DLT_quick_reconstruct`, `MakeFisheyeTransformForDLT`,
        `MatlabManualStereoCHEXCalc`, `MatlabManualStereoReconstruct`,
        `MatlabStereoParamsFromWandTracksAndIntrinsics`,
        `MatlabUndistortPoints`, `PrincipalPointUnpairedGridSearch`,
        `Single_Cam_Stereo_Image_Processing`,
        `StereoParamsFromGivenIntrinsicsAndMatchedPoints`, `VideoSlicer`.
        **Correction from the original plan:** `main_calibration_reconstruction.mlx`
        was NOT archived with the rest — it's the live-script twin of the
        legacy `Helpers/main_calibration_reconstruction.m`, not a separate
        Squid/Nikon-era notebook, so it was deleted alongside that file instead
        (see Calibration section above).
  - [x] `absor.m`, `fisheyeUndistort_v4.m`, `makefisheye_tform.m`,
        `fishUndistWATER_func.m`
  - [x] `DLTcameraPositionToIntrinsicsExtrinsics.m`,
        `MatlabFisheyeParamsToOcamParams.m`,
        `MatlabParamsToEasywandCamProfile.m`, `MatlabStereoParamsToDLTCoeffs.m`
  - [x] `TestCameraProfile.txt`, `test.mat` — re-grepped the whole repo
        immediately before archiving; confirmed zero references from anything
        kept
- [x] **Delete outright** (not archived — pure junk)
  - [x] `*.asv` autosave files (`DLT_quick_reconstruct.asv`,
        `MatlabManualStereoReconstruct.asv`, `VideoSlicer.asv`)
  - [x] `dlt_reconstruct_fast.m` (superseded, zero references anywhere)
  - [x] `Helpers/undistortUVMatlab.m` (superseded, zero references anywhere)
  - [x] `MatlabStereoParamstoOPENCVStruct.m` (unfinished stub — body was just
        `opencvStruct = [];`)
- [x] Added `.gitignore` (`*.asv`, `*.autosave`, `codegen/`, `slprj/`)
- [ ] Retire `README - stereo and regular camera calib and tracking workflow.txt`
      (fold anything still accurate into the new README's Usage section,
      then delete the .txt) — **deliberately left untouched**: its content is
      the raw material for the still-empty Usage section, so deleting it now
      would lose that source
- [ ] Decide storage for `testdata/` (98MB + 26MB, currently committed
      directly with no LFS) — keep as-is, move to Git LFS, or move out of the
      repo entirely — still open, see Open Questions

## Phase 2 — De-branding (generalize naming, no algorithm changes)
- [ ] Rename crab-specific identifiers to generic ones across
      `videoSegmentTool.m`, `visualHull.m`, `stereoPairReconstruct.m`,
      `landmarkAnnotator.m`; rename `vh.legMetrics.m` -> `vh.segmentMetrics.m`
- [ ] `pipelineConfig.m`: rename tool key `'legAnnotator'` -> `'landmarkAnnotator'`
- [ ] `landmarkAnnotator.m`: generalize "leg" vocabulary in struct fields and
      docstring to "part"/"landmark"; parameterize the `legLandmarks.csv`
      output filename instead of hardcoding it
- [ ] `colourThresholdProbe.m`: replace the hardcoded
      `fileparts(codeDir)/'Test Data'/'Test Screenshots'` path with a
      prompted/config path, matching every other tool
- [ ] Document the `camOrder = [4 1 3 2]` defaults as rig-specific examples,
      not requirements — both `visualHull` and `stereoPairReconstruct`
      already auto-resolve pairing from data when no order is given

## Phase 3 — Video-as-input streamlining
Ranked easiest/highest-value first.
- [ ] Batch/headless mask export: apply a saved `colourThresholdProbe`
      recipe across every frame of a video unattended, without the
      interactive GUI (extend `videoSegmentTool.m`)
- [ ] Script intrinsics calibration from video directly
      (`detectCheckerboardPoints` + `estimateFisheyeParameters`), removing
      the manual "export frames, open the Camera Calibrator app" step
- [ ] Auto-digitize the calibration wand from video via colour thresholding
      (reuse `probeChannel` + centroid detection, same idea already used for
      silhouette centroids in `stereoPairReconstruct`), removing manual
      wand-point clicking in an external digitizer
- [ ] Let `landmarkAnnotator.m` take `(videoFile, frameNumber)` directly
      instead of requiring pre-exported `_seg.png` frames
- [ ] *(Longer-term, separate effort)* Investigate scripting DLT coefficient
      computation in-house rather than depending on external easyWand

## Known consideration from Phase 1: MATLAB path
Splitting the old single flat folder into `calibration/`, `segmentation/`,
`reconstruction3d/`, and a root-level `pipelineConfig.m` means these no
longer sit next to each other on disk. `pipelineConfig.m` calls
`visualHull('defaults')` / `stereoPairReconstruct('defaults')`
(in `reconstruction3d/`), and `landmarkAnnotator.m` (in `reconstruction3d/`)
calls `pipelineConfig(...)` (at repo root) — both cross-folder. Add the whole
repo to the MATLAB path (`addpath(genpath(repoRoot))`) rather than just one
folder, or these calls won't resolve. `+vh` is a package folder, so
`genpath` adding `reconstruction3d/` (its parent) is correct — do not add
`reconstruction3d/+vh` itself to the path. Worth a line in the README Usage
section once that gets written.

## Open questions (need a decision, not just work)
- [ ] Keep `/archive/legacy/` in the main repo, or split it into its own repo?
- [ ] Where should `testdata/calibration-example/` + `testdata/reconstruction3d-example/`
      actually live long-term? (provisionally merged under one `/testdata/`
      in Phase 1 — revisit if a different split is wanted)
- [ ] Final name for the repo / top-level folder (currently just the OneDrive
      folder name)?
