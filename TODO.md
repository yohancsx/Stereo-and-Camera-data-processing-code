# TODO — codebase reorganization

Tracks the reorg discussed in-session. See [README.md](README.md) for the
target file structure and [CHANGELOG.md](CHANGELOG.md) for what has actually
landed so far.

## Phase 0 — Documentation scaffolding
- [x] Add TODO.md, CHANGELOG.md, README.md (this)

## Phase 1 — Mechanical reorg (no behavior change)
Move files into the target structure, dedupe, drop dead code. Do every move
with `git mv` so history is preserved.

- [ ] Create `/calibration/`, `/segmentation/`, `/reconstruction3d/`, `/archive/legacy/`
- [ ] **Calibration**
  - [ ] Keep the `3D tracking hull test code/main_calibration_reconstruction.m`
        version (more complete); move to `/calibration/calibrateAndReconstruct.m`
  - [ ] Delete the root `Helpers/main_calibration_reconstruction.m` and root
        `main_calibration_reconstruction.mlx` (both superseded by the above)
  - [ ] Keep the `3D tracking hull test code/gravity_align_points.m` version
        (prompts for input instead of a hardcoded path); move to
        `/calibration/alignToGravity.m`
  - [ ] Delete the root `gravity_align_points.m`
  - [ ] Move `3D tracking hull test code/Helpers/` -> `/calibration/Helpers/`
        (keep the cleaned-up `dltReconstruct.m` from that copy)
  - [ ] Delete the root `Helpers/` (byte-identical duplicates, plus the
        superseded `dltReconstruct.m`)
- [ ] **Segmentation**
  - [ ] Move `crabROITool.m` -> `/segmentation/videoSegmentTool.m`
  - [ ] Move `colourProbe.m` -> `/segmentation/colourThresholdProbe.m`
  - [ ] Move `probeChannel.m` -> `/segmentation/probeChannel.m`
  - [ ] Move `sync_by_audio.m` -> `/segmentation/syncByAudio.m`
- [ ] **3D reconstruction**
  - [ ] Move `+vh/` -> `/reconstruction3d/+vh/` (unchanged)
  - [ ] Move `crabVisualHull.m` -> `/reconstruction3d/visualHull.m`
  - [ ] Move `stereoCrab.m` -> `/reconstruction3d/stereoPairReconstruct.m`
  - [ ] Move `crabLegAnnotator.m` -> `/reconstruction3d/landmarkAnnotator.m`
- [ ] Move `crabConfig.m` -> `/pipelineConfig.m`
- [ ] Move `3D tracking hull test code/testdata/` -> `/testdata/` (decide
      during the move whether to merge with `Test Calibration and Data/` or
      keep separate)
- [ ] **Archive** (move to `/archive/legacy/`, relocate only, no renames)
  - [ ] All 12 root `.mlx` live scripts: `CompileUnpairedPoints`,
        `DLT_quick_reconstruct`, `MakeFisheyeTransformForDLT`,
        `MatlabManualStereoCHEXCalc`, `MatlabManualStereoReconstruct`,
        `MatlabStereoParamsFromWandTracksAndIntrinsics`,
        `MatlabUndistortPoints`, `PrincipalPointUnpairedGridSearch`,
        `Single_Cam_Stereo_Image_Processing`,
        `StereoParamsFromGivenIntrinsicsAndMatchedPoints`, `VideoSlicer`,
        `main_calibration_reconstruction.mlx`
  - [ ] `absor.m`, `fisheyeUndistort_v4.m`, `makefisheye_tform.m`,
        `fishUndistWATER_func.m`
  - [ ] `DLTcameraPositionToIntrinsicsExtrinsics.m`,
        `MatlabFisheyeParamsToOcamParams.m`,
        `MatlabParamsToEasywandCamProfile.m`, `MatlabStereoParamsToDLTCoeffs.m`
  - [ ] `TestCameraProfile.txt`, `test.mat` (confirm nothing being kept
        references these before archiving)
- [ ] **Delete outright** (not archived — pure junk)
  - [ ] `*.asv` autosave files (`DLT_quick_reconstruct.asv`,
        `MatlabManualStereoReconstruct.asv`, `VideoSlicer.asv`)
  - [ ] `dlt_reconstruct_fast.m` (superseded, zero references anywhere)
  - [ ] `Helpers/undistortUVMatlab.m` (superseded, zero references anywhere)
  - [ ] `MatlabStereoParamstoOPENCVStruct.m` (unfinished stub — body is just
        `opencvStruct = [];`)
- [ ] Add `.gitignore` (`*.asv` at minimum)
- [ ] Retire `README - stereo and regular camera calib and tracking workflow.txt`
      (fold anything still accurate into the new README's Usage section,
      then delete the .txt)
- [ ] Decide storage for `Test Calibration and Data/` + `testdata/` (98MB +
      26MB, currently committed directly with no LFS) — keep as-is, move to
      Git LFS, or move out of the repo entirely

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

## Open questions (need a decision, not just work)
- [ ] Keep `/archive/legacy/` in the main repo, or split it into its own repo?
- [ ] Where should `Test Calibration and Data/` + `testdata/` actually live
      long-term?
- [ ] Final name for the repo / top-level folder (currently just the OneDrive
      folder name)?
