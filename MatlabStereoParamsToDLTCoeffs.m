function dltCoeffs = MatlabStereoParamsToDLTCoeffs(stereoParams)
    %Yohan Sequeira, 11-24-25
    %Converts matlab stereo parameters from the stereo camera calibrator to
    %the associated DLT coefficients.
    %NOTE: does not account for fisheye/other distortion! For gopro
    %cameras, there will be some minor error using the DLT coefficients fro
    %reconstruction due to not accounting for the error. Note that this can
    %be avoided by undistorting the points, but ONLY by using radial and
    %tangential distortion. Using fisheye undistortion may introduce
    %error...
    %see: https://biomech.web.unc.edu/dlt-to-from-intrinsic-extrinsic/ for
    %details on conversion.

    %since one of the cameras is set as the origin (per matlab stereo
    %calibration, we use that method)
    eR = eye(3); %external rotation, a 3x3 identity matrix
    eT = [1 1 1]; %external translation, 1 units in each direction
    eRT = [eR, eT'
       0 0 0 1]; %external translation and rotation, homogenized to a 4x4 matrix
    
    %FIRST CAMERA
    %f_x,y are the horizontal and vertical focal lengths, 
    %p_x,y are the horizontal and vertical image center in pixels
    f_x = stereoParams.CameraParameters1.FocalLength(1);
    p_x = stereoParams.CameraParameters1.ImageSize(2)*0.5;
    f_y = stereoParams.CameraParameters1.FocalLength(2);
    p_y = stereoParams.CameraParameters1.ImageSize(1)*0.5;
    K = [f_x  0 p_x;
     0  f_y p_y;
     0   0   1 ];
    %or set K directly
    K = stereoParams.CameraParameters1.K;

    %rotation translation (nothing for first camera)
    %R is the extrinsic rotation matrix, T is the extrinsic translation vector 
    P = [eye(3), [0 0 0]';
     0 0 0 1];

    %last needed matrix
    m = [1 0 0 0;
     0 1 0 0;
     0 0 1 0];

    %calculate coeffs for the first camera
    DLTCoeffsCam1 = K*m*P*eRT;
    DLTCoeffsCam1Norm = DLTCoeffsCam1/DLTCoeffsCam1(3,4);
    DLTCoeffsCam1Final = DLTCoeffsCam1Norm(1:11);

    %SECOND CAMERA
    %f_x,y are the horizontal and vertical focal lengths, 
    %p_x,y are the horizontal and vertical image center in pixels
    f_x = stereoParams.CameraParameters2.FocalLength(1);
    p_x = stereoParams.CameraParameters2.ImageSize(2)*0.5;
    f_y = stereoParams.CameraParameters2.FocalLength(2);
    p_y = stereoParams.CameraParameters2.ImageSize(1)*0.5;
    K = [f_x  0 p_x;
     0  f_y p_y;
     0   0   1 ];
    %or set K directly
    K = stereoParams.CameraParameters2.K;

    %rotation translation
    %just use the given pose here
    P = stereoParams.PoseCamera2.A;

    %last needed matrix
    m = [1 0 0 0;
     0 1 0 0;
     0 0 1 0];

    %calculate coeffs for the first camera
    DLTCoeffsCam2 = K*m*P*eRT;
    DLTCoeffsCam2Norm = DLTCoeffsCam2/DLTCoeffsCam2(3,4);
    DLTCoeffsCam2Final = DLTCoeffsCam2Norm(1:11);
    
    %combine the coeffs into a single matrix
    dltCoeffs = [DLTCoeffsCam1Final', DLTCoeffsCam2Final'];
end