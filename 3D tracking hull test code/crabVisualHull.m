function out = crabVisualHull(cfg)
%CRABVISUALHULL Visual hull of a crab from n thresholded silhouettes.
%
%   out = crabVisualHull            prompts for masks, DLT csv, calibrations
%   out = crabVisualHull(cfg)       runs with the given settings
%   cfg = crabVisualHull('defaults')  returns the default settings to edit
%
%   PIPELINE
%     1. read DLT-11 coefficients (11 rows x nCams columns)
%     2. read the thresholded masks and UNDISTORT them, so they live in the
%        same virtual pinhole camera the wand points were undistorted into
%     3. work out which mask belongs to which DLT column, and whether the
%        DLT y axis runs up from the bottom - both by measurement
%     4. seed a voxel box on the triangulated centroid
%     5. carve coarse, shrink to what was occupied, carve fine
%     6. mesh, measure, and reproject the hull back into every camera to
%        check it against the input silhouettes
%
%   Units are whatever the wand length was given in. For this project that
%   is mm, so volumes come out in mm^3.
%
%   KEY SETTINGS
%     cfg.maskFiles     nCams mask images ({} to be prompted)
%     cfg.dltFile       DLT coefficient csv ('' to be prompted)
%     cfg.calibFiles    .mat camera parameters, one per camera or one for
%                       all ({} to be prompted, or 'none' to skip)
%     cfg.camOrder      [] to resolve automatically, or a fixed permutation
%                       mapping DLT columns to mask files
%     cfg.yOrigin       'auto' | 'bottom' (DLT convention) | 'top'
%     cfg.objectSize    object size in WORLD units (whatever the wand
%                       length was given in). [] estimates it from the
%                       silhouettes, which is unit-agnostic and usually
%                       what you want - see vh.objectScale.
%     cfg.boxPadFactor  box half-width = objectSize * boxPadFactor / 2
%     cfg.coarseN       coarse pass resolution per axis
%     cfg.fineN         fine pass resolution per axis
%     cfg.minCams       occupancy threshold; [] means all cameras (strict)
%
%   Yohan Sequeira - Crab Visual Hull Analysis

%% ------------------------------------------------------------- DEFAULTS

d = struct( ...
    'maskFiles',       {{}}, ...
    'dltFile',         '', ...
    'calibFiles',      {{}}, ...
    'camOrder',        [4 1 3 2], ...
    'yOrigin',         'auto', ...
    'objectSize',      [], ...
    'boxPadFactor',    1.6, ...
    'coarseN',         64, ...
    'fineN',           200, ...
    'probeN',          40, ...
    'maxProbe',        8, ...
    'minCams',         [], ...
    'undistortScale',  1, ...
    'chunk',           2e6, ...
    'smoothMesh',      true, ...
    'reduceFaces',     0, ...
    'units',           'mm', ...
    'outDir',          '', ...
    'saveResults',     true, ...
    'verbose',         true);

if nargin == 1 && (ischar(cfg) || isstring(cfg)) && strcmpi(cfg, 'defaults')
    out = d;  return
end
if nargin < 1, cfg = struct(); end
cfg = mergeDefaults(cfg, d);

thisDir = fileparts(mfilename('fullpath'));
if isempty(thisDir), thisDir = pwd; end
addpath(thisDir);                        % so the +vh package is visible

%% ---------------------------------------------------------------- INPUTS

if isempty(cfg.maskFiles)
    [f, p] = uigetfile({'*.png;*.tif;*.tiff;*.bmp;*.jpg', 'Mask images'}, ...
        'Select the thresholded mask for EVERY camera', 'MultiSelect', 'on');
    if isequal(f, 0), out = []; return, end
    if ischar(f), f = {f}; end
    cfg.maskFiles = cellfun(@(x) fullfile(p,x), f, 'UniformOutput', false);
end
cfg.maskFiles = cfg.maskFiles(:);

if isempty(cfg.dltFile)
    [f, p] = uigetfile({'*.csv;*.txt', 'DLT coefficients'}, ...
        'Select the DLT coefficient file (11 rows x nCams columns)');
    if isequal(f, 0), out = []; return, end
    cfg.dltFile = fullfile(p, f);
end

if isempty(cfg.calibFiles)
    [f, p] = uigetfile({'*.mat', 'Camera parameters'}, ...
        ['Select camera fisheye unistortion .mat - one per camera in the SAME ' ...
         'order as the masks, or one file for all (Cancel to skip)'], ...
        'MultiSelect', 'on');
    if isequal(f, 0)
        warning('crabVisualHull:noCalib', ...
            ['No calibration selected. The masks will NOT be undistorted, ' ...
             'which does not match a DLT fitted to undistorted points.']);
        cfg.calibFiles = {};
    else
        if ischar(f), f = {f}; end
        cfg.calibFiles = cellfun(@(x) fullfile(p,x), f, 'UniformOutput', false);
    end
