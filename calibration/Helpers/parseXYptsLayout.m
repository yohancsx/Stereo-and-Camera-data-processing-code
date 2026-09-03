function [nPts, nCams, ptNames] = parseXYptsLayout(headerNames)
% Written by Yohan Sequeira 2026
% PARSEXYPTSLAYOUT  Work out how many points and cameras a DLTdv-style
% xypts file contains from its column headers.
%
%   Column headers follow the DLTdv convention:
%       ptP_camC_U , ptP_camC_V
%   ordered point-major, camera-minor, e.g.:
%       pt1_cam1_U, pt1_cam1_V, pt1_cam2_U, pt1_cam2_V, ...
%
% INPUT:
%   headerNames - cellstr / string array of column names (2*nPts*nCams).
%
% OUTPUTS:
%   nPts    - number of tracked points.
%   nCams   - number of cameras.
%   ptNames - 1 x nPts cellstr of point labels, e.g. {'pt1','pt2',...}.

    headerNames = string(headerNames);

    tokens = regexp(headerNames, '^pt(\d+)_cam(\d+)_([UV])$', 'tokens', 'once');
    ok = ~cellfun(@isempty, tokens);
    if ~all(ok)
        bad = headerNames(find(~ok, 1));
        error('parseXYptsLayout:badHeader', ...
            ['Column "%s" does not match the expected ptP_camC_U/V ', ...
             'naming. Check the CSV was exported from DLTdv.'], bad);
    end

    ptIdx  = cellfun(@(t) str2double(t{1}), tokens);
    camIdx = cellfun(@(t) str2double(t{2}), tokens);

    nPts  = max(ptIdx);
    nCams = max(camIdx);

    if numel(headerNames) ~= 2 * nPts * nCams
        error('parseXYptsLayout:sizeMismatch', ...
            ['Column count (%d) does not equal 2*nPts*nCams (2*%d*%d=%d). ', ...
             'The file may have missing or extra columns.'], ...
            numel(headerNames), nPts, nCams, 2*nPts*nCams);
    end

    ptNames = arrayfun(@(k) sprintf('pt%d', k), 1:nPts, 'UniformOutput', false);
end
