%% 3D Calibration & Reconstruction Workflow
% Written by Yohan Sequeira 2026
% This script walks you through preparing digitized 2D points for a DLT
% camera calibration, and then using that calibration to reconstruct 3D
% points. You do NOT need to know MATLAB or DLT to use it - just run one
% section at a time and pick files when prompted.
%
% HOW TO USE THIS FILE
%   * Run it ONE SECTION AT A TIME using the "Run Section" button, not all
%     at once - there is a manual step in the middle where you compute the
%     DLT calibration in an external program (easyWand).
%
% >>> IMPORTANT: CAMERA ORDER <<<
%   The camera order MUST be identical everywhere: in the calibration CSV,
%   in the tracked-data CSV, and in the columns of the DLT coefficient file.
%   (i.e. cam1, cam2, cam3 always mean the same physical cameras.)
%   If the orders don't match, reconstruction will silently give WRONG 3D
%   points with no error message.
%
% Overall steps:
%   1. Load fisheye undistortion parameters (from the calibrator .mat).
%   2. Undistort the calibration points  -> save a CSV.
%   3. [OUTSIDE MATLAB] compute the 11 DLT coefficients per camera, using
%      easyWand.
%   4. Load the DLT coefficients.
%   5. Load and undistort the tracked points.
%   6. Reconstruct 3D points -> save a CSV.
%   7. Optionally run gravity_align_points.m to make the scene vertical.
%
% Helper functions used (all in Helpers/):
%   loadFisheyeIntrinsics, parseXYptsLayout, undistortUV,
%   undistortPointsTable, reconstruct3D, dltReconstruct.
%
% See README.md for where this sits in the wider pipeline.

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
if isempty(thisDir), thisDir = pwd; end
addpath(thisDir, fullfile(thisDir, 'Helpers'));

%% Step 1 - Load fisheye undistortion parameters
% Pick the .mat file exported by the MATLAB (single) Camera Calibrator app.
% All cameras in this rig share the same distortion, so one file covers them
% all.
%
% To produce it: take a checkerboard of known square size, record it in
% front of the camera (through the same water and housing as the trial),
% pull frames out of that video, and calibrate them with the MATLAB Camera
% Calibrator app. Export the FISHEYE camera parameters as a .mat.
%
% Background on the fisheye model:
%   https://www.mathworks.com/help/vision/ug/fisheye-calibration-basics.html
%
% To get the frames out of the calibration video, use crabROITool.m: draw
% the ROI around the checkerboard and export the frame.

[fMat, pMat] = uigetfile({'*.mat','Camera parameters (*.mat)'}, ...
    'Select the fisheye calibration .mat file');
if isequal(fMat, 0); error('No .mat file selected - stopping.'); end

intrinsics = loadFisheyeIntrinsics(fullfile(pMat, fMat));
disp('Loaded fisheye intrinsics:');
disp(intrinsics);


%% Step 2 - Undistort the CALIBRATION points
% Pick the calibration xypts CSV (DLTdv style: ptP_camC_U / ptP_camC_V).
% This section undistorts every point and writes a new CSV you will feed to
% easyWand (together with your known wand length).
%
% Track the wand across MANY frames (30-40) spanning the volume the 3D
% motion actually takes place in - including in DEPTH, not just across the
% frame. Depth coverage is what conditions the DLT solution.

[fCal, pCal] = uigetfile({'*.csv','Calibration points (*.csv)'}, ...
    'Select the CALIBRATION xypts CSV');
if isequal(fCal, 0); error('No calibration CSV selected - stopping.'); end

Tcal   = readtable(fullfile(pCal, fCal), 'VariableNamingRule', 'preserve');
names  = Tcal.Properties.VariableNames;
Mcal   = table2array(Tcal);

[nPtsC, nCamsC] = parseXYptsLayout(names);
fprintf('Calibration file: %d points x %d cameras.\n', nPtsC, nCamsC);

McalU  = undistortPointsTable(Mcal, nPtsC, nCamsC, intrinsics);

% Save undistorted calibration points, same column names as the input.
[fSave, pSave] = uiputfile('*.csv', 'Save UNDISTORTED calibration points as', ...
    fullfile(pCal, 'Calibration_points_UNDISTORTED.csv'));
if isequal(fSave, 0); error('No save location chosen - stopping.'); end

writetable(array2table(McalU, 'VariableNames', names), fullfile(pSave, fSave));
fprintf('Saved undistorted calibration points to:\n  %s\n', fullfile(pSave, fSave));


