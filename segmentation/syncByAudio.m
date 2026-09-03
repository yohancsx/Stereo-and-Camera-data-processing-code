%% sync_by_audio.m
% Determine the frame offset between several video files by correlating the
% onset structure of their audio tracks. Intended for the click sounds made
% before a calibration or trial recording.
%
% THE HEADLINE OUTPUT
%   A START FRAME for each video. Set every file to its start frame and they
%   are all showing the same instant; step them together from there.
%   It is chosen as the earliest moment covered by ALL the files, so the
%   camera that started recording LAST gets frame 1 and the others skip in.
%
% METHOD
%   Each track is reduced to an "onset function" rather than correlated as a
%   raw waveform. The same click reaches each camera at a different distance,
%   through a different housing, with different reverberation - so the
%   waveforms differ, but the TIMING of the energy onset does not.
%
%     audio -> mono -> band-pass -> RMS envelope -> common 1 kHz grid
%           -> robust z-score -> half-wave-rectified first difference
%
%   The z-score removes level differences between cameras; the difference
%   emphasises sharp attacks. Cross-correlation of that against a reference
%   camera gives the offset, refined by parabolic interpolation.
%
% CHECKING IT BY HAND
%   Every click time is printed in each camera's OWN timeline, as seconds,
%   frame number and hh:mm:ss.mmm timecode. Open a file in any player,
%   scrub to the printed time, and you should hear the click. Figure 1 plots
%   the same thing as waveforms, so the printed table and the picture agree.
%
% SIGN CONVENTION
%   lag > 0  means the click appears LATER in that camera's own timeline,
%            i.e. that camera started recording EARLIER than the reference.
%   frame_i = frame_ref + frameOffset(i).
%   Verified empirically below by matching individually detected clicks, and
%   by re-testing with the sign flipped - not taken on trust from a comment.
%
% BEFORE YOU RELY ON THE RESULT, CHECK
%   * ambiguity ratio - if you clicked at a REGULAR rate, the correlation
%     has near-equal peaks one click-period apart and the answer is
%     ambiguous by a whole interval. Click irregularly.
%   * click residual RMS - should be a small fraction of a frame.
%   * drift - GoPros have independent clocks. 50 ppm over 10 min is ~30 ms,
%     about 2 frames at 60 fps. Set cfg.driftWindow to measure it.
%
% Requires: Signal Processing Toolbox (bandpass, xcorr), Image Processing
% Toolbox only for the optional visual check.
%
% Yohan Sequeira - Crab Visual Hull Analysis

%% ------------------------------------------------------------------ CONFIG

clear; close all; clc;

% Video files. Leave empty to be prompted (multi-select).
cfg.files = {};

cfg.refCam = 1;            % all offsets are reported relative to this file

% Analysis window in seconds, relative to each file's own start. Keep it
% tight around the clicks: it bounds both runtime and memory.
% [] = whole file (can be slow and memory-hungry on long recordings).
cfg.window = [0 60];

% Optional SECOND window for clock-drift estimation, e.g. [540 600] for the
% last minute of a 10 minute file. [] = skip.
cfg.driftWindow = [];

% Align at a specific reference-camera frame instead of the first commonly
% covered instant. [] = use the first common instant (usually what you want).
cfg.alignAtRefFrame = [];

% --- Signal processing ----------------------------------------------------
cfg.bandHz      = [200 8000];  % click band. Underwater housings roll off the
                               % top end; widen/narrow after looking at fig 1.
cfg.envWinSec   = 0.005;       % RMS envelope window
cfg.envFs       = 1000;        % common envelope rate (Hz) -> 1 ms resolution
cfg.waveFs      = 2000;        % waveform display rate (Hz), figures only
cfg.maxLagSec   = 10;          % search range for the offset

% --- Click detection (verification and the printed tables) ---------------
cfg.minProminence  = 4;        % in robust-z units of the onset function
cfg.minClickSepSec = 0.15;
cfg.maxClicks      = 30;
cfg.matchTolSec    = 0.10;     % how far a click may sit from its prediction

