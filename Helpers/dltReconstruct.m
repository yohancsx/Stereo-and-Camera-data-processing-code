function xyz = dltReconstruct(c,camPtsRaw)

% function [xyz] = dlt_reconstruct_fast(c,camPts)
%
% This function reconstructs the 3D position of a coordinate based on a set
% of DLT coefficients and [u,v] pixel coordinates from 2 or more cameras
%
% Inputs:
%  c - 12 DLT coefficients for all n cameras, [12,n] array
%  camPtsRaw - [u;v] pixel coordinates from all n cameras over f frames,
%   [2,n] array [u;v]
%
% Outputs:
%  xyz - the xyz location in each frame, an [f,3] array
%  rmse - the root mean square error for each xyz point, and [f,1] array,
%   units are [u,v] i.e. camera coordinates or pixels
%
% Written by Yohan Sequeira 2026 - Adapted from Ty Hedrick's code (2024). Note that we aren't assuming
% the camera axes are aligned in any way, so it requirues all 12 coeffs

% Reshape camPtsRaw [2 x nCams] into [1 x 2*nCams] row vector
camPts = [];
for i = 1:size(camPtsRaw, 2)
    camPts = [camPts, camPtsRaw(:,i)'];
end

nFrames = size(camPts, 1);
nCams   = size(camPts, 2) / 2;
nCoeffs = size(c, 1);       % 11 or 12

xyz  = NaN(nFrames, 3);
rmse = NaN(nFrames, 1);

for i = 1:nFrames
    % Cameras with non-NaN [u,v]
    cdx = find(~isnan(camPts(i, 1:2:nCams*2)));

    if numel(cdx) >= 2
        m1 = zeros(numel(cdx)*2, 3);
        m2 = zeros(numel(cdx)*2, 1);

        % Get c12 for each camera — either supplied or assumed to be 1
        if nCoeffs == 12
            c12 = c(12, cdx);
        else
            c12 = ones(1, numel(cdx));
        end

        u = camPts(i, cdx*2-1);
        v = camPts(i, cdx*2);

        % u equation: (c1*X + c2*Y + c3*Z + c4) - u*(c9*X + c10*Y + c11*Z + c12) = 0
        m1(1:2:end, 1) = u .* c(9,cdx)  - c(1,cdx);
        m1(1:2:end, 2) = u .* c(10,cdx) - c(2,cdx);
        m1(1:2:end, 3) = u .* c(11,cdx) - c(3,cdx);
        m2(1:2:end)    = c(4,cdx) - u .* c12;

        % v equation: (c5*X + c6*Y + c7*Z + c8) - v*(c9*X + c10*Y + c11*Z + c12) = 0
        m1(2:2:end, 1) = v .* c(9,cdx)  - c(5,cdx);
        m1(2:2:end, 2) = v .* c(10,cdx) - c(6,cdx);
        m1(2:2:end, 3) = v .* c(11,cdx) - c(7,cdx);
        m2(2:2:end)    = c(8,cdx) - v .* c12;

        % Least squares solution
        xyz(i, 1:3) = mldivide(m1, m2)';

        % % RMSE in pixel units
        % uv  = m1 * xyz(i,1:3)';
        % dof = numel(m2) - 3;
        % rmse(i,1) = sqrt(sum((m2 - uv).^2) / dof);
    end
end

% %reshape the camPoints for DLT reconstruct
% camPts = [];
% for i = 1:size(camPtsRaw,2)
%     camPts = [camPts, camPtsRaw(:,i)'];
% end
% 
% % number of frames
% nFrames=size(camPts,1);
% 
% % number of cameras
% nCams=size(camPts,2)/2;
% 
% % setup output variables
% xyz(1:nFrames,1:3)=NaN;
% rmse(1:nFrames,1)=NaN;
% 
% % process each frame
% for i=1:nFrames
% 
%     % get a list of cameras with non-NaN [u,v]
%     cdx=find(isnan(camPts(i,1:2:nCams*2))==false);
% 
%     % if we have 2+ cameras, begin reconstructing
%     if numel(cdx)>=2
% 
%         % preallocate least-square solution matrices
%         m1=zeros(numel(cdx)*2,3);
%         m2=zeros(numel(cdx)*2,1);
% 
%         m1(1:2:numel(cdx)*2,1)=camPts(i,cdx*2-1).*c(9,cdx)-c(1,cdx);
%         m1(1:2:numel(cdx)*2,2)=camPts(i,cdx*2-1).*c(10,cdx)-c(2,cdx);
%         m1(1:2:numel(cdx)*2,3)=camPts(i,cdx*2-1).*c(11,cdx)-c(3,cdx);
%         m1(2:2:numel(cdx)*2,1)=camPts(i,cdx*2).*c(9,cdx)-c(5,cdx);
%         m1(2:2:numel(cdx)*2,2)=camPts(i,cdx*2).*c(10,cdx)-c(6,cdx);
%         m1(2:2:numel(cdx)*2,3)=camPts(i,cdx*2).*c(11,cdx)-c(7,cdx);
% 
%         %m2(1:2:numel(cdx)*2,1)=c(4,cdx)-camPts(i,cdx*2-1);
%         m2(1:2:numel(cdx)*2,1) = c(4,cdx)  - camPts(i,cdx*2-1) .* c(12,cdx);
%         m2(2:2:numel(cdx)*2,1)=c(8,cdx)-camPts(i,cdx*2);
% 
%         % get the least squares solution to the reconstruction
%         xyz(i,1:3)=mldivide(m1,m2)';
%         xyz = xyz';
%         % compute ideal [u,v] for each camera
%         %uv=m1*xyz(i,1:3)';
% 
%         % compute the number of degrees of freedom in the reconstruction
%         %dof=numel(m2)-3;
% 
%         % estimate the root mean square reconstruction error
%         %rmse(i,1)=(sum((m2-uv).^2)/dof)^0.5;
%     end
end