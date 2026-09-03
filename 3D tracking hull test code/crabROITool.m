function crabROITool(videoFile)
%CRABROITOOL Interactive per-frame ROI + colour threshold tool for video.
%
%   crabROITool                 prompts for a video file
%   crabROITool(videoFile)      opens that file
%
%   For a chosen frame you draw an ROI (to exclude glass and water-surface
%   reflections), pick a colour channel and a threshold band, and export
%   either the ROI-masked frame or the ROI + threshold silhouette.
%
%   Settings are stored PER FRAME, because the lighting changes as the crab
%   falls through the tank. Navigating back to a frame you have already set
%   up restores its ROI and thresholds. Scrubbing through frames does NOT
%   add them to the saved set - press "Save settings" (or export) for that,
%   so "All saved" only ever touches frames you deliberately kept.
%
%   Layout
%     left    the frame, with the current view mode applied
%     right   channel / threshold / ROI / cleanup controls, plus a live
%             histogram of the channel inside the ROI
%     bottom  frame number entry, slider and step buttons
%
%   Exports (written to a folder you choose on first export):
%     <base>_f<NNNNN>_roi.png      RGB, outside the ROI blacked out
%     <base>_f<NNNNN>_roimask.png  the ROI itself, binary
%     <base>_f<NNNNN>_seg.png      RGB, outside ROI-and-threshold blacked out
%     <base>_f<NNNNN>_mask.png     the silhouette, binary  <- for the hull
%     <base>_f<NNNNN>_params.mat   channel, thresholds, ROI vertices, cleanup
%
%   All exports are computed at FULL video resolution. The display is
%   downscaled only so the live preview stays responsive; the ROI is
%   rasterised at full resolution from its vertices, not by upsampling.
%
%   Progress is written to <video>_roiSession.mat beside the video and
%   reloaded automatically next time you open the same file.
%
%   Depends on probeChannel.m (same folder) for the channel definitions, so
%   that a threshold set here reproduces exactly in batch code:
%       v = probeChannel(img, channel);  mask = v >= lo & v <= hi;
%
%   Yohan Sequeira - Crab Visual Hull Analysis

%% ---------------------------------------------------------------- SET-UP

thisDir = fileparts(mfilename('fullpath'));
if isempty(thisDir), thisDir = pwd; end
addpath(thisDir);           % probeChannel.m sits beside this file

if nargin < 1 || isempty(videoFile)
    [f, p] = uigetfile({'*.mp4;*.MP4;*.mov;*.MOV;*.avi;*.MTS', 'Video files'; ...
                        '*.*', 'All files'}, 'Select a video');
    if isequal(f, 0), return, end
    videoFile = fullfile(p, f);
end
assert(isfile(videoFile), 'File not found: %s', videoFile);

S = struct();
S.videoFile = videoFile;
[~, S.base] = fileparts(videoFile);
S.reader    = VideoReader(videoFile);
S.fps       = S.reader.FrameRate;
S.Wfull     = S.reader.Width;
S.Hfull     = S.reader.Height;

try
    S.nFrames = S.reader.NumFrames;
catch
    S.nFrames = [];
end
if isempty(S.nFrames) || S.nFrames < 1
    S.nFrames = max(1, floor(S.reader.Duration * S.fps));
end

S.displayMaxDim = 1200;
S.scale = min(1, S.displayMaxDim / max(S.Hfull, S.Wfull));

S.channels = {'RmG','BmG','RmB','GmR','rgRed','rgBlue', ...
              'Lab_a','Lab_b','Lab_L','gray'};

S.frame       = 0;
S.frameFull   = [];     % current frame, full resolution
S.frameDisp   = [];     % current frame, display resolution
S.chanDisp    = [];     % channel of frameDisp
S.roiMaskDisp = [];     % ROI as a display-res logical, [] = whole frame
S.hROI        = [];
S.hImg        = [];
S.outDir      = '';

% Per-frame settings, appended only when you save or export.
S.store = struct('frame',{},'channel',{},'lo',{},'hi',{}, ...
                 'roiType',{},'roiPos',{},'fillHoles',{},'minArea',{}, ...
                 'largestOnly',{});

