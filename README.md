# Stereo & Camera 3D Tracking Toolkit

A MATLAB toolkit for multi-camera calibration, DLT-based 3D reconstruction,
video-based silhouette segmentation, visual-hull / stereo reconstruction, and
manual landmark digitizing. It was built up across several separate projects
(GoPro fisheye rigs, underwater tank calibration, crab visual-hull tracking);
this repo is being consolidated into one general-purpose pipeline.

> **Status:** mid-reorganization. See [TODO.md](TODO.md) for the plan and
> [CHANGELOG.md](CHANGELOG.md) for what has actually landed. The layout below
> is the **target** structure, not necessarily what's on disk right now.

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
    +vh/                            Visual-hull / stereo / DLT geometry package (19 fns)
    visualHull.m                    Space-carving visual hull from n silhouettes
    stereoPairReconstruct.m         Dense/feature stereo reconstruction per camera pair
    landmarkAnnotator.m             Manual two-view point digitizer with live 3D + QC

pipelineConfig.m               Central default settings for every tool above
testdata/                      Example calibration + trial data for the tools above

/archive/legacy/                Superseded and single-project (pre-consolidation)
                                code, kept for reference, not maintained

README.md, TODO.md, CHANGELOG.md
```

## Usage

*(TODO — fill in once the reorganization lands)*

## Code explanation

*(TODO — fill in once the reorganization lands: one subsection per folder
above, explaining what each tool does, its inputs/outputs, and how the
folders chain together into the full pipeline)*
