# Stereo & Camera 3D Tracking Toolkit

A MATLAB toolkit for multi-camera calibration, DLT-based 3D reconstruction,
video-based silhouette segmentation, visual-hull / stereo reconstruction, and
manual landmark digitizing. It was built up across several separate projects
(GoPro fisheye rigs, underwater tank calibration, crab visual-hull tracking);
this repo is being consolidated into one general-purpose pipeline.

> **Status:** the reorg and de-branding passes described in
> [TODO.md](TODO.md) are done, and `landmarkAnnotator.m` has since gained a
> video/frame-tracking mode. See [CHANGELOG.md](CHANGELOG.md) for the full
> history. The sections below reflect what's actually on disk.

## Requirements & Quickstart

**MATLAB toolboxes required:**

| Toolbox | Used for | Where |
|---|---|---|
| Computer Vision Toolbox | fisheye/stereo calibration objects, undistortion, disparity (SGM/BM), feature matching | `calibration/Helpers/*`, `reconstruction3d/+vh/*` (`loadMasks`, `sniffCalib`, `undistortFrame`, `stereoMatch`, `rectifyPair`, `epipolarAudit`) |
| Image Processing Toolbox | ROI drawing, morphology, colour-space conversion | `segmentation/*`, `landmarkAnnotator.m`, several `+vh` helpers (`report`, `resolveSetup`, `stereoReport`) |
| Signal Processing Toolbox | `bandpass`/`xcorr` for audio-based video sync | `segmentation/syncByAudio.m` only |

Base MATLAB covers everything else. Nothing in the active pipeline needs
Statistics Toolbox — `colourThresholdProbe.m` deliberately hand-rolls its
own AUC/percentile helpers to avoid that dependency.

This code uses `arguments`-block argument validation throughout, plus
Computer Vision/Image Processing functions such as `drawassisted` and
`disparitySGM`. A reasonably recent MATLAB release (R2020a or later is a
sensible target) should have all of these; if you're on an older
installation, check that those specific functions resolve before relying on
the tools that use them.

**Quickstart**

```matlab
cd('path/to/this/repo')
addpath(genpath(pwd))     % adds every subfolder, including +vh's parent
                           % (reconstruction3d/) - do NOT addpath +vh itself,
                           % that would break the vh.functionName() calls
pipelineConfig('all')     % smoke test: should return a struct, not error
```

From there, jump to whichever stage of the pipeline you're working on — see
**Usage** below for what each stage does and which tool runs it, or **Code
explanation** for the full per-tool reference (inputs, outputs, exact file
formats).

## File structure

```
/calibration/                  Generic DLT camera calibration + 3D reconstruction
    calibrateAndReconstruct.m      Step-by-step calibration/reconstruction workflow
    alignToGravity.m               Rotate reconstructed points so "up" is vertical
    Helpers/
        loadFisheyeIntrinsics.m
        parseXYptsLayout.m
        undistortUV.m
        undistortPointsTable.m
        reconstruct3D.m
        dltReconstruct.m

/segmentation/                 Video -> per-frame silhouettes / masks
    videoSegmentTool.m             Interactive per-frame ROI + colour threshold export
    colourThresholdProbe.m         Train a colour-channel threshold recipe from screenshots
    probeChannel.m                 Shared colour-channel evaluation used by both above
    syncByAudio.m                  Frame-align multiple camera videos from their audio

/reconstruction3d/             3D geometry from calibrated, segmented views
    +vh/                            Visual-hull / stereo / DLT geometry package (22 fns)
    visualHull.m                    Space-carving visual hull from n silhouettes
    stereoPairReconstruct.m         Dense/feature stereo reconstruction per camera pair
    landmarkAnnotator.m             Manual two-view point digitizer with live 3D + QC,
                                     single instant or tracked across video frames

pipelineConfig.m               Central default settings for every tool above
testdata/                      Example calibration + trial data for the tools above

/archive/legacy/                Superseded and single-project (pre-consolidation)
                                code, kept for reference, not maintained

README.md, TODO.md, CHANGELOG.md
```

