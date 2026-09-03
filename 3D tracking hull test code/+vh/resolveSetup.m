function R = resolveSetup(P, M, opts)
%VH.RESOLVESETUP Work out the camera pairing and the y convention from data.
%
%   R = vh.resolveSetup(P, M, opts)
%
%   Two things are ambiguous when you hand over n masks and a DLT file:
%     1. WHICH mask belongs to which column of the DLT file
%     2. WHETHER the DLT y axis runs up from the bottom (the DLT/easyWand
%        convention) or down from the top (MATLAB image convention)
%   Both are settled by measurement rather than assumption.
%
%   TWO STAGES, because one is not enough.
%
%   Stage 1 (cheap) triangulates a 3-D point from the mask centroids and
%   measures the reprojection residual. This is fast but it can be nearly
%   blind: if the object sits near the vertical centre of every frame then
%   flipping y barely moves the centroid, and a symmetric camera rig makes
%   several pairings score alike. Measured on a synthetic rig, the correct
%   and incorrect answers came in at 0.53 px and 0.54 px - no signal at all.
%
%   Stage 2 (decisive) carves a low-resolution hull for each surviving
%   candidate and measures how much of each mask the hull covers when
%   reprojected. This uses the whole silhouette instead of one point, so a
%   wrong pairing or a wrong flip produces cones that do not agree and a
%   hull that is small, misplaced, or empty. Masks are downsampled for this
%   probe, so it stays quick even on 16 MP frames.
%
%   opts  .camOrder      [] to search, or a fixed permutation
%         .yOrigin       'auto' | 'bottom' | 'top'
%         .objectSize    [] to estimate it from the silhouettes
%         .boxPadFactor
%         .probeN        probe grid resolution per axis
%         .maxProbe      how many stage-1 candidates to carve
%         .probeMaxDim   mask downsample for the probe
%
%   R     .camOrder .yOrigin .XYZ .residPx .coverage .ranking

arguments
    P double
    M struct
    opts.camOrder double = []
    opts.yOrigin (1,:) char = 'auto'
    opts.objectSize double = []
    opts.boxPadFactor (1,1) double = 1.6
    opts.probeN (1,1) double = 40
    opts.maxProbe (1,1) double = 8
    opts.probeMaxDim (1,1) double = 600
    opts.verbose (1,1) logical = true
end

nCams = size(P, 3);
assert(numel(M) == nCams, 'vh:resolveSetup:count', ...
    'Got %d mask(s) for %d DLT camera(s).', numel(M), nCams);

% Mask centroids in MATLAB image indices.
cen = zeros(nCams, 2);
for i = 1:nCams
    [r, c] = ind2sub([M(i).H M(i).W], find(M(i).mask));
    cen(i,:) = [mean(c) mean(r)];
end

% Candidate pairings.
if ~isempty(opts.camOrder)
    orders = opts.camOrder(:).';
    assert(isequal(sort(orders), 1:nCams), 'vh:resolveSetup:badOrder', ...
        'camOrder must be a permutation of 1:%d.', nCams);
elseif nCams <= 7
    orders = flipud(perms(1:nCams));      % identity first, so ties favour it
else
    warning('vh:resolveSetup:tooManyCams', ...
        'nCams = %d; not searching permutations.', nCams);
    orders = 1:nCams;
end

switch lower(opts.yOrigin)
    case 'auto',   yList = {'bottom', 'top'};
    case 'bottom', yList = {'bottom'};
    case 'top',    yList = {'top'};
    otherwise, error('vh:resolveSetup:yOrigin','Bad yOrigin ''%s''.', opts.yOrigin);
end

%% ------------------------------------------- stage 1: centroid consistency

res = struct('order',{},'yOrigin',{},'residPx',{},'insideAll',{}, ...
             'XYZ',{},'perCam',{},'coverage',{},'nOcc',{},'probed',{}, ...
             'objectSize',{});

