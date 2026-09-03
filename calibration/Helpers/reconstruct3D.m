function XYZ = reconstruct3D(M, nPts, nCams, c)
% Written by Yohan Sequeira 2026
% RECONSTRUCT3D  DLT reconstruct every point/frame from undistorted 2D data.
%
%   Loops over frames and points, calling dltReconstruct once per point per
%   frame with that point's [2 x nCams] [u;v] slice. Frames where a point
%   has fewer than 2 cameras (or is untracked) come back as NaN, so the
%   output stays frame-aligned with the input — important for time-based
%   kinematics.
%
% INPUTS:
%   M          - [F x 2*nPts*nCams] UNDISTORTED pixel coords, columns ordered
%                ptP_camC_U, ptP_camC_V (point-major, camera-minor).
%   nPts,nCams - layout from parseXYptsLayout.
%   c          - [11 x nCams] DLT coefficients (c12 assumed = 1 inside
%                dltReconstruct when only 11 rows are supplied).
%
% OUTPUT:
%   XYZ        - [F x 3*nPts], columns ptP_X, ptP_Y, ptP_Z per point.
%
%   IMPORTANT: the camera order in c (columns) MUST match the camera order in
%   M (cam1, cam2, ...). If they differ, reconstruction silently produces
%   wrong 3D coordinates.

    F   = size(M, 1);
    XYZ = NaN(F, 3 * nPts);

    for p = 1:nPts
        % Column indices for this point's u,v for each camera.
        uCols = ((p-1)*nCams + (0:nCams-1)) * 2 + 1;   % [1 x nCams]
        vCols = uCols + 1;

        for f = 1:F
            camPts = [M(f, uCols); M(f, vCols)];       % [2 x nCams] = [u; v]

            % Skip frames with <2 cameras tracked (dltReconstruct needs >=2).
            if sum(~isnan(camPts(1, :))) < 2
                continue
            end

            xyz = dltReconstruct(c, camPts);           % [1 x 3]
            XYZ(f, (p-1)*3 + (1:3)) = xyz;
        end
    end
end