%% ------------------------------------------------------------------- UI

fig = uifigure('Name', sprintf('crabROITool  -  %s', S.base), ...
    'Position', [60 60 1520 920], 'Color', [0.94 0.94 0.94]);

main = uigridlayout(fig, [3 2]);
main.RowHeight   = {'1x', 56, 20};
main.ColumnWidth = {'1x', 350};
main.Padding     = [8 6 8 6];
main.RowSpacing  = 6;

% ---- image axes ----------------------------------------------------------
ax = uiaxes(main);
ax.Layout.Row = 1; ax.Layout.Column = 1;
ax.YDir = 'reverse';
ax.DataAspectRatio = [1 1 1];
ax.Visible = 'off';
ax.XTick = []; ax.YTick = [];

% ---- control panel -------------------------------------------------------
ctrlPanel = uipanel(main, 'Title', 'Segmentation', 'FontWeight', 'bold');
ctrlPanel.Layout.Row = 1; ctrlPanel.Layout.Column = 2;

cg = uigridlayout(ctrlPanel, [17 2]);
cg.RowHeight = {20, 26, ...          % 1-2   channel
                20, 26, 32, ...      % 3-5   low
                20, 26, 32, ...      % 6-8   high
                28, ...              % 9     auto
                '1x', ...            % 10    histogram
                20, 26, 26, ...      % 11-13 ROI
                24, 26, ...          % 14-15 cleanup
                20, 26};             % 16-17 view
cg.ColumnWidth = {'1x','1x'};
cg.RowSpacing = 4; cg.Padding = [8 6 8 6];

r = 1;
lbl(cg, r, [1 2], 'Colour channel'); r = r+1;
ddChannel = uidropdown(cg, 'Items', S.channels, 'Value', 'RmG');
ddChannel.Layout.Row = r; ddChannel.Layout.Column = [1 2]; r = r+1;

lbl(cg, r, [1 2], 'Threshold low'); r = r+1;
edLo = uieditfield(cg, 'numeric', 'Value', 10, 'ValueDisplayFormat', '%.2f');
edLo.Layout.Row = r; edLo.Layout.Column = 1;
lblRange = uilabel(cg, 'Text', '', 'FontSize', 10, ...
    'FontColor', [0.4 0.4 0.4], 'HorizontalAlignment', 'right');
lblRange.Layout.Row = r; lblRange.Layout.Column = 2; r = r+1;
slLo = uislider(cg, 'MajorTicks', [], 'MinorTicks', []);
slLo.Layout.Row = r; slLo.Layout.Column = [1 2]; r = r+1;

lbl(cg, r, [1 2], 'Threshold high'); r = r+1;
edHi = uieditfield(cg, 'numeric', 'Value', 255, 'ValueDisplayFormat', '%.2f');
edHi.Layout.Row = r; edHi.Layout.Column = 1; r = r+1;
slHi = uislider(cg, 'MajorTicks', [], 'MinorTicks', []);
slHi.Layout.Row = r; slHi.Layout.Column = [1 2]; r = r+1;

btnAuto = uibutton(cg, 'Text', 'Auto threshold (Otsu, inside ROI)');
btnAuto.Layout.Row = r; btnAuto.Layout.Column = [1 2]; r = r+1;

axHist = uiaxes(cg);
axHist.Layout.Row = r; axHist.Layout.Column = [1 2];
axHist.FontSize = 9;
axHist.Toolbar.Visible = 'off';
r = r+1;

lbl(cg, r, [1 2], 'Region of interest'); r = r+1;
ddROITool = uidropdown(cg, 'Items', {'polygon','freehand','rectangle'}, ...
                       'Value', 'polygon');
