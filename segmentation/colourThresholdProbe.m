%% colourProbe.m
% Measure the colour separation between the crab / wand markers and the
% underwater background, and turn it into thresholds the batch segmentation
% code can use directly.
%
% Workflow
%   1. ANNOTATE  - for each training screenshot you pick which classes are
%                  present and draw one or more ROIs over each. Pixels inside
%                  the ROIs are pooled per class.
%   2. ANALYSE   - every candidate channel (R-G, B-G, Lab a*, ...) is scored
%                  by how well it separates each target class from the pooled
%                  background, using AUC. The winning channel and three
%                  thresholds (generous / balanced / conservative) are chosen.
%   3. SAVE      - everything goes to a .mat, including the raw sampled
%                  pixels and the ROI vertices, so you can re-analyse or add
%                  more ROIs later without redrawing.
%   4. VALIDATE  - the thresholds are applied to a separate set of held-out
%                  screenshots so you can see whether they actually work.
%
% Using the result in batch code:
%   S = load('params/colourProbe.mat');
%   r = S.probe.recipe.crab;
%   mask = r.polarity * probeChannel(img, r.channel) > r.threshold;
%
% Requires: Image Processing Toolbox. No Statistics Toolbox dependency.
%
% Yohan Sequeira - Crab Visual Hull Analysis

%% ------------------------------------------------------------------ CONFIG

clear; close all; clc;

codeDir = fileparts(mfilename('fullpath'));
if isempty(codeDir), codeDir = pwd; end     % running section-by-section
addpath(codeDir);                           % so probeChannel is visible

% Screenshots live outside Code/, in the sibling "Test Data" folder, split
% into Training (you draw ROIs on these) and Validation (applied only).
shotDir  = fullfile(fileparts(codeDir), 'Test Data', 'Test Screenshots');
trainDir = fullfile(shotDir, 'Training');
testDir  = fullfile(shotDir, 'Validation');

% Globbed rather than listed, so adding a screenshot to either folder is
% enough - no edit here needed.
cfg.trainImages    = listImages(trainDir);
cfg.validateImages = listImages(testDir);

assert(~isempty(cfg.trainImages), 'colourProbe:noTraining', ...
    'No images found in %s', trainDir);

% --- Classes to annotate --------------------------------------------------
% tool: 'assisted' (edge-snapping, best for the crab), 'freehand', 'polygon'
% isBackground: pooled together as the negative class for every target
cfg.classes = struct( ...
    'name',        {'crab',     'orangeBall', 'blueBall', 'background'}, ...
    'tool',        {'assisted', 'polygon',    'polygon',  'polygon'   }, ...
    'isBackground',{ false,      false,        false,      true       });

% --- Channels to score ----------------------------------------------------
cfg.channels = {'RmG','BmG','RmB','GmR','rgRed','rgBlue','Lab_a','Lab_b'};

% --- Sampling / display ---------------------------------------------------
cfg.displayMaxDim   = 1400;   % ROIs are drawn on an image scaled to this
cfg.maxPxPerROI     = 5e4;    % pixels kept per ROI (random subsample)
cfg.maxPxPerClass   = 2e5;    % pixels used per class when scoring

% --- Threshold policy -----------------------------------------------------
% 'generous'     keeps ~targetRecall of target pixels (fewest missed legs)
% 'balanced'     maximises Youden's J (TPR - FPR)
% 'conservative' sits at the bgPercentile of the background distribution
% A visual hull is a cone INTERSECTION, so a leg missing from one view is
% deleted from the reconstruction entirely, while a stray blob in one view is
% usually carved away by the other three. Default to 'generous'.
cfg.recommend     = 'generous';
cfg.targetRecall  = 0.99;     % for 'generous'
cfg.bgPercentile  = 99.9;     % for 'conservative'

% --- Validation display ---------------------------------------------------
cfg.minBlobArea       = 200;   % px, at full resolution, for cleanup only
cfg.excludeAboveRow   = [];    % e.g. 0.25 -> ignore the top 25% of the frame
                               % (use this to kill the water-surface
                               % reflection once you know where it sits)

% --- Output ---------------------------------------------------------------
cfg.outFile = fullfile(codeDir, 'params', 'colourProbe.mat');

