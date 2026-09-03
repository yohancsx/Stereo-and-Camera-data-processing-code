function intrinsics = loadFisheyeIntrinsics(matPath)
% Written by Yohan Sequeira 2026
% LOADFISHEYEINTRINSICS  Pull a fisheyeIntrinsics object out of a .mat file.
%
%   The MATLAB Camera Calibrator app saves a variable (often named
%   'cameraParams') that is a fisheyeParameters object. This helper loads
%   the file, finds that object no matter what the variable is called, and
%   returns its .Intrinsics (a fisheyeIntrinsics object) ready for
%   undistortUV / undistortFisheyePoints.
%
% INPUT:
%   matPath - full path to the .mat file exported by the calibrator app.
%
% OUTPUT:
%   intrinsics - a fisheyeIntrinsics object.

    S = load(matPath);
    fn = fieldnames(S);

    intrinsics = [];
    for i = 1:numel(fn)
        v = S.(fn{i});
        if isa(v, 'fisheyeIntrinsics')
            intrinsics = v;
            return
        elseif isa(v, 'fisheyeParameters')
            intrinsics = v.Intrinsics;
            return
        elseif isprop(v, 'Intrinsics') && isa(v.Intrinsics, 'fisheyeIntrinsics')
            intrinsics = v.Intrinsics;
            return
        end
    end

    error('loadFisheyeIntrinsics:notFound', ...
        ['No fisheyeIntrinsics / fisheyeParameters object found in "%s". ', ...
         'Make sure this .mat was exported from the fisheye Camera ', ...
         'Calibrator app.'], matPath);
end
