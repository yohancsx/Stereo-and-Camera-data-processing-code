function [upts] = fisheyeUndistort_v4(dpts,mode)

% function [pts] = fisheye_undistort_v4(dpts,tdata)
%
% This routine applies the fisheye undistortion to the input points,
% undistortion coefficients are set based on the "mode" input.  Here are a
% list of known modes:
%
% 'GP3_720p_wide' - GoPro Hero3+ black, 720p/wide shooting mode
% 'GP4_960p_wide' - GoPro Hero4 black, 960p/wide shooting mode
% 'GP4_2.7K_wide' - GoPro Hero4 black, 2.7K/wide shooting mode
% 'GP4_1440p_wide' - GoPro Hero4 black, 1440p/wide shooting mode
% 'GP4_1080p_wide' - GoPro Hero4 black, 1080p/wide shooting mode
% 'GP4_480p_wide' - GoPro Hero4 black, 480p/wide (240 fps) shooting mode
% 'GP5_1080p_wide' - GoPro Hero5 black, 1080p/wide shooting mode
% 'GP6_1080p_wide' - GoPro Hero6, 1080p/wide shooting mode
%
% updated - 10272015 by Pranav Khandelwal
% Ty Hedrick 2016-02-12 based on Pranav's fisheye_undistort.m
% Ty Hedrick 2016-02-24 added GP3B_1080p_wide
% Ty Hedrick 2016-05-25 added GP4_960p_wide
% Ty Hedrick 2017-12-06 added GP5_1080p_wide, fixed r2017b compatibility
% Ty Hedrick 2017-12-11 added GP5_720p_wide
% Ty Hedrick 2018-04-17 added GP6_1080p_wide
%
% _v3 Ty Hedrick 2018-05-02 Makes two substantial improvements. First, the
% model fc is used, not fc = 4 as in versions 1 and 2. Second, the vertical
% coordinate is inverted to account for the fisheye calibration being in
% standard image coordinates with the origin in the upper left and DLTdv
% (and Argus) using Hedrickized coordinates with the origin in the lower
% left.
%
% Pranav Khandelwal 2019-10-09 added multiple xy pair handling capability
%
% Notes on converting from the Argus Fisheye calibration strings:
%
% Here's the order of the Argus entries:
% name,?,width,height,c,d,e,xc,yc,ss(1),ss(2),ss(3),ss(4),ss(5),?,?,?,?,?,?

if isstruct(mode)
  mode=mode.tdata;
end

