function T = dltIntrinsics(P)
%VH.DLTINTRINSICS Recover the pinhole camera each DLT column implies.
%
%   T = vh.dltIntrinsics(P)   P is 3-by-4-by-nCams
%
%   T  nCams-by-1 struct with .fx .fy .cx .cy .aspect
%
%   WHY THIS IS WORTH CHECKING
%   DLT-11 has enough free parameters to absorb an arbitrary principal
%   point, aspect ratio and skew. A poorly conditioned wand calibration can
%   therefore reproduce its own wand points while describing a camera that
%   cannot physically exist - and it will still carve a hull, just the wrong
%   one. Decomposing the coefficients exposes that immediately.
%
%   For masks undistorted by undistortFisheyeImage / undistortImage with
%   OutputView 'same', the virtual camera has its principal point EXACTLY at
%   the image centre and fx == fy exactly. So a healthy DLT should return
%   cx = (W+1)/2, cy = (H+1)/2 and aspect = 1 for every camera. Departures of
%   more than a few tens of pixels, or a percent or two of aspect, mean the
%   calibration is not describing the real geometry.
%
%   Method: write the left 3-by-3 block as M = K*R with R orthonormal and
%   scale so |m3| = 1. Then
%       cx = m1 . m3      cy = m2 . m3
%       fy = |m2 x m3|    sqrt(fx^2 + skew^2) = |m1 x m3|

nCams = size(P, 3);
T = struct('fx', {}, 'fy', {}, 'cx', {}, 'cy', {}, 'aspect', {});

for k = 1:nCams
    M = P(:,1:3,k);
    n3 = norm(M(3,:));
    if n3 < eps
        T(k) = struct('fx',NaN,'fy',NaN,'cx',NaN,'cy',NaN,'aspect',NaN);
        continue
    end
    Mn = M / n3;
    cx = dot(Mn(1,:), Mn(3,:));
    cy = dot(Mn(2,:), Mn(3,:));
    fx = norm(cross(Mn(1,:), Mn(3,:)));
    fy = norm(cross(Mn(2,:), Mn(3,:)));
    T(k) = struct('fx', fx, 'fy', fy, 'cx', cx, 'cy', cy, ...
                  'aspect', fy / max(fx, eps));
end
T = T(:);
end
