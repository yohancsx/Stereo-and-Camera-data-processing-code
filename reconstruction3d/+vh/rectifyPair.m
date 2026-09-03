function S = rectifyPair(P1, P2, M1, M2, box, yOrigin, opts)
%VH.RECTIFYPAIR Rectify a DLT camera pair for stereo matching.
%
%   S = vh.rectifyPair(P1, P2, M1, M2, box, yOrigin, opts)
%
%   P1,P2    3-by-4 DLT matrices for the pair
%   M1,M2    the two views from vh.loadMasks (need .rgb, .mask, .H, .W)
%   box      struct with .centre (1x3) and .half (scalar), the working
%            volume, used to synthesise exact correspondences and to
%            predict the disparity range
%   yOrigin  'bottom' or 'top'
%
%   opts  .pad         pixels of margin around the rectified silhouette
%         .maxDim      cap on the rectified output size
%         .verbose
%
%   S  .I1 .I2         rectified greyscale (uint8), same size, rows aligned
%      .Irgb1 .Irgb2   rectified colour
%      .K1 .K2         rectified masks
%      .ref1 .ref2     imref2d for each rectified image
%      .tform1 .tform2 rectifying transforms
%      .F              fundamental matrix in image coordinates
%      .dispRange      disparity range to search, [min max]
%      .checks         validation numbers, see below
%
%   THE ONE THING RECTIFICATION IS FOR
%   Only to let a block matcher assume corresponding pixels share a row.
%   The 3-D reconstruction afterwards goes back to the original image
%   coordinates and triangulates with the DLT, so nothing here can inject
%   the DLT's bad implied intrinsics into the result.
%
%   Correspondences fed to estimateStereoRectification are synthesised by
%   projecting points from the working volume through both P matrices, so
%   they are exact inliers by construction and the rectification is not at
%   the mercy of a feature matcher.

arguments
    P1 (3,4) double
    P2 (3,4) double
    M1 struct
    M2 struct
    box struct
    yOrigin (1,:) char
    opts.pad (1,1) double = 60
    opts.maxDim (1,1) double = 2400
    opts.maxDisparitySpan (1,1) double = 112
    opts.F double = []                 % override the DLT's F
    opts.corr double = []              % n-by-4 real correspondences [x1 y1 x2 y2]
    opts.verbose (1,1) logical = true
end

S = struct();
S.source = 'dlt';

%% ---- fundamental matrix, and proof that it is right --------------------
[Fdlt, e1, e2] = vh.fundamentalFromDLT(P1, P2, M1.H, M2.H, yOrigin);

% Synthetic correspondences spanning a volume wider than the animal, so the
% rectification is conditioned over the whole region we care about, and so
% the disparity range can be predicted before any matching happens.
rng(0);
nSyn = 4000;
Xs = box.centre + (rand(nSyn,3)-0.5) * (4*box.half);
[c1, r1, w1] = vh.project(P1, Xs, M1.H, yOrigin);
[c2, r2, w2] = vh.project(P2, Xs, M2.H, yOrigin);
keep = isfinite(c1) & isfinite(c2) & isfinite(r1) & isfinite(r2) & ...
       sign(w1) == sign(median(w1)) & sign(w2) == sign(median(w2));
p1 = [c1(keep) r1(keep)];  p2 = [c2(keep) r2(keep)];
assert(size(p1,1) >= 50, 'vh:rectifyPair:noSynthetic', ...
    'Could not synthesise correspondences - is the working volume sane?');

% When the DLT's epipolar geometry has been shown not to fit the images, we
% can instead rectify on an F fitted to real correspondences. The 3-D points
% are still triangulated with the DLT afterwards - this only buys correct
% MATCHES. It also makes the reprojection residual informative again,
% because correspondences are no longer forced onto the DLT's epipolar lines.
if ~isempty(opts.F)
    F = opts.F;  S.source = 'data';
    assert(~isempty(opts.corr) && size(opts.corr,1) >= 8, ...
        'vh:rectifyPair:needCorr', ...
        'An external F must come with at least 8 real correspondences.');
    p1 = opts.corr(:,1:2);  p2 = opts.corr(:,3:4);
else
    F = Fdlt;
end
S.F = F;  S.Fdlt = Fdlt;  S.e1 = e1;  S.e2 = e2;

% Check 1: do these exact correspondences satisfy x2'*F*x1 = 0?
x1h = [p1 ones(size(p1,1),1)].';
x2h = [p2 ones(size(p2,1),1)].';
alg = abs(sum(x2h .* (F * x1h), 1)).';
Fx1  = F * x1h;   Ftx2 = F.' * x2h;
samp = alg ./ sqrt(Fx1(1,:).'.^2 + Fx1(2,:).'.^2 + Ftx2(1,:).'.^2 + Ftx2(2,:).'.^2);
S.checks.fSampsonPx = max(samp);

%% ---- rectifying transforms ---------------------------------------------
imSize = [M1.H M1.W];
if exist('estimateStereoRectification', 'file')
    [t1, t2] = estimateStereoRectification(F, p1, p2, imSize);
else
    [t1, t2] = estimateUncalibratedRectification(F, p1, p2, imSize);
end
S.tform1 = t1;  S.tform2 = t2;