ddROITool.Layout.Row = r; ddROITool.Layout.Column = 1;
btnDraw = uibutton(cg, 'Text', 'Draw ROI');
btnDraw.Layout.Row = r; btnDraw.Layout.Column = 2; r = r+1;
btnClearROI = uibutton(cg, 'Text', 'Clear ROI');
btnClearROI.Layout.Row = r; btnClearROI.Layout.Column = 1;
btnCopyPrev = uibutton(cg, 'Text', 'Copy nearest');
btnCopyPrev.Layout.Row = r; btnCopyPrev.Layout.Column = 2; r = r+1;

cbFill = uicheckbox(cg, 'Text', 'Fill holes', 'Value', true);
cbFill.Layout.Row = r; cbFill.Layout.Column = 1;
cbLargest = uicheckbox(cg, 'Text', 'Largest blob only', 'Value', false);
cbLargest.Layout.Row = r; cbLargest.Layout.Column = 2; r = r+1;
lblMin = uilabel(cg, 'Text', 'Min area (px)');
lblMin.Layout.Row = r; lblMin.Layout.Column = 1;
edMinArea = uieditfield(cg, 'numeric', 'Value', 200, 'Limits', [0 Inf]);
edMinArea.Layout.Row = r; edMinArea.Layout.Column = 2; r = r+1;

lbl(cg, r, [1 2], 'View'); r = r+1;
ddView = uidropdown(cg, 'Items', ...
    {'original','ROI only','mask overlay','channel map','masked result'}, ...
    'Value', 'mask overlay');
ddView.Layout.Row = r; ddView.Layout.Column = [1 2];

% ---- export panel --------------------------------------------------------
exPanel = uipanel(main, 'Title', 'Export', 'FontWeight', 'bold');
exPanel.Layout.Row = 2; exPanel.Layout.Column = 2;
eg = uigridlayout(exPanel, [1 3]);
eg.Padding = [6 3 6 3]; eg.ColumnSpacing = 4;
btnExpROI = uibutton(eg, 'Text', 'ROI frame');
btnExpSeg = uibutton(eg, 'Text', 'ROI+thresh');
btnExpAll = uibutton(eg, 'Text', 'All saved');

% ---- bottom bar ----------------------------------------------------------
bot = uipanel(main);
bot.Layout.Row = 2; bot.Layout.Column = 1;
bg = uigridlayout(bot, [1 9]);
bg.ColumnWidth = {56, 88, 40, 40, 40, 40, '1x', 165, 116};
bg.Padding = [8 6 8 6]; bg.ColumnSpacing = 6;

uilabel(bg, 'Text', 'Frame', 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'right');
edFrame = uieditfield(bg, 'numeric', 'Value', 1, ...
    'Limits', [1 S.nFrames], 'RoundFractionalValues', true);
btnM10 = uibutton(bg, 'Text', '-10');
btnM1  = uibutton(bg, 'Text', '-1');
btnP1  = uibutton(bg, 'Text', '+1');
btnP10 = uibutton(bg, 'Text', '+10');
slFrame = uislider(bg, 'Limits', [1 max(2, S.nFrames)], 'Value', 1, ...
    'MajorTicks', [], 'MinorTicks', []);
lblFrameInfo = uilabel(bg, 'Text', '', 'FontSize', 11, ...
    'FontColor', [0.3 0.3 0.3]);
btnSaveFrame = uibutton(bg, 'Text', 'Save settings', ...
    'BackgroundColor', [0.80 0.90 0.80]);

% ---- status --------------------------------------------------------------
lblStatus = uilabel(main, 'Text', '', 'FontSize', 10, ...
                    'FontColor', [0.25 0.25 0.25]);
lblStatus.Layout.Row = 3; lblStatus.Layout.Column = [1 2];

%% ------------------------------------------------------------- CALLBACKS

ddChannel.ValueChangedFcn    = @(~,~) onChannelChanged();
edLo.ValueChangedFcn         = @(~,~) onThreshEdit();
edHi.ValueChangedFcn         = @(~,~) onThreshEdit();
slLo.ValueChangingFcn        = @(~,e) onThreshSlide('lo', e.Value);
slHi.ValueChangingFcn        = @(~,e) onThreshSlide('hi', e.Value);
slLo.ValueChangedFcn         = @(~,~) onThreshEdit();
slHi.ValueChangedFcn         = @(~,~) onThreshEdit();
btnAuto.ButtonPushedFcn      = @(~,~) onAuto();