% load camera parameters
%load('Omni_Calib_Results.mat');
%ocam_model=calib_data.ocam_model;
%% camera profiles to be selected
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if strcmpi(mode,'GP4_960p_wide')
  % 960p @60fps, Wide field of view - ocam model
  
  % define ocam_model (instead of loading from ocamcalib results)
  ocam_model.ss(1,1)=-561.2277003835;
  ocam_model.ss(2,1)=0;
  ocam_model.ss(3,1)=0.0004846941;
  ocam_model.ss(4,1)=2.8547e-9;
  ocam_model.ss(5,1)=3.54e-11;
  ocam_model.xc=472.6683719824;
  ocam_model.yc=650.6339006993;
  ocam_model.c=0.9994469914;
  ocam_model.d=-0.0010949744;
  ocam_model.e=0.0011497611;
  ocam_model.width=1280;
  ocam_model.height=960;
  
  % define image/video resolution
  Nwidth = 1280; %size of the final image
  Nheight = 960;
  
  fc = 4; %amount of zoom (4 seems to work for GoPro4 wide angle and capture the entire FOV)
  
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
elseif strcmpi(mode,'GP4_2.7K_wide')
  % 2.7K @60fps, Wide field of view - ocam model
  
  % define ocam_model (instead of loading from ocamcalib results)
  ocam_model.ss(1,1)=-1.234767106495970e3;
  ocam_model.ss(2,1)=0;
  ocam_model.ss(3,1)=0.000000233157305e3;
  ocam_model.ss(4,1)=-0.000000000021227e3;
  ocam_model.ss(5,1)=0.000000000000014e3;
  ocam_model.xc=7.669108374384379e+02;
  ocam_model.yc=1.352406563245692e+03;
  ocam_model.c=0.999289595465724;
  ocam_model.d=-0.006963540857230;
  ocam_model.e=0.007533029275197;
  ocam_model.width=2704;
  ocam_model.height=1520;
  
  % define image/video resolution
  Nwidth = 2704; %size of the final image
  Nheight = 1520;
  
  fc = 4; %amount of zoom (4 seems to work for GoPro4 wide angle and capture the entire FOV)
  
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
elseif strcmpi(mode,'GP4_1440p_wide');
  %1440p @80fps, wide field of view - ocam model
  
  % define ocam_model (instead of loading from ocamcalib results)
  ocam_model.ss(1,1)=-8.477755708037934e+02;
  ocam_model.ss(2,1)=0;
  ocam_model.ss(3,1)=3.883048138762428e-04;
  ocam_model.ss(4,1)=-1.510687839308625e-07;
  ocam_model.ss(5,1)=9.372182811924376e-11;
  ocam_model.xc=7.184445375924397e+02;
  ocam_model.yc=9.771355515393601e+02;
  ocam_model.c=0.999938379179311;
  ocam_model.d=-0.016187871855188;
  ocam_model.e=0.016810280637347;
  ocam_model.width=1920;
  ocam_model.height=1440;
  
  % define image/video resolution
  Nwidth = 1920; %size of the final image
  Nheight = 1440;
  
  fc = 4; %amount of zoom (4 seems to work for GoPro4 wide angle and capture the entire FOV)
  
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
elseif strcmpi(mode,'GP4_1080p_wide')
  %1080p @120fps, wide field of view - ocam model
  
  % define ocam_model (instead of loading from ocamcalib results)
  ocam_model.ss(1,1)=-878.233827636196;
  ocam_model.ss(2,1)=0;
  ocam_model.ss(3,1)=0.0003102319339;
  ocam_model.ss(4,1)=0.0000000032907;
  ocam_model.ss(5,1)=0.0000000000103;
  ocam_model.xc=531.37446537215;
  ocam_model.yc=976.090199227024;
  ocam_model.c=1.00778152468958;
  ocam_model.d=-0.003542483075365;
  ocam_model.e=0.003742925400506;
  ocam_model.width=1920;
  ocam_model.height=1080;
  
  % define image/video resolution
  Nwidth = 1920; %size of the final image
  Nheight = 1080;
  
  fc = 4; %amount of zoom (4 seems to work for GoPro4 wide angle and capture the entire FOV)
  
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  
elseif strcmpi(mode,'GP4_480p_wide')
  %480p @240fps, wide field of view - ocam model
  
  % define ocam_model (instead of loading from ocamcalib results)
  ocam_model.ss(1,1)=-3.874821106938145e2;
  ocam_model.ss(2,1)=0;
  ocam_model.ss(3,1)=0.000007030006369e2;
  ocam_model.ss(4,1)=0.000000000073133e2;
  ocam_model.ss(5,1)=0.000000000001439e2;
  ocam_model.xc=2.355247543774561e+02;
  ocam_model.yc=4.308256491888478e+02;
  ocam_model.c=1.006134958833511;
  ocam_model.d=-3.294295058161427e-04;
  ocam_model.e=5.270098550859433e-04;
  ocam_model.width=848;
  ocam_model.height=480;
  
  % define image/video resolution
  Nwidth = 848; %size of the final image
  Nheight = 480;
  
  fc = 4; %amount of zoom (4 seems to work for GoPro4 wide angle and capture the entire FOV)
  
