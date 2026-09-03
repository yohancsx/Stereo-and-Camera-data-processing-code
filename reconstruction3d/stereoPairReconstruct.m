function out = stereoPairReconstruct(cfg)
%STEREOCRAB Stereo reconstruction of the crab from the two close camera pairs.
%
%   out = stereoCrab            prompts for files
%   out = stereoCrab(cfg)       runs with the given settings
%   cfg = stereoCrab('defaults')
%
%   WHY STEREO RATHER THAN A HULL
%   The four cameras sit in two tight pairs about 160 deg apart. That is
%   nearly the worst case for a visual hull - two viewing directions along
%   one line cannot carve depth, so the hull stretches along the camera
%   axis. It is a perfectly ordinary case for stereo: each pair has a ~12
%   deg convergence, which is a normal stereo baseline, and the two pairs
%   look at opposite sides, so together they sample the front and the back
%   of the animal.
%
%   PIPELINE
%     1. read the DLT coefficients and UNDISTORT both the masks and the
%        texture images into the virtual pinhole camera the wand points
%        were undistorted into
%     2. seed a working volume by triangulating the silhouette centroids
%     3. per pair: fundamental matrix straight from the two DLT matrices,
%        rectify, match (SGM / BM / features), un-rectify
%     4. triangulate the matches with the DLT and filter on reprojection
%     5. merge the two pairs and report
%
%   The rectification exists only to let a block matcher assume that
%   corresponding pixels share a row. Every 3-D point is triangulated from
%   original image coordinates with the DLT, so the badly conditioned
%   intrinsics the DLT implies never enter the reconstruction.
%
%   KEY SETTINGS
%     cfg.dataDir     folder holding *_mask.png, *_seg.png, the DLT csv and
%                     the fisheye .mat
%     cfg.camOrder    permutation mapping DLT columns to mask files
%     cfg.pairs       DLT column pairs to run, one per row
%     cfg.yOrigin     'auto' | 'top' | 'bottom'
%     cfg.methods     any of {'sgm','bm','features'}
%
%   Yohan Sequeira - Crab Visual Hull Analysis

%% ------------------------------------------------------------- DEFAULTS

d = struct( ...
    'dataDir',     '', ...
    'maskFiles',   {{}}, ...
    'imageFiles',  {{}}, ...
    'dltFile',     '', ...
    'calibFile',   '', ...
    'camOrder',    [4 1 3 2], ...
    'pairs',       [], ...        % [] = find the two closest pairs
    'yOrigin',     'top', ...
    'boxPadFactor', 1.6, ...
    'rectifyFromData', true, ...
    'methods',     {{'sgm','bm','features'}}, ...
    'subsample',   2, ...
    'maxResidPx',  4, ...
    'rectMaxDim',  2400, ...
    'undistortScale', 1, ...
    'units',       'wu', ...
    'saveResults', true, ...
    'outDir',      '', ...
    'verbose',     true);

if nargin == 1 && (ischar(cfg) || isstring(cfg)) && strcmpi(cfg,'defaults')
    out = d;  return
end
if nargin < 1, cfg = struct(); end
fn = fieldnames(d);
for k = 1:numel(fn)
    if ~isfield(cfg, fn{k}), cfg.(fn{k}) = d.(fn{k}); end
end
% Accept "double-quoted" strings as well as 'char' for every path field.
for k = {'dataDir','dltFile','calibFile','outDir','yOrigin','units'}
    if isstring(cfg.(k{1})), cfg.(k{1}) = char(cfg.(k{1})); end
end

thisDir = fileparts(mfilename('fullpath'));
if isempty(thisDir), thisDir = pwd; end
addpath(thisDir);

%% ---------------------------------------------------------------- INPUTS