%% -------------------------------------------------------------- HOUSEKEEPING

assert(~isempty(ver('images')), 'Image Processing Toolbox is required.');

if ~exist(fileparts(cfg.outFile), 'dir')
    mkdir(fileparts(cfg.outFile));
end

targetNames = {cfg.classes(~[cfg.classes.isBackground]).name};
bgNames     = {cfg.classes( [cfg.classes.isBackground]).name};
assert(~isempty(bgNames), 'At least one class must have isBackground = true.');

ann = struct('class',{},'imageFile',{},'tool',{},'vertices',{}, ...
             'displayScale',{},'nPixelsFull',{},'px',{});

mode = 'fresh';
if isfile(cfg.outFile)
    choice = questdlg(sprintf(['An existing probe file was found:\n%s\n\n' ...
        'What would you like to do?'], cfg.outFile), 'Existing probe', ...
        'Add more ROIs', 'Re-analyse only', 'Start fresh', 'Add more ROIs');
    switch choice
        case 'Add more ROIs',  mode = 'append';
        case 'Re-analyse only',mode = 'reanalyse';
        case 'Start fresh',    mode = 'fresh';
        otherwise,             return
    end
    if ~strcmp(mode,'fresh')
        old = load(cfg.outFile);
        ann = old.probe.annotations;
        fprintf('Loaded %d existing ROIs from %s\n', numel(ann), cfg.outFile);
    end
end

%% ------------------------------------------------------------------ ANNOTATE

imgList = cfg.trainImages;
if strcmp(mode, 'reanalyse'), imgList = {}; end

for iImg = 1:numel(imgList)

    imgFile = imgList{iImg};
    if ~isfile(imgFile)
        warning('Skipping missing file: %s', imgFile);
        continue
    end

    img = imread(imgFile);
    [H, W, ~] = size(img);
    scale = min(1, cfg.displayMaxDim / max(H, W));
    imgDisp = imresize(img, scale);

    % fprintf('\n=== %s  (%d x %d, displayed at %.0f%%) ===\n', ...
    %     nameOf(imgFile), W, H, scale*100);

    % Which classes are in this image?
    allNames = {cfg.classes.name};
    sel = listdlg('ListString', allNames, ...
        'PromptString', sprintf('Classes present in %s:', nameOf(imgFile)), ...
        'SelectionMode', 'multiple', 'InitialValue', 1:numel(allNames), ...
        'ListSize', [260 160]);
    if isempty(sel), continue, end

    hFig = figure('Name', nameOf(imgFile), 'NumberTitle', 'off', ...
                  'Color', 'w', 'Units','normalized', ...
                  'Position', [0.05 0.08 0.9 0.84]);
    hIm  = imshow(imgDisp);
    hAx  = gca;
    drawnow;

    for k = sel
        cls  = cfg.classes(k);
        keepGoing = true;
        nDrawn = 0;

        while keepGoing
            title(hAx, sprintf(['Draw ROI %d for "%s"   [tool: %s]\n' ...
                'polygon/assisted: click points, double-click or Enter to ' ...
                'close   |   freehand: click-drag'], ...
                nDrawn+1, cls.name, cls.tool), ...
                'Interpreter','none', 'FontSize', 12);
            drawnow;

            roi = drawROI(cls.tool, hAx, hIm);
            if isempty(roi) || isempty(roi.Position)
                keepGoing = false; continue
            end

            verts = roi.Position;
            mDisp = createMask(roi, size(imgDisp,1), size(imgDisp,2));

            if nnz(mDisp) < 4
                warning('ROI was empty, ignoring.');
                delete(roi); continue
            end

            act = questdlg(sprintf('"%s" ROI: %d display px selected.', ...
                cls.name, nnz(mDisp)), 'Confirm ROI', ...
                'Accept', 'Redo', 'Done with this class', 'Accept');
            switch act
                case 'Redo'
                    delete(roi); continue
                case {'Done with this class', ''}
                    delete(roi); keepGoing = false; continue
            end

            % Sample the FULL resolution pixels under this ROI.
            mFull = imresize(mDisp, [H W], 'nearest');
            flat  = reshape(img, [], 3);
            px    = flat(mFull(:), :);
            nFull = size(px, 1);
            if nFull > cfg.maxPxPerROI
                px = px(randperm(nFull, cfg.maxPxPerROI), :);
            end

            ann(end+1) = struct( ...
                'class',        cls.name, ...
                'imageFile',    imgFile, ...
                'tool',         cls.tool, ...
                'vertices',     verts, ...
                'displayScale', scale, ...
                'nPixelsFull',  nFull, ...
                'px',           px);           %#ok<SAGROW>

            nDrawn = nDrawn + 1;
            fprintf('  %-11s ROI %d: %8d px (kept %d)\n', ...
                cls.name, nDrawn, nFull, size(px,1));

            roi.Color = colourFor(cls.name);
            roi.FaceAlpha = 0.25;
            roi.InteractionsAllowed = 'none';

            more = questdlg(sprintf('Draw another "%s" ROI?', cls.name), ...
                'Another ROI', 'Yes', 'No', 'No');
            keepGoing = strcmp(more, 'Yes');
        end
    end

    if isvalid(hFig), close(hFig); end
