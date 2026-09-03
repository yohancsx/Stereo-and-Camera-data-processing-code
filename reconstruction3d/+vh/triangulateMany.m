function [XYZ, ok] = triangulateMany(P, uv)
%VH.TRIANGULATEMANY Vectorised least-squares DLT triangulation.
%
%   [XYZ, ok] = vh.triangulateMany(P, uv)
%
%   P    3-by-4-by-nCams DLT projection matrices
%   uv   nCams-by-2-by-nPts observations in DLT coordinates; NaN skips a view
%
%   XYZ  nPts-by-3
%   ok   nPts-by-1 logical, false where fewer than two views saw the point
%        or the normal equations were singular
%
%   Same equations as vh.triangulate, but the 3-by-3 normal system is
%   accumulated for every point at once and solved in batch by Cramer's
%   rule. Looping vh.triangulate over a dense disparity map would take
%   minutes; this takes a fraction of a second.
%
%   Each view contributes
%       (L1 - u L9) X + (L2 - u L10) Y + (L3 - u L11) Z = u - L4
%       (L5 - v L9) X + (L6 - v L10) Y + (L7 - v L11) Z = v - L8

nCams = size(P, 3);
nPts  = size(uv, 3);

% Symmetric 3x3 normal matrix stored as [n11 n12 n13 n22 n23 n33].
N = zeros(nPts, 6);
g = zeros(nPts, 3);
nViews = zeros(nPts, 1);

for i = 1:nCams
    u = reshape(uv(i,1,:), [], 1);
    v = reshape(uv(i,2,:), [], 1);
    good = isfinite(u) & isfinite(v);
    if ~any(good), continue, end
    u(~good) = 0;  v(~good) = 0;

    L = P(:,:,i);
    a1 = [L(1,1) - u*L(3,1), L(1,2) - u*L(3,2), L(1,3) - u*L(3,3)];
    b1 = u - L(1,4);
    a2 = [L(2,1) - v*L(3,1), L(2,2) - v*L(3,2), L(2,3) - v*L(3,3)];
    b2 = v - L(2,4);

    a1(~good,:) = 0;  b1(~good) = 0;
    a2(~good,:) = 0;  b2(~good) = 0;

    N(:,1) = N(:,1) + a1(:,1).*a1(:,1) + a2(:,1).*a2(:,1);
    N(:,2) = N(:,2) + a1(:,1).*a1(:,2) + a2(:,1).*a2(:,2);
    N(:,3) = N(:,3) + a1(:,1).*a1(:,3) + a2(:,1).*a2(:,3);
    N(:,4) = N(:,4) + a1(:,2).*a1(:,2) + a2(:,2).*a2(:,2);
    N(:,5) = N(:,5) + a1(:,2).*a1(:,3) + a2(:,2).*a2(:,3);
    N(:,6) = N(:,6) + a1(:,3).*a1(:,3) + a2(:,3).*a2(:,3);

    g(:,1) = g(:,1) + a1(:,1).*b1 + a2(:,1).*b2;
    g(:,2) = g(:,2) + a1(:,2).*b1 + a2(:,2).*b2;
    g(:,3) = g(:,3) + a1(:,3).*b1 + a2(:,3).*b2;

    nViews = nViews + good;
end

% Batch solve of the symmetric 3x3 systems.
n11 = N(:,1); n12 = N(:,2); n13 = N(:,3);
n22 = N(:,4); n23 = N(:,5); n33 = N(:,6);

c11 = n22.*n33 - n23.*n23;
c12 = n13.*n23 - n12.*n33;
c13 = n12.*n23 - n13.*n22;
det_ = n11.*c11 + n12.*c12 + n13.*c13;

c22 = n11.*n33 - n13.*n13;
c23 = n13.*n12 - n11.*n23;
c33 = n11.*n22 - n12.*n12;

scale = max(abs([n11 n22 n33]), [], 2);
ok = nViews >= 2 & abs(det_) > 1e-12 * max(scale, eps).^3;

XYZ = nan(nPts, 3);
d = det_;  d(~ok) = 1;
XYZ(:,1) = (c11.*g(:,1) + c12.*g(:,2) + c13.*g(:,3)) ./ d;
XYZ(:,2) = (c12.*g(:,1) + c22.*g(:,2) + c23.*g(:,3)) ./ d;
XYZ(:,3) = (c13.*g(:,1) + c23.*g(:,2) + c33.*g(:,3)) ./ d;
XYZ(~ok,:) = NaN;
end
