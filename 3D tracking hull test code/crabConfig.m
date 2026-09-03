function cfg = crabConfig(tool, outFile)
%CRABCONFIG Editable settings for the crab tools, optionally saved to a .mat.
%
%   cfg = crabConfig('legAnnotator')              return the defaults
%   crabConfig('legAnnotator', 'myRun.mat')       write them to a file
%   crabConfig('all', 'cfg.mat')                  one struct per tool
%
%   The point of the file is a run you can come back to: save it once, edit
%   a couple of fields in the workspace, and hand it straight to the tool.
%
%       crabConfig('legAnnotator','cfg.mat');
%       load cfg.mat                    % gives you `cfg`
%       cfg.dataDir = "...\my frame";
%       cfg.imagePattern = '*_roi.png'; % un-thresholded frames
%       crabLegAnnotator(cfg)
%
%   The tools also take the file directly:  crabLegAnnotator('cfg.mat')
%
%   tool: 'legAnnotator' | 'visualHull' | 'stereo' | 'sync' | 'all'

arguments
    tool (1,:) char = 'legAnnotator'
    outFile (1,:) char = ''
end

switch lower(tool)
    case 'legannotator', cfg = legAnnotatorDefaults();
    case 'visualhull',   cfg = crabVisualHull('defaults');
    case 'stereo',       cfg = stereoCrab('defaults');
    case 'sync',         cfg = syncDefaults();
    case 'all'
        cfg = struct('legAnnotator', legAnnotatorDefaults(), ...
                     'visualHull',   crabVisualHull('defaults'), ...
                     'stereo',       stereoCrab('defaults'), ...
                     'sync',         syncDefaults());
    otherwise
        error('crabConfig:tool', ['Unknown tool "%s". Use legAnnotator, ' ...
            'visualHull, stereo, sync or all.'], tool);
end

if ~isempty(outFile)
    save(outFile, 'cfg');
    fprintf('Wrote config to %s\n\n', outFile);
    describe(cfg, tool);
end
end


%% ------------------------------------------------------------------------

function d = legAnnotatorDefaults()
d = struct( ...
    ... % --- where the data is -------------------------------------------
    'dataDir',      '', ...   % folder holding the frame; '' prompts
    'maskFiles',    {{}}, ... % explicit mask list, else globbed
    'imageFiles',   {{}}, ... % explicit texture list, else globbed
    'maskPattern',  '*_mask.png', ...
    'imagePattern', '*_seg.png', ... % '*_roi.png' for un-thresholded frames
    'dltFile',      '', ...   % '' finds the *dlt*.csv in dataDir
    'calibFile',    '', ...   % '' finds the fisheye params in dataDir
    ... % --- geometry ----------------------------------------------------
    'pair',         [2 4], ...  % DLT columns to start on
    'camOrder',     [4 1 3 2], ...
    'yOrigin',      'top', ...
    'undistortScale', 1, ...
    ... % --- behaviour ---------------------------------------------------
    'carryAcrossPairs', true, ... % reproject legs when switching pairs
    'cropToMask',   true, ...     % false shows the whole frame
    'snapEpipolar', false, ...
    ... % --- what the 3-D window shows (turn off for cleaner figures) -----
    'showCloud',    true, ...     % the dense stereo points
    'showBox',      true, ...     % the working-volume wireframe
    ... % --- background cloud --------------------------------------------
    'cloudXYZ',     [], ...
    'cloudFile',    '', ...
    'computeCloud', true, ...
    ... % --- display -----------------------------------------------------
    'dispMaxDim',   1000, ...
    'cropMargin',   80, ...
    'residWarnPx',  8, ...
    'zoomStep',     1.2, ...
    'units',        'wu', ...
    'sessionFile',  '');
end


function d = syncDefaults()
d = struct('files', {{}}, 'refCam', 1, 'window', [0 60], ...
    'driftWindow', [], 'alignAtRefFrame', [], 'bandHz', [200 8000], ...
    'envWinSec', 0.005, 'envFs', 1000, 'waveFs', 2000, 'maxLagSec', 10, ...
    'minProminence', 4, 'minClickSepSec', 0.15, 'maxClicks', 30, ...
    'matchTolSec', 0.10, 'visualCheck', false, 'visualCheckPlusFrames', 0);
end


function describe(cfg, tool)
%DESCRIBE Print the fields most people actually edit.
key = struct( ...
    'legannotator', {{'dataDir','imagePattern','pair','camOrder', ...
                      'carryAcrossPairs','cropToMask','computeCloud'}}, ...
    'visualhull',   {{'maskFiles','dltFile','calibFiles','camOrder', ...
                      'objectSize','fineN'}}, ...
    'stereo',       {{'dataDir','camOrder','pairs','methods'}}, ...
    'sync',         {{'files','window','driftWindow','bandHz'}});
t = lower(tool);
if ~isfield(key, t)
    fprintf('Fields: %s\n', strjoin(fieldnames(cfg)', ', '));
    return
end
fprintf('Most-edited fields for %s:\n', tool);
for k = key.(t)
    for f = k
        if isfield(cfg, f{1})
            fprintf('   cfg.%-18s = %s\n', f{1}, shortVal(cfg.(f{1})));
        end
    end
end
fprintf('\nEdit, then run the tool with that struct (or the .mat path).\n');
end


function s = shortVal(v)
if ischar(v),        s = sprintf('''%s''', v);
elseif isstring(v),  s = sprintf('"%s"', v);
elseif islogical(v), s = mat2str(v);
elseif isnumeric(v) && numel(v) <= 6, s = mat2str(v);
elseif iscell(v) && isempty(v), s = '{}';
elseif iscell(v),    s = sprintf('{%d entries}', numel(v));
else,                s = sprintf('<%s>', class(v));
end
end
