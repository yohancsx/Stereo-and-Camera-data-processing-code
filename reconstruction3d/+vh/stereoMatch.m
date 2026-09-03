function R = stereoMatch(S, method, opts)
%VH.STEREOMATCH Find correspondences in a rectified pair.
%
%   R = vh.stereoMatch(S, method, opts)
%
%   S       output of vh.rectifyPair
%   method  'sgm' | 'bm' | 'features'
%
%   R  .name .p1 .p2   n-by-2 matched points in RECTIFIED image coordinates
%      .n              number of matches
%      .disparity      the disparity map, for the dense methods ([] otherwise)
%      .rowErr         median |y1 - y2| for 'features' (0 by construction
%                      for the dense methods, which only search along rows)
%
%   Dense matching is restricted to the silhouette and preceded by local
%   contrast equalisation - underwater frames are flat, and a block matcher
%   keys entirely off local intensity variation.

arguments
    S struct
    method (1,:) char
    opts.subsample (1,1) double = 2      % keep every Nth pixel of a dense map
    opts.uniqueness (1,1) double = 5
    opts.blockSize (1,1) double = 15
    opts.rowTolPx (1,1) double = 4       % epipolar band for 'features'
    opts.lrCheck (1,1) logical = true    % left-right consistency
    opts.lrTolPx (1,1) double = 1.5
    opts.verbose (1,1) logical = true
end

I1 = prep(S.I1, S.K1);
I2 = prep(S.I2, S.K2);

% Every method returns the same fields, so the results concatenate.
R = struct('name', method, 'p1', zeros(0,2), 'p2', zeros(0,2), 'n', 0, ...
           'disparity', [], 'rowErr', NaN, 'note', '', ...
           'rowErrAll', zeros(0,1), 'nBeforeEpipolar', 0, 'lrRejected', 0, ...
           'q1All', zeros(0,2), 'q2All', zeros(0,2));

