%% gravity_align_points.m
% =========================================================================
% Written by Yohan Sequeira 2026
% Align a set of digitized 3D points to vertical using a plumb line.
%
% A plumb line hangs along the local gravity direction, so the vector from
% its TOP marker to its BOTTOM marker points in the direction of gravity.
% This script:
%   1. Reads a DLTdv8 "xyzpts" style CSV (columns pt1_X, pt1_Y, pt1_Z, ...).
%   2. Builds the gravity (down) direction from two plumb-line points.
%   3. Builds a rotation matrix R that rotates that direction onto the
%      chosen world "up" axis (default +Z), i.e. makes the scene vertical.
%   4. Applies R to every point and writes the result back out in the
%      identical CSV format, with "_gravity_aligned" appended to the name.
%
% NOTE ON INPUT FORMAT:
%   This expects the 3D points file (pt#_X, pt#_Y, pt#_Z), NOT the 2D
%   "xypts" file (pt#_cam#_U/V). The 2D pixel file cannot define a real
%   gravity direction; only the reconstructed 3D coordinates can.
% =========================================================================

clear; clc;

%% ------------------------------------------------------------------------
%  USER-ADJUSTABLE INPUTS  (edit everything in this block only)
%  ------------------------------------------------------------------------

% Path to the input 3D points spreadsheet (DLTdv8 xyzpts format).
%CHANGE THIS
inputPath = "C:\Users\yohan\OneDrive\Desktop\Code for Jeff\Test Calibration and Data\STEP5_FINISHED_Reconstructed_xyzpts.csv";

% World "up" direction to align the plumb line to, AFTER rotation.
% [0 0 1] means the vertical axis becomes +Z (up), gravity becomes -Z.
upAxis = [0 0 1];

% How to obtain the two plumb-line points.
%   'manual'     -> type the top/bottom XYZ coordinates directly below.
%   'frompoints' -> pull two tracked points out of the data by name.
plumbMode = 'manual';

% --- Option A: plumbMode = 'manual' -------------------------------------
%CHANGE THIS
% Enter the 3D coordinates of the plumb-line markers directly.
plumbTopXYZ    = [0 0 1];   % top of the plumb line   [x y z]
plumbBottomXYZ = [0 0 0];   % bottom of the plumb line [x y z]

% % --- Option B: plumbMode = 'frompoints' ---------------------------------
% % Give the point NAMES (matching the CSV header prefix) that mark the
% % plumb line, plus which frame(s) to use for their coordinates.
% plumbTopPt    = 'pt8';      % point that is the top of the plumb line
% plumbBottomPt = 'pt9';      % point that is the bottom of the plumb line
% % Frame to sample: a positive integer (row index into the data), or the
% % string 'mean' to average over every frame where BOTH points are visible.
% plumbFrame    = 'mean';

%% ------------------------------------------------------------------------
%  READ THE DATA
%  ------------------------------------------------------------------------
% 'VariableNamingRule','preserve' keeps the original header text (e.g.
% "pt1_X") exactly, so we can match columns by name and write them back
% out unchanged.
T = readtable(inputPath, 'VariableNamingRule', 'preserve');
varNames = T.Properties.VariableNames;   % cell array of column header strings
M = table2array(T);                      % numeric matrix, same column order

% Identify every point in the file by finding its "_X" column, then its
% matching "_Y" and "_Z" columns. This makes the script work for any number
% of points and any point-naming scheme (pt1, pt2, marker_a, ...).
ptBases = {};    % base name of each point, e.g. 'pt1'
colXYZ  = [];    % Nx3 matrix of the [X Y Z] column indices for each point
for i = 1:numel(varNames)
    nm = varNames{i};
    if numel(nm) >= 2 && strcmpi(nm(end-1:end), '_X')
        base = nm(1:end-2);                       % strip the trailing "_X"
        iy = find(strcmpi(varNames, [base '_Y']), 1);
        iz = find(strcmpi(varNames, [base '_Z']), 1);
        if ~isempty(iy) && ~isempty(iz)
            ptBases{end+1}   = base;              %#ok<SAGROW>
            colXYZ(end+1, :) = [i, iy, iz];       %#ok<SAGROW>
        end
    end
end

% Guard against accidentally feeding in the 2D "xypts" (U/V) file, which
% has no _X/_Y/_Z columns and cannot define gravity.
if isempty(ptBases)
    error(['No X/Y/Z columns found. This looks like a 2D pixel (xypts) ', ...
           'file. Use the DLTdv8 xyzpts (3D) export instead.']);
end

%% ------------------------------------------------------------------------
%  DETERMINE THE PLUMB-LINE ENDPOINTS
%  ------------------------------------------------------------------------
switch lower(plumbMode)

    case 'manual'
        % Use the coordinates typed in above.
        pTop    = plumbTopXYZ(:).';      % force to a 1x3 row vector
        pBottom = plumbBottomXYZ(:).';

    case 'frompoints'
        % Locate the named plumb points among the detected points.
        iTop    = find(strcmp(ptBases, plumbTopPt),    1);
        iBottom = find(strcmp(ptBases, plumbBottomPt), 1);
        if isempty(iTop) || isempty(iBottom)
            error('Plumb point name not found among: %s', strjoin(ptBases, ', '));
        end
        topCols    = colXYZ(iTop, :);    % [X Y Z] column indices of top point
        bottomCols = colXYZ(iBottom, :);

        if ischar(plumbFrame) && strcmpi(plumbFrame, 'mean')
            % Average each marker over all frames where it was digitized.
            % 'omitnan' ignores frames where the point was not visible.
            pTop    = mean(M(:, topCols),    1, 'omitnan');
            pBottom = mean(M(:, bottomCols), 1, 'omitnan');
        else
            % Use one specific frame (row) for each marker.
            pTop    = M(plumbFrame, topCols);
            pBottom = M(plumbFrame, bottomCols);
        end

    otherwise
        error('plumbMode must be ''manual'' or ''frompoints''.');
end

% Sanity check: the endpoints must be real, finite, and distinct.
if any(~isfinite([pTop, pBottom]))
    error('Plumb-line endpoints contain NaN/Inf. Check the frame/points chosen.');
end

%% ------------------------------------------------------------------------
%  BUILD THE GRAVITY DIRECTION AND THE ROTATION MATRIX
%  ------------------------------------------------------------------------
% The plumb line hangs along gravity: TOP -> BOTTOM is the "down" direction.
% The "up" direction of the scene is therefore BOTTOM -> TOP.
gravityVec = pBottom - pTop;        % points downward (direction of gravity)
sceneUp    = pTop - pBottom;        % points upward (opposite of gravity)

if norm(sceneUp) < eps
    error('Plumb top and bottom coincide; cannot define a direction.');
end

% Normalize to unit vectors. We solve for R such that R * a = b, where:
%   a = current scene-up direction (unit)
%   b = desired world-up direction (unit)
a = sceneUp(:) / norm(sceneUp);     % 3x1 unit vector, current up
b = upAxis(:)  / norm(upAxis);      % 3x1 unit vector, target up

% --- Rotation that carries unit vector a onto unit vector b --------------
% Using the cross-product form of Rodrigues' rotation formula.
% Let  v = a x b   (rotation axis, its length = sin(theta))
%      c = a . b   (cosine of the rotation angle theta)
% For a NON-degenerate case (a and b not exactly parallel/antiparallel):
%      R = I + [v]_x + [v]_x^2 * (1 - c)/|v|^2
% and since |v|^2 = 1 - c^2 = (1 - c)(1 + c), the last coefficient
% simplifies to 1/(1 + c). [v]_x below is the skew-symmetric "cross-product
% matrix" of v, for which [v]_x * w == cross(v, w) for any vector w.
v = cross(a, b);
c = dot(a, b);

if norm(v) < 1e-12
    % Degenerate case: a and b are collinear.
    if c > 0
        % Already pointing the same way -> no rotation needed.
        R = eye(3);
    else
        % Exactly opposite (theta = 180 deg). Rotate 180 deg about ANY axis
        % perpendicular to a. Build one such axis by crossing a with the
        % world basis vector least aligned with it (keeps it well-conditioned).
        [~, iMin] = min(abs(a));
        e = zeros(3,1); e(iMin) = 1;         % basis vector least parallel to a
        k = cross(a, e); k = k / norm(k);    % unit axis perpendicular to a
        % 180-degree rotation about unit axis k:  R = 2*k*k' - I
        R = 2*(k*k.') - eye(3);
    end
else
    % General case.
    K = [   0   -v(3)  v(2);          % skew-symmetric cross-product matrix [v]_x
          v(3)     0  -v(1);
         -v(2)  v(1)     0   ];
    R = eye(3) + K + K^2 * (1/(1 + c));
end

% Report the recovered geometry so the result can be checked at a glance.
fprintf('Gravity direction (down), unit vector: [% .4f % .4f % .4f]\n', ...
        gravityVec/norm(gravityVec));
fprintf('Rotated scene-up dotted with target up: %.6f (should be 1.0)\n', ...
        dot(R*a, b));

%% ------------------------------------------------------------------------
%  APPLY THE ROTATION TO EVERY POINT
%  ------------------------------------------------------------------------
% Each point occupies three columns [X Y Z]. Stored row-wise, a set of
% points P (n x 3) rotates as P_rot = (R * P.').' = P * R.'.
% NaN gaps (frames where a point was not tracked) rotate to NaN and are
% preserved, keeping the output format identical to the input.
Mrot = M;
for p = 1:numel(ptBases)
    cols = colXYZ(p, :);                 % [X Y Z] columns for this point
    P    = M(:, cols);                   % n x 3 coordinates over all frames
    Mrot(:, cols) = P * R.';             % rotate; NaNs stay NaN
end

%% ------------------------------------------------------------------------
%  WRITE THE OUTPUT (same format, "_gravity_aligned" appended to the name)
%  ------------------------------------------------------------------------
Tout = array2table(Mrot, 'VariableNames', varNames);  % restore original headers

[inDir, inName, inExt] = fileparts(inputPath);
outPath = fullfile(inDir, inName + '_gravity_aligned' + inExt);
writetable(Tout, outPath);

fprintf('Wrote gravity-aligned points to:\n  %s\n', outPath);