btnDraw.ButtonPushedFcn      = @(~,~) onDrawROI();
btnClearROI.ButtonPushedFcn  = @(~,~) onClearROI();
btnCopyPrev.ButtonPushedFcn  = @(~,~) onCopyNearest();

cbFill.ValueChangedFcn       = @(~,~) refresh();
cbLargest.ValueChangedFcn    = @(~,~) refresh();
edMinArea.ValueChangedFcn    = @(~,~) refresh();
ddView.ValueChangedFcn       = @(~,~) refresh();

edFrame.ValueChangedFcn      = @(~,~) gotoFrame(edFrame.Value);
slFrame.ValueChangedFcn      = @(~,e) gotoFrame(round(e.Value));
btnM10.ButtonPushedFcn       = @(~,~) gotoFrame(S.frame - 10);
btnM1.ButtonPushedFcn        = @(~,~) gotoFrame(S.frame - 1);
btnP1.ButtonPushedFcn        = @(~,~) gotoFrame(S.frame + 1);
btnP10.ButtonPushedFcn       = @(~,~) gotoFrame(S.frame + 10);
btnSaveFrame.ButtonPushedFcn = @(~,~) onSaveFrame();

btnExpROI.ButtonPushedFcn    = @(~,~) exportCurrent('roi');
btnExpSeg.ButtonPushedFcn    = @(~,~) exportCurrent('seg');
btnExpAll.ButtonPushedFcn    = @(~,~) exportAll();

fig.CloseRequestFcn          = @(~,~) onClose();

%% ------------------------------------------------------------------ START

tryLoadSession();
gotoFrame(1);

%% ------------------------------------------------- NESTED: FRAME HANDLING

    function gotoFrame(n)
        n = max(1, min(S.nFrames, round(n)));

        % Update the outgoing frame's entry, but only if it was already
        % saved - scrubbing must not silently add frames to the set.
        stashCurrent(false);

        setStatus(sprintf('Reading frame %d ...', n));
        try
            S.frameFull = read(S.reader, n);
        catch ME
            setStatus(sprintf('Could not read frame %d: %s', n, ME.message));
            return
        end
        S.frame     = n;
        S.frameDisp = imresize(S.frameFull, S.scale);

        edFrame.Value = n;
        slFrame.Value = n;
        lblFrameInfo.Text = sprintf('%d / %d    t = %.3f s', ...
            n, S.nFrames, (n-1)/S.fps);

        clearROIGraphics();
        k = findStored(n);
        if isempty(k)
            computeChannel();
            setSliderRange();
            setThresh(edLo.Value, edHi.Value);
        else
            applySettings(S.store(k));
        end

        updateROIMask();
        refresh();
    end

    function applySettings(st)
        ddChannel.Value = st.channel;
        cbFill.Value    = st.fillHoles;
        cbLargest.Value = st.largestOnly;
        edMinArea.Value = st.minArea;
        computeChannel();
        setSliderRange();
        setThresh(st.lo, st.hi);
        clearROIGraphics();
        if ~isempty(st.roiPos)
            ddROITool.Value = st.roiType;
            makeROI(st.roiType, st.roiPos);
        end
    end

    function computeChannel()
        S.chanDisp = probeChannel(S.frameDisp, ddChannel.Value);
    end

    function setSliderRange()
        q = prctileLocal(S.chanDisp(:), [0.1 99.9]);
        lo = q(1); hi = q(2);
        pad = 0.05 * max(hi - lo, 1);
        lo = lo - pad; hi = hi + pad;
        if ~(hi > lo), hi = lo + 1; end

        slLo.Limits = [lo hi];   slHi.Limits = [lo hi];
        edLo.Limits = [lo hi];   edHi.Limits = [lo hi];
        lblRange.Text = sprintf('[%.1f .. %.1f]', lo, hi);
    end

    function setThresh(lo, hi)
        lims = slLo.Limits;
        lo = max(lims(1), min(lims(2), lo));
        hi = max(lims(1), min(lims(2), hi));
        if hi < lo, hi = lo; end
        edLo.Value = lo;  slLo.Value = lo;
        edHi.Value = hi;  slHi.Value = hi;
    end