end

assert(~isempty(ann), 'No ROIs were collected - nothing to analyse.');

%% ------------------------------------------------------------------- ANALYSE

fprintf('\n================ POOLED SAMPLES ================\n');
pooled = struct();
for k = 1:numel(cfg.classes)
    nm = cfg.classes(k).name;
    idx = strcmp({ann.class}, nm);
    if ~any(idx)
        fprintf('  %-11s  (not annotated)\n', nm);
        continue
    end
    px = vertcat(ann(idx).px);
    if size(px,1) > cfg.maxPxPerClass
        px = px(randperm(size(px,1), cfg.maxPxPerClass), :);
    end
    pooled.(nm) = px;
    fprintf('  %-11s  %2d ROIs, %7d px pooled, mean RGB = (%3.0f %3.0f %3.0f)\n', ...
        nm, nnz(idx), size(px,1), mean(double(px),1));
end

% Pooled background is the negative class for every target.
bgPx = [];
for k = 1:numel(bgNames)
    if isfield(pooled, bgNames{k}), bgPx = [bgPx; pooled.(bgNames{k})]; end %#ok<AGROW>
end
assert(~isempty(bgPx), 'No background ROIs were drawn - cannot score channels.');

% Score every channel for every target class.
results = struct();
for t = 1:numel(targetNames)
    nm = targetNames{t};
    if ~isfield(pooled, nm), continue, end

    tPx = pooled.(nm);
    tab = struct('channel',{},'auc',{},'polarity',{},'dprime',{}, ...
                 'tMean',{},'bMean',{});

    for c = 1:numel(cfg.channels)
        ch = cfg.channels{c};
        tv = probeChannel(tPx,  ch);
        bv = probeChannel(bgPx, ch);

        a = aucRank(tv, bv);
        pol = 1;
        if a < 0.5, pol = -1; a = 1 - a; end   % class sits below background

        d = abs(mean(tv) - mean(bv)) / sqrt(0.5*(var(tv) + var(bv)) + eps);

        tab(end+1) = struct('channel',ch, 'auc',a, 'polarity',pol, ...
            'dprime',d, 'tMean',mean(tv), 'bMean',mean(bv)); %#ok<SAGROW>
    end

    [~, ord] = sort([tab.auc], 'descend');
    tab = tab(ord);
    best = tab(1);

    % Thresholds on the polarity-corrected channel (target always > bg).
    tv = best.polarity * probeChannel(tPx,  best.channel);
    bv = best.polarity * probeChannel(bgPx, best.channel);

    thr = struct();
    thr.generous     = pctl(tv, 100*(1 - cfg.targetRecall));
    thr.conservative = pctl(bv, cfg.bgPercentile);

    lo = min([tv; bv]); hi = max([tv; bv]);
    sweep = linspace(lo, hi, 512);
    tpr = arrayfun(@(s) mean(tv > s), sweep);
    fpr = arrayfun(@(s) mean(bv > s), sweep);
    [~, jBest] = max(tpr - fpr);
    thr.balanced = sweep(jBest);

    chosen = thr.(cfg.recommend);

    results.(nm) = struct( ...
        'channel',    best.channel, ...
        'polarity',   best.polarity, ...
        'auc',        best.auc, ...
        'dprime',     best.dprime, ...
        'thresholds', thr, ...
        'recommend',  cfg.recommend, ...
        'threshold',  chosen, ...
        'tpr',        mean(tv > chosen), ...
        'fpr',        mean(bv > chosen), ...
        'ranking',    tab, ...
        'sweep',      struct('thr',sweep, 'tpr',tpr, 'fpr',fpr), ...
        'targetStats',chanStats(tv), ...
        'bgStats',    chanStats(bv));
