function [sz, per, pxPerUnit] = objectScale(P, M, XYZ, yOrigin)
%VH.OBJECTSCALE How big is the object, in WORLD units, judged from the masks.
%
%   [sz, per, pxPerUnit] = vh.objectScale(P, M, XYZ, yOrigin)
%
%   P        3-by-4-by-nCams, already in camera order
%   M        nCams struct array from vh.loadMasks, in camera order
%   XYZ      1-by-3 point on the object (the triangulated centroid)
%   yOrigin  'bottom' or 'top'
%
%   sz         object size in world units (the largest per-camera estimate)
%   per        nCams-by-1 per-camera estimates
%   pxPerUnit  nCams-by-1 image scale at XYZ, pixels per world unit
%
%   WHY THIS EXISTS
%   The voxel box has to be sized in whatever units the DLT was solved in,
%   and that is set by the wand length given to easyWand. If the wand length
%   was left at 1, the world is in wand-lengths, not mm, and a box specified
%   in mm is wrong by whatever the wand measures. Asking the silhouettes how
%   big the object looks removes the guess entirely.
%
%   Method: the projection Jacobian at XYZ gives pixels per world unit for
%   this camera at this depth (its largest singular value - the two large
%   ones are the directions across the viewing ray, the small one is along
%   it). Dividing the mask's equivalent diameter by that scale converts the
%   silhouette back into world units.

nCams = size(P, 3);
per = zeros(nCams, 1);
pxPerUnit = zeros(nCams, 1);

delta = 1e-3 * max(1, norm(XYZ));

for k = 1:nCams
    m = M(k);
    [c0, r0] = vh.project(P(:,:,k), XYZ, m.H, yOrigin);

    J = zeros(2,3);
    for a = 1:3
        step = zeros(1,3);  step(a) = delta;
        [c1, r1] = vh.project(P(:,:,k), XYZ + step, m.H, yOrigin);
        J(:,a) = [c1 - c0; r1 - r0] / delta;
    end

    s = svd(J);
    pxPerUnit(k) = s(1);

    equivDiam = 2 * sqrt(nnz(m.mask) / pi);
    if pxPerUnit(k) > 0 && isfinite(pxPerUnit(k))
        per(k) = equivDiam / pxPerUnit(k);
    else
        per(k) = NaN;
    end
end

sz = max(per(isfinite(per)));
if isempty(sz), sz = NaN; end
end