elseif strcmpi(mode,'GP5_1080p_wide')
  %1080p @120fps, wide field of view - ocam model
  
  % define ocam_model (instead of loading from ocamcalib results)
  % first pass
%   ocam_model.ss(1,1)=-847.1403;
%   ocam_model.ss(2,1)=0;
%   ocam_model.ss(3,1)=2.6210e-04;
%   ocam_model.ss(4,1)=1.9087e-07;
%   ocam_model.ss(5,1)=-9.3285e-11;
%   ocam_model.xc=524.9973;
%   ocam_model.yc=947.6678;
%   ocam_model.c=0.9989;
%   ocam_model.d=2.4366e-04;
%   ocam_model.e=0.0026;
%   ocam_model.width=1920;
%   ocam_model.height=1080;
  
  % second pass
  ocam_model.ss(1,1)=-9.419080075013920e+02;
  ocam_model.ss(2,1)=0;
  ocam_model.ss(3,1)=3.485059372262522e-04;
  ocam_model.ss(4,1)=-2.688408104617925e-08;
  ocam_model.ss(5,1)=7.812132439782389e-12;
  ocam_model.xc=5.334676257216465e+02;
  ocam_model.yc=9.663780254990372e+02;
  ocam_model.c=0.998233333369969;
  ocam_model.d=-0.014457913318790;
  ocam_model.e=0.016286050872427;
  ocam_model.width=1920;
  ocam_model.height=1080;
  
  
  % define image/video resolution
  Nwidth = 1920; %size of the final image
  Nheight = 1080;
  
  fc = 4; %amount of zoom (4 seems to work for GoPro4 wide angle and capture the entire FOV)
  
  elseif strcmpi(mode,'GP3_720p_wide')
  %720p @60fps, wide field of view - ocam model
  
  ocam_model.ss(1,1)=-5.964860064092100e2;
  ocam_model.ss(2,1)=0;
  ocam_model.ss(3,1)=0.000006317642603e2;
  ocam_model.ss(4,1)=-0.000000002252898e2;
  ocam_model.ss(5,1)=-0.000000000000015e2;
  ocam_model.xc=3.495968049386204e+02;
  ocam_model.yc=6.551208185430136e+02;
  ocam_model.c=1.038962477337479;
  ocam_model.d=0.011039937655688;
  ocam_model.e=-0.010160134900257;
  ocam_model.width=1280;
  ocam_model.height=720;
  
  % define image/video resolution
  Nwidth = 1280; %size of the final image
  Nheight = 720;
  
  fc = 4; %amount of zoom (4 seems to work for GoPro4 wide angle and capture the entire FOV)
  
elseif strcmpi(mode,'GP6_1080p_wide')
  %1080p @240fps, wide field of view - ocam model
  
%   % Ty 2018-04-17 scaramuzza w/ Urban
%   ocam_model.ss(1,1)=-8.752221e+02;
%   ocam_model.ss(2,1)=0;
%   ocam_model.ss(3,1)=3.086019e-04;
%   ocam_model.ss(4,1)=3.200529e-08;
%   ocam_model.ss(5,1)=-2.342087e-11;
%   ocam_model.xc=548.176470;
%   ocam_model.yc=963.251238;
%   ocam_model.c=1.005802;
%   ocam_model.d=0.005289;
%   ocam_model.e=-0.006500;
%   ocam_model.width=1920;
%   ocam_model.height=1080;
  
  % Ty 2018-04-17 scaramuzza w/ Urban - revised (argus _v4c)
  ocam_model.ss(1,1)=-8.783667e+02;
  ocam_model.ss(2,1)=0;
  ocam_model.ss(3,1)=3.621306e-04;
  ocam_model.ss(4,1)=-1.551353e-07;
  ocam_model.ss(5,1)=1.433537e-10;
  ocam_model.xc=552.249137;
  ocam_model.yc=962.213451;
  ocam_model.c=1.004725;
  ocam_model.d=-0.026136;
  ocam_model.e=0.024187;
  ocam_model.width=1920;
  ocam_model.height=1080;
  
  
  % define image/video resolution
  Nwidth = 1920; %size of the final image
  Nheight = 1080;
  
  fc = 5; %amount of zoom (4 seems to work for GoPro4 wide angle and capture the entire FOV)
  