%% ----------------------------------------------- NESTED: THRESHOLD / ROI

    function onChannelChanged()
        computeChannel();
        setSliderRange();
        % Stale numbers mean nothing on a new channel - seed from the data.
        setThresh(prctileLocal(S.chanDisp(:), 90), slHi.Limits(2));
        refresh();
    end

    function onThreshEdit()
        setThresh(edLo.Value, edHi.Value);
        refresh();
    end

    function onThreshSlide(which, val)
        if strcmp(which, 'lo'), edLo.Value = val; else, edHi.Value = val; end
        refresh();
    end

    function onAuto()
        v = S.chanDisp;
        if isempty(S.roiMaskDisp), v = v(:); else, v = v(S.roiMaskDisp); end
        if isempty(v), setStatus('ROI is empty.'); return, end

        lo = min(v); hi = max(v);
        if hi <= lo, setStatus('Channel is flat inside the ROI.'); return, end
        t = graythresh(rescale(v)) * (hi - lo) + lo;   % Otsu, mapped back
        setThresh(t, slHi.Limits(2));
        refresh();
        setStatus(sprintf('Otsu threshold inside the ROI: %.2f', t));
    end

    function onDrawROI()
        clearROIGraphics();
        refresh();
        setStatus(['Draw the ROI.  polygon/rectangle: click corners, ' ...
                   'double-click or Enter to close.  freehand: click-drag.']);
        roi = [];
        try
            switch ddROITool.Value
                case 'polygon',   roi = drawpolygon(ax);
                case 'freehand',  roi = drawfreehand(ax);
                case 'rectangle', roi = drawrectangle(ax);
            end
        catch
        end
        if isempty(roi) || ~isvalid(roi) || isempty(roi.Position)
            if ~isempty(roi) && isvalid(roi), delete(roi); end
            setStatus('ROI drawing cancelled.');
            return
        end
        attachROI(roi);
        updateROIMask();
        refresh();
        setStatus('ROI set. Drag its vertices to adjust.');
    end

    function makeROI(roiType, pos)
        switch roiType
            case 'polygon',   roi = images.roi.Polygon(ax,   'Position', pos);
            case 'freehand',  roi = images.roi.Freehand(ax,  'Position', pos);
            case 'rectangle', roi = images.roi.Rectangle(ax, 'Position', pos);
            otherwise, return
        end
        attachROI(roi);
    end

    function attachROI(roi)
        roi.Color     = [1 0.85 0.1];
        roi.FaceAlpha = 0.05;
        roi.LineWidth = 1.5;
        addlistener(roi, 'ROIMoved', @(~,~) onROIMoved());
        S.hROI = roi;
    end

    function onROIMoved()
        updateROIMask();
        refresh();
    end

    function onClearROI()
        clearROIGraphics();
        refresh();
        setStatus('ROI cleared - the whole frame is now in play.');
    end

    function clearROIGraphics()
        if ~isempty(S.hROI) && isvalid(S.hROI), delete(S.hROI); end
        S.hROI = [];
        S.roiMaskDisp = [];
    end

    function onCopyNearest()
        if isempty(S.store), setStatus('Nothing saved yet.'); return, end
        [~, k] = min(abs([S.store.frame] - S.frame));
        applySettings(S.store(k));
        updateROIMask();
        refresh();
        setStatus(sprintf('Copied settings from frame %d.', S.store(k).frame));
    end

    function updateROIMask()
        if isempty(S.hROI) || ~isvalid(S.hROI)
            S.roiMaskDisp = [];
            return
        end
        S.roiMaskDisp = createMask(S.hROI, ...
            size(S.frameDisp,1), size(S.frameDisp,2));
    end