% Check 2: after rectification the same 3-D points must share a row.
q1 = transformPointsForward(t1, p1);
q2 = transformPointsForward(t2, p2);
S.checks.rectRowErrPx = median(abs(q1(:,2) - q2(:,2)));
S.checks.rectRowErrMaxPx = max(abs(q1(:,2) - q2(:,2)));

%% ---- output windows -----------------------------------------------------
% Rectified extent of each silhouette, so we only warp the part that matters.
b1 = maskOutline(M1.mask);   b2 = maskOutline(M2.mask);
o1 = transformPointsForward(t1, b1);
o2 = transformPointsForward(t2, b2);

yLim = [min([o1(:,2); o2(:,2)]) - opts.pad, max([o1(:,2); o2(:,2)]) + opts.pad];

% Disparity of the animal itself. With the DLT's F this comes from synthetic
% points inside the working volume; with a data-driven F the real matches
% are the only honest source.
if strcmp(S.source, 'data')
    d = q1(:,1) - q2(:,1);
    d = d(d > prctileL(d,2) & d < prctileL(d,98));    % trim match outliers
else
    inVol = all(abs(Xs - box.centre) <= box.half, 2);
    d = q1(inVol(keep),1) - q2(inVol(keep),1);
    if isempty(d), d = q1(:,1) - q2(:,1); end
end

% Shift image 2 so the search starts just above zero: the absolute
% disparity here is hundreds of pixels, but its spread across the animal is
% only tens, and that spread is all a block matcher needs to cover.
shift = median(d) - 16;
xLim1 = [min(o1(:,1)) - opts.pad, max(o1(:,1)) + opts.pad];
xLim2 = xLim1 - shift;

wPix = ceil(diff(xLim1));  hPix = ceil(diff(yLim));
sc = min(1, opts.maxDim / max(wPix, hPix));

% disparitySGM will not search a span wider than 128 px. The disparity
% spread across the animal is a physical quantity, so the only lever is
% resolution: shrink the rectified pair just enough to fit, and no more.
spread = max(d) - min(d);
scDisp = opts.maxDisparitySpan / max(spread, eps);
if scDisp < sc
    sc = scDisp;
    S.checks.scaledForDisparity = true;
else
    S.checks.scaledForDisparity = false;
end

outSize = [max(8, round(hPix*sc)), max(8, round(wPix*sc))];

S.ref1 = imref2d(outSize, xLim1, yLim);
S.ref2 = imref2d(outSize, xLim2, yLim);
S.scale = sc;

dRes = d - shift;                                    % residual disparity
lo = floor((min(dRes)*sc - 8)/16)*16;
hi = ceil( (max(dRes)*sc + 8)/16)*16;
if hi - lo < 32, hi = lo + 32; end
if hi - lo > 128                       % hard limit in disparitySGM
    mid = round((hi + lo)/2 / 16) * 16;
    lo = mid - 64;  hi = mid + 64;
    S.checks.disparityClipped = true;
else
    S.checks.disparityClipped = false;
end
S.dispRange = [lo hi];
S.shift = shift;
S.checks.absDisparityPx = median(d);
S.checks.disparitySpreadPx = max(d) - min(d);

%% ---- warp ---------------------------------------------------------------
S.Irgb1 = imwarp(M1.rgb,  t1, 'OutputView', S.ref1, 'SmoothEdges', true);
S.Irgb2 = imwarp(M2.rgb,  t2, 'OutputView', S.ref2, 'SmoothEdges', true);
S.K1    = imwarp(M1.mask, t1, 'nearest', 'OutputView', S.ref1);
S.K2    = imwarp(M2.mask, t2, 'nearest', 'OutputView', S.ref2);
S.I1    = im2gray(S.Irgb1);
S.I2    = im2gray(S.Irgb2);

if opts.verbose
    if strcmp(S.source,'data'), src = 'real matches'; else, src = 'synthetic '; end
    fprintf('    F Sampson error on %s : %.2e px\n', src, S.checks.fSampsonPx);
    fprintf('    rectified row error, %s : %.3f px median, %.3f max\n', ...
        src, S.checks.rectRowErrPx, S.checks.rectRowErrMaxPx);
    fprintf('    epipoles at (%.0f, %.0f) and (%.0f, %.0f)\n', e1, e2);
    fprintf('    absolute disparity %.0f px, spread across the animal %.0f px\n', ...
        S.checks.absDisparityPx, S.checks.disparitySpreadPx);
    fprintf('    rectified size %d x %d (scale %.3f), search range [%d %d]\n', ...
        outSize(2), outSize(1), sc, S.dispRange);
    if S.checks.scaledForDisparity
        fprintf(['    (scaled down to %.2f so the %.0f px disparity spread ' ...
            'fits SGM''s 128 px limit)\n'], sc, spread);
    end
    if S.checks.disparityClipped
        fprintf('    [!] disparity range clipped to 128 px - far/near points will be lost\n');
    end
end
end


function q = prctileL(x, p)
x = sort(x(:));  n = numel(x);
if n < 2, q = NaN; return, end
i = max(1, min(n, (p/100)*(n-1)+1));
lo = floor(i); hi = ceil(i);
q = x(lo) + (i-lo)*(x(hi)-x(lo));
end


function b = maskOutline(mask)
%MASKOUTLINE A few hundred boundary points, enough to bound the warped shape.
[r, c] = find(bwperim(mask));
if numel(r) > 600
    k = round(linspace(1, numel(r), 600));
    r = r(k);  c = c(k);
end
b = [c r];
end