end

% ---- Report -------------------------------------------------------------
fprintf('\n================ CHANNEL RANKING (AUC vs pooled background) ================\n');
for t = 1:numel(targetNames)
    nm = targetNames{t};
    if ~isfield(results, nm), continue, end
    r = results.(nm);
    fprintf('\n%s:\n', upper(nm));
    fprintf('   %-8s %7s %6s %9s   %s\n','channel','AUC','pol','d-prime','means (target / bg)');
    for c = 1:numel(r.ranking)
        e = r.ranking(c);
        mark = ' ';  if c == 1, mark = '*'; end
        fprintf(' %s %-8s %7.4f %+6d %9.2f   %8.2f / %8.2f\n', ...
            mark, e.channel, e.auc, e.polarity, e.dprime, e.tMean, e.bMean);
    end
end

fprintf('\n================ RECOMMENDED THRESHOLDS ================\n');
fprintf('%-11s %-8s %4s %10s %10s %10s   %6s %6s\n', ...
    'class','channel','pol','generous','balanced','conservat.','TPR','FPR');
for t = 1:numel(targetNames)
    nm = targetNames{t};
    if ~isfield(results, nm), continue, end
    r = results.(nm);
    fprintf('%-11s %-8s %+4d %10.2f %10.2f %10.2f   %6.3f %6.3f\n', ...
        nm, r.channel, r.polarity, r.thresholds.generous, ...
        r.thresholds.balanced, r.thresholds.conservative, r.tpr, r.fpr);
end
fprintf('\nUsing the "%s" policy -> the values saved in probe.recipe.\n', cfg.recommend);

%% -------------------------------------------------------------------- PLOTS

for t = 1:numel(targetNames)
    nm = targetNames{t};
    if ~isfield(results, nm), continue, end
    r  = results.(nm);
    tv = r.polarity * probeChannel(pooled.(nm), r.channel);
    bv = r.polarity * probeChannel(bgPx,        r.channel);

    figure('Name', sprintf('t02 - %s', nm), 'NumberTitle','off', 'Color','w', ...
           'Position', [80+40*t 80 980 420]);

    subplot(1,2,1); hold on; grid on
    edges = linspace(min([tv;bv]), max([tv;bv]), 120);
    histogram(bv, edges, 'Normalization','probability', ...
        'FaceColor',[0.35 0.55 0.35], 'EdgeColor','none', 'FaceAlpha',0.7);
    histogram(tv, edges, 'Normalization','probability', ...
        'FaceColor', colourFor(nm), 'EdgeColor','none', 'FaceAlpha',0.7);
    yl = ylim;
    plot([r.thresholds.generous     r.thresholds.generous    ], yl, 'k-', 'LineWidth',1.5);
    plot([r.thresholds.balanced     r.thresholds.balanced    ], yl, 'k--','LineWidth',1.2);
    plot([r.thresholds.conservative r.thresholds.conservative], yl, 'k:', 'LineWidth',1.2);
    xlabel(sprintf('%s%s', ternary(r.polarity<0,'-',''), r.channel));
    ylabel('probability');
    title(sprintf('%s vs background  (AUC = %.4f)', nm, r.auc), 'Interpreter','none');
    legend({'background', nm, 'generous','balanced','conservative'}, ...
        'Location','best', 'Interpreter','none');

    subplot(1,2,2); hold on; grid on
    plot(r.sweep.thr, r.sweep.tpr, 'LineWidth',1.6);
    plot(r.sweep.thr, r.sweep.fpr, 'LineWidth',1.6);
    plot(r.sweep.thr, r.sweep.tpr - r.sweep.fpr, 'LineWidth',1.2);
    plot([r.threshold r.threshold], [0 1], 'k-', 'LineWidth',1.5);
    xlabel('threshold'); ylabel('rate'); ylim([0 1]);
    legend({'TPR (target kept)','FPR (background kept)','Youden J','chosen'}, ...
        'Location','best');
    title('threshold sweep');
