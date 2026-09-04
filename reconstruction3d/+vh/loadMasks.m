function M = loadMasks(maskFiles, calibFiles, opts)
%VH.LOADMASKS Read binary silhouettes and undistort them for the hull.
%
%   M = vh.loadMasks(maskFiles, calibFiles, opts)
%
%   maskFiles   cell array of nCams image paths (logical PNG, greyscale or
%               RGB; anything non-zero counts as object)
%   calibFiles  cell array of nCams .mat paths, OR a single path used for
%               every camera, OR {} for no undistortion
%   opts        .scaleFactor  passed to undistortFisheyePoints/Image
%               .verbose
%
%   M(i)  .file .calibFile .kind .raw .mask .H .W .H0 .W0 .intrinsics
%
%   WHY THIS IS THE CRITICAL STEP
%   The DLT is a linear pinhole model, so it only describes the UNDISTORTED
%   image. The wand points were undistorted before easyWand solved for the
%   coefficients, so the silhouettes must be undistorted the same way and
%   land in the same virtual pinhole camera.
%
%   Verified on this MATLAB install: with OutputView 'same' and a matching
%   ScaleFactor, undistortFisheyePoints and undistortFisheyeImage produce
%   IDENTICAL virtual intrinsics (focal and principal-point differences
%   0.000000). That equality is re-checked at run time below and raises a
%   warning if it ever stops holding - a mismatch there would silently
%   invalidate every hull.
%
%   OutputView is forced to 'same'. 'full' and 'valid' move the principal
%   point (and 'full' can fail outright on a strong fisheye), which would
%   break the correspondence with the wand points.

arguments
    maskFiles
    calibFiles = {}
    opts.scaleFactor (1,1) double = 1
    opts.verbose (1,1) logical = true
    opts.imageFiles = {}               % optional greyscale/RGB per camera
end

% Accept cell, string array or a single char/string. fullfile() returns a
% STRING ARRAY when any input is a string, so a caller who wrote
% cfg.dataDir = "..." with double quotes lands here with a string array
% rather than a cell - normalise instead of rejecting it.
maskFiles       = toPathCell(maskFiles);
opts.imageFiles = toPathCell(opts.imageFiles);

nCams = numel(maskFiles);
if ~isempty(opts.imageFiles)
    assert(numel(opts.imageFiles) == nCams, 'vh:loadMasks:imageCount', ...
        'Got %d image(s) for %d camera(s).', numel(opts.imageFiles), nCams);
end

% Normalise calibFiles to one entry per camera.
if isempty(calibFiles)
    calibFiles = repmat({''}, nCams, 1);
elseif ischar(calibFiles) || (isstring(calibFiles) && isscalar(calibFiles))
    calibFiles = repmat({char(calibFiles)}, nCams, 1);
elseif isstring(calibFiles)
    calibFiles = cellstr(calibFiles(:));
elseif isscalar(calibFiles)
    calibFiles = repmat(calibFiles(:), nCams, 1);
else
    assert(numel(calibFiles) == nCams, 'vh:loadMasks:calibCount', ...
        'Got %d calibration file(s) for %d camera(s).', ...
        numel(calibFiles), nCams);
    calibFiles = calibFiles(:);
end

M = struct('file',{},'calibFile',{},'kind',{},'raw',{},'mask',{}, ...
           'H',{},'W',{},'H0',{},'W0',{},'intrinsics',{}, ...
           'imageFile',{},'rgb',{},'rgbRaw',{});

if opts.verbose
    fprintf('\nvh.loadMasks:\n');
end