else
  disp('fisheyeUndistort_v3 - unknown mode - halting')
  upts=[];
  return
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Do not change this part of the code!

% to handle multiple pts
nXY = size(dpts,2)/2;
for i = 1:nXY
    tmp_dpts = dpts(:,2*i-1:2*i);
Nxc = Nheight/2;
Nyc = Nwidth/2;
Nz  = -Nwidth/fc; % in practice, FC is fixed at 4.0 in the undistort

% transform Y coordinate of dpts to standard image coordinates
%dpts(:,1)=Nwidth-dpts(:,1);
%dpts(:,2)=Nheight-dpts(:,2);

% transpose to image style layout
tmp_dpts=tmp_dpts';

ind=find(isnan(tmp_dpts)); % finding the NaNs (OcamCalib spits out a value for NaNs also)

M = cam2world([tmp_dpts(2,:);tmp_dpts(1,:)],ocam_model); % NOTE!!! input y,x format here!
%M = M./(ones(3,1)*M(3,:))*(-Nwidth/4); % broken _v2 implementation
M = M./(ones(3,1)*M(3,:))*(-Nwidth/fc); % test by Ty on 2018-04-26

ti = M(1,:) + Nxc;
tj = M(2,:) + Nyc;

und_points = [tj ; ti];% NOTE!!! output is X,Y format! row1 is X and row2 is Y
und_points(ind) = nan; %replacing the false values due to NaNs with NaNs again
upts(:,2*i-1:2*i) = und_points';
end

% transform back to Hedrick image coordinate system
%pts(:,1)=Nwidth-pts(:,1);
%pts(:,2)=Nheight-pts(:,2);

%CAM2WORLD Project a give pixel point onto the unit sphere
%   M=CAM2WORLD=(m, ocam_model) returns the 3D coordinates of the vector
%   emanating from the single effective viewpoint on the unit sphere
%
%   m=[rows;cols] is a 2xN matrix containing the pixel coordinates of the image
%   points.
%
%   "ocam_model" contains the model of the calibrated camera.
%
%   M=[X;Y;Z] is a 3xN matrix with the coordinates on the unit sphere:
%   thus, X^2 + Y^2 + Z^2 = 1
%
%   Last update May 2009
%   Copyright (C) 2006 DAVIDE SCARAMUZZA
%   Author: Davide Scaramuzza - email: davide.scaramuzza@ieee.org

function M=cam2world(m, ocam_model)

n_points = size(m,2);

ss = ocam_model.ss;
xc = ocam_model.xc;
yc = ocam_model.yc;
width = ocam_model.width;
height = ocam_model.height;
c = ocam_model.c;
d = ocam_model.d;
e = ocam_model.e;

A = [c,d;
  e,1];
T = [xc;yc]*ones(1,n_points);

m = A^-1*(m-T);
M = getpoint(ss,m);
%M = normc(M); %normalizes coordinates so that they have unit length (projection onto the unit sphere)
M = M./repmat(rnorm(M')',size(M,1),1); % replace normc, which requires the neural network toolbox

function w=getpoint(ss,m)

% Given an image point it returns the 3D coordinates of its correspondent optical
% ray

w = [m(1,:) ; m(2,:) ; polyval(ss(end:-1:1),sqrt(m(1,:).^2+m(2,:).^2)) ];

function [norms] = rnorm(matrix)

% function [norms] = rnorm(matrix)
%
% Description: rnorm returns a column of norm values.  Given an input
% 	       matrix of X rows and Y columns it returns an X by 1
%	       column of norms.

norms=sqrt(dot(matrix',matrix'))';