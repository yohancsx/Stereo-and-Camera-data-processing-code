STEPS FOR CAMERA CALIBRATION: CAMERA INTRINSICS - MATLAB



STEPS FOR CAMERA CALIBRATION: CAMERA INTRINSICS - 

Steps for calibration (water tank)
1. sync camera data 
2. click wand points in camera videos 
3. create synced camera images of checkerboards 
4. get intrinsics for cameras through matlab calib 
5. get intrinsics for cameras through Ocam calib 
6. undistort wand points (using either intrinsics)
7. create camera profile from camera intrinsics
8. use easywand to get extrinsics (minimize residuals)

Steps for calibration (in air)
1. sync camera data
2. click a paired set of points in vids (tank corners) and 15-20 unpaired points
3. create synced camera images of checkerboards 
4. get intrinsics for cameras
5. undistort unpaired points
6. create camera profile from intrinsics
7. use easywand to get extrinsics

Steps for tracking
1. Sync vids
2. create DLTDV8 undistortion params from ocam calib intrinsics
3. import videos, extrinsics and distortion profiles
4. click points
5. undistort points using ocamcalib or matlab intrinsics
6. use fast reconstruction to get 3d points