switch lower(method)

    case {'sgm', 'bm'}
        if strcmpi(method, 'sgm')
            D = disparitySGM(I1, I2, 'DisparityRange', S.dispRange, ...
                'UniquenessThreshold', opts.uniqueness);
        else
            D = disparityBM(I1, I2, 'DisparityRange', S.dispRange, ...
                'BlockSize', opts.blockSize, ...
                'UniquenessThreshold', opts.uniqueness, ...
                'ContrastThreshold', 0.3, 'DistanceThreshold', []);
        end
        R.disparity = D;

        % Left-right consistency. For rectified stereo the reprojection
        % residual is NOT a quality measure - the match is forced onto the
        % epipolar line, so the two rays intersect almost exactly whether or
        % not the match is correct. Matching both ways and demanding the two
        % answers agree is the check that actually carries information.
        lrBad = false(size(D));
        if opts.lrCheck
            rev = [-S.dispRange(2) -S.dispRange(1)];
            if strcmpi(method,'sgm')
                D2 = disparitySGM(I2, I1, 'DisparityRange', rev, ...
                    'UniquenessThreshold', opts.uniqueness);
            else
                D2 = disparityBM(I2, I1, 'DisparityRange', rev, ...
                    'BlockSize', opts.blockSize, ...
                    'UniquenessThreshold', opts.uniqueness, ...
                    'ContrastThreshold', 0.3, 'DistanceThreshold', []);
            end
            [ccA, rrA] = meshgrid(1:size(D,2), 1:size(D,1));
            xb = round(ccA - double(D));
            okb = isfinite(D) & xb >= 1 & xb <= size(D,2);
            back = nan(size(D));
            back(okb) = D2(sub2ind(size(D2), rrA(okb), xb(okb)));
            lrBad = ~(abs(back + double(D)) <= opts.lrTolPx);
            R.lrRejected = nnz(lrBad & isfinite(D) & S.K1);
        end

        valid = isfinite(D) & S.K1 & ~lrBad;
        % Drop matches whose partner falls outside the other silhouette.
        [cc, rr] = meshgrid(1:size(D,2), 1:size(D,1));
        c2 = cc - double(D);
        inb = valid & c2 >= 1 & c2 <= size(D,2);
        idx2 = sub2ind(size(S.K2), rr(inb), round(c2(inb)));
        keep = false(size(valid));
        keep(inb) = S.K2(idx2);

        [ri, ci] = find(keep);
        if opts.subsample > 1
            sel = mod(ri, opts.subsample) == 0 & mod(ci, opts.subsample) == 0;
            ri = ri(sel);  ci = ci(sel);
        end
        dsel = double(D(sub2ind(size(D), ri, ci)));
        R.p1 = [ci ri];
        R.p2 = [ci - dsel, ri];
        R.rowErr = 0;               % dense matching searches along rows only

    case 'features'
        % Underwater texture is fine-grained and low contrast, so pool
        % several detectors rather than relying on one. Descriptors are not
        % comparable across detectors, so each is matched on its own and
        % the resulting point pairs are concatenated.
        q1 = zeros(0,2);  q2 = zeros(0,2);  nDet = 0;
        dets = {@(I) detectKAZEFeatures(I, 'Threshold', 1e-4), ...
                @(I) detectSURFFeatures(I, 'MetricThreshold', 100), ...
                @(I) detectBRISKFeatures(I, 'MinContrast', 0.05)};
        for dI = 1:numel(dets)
            try
                f1 = dets{dI}(I1);  f2 = dets{dI}(I2);
            catch
                continue
            end
            f1 = f1(onMask(f1.Location, S.K1));
            f2 = f2(onMask(f2.Location, S.K2));
            if f1.Count < 4 || f2.Count < 4, continue, end
            [g1, v1] = extractFeatures(I1, f1);
            [g2, v2] = extractFeatures(I2, f2);
            pr = matchFeatures(g1, g2, 'MaxRatio', 0.8, 'Unique', true);
            if isempty(pr), continue, end
            q1 = [q1; v1.Location(pr(:,1), :)];        %#ok<AGROW>
            q2 = [q2; v2.Location(pr(:,2), :)];        %#ok<AGROW>
            nDet = nDet + 1;
        end
        if isempty(q1)
            R.note = 'no feature matches from any detector';
            return
        end
        R.note = sprintf('%d detector(s) contributed', nDet);

        % In a correctly rectified pair a true match sits on the same row.
        % Measure that BEFORE filtering - it is the calibration diagnostic.
        R.rowErrAll = abs(q1(:,2) - q2(:,2));
        good = R.rowErrAll <= opts.rowTolPx;
        R.p1 = q1(good,:);  R.p2 = q2(good,:);
        R.rowErr = median(R.rowErrAll);
        R.nBeforeEpipolar = size(q1,1);
        R.q1All = q1;  R.q2All = q2;      % unfiltered, for the epipolar audit

    otherwise
        error('vh:stereoMatch:method', 'Unknown method ''%s''.', method);
end

R.n = size(R.p1, 1);

if opts.verbose
    fprintf('    %-9s %7d matches', method, R.n);
    if strcmpi(method,'features') && isfield(R,'nBeforeEpipolar')
        fprintf('   (%d before the epipolar filter, median row error %.1f px)', ...
            R.nBeforeEpipolar, R.rowErr);
    end
    if ~isempty(R.note), fprintf('   [%s]', R.note); end
    fprintf('\n');
end
end


function J = prep(I, K)
%PREP Local contrast equalisation, confined to the silhouette.
J = I;
if any(K(:))
    J = adapthisteq(J, 'NumTiles', [12 12], 'ClipLimit', 0.02);
end
J(~K) = 0;
end


function tf = onMask(loc, K)
c = round(loc(:,1));  r = round(loc(:,2));
tf = c >= 1 & c <= size(K,2) & r >= 1 & r <= size(K,1);
idx = sub2ind(size(K), r(tf), c(tf));
v = false(size(tf));  v(tf) = K(idx);
tf = v;
end


