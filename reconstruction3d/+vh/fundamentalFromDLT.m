function [F, e1, e2] = fundamentalFromDLT(P1, P2, H1, H2, yOrigin)
%VH.FUNDAMENTALFROMDLT Fundamental matrix straight from two DLT matrices.
%
%   [F, e1, e2] = vh.fundamentalFromDLT(P1, P2, H1, H2, yOrigin)
%
%   P1, P2   3-by-4 DLT projection matrices
%   H1, H2   image heights, for the y convention
%   yOrigin  'bottom' or 'top'
%
%   F   3-by-3 fundamental matrix in MATLAB IMAGE coordinates, i.e.
%       [col2 row2 1] * F * [col1 row1 1]' = 0
%   e1  epipole in image 1 (image coordinates), e2 epipole in image 2
%
%   Built analytically as F = [e2]x * P2 * pinv(P1). Note this deliberately
%   avoids decomposing P into K, R and t: the intrinsics a poorly
%   conditioned DLT implies can be badly wrong (principal point hundreds of
%   pixels off centre, aspect ratio off by percent), and feeding those into
%   stereoParameters would bake that error into every reconstructed point.
%   The epipolar geometry itself needs no such decomposition.

arguments
    P1 (3,4) double
    P2 (3,4) double
    H1 (1,1) double
    H2 (1,1) double
    yOrigin (1,:) char
end

% Camera 1 centre: P1 * [C;1] = 0.
C1 = -P1(:,1:3) \ P1(:,4);

e2d = P2 * [C1; 1];                        % epipole in image 2, DLT coords
Fd  = skew(e2d) * P2 * pinv(P1);           % F in DLT coordinates

% Convert to MATLAB image coordinates. With x_img = T * x_dlt,
% x2d' Fd x1d = 0  becomes  x2i' (inv(T2)' Fd inv(T1)) x1i = 0.
T1 = flipMat(H1, yOrigin);
T2 = flipMat(H2, yOrigin);
F = (T2 \ eye(3)).' * Fd * (T1 \ eye(3));
F = F / norm(F(:));

% Epipoles in image coordinates: right and left null vectors of F.
[~, ~, V] = svd(F);   e1 = hnorm(V(:,3));
[U, ~, ~] = svd(F);   e2 = hnorm(U(:,3));
end


function S = skew(v)
S = [    0  -v(3)   v(2)
      v(3)      0  -v(1)
     -v(2)   v(1)      0 ];
end


function T = flipMat(H, yOrigin)
switch lower(yOrigin)
    case 'bottom', T = [1 0 0; 0 -1 H+1; 0 0 1];
    case 'top',    T = eye(3);
    otherwise
        error('vh:fundamentalFromDLT:yOrigin', 'Bad yOrigin ''%s''.', yOrigin);
end
end


function p = hnorm(v)
if abs(v(3)) > eps*max(abs(v))
    p = v(1:2) / v(3);
else
    p = [Inf; Inf];        % epipole at infinity: the views are parallel
end
p = p(:).';
end