%% ====================================================================
%  STOP HERE - do the DLT calibration in easyWand now.
%  --------------------------------------------------------------------
%  easyWand and its manual:
%     https://biomech.web.unc.edu/easywand6-manual/
%
%  easyWand needs a CAMERA PROFILE, which is separate from the fisheye
%  parameters above. One row per camera:
%
%     camNum  focalPx  imgWidth  imgHeight  ppX  ppY  1  0 0 0  0 0
%              |        |         |          |    |   |  |     |
%              |        |         |          |    |   |  |     +- 2 tangential
%              |        |         |          |    |   |  +------- 3 radial
%              |        |         |          |    |   +---------- always 1
%              |        |         |          +----+-------------- principal
%              |        |         |                                point, usually
%              |        |         |                                the image centre
%              |        +---------+------------------------------ image size, px
%              +--------------------------------------------------- focal length, px
%
%  Get focalPx either by calibrating the camera in the same MATLAB app but
%  exporting the REGULAR (non-fisheye) camera parameters and reading the
%  focal length out of the .mat, or from the value printed on the lens:
%
%     sensor height (mm) / image height (px) == focal length (mm) / focal length (px)
%
%  See docs/focal_length_conversion_1.png and _2.png for the visual version.
%
%  CHECK THE IMAGE WIDTH AND HEIGHT MATCH YOUR ACTUAL FRAME ORIENTATION.
%  Portrait footage described as landscape will silently undistort to
%  nonsense.
%
%  Feed easyWand the undistorted calibration CSV just saved, plus your wand
%  length IN MM. If the wand length is left at 1, the world comes out in
%  wand-lengths and every reconstructed distance and volume is wrong by that
%  factor. Export the DLT coefficients ("export DLT coeffs" in easyWand).
%
%  Then continue with Step 3 below.
%  ====================================================================


%% Step 3 - Load the DLT coefficients
% Pick the CSV easyWand produced (11 rows x nCams columns).

[fDlt, pDlt] = uigetfile({'*.csv','DLT coefficients (*.csv)'}, ...
    'Select the DLT coefficient CSV (11 x nCams)');
if isequal(fDlt, 0); error('No DLT coefficient file selected - stopping.'); end

c = readmatrix(fullfile(pDlt, fDlt));

if size(c,1) ~= 11
    warning(['Expected 11 rows of DLT coefficients but found %d. ', ...
        'dltReconstruct assumes the 12th coefficient = 1 when only 11 are ', ...
        'given.'], size(c,1));
end
fprintf('Loaded DLT coefficients: %d rows x %d cameras.\n', size(c,1), size(c,2));

% Sanity-check the calibration before using it. For undistorted frames the
% virtual camera has its principal point EXACTLY at the image centre and
% fx == fy exactly, so a healthy DLT reproduces that. Large departures mean
% the coefficients fit the wand points but not the geometry.
try
    P = vh.readDLT(fullfile(pDlt, fDlt));
    disp('DLT conditioning check (cx, cy should be the image centre; fy/fx = 1):');
    disp(struct2table(vh.dltIntrinsics(P)));
catch
    fprintf('(skipped the conditioning check - +vh package not on the path)\n');
end


%% Step 4 - Load and undistort the TRACKED points
% Pick the tracked xypts CSV (same DLTdv layout, same camera order).

[fTrk, pTrk] = uigetfile({'*.csv','Tracked points (*.csv)'}, ...
    'Select the TRACKED xypts CSV');
if isequal(fTrk, 0); error('No tracked CSV selected - stopping.'); end

Ttrk  = readtable(fullfile(pTrk, fTrk), 'VariableNamingRule', 'preserve');
Mtrk  = table2array(Ttrk);

[nPts, nCams] = parseXYptsLayout(Ttrk.Properties.VariableNames);
fprintf('Tracked file: %d points x %d cameras.\n', nPts, nCams);

if nCams ~= size(c,2)
    error(['Camera count mismatch: tracked data has %d cameras but the DLT ', ...
        'file has %d columns. Check camera order and files.'], nCams, size(c,2));
end

MtrkU = undistortPointsTable(Mtrk, nPts, nCams, intrinsics);


%% Step 5 - Reconstruct 3D points and save
% Loops over every frame and point. Untracked frames (or frames seen by
% fewer than 2 cameras) stay NaN so the output remains frame-aligned in time.

XYZ = reconstruct3D(MtrkU, nPts, nCams, c);

% Build wide-format column names mirroring the DLT convention: ptP_X/Y/Z.
xyzNames = cell(1, 3*nPts);
for p = 1:nPts
    xyzNames((p-1)*3 + (1:3)) = {sprintf('pt%d_X',p), sprintf('pt%d_Y',p), sprintf('pt%d_Z',p)};
end

[fXYZ, pXYZ] = uiputfile('*.csv', 'Save reconstructed 3D points as', ...
    fullfile(pTrk, 'Reconstructed_xyzpts.csv'));
if isequal(fXYZ, 0); error('No save location chosen - stopping.'); end

writetable(array2table(XYZ, 'VariableNames', xyzNames), fullfile(pXYZ, fXYZ));
fprintf('Saved reconstructed 3D points to:\n  %s\n', fullfile(pXYZ, fXYZ));


%% Step 6 - Quick sanity check (optional)
% Reports how many frames were reconstructed for each point. If a point has
% very few frames, check its digitizing / camera coverage.

for p = 1:nPts
    nGood = sum(~isnan(XYZ(:, (p-1)*3 + 1)));
    fprintf('pt%d: %d of %d frames reconstructed.\n', p, nGood, size(XYZ,1));
end


%% Step 7 - Align to gravity (optional but recommended)
% Run gravity_align_points.m on the CSV just saved. It rotates every point so
% a digitised plumb line becomes vertical. Without it, world "up" is
% arbitrary and every fall velocity or orientation needs a correction later.
