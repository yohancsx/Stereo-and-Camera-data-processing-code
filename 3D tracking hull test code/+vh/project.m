function [col, row, w, u, v] = project(P, XYZ, imgH, yOrigin)
%VH.PROJECT DLT-project 3-D points and return MATLAB image indices.
%
%   [col, row, w, u, v] = vh.project(P, XYZ, imgH, yOrigin)
%
%   P        3-by-4 DLT projection matrix (see vh.readDLT)
%   XYZ      N-by-3 world points
%   imgH     image height in pixels, used only for the y flip
%   yOrigin  'bottom' - the DLT convention, y measured up from the bottom
%            'top'    - MATLAB image convention, y measured down from the top
%
%   col,row  N-by-1 unrounded MATLAB image indices (col = x, row = y-down)
%   w        N-by-1 homogeneous denominator. Its SIGN is the cheirality
%            test: points on the wrong side of the camera have the opposite
%            sign to points in front. The absolute sign depends on how the
%            DLT was scaled, so compare against a point known to be in view
%            rather than assuming w > 0.
%   u,v      N-by-1 coordinates in the DLT convention, before any flip
%
%   Deliberately avoids forming a 4-by-N homogeneous matrix: at a few
%   million voxels that copy alone is hundreds of megabytes.

X = XYZ(:,1);  Y = XYZ(:,2);  Z = XYZ(:,3);

w = P(3,1)*X + P(3,2)*Y + P(3,3)*Z + P(3,4);
u = (P(1,1)*X + P(1,2)*Y + P(1,3)*Z + P(1,4)) ./ w;
v = (P(2,1)*X + P(2,2)*Y + P(2,3)*Z + P(2,4)) ./ w;

col = u;
switch lower(yOrigin)
    case 'bottom', row = imgH + 1 - v;
    case 'top',    row = v;
    otherwise
        error('vh:project:yOrigin', ...
            'yOrigin must be ''bottom'' or ''top'', got ''%s''.', yOrigin);
end
end