end

%% --------------------------------------------------------------------- SAVE

if strcmpi(questdlg('Save the probe results to a .mat file?', 'Save', ...
        'Yes','No','Yes'), 'Yes')

    % Flat, dependency-free recipe for the batch code to consume.
    recipe = struct();
    for t = 1:numel(targetNames)
        nm = targetNames{t};
        if ~isfield(results, nm), continue, end
        recipe.(nm) = struct( ...
            'channel',   results.(nm).channel, ...
            'polarity',  results.(nm).polarity, ...
            'threshold', results.(nm).threshold, ...
            'usage', sprintf('mask = %d * probeChannel(img, ''%s'') > %.4f;', ...
                             results.(nm).polarity, results.(nm).channel, ...
                             results.(nm).threshold));
    end

    probe = struct( ...
        'recipe',      recipe, ...
        'results',     results, ...
        'annotations', ann, ...
        'config',      cfg, ...
        'createdOn',   datetime('now'), ...
        'matlabVer',   version, ...
        'createdBy',   mfilename);

    save(cfg.outFile, 'probe', '-v7.3');
    fprintf('\nSaved -> %s\n', cfg.outFile);
    fprintf('Port to batch code with:\n');
    fprintf('    S = load(''%s'');\n', cfg.outFile);
    for t = 1:numel(targetNames)
        nm = targetNames{t};
        if ~isfield(recipe, nm), continue, end
        fprintf('    %% %s:  %s\n', nm, recipe.(nm).usage);
    end
end

%% ----------------------------------------------------------------- VALIDATE

if isempty(cfg.validateImages), return, end

if ~isempty(intersect(cfg.validateImages, cfg.trainImages))
    warning(['Some validation images were also used for training. The ' ...
             'thresholds will look better than they really are. Add ' ...
             'held-out screenshots to cfg.validateImages.']);
end

for iImg = 1:numel(cfg.validateImages)
    imgFile = cfg.validateImages{iImg};
    if ~isfile(imgFile)
        warning('Skipping missing validation file: %s', imgFile);
        continue
    end

    img = imread(imgFile);
    [H, W, ~] = size(img);
    scale   = min(1, cfg.displayMaxDim / max(H, W));
    imgDisp = imresize(img, scale);

    validNames = targetNames(isfield(results, targetNames));
    nC = numel(validNames);
    if nC == 0, continue, end

    figure('Name', sprintf('t02 validation - %s', nameOf(imgFile)), ...
           'NumberTitle','off', 'Color','w', 'Units','normalized', ...
           'Position', [0.03 0.06 0.94 0.86]);
    tl = tiledlayout(2, nC+1, 'Padding','compact', 'TileSpacing','compact');
    title(tl, nameOf(imgFile), 'Interpreter','none', 'FontWeight','bold');

    nexttile(1); imshow(imgDisp); title('input');
    nexttile(nC+2); axis off;

    fprintf('\n--- validation: %s ---\n', nameOf(imgFile));

    for t = 1:nC
        nm = validNames{t};
        r  = results.(nm);

        chan = r.polarity * probeChannel(img, r.channel);
        mask = chan > r.threshold;

        if ~isempty(cfg.excludeAboveRow)
            mask(1:round(cfg.excludeAboveRow*H), :) = false;
        end

        % Deliberately gentle: no morphological opening, which would shave
        % off exactly the thin legs the hull needs. Speckle is removed by
        % area alone so you can see what the raw threshold really gives you.
        raw   = nnz(mask);
        mask  = imfill(mask, 'holes');
        mask  = bwareaopen(mask, cfg.minBlobArea);

        cc = bwconncomp(mask);
        st = regionprops(cc, 'Area','Centroid','BoundingBox');
        [~, ordA] = sort([st.Area], 'descend');

        fprintf('  %-11s ch=%s%s thr=%.2f : %d raw px -> %d blobs after cleanup\n', ...
            nm, ternary(r.polarity<0,'-',''), r.channel, r.threshold, raw, numel(st));
        for b = 1:min(3, numel(st))
            s = st(ordA(b));
            fprintf('        blob %d: area=%7d  centroid=(%7.1f,%7.1f)  bbox=[%.0f %.0f %.0f %.0f]\n', ...
                b, s.Area, s.Centroid(1), s.Centroid(2), s.BoundingBox);
        end
        if numel(st) > 1
            fprintf('        NOTE: >1 blob. Check for glass/surface reflections.\n');
        end

        chanDisp = imresize(chan, [size(imgDisp,1) size(imgDisp,2)]);
        nexttile(1+t);
        imagesc(chanDisp); axis image off; colormap(gca, parula); colorbar;
        title(sprintf('%s%s', ternary(r.polarity<0,'-',''), r.channel), ...
              'Interpreter','none');

        maskDisp = imresize(mask, [size(imgDisp,1) size(imgDisp,2)], 'nearest');
        nexttile(nC+2+t);
        imshow(labeloverlay(imgDisp, maskDisp, 'Colormap', colourFor(nm), ...
                            'Transparency', 0.4));
        title(sprintf('%s  thr=%.2f  (%d blobs)', nm, r.threshold, numel(st)), ...
              'Interpreter','none');
    end
