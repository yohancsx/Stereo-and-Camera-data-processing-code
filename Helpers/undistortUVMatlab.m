function uvUndist = undistortUVMatlab(uvDist, K, ss, affineCorrection, imageSize)
% Written by Yohan Sequeira 2026
% UNDISTORTUV_MATLAB  Wrapper around MATLAB's undistortFisheyePoints
%
% INPUTS:
%   uvDist          - [2×nCams] distorted pixel coordinates [u; v]
%   K               - [3×3×nCams] camera intrinsic matrices
%   ss              - [5×nCams] Scaramuzza ss coefficients [a0,a1,a2,a3,a4]
%   affineCorrection - [3×nCams] affine parameters [c; d; e]
%   imageSize       - [2×nCams] [height; width] for each camera
%
% OUTPUTS:
%   uvUndist        - [2×nCams] undistorted pixel coordinates

    nCams    = size(K, 3);
    uvUndist = zeros(2, nCams);

    for camNum = 1:nCams

        principalPoint = [K(1,3,camNum), K(2,3,camNum)];

        % MATLAB wants [a0, a2, a3, a4] — drop a1
        ss_cam        = ss(:, camNum);
        mappingCoeffs = [ss_cam(1), ss_cam(3), ss_cam(4), ss_cam(5)];

        % Affine stretch matrix [c d; e 1]
        stretchMat = [affineCorrection(1,camNum), affineCorrection(2,camNum);
                      affineCorrection(3,camNum), 1];

        intrinsics = fisheyeIntrinsics(mappingCoeffs, ...
                                       imageSize(:,camNum)', ...
                                       principalPoint, ...
                                       stretchMat);

        % undistortFisheyePoints expects N×2 [u,v]
        pt_out = undistortFisheyePoints(uvDist(:,camNum)', intrinsics);

        uvUndist(:,camNum) = pt_out';
    end
end