elseif (ischar(cfg.calibFiles) || isstring(cfg.calibFiles)) && ...
        strcmpi(cfg.calibFiles, 'none')
    cfg.calibFiles = {};
end

if isempty(cfg.outDir)
    cfg.outDir = fullfile(fileparts(cfg.maskFiles{1}), 'hull');
end

%% ------------------------------------------------------------------- RUN

fprintf('\n============================================================\n');
fprintf('  crabVisualHull\n');
fprintf('============================================================\n');

% --- 1. calibration -------------------------------------------------------
[P, L, camC] = vh.readDLT(cfg.dltFile);
nCams = size(P, 3);
assert(numel(cfg.maskFiles) == nCams, 'crabVisualHull:count', ...
    'The DLT file has %d camera(s) but %d mask(s) were given.', ...
    nCams, numel(cfg.maskFiles));

% --- 2. masks, undistorted -----------------------------------------------
M = vh.loadMasks(cfg.maskFiles, cfg.calibFiles, ...
    'scaleFactor', cfg.undistortScale, 'verbose', cfg.verbose);

% --- 3. pairing and y convention -----------------------------------------
R = vh.resolveSetup(P, M, 'camOrder', cfg.camOrder, ...
    'yOrigin', cfg.yOrigin, 'objectSize', cfg.objectSize, ...
    'boxPadFactor', cfg.boxPadFactor, 'probeN', cfg.probeN, ...
    'maxProbe', cfg.maxProbe, 'verbose', cfg.verbose);

% Reorder the masks so index k means "DLT column k" from here on.
M = M(R.camOrder);
yOrigin = R.yOrigin;

fprintf('\n  camera pairing in use\n');
fprintf('  %-4s %-8s %-38s %s\n', 'DLT', 'mask#', 'mask file', 'size (WxH)');
for k = 1:nCams
    fprintf('  %-4d %-8d %-38s %d x %d\n', k, R.camOrder(k), ...
        shortName(M(k).file), M(k).W, M(k).H);
end

% Cheirality reference: the centroid is definitely in front of every camera,
% so the sign of its homogeneous denominator is the "in front" sign.
wSign = zeros(nCams,1);
for k = 1:nCams
    [~, ~, w] = vh.project(P(:,:,k), R.XYZ, M(k).H, yOrigin);
    wSign(k) = sign(w);
end

