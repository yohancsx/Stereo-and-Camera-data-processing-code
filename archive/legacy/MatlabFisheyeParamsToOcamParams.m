function [ocam_model, fc, Nwidth, Nheight] = MatlabFisheyeParamsToOcamParams(fisheyeParams)
    %Yohan Sequeira, 11-24-2025
    %This function converts the matlab fisheye parameters from the fisheye
    %calibration tool to the ocam calib parameters (often used by DLTdv8 and
    %other undistortion codes
    %INPUTS:
    % fisheyeParams - the structure with type fisheyeParams, taken from a
    % camera calibrated with the single camera calibrator app
    %OUTPUTS:
    %ocam_model - a structure with the ocam calib coefficients needed for fast
    %undistortion. See this link for more info: https://www.mathworks.com/help/vision/ug/fisheye-calibration-basics.html
    %fc - arbitrary amount of zoom (may need to be changed but 4 or 5
    %usually works
    %Nwidth - the width of the final undistorted image
    %Nheight - the height of the final undistorted image

    %parse the fisheye params
    %Scaramuzza coefficients (NOTE: matlab coeffs are negative of those
    %from ocam calib, and matlab only does 4 coeffs instead of 5)
    ocam_model.ss(1,1)= -1*fisheyeParams.Intrinsics.MappingCoefficients(1);
    ocam_model.ss(2,1)= -1*fisheyeParams.Intrinsics.MappingCoefficients(2);
    ocam_model.ss(3,1)= -1*fisheyeParams.Intrinsics.MappingCoefficients(3);
    ocam_model.ss(4,1)= -1*fisheyeParams.Intrinsics.MappingCoefficients(3);
    ocam_model.ss(5,1)= 0.0;

    %Stretch and centering coefficients
    ocam_model.xc = fisheyeParams.Intrinsics.DistortionCenter(2);
    ocam_model.yc = fisheyeParams.Intrinsics.DistortionCenter(2);
    ocam_model.c = fisheyeParams.Intrinsics.StretchMatrix(1,1);
    ocam_model.d = fisheyeParams.Intrinsics.StretchMatrix(1,2);
    ocam_model.e = fisheyeParams.Intrinsics.StretchMatrix(2,1);
    ocam_model.width = fisheyeParams.Intrinsics.ImageSize(2);
    ocam_model.height = fisheyeParams.Intrinsics.ImageSize(1);
    
    %define image/video resolution
    Nwidth = fisheyeParams.Intrinsics.ImageSize(2); %size of the final image
    Nheight = fisheyeParams.Intrinsics.ImageSize(1);
    
    %zoom level (somewhat arbitrary)
    fc = 4;

end