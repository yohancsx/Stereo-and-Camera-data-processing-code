function landmarkAnnotator(cfg)
%LANDMARKANNOTATOR Digitise landmarks in two views with a live 3-D readout.
%
%   landmarkAnnotator            prompts for the data folder
%   landmarkAnnotator(cfg)       runs with the given settings
%   cfg = landmarkAnnotator('defaults')
%
%   TWO WINDOWS
%     annotator  view A and view B side by side, part list, controls
%     3-D        the dense stereo cloud, the part polylines, the active
%                point and its back-projected ray, updating live as you drag
%
%   THE CORRESPONDENCE MODEL
%   Point j of a part in view A and point j in view B are the SAME physical
%   landmark - a joint, the base where the part attaches to the body, the tip.
%   You supply that pairing by clicking, which is why this survives a
%   calibration that defeated dense matching: a block matcher searching the
%   wrong scanline finds something and reports it confidently, whereas a
%   hand-placed pair can only be as wrong as your click.
%
%   THE LIVE QUALITY SIGNAL
%   Because your clicks are NOT forced onto the epipolar line, the distance
%   from the view-B click to the epipolar line of the view-A click measures
%   something real: how far the two clicks are from being mutually
%   consistent with the calibration. Markers are coloured by it - green
%   consistent, red not. (In the dense stereo this same idea was
%   structurally ~0 and meant nothing, because the matcher could only ever
%   return points already on the line.)
%
%   That distance is recorded whether or not "snap to epipolar" is on, so
%   turning snapping on for speed does not destroy the diagnostic.
%
%   SWITCHING CAMERA PAIRS
%   The dropdown above the panels lists every camera pair, closest baseline
%   first. Switching carries your work across: 3-D landmarks are
%   pair-independent, so the new pair's 2-D points are restored if you have
%   digitised there before, or seeded by reprojecting the existing 3-D if
%   you have not. Either way the parts arrive already drawn and you only need
%   to nudge them - which is also how you refine a part using a second
%   baseline.
%
%   CONTROLS
%     place mode   clicks alternate A then B, appending landmarks base->tip
%     edit mode    drag any marker in either view; 3-D follows continuously
%     scroll       zoom about the cursor      right/middle-drag  pan
%     1..9         switch active part         n  new part
%     left/right   select previous/next landmark of the active part
%     i            insert a landmark after the selected one
%     Delete       remove the selected landmark
%     m            print the body-frame part metrics
%     c  hide/show the dense stereo cloud in the 3-D window
%     b  hide/show the working-volume box
%     u  undo      r  reprojection overlay    z  reset zoom
%
%   The cloud and box are context while you digitise but clutter in a
%   figure, so both can be turned off from the checkboxes, the keys above,
%   or up front via cfg.showCloud / cfg.showBox.
%
%   OUTPUT
%     export csv writes landmarks.csv (3-D points + per-point epipolar
%     miss) and partMetrics.csv (length, span, elevation, azimuth and base
%     offsets in a body-fixed frame - see vh.segmentMetrics).
%
%   VIDEO MODE - tracking a part across frames
%   Supply cfg.videoFiles (one video per camera, DLT camera order) and
%   cfg.frameRange ([startFrame endFrame] or [startFrame endFrame step]),
%   or just run with neither image nor video cfg set and pick "Video range"
%   at the prompt. A frame-navigation bar appears below the images.
%
%   Each frame you visit is digitised FRESH - parts keep their names from
%   frame to frame, but nothing carries forward: no auto-tracking, no
%   reprojected starting guess. Navigating to a different frame (by the
%   slider, the +-1/+-10 buttons, or typing a number) archives whatever you
%   digitised on the frame you are leaving, then clears the points for the
%   new one. "export track" writes the whole archive as two long-format
%   CSVs - landmarks_track.csv (one row per point per part per frame) and
%   partMetrics_track.csv (vh.segmentMetrics run once per frame, i.e. the
%   time series of each part's length/span/angles) - across every frame you
%   visited, not just the one currently on screen.
%
%   There is no silhouette mask in video mode, so cfg.cropToMask is forced
%   off (you see the full undistorted frame; scroll to zoom, right/middle
%   drag to pan) and cfg.showCloud/cfg.computeCloud/cfg.showBox default off
%   too - there is nothing to seed a dense-cloud or mask-derived box context
%   from automatically. The working-volume box used only for ray-clipping
%   and 3-D axis limits (never for triangulation, which is exact DLT
%   regardless) falls back to half the active pair's baseline, or
%   cfg.objectSize/2 if you set it.
%
%   Yohan Sequeira

%% -------------------------------------------------------------- DEFAULTS

d = pipelineConfig('landmarkAnnotator');

if nargin == 1 && (ischar(cfg) || isstring(cfg))
    if strcmpi(cfg, 'defaults'), disp(d); return, end
    % A path to a saved config: landmarkAnnotator('myRun.mat')
    cfgFile = char(cfg);
    assert(isfile(cfgFile), 'landmarkAnnotator:noConfig', ...
        'Config file not found: %s', cfgFile);
    L = load(cfgFile);
    if isfield(L,'cfg'), cfg = L.cfg;
    else
        fnl = fieldnames(L);
        cfg = L.(fnl{1});
    end
    fprintf('landmarkAnnotator: loaded config from %s\n', cfgFile);
end
if nargin < 1, cfg = struct(); end
rawCfg = cfg;           % what the caller actually set, before defaults fill in
fn = fieldnames(d);
for fi = 1:numel(fn)
    if ~isfield(cfg, fn{fi}), cfg.(fn{fi}) = d.(fn{fi}); end
end
% Accept "double-quoted" strings as well as 'char' for every path field.
% fullfile() propagates string-ness, and a string array is not a cell.
for fi = {'dataDir','cloudFile','sessionFile','yOrigin','units', ...
          'dltFile','calibFile','maskPattern','imagePattern','videoPattern'}
    if isstring(cfg.(fi{1})), cfg.(fi{1}) = char(cfg.(fi{1})); end
end

thisDir = fileparts(mfilename('fullpath'));
if isempty(thisDir), thisDir = pwd; end
addpath(thisDir);

% Neither an image-mode nor a video-mode input was configured - ask, rather
% than silently assuming one.
if isempty(cfg.videoFiles) && isempty(cfg.frameRange) && isempty(cfg.dataDir) ...
        && isempty(cfg.maskFiles) && isempty(cfg.imageFiles)
    choice = questdlg( ...
        'Digitise a single image pair, or track across a range of video frames?', ...
        'landmarkAnnotator', 'Single image (existing)', 'Video range (new)', ...
        'Single image (existing)');
    if isempty(choice), return, end
    if strcmp(choice, 'Video range (new)')
        [vf, vp] = uigetfile( ...
            {'*.mp4;*.MP4;*.mov;*.MOV;*.avi;*.MTS', 'Video files'}, ...
            'Select the video files, one per camera, in DLT camera order', ...
            'MultiSelect', 'on');
        if isequal(vf, 0), return, end
        if ischar(vf), vf = {vf}; end
        cfg.videoFiles = fullfile(vp, vf(:));
        cfg.dataDir = vp;      % outputs land next to the videos by default
    end
end

S = struct();
S.videoMode = ~isempty(cfg.videoFiles);

% Video mode has no silhouette mask at all, so cropToMask is FORCED off
% (regionprops(S.M(kk2).mask, ...) would error on the empty placeholder
% mask - this isn't a default that can be overridden). The cloud/box
% context default off too, since there is no mask to seed them from
% automatically, but those stay user-overridable via cfg/the checkboxes.
if S.videoMode
    if isfield(rawCfg,'cropToMask') && rawCfg.cropToMask
        warning('landmarkAnnotator:noCropInVideoMode', ...
            'cropToMask has no effect in video mode (no mask to crop to) - ignoring it.');
    end
    cfg.cropToMask = false;
    if ~isfield(rawCfg,'showCloud'),    cfg.showCloud    = false; end
    if ~isfield(rawCfg,'computeCloud'), cfg.computeCloud = false; end
    if ~isfield(rawCfg,'showBox'),      cfg.showBox      = false; end
end

if isempty(cfg.dataDir)
    cfg.dataDir = uigetdir(thisDir, 'Folder with masks, seg images, DLT and calibration');
    if isequal(cfg.dataDir, 0), return, end
end

%% ------------------------------------------------------------------ LOAD

fprintf('\nlandmarkAnnotator\n');

dltFile   = resolveOne(cfg.dltFile,   cfg.dataDir, {'*dlt*.csv','*DLT*.csv'}, ...
                       {}, 'DLT coefficient csv');
% Exclude the tool's own outputs, which are also .mat files sitting here.
calibFile = resolveOne(cfg.calibFile, cfg.dataDir, ...
    {'*fisheye*.mat','*Fisheye*.mat','*aram*.mat','*.mat'}, ...
    {'landmarkAnnotation','roiSession','cfg','stereo_','hull_'}, ...
    'camera calibration .mat');
fprintf('  dlt     : %s\n', nameOnly(dltFile));
fprintf('  calib   : %s\n', nameOnly(calibFile));

S.cfg = cfg;
[S.P, ~, S.camC] = vh.readDLT(dltFile);

if S.videoMode
    %% ---- video: open one reader per camera, no mask/texture files -----
    videoFiles = resolveList(cfg.videoFiles, cfg.dataDir, cfg.videoPattern, 'video');
    nCamsV = numel(videoFiles);
    assert(nCamsV == size(S.P,3), 'landmarkAnnotator:videoCount', ...
        'The DLT file has %d camera(s) but %d video(s) were given.', ...
        size(S.P,3), nCamsV);
    fprintf('  videos  : %d file(s)\n', nCamsV);

    [S.calibObj, S.calibKind] = vh.sniffCalib(calibFile);

    S.vidReaders = cell(nCamsV,1);
    S.vidNames   = cell(nCamsV,1);
    nFramesAll   = zeros(nCamsV,1);
    for ii = 1:nCamsV
        S.vidReaders{ii} = VideoReader(videoFiles{ii});
        [~, S.vidNames{ii}] = fileparts(videoFiles{ii});
        nf = [];
        try
            nf = S.vidReaders{ii}.NumFrames;
        catch
        end
        if isempty(nf) || nf < 1
            nf = max(1, floor( ...
                S.vidReaders{ii}.Duration * S.vidReaders{ii}.FrameRate));
        end
        nFramesAll(ii) = nf;
    end
    % Reorder to DLT camera order, exactly like the single-image path does
    % for S.M below.
    S.vidReaders = S.vidReaders(cfg.camOrder);
    S.vidNames   = S.vidNames(cfg.camOrder);
    nFramesCommon = min(nFramesAll(cfg.camOrder));

    if isempty(cfg.frameRange)
        a = inputdlg( ...
            {sprintf('Start frame (1 - %d):', nFramesCommon), ...
             sprintf('End frame (1 - %d):', nFramesCommon), 'Step:'}, ...
            'Frame range to track', 1, ...
            {'1', num2str(nFramesCommon), '1'});
        if isempty(a), return, end
        cfg.frameRange = [str2double(a{1}) str2double(a{2}) str2double(a{3})];
    end
    if numel(cfg.frameRange) < 3, cfg.frameRange(3) = 1; end
    S.frameRange = round(cfg.frameRange);
    S.frame = S.frameRange(1);
    S.cfg = cfg;

    % .rgb starts empty - rebuildViews() decodes+undistorts the active
    % pair's current frame into it on demand (see VIDEO NESTED: FRAMES).
    S.M = struct('file',{},'calibFile',{},'kind',{},'H',{},'W',{}, ...
        'rgb',{},'mask',{});
    for ii = 1:nCamsV
        S.M(ii) = struct('file', S.vidNames{ii}, 'calibFile', calibFile, ...
            'kind', S.calibKind, 'H', S.vidReaders{ii}.Height, ...
            'W', S.vidReaders{ii}.Width, 'rgb', [], 'mask', []);
    end
    S.track = struct('frame',{},'parts',{},'pair',{});
else
    %% ---- single image: unchanged from before video mode existed -------
    maskFiles  = resolveList(cfg.maskFiles,  cfg.dataDir, cfg.maskPattern,  'mask');
    imageFiles = resolveList(cfg.imageFiles, cfg.dataDir, cfg.imagePattern, 'texture');
    assert(numel(imageFiles) == numel(maskFiles), 'landmarkAnnotator:files', ...
        ['Found %d mask(s) matching "%s" but %d image(s) matching "%s" in\n  %s\n' ...
         'They must correspond one-to-one, in the same alphabetical order.'], ...
        numel(maskFiles), cfg.maskPattern, numel(imageFiles), cfg.imagePattern, ...
        cfg.dataDir);
    fprintf('  masks   : %d matching %s\n', numel(maskFiles), cfg.maskPattern);
    fprintf('  textures: %d matching %s\n', numel(imageFiles), cfg.imagePattern);

    S.M = vh.loadMasks(maskFiles, calibFile, ...
        'imageFiles', imageFiles, ...
        'scaleFactor', cfg.undistortScale, 'verbose', true);
    S.M = S.M(cfg.camOrder);
end

S.a = cfg.pair(1);  S.b = cfg.pair(2);
S.yOrigin = cfg.yOrigin;

S.F = vh.fundamentalFromDLT(S.P(:,:,S.a), S.P(:,:,S.b), ...
    S.M(S.a).H, S.M(S.b).H, S.yOrigin);

fprintf('  digitising DLT cameras %d and %d\n', S.a, S.b);
VNAME = 'AB';
for vi = 1:2
    kk = pairIdx(vi);
    [~,n1,e1] = fileparts(S.M(kk).file);
    fprintf('    view %s  = DLT %d  <- %s%s\n', VNAME(vi), kk, n1, e1);
end

% Working volume, for clipping rays and framing the 3-D axes. Never used
% for triangulation itself (that is exact DLT regardless of this box).
cen = zeros(numel(S.M),2);
if S.videoMode
    % No mask to centre on - guess the subject is framed near image centre.
    % Wrong by a bit just makes the ray-clip/axis-limit box a bit off, not
    % the digitised points, which come from your clicks, not this guess.
    for ii = 1:numel(S.M)
        cen(ii,:) = [S.M(ii).W/2, S.M(ii).H/2];
    end
else
    for ii = 1:numel(S.M)
        [rr0,cc0] = ind2sub([S.M(ii).H S.M(ii).W], find(S.M(ii).mask));
        cen(ii,:) = [mean(cc0) mean(rr0)];
    end
end
uv0 = zeros(numel(S.M),2);
for ii = 1:numel(S.M)
    uv0(ii,:) = vh.imageToDLT(cen(ii,:), S.M(ii).H, S.yOrigin);
end
S.centre = vh.triangulate(S.P, uv0);
if S.videoMode
    S.half = norm(S.camC(:,S.a) - S.camC(:,S.b)) / 2;
    if ~isempty(cfg.objectSize), S.half = cfg.objectSize / 2; end
else
    S.half = vh.objectScale(S.P, S.M, S.centre, S.yOrigin) * 1.6/2;
end
S.boxLo  = S.centre - S.half;
S.boxHi  = S.centre + S.half;
fprintf('  working volume centre (%.3f %.3f %.3f), half-width %.3f %s\n', ...
    S.centre, S.half, cfg.units);

%% ---- dense cloud, for context in the 3-D window ------------------------
S.cloud = cfg.cloudXYZ;
if isempty(S.cloud) && ~isempty(cfg.cloudFile) && isfile(cfg.cloudFile)
    L = load(cfg.cloudFile);
    if isfield(L,'slim'),  S.cloud = gatherCloud(L.slim);
    elseif isfield(L,'out'), S.cloud = gatherCloud(L.out); end
end
if isempty(S.cloud) && cfg.computeCloud
    fprintf('  computing a dense cloud for context (SGM, this pair only)...\n');
    try
        box = struct('centre', S.centre, 'half', S.half);
        Sr = vh.rectifyPair(S.P(:,:,S.a), S.P(:,:,S.b), S.M(S.a), S.M(S.b), ...
            box, S.yOrigin, 'verbose', false);
        Rm = vh.stereoMatch(Sr, 'sgm', 'verbose', false);
        Cm = vh.reconstructMatches(Sr, Rm, S.P(:,:,S.a), S.P(:,:,S.b), ...
            S.M(S.a), S.M(S.b), S.yOrigin, 'box', box, 'verbose', false);
        S.cloud = Cm.XYZ;
        fprintf('  %d cloud points\n', size(S.cloud,1));
    catch ME
        fprintf('  (dense cloud unavailable: %s)\n', ME.message);
        S.cloud = zeros(0,3);
    end
end
if isempty(S.cloud), S.cloud = zeros(0,3); end

%% ---- the pairs you can digitise, closest baseline first ----------------
% Loop variables here are deliberately named ia/ib/iq: nested functions
% share this workspace, and several of them use a, b and q.
nCamAll = size(S.P,3);
nPair   = nCamAll*(nCamAll-1)/2;
S.pairList = zeros(nPair,2);
bl = zeros(nPair,1);
iq = 0;
for ia = 1:nCamAll
    for ib = ia+1:nCamAll
        iq = iq + 1;
        S.pairList(iq,:) = [ia ib];
        bl(iq) = norm(S.camC(:,ia) - S.camC(:,ib));
    end
end
[bl, ord] = sort(bl);
S.pairList = S.pairList(ord,:);
S.pairLabel = cell(nPair,1);
for iq = 1:nPair
    S.pairLabel{iq} = sprintf('DLT %d + %d   (baseline %.2f)', ...
        S.pairList(iq,1), S.pairList(iq,2), bl(iq));
end

%% ---- display copies: crop to the animal, then scale to the panel -------
S.view = struct('cam',{},'r0',{},'c0',{},'scale',{},'img',{},'H',{},'W',{});
rebuildViews();

%% ---- part model ---------------------------------------------------------
% byPair caches the 2-D clicks per camera pair, so switching pairs and
% coming back restores your exact points rather than reprojected ones.
S.parts = struct('name',{},'color',{},'A',{},'B',{},'XYZ',{},'resid',{}, ...
    'epiDist',{},'byPair',{});
S.parts = addPartStruct(S.parts, 'body');
S.parts = addPartStruct(S.parts, 'part1');
S.active = 2;          % start on part1, not the body
S.activePt = 0;        % selected landmark within the active part
S.mode = 'place';
S.awaiting = 'A';
S.dragging = [];
S.panning = [];
S.undoStack = {};
S.showReproj = false;
S.snap = cfg.snapEpipolar;
S.showCloud = cfg.showCloud;      % dense stereo points in the 3-D window
S.showBox   = cfg.showBox;        % the working-volume wireframe

if isempty(cfg.sessionFile)
    cfg.sessionFile = fullfile(cfg.dataDir, 'landmarkAnnotation.mat');
    S.cfg.sessionFile = cfg.sessionFile;
end

%% -------------------------------------------------------------------- UI

figA = figure('Name','landmarkAnnotator - digitise', 'NumberTitle','off', ...
    'Color',[0.94 0.94 0.94], 'Units','normalized', ...
    'Position',[0.02 0.10 0.66 0.82], 'CloseRequestFcn', @(~,~) onClose());

axV = gobjects(1,2);  hImg = gobjects(1,2);  hEpi = gobjects(1,2);
hSel = gobjects(1,2);
axBottom = 0.24;
if S.videoMode, axBottom = 0.28; end   % leaves room for the frame-nav bar
pos = {[0.03 axBottom 0.45 0.96-axBottom], [0.52 axBottom 0.45 0.96-axBottom]};
for vi = 1:2
    axV(vi) = axes(figA, 'Position', pos{vi});
    hImg(vi) = image(axV(vi), 'CData', S.view(vi).img);
    axV(vi).YDir = 'reverse';  axV(vi).DataAspectRatio = [1 1 1];
    axV(vi).XLim = [0.5 size(S.view(vi).img,2)+0.5];
    axV(vi).YLim = [0.5 size(S.view(vi).img,1)+0.5];
    axV(vi).XTick = []; axV(vi).YTick = [];
    hold(axV(vi),'on');
    title(axV(vi), sprintf('view %s   (DLT camera %d)', VNAME(vi), pairIdx(vi)));
    hEpi(vi) = plot(axV(vi), nan, nan, '-', 'Color',[1 0.85 0.1], ...
        'LineWidth',1.2, 'HitTest','off', 'PickableParts','none');
    hSel(vi) = plot(axV(vi), nan, nan, 'o', 'MarkerSize',15, ...
        'MarkerEdgeColor',[1 0.85 0.1], 'LineWidth',2, ...
        'HitTest','off','PickableParts','none');
    hImg(vi).ButtonDownFcn = @(~,~) onImageClick(vi);
end

hPartLine = gobjects(0,2);      % per part, per view
hPartRepro = gobjects(0,2);

% Camera pair selector - closest baseline first, so the natural stereo pairs
% are at the top of the list.
uicontrol(figA,'Style','text','Units','normalized','Position',[0.52 0.185 0.08 0.03], ...
    'String','camera pair','FontWeight','bold','HorizontalAlignment','left', ...
    'BackgroundColor',[0.94 0.94 0.94]);
qNow = find(S.pairList(:,1)==S.a & S.pairList(:,2)==S.b, 1);
if isempty(qNow), qNow = 1; end
uicontrol(figA,'Style','popupmenu','Units','normalized', ...
    'Position',[0.60 0.185 0.20 0.035], 'String', S.pairLabel, ...
    'Value', qNow, 'Callback', @(src,~) onSwitchPair(src.Value));
uicontrol(figA,'Style','checkbox','Units','normalized', ...
    'String','carry parts across', 'Value', cfg.carryAcrossPairs, ...
    'BackgroundColor',[0.94 0.94 0.94], 'Position',[0.815 0.185 0.16 0.035], ...
    'TooltipString', ['On: switching reprojects existing parts into the new ' ...
        'pair. Off: the new pair starts clean, so you can track the parts ' ...
        'visible from that side without the others overlapping.'], ...
    'Callback', @(src,~) onCarry(src.Value));

if S.videoMode
    % ---- frame navigation - reused pattern from videoSegmentTool.m -------
    uicontrol(figA,'Style','text','Units','normalized', ...
        'Position',[0.03 0.245 0.06 0.03], 'String','frame', ...
        'FontWeight','bold','HorizontalAlignment','left', ...
        'BackgroundColor',[0.94 0.94 0.94]);
    edFrame = uicontrol(figA,'Style','edit','Units','normalized', ...
        'Position',[0.09 0.245 0.06 0.03], 'String', num2str(S.frame), ...
        'Callback', @(src,~) gotoFrame(str2double(src.String)));
    slFrame = uicontrol(figA,'Style','slider','Units','normalized', ...
        'Position',[0.16 0.245 0.24 0.03], ...
        'Min', S.frameRange(1), 'Max', max(S.frameRange(1)+1, S.frameRange(2)), ...
        'Value', S.frame, 'Callback', @(src,~) gotoFrame(round(src.Value)));
    uicontrol(figA,'Style','pushbutton','Units','normalized','String','-10', ...
        'Position',[0.405 0.245 0.03 0.03], ...
        'Callback', @(~,~) gotoFrame(S.frame - 10*S.frameRange(3)));
    uicontrol(figA,'Style','pushbutton','Units','normalized','String','-1', ...
        'Position',[0.44 0.245 0.03 0.03], ...
        'Callback', @(~,~) gotoFrame(S.frame - S.frameRange(3)));
    uicontrol(figA,'Style','pushbutton','Units','normalized','String','+1', ...
        'Position',[0.475 0.245 0.03 0.03], ...
        'Callback', @(~,~) gotoFrame(S.frame + S.frameRange(3)));
    uicontrol(figA,'Style','pushbutton','Units','normalized','String','+10', ...
        'Position',[0.51 0.245 0.03 0.03], ...
        'Callback', @(~,~) gotoFrame(S.frame + 10*S.frameRange(3)));
    uicontrol(figA,'Style','text','Units','normalized', ...
        'Position',[0.55 0.245 0.24 0.03], 'HorizontalAlignment','left', ...
        'FontSize', 9, 'BackgroundColor',[0.94 0.94 0.94], ...
        'String', sprintf('range [%d %d] step %d', ...
            S.frameRange(1), S.frameRange(2), S.frameRange(3)));
    uicontrol(figA,'Style','pushbutton','Units','normalized', ...
        'String','export track', 'Position',[0.80 0.245 0.15 0.03], ...
        'TooltipString', ['Writes landmarks_track.csv and partMetrics_track.csv ' ...
            'across every frame you have visited, not just this one.'], ...
        'Callback', @(~,~) onExportTrack());
end

% What the 3-D window draws besides the parts. Off makes a cleaner figure.
chkCloud = uicontrol(figA,'Style','checkbox','Units','normalized', ...
    'String','3D: stereo cloud (c)', 'Value', S.showCloud, ...
    'BackgroundColor',[0.94 0.94 0.94], 'Position',[0.815 0.150 0.16 0.032], ...
    'TooltipString', ['Show the dense stereo points in the 3-D window. ' ...
        'Useful context while digitising, clutter in a figure.'], ...
    'Callback', @(src,~) onShowCloud(src.Value));
chkBox = uicontrol(figA,'Style','checkbox','Units','normalized', ...
    'String','3D: volume box (b)', 'Value', S.showBox, ...
    'BackgroundColor',[0.94 0.94 0.94], 'Position',[0.815 0.118 0.16 0.032], ...
    'Callback', @(src,~) onShowBox(src.Value));

uicontrol(figA,'Style','text','Units','normalized','Position',[0.03 0.19 0.10 0.03], ...
    'String','parts','FontWeight','bold','HorizontalAlignment','left', ...
    'BackgroundColor',[0.94 0.94 0.94]);
lstParts = uicontrol(figA,'Style','listbox','Units','normalized', ...
    'Position',[0.03 0.03 0.16 0.16], 'Callback', @(src,~) onSelectPart(src.Value));

bw = 0.085;  bh = 0.045;  bx = 0.21;  by = 0.14;
uicontrol(figA,'Style','pushbutton','Units','normalized','String','new part (n)', ...
    'Position',[bx by bw bh], 'Callback', @(~,~) onNewPart());
uicontrol(figA,'Style','pushbutton','Units','normalized','String','rename', ...
    'Position',[bx+bw+0.01 by bw bh], 'Callback', @(~,~) onRename());
uicontrol(figA,'Style','pushbutton','Units','normalized','String','delete part', ...
    'Position',[bx+2*(bw+0.01) by bw bh], 'Callback', @(~,~) onDeletePart());
btnMode = uicontrol(figA,'Style','togglebutton','Units','normalized', ...
    'String','edit mode', 'Position',[bx+3*(bw+0.01) by bw bh], ...
    'Callback', @(src,~) onMode(src.Value));

by2 = by - bh - 0.015;
uicontrol(figA,'Style','pushbutton','Units','normalized','String','undo (u)', ...
    'Position',[bx by2 bw bh], 'Callback', @(~,~) onUndo());
uicontrol(figA,'Style','pushbutton','Units','normalized','String','del point', ...
    'Position',[bx+bw+0.01 by2 bw bh], 'Callback', @(~,~) onDeletePoint());
uicontrol(figA,'Style','pushbutton','Units','normalized','String','insert pt', ...
    'Position',[bx+2*(bw+0.01) by2 bw bh], 'Callback', @(~,~) onInsertPoint());
uicontrol(figA,'Style','pushbutton','Units','normalized','String','metrics (m)', ...
    'Position',[bx+3*(bw+0.01) by2 bw bh], 'Callback', @(~,~) onMetrics());

bx2 = bx + 4*(bw+0.01);
uicontrol(figA,'Style','pushbutton','Units','normalized','String','save', ...
    'Position',[bx2 by bw bh], 'Callback', @(~,~) onSave());
uicontrol(figA,'Style','pushbutton','Units','normalized','String','export csv', ...
    'Position',[bx2 by2 bw bh], 'Callback', @(~,~) onExport());
uicontrol(figA,'Style','checkbox','Units','normalized', ...
    'String','snap to epipolar', 'Value', S.snap, ...
    'BackgroundColor',[0.94 0.94 0.94], ...
    'Position',[bx2+bw+0.015 by bw*1.4 bh], ...
    'Callback', @(src,~) onSnap(src.Value));
uicontrol(figA,'Style','pushbutton','Units','normalized','String','reset zoom', ...
    'Position',[bx2+bw+0.015 by2 bw*1.4 bh], 'Callback', @(~,~) resetZoom());

txtStatus = uicontrol(figA,'Style','text','Units','normalized', ...
    'Position',[0.21 0.03 0.76 0.05], 'HorizontalAlignment','left', ...
    'FontName','Consolas','FontSize',9, 'BackgroundColor',[0.94 0.94 0.94]);

figA.WindowButtonMotionFcn = @(~,~) onMotion();
figA.WindowButtonUpFcn     = @(~,~) onMouseUp();
figA.KeyPressFcn           = @(~,e) onKey(e);
figA.WindowScrollWheelFcn  = @(~,e) onScroll(e);
% Scroll zooms about the cursor and right/middle-drag pans, so left-click
% stays free for digitising. MATLAB's built-in zoom and pan modes would
% swallow the ButtonDownFcn the whole tool relies on.
figA.WindowButtonDownFcn   = @(~,~) onFigDown();

% ---- 3-D window ---------------------------------------------------------
fig3 = figure('Name','landmarkAnnotator - 3D', 'NumberTitle','off', ...
    'Color','w', 'Units','normalized', 'Position',[0.60 0.20 0.38 0.68]);
ax3 = axes(fig3); hold(ax3,'on'); grid(ax3,'on'); set(ax3,'Box','on');
% Kept as a handle rather than drawn and forgotten, so it can be hidden: the
% dense cloud is useful context while digitising but gets in the way of a
% figure meant to show the parts.
hCloud = gobjects(1);
if ~isempty(S.cloud)
    hCloud = scatter3(ax3, S.cloud(:,1), S.cloud(:,2), S.cloud(:,3), 3, ...
        [0.72 0.72 0.75], 'filled');
    hCloud.Visible = onOff(S.showCloud);
end
hBox3 = drawBox3(ax3, S.boxLo, S.boxHi);
hBox3.Visible = onOff(S.showBox);
hRay = plot3(ax3, nan, nan, nan, '-', 'Color',[1 0.6 0.1], 'LineWidth',1.4);
hAxis3 = plot3(ax3, nan, nan, nan, '-', 'Color',[0.15 0.15 0.15], ...
    'LineWidth', 3);
hActive = plot3(ax3, nan, nan, nan, 'o', 'MarkerSize',11, ...
    'MarkerEdgeColor','k', 'MarkerFaceColor',[1 0.85 0.1], 'LineWidth',1.2);
h3 = gobjects(0,1);
axis(ax3,'equal'); axis(ax3,'vis3d'); view(ax3, 40, 20);
xlabel(ax3, sprintf('X (%s)', cfg.units));
ylabel(ax3, sprintf('Y (%s)', cfg.units));
zlabel(ax3, sprintf('Z (%s)', cfg.units));
title(ax3, 'live reconstruction  -  drag a marker and watch this update');
pad = 0.35 * (S.boxHi - S.boxLo);
xlim(ax3, [S.boxLo(1)-pad(1) S.boxHi(1)+pad(1)]);
ylim(ax3, [S.boxLo(2)-pad(2) S.boxHi(2)+pad(2)]);
zlim(ax3, [S.boxLo(3)-pad(3) S.boxHi(3)+pad(3)]);

tryLoadSession();
rebuildPartGraphics();
refreshList();
redraw();
setStatus();

%% =================================================== NESTED: THE PAIR

    function rebuildViews()
        %REBUILDVIEWS Crop each of the current pair's views to the animal and
        %   scale it to the panel. Called at load, on every pair switch, and
        %   (video mode) on every frame navigation.
        for vv = 1:2
            kk2 = pairIdx(vv);
            if S.videoMode, loadFrame(kk2); end
            if S.cfg.cropToMask
                st = regionprops(S.M(kk2).mask, 'BoundingBox', 'Area');
                [~, bi2] = max([st.Area]);
                bb = st(bi2).BoundingBox;
                c0 = max(1, floor(bb(1)) - S.cfg.cropMargin);
                r0 = max(1, floor(bb(2)) - S.cfg.cropMargin);
                c1 = min(S.M(kk2).W, ceil(bb(1)+bb(3)) + S.cfg.cropMargin);
                r1 = min(S.M(kk2).H, ceil(bb(2)+bb(4)) + S.cfg.cropMargin);
            else
                c0 = 1;  r0 = 1;  c1 = S.M(kk2).W;  r1 = S.M(kk2).H;
            end
            crop = S.M(kk2).rgb(r0:r1, c0:c1, :);
            sc = min(1, S.cfg.dispMaxDim / max(size(crop,1), size(crop,2)));
            S.view(vv) = struct('cam', kk2, 'r0', r0, 'c0', c0, 'scale', sc, ...
                'img', imresize(crop, sc), 'H', S.M(kk2).H, 'W', S.M(kk2).W);
        end
    end

    function loadFrame(camIdx)
        %LOADFRAME Video mode only: decode S.frame from camIdx's reader and
        %   undistort it into S.M(camIdx).rgb, in the same virtual pinhole
        %   camera the single-image path's textures are undistorted into
        %   (vh.undistortFrame - same calibration object, same OutputView).
        %   Called from rebuildViews() for whichever cameras are in the
        %   active pair, so only those ever get decoded - not all nCams.
        raw = read(S.vidReaders{camIdx}, S.frame);
        S.M(camIdx).rgb = vh.undistortFrame(raw, S.calibObj, S.calibKind, ...
            'method', 'linear', 'scaleFactor', S.cfg.undistortScale);
    end

    function onSwitchPair(q)
        %ONSWITCHPAIR Digitise the same animal through a different camera pair.
        %   3-D landmarks are pair-independent, so work carries across: the
        %   current pair's clicks are stashed, and the new pair's 2-D points
        %   are restored if you have been here before, or seeded by
        %   reprojecting the existing 3-D if you have not. Either way you
        %   arrive with the parts already drawn and only need to nudge them.
        if q < 1 || q > size(S.pairList,1), return, end
        newA = S.pairList(q,1);  newB = S.pairList(q,2);
        if newA == S.a && newB == S.b, return, end

        pushUndo();
        stashPair();                       % remember the pair we are leaving

        S.a = newA;  S.b = newB;
        S.F = vh.fundamentalFromDLT(S.P(:,:,S.a), S.P(:,:,S.b), ...
            S.M(S.a).H, S.M(S.b).H, S.yOrigin);
        rebuildViews();

        % Repaint both panels for the new cameras.
        for vv = 1:2
            set(hImg(vv), 'CData', S.view(vv).img);
            axV(vv).XLim = [0.5 size(S.view(vv).img,2)+0.5];
            axV(vv).YLim = [0.5 size(S.view(vv).img,1)+0.5];
            title(axV(vv), sprintf('view %s   (DLT camera %d)', ...
                VNAME(vv), pairIdx(vv)));
        end

        restorePair();
        S.awaiting = 'A';  S.dragging = [];  S.panning = [];
        refreshList();  redraw();
        setStatus(sprintf('switched to DLT %d + %d', S.a, S.b));
    end

    function stashPair()
        k2 = pairKey(S.a, S.b);
        for kk2 = 1:numel(S.parts)
            S.parts(kk2).byPair.(k2) = struct('A', S.parts(kk2).A, ...
                                             'B', S.parts(kk2).B);
        end
    end

    function restorePair()
        k2 = pairKey(S.a, S.b);
        for kk2 = 1:numel(S.parts)
            if isfield(S.parts(kk2).byPair, k2)
                S.parts(kk2).A = S.parts(kk2).byPair.(k2).A;
                S.parts(kk2).B = S.parts(kk2).byPair.(k2).B;
            elseif S.cfg.carryAcrossPairs
                % Seed from the 3-D we already have.
                X = S.parts(kk2).XYZ;
                n = size(X,1);
                A = nan(n,2);  B = nan(n,2);
                g = all(isfinite(X), 2);
                if any(g)
                    [ca, ra] = vh.project(S.P(:,:,S.a), X(g,:), ...
                        S.M(S.a).H, S.yOrigin);
                    [cb, rb] = vh.project(S.P(:,:,S.b), X(g,:), ...
                        S.M(S.b).H, S.yOrigin);
                    A(g,:) = [ca ra];  B(g,:) = [cb rb];
                end
                S.parts(kk2).A = A;  S.parts(kk2).B = B;
            else
                % Carry-across is off: this pair starts clean, so parts
                % digitised elsewhere vanish from the panels instead of
                % cluttering them. A and B stay the same LENGTH as XYZ (all
                % NaN) so every array stays index-aligned; the 3-D survives
                % and is drawn faintly, and switching back restores the
                % original clicks from byPair.
                n = size(S.parts(kk2).XYZ, 1);
                S.parts(kk2).A = nan(n,2);
                S.parts(kk2).B = nan(n,2);
            end
            solvePart(kk2);
        end
    end

    function tf = partInThisPair(k)
        %PARTINTHISPAIR Does this part have 2-D points in the current pair?
        tf = ~isempty(S.parts(k).A) && any(all(isfinite(S.parts(k).A), 2));
    end

%% =================================================== NESTED: VIDEO FRAMES
%   Video mode only. Every frame is digitised fresh (no carry-forward, no
%   auto-tracking - confirmed as the wanted behaviour): gotoFrame stashes
%   whatever the outgoing frame had into S.track, blanks the part points
%   (keeping their names, so "part1" means the same thing on every frame),
%   then loads and undistorts the new frame. This mirrors, frame-for-frame,
%   how switching camera pairs already stashes/restores S.parts elsewhere
%   in this file - same pattern, different axis.

    function gotoFrame(n)
        n = max(S.frameRange(1), min(S.frameRange(2), round(n)));
        if ~isfinite(n) || n == S.frame
            edFrame.Value = S.frame;  slFrame.Value = S.frame;
            return
        end

        pushUndo();
        stashFrame();
        S.frame = n;
        resetPartsBlank();

        setStatus(sprintf('loading frame %d ...', n));
        loadFrameUI();

        S.awaiting = 'A';  S.dragging = [];  S.panning = [];
        rebuildPartGraphics();  refreshList();  redraw();
        setStatus(sprintf('frame %d  [range %d-%d step %d]', ...
            n, S.frameRange(1), S.frameRange(2), S.frameRange(3)));
    end

    function loadFrameUI()
        %LOADFRAMEUI Repaint both panels for the current S.frame/S.a/S.b.
        %   Shared by gotoFrame and session-resume, so there is one place
        %   that knows how to put a newly-loaded frame on screen.
        rebuildViews();
        for vv = 1:2
            set(hImg(vv), 'CData', S.view(vv).img);
            axV(vv).XLim = [0.5 size(S.view(vv).img,2)+0.5];
            axV(vv).YLim = [0.5 size(S.view(vv).img,1)+0.5];
        end
        edFrame.Value = S.frame;
        slFrame.Value = S.frame;
    end

    function stashFrame()
        %STASHFRAME Archive the current frame's digitised parts into
        %   S.track, overwriting any earlier archive of the same frame.
        entry = struct('frame', S.frame, 'parts', S.parts, 'pair', [S.a S.b]);
        ti = find([S.track.frame] == S.frame, 1);
        if isempty(ti), S.track(end+1) = entry;
        else,           S.track(ti) = entry;
        end
    end

    function resetPartsBlank()
        %RESETPARTSBLANK Same named parts, no points - "blank every frame".
        names = {S.parts.name};
        S.parts = struct('name',{},'color',{},'A',{},'B',{},'XYZ',{}, ...
            'resid',{},'epiDist',{},'byPair',{});
        for k = 1:numel(names)
            S.parts = addPartStruct(S.parts, names{k});
        end
        S.active = min(max(S.active,1), numel(S.parts));
        S.activePt = 0;
    end

%% ================================================ NESTED: INTERACTION

    function onImageClick(v)
        if ~strcmp(figA.SelectionType, 'normal'), return, end   % pan uses the others
        if ~strcmp(S.mode,'place'), return, end
        p = currentPointFull(v);
        if isempty(p), return, end
        pushUndo();

        k = S.active;
        if strcmp(S.awaiting,'A')
            if v ~= 1
                setStatus('click in view A for this landmark');  return
            end
            S.parts(k).A(end+1,:) = p;
            S.parts(k).B(end+1,:) = [NaN NaN];
            S.parts(k).XYZ(end+1,:) = [NaN NaN NaN];
            S.parts(k).resid(end+1,1) = NaN;
            S.parts(k).epiDist(end+1,1) = NaN;
            S.activePt = size(S.parts(k).A,1);
            S.awaiting = 'B';
        else
            if v ~= 2
                setStatus('click in view B to complete this landmark');  return
            end
            j = size(S.parts(k).A,1);
            S.parts(k).B(j,:) = applySnap(S.parts(k).A(j,:), p);
            solvePart(k);
            S.activePt = j;
            S.awaiting = 'A';
        end
        redraw();  refreshList();  setStatus();
    end

    function [pOut, dist] = applySnap(pA, pB)
        %APPLYSNAP Measure how far the view-B click sits off the epipolar
        %   line of the view-A click, and optionally project it on.
        %   The distance is recorded either way: it is the snap-invariant
        %   measure of whether the two clicks agree with the calibration.
        pOut = pB;  dist = NaN;
        if any(~isfinite(pA)), return, end
        l = S.F * [pA(:); 1];
        nrm = hypot(l(1), l(2));
        if nrm < eps, return, end
        dist = abs(l(1)*pB(1) + l(2)*pB(2) + l(3)) / nrm;
        if S.snap
            u = [l(1) l(2)] / nrm;                 % unit normal of the line
            sgn = (l(1)*pB(1) + l(2)*pB(2) + l(3)) / nrm;
            pOut = pB - sgn * u;
        end
    end

    function onMarkerDown(v, k)
        if ~strcmp(figA.SelectionType, 'normal'), return, end
        if ~strcmp(S.mode,'edit'), return, end
        p = currentPointDisp(v);
        if isempty(p), return, end
        XY = viewPts(k, v);
        good = all(isfinite(XY), 2);
        if ~any(good), return, end
        dxy = nan(size(XY));
        dxy(good,:) = f2d(v, XY(good,:));
        dd = hypot(dxy(:,1)-p(1), dxy(:,2)-p(2));
        [mn, j] = min(dd);
        if ~isfinite(mn) || mn > 25, return, end
        pushUndo();
        S.active = k;  S.activePt = j;
        S.dragging = struct('part',k,'pt',j,'view',v);
        refreshList();  redraw();  setStatus();
    end

    function onFigDown()
        % Right or middle button starts a pan; left is left alone.
        if strcmp(figA.SelectionType, 'normal'), return, end
        for vv = 1:2
            p = currentPointDisp(vv);
            if isempty(p), continue, end
            S.panning = struct('view', vv, 'p0', p, ...
                'xl', axV(vv).XLim, 'yl', axV(vv).YLim);
            return
        end
    end

    function onScroll(e)
        for vv = 1:2
            p = currentPointDisp(vv);
            if isempty(p), continue, end
            f = S.cfg.zoomStep ^ double(e.VerticalScrollCount);
            xl = axV(vv).XLim;  yl = axV(vv).YLim;
            nx = p(1) + (xl - p(1)) * f;
            ny = p(2) + (yl - p(2)) * f;
            W = size(S.view(vv).img,2);  H = size(S.view(vv).img,1);
            if diff(nx) > W || diff(ny) > H, resetZoomOne(vv); return, end
            if diff(nx) < 12, return, end
            axV(vv).XLim = nx;  axV(vv).YLim = ny;
            return
        end
    end

    function resetZoom()
        for vv = 1:2, resetZoomOne(vv); end
    end

    function resetZoomOne(vv)
        axV(vv).XLim = [0.5 size(S.view(vv).img,2)+0.5];
        axV(vv).YLim = [0.5 size(S.view(vv).img,1)+0.5];
    end

    function onSnap(val)
        S.snap = logical(val);
        setStatus();
    end

    function onShowCloud(val)
        S.showCloud = logical(val);
        chkCloud.Value = S.showCloud;      % keep the box and key in step
        if ~isempty(hCloud) && isgraphics(hCloud)
            hCloud.Visible = onOff(S.showCloud);
        end
        setStatus(sprintf('stereo cloud %s', onOff(S.showCloud)));
    end

    function onShowBox(val)
        S.showBox = logical(val);
        chkBox.Value = S.showBox;
        if isgraphics(hBox3), hBox3.Visible = onOff(S.showBox); end
        setStatus(sprintf('volume box %s', onOff(S.showBox)));
    end

    function onCarry(val)
        S.cfg.carryAcrossPairs = logical(val);
        if val
            setStatus('switching pairs will reproject existing parts');
        else
            setStatus(['switching pairs will start clean - parts from the ' ...
                'other pair stay in 3-D but leave the panels']);
        end
    end

    function onMotion()
        % Epipolar guide follows the cursor over either image.
        for v = 1:2
            p = currentPointFull(v);
            if isempty(p), continue, end
            other = 3 - v;
            ko = pairIdx(other);
            xy = vh.epipolarLine(S.F, p, [S.M(ko).H S.M(ko).W], v);
            if isempty(xy)
                set(hEpi(other), 'XData', nan, 'YData', nan);
            else
                dxy = f2d(other, xy);
                set(hEpi(other), 'XData', dxy(:,1), 'YData', dxy(:,2));
            end
            set(hEpi(v), 'XData', nan, 'YData', nan);
        end

        if ~isempty(S.panning)
            vv = S.panning.view;
            p = currentPointDisp(vv);
            if isempty(p), return, end
            d = S.panning.p0 - p;
            axV(vv).XLim = S.panning.xl + d(1);
            axV(vv).YLim = S.panning.yl + d(2);
            return
        end

        if ~isempty(S.dragging)
            v = S.dragging.view;
            p = currentPointFull(v);
            if isempty(p), return, end
            k = S.dragging.part;  j = S.dragging.pt;
            if v == 1
                S.parts(k).A(j,:) = p;
            else
                S.parts(k).B(j,:) = applySnap(S.parts(k).A(j,:), p);
            end
            solvePart(k);
            redraw();  setStatus();
        end
    end

    function onMouseUp()
        S.panning = [];
        if ~isempty(S.dragging)
            S.dragging = [];
            refreshList();  setStatus();
        end
    end

    function onKey(e)
        switch e.Key
            case 'n',       onNewPart();
            case 'u',       onUndo();
            case 'm',       onMetrics();
            case 'i',       onInsertPoint();
            case 'z',       resetZoom();
            case 'r',       S.showReproj = ~S.showReproj; redraw();
            case 'c',       onShowCloud(~S.showCloud);
            case 'b',       onShowBox(~S.showBox);
            case {'delete','backspace'}, onDeletePoint();
            case 'leftarrow'
                S.activePt = max(1, S.activePt-1);  redraw();  setStatus();
            case 'rightarrow'
                S.activePt = min(size(S.parts(S.active).A,1), S.activePt+1);
                redraw();  setStatus();
            case 'escape',  S.awaiting = 'A'; setStatus();
            otherwise
                n = str2double(e.Key);
                if ~isnan(n) && n >= 1 && n <= numel(S.parts)
                    onSelectPart(n);
                end
        end
    end

%% ==================================================== NESTED: GEOMETRY

    function solvePart(k)
        %SOLVEPART Triangulate every complete landmark of one part.
        A = S.parts(k).A;  B = S.parts(k).B;
        n = size(A,1);
        % Keep any 3-D we already have for landmarks this pair cannot see -
        % when carryAcrossPairs is off, A and B are all NaN here and the
        % 3-D from the other pair must survive rather than be wiped.
        S.parts(k).XYZ   = sizeTo(S.parts(k).XYZ, n, 3);
        S.parts(k).resid = nan(n,1);
        S.parts(k).epiDist = nan(n,1);
        Pa = S.P(:,:,S.a);  Pb = S.P(:,:,S.b);
        Ha = S.M(S.a).H;    Hb = S.M(S.b).H;
        for j = 1:n
            if any(~isfinite(A(j,:))) || any(~isfinite(B(j,:))), continue, end
            l = S.F * [A(j,:).'; 1];
            nrm = hypot(l(1), l(2));
            if nrm > eps
                S.parts(k).epiDist(j) = ...
                    abs(l(1)*B(j,1) + l(2)*B(j,2) + l(3)) / nrm;
            end
            uv = [vh.imageToDLT(A(j,:), Ha, S.yOrigin)
                  vh.imageToDLT(B(j,:), Hb, S.yOrigin)];
            X = vh.triangulate(cat(3,Pa,Pb), uv);
            if any(~isfinite(X)), continue, end
            S.parts(k).XYZ(j,:) = X;
            [ca, ra] = vh.project(Pa, X, Ha, S.yOrigin);
            [cb, rb] = vh.project(Pb, X, Hb, S.yOrigin);
            % With free clicks in two views this residual is real: it is how
            % far the two clicks are from agreeing with the calibration.
            S.parts(k).resid(j) = 0.5*(hypot(ca-A(j,1), ra-A(j,2)) + ...
                                      hypot(cb-B(j,1), rb-B(j,2)));
        end
    end

    function [C, dir_] = backRay(v, p)
        %BACKRAY Camera centre and unit direction for a clicked point.
        k = pairIdx(v);
        Pk = S.P(:,:,k);
        C = -Pk(:,1:3) \ Pk(:,4);
        uv = vh.imageToDLT(p, S.M(k).H, S.yOrigin);
        dir_ = Pk(:,1:3) \ [uv(1); uv(2); 1];
        dir_ = dir_ / norm(dir_);
        if dot(S.centre(:) - C, dir_) < 0, dir_ = -dir_; end
    end

%% ====================================================== NESTED: DRAWING

    function rebuildPartGraphics()
        delete(hPartLine(ishandle(hPartLine)));
        delete(hPartRepro(ishandle(hPartRepro)));
        delete(h3(ishandle(h3)));
        nL = numel(S.parts);
        hPartLine  = gobjects(nL,2);
        hPartRepro = gobjects(nL,2);
        h3 = gobjects(nL,1);
        for k = 1:nL
            for v = 1:2
                hPartLine(k,v) = plot(axV(v), nan, nan, '-o', ...
                    'Color', S.parts(k).color, 'MarkerFaceColor', 'w', ...
                    'MarkerSize', 7, 'LineWidth', 1.4);
                hPartLine(k,v).ButtonDownFcn = @(~,~) onMarkerDown(v, k);
                hPartRepro(k,v) = plot(axV(v), nan, nan, ':', ...
                    'Color', S.parts(k).color, 'LineWidth', 1.6, ...
                    'HitTest','off','PickableParts','none');
            end
            h3(k) = plot3(ax3, nan, nan, nan, '-o', ...
                'Color', S.parts(k).color, 'MarkerFaceColor', S.parts(k).color, ...
                'MarkerSize', 5, 'LineWidth', 2);
        end
        uistack(hActive, 'top');
    end

    function redraw()
        pick = 'none';
        if strcmp(S.mode,'edit'), pick = 'visible'; end

        for k = 1:numel(S.parts)
            for v = 1:2
                XY = viewPts(k, v);
                good = all(isfinite(XY), 2);
                dxy = nan(size(XY));
                if any(good), dxy(good,:) = f2d(v, XY(good,:)); end
                lw = 1.2;  ms = 6;
                if k == S.active, lw = 2.2; ms = 9; end
                set(hPartLine(k,v), 'XData', dxy(:,1), 'YData', dxy(:,2), ...
                    'LineWidth', lw, 'MarkerSize', ms, 'PickableParts', pick);

                % Marker face encodes the residual: green consistent, red not.
                if any(good)
                    r = partEpi(k);
                    fc = [0.2 0.75 0.3];
                    if any(isfinite(r)) && median(r(isfinite(r))) > S.cfg.residWarnPx
                        fc = [0.9 0.25 0.2];
                    end
                    set(hPartLine(k,v), 'MarkerFaceColor', fc);
                end

                % Optional: the 3-D polyline pushed back into the image.
                if S.showReproj
                    X = S.parts(k).XYZ;
                    g = all(isfinite(X),2);
                    if nnz(g) >= 2
                        kk = pairIdx(v);
                        [cc, rr] = vh.project(S.P(:,:,kk), X(g,:), ...
                            S.M(kk).H, S.yOrigin);
                        rd = f2d(v, [cc rr]);
                        set(hPartRepro(k,v), 'XData', rd(:,1), 'YData', rd(:,2));
                    else
                        set(hPartRepro(k,v), 'XData', nan, 'YData', nan);
                    end
                else
                    set(hPartRepro(k,v), 'XData', nan, 'YData', nan);
                end
            end

            X = S.parts(k).XYZ;
            g = all(isfinite(X), 2);
            lw3 = 1.6;  if k == S.active, lw3 = 3; end
            % Parts with no points in the current pair are drawn faintly, so
            % you can still see where they are in 3-D without them reading
            % as part of what you are working on.
            if partInThisPair(k)
                c3 = S.parts(k).color;  a3 = 1;
            else
                c3 = 0.55 + 0.45*S.parts(k).color;  a3 = 0.45;  lw3 = 1.2;
            end
            set(h3(k), 'XData', X(g,1), 'YData', X(g,2), 'ZData', X(g,3), ...
                'LineWidth', lw3, 'Color', [c3 a3], ...
                'MarkerFaceColor', min(c3,1));
        end

        % Selected landmark, in 3-D and in both images.
        k = S.active;
        X = S.parts(k).XYZ;
        j = S.activePt;
        if j < 1 || j > size(X,1), j = size(X,1); end
        if j >= 1 && all(isfinite(X(j,:)))
            set(hActive, 'XData', X(j,1), 'YData', X(j,2), 'ZData', X(j,3));
        else
            set(hActive, 'XData', nan, 'YData', nan, 'ZData', nan);
        end
        for vv = 1:2
            XY = viewPts(k, vv);
            if j >= 1 && j <= size(XY,1) && all(isfinite(XY(j,:)))
                q = f2d(vv, XY(j,:));
                set(hSel(vv), 'XData', q(1), 'YData', q(2));
            else
                set(hSel(vv), 'XData', nan, 'YData', nan);
            end
        end

        % Body axis, so the frame the angles are measured in is visible.
        bi = find(strcmpi({S.parts.name}, 'body'), 1);
        set(hAxis3, 'XData', nan, 'YData', nan, 'ZData', nan);
        if ~isempty(bi)
            Xb = S.parts(bi).XYZ;
            Xb = Xb(all(isfinite(Xb),2), :);
            if size(Xb,1) >= 2
                set(hAxis3, 'XData', Xb([1 end],1), 'YData', Xb([1 end],2), ...
                    'ZData', Xb([1 end],3));
            end
        end

        set(hRay, 'XData', nan, 'YData', nan, 'ZData', nan);
        if strcmp(S.awaiting,'B') && ~isempty(S.parts(k).A)
            p = S.parts(k).A(end,:);
            if all(isfinite(p))
                [C, dv] = backRay(1, p);
                [t0, t1] = clipRayBox(C, dv, S.boxLo(:), S.boxHi(:));
                if isfinite(t0)
                    e = [C + t0*dv, C + t1*dv];
                    set(hRay, 'XData', e(1,:), 'YData', e(2,:), 'ZData', e(3,:));
                end
            end
        end
        drawnow limitrate
    end

%% ==================================================== NESTED: PART ADMIN

    function onSelectPart(k)
        if k < 1 || k > numel(S.parts), return, end
        S.active = k;  S.awaiting = 'A';
        refreshList();  redraw();  setStatus();
    end

    function onNewPart()
        pushUndo();
        S.parts = addPartStruct(S.parts, sprintf('part%d', numel(S.parts)));
        S.active = numel(S.parts);  S.awaiting = 'A';
        rebuildPartGraphics();  refreshList();  redraw();  setStatus();
    end

    function onRename()
        a = inputdlg('Part name:', 'Rename', 1, {S.parts(S.active).name});
        if isempty(a), return, end
        S.parts(S.active).name = a{1};
        refreshList();
    end

    function onDeletePart()
        if numel(S.parts) <= 1, return, end
        pushUndo();
        S.parts(S.active) = [];
        S.active = max(1, S.active-1);
        rebuildPartGraphics();  refreshList();  redraw();  setStatus();
    end

    function onDeletePoint()
        k = S.active;
        n = size(S.parts(k).A,1);
        if n == 0, return, end
        j = S.activePt;
        if j < 1 || j > n, j = n; end          % default to the last
        pushUndo();
        S.parts(k).A(j,:) = [];  S.parts(k).B(j,:) = [];
        S.parts(k).XYZ(j,:) = []; S.parts(k).resid(j) = [];
        if numel(S.parts(k).epiDist) >= j, S.parts(k).epiDist(j) = []; end
        S.activePt = min(j, size(S.parts(k).A,1));
        S.awaiting = 'A';
        solvePart(k);
        redraw();  refreshList();  setStatus();
    end

    function onInsertPoint()
        %ONINSERTPOINT Add a landmark after the selected one, midway to the
        %   next, so you can drag it into place rather than re-digitising.
        k = S.active;
        n = size(S.parts(k).A,1);
        if n < 2
            setStatus('need at least 2 landmarks before inserting');  return
        end
        j = S.activePt;
        if j < 1 || j >= n, j = n-1; end
        pushUndo();
        midA = mean(S.parts(k).A(j:j+1,:), 1);
        midB = mean(S.parts(k).B(j:j+1,:), 1);
        S.parts(k).A = [S.parts(k).A(1:j,:); midA; S.parts(k).A(j+1:end,:)];
        S.parts(k).B = [S.parts(k).B(1:j,:); midB; S.parts(k).B(j+1:end,:)];
        solvePart(k);
        S.activePt = j+1;
        S.mode = 'edit';  btnMode.Value = 1;  btnMode.String = 'place mode';
        redraw();  refreshList();
        setStatus('inserted a landmark - drag it into place (edit mode)');
    end

    function onMetrics()
        [T, fr] = vh.segmentMetrics(S.parts);
        fprintf('\n===== part metrics (%s) =====\n', S.cfg.units);
        if ~fr.valid
            fprintf('  body frame not established: %s\n', fr.note);
        else
            fprintf('  body axis (%.3f %.3f %.3f) from origin (%.3f %.3f %.3f)\n', ...
                fr.e1, fr.origin);
            if ~isempty(fr.note), fprintf('  note: %s\n', fr.note); end
        end
        disp(T);
        setStatus('metrics printed to the command window');
    end

    function onMode(val)
        if val, S.mode = 'edit'; else, S.mode = 'place'; end
        btnMode.String = ternary(val, 'place mode', 'edit mode');
        S.awaiting = 'A';
        redraw();  setStatus();
    end

    function refreshList()
        items = cell(numel(S.parts),1);
        for k = 1:numel(S.parts)
            r = partEpi(k);  r = r(isfinite(r));
            if isempty(r), rs = '  -'; else, rs = sprintf('%4.1f', median(r)); end
            items{k} = sprintf('%d %-8s n=%-2d epi=%s', k, S.parts(k).name, ...
                size(S.parts(k).A,1), rs);
        end
        lstParts.String = items;
        lstParts.Value = min(S.active, numel(items));
    end

%% ======================================================= NESTED: SESSION

    function pushUndo()
        S.undoStack{end+1} = S.parts;
        if numel(S.undoStack) > 25, S.undoStack(1) = []; end
    end

    function onUndo()
        if isempty(S.undoStack), return, end
        S.parts = S.undoStack{end};  S.undoStack(end) = [];
        S.active = min(S.active, numel(S.parts));
        S.awaiting = 'A';
        rebuildPartGraphics();  refreshList();  redraw();  setStatus();
    end

    function onSave()
        if S.videoMode, stashFrame(); end     % archive work in progress too
        session = struct('parts', S.parts, 'pair', [S.a S.b], ...
            'camOrder', S.cfg.camOrder, 'yOrigin', S.yOrigin, ...
            'dataDir', S.cfg.dataDir, 'createdOn', datetime('now'));
        if S.videoMode
            session.track      = S.track;
            session.frame      = S.frame;
            session.frameRange = S.frameRange;
        end
        save(S.cfg.sessionFile, 'session');
        setStatus(sprintf('saved -> %s', S.cfg.sessionFile));
    end

    function tryLoadSession()
        f = S.cfg.sessionFile;
        if ~isfile(f), return, end
        try
            L = load(f);
            if isfield(L,'session')
                % 'parts' is the current field name; 'legs' is what sessions
                % saved before this tool was generalized used - read either.
                if isfield(L.session,'parts'),   partsIn = L.session.parts;
                elseif isfield(L.session,'legs'), partsIn = L.session.legs;
                else, partsIn = []; end
            else
                partsIn = [];
            end
            if ~isempty(partsIn)
                S.parts = partsIn;
                % Fields added after earlier sessions were saved.
                if ~isfield(S.parts, 'epiDist')
                    [S.parts.epiDist] = deal(zeros(0,1));
                end
                if ~isfield(S.parts, 'byPair')
                    [S.parts.byPair] = deal(struct());
                end
                S.active = min(S.active, numel(S.parts));
                for k = 1:numel(S.parts), solvePart(k); end
                fprintf('  loaded %d part(s) from %s\n', numel(S.parts), f);
            end
            if S.videoMode && isfield(L,'session') && isfield(L.session,'track')
                S.track = L.session.track;
                fprintf('  loaded %d tracked frame(s) from %s\n', numel(S.track), f);
                if isfield(L.session,'frame') && L.session.frame ~= S.frame
                    S.frame = max(S.frameRange(1), ...
                        min(S.frameRange(2), L.session.frame));
                    loadFrameUI();
                end
            end
        catch
        end
    end

    function onExport()
        rows = {};
        for k = 1:numel(S.parts)
            for j = 1:size(S.parts(k).A,1)
                rows(end+1,:) = {S.parts(k).name, j, ...
                    S.parts(k).XYZ(j,1), S.parts(k).XYZ(j,2), S.parts(k).XYZ(j,3), ...
                    S.parts(k).resid(j), epiOf(k,j), ...
                    S.parts(k).A(j,1), S.parts(k).A(j,2), ...
                    S.parts(k).B(j,1), S.parts(k).B(j,2)};
            end
        end
        if isempty(rows), setStatus('nothing to export'); return, end
        T = cell2table(rows, 'VariableNames', ...
            {'part','point','X','Y','Z','residPx','epiPx','uA','vA','uB','vB'});
        f = fullfile(S.cfg.dataDir, 'landmarks.csv');
        writetable(T, f);

        [Tm, fr] = vh.segmentMetrics(S.parts);
        fm = fullfile(S.cfg.dataDir, 'partMetrics.csv');
        writetable(Tm, fm);
        note = '';
        if ~fr.valid, note = ' (body frame not established - angles are NaN)'; end
        setStatus(sprintf('exported %d landmark(s) and %d part metric row(s)%s', ...
            height(T), height(Tm), note));
        fprintf('  -> %s\n  -> %s\n', f, fm);
    end

    function onExportTrack()
        %ONEXPORTTRACK Video mode only. Every frame you have visited (not
        %   just the one on screen), as two long-format CSVs: one row per
        %   point per part per frame, and vh.segmentMetrics run once per
        %   frame for the time series of each part's length/span/angles.
        stashFrame();
        if isempty(S.track), setStatus('nothing to export'); return, end

        rows = {};
        metricsAll = table();
        for ti = 1:numel(S.track)
            fr = S.track(ti).frame;
            pts = S.track(ti).parts;
            for k = 1:numel(pts)
                for j = 1:size(pts(k).A,1)
                    epi = NaN;
                    if isfield(pts,'epiDist') && numel(pts(k).epiDist) >= j
                        epi = pts(k).epiDist(j);
                    end
                    rows(end+1,:) = {fr, pts(k).name, j, ...
                        pts(k).XYZ(j,1), pts(k).XYZ(j,2), pts(k).XYZ(j,3), ...
                        pts(k).resid(j), epi, ...
                        pts(k).A(j,1), pts(k).A(j,2), pts(k).B(j,1), pts(k).B(j,2)};
                end
            end
            Tm = vh.segmentMetrics(pts);
            if height(Tm) > 0
                Tm = addvars(Tm, repmat(fr, height(Tm), 1), ...
                    'Before', 1, 'NewVariableNames', 'frame');
                metricsAll = [metricsAll; Tm]; %#ok<AGROW>
            end
        end

        if isempty(rows), setStatus('nothing to export'); return, end
        T = cell2table(rows, 'VariableNames', ...
            {'frame','part','point','X','Y','Z','residPx','epiPx','uA','vA','uB','vB'});
        f = fullfile(S.cfg.dataDir, 'landmarks_track.csv');
        writetable(T, f);

        fm = fullfile(S.cfg.dataDir, 'partMetrics_track.csv');
        writetable(metricsAll, fm);

        setStatus(sprintf('exported %d landmark row(s) across %d frame(s)', ...
            height(T), numel(S.track)));
        fprintf('  -> %s\n  -> %s\n', f, fm);
    end

    function onClose()
        if ~isempty(S.parts), onSave(); end
        if isvalid(fig3), delete(fig3); end
        delete(figA);
    end

%% ========================================================= NESTED: MISC

    function k = pairIdx(v)
        if v == 1, k = S.a; else, k = S.b; end
    end

    function s = pairKey(a, b)
        s = sprintf('p%d_%d', a, b);
    end

    function XY = viewPts(k, v)
        if v == 1, XY = S.parts(k).A; else, XY = S.parts(k).B; end
    end

    function e = partEpi(k)
        %PARTEPI Epipolar miss distance, tolerant of sessions saved before
        %   the field existed.
        if isfield(S.parts, 'epiDist') && ~isempty(S.parts(k).epiDist)
            e = S.parts(k).epiDist;
        else
            e = nan(size(S.parts(k).A,1), 1);
        end
    end

    function e = epiOf(k, j)
        v = partEpi(k);
        if j >= 1 && j <= numel(v), e = v(j); else, e = NaN; end
    end

    function p = currentPointDisp(v)
        p = [];
        if ~isvalid(axV(v)), return, end
        cp = axV(v).CurrentPoint;
        x = cp(1,1);  y = cp(1,2);
        if x < axV(v).XLim(1) || x > axV(v).XLim(2) || ...
           y < axV(v).YLim(1) || y > axV(v).YLim(2), return, end
        p = [x y];
    end

    function p = currentPointFull(v)
        p = currentPointDisp(v);
        if isempty(p), return, end
        p = d2f(v, p);
    end

    function q = d2f(v, p)
        %D2F display pixel -> full-resolution undistorted image pixel
        V = S.view(v);
        q = [(p(:,1) - 0.5)/V.scale + 0.5 + V.c0 - 1, ...
             (p(:,2) - 0.5)/V.scale + 0.5 + V.r0 - 1];
    end

    function q = f2d(v, p)
        %F2D full-resolution image pixel -> display pixel
        V = S.view(v);
        q = [((p(:,1) - V.c0 + 1) - 0.5)*V.scale + 0.5, ...
             ((p(:,2) - V.r0 + 1) - 0.5)*V.scale + 0.5];
    end

    function setStatus(msg)
        if nargin == 1
            txtStatus.String = msg;  drawnow limitrate;  return
        end
        k = S.active;
        e = partEpi(k);  e = e(isfinite(e));
        if isempty(e), es = '-'; else, es = sprintf('%.1f px', median(e)); end
        if strcmp(S.mode,'place')
            act = sprintf('PLACE - click view %s for landmark %d', ...
                S.awaiting, size(S.parts(k).A,1) + double(strcmp(S.awaiting,'A')));
        else
            act = sprintf('EDIT - drag markers (point %d selected)', S.activePt);
        end
        sn = '';  if S.snap, sn = '  SNAP ON'; end
        txtStatus.String = sprintf(['%s%s  |  part %d "%s", %d landmark(s), ' ...
            'median epipolar miss %s  |  n new part  i insert  m metrics  u undo  ' ...
            'r reproject  z reset zoom  scroll=zoom  right-drag=pan'], ...
            act, sn, k, S.parts(k).name, size(S.parts(k).A,1), es);
        drawnow limitrate
    end

end % landmarkAnnotator


%% =========================================================== LOCAL HELPERS

function f = resolveList(explicitList, dataDir, pattern, what)
%RESOLVELIST An explicit file list if given, otherwise glob the pattern.
if ~isempty(explicitList)
    if isstring(explicitList), f = cellstr(explicitList(:));
    elseif ischar(explicitList), f = {explicitList};
    else, f = cellfun(@char, explicitList(:), 'UniformOutput', false);
    end
    for k = 1:numel(f)
        assert(isfile(f{k}), 'landmarkAnnotator:noFile', ...
            'Listed %s file not found: %s', what, f{k});
    end
    return
end
p = dir(fullfile(dataDir, pattern));
p = p(~[p.isdir]);
assert(~isempty(p), 'landmarkAnnotator:noMatch', ...
    'No %s files matching "%s" in\n  %s', what, pattern, dataDir);
f = fullfile(dataDir, {p.name}');
end


function f = resolveOne(explicitFile, dataDir, patterns, excludeSubstr, what)
%RESOLVEONE One file: the given path, or the first match that is not one of
%   this tool's own outputs. Patterns are tried in order of preference.
if ~isempty(explicitFile)
    f = char(explicitFile);
    assert(isfile(f), 'landmarkAnnotator:noFile', ...
        '%s not found: %s', what, f);
    return
end
for pi = 1:numel(patterns)
    p = dir(fullfile(dataDir, patterns{pi}));
    p = p(~[p.isdir]);
    keep = true(numel(p),1);
    for k = 1:numel(p)
        for e = 1:numel(excludeSubstr)
            if contains(p(k).name, excludeSubstr{e}, 'IgnoreCase', true)
                keep(k) = false;
            end
        end
    end
    p = p(keep);
    if ~isempty(p), f = fullfile(dataDir, p(1).name); return, end
end
error('landmarkAnnotator:noMatch', ...
    'No %s found in\n  %s\n(tried %s)', what, dataDir, strjoin(patterns, ', '));
end


function s = nameOnly(f)
[~, n, e] = fileparts(f);  s = [n e];
end


function M = sizeTo(M, n, w)
%SIZETO Pad or trim a matrix to n rows, filling new rows with NaN.
if isempty(M), M = nan(n, w); return, end
if size(M,1) >= n, M = M(1:n, 1:w); return, end
M = [M(:,1:w); nan(n - size(M,1), w)];
end


function parts = addPartStruct(parts, name)
cmap = lines(12);
c = cmap(mod(numel(parts), 12) + 1, :);
if strcmp(name,'body'), c = [0.1 0.1 0.1]; end
parts(end+1) = struct('name', name, 'color', c, ...
    'A', zeros(0,2), 'B', zeros(0,2), 'XYZ', zeros(0,3), ...
    'resid', zeros(0,1), 'epiDist', zeros(0,1), 'byPair', struct());
end


function [t0, t1] = clipRayBox(C, dv, lo, hi)
%CLIPRAYBOX Parameter range where C + t*dv lies inside the axis-aligned box.
t0 = -inf;  t1 = inf;
for k = 1:3
    if abs(dv(k)) < eps
        if C(k) < lo(k) || C(k) > hi(k), t0 = NaN; t1 = NaN; return, end
    else
        ta = (lo(k) - C(k)) / dv(k);
        tb = (hi(k) - C(k)) / dv(k);
        if ta > tb, tmp = ta; ta = tb; tb = tmp; end
        t0 = max(t0, ta);  t1 = min(t1, tb);
    end
end
if t0 > t1, t0 = NaN; t1 = NaN; end
end


function h = drawBox3(ax, lo, hi)
x = [lo(1) hi(1)];  y = [lo(2) hi(2)];  z = [lo(3) hi(3)];
c = [x([1 2 2 1 1 1 2 2 1 1 2 2 2 2 1 1]).', ...
     y([1 1 2 2 1 1 1 2 2 1 1 1 2 2 2 2]).', ...
     z([1 1 1 1 1 2 2 2 2 2 2 1 1 2 2 1]).'];
h = plot3(ax, c(:,1), c(:,2), c(:,3), '-', 'Color', [0.75 0.75 0.75]);
end


function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end


function XYZ = gatherCloud(outStruct)
XYZ = zeros(0,3);
if ~isfield(outStruct,'pairs'), return, end
for q = 1:numel(outStruct.pairs)
    if ~isfield(outStruct.pairs(q),'clouds'), continue, end
    for mi = 1:numel(outStruct.pairs(q).clouds)
        C = outStruct.pairs(q).clouds(mi);
        if isfield(C,'XYZ') && size(C.XYZ,1) > size(XYZ,1), XYZ = C.XYZ; end
    end
end
end


function o = ternary(c, a, b)
if c, o = a; else, o = b; end
end