% --- Optional visual confirmation ----------------------------------------
cfg.visualCheck        = false;  % montage of all cameras at the start frames
cfg.visualCheckPlusFrames = 0;   % nudge forward if the start frame is dull

thisDir = fileparts(mfilename('fullpath'));
if isempty(thisDir), thisDir = pwd; end     % running section-by-section
cfg.outFile = fullfile(thisDir, 'params', 'sync.mat');

%% -------------------------------------------------------------- HOUSEKEEPING

if isempty(cfg.files)
    [f, p] = uigetfile({'*.mp4;*.MP4;*.mov;*.MOV;*.avi', 'Video files'}, ...
        'Select the synced video files', 'MultiSelect', 'on');
    if isequal(f, 0), return, end
    if ischar(f), f = {f}; end
    cfg.files = cellfun(@(x) fullfile(p, x), f, 'UniformOutput', false);
end
cfg.files = cfg.files(:);
nCam = numel(cfg.files);
assert(nCam >= 2, 'Need at least two files to synchronise.');
assert(cfg.refCam >= 1 && cfg.refCam <= nCam, 'cfg.refCam out of range.');

if ~exist(fileparts(cfg.outFile), 'dir'), mkdir(fileparts(cfg.outFile)); end

%% ---------------------------------------------------------------- FILE INFO

fprintf('================ FILES ================\n');
info = struct('file',{},'name',{},'fps',{},'videoDur',{},'nFrames',{}, ...
              'audioFs',{},'audioDur',{},'audioSamples',{},'nChan',{});
for i = 1:nCam
    f = cfg.files{i};
    assert(isfile(f), 'File not found: %s', f);

    v = VideoReader(f);
    try
        ai = audioinfo(f);
    catch ME
        error(['Could not read audio from\n  %s\n%s\n\n' ...
               'MATLAB reads MP4 audio through the OS codecs. If this ' ...
               'fails, extract the audio first, e.g.\n' ...
               '    ffmpeg -i "%s" -vn -ac 1 -ar 48000 out.wav\n' ...
               'and point cfg.files at the .wav files instead (the frame ' ...
               'rate must then be set by hand).'], f, ME.message, f);
    end

    [~, nm, ex] = fileparts(f);
    info(i) = struct('file', f, 'name', [nm ex], 'fps', v.FrameRate, ...
        'videoDur', v.Duration, 'nFrames', floor(v.Duration * v.FrameRate), ...
        'audioFs', ai.SampleRate, 'audioDur', ai.Duration, ...
        'audioSamples', ai.TotalSamples, 'nChan', ai.NumChannels);

    fprintf('  [%d] %-28s  %6.2f fps  %7.2f s  ~%6d frames  audio %d Hz\n', ...
        i, info(i).name, info(i).fps, info(i).videoDur, info(i).nFrames, ...
        info(i).audioFs);
end

if numel(unique(round([info.fps], 3))) > 1
    warning(['Frame rates differ between files. The start frames below are ' ...
             'still correct, but you cannot step the files together with a ' ...
             'single frame increment.']);
end

%% ------------------------------------------------------- ESTIMATE THE LAGS

fprintf('\n================ MAIN WINDOW ================\n');
S = estimateLags(info, cfg.window, cfg);
lagSec = S.lagSec;
fpsRef = info(cfg.refCam).fps;

%% ------------------------------------------- CLICK DETECTION (PER CAMERA)

% Times are absolute in each camera's OWN timeline, so they match what a
% media player shows when you open that file.
clicks = cell(nCam, 1);
for i = 1:nCam
    clicks{i} = S.windowStart + detectClicks(S.onset{i}, S.tEnv, cfg);
end
clicksRef = clicks{cfg.refCam};

if numel(clicksRef) < 2
    warning(['Fewer than 2 clicks found in the reference track. Lower ' ...
             'cfg.minProminence or check cfg.window covers the clicks.']);
end

