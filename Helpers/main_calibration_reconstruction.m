%% 3D Calibration & Reconstruction Workflow
% Written by Yohan Sequeira 2026
% This script walks you through preparing digitized 2D points for a DLT
% camera calibration, and then using that calibration to reconstruct 3D
% points. You do NOT need to know MATLAB or DLT to use it — just run one
% section at a time and pick files when prompted.
%
% HOW TO USE THIS FILE
%   * Run it ONE SECTION AT A TIME using the "Run Section" button, not all
%     at once — there is a manual step in the middle where you compute the
%     DLT calibration in an external program.
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
%   3. [OUTSIDE MATLAB] compute the 11 DLT coefficients per camera.
%   4. Load the DLT coefficients.
%   5. Load and undistort the tracked points.
%   6. Reconstruct 3D points -> save a CSV.
%
% Helper functions used (keep them in the same folder as this script):
%   loadFisheyeIntrinsics, parseXYptsLayout, undistortUV,
%   undistortPointsTable, reconstruct3D, dltReconstruct.

clear; clc;

cd(fileparts(matlab.desktop.editor.getActiveFilename));
addpath("Helpers\")

%% Step 1 — Load fisheye undistortion parameters
% Pick the .mat file exported by the MATLAB (single) Camera Calibrator app.
% All cameras in this rig share the same distortion, so one file covers them
% all.

[fMat, pMat] = uigetfile({'*.mat','Camera parameters (*.mat)'}, ...
    'Select the fisheye calibration .mat file');
if isequal(fMat, 0); error('No .mat file selected — stopping.'); end

intrinsics = loadFisheyeIntrinsics(fullfile(pMat, fMat));
disp('Loaded fisheye intrinsics:');
disp(intrinsics);


%% Step 2 — Undistort the CALIBRATION points
% Pick the calibration xypts CSV (DLTdv style: ptP_camC_U / ptP_camC_V).
% This section undistorts every point and writes a new CSV you will feed to
% your external DLT program (together with your known wand lengths / world
% coordinates).

[fCal, pCal] = uigetfile({'*.csv','Calibration points (*.csv)'}, ...
    'Select the CALIBRATION xypts CSV');
if isequal(fCal, 0); error('No calibration CSV selected — stopping.'); end

Tcal   = readtable(fullfile(pCal, fCal), 'VariableNamingRule', 'preserve');
names  = Tcal.Properties.VariableNames;
Mcal   = table2array(Tcal);

[nPtsC, nCamsC] = parseXYptsLayout(names);
fprintf('Calibration file: %d points x %d cameras.\n', nPtsC, nCamsC);

McalU  = undistortPointsTable(Mcal, nPtsC, nCamsC, intrinsics);

% Save undistorted calibration points, same column names as the input.
[fSave, pSave] = uiputfile('*.csv', 'Save UNDISTORTED calibration points as', ...
    fullfile(pCal, 'Calibration_points_UNDISTORTED.csv'));
if isequal(fSave, 0); error('No save location chosen — stopping.'); end

writetable(array2table(McalU, 'VariableNames', names), fullfile(pSave, fSave));
fprintf('Saved undistorted calibration points to:\n  %s\n', fullfile(pSave, fSave));


%% ====================================================================
%  STOP HERE — do the DLT calibration in your external program now.
%  --------------------------------------------------------------------
%  Use the undistorted calibration CSV just saved, plus your known wand
%  lengths / world coordinates, to compute the 11 DLT coefficients per
%  camera. Save the result as a CSV with 11 rows and nCams columns
%  (one column per camera, in the SAME camera order as above).
%  Then continue with Step 3 below.
%  ====================================================================


%% Step 3 — Load the DLT coefficients
% Pick the CSV your external tool produced (11 rows x nCams columns).

[fDlt, pDlt] = uigetfile({'*.csv','DLT coefficients (*.csv)'}, ...
    'Select the DLT coefficient CSV (11 x nCams)');
if isequal(fDlt, 0); error('No DLT coefficient file selected — stopping.'); end

c = readmatrix(fullfile(pDlt, fDlt));

if size(c,1) ~= 11
    warning(['Expected 11 rows of DLT coefficients but found %d. ', ...
        'dltReconstruct assumes the 12th coefficient = 1 when only 11 are ', ...
        'given.'], size(c,1));
end
fprintf('Loaded DLT coefficients: %d rows x %d cameras.\n', size(c,1), size(c,2));


%% Step 4 — Load and undistort the TRACKED points
% Pick the tracked xypts CSV (same DLTdv layout, same camera order).

[fTrk, pTrk] = uigetfile({'*.csv','Tracked points (*.csv)'}, ...
    'Select the TRACKED xypts CSV');
if isequal(fTrk, 0); error('No tracked CSV selected — stopping.'); end

Ttrk  = readtable(fullfile(pTrk, fTrk), 'VariableNamingRule', 'preserve');
Mtrk  = table2array(Ttrk);

[nPts, nCams] = parseXYptsLayout(Ttrk.Properties.VariableNames);
fprintf('Tracked file: %d points x %d cameras.\n', nPts, nCams);

if nCams ~= size(c,2)
    error(['Camera count mismatch: tracked data has %d cameras but the DLT ', ...
        'file has %d columns. Check camera order and files.'], nCams, size(c,2));
end

MtrkU = undistortPointsTable(Mtrk, nPts, nCams, intrinsics);


%% Step 5 — Reconstruct 3D points and save
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
if isequal(fXYZ, 0); error('No save location chosen — stopping.'); end

writetable(array2table(XYZ, 'VariableNames', xyzNames), fullfile(pXYZ, fXYZ));
fprintf('Saved reconstructed 3D points to:\n  %s\n', fullfile(pXYZ, fXYZ));


%% Step 6 — Quick sanity check (optional)
% Reports how many frames were reconstructed for each point. If a point has
% very few frames, check its digitizing / camera coverage.

for p = 1:nPts
    nGood = sum(~isnan(XYZ(:, (p-1)*3 + 1)));
    fprintf('pt%d: %d of %d frames reconstructed.\n', p, nGood, size(XYZ,1));
end
