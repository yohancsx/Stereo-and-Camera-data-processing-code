function [XYZ, algResid] = triangulate(P, uv)
%VH.TRIANGULATE Least-squares 3-D point from DLT views.
%
%   [XYZ, algResid] = vh.triangulate(P, uv)
%
%   P     3-by-4-by-nCams DLT projection matrices
%   uv    nCams-by-2 (single point) or nCams-by-2-by-nPts, in the DLT
%         convention. Rows of NaN are skipped, so a camera that did not see
%         the point can be left out.
%
%   XYZ        nPts-by-3
%   algResid   nPts-by-1 residual norm of the linear system (world units,
%              not pixels - use vh.project for a pixel residual)
%
%   Each view contributes two rows, from
%       u*(L9 X + L10 Y + L11 Z + 1) = L1 X + L2 Y + L3 Z + L4
%   rearranged to
%       (L1 - u L9) X + (L2 - u L10) Y + (L3 - u L11) Z = u - L4
%   and likewise for v with L5..L8.

nCams = size(P, 3);
assert(size(uv,1) == nCams, 'vh:triangulate:size', ...
    'uv must have one row per camera (%d).', nCams);

nPts = size(uv, 3);
XYZ = nan(nPts, 3);
algResid = nan(nPts, 1);

for p = 1:nPts
    A = zeros(2*nCams, 3);
    b = zeros(2*nCams, 1);
    n = 0;
    for i = 1:nCams
        u = uv(i,1,p);  v = uv(i,2,p);
        if ~isfinite(u) || ~isfinite(v), continue, end
        L = P(:,:,i);
        n = n + 1;
        A(2*n-1,:) = [L(1,1) - u*L(3,1), L(1,2) - u*L(3,2), L(1,3) - u*L(3,3)];
        b(2*n-1)   =  u - L(1,4);
        A(2*n,:)   = [L(2,1) - v*L(3,1), L(2,2) - v*L(3,2), L(2,3) - v*L(3,3)];
        b(2*n)     =  v - L(2,4);
    end
    if n < 2, continue, end          % need at least two views
    A = A(1:2*n,:);  b = b(1:2*n);

    x = A \ b;
    XYZ(p,:) = x.';
    algResid(p) = norm(A*x - b);
end
end