% Independent verification: does the estimated lag actually line the click
% trains up? And does the NEGATED lag fit better (i.e. a sign error)?
resid     = nan(nCam, 1);
residFlip = nan(nCam, 1);
nMatched  = zeros(nCam, 1);
for i = 1:nCam
    if i == cfg.refCam, resid(i) = 0; residFlip(i) = 0; continue, end
    if isempty(clicks{i}) || isempty(clicksRef), continue, end
    [resid(i), nMatched(i)] = clickResidual(clicksRef, clicks{i},  lagSec(i));
    residFlip(i)            = clickResidual(clicksRef, clicks{i}, -lagSec(i));
end

%% ------------------------------------------------------------ FRAME OFFSETS

frameOffset    = lagSec .* [info.fps]';
frameOffsetInt = round(frameOffset);
subFrame       = frameOffset - frameOffsetInt;

% ---- the aligned start frames -------------------------------------------
% Camera i covers own-time [0, videoDur_i), which in reference time is
% [-lag_i, videoDur_i - lag_i). The commonly covered span is the
% intersection over all cameras.
tCommonStart = max(-lagSec);
tCommonEnd   = min([info.videoDur]' - lagSec);

if isempty(cfg.alignAtRefFrame)
    tAlign = tCommonStart;
else
    tAlign = (cfg.alignAtRefFrame - 1) / fpsRef;
end

startFrame = zeros(nCam, 1);
startTime  = zeros(nCam, 1);
for i = 1:nCam
    startFrame(i) = max(1, round(1 + info(i).fps * (tAlign + lagSec(i))));
    startTime(i)  = (startFrame(i) - 1) / info(i).fps;
end
overlapSec    = max(0, tCommonEnd - tAlign);
overlapFrames = floor(overlapSec * fpsRef);

%% ------------------------------------------------ REPORT: THE START FRAMES

fprintf('\n');
fprintf('==================== ALIGNED START FRAMES ====================\n');
fprintf('Set each video to the frame below. They are then all showing the\n');
fprintf('same instant, and you can step them together from there.\n\n');
fprintf('%-4s %-26s %12s %12s %16s\n', ...
    'cam', 'file', 'START FRAME', 'time (s)', 'timecode');
for i = 1:nCam
    fprintf('%-4d %-26s %12d %12.5f %16s\n', i, ...
        truncName(info(i).name, 26), startFrame(i), startTime(i), ...
        timecodeStr(startTime(i)));
end
fprintf('\nUsable overlap from there: %d frames (%.2f s) at %.3f fps\n', ...
    overlapFrames, overlapSec, fpsRef);
if isempty(cfg.alignAtRefFrame)
    [~, iLast] = min(lagSec);
    fprintf('Camera %d started recording last, so it anchors at frame 1.\n', iLast);
end
fprintf('\nTo advance together:   frame_i(n) = startFrame(i) + n\n');
fprintf('For any reference frame f:\n');
fprintf('   frame_i = round(1 + fps_i * ((f-1)/fps_ref + lagSeconds(i)))\n');

%% ------------------------------------------------- REPORT: LAGS AND CHECKS

fprintf('\n================ LAGS (ref = [%d] %s) ================\n', ...
    cfg.refCam, info(cfg.refCam).name);
fprintf('%-3s %-24s %10s %10s %8s %9s   %6s %7s %9s\n', ...
    'cam','file','lag (s)','frames','rounded','sub-frame','corr','ambig','clickRMS');
for i = 1:nCam
    residStr = '     -   ';
    if ~isnan(resid(i))
        residStr = sprintf('%6.2f fr', resid(i) * info(i).fps);
    end
    fprintf('%-3d %-24s %10.5f %10.3f %8d %9.3f   %6.3f %7.3f %9s\n', ...
        i, truncName(info(i).name, 24), lagSec(i), frameOffset(i), ...
        frameOffsetInt(i), subFrame(i), S.corrPeak(i), S.ambigRatio(i), ...
        residStr);
end
fprintf('\nlag > 0 means that camera started recording EARLIER, so the same\n');
fprintf('instant sits at a LATER frame number in its own file.\n');

fprintf('\n---- checks ----\n');
ok = true;
for i = 1:nCam
    if i == cfg.refCam, continue, end

    if S.ambigRatio(i) > 0.8
        fprintf(['  [!] cam %d: ambiguity ratio %.2f - a competing ' ...
            'correlation peak is nearly as strong.\n      The clicks may ' ...
            'be too regularly spaced. Check figure 3 before trusting this.\n'], ...
            i, S.ambigRatio(i));
        ok = false;
    end
    if S.corrPeak(i) < 0.3
        fprintf(['  [!] cam %d: weak correlation peak (%.3f). Try widening ' ...
            'cfg.bandHz or cfg.window.\n'], i, S.corrPeak(i));
        ok = false;
    end
    if ~isnan(resid(i))
        rFrames = resid(i) * info(i).fps;
        if rFrames > 0.5
            fprintf(['  [!] cam %d: click residual %.2f frames - the click ' ...
                'trains do not line up well.\n'], i, rFrames);
            ok = false;
        end
        if residFlip(i) < resid(i) * 0.5
            fprintf(['  [!!] cam %d: the NEGATED lag fits the clicks better ' ...
                '(%.2f vs %.2f frames).\n       Treat the sign convention ' ...
                'as unverified and inspect figure 2.\n'], i, ...
                residFlip(i)*info(i).fps, rFrames);
            ok = false;
        end
    end
    if abs(subFrame(i)) > 0.35
        fprintf(['  [ ] cam %d: offset is %.2f frames from an integer. ' ...
            'Rounding costs you\n      %.1f ms here - unavoidable without ' ...
            'sub-frame interpolation.\n'], i, subFrame(i), ...
            abs(subFrame(i))/info(i).fps*1000);
    end
end
if ok, fprintf('  all cameras passed\n'); end

%% ------------------------------------------------- REPORT: CLICKS PER FILE

fprintf('\n========= DETECTED CLICKS (each camera''s OWN timeline) =========\n');
fprintf('Open the file in any player, scrub to these times, hear the click.\n');
for i = 1:nCam
    fprintf('\n--- [%d] %s   (%.3f fps) ---\n', i, info(i).name, info(i).fps);
    if isempty(clicks{i})
        fprintf('    none detected\n');
        continue
    end
    fprintf('   %3s %12s %10s %16s\n', '#', 'time (s)', 'frame', 'timecode');
    for c = 1:numel(clicks{i})
        t = clicks{i}(c);
        fprintf('   %3d %12.4f %10d %16s\n', c, t, ...
            1 + round(info(i).fps * t), timecodeStr(t));
    end
end

%% -------------------------------------- REPORT: THE SAME CLICK EVERYWHERE

fprintf('\n========= SAME CLICK, EVERY CAMERA =========\n');
fprintf('Each row is one instant. The numbers are the frame in each file\n');
fprintf('that contains it - the direct check on the start frames above.\n\n');

hdr = sprintf('%4s %11s %14s', '#', 'ref t (s)', 'ref timecode');
for i = 1:nCam, hdr = [hdr sprintf(' %9s', sprintf('[%d] frm', i))]; end %#ok<AGROW>
hdr = [hdr sprintf(' %11s', 'max res(ms)')];
fprintf('%s\n', hdr);

matchTable = nan(numel(clicksRef), nCam);
for c = 1:numel(clicksRef)
    tRef = clicksRef(c);
    row  = sprintf('%4d %11.4f %14s', c, tRef, timecodeStr(tRef));
    worst = 0;
    for i = 1:nCam
        tPred = tRef + lagSec(i);
        tGot  = matchOne(clicks{i}, tPred, cfg.matchTolSec);
        if isnan(tGot)
            row = [row sprintf(' %9s', '  -')];                 %#ok<AGROW>
        else
            matchTable(c, i) = tGot;
            row = [row sprintf(' %9d', 1 + round(info(i).fps*tGot))]; %#ok<AGROW>
            worst = max(worst, abs(tGot - tPred));
        end
    end
    fprintf('%s %11.1f\n', row, worst*1000);
end
fprintf('\nA dash means no click was detected there in that file within %.0f ms.\n', ...
    cfg.matchTolSec*1000);

%% ------------------------------------------------------------------- DRIFT

drift = [];
if ~isempty(cfg.driftWindow)
    fprintf('\n================ DRIFT WINDOW ================\n');
    S2 = estimateLags(info, cfg.driftWindow, cfg);

    dt = mean(cfg.driftWindow) - mean(cfg.window);
    drift = struct('window1', cfg.window, 'window2', cfg.driftWindow, ...
        'lag1', lagSec, 'lag2', S2.lagSec, ...
        'deltaSec', S2.lagSec - lagSec, ...
        'deltaFrames', (S2.lagSec - lagSec) .* [info.fps]', ...
        'ppm', (S2.lagSec - lagSec) / dt * 1e6, ...
        'separationSec', dt);

    fprintf('\n%-3s %-24s %12s %10s %10s\n', ...
        'cam','file','drift (ms)','frames','ppm');
    for i = 1:nCam
        fprintf('%-3d %-24s %12.2f %10.3f %10.1f\n', i, ...
            truncName(info(i).name,24), drift.deltaSec(i)*1000, ...
            drift.deltaFrames(i), drift.ppm(i));
    end
    if any(abs(drift.deltaFrames) > 0.5)
        fprintf(['\n  [!] More than half a frame of drift across the ' ...
            'recording. The start frames\n      will not stay aligned to ' ...
            'the end of the file - sync against a click\n      close in ' ...
            'time to the segment you actually care about.\n']);
    end
end

%% -------------------------------------------------------------------- PLOTS

% Fig 1: waveforms on each camera's OWN timeline - the figure to hold next
% to a media player. Click numbers match the printed tables.
figure('Name','sync 1 - waveforms, own timeline','NumberTitle','off', ...
       'Color','w','Position',[40 40 1250 160+130*nCam]);
tl1 = tiledlayout(nCam, 1, 'Padding','compact', 'TileSpacing','compact');
title(tl1, ['Waveforms in each file''s OWN timeline  -  scrub a player to ' ...
    'these times to verify'], 'FontWeight','bold');
ax1 = gobjects(nCam,1);
for i = 1:nCam
    ax1(i) = nexttile;
    plotWave(ax1(i), S.windowStart + S.tWave, S.wave{i}, clicks{i}, ...
             S.windowStart + S.tWave([1 end]), info(i), i, lagSec(i), true);
end
xlabel(tl1, 'time in that file (s)');
linkaxes(ax1, 'x');

% Fig 2: the same waveforms shifted into the reference timeline. If the sync
% is right the clicks line up vertically.
figure('Name','sync 2 - waveforms, aligned','NumberTitle','off', ...
       'Color','w','Position',[70 60 1250 160+130*nCam]);
tl2 = tiledlayout(nCam, 1, 'Padding','compact', 'TileSpacing','compact');
title(tl2, sprintf(['Aligned to camera %d''s timeline  -  clicks should ' ...
    'line up vertically'], cfg.refCam), 'FontWeight','bold');
ax2 = gobjects(nCam,1);
tRefSpan = S.windowStart + S.tWave([1 end]);
for i = 1:nCam
    ax2(i) = nexttile;
    plotWave(ax2(i), S.windowStart + S.tWave - lagSec(i), S.wave{i}, ...
             clicks{i} - lagSec(i), tRefSpan, info(i), i, lagSec(i), false);
    for c = 1:numel(clicksRef)
        xline(ax2(i), clicksRef(c), 'k:', 'LineWidth', 0.8);
    end
end
xlabel(tl2, sprintf('time in camera %d''s timeline (s)', cfg.refCam));
linkaxes(ax2, 'x');

% Fig 3: what the algorithm actually used, plus the correlation curves.
figure('Name','sync 3 - onset functions and correlation','NumberTitle','off', ...
       'Color','w','Position',[100 80 1150 700]);
tiledlayout(2, 1, 'Padding','compact', 'TileSpacing','compact');

nexttile; hold on; grid on
step = 1;
for i = 1:nCam
    o = S.onset{i} / max(max(S.onset{i}), eps);
    plot(S.windowStart + S.tEnv - lagSec(i), o + (nCam-i)*step, 'LineWidth', 1);
    text(tRefSpan(1), (nCam-i)*step + 0.75, ...
        sprintf('[%d] %s   lag %+.4f s', i, truncName(info(i).name,20), lagSec(i)), ...
        'Interpreter','none','FontSize',9,'VerticalAlignment','bottom');
end
xlim(tRefSpan); ylim([-0.1 nCam*step]); set(gca,'YTick',[]);
xlabel(sprintf('time in camera %d''s timeline (s)', cfg.refCam));
title('onset functions (what the correlation sees), aligned');

nexttile; hold on; grid on
leg = {};
for i = 1:nCam
    if i == cfg.refCam, continue, end
    plot(S.corrLags, S.corr(:,i), 'LineWidth', 1.3);
    leg{end+1} = sprintf('cam %d', i);              %#ok<SAGROW>
end
yl = ylim;
for i = 1:nCam
    if i == cfg.refCam, continue, end
    plot([lagSec(i) lagSec(i)], yl, 'k:', 'HandleVisibility','off');
end
xlabel('lag (s)   [positive = this camera started earlier]');
ylabel('normalised cross-correlation');
title('correlation against the reference - look for a single clear peak');
if ~isempty(leg), legend(leg, 'Location','best'); end

%% --------------------------------------------------------------------- SAVE

if strcmpi(questdlg('Save the sync result?', 'Save', 'Yes','No','Yes'), 'Yes')
    sync = struct( ...
        'files',            {{info.file}'}, ...
        'names',            {{info.name}'}, ...
        'refCam',           cfg.refCam, ...
        'fps',              [info.fps]', ...
        'nFrames',          [info.nFrames]', ...
        'startFrame',       startFrame, ...
        'startTime',        startTime, ...
        'alignRefTime',     tAlign, ...
        'overlapFrames',    overlapFrames, ...
        'overlapSeconds',   overlapSec, ...
        'lagSeconds',       lagSec, ...
        'frameOffset',      frameOffset, ...
        'frameOffsetInt',   frameOffsetInt, ...
        'subFrameResidual', subFrame, ...
        'corrPeak',         S.corrPeak, ...
        'ambiguityRatio',   S.ambigRatio, ...
        'clickTimes',       {clicks}, ...
        'clickMatchTable',  matchTable, ...
        'clickResidualSec', resid, ...
        'clicksMatched',    nMatched, ...
        'drift',            drift, ...
        'config',           cfg, ...
        'convention',       ['set file i to startFrame(i); then ' ...
                             'frame_i = frame_ref + frameOffset(i)'], ...
        'createdOn',        datetime('now'), ...
        'matlabVer',        version);

    save(cfg.outFile, 'sync');
    fprintf('\nSaved -> %s\n', cfg.outFile);
    fprintf('\n    cfg.startFrame  = [%s];\n', ...
        strjoin(compose('%d', startFrame(:)'), ' '));
    fprintf('    cfg.frameOffset = [%s];\n', ...
        strjoin(compose('%d', frameOffsetInt(:)'), ' '));
end

%% ------------------------------------------------------------ VISUAL CHECK

if cfg.visualCheck
    figure('Name','sync 4 - visual check at the start frames', ...
           'NumberTitle','off','Color','w', ...
           'Units','normalized','Position',[0.05 0.08 0.9 0.82]);
    tl = tiledlayout('flow','Padding','compact','TileSpacing','compact');
    title(tl, sprintf('same instant  (start frames + %d)', ...
        cfg.visualCheckPlusFrames), 'FontWeight','bold');

    for i = 1:nCam
        fi = startFrame(i) + cfg.visualCheckPlusFrames;
        v  = VideoReader(info(i).file);
        t  = (fi - 1) / info(i).fps;

        nexttile;
        if t < 0 || t >= v.Duration
            axis off
            title(sprintf('[%d] frame %d is outside this file', i, fi));
            continue
        end
        v.CurrentTime = t;
        imshow(imresize(readFrame(v), 0.25));
        title(sprintf('[%d] %s   frame %d', i, truncName(info(i).name,18), fi), ...
              'Interpreter','none');
    end
end

fprintf('\nDone.\n');

%% ----------------------------------------------------------- LOCAL FUNCTIONS

function S = estimateLags(info, win, cfg)
%ESTIMATELAGS Onset functions + cross-correlation lags over one time window.
    nCam = numel(info);

    % Common time grids, relative to each file's own start.
    if isempty(win)
        dur = min([info.audioDur]);
        t0  = 0;
    else
        t0  = win(1);
        dur = win(2) - win(1);
        dur = min(dur, min([info.audioDur]) - t0);
    end
    assert(dur > 1, 'Analysis window is shorter than 1 s - check cfg.window.');
    tEnv  = (0 : 1/cfg.envFs  : dur)';
    tWave = (0 : 1/cfg.waveFs : dur)';

    fprintf('window = [%.1f %.1f] s   (%.1f s, %d envelope samples)\n', ...
        t0, t0+dur, dur, numel(tEnv));

    onset = cell(nCam, 1);
    wave  = cell(nCam, 1);
    for i = 1:nCam
        [onset{i}, wave{i}] = onsetFunction(info(i), t0, dur, tEnv, tWave, cfg);
    end

    % Cross-correlate every camera against the reference.
    maxLagSamp = round(cfg.maxLagSec * cfg.envFs);
    maxLagSamp = min(maxLagSamp, numel(tEnv) - 2);

    lagsIdx  = (-maxLagSamp : maxLagSamp)';
    corrAll  = zeros(numel(lagsIdx), nCam);
    lagSec   = zeros(nCam, 1);
    corrPeak = zeros(nCam, 1);
    ambig    = zeros(nCam, 1);

    for i = 1:nCam
        r = xcorr(onset{i}, onset{cfg.refCam}, maxLagSamp, 'normalized');
        corrAll(:, i) = r;

        if i == cfg.refCam
            corrPeak(i) = 1; lagSec(i) = 0; ambig(i) = 0;
            continue
        end

        [pk, k] = max(r);

        % Parabolic interpolation for sub-sample precision.
        d = 0;
        if k > 1 && k < numel(r)
            den = r(k-1) - 2*r(k) + r(k+1);
            if abs(den) > eps
                d = 0.5 * (r(k-1) - r(k+1)) / den;
                d = max(-1, min(1, d));
            end
        end

        lagSec(i)   = (lagsIdx(k) + d) / cfg.envFs;
        corrPeak(i) = pk;

        % Ambiguity: strongest competing peak outside the main lobe.
        guard = round(0.05 * cfg.envFs);        % 50 ms either side
        mask  = true(size(r));
        mask(max(1,k-guard) : min(numel(r),k+guard)) = false;
        if any(mask) && pk > 0
            ambig(i) = max(r(mask)) / pk;
        end
    end

    S = struct('tEnv', tEnv, 'onset', {onset}, 'tWave', tWave, ...
        'wave', {wave}, 'lagSec', lagSec, 'corrPeak', corrPeak, ...
        'ambigRatio', ambig, 'corr', corrAll, ...
        'corrLags', lagsIdx(:) / cfg.envFs, 'windowStart', t0, ...
        'windowDur', dur);
end


function [o, wav] = onsetFunction(inf1, t0, dur, tEnv, tWave, cfg)
%ONSETFUNCTION Audio -> band-passed RMS envelope -> robust-z -> attack.
%   Also returns a peak-decimated waveform for display, normalised to its
%   own maximum so cameras at different gains are comparable by eye.
    Fs = inf1.audioFs;

    s1 = max(1, round(t0 * Fs) + 1);
    s2 = min(round((t0 + dur) * Fs), inf1.audioSamples);
    assert(s2 > s1, 'Empty audio window for %s.', inf1.name);
    x  = audioread(inf1.file, [s1 s2]);
    x  = mean(double(x), 2);                       % mono

    % Band-pass to the click band. Guard the upper edge against Nyquist.
    b = cfg.bandHz;
    b(2) = min(b(2), 0.45 * Fs);
    if b(1) < b(2)
        x = bandpass(x, b, Fs, 'Steepness', 0.7);
    end

    tx = (0 : numel(x)-1)' / Fs;

    % Peak-hold decimation for the waveform display, the way an audio
    % editor draws it - transients survive the downsample.
    blk = max(1, round(Fs / cfg.waveFs));
    wav = interp1(tx, movmax(abs(x), blk), tWave, 'linear', 'extrap');
    wav = wav / max(max(wav), eps);

    % Short-time RMS energy. movmean also anti-aliases ahead of the
    % downsample to cfg.envFs, so no separate filter is needed.
    w   = max(3, round(cfg.envWinSec * Fs));
    env = sqrt(movmean(x.^2, w));
    e   = interp1(tx, env, tEnv, 'linear', 'extrap');

    % Robust z-score: level-independent across cameras.
    med = median(e);
    sd  = 1.4826 * median(abs(e - med));
    z   = (e - med) / (sd + eps);

    % Half-wave-rectified first difference emphasises attacks.
    o = [0; max(0, diff(z))];
end


function t = detectClicks(onset, tEnv, cfg)
%DETECTCLICKS Individual click times, relative to the window start.
    idx = islocalmax(onset, ...
        'MinProminence', cfg.minProminence, ...
        'MinSeparation', max(1, round(cfg.minClickSepSec * cfg.envFs)));
    t = tEnv(idx);
    if numel(t) > cfg.maxClicks
        [~, ord] = sort(onset(idx), 'descend');
        t = sort(t(ord(1:cfg.maxClicks)));
    end
end


function tGot = matchOne(tList, tPred, tol)
%MATCHONE Nearest detected click to a predicted time, NaN if none in range.
    tGot = NaN;
    if isempty(tList), return, end
    [d, k] = min(abs(tList - tPred));
    if d <= tol, tGot = tList(k); end
end


function [rms_, n] = clickResidual(tRef, tCam, lagSec)
%CLICKRESIDUAL RMS distance from each reference click to the nearest camera
%   click, after removing the estimated lag. Unmatched clicks (beyond 100 ms)
%   are dropped rather than allowed to dominate.
    if isempty(tRef) || isempty(tCam), rms_ = NaN; n = 0; return, end
    d = abs(tRef(:) - (tCam(:)' - lagSec));       % implicit expansion
    dmin = min(d, [], 2);
    keep = dmin < 0.1;
    n = nnz(keep);
    if n == 0, rms_ = NaN; return, end
    rms_ = sqrt(mean(dmin(keep).^2));
end


function plotWave(ax, t, w, clickT, xspan, inf1, iCam, lagSec, showFrames)
%PLOTWAVE One camera's waveform with its clicks numbered.
    hold(ax, 'on'); grid(ax, 'on');
    fill(ax, [t; flipud(t)], [w; -flipud(w)], [0.25 0.45 0.70], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.85);

    for c = 1:numel(clickT)
        xline(ax, clickT(c), 'r-', 'LineWidth', 1.0);
        text(ax, clickT(c), 1.02, sprintf('%d', c), 'Color', 'r', ...
            'FontSize', 8, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end

    ylim(ax, [-1.25 1.35]);
    xlim(ax, xspan);
    ax.YTick = [];
    if showFrames
        lab = sprintf('[%d] %s   %.3f fps   %d click(s)', ...
            iCam, inf1.name, inf1.fps, numel(clickT));
    else
        lab = sprintf('[%d] %s   shifted by %+.4f s', ...
            iCam, inf1.name, -lagSec);
    end
    ylabel(ax, sprintf('[%d]', iCam), 'FontWeight', 'bold');
    title(ax, lab, 'Interpreter', 'none', 'FontSize', 9, ...
          'FontWeight', 'normal');
end


function s = timecodeStr(t)
%TIMECODESTR Seconds -> hh:mm:ss.mmm
    if ~isfinite(t), s = '   --   '; return, end
    neg = t < 0; t = abs(t);
    h = floor(t/3600); m = floor((t - 3600*h)/60); sec = t - 3600*h - 60*m;
    s = sprintf('%02d:%02d:%06.3f', h, m, sec);
    if neg, s = ['-' s]; end
end


function s = truncName(s, n)
    if numel(s) > n, s = ['..' s(end-n+3:end)]; end
end
