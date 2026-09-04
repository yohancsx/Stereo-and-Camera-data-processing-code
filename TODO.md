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

## Phase 2 — De-branding (generalize naming, no algorithm changes) — DONE 2026-09-03
Zero occurrences of "crab" remain in any `.m` file (verified by a final
repo-wide grep). Every renamed identifier was re-checked against its
declaration and call sites the same way as Phase 1.

- [x] Renamed crab-specific identifiers to generic ones across
      `videoSegmentTool.m`, `visualHull.m`, `stereoPairReconstruct.m`
      (docstrings, printed banners, error-ID strings); renamed
      `vh.legMetrics.m` -> `vh.segmentMetrics.m` (function, docstring, and
      its 2 call sites in `landmarkAnnotator.m`)
- [x] `pipelineConfig.m`: renamed tool key `'legAnnotator'` -> `'landmarkAnnotator'`
      (the `arguments` default, the `switch` case, the `'all'` struct field,
      the local `legAnnotatorDefaults()` -> `landmarkAnnotatorDefaults()`
      helper, and `landmarkAnnotator.m`'s call into it)
- [x] `landmarkAnnotator.m`: generalized the "leg" vocabulary throughout —
      this was the largest single piece (202 occurrences across a
      1281-line interactive GUI file). Renamed the `S.legs` struct field to
      `S.parts`, 8 nested functions/handle arrays
      (`legInThisPair`->`partInThisPair`, `solveLeg`->`solvePart`,
      `legEpi`->`partEpi`, `rebuildLegGraphics`->`rebuildPartGraphics`,
      `hLegLine`/`hLegRepro`->`hPartLine`/`hPartRepro`, `lstLegs`->`lstParts`,
      `onNewLeg`/`onDeleteLeg`/`onSelectLeg`->`onNewPart`/`onDeletePart`/`onSelectPart`,
      `addLegStruct`->`addPartStruct`), every UI label/tooltip/status string,
      the output filenames (`legLandmarks.csv`->`landmarks.csv`,
      `legMetrics.csv`->`partMetrics.csv`, CSV column `'leg'`->`'part'`,
      default session file `legAnnotation.mat`->`landmarkAnnotation.mat`),
      and the docstring (including generalizing the crab-anatomy example
      "the leg meets the carapace" to "the part attaches to the body").
      **Compatibility note:** the saved-session `.mat` field also changed
      (`session.legs` -> `session.parts`). Added a migration in
      `tryLoadSession()` that reads either field name, so old session files
      - including the ones under `testdata/reconstruction3d-example/*/legAnnotation.mat`
      - still load correctly. This is the one deliberate exception to "pure
      rename": everything else in Phase 2 is text-only.
- [x] `colourThresholdProbe.m`: replaced the hardcoded
      `fileparts(codeDir)/'Test Data'/'Test Screenshots'` path with a
      prompted `uigetdir`, matching every other tool's pattern. Also
      generalized the default class list (`'crab'` -> `'subject'`) and fixed
      a dangling reference to two scripts that were never part of this repo
      (`t03_wand_detect_single.m`, `t04_crab_segment_colour.m`) to instead
      point at `videoSegmentTool.m`, which is the tool that actually plays
      that role now.
- [x] Documented the `camOrder = [4 1 3 2]` defaults as rig-specific examples,
      not requirements, in both `visualHull.m` and `stereoPairReconstruct.m`
      — both already auto-resolve pairing from data when no order is given.
      Also generalized `stereoPairReconstruct.m`'s "WHY STEREO RATHER THAN A
      HULL" docstring section to state the general principle first, with the
      4-camera/2-pair rig kept as a labeled worked example rather than
      presented as a requirement.

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
- [x] Let `landmarkAnnotator.m` take video directly instead of requiring
      pre-exported `_seg.png` frames — **done 2026-09-04, and grew into more
      than this item asked for**, see Phase 4 below
- [ ] *(Longer-term, separate effort)* Investigate scripting DLT coefficient
      computation in-house rather than depending on external easyWand

## Phase 4 — landmarkAnnotator.m video/track mode — DONE 2026-09-04
Added the ability to track named parts (and their `vh.segmentMetrics`
length/span/angles) across a continuous range of video frames, producing a
time series - not just a single instant. Confirmed design choices before
building (asked directly): every frame is digitised fresh with **no
carry-forward or auto-tracking** between frames; distance/segment tracking
stays scoped to the existing named **"part" (base->tip) only**, no new
arbitrary two-point measurement; frames are a **continuous range**
(start/end/step), not a sparse list. Full design reasoning (including why
full-frame undistortion was chosen over undistorting only the clicks) is in
the session's approved plan - ask to see it if useful context resurfaces.

- [x] Extracted `vh.undistortFrame` (fisheye/standard branch) and
      `vh.sniffCalib` (pull a calibration object out of a .mat) out of
      `+vh/loadMasks.m`'s existing inline logic, so the same undistortion
      applied to static masks/textures can also undistort a video frame
      decoded on the fly. `loadMasks.m` now calls both - pure extraction,
      same `undistortFisheyeImage`/`undistortImage` calls with the same
      arguments, no behavior change.
- [x] `landmarkAnnotator.m` video mode: supply `cfg.videoFiles` (one video
      per camera, DLT order) + `cfg.frameRange` (`[start end]` or
      `[start end step]`), or run with neither image nor video cfg set and
      pick "Video range" at the prompt. Opens one `VideoReader` per camera
      (pattern reused from `videoSegmentTool.m`), decodes+undistorts only
      the active pair's current frame on demand (not all cameras, not the
      whole range up front).
  - `S.M` holds per-camera image data regardless of source (static file or
    decoded frame) - this is what let every existing piece of undistorted-
    space geometry (`vh.epipolarLine`, the live epipolar-guide overlay,
    `backRay`, the reprojection overlay, `vh.triangulate`/`vh.project`,
    `rebuildViews`, `onSwitchPair`) keep working completely unchanged.
  - New frame-nav bar (slider + edit field + -+1/-+10 buttons), funneled
    through a single `gotoFrame(n)`, mirroring `videoSegmentTool.m`'s
    proven `gotoFrame` shape.
  - Frame transitions reuse the stash-then-reset pattern already proven
    twice in this file for camera-pair switching (`stashPair`/`restorePair`):
    navigating away from a frame archives its digitised parts into
    `S.track` (`stashFrame`), then blanks the points while keeping the same
    named parts (`resetPartsBlank`) - "blank every frame" per the confirmed
    design.
  - No silhouette mask exists in video mode, so `cropToMask` is **forced**
    off (not just defaulted - `regionprops` on the empty placeholder mask
    would error), and `showCloud`/`computeCloud`/`showBox` default off
    (user-overridable; both checkboxes still work, they just have nothing
    automatic to show). The ray-clip/axis-limit working-volume box (never
    used for triangulation, which is exact DLT regardless) falls back to
    half the active pair's camera baseline, or `cfg.objectSize/2` if set.
  - New `onExportTrack()` (a new "export track" button, video mode only):
    writes `landmarks_track.csv` (today's `landmarks.csv` columns plus a
    leading `frame` column) and `partMetrics_track.csv` (`vh.segmentMetrics`
    run once per visited frame, stacked with a `frame` column - the
    requested segment-length time series). The existing `onExport()` /
    "export csv" button is untouched, still writes today's single-instant
    format with no schema change.
  - `onSave()`/`tryLoadSession()` also persist/restore `S.track` and
    `S.frame` in video mode (guarded by `isfield`, same pattern as the
    `legs`->`parts` migration), so a long tracking session survives closing
    MATLAB and resuming later.
- [x] `pipelineConfig.m`: added `videoFiles`, `videoPattern`, `frameRange`,
      `objectSize` to `landmarkAnnotatorDefaults()`.

### Not yet verified - no MATLAB runtime in this environment
Every change was checked statically the same way Phase 1/2 were (function
names match filenames, every new/renamed identifier's call sites grepped,
structural function/end count re-checked, every new `S.*`/`edFrame`/
`slFrame` reference traced to confirm it's only reachable when
`S.videoMode` is actually true) - but the GUI itself has not been run.
**Before relying on it**, open it in MATLAB against a real video pair and
check: the frame-nav bar's layout/spacing (absolute-position UI tuned by
eye, not measured against a running figure), that `gotoFrame` stashes and
blanks correctly across a few frames, and that `onExportTrack` produces the
expected two CSVs.

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
