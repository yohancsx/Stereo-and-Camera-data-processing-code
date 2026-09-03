function [camud, camd] = makefisheye_tform(name)
% function [camud camd] = makefisheye_tform(name)
%
% Create forward and reverse tforms for intrinsic camera parameters:
% name: filename to use in saving the tforms
%
% here, the undistort transform will be made from the fisheye undistort
% parameters given in matlab
% example usage: makefisheye_tform('fisheye_transform_v2.mat')


% Get window resolution
res=[2704,1520]; % GoPro size
nc = res(1); nr = res(2);

% Create mesh grid for interpolation points
[mx,my] = meshgrid(1:10:nc, 1:10:nr);
px = reshape(mx',numel(mx),1);
py = reshape(my',numel(my),1);
cp = [px py];

% Apply undistort transform
imp = fisheyeUndistort_v4(cp,'GP5_1080p_wide');

% Local weighted mean: 1
% Choose some control points and the corresponding image points
points = ceil(numel(px)*rand(1000,1));
points = unique(sort(points));
cpnonlinear = cp(points,:);
impnonlinear = imp(points,:);
% Use cp2tform to find local weighted mean approx. of the inverse transform
camd = cp2tform(cpnonlinear,impnonlinear,'lwm',15);

% Create reverse Tform from undistort_Tform.m
% maketform('custom',#dims_in,#dims_out,forward_function,reverse_fuction,tdata)
%   tdata is input that the forward and reverse functions will receive:
%   function(dim_data,tdata)
camud = maketform('custom',2,2,[],@fisheye_undistort,[]);

% Save Tforms to file
save(name,'camd','camud');