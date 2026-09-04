function [obj, kind, imageSize] = sniffCalib(path)
%VH.SNIFFCALIB Pull camera parameters out of a .mat whatever they are called.
%
%   [obj, kind, imageSize] = vh.sniffCalib(path)
%
%   path       a .mat saved by the MATLAB Camera Calibrator app (single or
%              stereo session) or one containing a bare parameters object
%
%   obj        fisheyeIntrinsics or cameraParameters/cameraIntrinsics object,
%              ready for vh.undistortFrame / undistortFisheyePoints
%   kind       'fisheye' | 'standard'
%   imageSize  [H W] the calibration was made at, or [] if unavailable -
%              compare against the image/frame you are about to undistort;
%              a mismatch means a rotated or resized frame will undistort to
%              nonsense
%
%   Errors if the file has neither. Extracted from vh.loadMasks so the same
%   calibration this rig's masks/textures are undistorted with can also be
%   loaded once and reused for undistorting video frames on the fly (see
%   landmarkAnnotator.m's video mode).

assert(isfile(path), 'vh:sniffCalib:noFile', ...
    'Calibration file not found: %s', path);
L = load(path);
fn = fieldnames(L);

% A calibration session saved by the Camera Calibrator app.
for k = 1:numel(fn)
    v = L.(fn{k});
    if isobject(v) && isprop(v, 'CameraParameters')
        [obj, kind] = fromParams(v.CameraParameters);
        if ~isempty(kind), imageSize = calibImageSize(obj, kind); return, end
    end
end

for k = 1:numel(fn)
    [obj, kind] = fromParams(L.(fn{k}));
    if ~isempty(kind), imageSize = calibImageSize(obj, kind); return, end
end

error('vh:sniffCalib:noParams', ...
    ['No camera parameters found in %s.\nExpected a fisheyeParameters, ' ...
     'fisheyeIntrinsics, cameraParameters or cameraIntrinsics object ' ...
     '(variables present: %s).'], path, strjoin(fn', ', '));
end


function [obj, kind] = fromParams(v)
obj = [];  kind = '';
if isa(v, 'fisheyeParameters')
    obj = v.Intrinsics;      kind = 'fisheye';
elseif isa(v, 'fisheyeIntrinsics')
    obj = v;                 kind = 'fisheye';
elseif isa(v, 'cameraParameters') || isa(v, 'cameraIntrinsics')
    obj = v;                 kind = 'standard';
end
end


function sz = calibImageSize(obj, kind)
sz = [];
switch kind
    case 'fisheye'
        if isprop(obj, 'ImageSize'), sz = obj.ImageSize; end
    case 'standard'
        if isprop(obj, 'ImageSize') && ~isempty(obj.ImageSize)
            sz = obj.ImageSize;
        end
end
end