for oi = 1:size(orders,1)
    ord = orders(oi,:);
    for yi = 1:numel(yList)
        yO = yList{yi};

        uv = nan(nCams, 2);
        for k = 1:nCams
            uv(k,:) = vh.imageToDLT(cen(ord(k),:), M(ord(k)).H, yO);
        end
        XYZ = vh.triangulate(P, uv);
        if any(~isfinite(XYZ)), continue, end

        perCam = nan(nCams,1);  inside = true;
        for k = 1:nCams
            m = M(ord(k));
            [col, row] = vh.project(P(:,:,k), XYZ, m.H, yO);
            perCam(k) = hypot(col - cen(ord(k),1), row - cen(ord(k),2));
            rc = round([row col]);
            if rc(1) < 1 || rc(1) > m.H || rc(2) < 1 || rc(2) > m.W
                inside = false;
            elseif ~m.mask(rc(1), rc(2))
                inside = false;
            end
        end

        res(end+1) = struct('order', ord, 'yOrigin', yO, ...
            'residPx', sqrt(mean(perCam.^2)), 'insideAll', inside, ...
            'XYZ', XYZ, 'perCam', perCam, 'coverage', NaN, ...
            'nOcc', NaN, 'probed', false, 'objectSize', NaN);                      %#ok<AGROW>
    end
end

assert(~isempty(res), 'vh:resolveSetup:noSolution', ...
    'No camera pairing produced a finite triangulation.');

s1 = [res.residPx]';
s1(~[res.insideAll]') = s1(~[res.insideAll]') + 1e6;
[~, ord1] = sort(s1);
res = res(ord1);

%% ---------------------------------------------- stage 2: probe carve

% Downsampled masks, once, for a cheap coverage test.
Md = M;
dScale = zeros(nCams,1);
for i = 1:nCams
    dScale(i) = min(1, opts.probeMaxDim / max(M(i).H, M(i).W));
    Md(i).mask = imresize(M(i).mask, dScale(i), 'nearest');
    [Md(i).H, Md(i).W] = size(Md(i).mask);
end

nProbe = min(opts.maxProbe, numel(res));