for i = 1:nCams
    f = maskFiles{i};
    assert(isfile(f), 'vh:loadMasks:noFile', 'Mask not found: %s', f);

    raw = toLogical(imread(f));
    assert(any(raw(:)), 'vh:loadMasks:emptyMask', ...
        'Mask %s is empty - nothing to carve with.', f);
    [H0, W0] = size(raw);

    % Optional companion image (texture for stereo). It must be undistorted
    % by exactly the same transform as the mask, or the two disagree.
    rgbRaw = [];
    imgFile = '';
    if ~isempty(opts.imageFiles)
        imgFile = opts.imageFiles{i};
        assert(isfile(imgFile), 'vh:loadMasks:noImage', ...
            'Image not found: %s', imgFile);
        rgbRaw = imread(imgFile);
        assert(isequal(size(rgbRaw,1,2), [H0 W0]), 'vh:loadMasks:imageSize', ...
            'Camera %d: image %s is %dx%d but its mask is %dx%d.', ...
            i, shortName(imgFile), size(rgbRaw,1), size(rgbRaw,2), H0, W0);
    end
    rgbU = rgbRaw;

    if isempty(calibFiles{i})
        kind = 'none';  intr = [];  maskU = raw;
        if opts.verbose
            fprintf('  [%d] %-38s %5d x %5d   NOT UNDISTORTED\n', ...
                i, shortName(f), W0, H0);
        end
    else
        [obj, kind, calSz] = vh.sniffCalib(calibFiles{i});

        % The calibration must belong to this image.
        if ~isempty(calSz) && ~isequal(calSz(:).', [H0 W0])
            error('vh:loadMasks:sizeMismatch', ...
                ['Camera %d: mask %s is %dx%d (HxW) but its calibration ' ...
                 'was made at %dx%d.\nA rotated or resized frame will ' ...
                 'undistort to nonsense.'], ...
                i, shortName(f), H0, W0, calSz(1), calSz(2));
        end

        switch kind
            case 'fisheye'
                [maskU, camI] = vh.undistortFrame(raw, obj, 'fisheye', ...
                    'method', 'nearest', 'scaleFactor', opts.scaleFactor);

                % Re-check that the point path and the image path agree.
                [~, camP] = undistortFisheyePoints([1 1], obj, opts.scaleFactor);
                dF = norm(camP.FocalLength    - camI.FocalLength);
                dP = norm(camP.PrincipalPoint - camI.PrincipalPoint);
                if dF > 1e-6 || dP > 1e-6
                    warning('vh:loadMasks:virtualCameraMismatch', ...
                        ['Camera %d: undistortFisheyePoints and ' ...
                         'undistortFisheyeImage disagree (focal %.4g, ' ...
                         'principal point %.4g). The DLT was fitted to ' ...
                         'undistorted POINTS, so the masks no longer match ' ...
                         'it. Do not trust the hull.'], i, dF, dP);
                end
                intr = camI;
                if ~isempty(rgbRaw)
                    % Bilinear for texture, same transform and output view.
                    rgbU = vh.undistortFrame(rgbRaw, obj, 'fisheye', ...
                        'method', 'linear', 'scaleFactor', opts.scaleFactor);
                end

            case 'standard'
                [maskU, camI] = vh.undistortFrame(raw, obj, 'standard', ...
                    'method', 'nearest');
                intr = camI;
                if ~isempty(rgbRaw)
                    rgbU = vh.undistortFrame(rgbRaw, obj, 'standard', ...
                        'method', 'linear');
                end

            otherwise
                error('vh:loadMasks:badCalib', ...
                    'Unrecognised calibration in %s', calibFiles{i});
        end

        maskU = toLogical(maskU);
        if opts.verbose
            fprintf('  [%d] %-38s %5d x %5d   %-8s f=[%.1f %.1f] pp=[%.1f %.1f]\n', ...
                i, shortName(f), W0, H0, kind, ...
                intr.FocalLength, intr.PrincipalPoint);
        end
    end

    assert(any(maskU(:)), 'vh:loadMasks:emptyAfterUndistort', ...
        'Camera %d: the mask is empty after undistortion.', i);

    [H, W] = size(maskU);
    M(i) = struct('file', f, 'calibFile', calibFiles{i}, 'kind', kind, ...
        'raw', raw, 'mask', maskU, 'H', H, 'W', W, 'H0', H0, 'W0', W0, ...
        'intrinsics', intr, 'imageFile', imgFile, 'rgb', rgbU, ...
        'rgbRaw', rgbRaw);
end

if opts.verbose
    kinds = unique({M.kind});
    if any(strcmp(kinds, 'none'))
        warning('vh:loadMasks:noUndistort', ...
            ['At least one camera was not undistorted. The DLT is a ' ...
             'linear model and will not match a distorted silhouette.']);
    end
end
end

%% ------------------------------------------------------------------ helpers

function c = toPathCell(p)
%TOPATHCELL Cell array of char paths, from cell / string array / char.
if isempty(p)
    c = {};
elseif iscell(p)
    c = cellfun(@char, p(:), 'UniformOutput', false);
elseif isstring(p)
    c = cellstr(p(:));
elseif ischar(p)
    c = {p};
else
    error('vh:loadMasks:badPaths', ...
        'File list must be a cell array, string array or char, got %s.', ...
        class(p));
end
end


function b = toLogical(A)
if islogical(A)
    b = A;
    return
end
if ndims(A) == 3, A = max(A, [], 3); end     % any channel lit counts
b = A > 0;
end


function s = shortName(f)
[~, n, e] = fileparts(f);
s = [n e];
if numel(s) > 38, s = ['..' s(end-35:end)]; end
end