## Usage

This is the conceptual walkthrough: what each stage of a stereo/tracking
project actually is, and which tool does it. For exact inputs/outputs of any
tool named here, jump to **Code explanation** below.

### 1. Camera intrinsics (per camera, done once per calibration)

Every camera's own lens distortion (fisheye or standard) has to be
characterized before anything else makes sense. This step is **external to
this repo**: record a checkerboard of known square size through the same
water/housing the real footage goes through, pull frames out with
[`videoSegmentTool.m`](segmentation/videoSegmentTool.m) (draw an ROI around
the board and export the frame), then run those frames through MATLAB's
**Camera Calibrator app** and export the resulting `fisheyeParameters` (or
`cameraParameters`, for a non-fisheye lens) as a `.mat`. That `.mat` is the
`calibFile` almost every tool below asks for.

### 2. Camera extrinsics / DLT calibration (per rig setup)

This is what actually ties the cameras' positions/orientations together
into one shared 3D coordinate system, via Direct Linear Transformation (DLT)
coefficients.

- [`calibration/calibrateAndReconstruct.m`](calibration/calibrateAndReconstruct.m)
  Steps 1–3: undistort digitized wand-point clicks (from an external
  digitizer such as DLTdv8), then take that undistorted CSV plus your known
  wand length into the external tool **easyWand** to solve for the DLT
  coefficients (11 rows × nCams columns). This step's output CSV is what
  every reconstruction tool below calls `dltFile`.

### 3. Sync (per trial, if cameras started recording independently)

- [`segmentation/syncByAudio.m`](segmentation/syncByAudio.m) — correlates
  the audio click/onset structure across camera videos to find each
  camera's frame offset, so you can step them together in lockstep from a
  common instant onward.

### 4. Segmentation (per trial, turning video into silhouettes/textures)

- [`segmentation/colourThresholdProbe.m`](segmentation/colourThresholdProbe.m) —
  train a colour-channel + threshold "recipe" once, from a handful of
  annotated training screenshots, that separates your subject (and any
  wand/marker colours) from the background.
- [`segmentation/videoSegmentTool.m`](segmentation/videoSegmentTool.m) —
  apply a channel/threshold (from the probe above, or picked live) to a
  video interactively, frame by frame, exporting silhouette masks and
  thresholded textures. This is also how you pull single frames for camera
  calibration (stage 1) or a still image pair for landmark digitizing.

### 5. Tracking / digitizing points

Two different tools cover this, depending on what you're tracking:

- **Simple point tracking** (e.g. a single marker's trajectory): digitize
  in an external tool (DLTdv8 or similar) that produces a DLTdv-style
  `xypts` CSV, then hand that to
  [`calibration/calibrateAndReconstruct.m`](calibration/calibrateAndReconstruct.m)
  (stage 6 below) for reconstruction.
- **Named landmarks/segments with live 3D feedback** (e.g. body parts, limb
  segments, anything where you want to watch the reconstruction as you
  click and get an epipolar-consistency quality signal): use
  [`reconstruction3d/landmarkAnnotator.m`](reconstruction3d/landmarkAnnotator.m)
  directly — it digitizes AND reconstructs in one interactive session,
  either a single instant or a tracked range of video frames.

### 6. Reconstruction (turning 2D digitized data into 3D)

Which tool you want here depends on what "3D" means for your project —
these are three independent options, not sequential steps:

| You want... | Use |
|---|---|
| 3D positions of previously-digitized points (from an external digitizer) | [`calibration/calibrateAndReconstruct.m`](calibration/calibrateAndReconstruct.m) Steps 4–6 |
| The whole-body 3D shape of a subject from n silhouettes | [`reconstruction3d/visualHull.m`](reconstruction3d/visualHull.m) |
| A dense/feature-matched 3D point cloud from a stereo camera pair (better than a hull when cameras are near-collinear) | [`reconstruction3d/stereoPairReconstruct.m`](reconstruction3d/stereoPairReconstruct.m) |
| Named landmark points and the lengths/angles between them, single instant or tracked across video frames | [`reconstruction3d/landmarkAnnotator.m`](reconstruction3d/landmarkAnnotator.m) |

### 7. Post-processing

- [`calibration/alignToGravity.m`](calibration/alignToGravity.m) — rotate a
  set of reconstructed 3D points so a digitized plumb line becomes
  vertical, i.e. so world "up" is meaningful for fall velocity/orientation
  analysis. Optional, run after any of the reconstruction options above.

## Code explanation

One subsection per user-facing file, organized the same way as **File
structure** above: what it does, how to run it, its inputs (with shapes),
and its outputs (exact filenames and CSV columns).

### calibration/

#### [`calibrateAndReconstruct.m`](calibration/calibrateAndReconstruct.m)
A **script**, not a function — open it in the MATLAB Editor and run one
section at a time ("Run Section"), not all at once: there's a manual step
in the middle (easyWand, external to MATLAB). Every input is chosen via
file-picker dialogs as you step through sections; there is no `cfg` struct.

| Step | What it does | Reads | Writes |
|---|---|---|---|
| 1 | Load fisheye calibration | a `.mat` from the Camera Calibrator app | — |
| 2 | Undistort calibration points | calibration `xypts` CSV (`ptP_camC_U`/`_V` columns) | `Calibration_points_UNDISTORTED.csv` (same columns) |
| — | **STOP** — solve for DLT coefficients in **easyWand** (external) | the CSV above + your wand length (mm) | DLT coefficient CSV (11 × nCams, no header) |
| 3 | Load + sanity-check the DLT coefficients | the DLT CSV | prints a conditioning check via `vh.dltIntrinsics` (skipped silently if `+vh` isn't on the path) |
| 4 | Load + undistort tracked points | tracked `xypts` CSV, same layout/camera order as step 2 | — |
| 5 | Reconstruct 3D points | (in memory) | `Reconstructed_xyzpts.csv` (columns `pt1_X,pt1_Y,pt1_Z,pt2_X,...`) |
| 6 | Sanity check | — | console only: frames reconstructed per point |
| 7 | (pointer only) run `alignToGravity.m` on the step-5 CSV | — | — |

**Camera order must be identical** in the calibration CSV, the tracked CSV,
and the DLT coefficient columns — a mismatch reconstructs silently wrong
3D points with no error.

#### [`alignToGravity.m`](calibration/alignToGravity.m)
A script: edit the variables at the top, then run.

| Variable | Shape/type | Default |
|---|---|---|
| `inputPath` | string, path to an xyzpts CSV | `""` (prompts) |
| `upAxis` | `[x y z]` | `[0 0 1]` |
| `plumbMode` | `'manual'` \| `'frompoints'` | — |
| `plumbTopXYZ` / `plumbBottomXYZ` (manual mode) | literal `[x y z]` | `[0 0 1]` / `[0 0 0]` |
| `plumbTopPt` / `plumbBottomPt` (frompoints mode) | point-name strings matching CSV header prefixes, e.g. `'pt8'` | — |
| `plumbFrame` (frompoints mode) | row index, or `'mean'` to average over all frames where both points are visible | — |

**Reads:** a DLTdv8-style **xyzpts** CSV (`pt#_X, pt#_Y, pt#_Z` columns) —
not the xypts/pixel file; errors clearly if no `_X/_Y/_Z` columns are found.
**Writes:** same folder, `<inputName>_gravity_aligned<ext>`, identical
column layout, NaNs preserved.

#### `Helpers/` (called by `calibrateAndReconstruct.m`, not usually run directly)
| File | Signature | Role |
|---|---|---|
| `loadFisheyeIntrinsics.m` | `intrinsics = loadFisheyeIntrinsics(matPath)` | Pull a `fisheyeIntrinsics` object out of a Camera Calibrator `.mat`, whatever the variable is named |
| `parseXYptsLayout.m` | `[nPts, nCams, ptNames] = parseXYptsLayout(headerNames)` | Work out point/camera counts from `xypts` CSV column headers |
| `undistortUV.m` | `uvUndist = undistortUV(uvDist, intrinsics)` | Undistort one `[2×nCams]` `[u;v]` instant |
| `undistortPointsTable.m` | `M = undistortPointsTable(M, nPts, nCams, intrinsics)` | Undistort every point/frame in a raw `xypts` matrix at once |
| `reconstruct3D.m` | `XYZ = reconstruct3D(M, nPts, nCams, c)` | Loop `dltReconstruct` over every point/frame |
| `dltReconstruct.m` | `xyz = dltReconstruct(c, camPtsRaw)` | Single-instant DLT triangulation (adapted from Ty Hedrick's DLTdv code) |

### segmentation/

#### [`syncByAudio.m`](segmentation/syncByAudio.m)
A script with a `cfg` struct at the top.

| Field | Shape/type | Default |
|---|---|---|
| `cfg.files` | cell array of video paths | `{}` (prompts, multi-select) |
| `cfg.refCam` | scalar index into `cfg.files` | `1` |
| `cfg.window` | `[startSec endSec]`, or `[]` for whole file | `[0 60]` |
| `cfg.driftWindow` | `[startSec endSec]`, or `[]` to skip the drift check | `[]` |
| `cfg.alignAtRefFrame` | scalar frame number, or `[]` for the first common instant | `[]` |
| `cfg.bandHz` | `[loHz hiHz]` click band-pass | `[200 8000]` |
| `cfg.maxLagSec` | scalar, cross-correlation search range (s) | `10` |
| `cfg.visualCheck` | logical | `false` |

(remaining fields tune the click-detection internals — see the file's own
`cfg` block for the full list; the ones above are what you'd typically
touch.)

**Reads:** video files (`.mp4/.mov/.avi`, audio decodable via OS codecs —
extract to `.wav` with ffmpeg first if a file fails to open).
**Writes:** `params/sync.mat` (relative to the script's folder) — a `sync`
struct with, among other fields, `frameOffset` per camera (the headline
result), `clickTimes`, `corrPeak`, `ambiguityRatio`, `drift`. Also produces
3–4 diagnostic figures; no CSV output.

#### [`colourThresholdProbe.m`](segmentation/colourThresholdProbe.m)
A script with a `cfg` struct + an interactive ROI-annotation UI.

| Field | Shape/type | Default |
|---|---|---|
| `cfg.classes` | struct array: `.name`, `.tool` (`'assisted'`\|`'freehand'`\|`'polygon'`), `.isBackground` | `subject`(assisted) / `orangeBall`(polygon) / `blueBall`(polygon) / `background`(polygon, isBackground) |
| `cfg.channels` | cellstr of candidate channels to score | `{'RmG','BmG','RmB','GmR','rgRed','rgBlue','Lab_a','Lab_b'}` |
| `cfg.recommend` | `'generous'` \| `'balanced'` \| `'conservative'` | `'generous'` |
| `cfg.targetRecall` | scalar 0–1, for `'generous'` | `0.99` |
| `cfg.minBlobArea` | scalar px, full resolution | `200` |
| `cfg.excludeAboveRow` | scalar fraction 0–1, or `[]` (e.g. to kill a water-surface reflection) | `[]` |

Prompts for a folder containing `Training/` and `Validation/` subfolders of
screenshots (any of `.jpg/.jpeg/.png/.tif/.tiff/.bmp`).
**Writes:** `params/colourThresholdProbe.mat` — a `probe` struct whose
`.recipe.<className>` holds `.channel`, `.polarity`, `.threshold`, and a
ready-to-paste `.usage` string. Consumed directly by
[`videoSegmentTool.m`](segmentation/videoSegmentTool.m) and
`probeChannel.m`'s calling convention:
```matlab
S = load('params/colourThresholdProbe.mat');
r = S.probe.recipe.subject;
mask = r.polarity * probeChannel(img, r.channel) > r.threshold;
```

#### [`probeChannel.m`](segmentation/probeChannel.m)
```matlab
v = probeChannel(rgbIn, name)
```
**Inputs:** `rgbIn` — an `H×W×3` image, or an `N×3` list of RGB triplets
(any numeric type/range, auto-scaled). `name` — one of `'RmG'`, `'BmG'`,
`'RmB'`, `'GmR'`, `'rgRed'`, `'rgBlue'`, `'Lab_a'`, `'Lab_b'`, `'Lab_L'`,
`'gray'`. **Output:** `v` — `H×W` (image in) or `N×1` (list in) double.

#### [`videoSegmentTool.m`](segmentation/videoSegmentTool.m)
```matlab
videoSegmentTool            % prompts for a video file
videoSegmentTool(videoFile)
```
An interactive `uifigure` app, not `cfg`-driven — configure live via the
UI: colour channel, threshold low/high (+ Otsu auto-threshold), ROI tool
(`polygon`/`freehand`/`rectangle`), cleanup (fill holes, largest-blob-only,
min area), view mode, and frame navigation (number field, slider, ±1/±10).
Per-frame settings are only stored on "Save settings" or export — scrubbing
alone never adds a frame to the saved set.

**Reads:** one video (`.mp4/.mov/.avi/.MTS`); auto-resumes a prior session
from `<video>_roiSession.mat` beside it.
**Writes** (per exported frame, to a folder chosen on first export; `<base>`
= video filename, frame padded to 5 digits):
- `<base>_f<NNNNN>_roi.png` / `_roimask.png` — full-res RGB/mask, ROI only
- `<base>_f<NNNNN>_seg.png` — full-res RGB, ROI **and** threshold applied —
  the `*_seg.png` texture input consumed by `stereoPairReconstruct.m` and
  `landmarkAnnotator.m`
- `<base>_f<NNNNN>_mask.png` — full-res binary silhouette — the `*_mask.png`
  input consumed by `visualHull.m`, `stereoPairReconstruct.m`, and
  `landmarkAnnotator.m`
- `<base>_f<NNNNN>_params.mat` — the exact channel/threshold/ROI used
- `<video>_roiSession.mat` — resumable session state

### reconstruction3d/

#### [`visualHull.m`](reconstruction3d/visualHull.m)
```matlab
out = visualHull              % prompts for masks/DLT/calibration
out = visualHull(cfg)
cfg = visualHull('defaults')
```
| Field | Shape/type | Default |
|---|---|---|
| `cfg.maskFiles` | cell array, nCams silhouette paths | `{}` (prompts) |
| `cfg.dltFile` | path, 11×nCams DLT csv | `''` (prompts) |
| `cfg.calibFiles` | cell array (nCams or 1 shared), or `'none'` | `{}` (prompts) |
| `cfg.camOrder` | permutation mapping DLT columns → mask files, or `[]` to auto-resolve | `[4 1 3 2]` (a worked example for one specific rig — leave `[]` for a new one) |
| `cfg.yOrigin` | `'auto'` \| `'bottom'` \| `'top'` | `'auto'` |
| `cfg.objectSize` | scalar world units, or `[]` to estimate from silhouettes | `[]` |
| `cfg.coarseN` / `cfg.fineN` | scalar grid resolution, coarse/fine carving pass | `64` / `200` |
| `cfg.minCams` | occupancy threshold, or `[]` = all cameras | `[]` |

**Reads:** nCams mask images (any of `.png/.tif/.tiff/.bmp/.jpg`) + a DLT
csv + camera-calibration `.mat`(s).
**Writes** (to `cfg.outDir`, default `<maskDir>/hull`):
`hull_<yyyymmdd_HHMMSS>.mat` (the full result struct, `-v7.3`) and
`hull_<yyyymmdd_HHMMSS>.stl` (mesh export). No CSV output; prints extensive
diagnostics (rig geometry, DLT conditioning) and produces validation
figures.

#### [`stereoPairReconstruct.m`](reconstruction3d/stereoPairReconstruct.m)
```matlab
out = stereoPairReconstruct           % prompts for a data folder
out = stereoPairReconstruct(cfg)
cfg = stereoPairReconstruct('defaults')
```
| Field | Shape/type | Default |
|---|---|---|
| `cfg.dataDir` | path holding `*_mask.png`/`*_seg.png`/DLT csv/calib `.mat` | `''` (prompts) |
| `cfg.camOrder` | permutation, DLT columns → mask files | `[4 1 3 2]` (worked-example rig) |
| `cfg.pairs` | `Qx2` DLT-column pairs, or `[]` = auto-pick the closest nCams/2 pairs | `[]` |
| `cfg.methods` | subset of `{'sgm','bm','features'}` | all three |
| `cfg.rectifyFromData` | logical — re-rectify on image-fitted epipolar geometry if the DLT's own geometry looks wrong | `true` |

**Reads:** `*_mask.png` + `*_seg.png` (nCams each) + a DLT csv + a
calibration `.mat` from `cfg.dataDir`.
**Writes** (to `cfg.outDir`, default `<maskDir>/stereo`):
`stereo_<yyyyMMdd_HHmmss>.mat` (slim result struct, `-v7.3`). No CSV
output; produces rectification/disparity/point-cloud validation figures via
`vh.stereoReport`.

#### [`landmarkAnnotator.m`](reconstruction3d/landmarkAnnotator.m)
```matlab
landmarkAnnotator                % prompts (image pair or video range)
landmarkAnnotator(cfg)
landmarkAnnotator('defaults')    % disp()'s the default cfg
landmarkAnnotator('myRun.mat')   % loads a saved cfg struct
```
Defaults come from `pipelineConfig('landmarkAnnotator')`. Two input modes:

**Single-instant mode** (default) — digitize one image pair per camera:
| Field | Shape/type | Default |
|---|---|---|
| `cfg.dataDir` | path | `''` (prompts) |
| `cfg.maskPattern` / `cfg.imagePattern` | glob patterns | `'*_mask.png'` / `'*_seg.png'` (`'*_roi.png'` for un-thresholded frames) |
| `cfg.pair` | `[a b]` starting DLT camera pair | `[2 4]` |
| `cfg.carryAcrossPairs` | logical — reproject landmarks when you switch camera pairs | `true` |

**Video mode** — track across a range of frames instead:
| Field | Shape/type | Default |
|---|---|---|
| `cfg.videoFiles` | cell array, nCams video paths in DLT camera order — **presence of this field is what triggers video mode** | `{}` |
| `cfg.frameRange` | `[startFrame endFrame]` or `[start end step]`; `[]` prompts | `[]` |
| `cfg.objectSize` | scalar world units; `[]` falls back to half the active pair's camera baseline (no mask to measure from) | `[]` |

If neither an image nor a video input is configured, you get a prompt to
choose. In video mode, `cropToMask` is forced off (no mask exists) and
`showCloud`/`computeCloud`/`showBox` default off (nothing to auto-seed them
from) — all still user-overridable via cfg or the on-screen checkboxes.

**Every frame in video mode is digitized fresh** — there is no
carry-forward or auto-tracking between frames by design. Navigating to a
different frame (slider, ±1/±10, or typing a number) archives whatever you
digitized on the frame you're leaving, then clears the points for the new
one, keeping the same part names throughout.

**Reads:** single-instant — `*_mask.png`/`*_seg.png` pairs; video mode —
video files, no masks. Either mode also needs a DLT csv + calibration
`.mat`, and optionally a prior `visualHull.m`/`stereoPairReconstruct.m`
`.mat` for 3D dense-cloud context.
**Writes:**
- Session (either mode): `<dataDir>/landmarkAnnotation.mat` — resumable;
  video mode also persists the per-frame track archive.
- **"export csv"** (single-instant): `landmarks.csv` (columns `part, point,
  X, Y, Z, residPx, epiPx, uA, vA, uB, vB`) and `partMetrics.csv` (columns
  `part, nPts, length, span, straight, elevation, azimuth, angleToAxis,
  baseAlong, baseRadial`, via `vh.segmentMetrics`).
- **"export track"** (video mode only): `landmarks_track.csv` and
  `partMetrics_track.csv` — the same columns as above, each with a leading
  `frame` column, one row per frame you visited (this is the segment-length
  time series).

#### `+vh/` package
The shared geometry/vision library behind all three tools above — not
usually called directly, except for these:

| Function | Signature | Role |
|---|---|---|
| `vh.readDLT` | `[P, L, C] = vh.readDLT(csvPath)` | Read an 11×nCams DLT csv into `3×4×nCams` projection matrices |
| `vh.loadMasks` | `M = vh.loadMasks(maskFiles, calibFiles, opts)` | Read + undistort masks/textures for the hull/stereo tools |
| `vh.dltIntrinsics` | `T = vh.dltIntrinsics(P)` | Decompose a DLT back into `fx,fy,cx,cy` — the conditioning check used in `calibrateAndReconstruct.m` step 3 |
| `vh.segmentMetrics` | `[T, frame] = vh.segmentMetrics(parts)` | Body-frame length/span/angle metrics from a `landmarkAnnotator` parts struct |

The rest are internal helpers consumed by `visualHull.m`,
`stereoPairReconstruct.m`, and `landmarkAnnotator.m`: `buildMesh`, `carve`
(space carving), `epipolarAudit`, `epipolarLine`, `fundamentalFromDLT`,
`imageToDLT`, `objectScale`, `project`, `reconstructMatches`, `rectifyPair`,
`report`, `resolveSetup`, `sniffCalib` (pull a calibration object out of a
`.mat` regardless of variable name), `stereoMatch`, `stereoReport`,
`triangulate`/`triangulateMany`, `undistortFrame` (undistort one image with
a fisheye or standard calibration — shared by `loadMasks` and
`landmarkAnnotator`'s video mode).

### pipelineConfig.m (root)
```matlab
cfg = pipelineConfig(tool, outFile)
% tool: 'landmarkAnnotator' | 'visualHull' | 'stereo' | 'sync' | 'all'
```
Returns the default `cfg` struct for a named tool. All four tools accept
either a `cfg` struct or a path to one saved as a `.mat`, so the intended
workflow is:
```matlab
pipelineConfig('landmarkAnnotator', 'myRun.mat');
load myRun.mat                  % gives you `cfg`
cfg.dataDir = "...\my frame";
landmarkAnnotator(cfg)
```
`tool = 'all'` returns a struct with all four as sub-fields. Passing
`outFile` also prints the handful of fields most people actually edit for
that tool.

---

### A few notes on the example data in `testdata/`

- `testdata/calibration-example/grav_Aligned_Point.csv` is shaped like an
  `xypts` file (`pt1_cam1_U,...`), not the `xyzpts` shape
  `alignToGravity.m` actually outputs — despite the name, don't treat it as
  an example of that tool's output.
  `STEP5_FINISHED_Reconstructed_xyzpts_gravity_aligned.csv` in the same
  folder is the real one (correct `xyzpts` shape).
- `testdata/reconstruction3d-example/crabFrame_f03924/legLandmarks.csv` and
  `legMetrics.csv` use the column name `leg` where the current
  `landmarkAnnotator.m` writes `part` — this is legacy example data
  predating the tool's generalization (see `CHANGELOG.md`), not a bug in
  today's exporter.