%% --------------------------------------------------- NESTED: MASK + VIEW

    function m = buildMask(chan, roiMask, areaScale)
        m = chan >= edLo.Value & chan <= edHi.Value;
        if ~isempty(roiMask), m = m & roiMask; end
        if cbFill.Value, m = imfill(m, 'holes'); end
        a = round(edMinArea.Value * areaScale);
        if a >= 1, m = bwareaopen(m, a); end
        if cbLargest.Value && any(m(:))
            cc = bwconncomp(m);
            [~, b] = max(cellfun(@numel, cc.PixelIdxList));
            m = false(size(m));
            m(cc.PixelIdxList{b}) = true;
        end
    end

    function refresh()
        if isempty(S.frameDisp), return, end

        mask = buildMask(S.chanDisp, S.roiMaskDisp, S.scale^2);
        img  = S.frameDisp;

        switch ddView.Value
            case 'original'
                out = img;
            case 'ROI only'
                out = img;
                if ~isempty(S.roiMaskDisp)
                    out = shade(out, ~S.roiMaskDisp, [0 0 0], 0.6);
                end
            case 'mask overlay'
                out = img;
                if ~isempty(S.roiMaskDisp)
                    out = shade(out, ~S.roiMaskDisp, [0 0 0], 0.6);
                end
                out = shade(out, mask, [1 0.15 0.15], 0.45);
            case 'channel map'
                out = im2uint8(ind2rgb(gray2ind(rescale(S.chanDisp), 256), ...
                                       parula(256)));
            case 'masked result'
                out = img;
                out(repmat(~mask, [1 1 3])) = 0;
            otherwise
                out = img;
        end

        if isempty(S.hImg) || ~isvalid(S.hImg)
            S.hImg = image(ax, 'CData', out);
            ax.XLim = [0.5 size(out,2)+0.5];
            ax.YLim = [0.5 size(out,1)+0.5];
        else
            S.hImg.CData = out;
        end
        uistack(S.hImg, 'bottom');

        drawHist(mask);

        cc = bwconncomp(mask);
        nFull = round(nnz(mask) / max(S.scale^2, eps));
        saved = '';
        if ~isempty(findStored(S.frame)), saved = '  [saved]'; end
        setStatus(sprintf(['frame %d%s  |  %s in [%.2f, %.2f]  |  mask ' ...
            '%d px (~%d full-res), %d blob(s)  |  %d frame(s) in set'], ...
            S.frame, saved, ddChannel.Value, edLo.Value, edHi.Value, ...
            nnz(mask), nFull, cc.NumObjects, numel(S.store)));
    end

    function drawHist(mask)
        cla(axHist);
        v = S.chanDisp;
        if isempty(S.roiMaskDisp), v = v(:); else, v = v(S.roiMaskDisp); end
        if isempty(v), return, end
        if numel(v) > 2e5, v = v(randperm(numel(v), 2e5)); end

        hold(axHist, 'on');
        histogram(axHist, v, 80, 'Normalization', 'probability', ...
            'FaceColor', [0.45 0.5 0.55], 'EdgeColor', 'none');
        yl = ylim(axHist);
        plot(axHist, [edLo.Value edLo.Value], yl, 'r-',  'LineWidth', 1.5);
        plot(axHist, [edHi.Value edHi.Value], yl, 'r--', 'LineWidth', 1.2);
        hold(axHist, 'off');
        xlim(axHist, slLo.Limits);
        axHist.YTick = [];
        xlabel(axHist, sprintf('%s inside ROI   (%d px kept)', ...
            ddChannel.Value, nnz(mask)), 'FontSize', 9, 'Interpreter', 'none');
    end

