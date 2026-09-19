function C = reconstructMatches(S, R, P1, P2, M1, M2, yOrigin, opts)
%VH.RECONSTRUCTMATCHES Rectified matches -> 3-D points, via the DLT.
%
%   C = vh.reconstructMatches(S, R, P1, P2, M1, M2, yOrigin, opts)
%
%   S   from vh.rectifyPair, R from vh.stereoMatch
%
%   C  .XYZ      n-by-3 world points that survived filtering
%      .rgb      n-by-3 uint8 colour sampled from view 1
%      .residPx  n-by-1 mean reprojection error
%      .kept     logical index into R.p1
%
%   Rectification is undone first, so the triangulation runs on original
%   undistorted image coordinates with the DLT matrices. The rectifying
%   homographies never touch the 3-D result - they only made the matching
%   tractable.

arguments
    S struct
    R struct
    P1 (3,4) double
    P2 (3,4) double
    M1 struct
    M2 struct
    yOrigin (1,:) char
    opts.maxResidPx (1,1) double = 4
    opts.box struct = struct('centre',[0 0 0],'half',Inf)
    opts.verbose (1,1) logical = true
end

C = struct('XYZ', zeros(0,3), 'rgb', zeros(0,3,'uint8'), ...
           'residPx', zeros(0,1), 'kept', false(0,1), 'n', 0);
if R.n == 0, return, end

% Rectified intrinsic pixels -> rectified world -> original image pixels.
o1 = unrectify(R.p1, S.ref1, S.tform1);
o2 = unrectify(R.p2, S.ref2, S.tform2);

uv = nan(2, 2, size(o1,1));
uv(1,:,:) = permute(vh.imageToDLT(o1, M1.H, yOrigin), [3 2 1]);
uv(2,:,:) = permute(vh.imageToDLT(o2, M2.H, yOrigin), [3 2 1]);

P = cat(3, P1, P2);
[XYZ, ok] = vh.triangulateMany(P, uv);

% Reprojection residual in both views.
resid = inf(size(XYZ,1), 1);
good = ok & all(isfinite(XYZ), 2);
if any(good)
    [c1, r1] = vh.project(P1, XYZ(good,:), M1.H, yOrigin);
    [c2, r2] = vh.project(P2, XYZ(good,:), M2.H, yOrigin);
    e1 = hypot(c1 - o1(good,1), r1 - o1(good,2));
    e2 = hypot(c2 - o2(good,1), r2 - o2(good,2));
    resid(good) = (e1 + e2) / 2;
end

inBox = true(size(XYZ,1),1);
if isfinite(opts.box.half)
    inBox = all(abs(XYZ - opts.box.centre) <= 1.5*opts.box.half, 2);
    inBox(~good) = false;
end

kept = good & resid <= opts.maxResidPx & inBox;

C.kept = kept;
C.XYZ = XYZ(kept,:);
C.residPx = resid(kept);
C.n = nnz(kept);

% Colour from the rectified view-1 image at the matched pixel.
if C.n > 0 && ~isempty(S.Irgb1)
    cc = min(max(round(R.p1(kept,1)),1), size(S.Irgb1,2));
    rr = min(max(round(R.p1(kept,2)),1), size(S.Irgb1,1));
    idx = sub2ind([size(S.Irgb1,1) size(S.Irgb1,2)], rr, cc);
    Ir = S.Irgb1;
    if size(Ir,3) == 3
        C.rgb = [reshape(Ir(idx),[],1), ...
                 reshape(Ir(idx + numel(Ir)/3),[],1), ...
                 reshape(Ir(idx + 2*numel(Ir)/3),[],1)];
    else
        % Grayscale texture on this camera - replicate the one channel so
        % every point still gets an R=G=B colour instead of garbage/a crash.
        g = reshape(Ir(idx), [], 1);
        C.rgb = [g g g];
    end
end

if opts.verbose
    fprintf('    %-9s %7d of %d matches reconstructed', ...
        R.name, C.n, R.n);
    if C.n > 0
        fprintf('   median reproj %.2f px', median(C.residPx));
    end
    nBox = nnz(good & resid <= opts.maxResidPx & ~inBox);
    if nBox > 0, fprintf('   (%d dropped outside the volume)', nBox); end
    fprintf('\n');
end
end


function p = unrectify(pRect, ref, tform)
%UNRECTIFY Rectified pixel indices -> original undistorted image pixels.
[xw, yw] = intrinsicToWorld(ref, pRect(:,1), pRect(:,2));
p = transformPointsInverse(tform, [xw yw]);
end
