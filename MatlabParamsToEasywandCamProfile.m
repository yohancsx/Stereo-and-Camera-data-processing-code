function easyWandCoeffs = MatlabParamsToEasywandCamProfile(cameraParams)
%Converts matlab camera parameters to the easywand camera profile
% NOTE: this must be a cameraParameters object, and not a fisheye
% parameters object, as the fisheye parameters object doesn't contain
% focal length information
%this profile can be loaded into DLTdv8 for undistortion
easyWandCoeffs = [1,...%camera number
                    mean(cameraParams.Intrinsics.FocalLength),...%focal length (just one) in pixels
                    cameraParams.ImageSize(2),... %image width
                    cameraParams.ImageSize(1),... %image height
                    cameraParams.PrincipalPoint(2),... %principal point 1
                    cameraParams.PrincipalPoint(1),... %principal point 2
                    1,...%just 1 for the matrix
                    cameraParams.RadialDistortion(1),...%radial distortion 1
                    cameraParams.RadialDistortion(2),...%radial distortion 2
                    cameraParams.TangentialDistortion(1),...%tangential distortion 1
                    cameraParams.TangentialDistortion(2),...%tangential distortion 2
                    cameraParams.Intrinsics.RadialDistortion(3),...%radial distortion 3
                    %not sure why the last radial distortion is at the
                    %end...
                    ];
end