%% -------------------------------------------------------- NESTED: EXPORT

    function [maskFull, roiMaskFull] = fullResMasks()
        % Rasterise the ROI at full resolution from its vertices rather than
        % upsampling the display mask, so the boundary stays exact.
        if isempty(S.hROI) || ~isvalid(S.hROI)
            roiMaskFull = [];
        else
            p = S.hROI.Position;
            if isa(S.hROI, 'images.roi.Rectangle'), p = rect2poly(p); end
            xf = (p(:,1) - 0.5) / S.scale + 0.5;
            yf = (p(:,2) - 0.5) / S.scale + 0.5;
            roiMaskFull = poly2mask(xf, yf, S.Hfull, S.Wfull);
        end
        chanFull = probeChannel(S.frameFull, ddChannel.Value);
        maskFull = buildMask(chanFull, roiMaskFull, 1);
    end

    function ok = ensureOutDir()
        ok = true;
        if ~isempty(S.outDir) && isfolder(S.outDir), return, end
        d = uigetdir(fileparts(S.videoFile), 'Choose an export folder');
        if isequal(d, 0), ok = false; return, end
        S.outDir = d;
    end

    function exportCurrent(what)
        if ~ensureOutDir(), return, end
        stashCurrent(true);
        setStatus('Exporting at full resolution ...'); drawnow;
        n = writeFrame(what);
        setStatus(sprintf('Wrote %d file(s) for frame %d to %s', ...
            n, S.frame, S.outDir));
    end

    function nWritten = writeFrame(what)
        [maskFull, roiMaskFull] = fullResMasks();
        stem = fullfile(S.outDir, sprintf('%s_f%05d', S.base, S.frame));
        nWritten = 0;

        if strcmp(what, 'roi')
            rgb = S.frameFull;
            if ~isempty(roiMaskFull)
                rgb(repmat(~roiMaskFull, [1 1 3])) = 0;
                imwrite(roiMaskFull, [stem '_roimask.png']);
                nWritten = nWritten + 1;
            end
            imwrite(rgb, [stem '_roi.png']);
            nWritten = nWritten + 1;
        else
            rgb = S.frameFull;
            rgb(repmat(~maskFull, [1 1 3])) = 0;
            imwrite(rgb,      [stem '_seg.png']);   % RGB, both applied
            imwrite(maskFull, [stem '_mask.png']);  % silhouette for the hull
            nWritten = nWritten + 2;
        end

        params = struct( ...
            'videoFile',     S.videoFile, ...
            'frame',         S.frame, ...
            'time',          (S.frame-1)/S.fps, ...
            'fps',           S.fps, ...
            'imageSize',     [S.Hfull S.Wfull], ...
            'channel',       ddChannel.Value, ...
            'lo',            edLo.Value, ...
            'hi',            edHi.Value, ...
            'fillHoles',     cbFill.Value, ...
            'minArea',       edMinArea.Value, ...
            'largestOnly',   cbLargest.Value, ...
            'roiType',       currentROIType(), ...
            'roiPosDisplay', currentROIPos(), ...
            'displayScale',  S.scale, ...
            'usage', sprintf(['v = probeChannel(img, ''%s''); ' ...
                              'mask = v >= %.4f & v <= %.4f;'], ...
                              ddChannel.Value, edLo.Value, edHi.Value), ...
            'createdOn',     datetime('now'));
        save([stem '_params.mat'], 'params');
        nWritten = nWritten + 1;
    end

    function exportAll()
        if ~ensureOutDir(), return, end
        stashCurrent(true);
        if isempty(S.store), setStatus('No saved frames to export.'); return, end

        frames = [S.store.frame];
        startFrame = S.frame;
        d = uiprogressdlg(fig, 'Title', 'Exporting', 'Indeterminate', 'off');
        total = 0;
        try
            for i = 1:numel(frames)
                d.Value   = (i-1) / numel(frames);
                d.Message = sprintf('Frame %d  (%d of %d)', ...
                    frames(i), i, numel(frames));
                gotoFrame(frames(i));
                total = total + writeFrame('roi');
                total = total + writeFrame('seg');
            end
        catch ME
            delete(d);
            setStatus(['Export failed: ' ME.message]);
            return
        end
        delete(d);
        gotoFrame(startFrame);
        setStatus(sprintf('Exported %d files for %d frame(s) to %s', ...
            total, numel(frames), S.outDir));
    end

