function [imgU, camI] = undistortFrame(img, obj, kind, opts)
%VH.UNDISTORTFRAME Undistort one image with a fisheye or standard calibration.
%
%   [imgU, camI] = vh.undistortFrame(img, obj, kind, opts)
%
%   img    the raw distorted image (mask, greyscale, or RGB)
%   obj    a fisheyeIntrinsics/fisheyeParameters or cameraParameters/
%          cameraIntrinsics object - see vh.sniffCalib, which pulls one of
%          these out of a .mat whatever it is called
%   kind   'fisheye' | 'standard' - must match obj's actual type
%   opts   .method       'nearest' (masks) | 'linear' (textures/video
%                         frames), default 'linear'
%          .scaleFactor  fisheye only, passed to undistortFisheyeImage,
%                         default 1
%
%   imgU   the undistorted image
%   camI   the virtual pinhole camera intrinsics implied by the undistortion
%
%   OutputView is forced to 'same', not 'full' or 'valid', so the principal
%   point does not move relative to anything else undistorted with the same
%   calibration (e.g. the wand points that fixed the DLT) - see
%   vh.loadMasks for the full reasoning. Extracted from vh.loadMasks so the
%   same undistortion this rig's masks/textures get can also be applied to
%   a video frame decoded on the fly (see landmarkAnnotator.m's video mode).

arguments
    img
    obj
    kind (1,:) char {mustBeMember(kind, {'fisheye','standard'})}
    opts.method (1,:) char = 'linear'
    opts.scaleFactor (1,1) double = 1
end

switch kind
    case 'fisheye'
        [imgU, camI] = undistortFisheyeImage(img, obj, opts.method, ...
            'OutputView', 'same', 'ScaleFactor', opts.scaleFactor);
    case 'standard'
        [imgU, camI] = undistortImage(img, obj, opts.method, ...
            'OutputView', 'same');
end
end
