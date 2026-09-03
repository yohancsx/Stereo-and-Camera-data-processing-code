function [count, stats] = carve(P, M, g, yOrigin, opts)
%VH.CARVE Space carving: count how many silhouettes each voxel falls inside.
%
%   [count, stats] = vh.carve(P, M, g, yOrigin, opts)
%
%   P        3-by-4-by-nCams DLT matrices, already in camera order
%   M        nCams struct array from vh.loadMasks, already in camera order
%   g        .x .y .z grid vectors (world units, mm)
%   yOrigin  'bottom' or 'top'
%   opts     .wSign   nCams-by-1 expected sign of the homogeneous
%                     denominator for points in front of each camera. Get it
%                     from a point known to be in view (vh.crabVisualHull
%                     passes the triangulated centroid's signs). Pass [] to
%                     skip the cheirality test.
%            .chunk   voxels processed at a time (memory control)
%            .verbose
%
%   count    nx-by-ny-by-nz uint8, how many cameras saw each voxel
%   stats    per-camera hit counts and out-of-frame counts
%
%   VECTORISED. The original per-voxel loop did one matrix multiply per
%   voxel per camera; at 200^3 voxels and 4 cameras that is 32 million
%   iterations per frame. Here every voxel in a chunk is projected with a
%   handful of array operations, which is the same arithmetic about three
%   orders of magnitude faster.
%
%   Chunking keeps peak memory flat regardless of grid size: a 256^3 grid is
%   16.7 million voxels, and materialising X, Y, Z for all of them at once
%   would cost ~400 MB before any projection temporaries.

arguments
    P double
    M struct
    g struct
    yOrigin (1,:) char
    opts.wSign double = []
    opts.chunk (1,1) double = 2e6
    opts.verbose (1,1) logical = true
end

nCams = size(P, 3);
nx = numel(g.x);  ny = numel(g.y);  nz = numel(g.z);
N  = nx * ny * nz;

count = zeros(N, 1, 'uint8');
hits  = zeros(nCams, 1);
oof   = zeros(nCams, 1);
behind= zeros(nCams, 1);

if opts.verbose
    fprintf('vh.carve: %d x %d x %d = %s voxels, %d cameras\n', ...
        nx, ny, nz, addComma(N), nCams);
    t0 = tic;
end

for i0 = 1:opts.chunk:N
    i1  = min(N, i0 + opts.chunk - 1);
    lin = (i0:i1).';

    % Linear index -> grid subscripts -> world coordinates. ndgrid ordering:
    % element (ix,iy,iz) is at (x(ix), y(iy), z(iz)).
    iz = floor((lin - 1) / (nx*ny));
    rem_ = lin - 1 - iz*(nx*ny);
    iy = floor(rem_ / nx);
    ix = rem_ - iy*nx;
    XYZ = [g.x(ix+1).', g.y(iy+1).', g.z(iz+1).'];

    c = zeros(numel(lin), 1, 'uint8');

    for k = 1:nCams
        m = M(k);
        [col, row, w] = vh.project(P(:,:,k), XYZ, m.H, yOrigin);

        ok = isfinite(col) & isfinite(row);

        % Cheirality: DLT has no built-in notion of "in front", and points
        % behind the camera project to perfectly plausible pixels. The sign
        % of the homogeneous denominator separates them; which sign means
        % "in front" depends on how the coefficients were scaled, so it is
        % measured rather than assumed.
        if ~isempty(opts.wSign) && opts.wSign(k) ~= 0
            wOk = (w * opts.wSign(k)) > 0;
            behind(k) = behind(k) + nnz(ok & ~wOk);
            ok = ok & wOk;
        end

        cc = round(col);  rr = round(row);
        inb = ok & cc >= 1 & cc <= m.W & rr >= 1 & rr <= m.H;
        oof(k) = oof(k) + nnz(ok & ~inb);

        if any(inb)
            idx = (cc(inb) - 1) * m.H + rr(inb);      % sub2ind, inlined
            hit = m.mask(idx);
            c(inb) = c(inb) + uint8(hit);
            hits(k) = hits(k) + nnz(hit);
        end
    end

    count(lin) = c;
end

count = reshape(count, [nx ny nz]);

stats = struct('hits', hits, 'outOfFrame', oof, 'behindCamera', behind, ...
    'nVoxels', N, 'voxelVolume', voxVol(g));

if opts.verbose
    fprintf('  carved in %.2f s\n', toc(t0));
    fprintf('  %-4s %12s %14s %14s\n', 'cam', 'voxels hit', 'out of frame', 'behind cam');
    for k = 1:nCams
        fprintf('  %-4d %12s %14s %14s\n', k, addComma(hits(k)), ...
            addComma(oof(k)), addComma(behind(k)));
    end
    for k = 1:nCams
        if oof(k) > 0.5*N
            fprintf(['  [!] cam %d: over half the grid projects outside ' ...
                'the frame. The box may be badly placed.\n'], k);
        end
    end
end
end


function v = voxVol(g)
d = @(a) mean(diff(a(:)));
v = abs(d(g.x) * d(g.y) * d(g.z));
end


function s = addComma(n)
s = regexprep(sprintf('%d', round(n)), '\d{1,3}(?=(\d{3})+$)', '$&,');
end