% --- 3b. rig geometry, and a sanity check on the world scale -------------
[estSize, perCamSize, pxPerUnit] = vh.objectScale(P, M, R.XYZ, yOrigin);
camDist = vecnorm(camC(:, R.camOrder) - R.XYZ.');
viewDir = (camC(:, R.camOrder) - R.XYZ.') ./ camDist;
maxSep = 0;  seps = [];
for a = 1:nCams
    for b = a+1:nCams
        s = acosd(max(-1, min(1, dot(viewDir(:,a), viewDir(:,b)))));
        seps(end+1) = s;  maxSep = max(maxSep, s);           %#ok<AGROW>
    end
end

fprintf('\n  rig geometry, measured from the data\n');
fprintf('  %-4s %14s %16s %14s\n', 'cam', 'dist to object', 'px per world unit', 'object looks');
for k = 1:nCams
    fprintf('  %-4d %14.3f %16.1f %14.3f %s\n', k, camDist(k), pxPerUnit(k), ...
        perCamSize(k), cfg.units);
end
fprintf('  object size used for the box: %.3f %s', estSize, cfg.units);
if isempty(cfg.objectSize)
    fprintf('  (estimated from the silhouettes)\n');
else
    fprintf('  (from cfg.objectSize)\n');
end
fprintf('  camera view directions differ by %.0f to %.0f deg (max %.0f)\n', ...
    min(seps), max(seps), maxSep);

% Does each DLT column describe a camera that could actually exist? An
% undistorted frame has its principal point exactly at the image centre and
% fx == fy exactly, so a healthy DLT must reproduce that.
T = vh.dltIntrinsics(P(:,:,1:nCams));
T = T(:);
fprintf('\n  DLT conditioning  (each column decomposed back to a camera)\n');
fprintf('  %-4s %10s %10s %9s %14s %14s\n', ...
    'cam','fx','fy','fy/fx','cx off centre','cy off centre');
dCx = zeros(nCams,1);  dAsp = zeros(nCams,1);
for k = 1:nCams
    ecx = (M(k).W + 1)/2;  ecy = (M(k).H + 1)/2;
    dCx(k)  = max(abs(T(k).cx - ecx), abs(T(k).cy - ecy));
    dAsp(k) = abs(T(k).aspect - 1);
    fprintf('  %-4d %10.1f %10.1f %9.4f %14.1f %14.1f\n', k, ...
        T(k).fx, T(k).fy, T(k).aspect, T(k).cx - ecx, T(k).cy - ecy);
end
fprintf('  expected: fy/fx = 1.0000 and both offsets 0, for undistorted frames\n');
if max(dCx) > 0.05*mean([M.W]) || max(dAsp) > 0.02
    fprintf(['  [!] these coefficients do not describe a physically ' ...
        'consistent camera:\n      principal point off by up to %.0f px, ' ...
        'aspect off by up to %.1f%%.\n      The wand calibration is poorly ' ...
        'conditioned. Silhouette coverage below\n      will be capped by ' ...
        'this no matter what else is correct.\n'], max(dCx), 100*max(dAsp));
end
if maxSep < 60
    fprintf(['  [!] all cameras look from nearly the same direction. The ' ...
        'hull will be badly\n      elongated along the viewing axis - ' ...
        'that is a rig limitation, not a bug.\n']);
end
if std(perCamSize)/mean(perCamSize) > 0.25
    fprintf(['  [!] the cameras disagree about how big the object is ' ...
        '(spread %.0f%%).\n      That points at the calibration or the ' ...
        'camera pairing.\n'], 100*std(perCamSize)/mean(perCamSize));
end

% --- 4. voxel box --------------------------------------------------------
if isempty(cfg.objectSize), objSize = estSize; else, objSize = cfg.objectSize; end
half = objSize * cfg.boxPadFactor / 2;
lo = R.XYZ - half;  hi = R.XYZ + half;
fprintf('\n  seed box: centre (%.3f %.3f %.3f) %s, half-width %.3f %s\n', ...
    R.XYZ, cfg.units, half, cfg.units);

if isempty(cfg.minCams), minCams = nCams; else, minCams = cfg.minCams; end

% --- 5a. coarse pass -----------------------------------------------------
fprintf('\n---- coarse pass ----\n');
gC = makeGrid(lo, hi, cfg.coarseN);
cntC = vh.carve(P, M, gC, yOrigin, 'wSign', wSign, ...
    'chunk', cfg.chunk, 'verbose', cfg.verbose);

occC = cntC >= minCams;
if ~any(occC(:))
    fprintf('\n  no voxel seen by all %d cameras; retrying at %d\n', ...
        nCams, nCams-1);
    minCams = nCams - 1;
    occC = cntC >= minCams;
end
assert(any(occC(:)), 'crabVisualHull:emptyCoarse', ...
    ['Nothing was carved. Check the reprojection overlays: most likely ' ...
     'the box misses the animal (raise objectSize / boxPadFactor), the ' ...
     'camera pairing is wrong, or the masks are not the same instant.']);

% Shrink to what was actually occupied, with a two-voxel margin.
[ix, iy, iz] = ind2sub(size(occC), find(occC));
pad = 2 * [mean(diff(gC.x)) mean(diff(gC.y)) mean(diff(gC.z))];
lo2 = [gC.x(min(ix)) gC.y(min(iy)) gC.z(min(iz))] - pad;
hi2 = [gC.x(max(ix)) gC.y(max(iy)) gC.z(max(iz))] + pad;
fprintf('  occupied %d / %d coarse voxels -> refining in a %.3f x %.3f x %.3f %s box\n', ...
    nnz(occC), numel(occC), hi2-lo2, cfg.units);

% A handful of coarse voxels means the coarse grid barely resolved the
% object, so the box it hands to the fine pass cannot be trusted. Redo the
% coarse pass finer rather than refining inside a bad box.
if nnz(occC) < 150 && cfg.coarseN < 160
    fprintf(['  [!] only %d coarse voxels occupied - the coarse grid is too ' ...
        'coarse for this\n      object. Repeating the coarse pass at %d.\n'], ...
        nnz(occC), 2*cfg.coarseN);
    gC = makeGrid(lo, hi, 2*cfg.coarseN);
    cntC = vh.carve(P, M, gC, yOrigin, 'wSign', wSign, ...
        'chunk', cfg.chunk, 'verbose', cfg.verbose);
    occC = cntC >= minCams;
    assert(any(occC(:)), 'crabVisualHull:emptyCoarse2', ...
        'Still nothing carved after refining the coarse pass.');
    [ix, iy, iz] = ind2sub(size(occC), find(occC));
    pad = 2 * [mean(diff(gC.x)) mean(diff(gC.y)) mean(diff(gC.z))];
    lo2 = [gC.x(min(ix)) gC.y(min(iy)) gC.z(min(iz))] - pad;
    hi2 = [gC.x(max(ix)) gC.y(max(iy)) gC.z(max(iz))] + pad;
    fprintf('  occupied %d / %d -> refining in a %.3f x %.3f x %.3f %s box\n', ...
        nnz(occC), numel(occC), hi2-lo2, cfg.units);
end

% --- 5b. fine pass -------------------------------------------------------
fprintf('\n---- fine pass ----\n');
gF = makeGrid(lo2, hi2, cfg.fineN);
cntF = vh.carve(P, M, gF, yOrigin, 'wSign', wSign, ...
    'chunk', cfg.chunk, 'verbose', cfg.verbose);

% --- 6. mesh and measure -------------------------------------------------
H = vh.buildMesh(cntF, gF, minCams, ...
    'smooth', cfg.smoothMesh, 'reduceFaces', cfg.reduceFaces);

fprintf('\n============================ RESULT ============================\n');
fprintf('  occupancy rule      : voxel seen by >= %d of %d cameras\n', ...
    minCams, nCams);
fprintf('  occupied voxels     : %d of %d\n', H.nOccupied, numel(cntF));
fprintf('  voxel size          : %.4f x %.4f x %.4f %s\n', H.voxelSize, cfg.units);
fprintf('  hull volume (voxel) : %.1f %s^3\n', H.volumeVoxel, cfg.units);
fprintf('  hull volume (mesh)  : %.1f %s^3\n', H.volumeMesh, cfg.units);
fprintf('  centroid            : (%.2f, %.2f, %.2f) %s\n', H.centroid, cfg.units);
fprintf('  principal extents   : %.2f, %.2f, %.2f %s\n', ...
    H.principalExtent, cfg.units);
fprintf(['\n  Remember a %d-camera visual hull OVERESTIMATES a limbed body:\n' ...
         '  concavities between the legs cannot be carved away. Treat this\n' ...
         '  as an upper bound unless you have characterised the bias.\n'], nCams);

% --- 7. validation figures ----------------------------------------------
Vld = vh.report(P, M, H, gF, yOrigin, 'units', cfg.units, ...
    'cameraCentres', camC(:, R.camOrder));

%% ---------------------------------------------------------------- OUTPUT

out = struct('cfg', cfg, 'P', P, 'L', L, 'cameraCentres', camC, ...
    'camOrder', R.camOrder, 'yOrigin', yOrigin, 'setup', R, ...
    'masks', {{M.file}'}, 'minCams', minCams, ...
    'gridCoarse', gC, 'countCoarse', cntC, ...
    'grid', gF, 'count', cntF, 'hull', H, 'validation', Vld, ...
    'units', cfg.units, 'createdOn', datetime('now'));

if cfg.saveResults
    if ~exist(cfg.outDir, 'dir'), mkdir(cfg.outDir); end
    stem = fullfile(cfg.outDir, ['hull_' datestr(now, 'yyyymmdd_HHMMSS')]); %#ok<TNOW1,DATST>

    save([stem '.mat'], 'out', '-v7.3');
    if ~isempty(H.faces)
        try
            stlwrite(triangulation(H.faces, H.vertices), [stem '.stl']);
        catch ME
            warning('crabVisualHull:stl', 'STL export failed: %s', ME.message);
        end
    end
    fprintf('\n  saved -> %s.mat\n', stem);
    if isfile([stem '.stl']), fprintf('  saved -> %s.stl\n', stem); end
end

fprintf('\nDone.\n');
end


%% ----------------------------------------------------------- LOCAL HELPERS

function g = makeGrid(lo, hi, n)
g = struct('x', linspace(lo(1), hi(1), n), ...
           'y', linspace(lo(2), hi(2), n), ...
           'z', linspace(lo(3), hi(3), n));
end


function c = mergeDefaults(c, d)
fn = fieldnames(d);
for k = 1:numel(fn)
    if ~isfield(c, fn{k}) || isempty(c.(fn{k}))
        if ~isfield(c, fn{k}), c.(fn{k}) = d.(fn{k}); end
    end
end
extra = setdiff(fieldnames(c), fn);
if ~isempty(extra)
    warning('crabVisualHull:unknownFields', ...
        'Ignoring unknown cfg field(s): %s', strjoin(extra', ', '));
end
end


function s = shortName(f)
[~, n, e] = fileparts(f);
s = [n e];
if numel(s) > 38, s = ['..' s(end-35:end)]; end
end

