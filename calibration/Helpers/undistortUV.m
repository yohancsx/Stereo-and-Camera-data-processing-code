function uvUndist = undistortUV(uvDist, intrinsics)
% Written by Yohan Sequeira 2026
% UNDISTORTUV  Undistort fisheye pixel coordinates for one or more cameras.
%
%   Rewritten version of undistortUVMatlab. Instead of hand-assembling K,
%   ss, affine and imageSize, this takes the fisheyeIntrinsics object
%   exactly as exported by the MATLAB (single) Camera Calibrator app.
%
%   In this rig ALL cameras share the SAME distortion coefficients, so you
%   pass a single fisheyeIntrinsics object and it is applied to every camera.
%
% INPUTS:
%   uvDist     - [2 x nCams] distorted pixel coordinates, one column per
%                camera, stacked as [u; v].
%   intrinsics - a fisheyeIntrinsics object (from params.Intrinsics), OR a
%                fisheyeParameters / cameraParameters object (its
%                .Intrinsics field is used automatically).
%
% OUTPUT:
%   uvUndist   - [2 x nCams] undistorted pixel coordinates [u; v].
%
% NaN handling: any camera whose point is NaN is passed through as NaN
% (undistortFisheyePoints would otherwise error or return garbage on NaN).

    % Accept either the intrinsics object or the full parameters object.
    if ~isa(intrinsics, 'fisheyeIntrinsics')
        if isprop(intrinsics, 'Intrinsics') || isfield(intrinsics, 'Intrinsics')
            intrinsics = intrinsics.Intrinsics;
        else
            error('undistortUV:badIntrinsics', ...
                ['Second argument must be a fisheyeIntrinsics object, or an ', ...
                 'object with an .Intrinsics property.']);
        end
    end

    nCams    = size(uvDist, 2);
    uvUndist = NaN(2, nCams);

    for camNum = 1:nCams
        pt = uvDist(:, camNum);           % [u; v] for this camera

        % Skip untracked points — leave them NaN.
        if any(isnan(pt))
            continue
        end

        % undistortFisheyePoints expects an N-by-2 [u, v] list.
        ptOut = undistortFisheyePoints(pt', intrinsics);
        uvUndist(:, camNum) = ptOut';
    end
end
