function A = epipolarAudit(F, p1, p2, opts)
%VH.EPIPOLARAUDIT Is the epipolar error the calibration's fault or the matcher's?
%
%   A = vh.epipolarAudit(F, p1, p2, opts)
%
%   F        fundamental matrix from the DLT (image coordinates)
%   p1, p2   n-by-2 UNCONSTRAINED feature matches in the same coordinates
%
%   A  .sampsonDLT      Sampson distance of every match under the DLT's F
%      .Fdata           F re-estimated from the matches by RANSAC
%      .inliers         logical, matches consistent with Fdata
%      .sampsonData     Sampson distance of the inliers under Fdata
%      .verdict         'calibration' | 'matches' | 'both' | 'inconclusive'
%
%   THE ATTRIBUTION
%   A large row error after rectification has two possible causes, and they
%   need different fixes:
%
%     * the feature matches are wrong        -> improve matching
%     * the DLT's epipolar geometry is wrong -> recalibrate
%
%   Fitting F to the matches themselves separates them. If a data-driven F
%   explains a large fraction of the matches to within a pixel or two, the
%   matches are real; and if the DLT's F then puts those same matches tens
%   of pixels off their epipolar lines, the DLT is what is wrong.

arguments
    F (3,3) double
    p1 double
    p2 double
    opts.distanceThreshold (1,1) double = 3
    opts.verbose (1,1) logical = true
end

A = struct('n', size(p1,1), 'sampsonDLT', [], 'Fdata', [], ...
           'inliers', [], 'sampsonData', [], 'verdict', 'inconclusive', ...
           'medDLT', NaN, 'medData', NaN, 'inlierFrac', NaN);

if size(p1,1) < 8
    if opts.verbose
        fprintf('    epipolar audit: only %d matches, not enough to judge\n', ...
            size(p1,1));
    end
    return
end

A.sampsonDLT = sampson(F, p1, p2);
A.medDLT = median(A.sampsonDLT);

try
    [Fd, inl] = estimateFundamentalMatrix(p1, p2, 'Method', 'RANSAC', ...
        'NumTrials', 5000, 'DistanceThreshold', opts.distanceThreshold, ...
        'Confidence', 99.9);
catch ME
    if opts.verbose
        fprintf('    epipolar audit: RANSAC failed (%s)\n', ME.message);
    end
    return
end

A.Fdata = Fd;
A.inliers = inl;
A.inlierFrac = nnz(inl) / numel(inl);
if nnz(inl) >= 8
    A.sampsonData = sampson(Fd, p1(inl,:), p2(inl,:));
    A.medData = median(A.sampsonData);
    % The DLT's F, judged on the matches the data itself considers good.
    A.medDLTonInliers = median(sampson(F, p1(inl,:), p2(inl,:)));
else
    A.medDLTonInliers = NaN;
end

goodMatches = A.inlierFrac >= 0.3 && A.medData <= 2*opts.distanceThreshold;
badDLT      = A.medDLTonInliers > 5;

if goodMatches && badDLT,        A.verdict = 'calibration';
elseif ~goodMatches && badDLT,   A.verdict = 'both';
elseif ~goodMatches,             A.verdict = 'matches';
else,                            A.verdict = 'ok';
end

if opts.verbose
    fprintf('    epipolar audit on %d unconstrained matches\n', A.n);
    fprintf('      RANSAC F fits %d of them (%.0f%%) to %.2f px median\n', ...
        nnz(inl), 100*A.inlierFrac, A.medData);
    fprintf('      the DLT''s F puts those same matches %.1f px off\n', ...
        A.medDLTonInliers);
    switch A.verdict
        case 'calibration'
            fprintf(['      -> the matches are real and mutually consistent; ' ...
                'the DLT epipolar\n         geometry is what is wrong. ' ...
                'Recalibration is the fix.\n']);
        case 'matches'
            fprintf('      -> the matches themselves are unreliable.\n');
        case 'both'
            fprintf('      -> both the matches and the calibration are poor.\n');
        case 'ok'
            fprintf('      -> calibration and matches agree.\n');
    end
end
end


function d = sampson(F, p1, p2)
x1 = [p1 ones(size(p1,1),1)].';
x2 = [p2 ones(size(p2,1),1)].';
num = sum(x2 .* (F * x1), 1).';
Fx1  = F * x1;
Ftx2 = F.' * x2;
den = sqrt(Fx1(1,:).'.^2 + Fx1(2,:).'.^2 + Ftx2(1,:).'.^2 + Ftx2(2,:).'.^2);
d = abs(num) ./ max(den, eps);
end
