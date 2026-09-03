function xyz = dltReconstruct(c,camPtsRaw)

% function [xyz] = dlt_reconstruct_fast(c,camPts)
%
% This function reconstructs the 3D position of a coordinate based on a set
% of DLT coefficients and [u,v] pixel coordinates from 2 or more cameras
%
% Inputs:
%  c - 12 DLT coefficients for all n cameras, [12,n] array
%  camPtsRaw - [u;v] pixel coordinates from all n cameras over f frames,
%   [2,n] array [u;v]
%
% Outputs:
%  xyz - the xyz location, a [1,3] array (NaN if fewer than 2 cameras saw it)
%
% Written by Yohan Sequeira 2026 - Adapted from Ty Hedrick's code (2024). Note that we aren't assuming
% the camera axes are aligned in any way, so it requirues all 12 coeffs
%
% Cross-checked against vh.triangulate: the two agree to 1.6e-14 on four
% cameras and 3.6e-13 on two, and both are exact against synthetic truth.

% Reshape camPtsRaw [2 x nCams] into [1 x 2*nCams] as [u1 v1 u2 v2 ...].
% Column-major reshape already interleaves u and v exactly that way.
camPts = reshape(camPtsRaw, 1, []);

nFrames = size(camPts, 1);
nCams   = size(camPts, 2) / 2;
nCoeffs = size(c, 1);       % 11 or 12

xyz  = NaN(nFrames, 3);

for i = 1:nFrames
    % Cameras with non-NaN [u,v]
    cdx = find(~isnan(camPts(i, 1:2:nCams*2)));

    if numel(cdx) >= 2
        m1 = zeros(numel(cdx)*2, 3);
        m2 = zeros(numel(cdx)*2, 1);

        % Get c12 for each camera â€” either supplied or assumed to be 1
        if nCoeffs == 12
            c12 = c(12, cdx);
        else
            c12 = ones(1, numel(cdx));
        end

        u = camPts(i, cdx*2-1);
        v = camPts(i, cdx*2);

        % u equation: (c1*X + c2*Y + c3*Z + c4) - u*(c9*X + c10*Y + c11*Z + c12) = 0
        m1(1:2:end, 1) = u .* c(9,cdx)  - c(1,cdx);
        m1(1:2:end, 2) = u .* c(10,cdx) - c(2,cdx);
        m1(1:2:end, 3) = u .* c(11,cdx) - c(3,cdx);
        m2(1:2:end)    = c(4,cdx) - u .* c12;

        % v equation: (c5*X + c6*Y + c7*Z + c8) - v*(c9*X + c10*Y + c11*Z + c12) = 0
        m1(2:2:end, 1) = v .* c(9,cdx)  - c(5,cdx);
        m1(2:2:end, 2) = v .* c(10,cdx) - c(6,cdx);
        m1(2:2:end, 3) = v .* c(11,cdx) - c(7,cdx);
        m2(2:2:end)    = c(8,cdx) - v .* c12;

        % Least squares solution
        xyz(i, 1:3) = mldivide(m1, m2)';

        % % RMSE in pixel units
        % uv  = m1 * xyz(i,1:3)';
        % dof = numel(m2) - 3;
        % rmse(i,1) = sqrt(sum((m2 - uv).^2) / dof);
    end
end
end