if isempty(cfg.maskFiles)
    if isempty(cfg.dataDir)
        cfg.dataDir = uigetdir(thisDir, 'Folder with the masks, seg images, DLT and calibration');
        if isequal(cfg.dataDir, 0), out = []; return, end
    end
    m = dir(fullfile(cfg.dataDir, '*_mask.png'));
    s = dir(fullfile(cfg.dataDir, '*_seg.png'));
    c = [dir(fullfile(cfg.dataDir,'*dlt*.csv')); dir(fullfile(cfg.dataDir,'*DLT*.csv'))];
    p = dir(fullfile(cfg.dataDir, '*.mat'));
    assert(~isempty(m), 'stereoCrab:noMasks', 'No *_mask.png in %s', cfg.dataDir);
    assert(numel(s) == numel(m), 'stereoCrab:noImages', ...
        ['Found %d mask(s) but %d *_seg.png. Stereo needs the texture ' ...
         'images, one per camera.'], numel(m), numel(s));
    cfg.maskFiles  = fullfile(cfg.dataDir, {m.name}');
    cfg.imageFiles = fullfile(cfg.dataDir, {s.name}');
    if isempty(cfg.dltFile),   cfg.dltFile   = fullfile(cfg.dataDir, c(1).name); end
    if isempty(cfg.calibFile), cfg.calibFile = fullfile(cfg.dataDir, p(1).name); end
end
if isempty(cfg.outDir)
    cfg.outDir = fullfile(fileparts(cfg.maskFiles{1}), 'stereo');
end

fprintf('\n============================================================\n');
fprintf('  stereoCrab\n');
fprintf('============================================================\n');

%% --------------------------------------------------- 1. CALIBRATION + VIEWS

[P, ~, camC] = vh.readDLT(cfg.dltFile);
nCams = size(P,3);
assert(numel(cfg.maskFiles) == nCams, 'stereoCrab:count', ...
    'DLT has %d cameras but %d masks were given.', nCams, numel(cfg.maskFiles));

M = vh.loadMasks(cfg.maskFiles, cfg.calibFile, ...
    'imageFiles', cfg.imageFiles, 'scaleFactor', cfg.undistortScale, ...
    'verbose', cfg.verbose);
M = M(cfg.camOrder);                      % index k now means DLT column k

fprintf('\n  camera pairing in use\n');
for k = 1:nCams
    [~,n1,e1] = fileparts(M(k).file);
    fprintf('  DLT %d  <-  %s%s\n', k, n1, e1);
end

%% --------------------------------------------- 2. WORKING VOLUME + y ORIGIN

yOrigin = cfg.yOrigin;
if strcmpi(yOrigin, 'auto')
    Rs = vh.resolveSetup(P, M, 'camOrder', 1:nCams, 'yOrigin', 'auto', ...
        'verbose', false);
    yOrigin = Rs.yOrigin;
    XYZ0 = Rs.XYZ;
    fprintf('\n  y convention resolved from the data: ''%s''\n', yOrigin);
else
    cen = zeros(nCams,2);
    for k = 1:nCams
        [r,c] = ind2sub([M(k).H M(k).W], find(M(k).mask));
        cen(k,:) = [mean(c) mean(r)];
    end
    uv = zeros(nCams,2);
    for k = 1:nCams, uv(k,:) = vh.imageToDLT(cen(k,:), M(k).H, yOrigin); end
    XYZ0 = vh.triangulate(P, uv);
end
objSize = vh.objectScale(P, M, XYZ0, yOrigin);
box = struct('centre', XYZ0, 'half', max(objSize * cfg.boxPadFactor/2, eps));
fprintf('  working volume: centre (%.3f %.3f %.3f) %s, half-width %.3f %s\n', ...
    box.centre, cfg.units, box.half, cfg.units);

%% ------------------------------------------------------------ 3. THE PAIRS

if isempty(cfg.pairs)
    dmat = inf(nCams);
    for a = 1:nCams
        for b = a+1:nCams
            dmat(a,b) = norm(camC(:,a) - camC(:,b));
        end
    end
    [~, ord] = sort(dmat(:));
    cfg.pairs = zeros(0,2);
    used = false(1,nCams);
    for t = ord.'
        [a,b] = ind2sub([nCams nCams], t);
        if ~isfinite(dmat(a,b)), break, end
        if used(a) || used(b), continue, end
        cfg.pairs(end+1,:) = [a b];
        used([a b]) = true;
    end
end

fprintf('\n  stereo pairs (DLT columns), by camera separation\n');
for q = 1:size(cfg.pairs,1)
    a = cfg.pairs(q,1);  b = cfg.pairs(q,2);
    base = norm(camC(:,a) - camC(:,b));
    va = camC(:,a) - box.centre.';  vb = camC(:,b) - box.centre.';
    conv = acosd(max(-1,min(1, dot(va,vb)/(norm(va)*norm(vb)))));
    depth = mean([norm(va) norm(vb)]);
    fprintf(['  pair %d: DLT %d + %d   baseline %.3f %s   convergence %.1f deg' ...
             '   depth %.2f %s   B/Z %.3f\n'], q, a, b, base, cfg.units, ...
             conv, depth, cfg.units, base/depth);
end

%% ------------------------------------------------- 4. RECTIFY, MATCH, BUILD

pairsOut = struct('idx',{},'rect',{},'matches',{},'clouds',{},'audit',{}, ...
                  'rectData',{},'matchesData',{},'cloudsData',{});

for q = 1:size(cfg.pairs,1)
    a = cfg.pairs(q,1);  b = cfg.pairs(q,2);
    fprintf('\n---- pair %d: DLT %d + %d ----\n', q, a, b);

    Sp = vh.rectifyPair(P(:,:,a), P(:,:,b), M(a), M(b), box, yOrigin, ...
        'maxDim', cfg.rectMaxDim, 'verbose', cfg.verbose);

    [matches, clouds] = runMethods(Sp, cfg, P(:,:,a), P(:,:,b), M(a), M(b), ...
        yOrigin, box);

    % ---- attribute any epipolar error, and if the DLT is at fault, redo
    % ---- the rectification on an F fitted to the images themselves.
    audit = struct('verdict','not run');
    Sd = [];  matchesD = struct([]);  cloudsD = struct([]);
    fi = find(strcmpi({matches.name}, 'features'), 1);
    if ~isempty(fi) && size(matches(fi).q1All,1) >= 8
        o1 = unrect(matches(fi).q1All, Sp.ref1, Sp.tform1);
        o2 = unrect(matches(fi).q2All, Sp.ref2, Sp.tform2);
        fprintf('\n');
        audit = vh.epipolarAudit(Sp.Fdlt, o1, o2, 'verbose', cfg.verbose);

        if cfg.rectifyFromData && ~isempty(audit.Fdata) && ...
                any(strcmp(audit.verdict, {'calibration','both'})) && ...
                nnz(audit.inliers) >= 8
            fprintf(['\n    re-rectifying on the data-driven F, so the ' ...
                'matcher searches the\n    real epipolar lines. 3-D points ' ...
                'are still triangulated with the DLT.\n']);
            corr = [o1(audit.inliers,:) o2(audit.inliers,:)];
            ws = warning('off','vision:calibrate:epipoleInImage');
            Sd = vh.rectifyPair(P(:,:,a), P(:,:,b), M(a), M(b), box, yOrigin, ...
                'maxDim', cfg.rectMaxDim, 'F', audit.Fdata, 'corr', corr, ...
                'verbose', cfg.verbose);
            warning(ws);

            % An F fitted to a few dozen points all sitting on one small
            % object is under-constrained: the rectification it implies can
            % put an epipole inside the frame and collapse the warp. Check
            % the transform on its own inliers before believing it.
            bad = Sd.checks.rectRowErrPx > 2 || Sd.scale < 0.2 || ...
                  ~isfinite(Sd.checks.absDisparityPx);
            if bad
                fprintf(['    [!] that rectification is degenerate (row ' ...
                    'error %.1f px on its own\n        inliers, scale ' ...
                    '%.3f). %d correspondences confined to the animal ' ...
                    'cannot\n        constrain F. Discarding this route.\n'], ...
                    Sd.checks.rectRowErrPx, Sd.scale, size(corr,1));
                Sd = [];
            else
                [matchesD, cloudsD] = runMethods(Sd, cfg, P(:,:,a), P(:,:,b), ...
                    M(a), M(b), yOrigin, box);
            end
        end
    end

    pairsOut(q) = struct('idx', [a b], 'rect', Sp, 'matches', matches, ...
        'clouds', clouds, 'audit', audit, 'rectData', Sd, ...
        'matchesData', matchesD, 'cloudsData', cloudsD);
end

%% ------------------------------------------------------------- 5. REPORT

fprintf('\n============================ SUMMARY ============================\n');
fprintf('%-6s %-9s %9s %9s %11s %12s %12s\n', ...
    'pair','method','matches','3D pts','med reproj','row err px','extent (wu)');
for q = 1:numel(pairsOut)
    for mi = 1:numel(pairsOut(q).matches)
        Rm = pairsOut(q).matches(mi);  Cm = pairsOut(q).clouds(mi);
        ext = '-';
        if Cm.n > 3
            ext = sprintf('%.2f', max(range(Cm.XYZ,1)));
        end
        mr = '-';
        if Cm.n > 0, mr = sprintf('%.2f', median(Cm.residPx)); end
        fprintf('%-6d %-9s %9d %9d %11s %12.2f %12s\n', q, Rm.name, Rm.n, ...
            Cm.n, mr, Rm.rowErr, ext);
    end
end

% Two dense methods on the same rectified pair should agree closely. When
% they do not, the matches are being driven by the search geometry rather
% than by the images, and neither result can be trusted.
for q = 1:numel(pairsOut)
    ex = nan(1, numel(pairsOut(q).clouds));
    for mi = 1:numel(pairsOut(q).clouds)
        if pairsOut(q).clouds(mi).n > 3 && ...
                any(strcmpi(pairsOut(q).matches(mi).name, {'sgm','bm'}))
            ex(mi) = max(range(pairsOut(q).clouds(mi).XYZ, 1));
        end
    end
    ex = ex(isfinite(ex));
    if numel(ex) >= 2 && max(ex)/min(ex) > 1.5
        fprintf(['\n  [!] pair %d: the dense methods disagree on the extent ' ...
            'by %.1fx (%.2f vs %.2f %s).\n      Two matchers on the same ' ...
            'rectified pair should agree. They do not, which\n      means ' ...
            'the matches are following the search geometry, not the ' ...
            'images.\n'], q, max(ex)/min(ex), min(ex), max(ex), cfg.units);
    end
end

% Results from the data-driven rectification, where it ran.
anyData = false;
for q = 1:numel(pairsOut)
    if isempty(pairsOut(q).matchesData), continue, end
    if ~anyData
        fprintf('\n  same, rectified on an F fitted to the images\n');
        fprintf('%-6s %-9s %9s %9s %11s %12s\n', ...
            'pair','method','matches','3D pts','med reproj','extent (wu)');
        anyData = true;
    end
    for mi = 1:numel(pairsOut(q).matchesData)
        Rm = pairsOut(q).matchesData(mi);  Cm = pairsOut(q).cloudsData(mi);
        ext = '-';  mr = '-';
        if Cm.n > 3, ext = sprintf('%.2f', max(range(Cm.XYZ,1))); end
        if Cm.n > 0, mr  = sprintf('%.2f', median(Cm.residPx)); end
        fprintf('%-6d %-9s %9d %9d %11s %12s\n', q, Rm.name, Rm.n, Cm.n, mr, ext);
    end
end
if anyData
    fprintf(['\n  Note the reprojection residual is meaningful in this ' ...
        'table and not in the\n  one above: matches found on the DLT''s own ' ...
        'epipolar lines always triangulate\n  to near-zero residual whether ' ...
        'they are right or wrong.\n']);
end

% Epipolar error from unconstrained feature matches is the calibration test.
fprintf('\n  epipolar agreement (unconstrained feature matches)\n');
for q = 1:numel(pairsOut)
    for mi = 1:numel(pairsOut(q).matches)
        Rm = pairsOut(q).matches(mi);
        if ~strcmpi(Rm.name,'features') || isempty(Rm.rowErrAll), continue, end
        e = Rm.rowErrAll;
        fprintf(['  pair %d: %d matches, |y1-y2| median %.1f px, ' ...
                 '75th %.1f, 90th %.1f'], q, numel(e), median(e), ...
                 prctile_(e,75), prctile_(e,90));
        A = pairsOut(q).audit;
        if isstruct(A) && isfield(A,'verdict')
            fprintf('   verdict: %s', A.verdict);
        end
        fprintf('\n');
        if median(e) > 5
            fprintf(['          [!] corresponding points do not share a row ' ...
                'under the DLT''s\n              epipolar geometry.\n']);
        end
    end
end

%% ------------------------------------------------------------- 6. FIGURES

vh.stereoReport(pairsOut, camC, box, cfg);

%% -------------------------------------------------------------- 7. OUTPUT

out = struct('cfg', cfg, 'P', P, 'cameraCentres', camC, 'views', M, ...
    'yOrigin', yOrigin, 'box', box, 'pairs', pairsOut, ...
    'createdOn', datetime('now'));

if cfg.saveResults
    if ~exist(cfg.outDir,'dir'), mkdir(cfg.outDir); end
    stem = fullfile(cfg.outDir, ['stereo_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
    slim = out;  slim.views = rmfield(M, {'raw','mask','rgb','rgbRaw'});
    for q = 1:numel(slim.pairs)
        slim.pairs(q).rect = rmfield(slim.pairs(q).rect, ...
            intersect(fieldnames(slim.pairs(q).rect), ...
                      {'Irgb1','Irgb2','I1','I2','K1','K2'}));
    end
    save([stem '.mat'], 'slim', '-v7.3');
    fprintf('\n  saved -> %s.mat\n', stem);
end

fprintf('\nDone.\n');
end


function [matches, clouds] = runMethods(S, cfg, Pa, Pb, Ma, Mb, yOrigin, box)
matches = struct([]);  clouds = struct([]);
fprintf('\n    matching (%s rectification)\n', S.source);
for mi = 1:numel(cfg.methods)
    Rm = vh.stereoMatch(S, cfg.methods{mi}, ...
        'subsample', cfg.subsample, 'verbose', cfg.verbose);
    Cm = vh.reconstructMatches(S, Rm, Pa, Pb, Ma, Mb, yOrigin, ...
        'maxResidPx', cfg.maxResidPx, 'box', box, 'verbose', cfg.verbose);
    if isempty(matches), matches = Rm;  clouds = Cm;
    else,                matches(end+1) = Rm;  clouds(end+1) = Cm; end %#ok<AGROW>
end
end


function p = unrect(pRect, ref, tform)
[xw, yw] = intrinsicToWorld(ref, pRect(:,1), pRect(:,2));
p = transformPointsInverse(tform, [xw yw]);
end


function q = prctile_(x, p)
x = sort(x(:));  n = numel(x);
if n == 0, q = NaN; return, end
if n == 1, q = x;   return, end
i = max(1, min(n, (p/100)*(n-1)+1));
lo = floor(i); hi = ceil(i);
q = x(lo) + (i-lo)*(x(hi)-x(lo));
end