end

fprintf('\nDone. Next: feed the saved thresholds into t03_wand_detect_single.m\n');
fprintf('and t04_crab_segment_colour.m.\n');

%% ----------------------------------------------------------- LOCAL FUNCTIONS

function roi = drawROI(tool, hAx, hIm)
%DRAWROI Dispatch to the requested interactive ROI tool. Blocks until drawn.
    try
        switch lower(tool)
            case 'assisted', roi = drawassisted(hIm);
            case 'freehand', roi = drawfreehand(hAx);
            case 'polygon',  roi = drawpolygon(hAx);
            otherwise
                error('t02:badTool', 'Unknown ROI tool "%s".', tool);
        end
    catch ME
        if strcmp(ME.identifier, 'MATLAB:class:InvalidHandle')
            roi = [];   % figure was closed mid-draw
        else
            rethrow(ME);
        end
    end
end

function a = aucRank(t, b)
%AUCRANK Area under the ROC curve via the Mann-Whitney rank statistic.
%   No Statistics Toolbox needed. Ties are broken arbitrarily, which is
%   negligible at these sample sizes.
    t = t(:); b = b(:);
    n1 = numel(t); n2 = numel(b);
    [~, ord] = sort([t; b]);
    r = zeros(n1+n2, 1);
    r(ord) = 1:(n1+n2);
    a = (sum(r(1:n1)) - n1*(n1+1)/2) / (n1*n2);
end

function q = pctl(x, p)
%PCTL Linear-interpolated percentile. No Statistics Toolbox needed.
    x = sort(x(:));
    n = numel(x);
    if n == 0, q = NaN; return, end
    if n == 1, q = x;   return, end
    idx = (p/100)*(n-1) + 1;
    idx = max(1, min(n, idx));
    lo  = floor(idx); hi = ceil(idx);
    q   = x(lo) + (idx-lo)*(x(hi)-x(lo));
end

function s = chanStats(v)
    s = struct('mean',mean(v), 'std',std(v), 'min',min(v), 'max',max(v), ...
               'p01',pctl(v,1), 'p50',pctl(v,50), 'p99',pctl(v,99), 'n',numel(v));
end

function c = colourFor(name)
    switch lower(name)
        case 'crab',       c = [0.90 0.35 0.15];
        case 'orangeball', c = [1.00 0.60 0.10];
        case 'blueball',   c = [0.20 0.35 0.90];
        case 'background', c = [0.35 0.55 0.35];
        otherwise,         c = [0.60 0.20 0.70];
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function f = listImages(d)
%LISTIMAGES Every image in a folder, as a cell array of full paths.
f = {};
if ~isfolder(d), return, end
ex = {'*.jpg','*.jpeg','*.png','*.tif','*.tiff','*.bmp'};
for k = 1:numel(ex)
    p = dir(fullfile(d, ex{k}));
    f = [f; fullfile(d, {p.name}')];  %#ok<AGROW>
end
end


function n = nameOf(f)
    [~, b, e] = fileparts(f);
    n = b;
end