%% ------------------------------------------------------- NESTED: SESSION

    function onSaveFrame()
        stashCurrent(true);
        writeSession();
        setStatus(sprintf('Frame %d saved (%d in set). Session written to %s', ...
            S.frame, numel(S.store), sessionFile()));
    end

    function stashCurrent(addIfNew)
        %STASHCURRENT Write the on-screen settings into the store.
        %   addIfNew = false updates an existing entry only, so simply
        %   scrubbing through frames never grows the set.
        if isempty(S.frameFull) || S.frame < 1, return, end
        k = findStored(S.frame);
        if isempty(k) && ~addIfNew, return, end

        entry = struct('frame', S.frame, 'channel', ddChannel.Value, ...
            'lo', edLo.Value, 'hi', edHi.Value, ...
            'roiType', currentROIType(), 'roiPos', currentROIPos(), ...
            'fillHoles', cbFill.Value, 'minArea', edMinArea.Value, ...
            'largestOnly', cbLargest.Value);

        if isempty(k)
            S.store(end+1) = entry;
            [~, ord] = sort([S.store.frame]);
            S.store = S.store(ord);
        else
            S.store(k) = entry;
        end
    end

    function k = findStored(n)
        k = [];
        if isempty(S.store), return, end
        k = find([S.store.frame] == n, 1);
    end

    function t = currentROIType()
        t = '';
        if ~isempty(S.hROI) && isvalid(S.hROI), t = ddROITool.Value; end
    end

    function p = currentROIPos()
        p = [];
        if ~isempty(S.hROI) && isvalid(S.hROI), p = S.hROI.Position; end
    end

    function f = sessionFile()
        f = fullfile(fileparts(S.videoFile), [S.base '_roiSession.mat']);
    end

    function writeSession()
        session = struct('videoFile', S.videoFile, 'store', S.store, ...
            'displayScale', S.scale, 'imageSize', [S.Hfull S.Wfull], ...
            'fps', S.fps, 'createdOn', datetime('now'));
        try
            save(sessionFile(), 'session');
        catch ME
            setStatus(['Could not write session: ' ME.message]);
        end
    end

    function tryLoadSession()
        f = sessionFile();
        if ~isfile(f), return, end
        try
            L = load(f);
            if isfield(L, 'session') && ~isempty(L.session.store)
                S.store = L.session.store;
                fprintf('crabROITool: loaded %d saved frame(s) from %s\n', ...
                    numel(S.store), f);
            end
        catch
        end
    end

    function onClose()
        if ~isempty(S.store), writeSession(); end
        delete(fig);
    end

%% ---------------------------------------------------------- NESTED: MISC

    function setStatus(msg)
        lblStatus.Text = msg;
        drawnow limitrate
    end

end % crabROITool

%% ----------------------------------------------------------- LOCAL HELPERS

function h = lbl(parent, row, col, text)
h = uilabel(parent, 'Text', text, 'FontWeight', 'bold', 'FontSize', 11);
h.Layout.Row = row; h.Layout.Column = col;
end

function out = shade(img, mask, rgb, alpha)
%SHADE Blend a flat colour into img wherever mask is true.
out = img;
if ~any(mask(:)), return, end
for c = 1:3
    ch = out(:,:,c);
    ch(mask) = uint8((1-alpha)*double(ch(mask)) + alpha*255*rgb(c));
    out(:,:,c) = ch;
end
end

function p = rect2poly(r)
%RECT2POLY [x y w h] -> 4 corner vertices.
p = [r(1) r(2); r(1)+r(3) r(2); r(1)+r(3) r(2)+r(4); r(1) r(2)+r(4)];
end

function q = prctileLocal(x, p)
%PRCTILELOCAL Linear-interpolated percentile(s). No Statistics Toolbox.
x = sort(x(:));
n = numel(x);
q = nan(size(p));
if n == 0, return, end
if n == 1, q(:) = x; return, end
for i = 1:numel(p)
    idx = (p(i)/100)*(n-1) + 1;
    idx = max(1, min(n, idx));
    lo = floor(idx); hi = ceil(idx);
    q(i) = x(lo) + (idx-lo)*(x(hi)-x(lo));
end
end
