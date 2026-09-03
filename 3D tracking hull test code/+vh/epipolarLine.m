function [xy, l] = epipolarLine(F, p, imgSize, direction)
%VH.EPIPOLARLINE The epipolar line of a point, clipped to the other image.
%
%   [xy, l] = vh.epipolarLine(F, p, imgSize, direction)
%
%   F          fundamental matrix in image coordinates, so that
%              [x2 y2 1] * F * [x1 y1 1]' = 0
%   p          1-by-2 point [x y]
%   imgSize    [H W] of the image the LINE will be drawn in
%   direction  1: p is in image 1, the line is in image 2  (l = F  * p)
%              2: p is in image 2, the line is in image 1  (l = F' * p)
%
%   xy   2-by-2 endpoints [x1 y1; x2 y2] clipped to the image rectangle,
%        or a 0-by-2 empty if the line misses the image entirely
%   l    the line [a b c] with a*x + b*y + c = 0
%
%   The whole point of drawing this while digitising: the match for p must
%   lie somewhere on this line. If it visibly does not pass through the
%   corresponding structure, the calibration is wrong and you can see it
%   before committing the click.

arguments
    F (3,3) double
    p (1,2) double
    imgSize (1,2) double
    direction (1,1) double {mustBeMember(direction,[1 2])} = 1
end

if direction == 1
    l = F * [p(:); 1];
else
    l = F.' * [p(:); 1];
end
l = l(:).';

H = imgSize(1);  W = imgSize(2);
a = l(1);  b = l(2);  c = l(3);

xy = zeros(0,2);
if ~all(isfinite(l)) || (abs(a) < eps && abs(b) < eps)
    return
end

tol = 1e-7;
cand = zeros(0,2);
if abs(b) > eps                       % where it crosses the left/right edges
    for x = [1 W]
        y = -(a*x + c) / b;
        if y >= 1-tol && y <= H+tol, cand(end+1,:) = [x y]; end %#ok<AGROW>
    end
end
if abs(a) > eps                       % where it crosses the top/bottom edges
    for y = [1 H]
        x = -(b*y + c) / a;
        if x >= 1-tol && x <= W+tol, cand(end+1,:) = [x y]; end %#ok<AGROW>
    end
end
if size(cand,1) < 2, return, end

% Keep the two furthest apart, which discards duplicates at the corners.
d = pdist2local(cand);
[~, k] = max(d(:));
[i, j] = ind2sub(size(d), k);
xy = cand([i j], :);
end


function d = pdist2local(p)
n = size(p,1);
d = zeros(n);
for i = 1:n
    for j = 1:n
        d(i,j) = hypot(p(i,1)-p(j,1), p(i,2)-p(j,2));
    end
end
end
