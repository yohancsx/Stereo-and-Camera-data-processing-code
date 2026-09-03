function M = undistortPointsTable(M, nPts, nCams, intrinsics)
% Written by Yohan Sequeira 2026
% UNDISTORTPOINTSTABLE  Undistort every point in a DLTdv xypts matrix.
%
%   Operates on the raw numeric matrix (frames x 2*nPts*nCams) whose columns
%   are ordered ptP_camC_U, ptP_camC_V (point-major, camera-minor). Returns a
%   matrix of the same size with undistorted [u,v]. NaN entries (untracked
%   frames) are preserved as NaN so the output stays frame-aligned.
%
%   All cameras share one fisheyeIntrinsics object (this rig uses identical
%   distortion for every camera).
%
% INPUTS:
%   M          - [F x 2*nPts*nCams] raw pixel coordinates.
%   nPts,nCams - layout from parseXYptsLayout.
%   intrinsics - fisheyeIntrinsics object.
%
% OUTPUT:
%   M          - same size, undistorted (NaN rows preserved per point/cam).
%
%   Undistortion is batched per (point,camera) column-pair across all frames
%   for speed; only non-NaN frames are sent to undistortFisheyePoints.

    for p = 1:nPts
        for c = 1:nCams
            uCol = ((p-1)*nCams + (c-1)) * 2 + 1;
            vCol = uCol + 1;

            uv = M(:, [uCol vCol]);            % [F x 2]
            good = ~any(isnan(uv), 2);         % frames with a real point

            if any(good)
                out = undistortFisheyePoints(uv(good, :), intrinsics);
                uv(good, :) = out;
                M(:, [uCol vCol]) = uv;        % NaN rows left untouched
            end
        end
    end
end