for c = 1:nProbe
    cand = res(c);
    Mo = M(cand.order);  Mdo = Md(cand.order);  dso = dScale(cand.order);

    % Size the probe box from the silhouettes themselves unless the caller
    % pinned it. This is what makes the search work whatever units the DLT
    % was solved in - see vh.objectScale.
    if isempty(opts.objectSize)
        estSz = vh.objectScale(P, Mo, cand.XYZ, cand.yOrigin);
        if ~isfinite(estSz) || estSz <= 0, estSz = 1; end
    else
        estSz = opts.objectSize;
    end
    res(c).objectSize = estSz;
    half = estSz * opts.boxPadFactor / 2;

    g = struct('x', linspace(cand.XYZ(1)-half, cand.XYZ(1)+half, opts.probeN), ...
               'y', linspace(cand.XYZ(2)-half, cand.XYZ(2)+half, opts.probeN), ...
               'z', linspace(cand.XYZ(3)-half, cand.XYZ(3)+half, opts.probeN));

    wS = zeros(nCams,1);
    for k = 1:nCams
        [~,~,w] = vh.project(P(:,:,k), cand.XYZ, Mo(k).H, cand.yOrigin);
        wS(k) = sign(w);
    end

    cnt = vh.carve(P, Mo, g, cand.yOrigin, 'wSign', wS, 'verbose', false);
    occ = cnt >= nCams;
    if ~any(occ(:)), occ = cnt >= nCams-1; end

    res(c).probed = true;
    res(c).nOcc = nnz(occ);
    if ~any(occ(:))
        res(c).coverage = 0;
        continue
    end

    [ix, iy, iz] = ind2sub(size(occ), find(occ));
    Pts = [g.x(ix).', g.y(iy).', g.z(iz).'];

    cov = zeros(nCams,1);
    for k = 1:nCams
        m = Mdo(k);  s = dso(k);
        [col, row] = vh.project(P(:,:,k), Pts, Mo(k).H, cand.yOrigin);
        col = (col - 0.5)*s + 0.5;      % full-res index -> downsampled index
        row = (row - 0.5)*s + 0.5;

        cc = round(col);  rr = round(row);
        inb = cc >= 1 & cc <= m.W & rr >= 1 & rr <= m.H;
        proj = false(m.H, m.W);
        if any(inb), proj((cc(inb)-1)*m.H + rr(inb)) = true; end

        % One voxel projects to roughly this many pixels; close the gaps so
        % the sparse point set becomes a comparable region.
        rad = probeVoxelRadius(P(:,:,k), cand.XYZ, g, Mo(k).H, cand.yOrigin, s);
        if rad >= 1
            proj = imdilate(proj, strel('disk', rad));
            proj = imfill(proj, 'holes');
        end
        cov(k) = nnz(proj & m.mask) / max(nnz(m.mask), 1);
    end
    res(c).coverage = mean(cov);
end

% Final ranking: probed candidates by coverage, then everything else.
probed = [res.probed];
cvg = [res.coverage];
score = -inf(size(cvg));
score(probed) = cvg(probed);
[~, ord2] = sort(score, 'descend');
res = res(ord2);
best = res(1);

R = struct('camOrder', best.order, 'yOrigin', best.yOrigin, ...
    'XYZ', best.XYZ, 'residPx', best.residPx, ...
    'perCamResidPx', best.perCam, 'insideAll', best.insideAll, ...
    'coverage', best.coverage, 'objectSize', best.objectSize, ...
    'ranking', res, 'maskCentroids', cen);

if opts.verbose
    fprintf('\nvh.resolveSetup: %d combination(s), %d carved as a probe\n', ...
        numel(res), nProbe);
    fprintf('  %-4s %-18s %-8s %10s %11s %10s\n', ...
        'rank','mask order','yOrigin','resid px','probe cover','probe vox');
    for k = 1:min(6, numel(res))
        if res(k).probed
            fprintf('  %-4d %-18s %-8s %10.2f %11.4f %10d\n', k, ...
                mat2str(res(k).order), res(k).yOrigin, res(k).residPx, ...
                res(k).coverage, res(k).nOcc);
        else
            fprintf('  %-4d %-18s %-8s %10.2f %11s %10s\n', k, ...
                mat2str(res(k).order), res(k).yOrigin, res(k).residPx, ...
                'not probed', '-');
        end
    end

    fprintf('\n  chosen: mask order %s, yOrigin ''%s''\n', ...
        mat2str(R.camOrder), R.yOrigin);
    fprintf('  centroid (%.2f, %.2f, %.2f) mm, centroid residual %.2f px, ', ...
        R.XYZ, R.residPx);
    fprintf('probe coverage %.4f\n', R.coverage);

    if R.coverage < 0.7
        warning('vh:resolveSetup:lowCoverage', ...
            ['Best probe coverage is only %.3f. The calibration may not ' ...
             'match these masks, or they may not be the same instant.'], ...
            R.coverage);
    end
    if numel(res) > 1 && res(2).probed && ...
            (res(1).coverage - res(2).coverage) < 0.02
        warning('vh:resolveSetup:ambiguous', ...
            ['Runner-up (%s, %s) scores %.4f against the winner''s %.4f - ' ...
             'too close to separate. Check the reprojection overlays, and ' ...
             'set cfg.camOrder / cfg.yOrigin by hand if you know them.'], ...
            mat2str(res(2).order), res(2).yOrigin, res(2).coverage, ...
            res(1).coverage);
    end
end
end


function rad = probeVoxelRadius(Pk, XYZ, g, imgH, yOrigin, dsScale)
%PROBEVOXELRADIUS How many pixels one probe voxel spans in this view.
d = [mean(diff(g.x)) mean(diff(g.y)) mean(diff(g.z))];
[c0, r0] = vh.project(Pk, XYZ, imgH, yOrigin);
px = 0;
for a = 1:3
    step = zeros(1,3);  step(a) = d(a);
    [c1, r1] = vh.project(Pk, XYZ + step, imgH, yOrigin);
    px = max(px, hypot(c1-c0, r1-r0));
end
rad = ceil(px * dsScale / 2) + 1;
if ~isfinite(rad), rad = 2; end
rad = min(30, max(1, rad));
end

