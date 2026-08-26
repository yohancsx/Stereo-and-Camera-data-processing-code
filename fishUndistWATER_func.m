function undistPts = fishUndistWATER_func(inPts,fakeVar)
    %custom fisheye undist function
    mappingCoeffs = [2.5801e+03,-1.4389e-04,2.2488e-08,-4.2507e-12];
    imSize = [2992,5312];
    distCenter = [2.6933e+03,1.4944e+03];
    stretchMat = [1,0;0,1];

    %set the intrinsics
    cameraParamsFisheye = fisheyeIntrinsics(mappingCoeffs,imSize,distCenter,stretchMat);
    
    %undistort
    undistPts = undistortFisheyePoints(inPts, cameraParamsFisheye);
end
