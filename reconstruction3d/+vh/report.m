function V = report(P, M, H, g, yOrigin, opts)
%VH.REPORT Validation figures for a carved hull.
%
%   V = vh.report(P, M, H, g, yOrigin, opts)
%
%   Produces
%     fig 1  per-camera reprojection overlay: the input mask against the
%            silhouette of the finished hull projected back into that view
%     fig 2  3-D diagnostic: hull, voxel box, camera centres and view rays
%     fig 3  raw vs undistorted mask, per camera
%
%   V  .coverage  fraction of each mask covered by the hull's reprojection
%      .spill     fraction of each reprojection falling outside the mask
%      .iou
%
%   HOW TO READ THE COVERAGE NUMBERS
%   A visual hull's silhouette in a carving camera is contained in that
%   camera's mask by construction, so spill should be near zero (what little
%   there is comes from voxel discretisation and the closing operation).
%   Coverage should be high - typically >0.95. Low coverage in ONE camera
%   points at that camera's calibration or its mask; low coverage in ALL of
%   them usually means the voxel box is clipping the object.

arguments
    P double
    M struct
    H struct
    g struct
    yOrigin (1,:) char
    opts.dispMaxDim (1,1) double = 900
    opts.units (1,:) char = 'mm'
    opts.cameraCentres double = []
end

nCams = size(P, 3);
V = struct('coverage', zeros(nCams,1), 'spill', zeros(nCams,1), ...
           'iou', zeros(nCams,1));

if H.nOccupied == 0
    warning('vh:report:empty', 'Nothing to report - the hull is empty.');
    return
end

% Occupied voxel centres, once.
[ix, iy, iz] = ind2sub(size(H.occ), find(H.occ));
Pts = [g.x(ix).', g.y(iy).', g.z(iz).'];

%% ---------------------------------------------- fig 1: reprojection check

f1 = figure('Name','vh - reprojection check','NumberTitle','off', ...
            'Color','w','Units','normalized','Position',[0.04 0.08 0.92 0.8]);
tl = tiledlayout(f1, 'flow', 'Padding','compact', 'TileSpacing','compact');
title(tl, ['Hull reprojected into each camera   ' ...
    'green = input mask, red = hull, yellow = both'], 'FontWeight','bold');

for k = 1:nCams
    m = M(k);
    [col, row] = vh.project(P(:,:,k), Pts, m.H, yOrigin);
    cc = round(col);  rr = round(row);
    inb = cc >= 1 & cc <= m.W & rr >= 1 & rr <= m.H;

    proj = false(m.H, m.W);
    if any(inb)
        proj((cc(inb)-1)*m.H + rr(inb)) = true;
    end
    % Voxels project to scattered pixels; close the gaps so the silhouette
    % is comparable with the mask as a region.
    proj = imclose(proj, strel('disk', 2));
    proj = imfill(proj, 'holes');

    inter = nnz(proj & m.mask);
    V.coverage(k) = inter / max(nnz(m.mask), 1);
    V.spill(k)    = nnz(proj & ~m.mask) / max(nnz(proj), 1);
    V.iou(k)      = inter / max(nnz(proj | m.mask), 1);

    s = min(1, opts.dispMaxDim / max(m.H, m.W));
    md = imresize(m.mask, s, 'nearest');
    pd = imresize(proj,   s, 'nearest');

    rgb = zeros([size(md) 3], 'uint8');
    rgb(:,:,1) = uint8(pd) * 235;                 % hull    -> red
    rgb(:,:,2) = uint8(md) * 235;                 % mask    -> green
    % both -> yellow, automatically

    nexttile;
    imshow(rgb);
    title(sprintf('cam %d   coverage %.3f   spill %.3f   IoU %.3f', ...
        k, V.coverage(k), V.spill(k), V.iou(k)), 'FontSize', 10);
end

fprintf('\nvh.report: silhouette agreement\n');
fprintf('  %-4s %10s %10s %10s\n', 'cam', 'coverage', 'spill', 'IoU');
for k = 1:nCams
    flag = '';
    if V.coverage(k) < 0.9, flag = '   <- low, check this camera'; end
    fprintf('  %-4d %10.4f %10.4f %10.4f%s\n', ...
        k, V.coverage(k), V.spill(k), V.iou(k), flag);
end
if all(V.coverage < 0.9)
    fprintf(['  [!] every camera is low - the voxel box is probably ' ...
             'clipping the object. Increase boxPadFactor.\n']);
end

%% ------------------------------------------------ fig 2: 3-D diagnostic

figure('Name','vh - 3D diagnostic','NumberTitle','off','Color','w', ...
       'Position',[120 80 1000 800]);
ax = axes; hold(ax,'on'); grid(ax,'on'); box(ax,'on');

if ~isempty(H.faces)
    patch(ax, 'Faces', H.faces, 'Vertices', H.vertices, ...
        'FaceColor', [0.85 0.42 0.22], 'EdgeColor', 'none', ...
        'FaceAlpha', 0.92, 'FaceLighting', 'gouraud', ...
        'AmbientStrength', 0.45, 'DiffuseStrength', 0.75);
end

% Voxel box - the thing you adjust with objectSizeMM / boxPadFactor.
drawBox(ax, [g.x(1) g.y(1) g.z(1)], [g.x(end) g.y(end) g.z(end)], ...
        [0.15 0.35 0.75], 1.4, '-');
% Tight bounding box of the occupied voxels.
drawBox(ax, H.bbox(1,:), H.bbox(2,:), [0.2 0.6 0.2], 1.1, '--');

plot3(ax, H.centroid(1), H.centroid(2), H.centroid(3), 'k+', ...
      'MarkerSize', 12, 'LineWidth', 1.5);

% Principal axes, scaled to the hull's own extent.
cols = [0.85 0.1 0.1; 0.1 0.5 0.1; 0.1 0.1 0.85];
for a = 1:3
    d = H.principalAxes(:,a).' * H.principalExtent(a)/2;
    plot3(ax, H.centroid(1)+[-d(1) d(1)], H.centroid(2)+[-d(2) d(2)], ...
              H.centroid(3)+[-d(3) d(3)], '-', 'Color', cols(a,:), ...
              'LineWidth', 2);
end

if ~isempty(opts.cameraCentres)
    C = opts.cameraCentres;
    for k = 1:size(C,2)
        if ~all(isfinite(C(:,k))), continue, end
        plot3(ax, C(1,k), C(2,k), C(3,k), 'ks', 'MarkerSize', 9, ...
            'MarkerFaceColor', [0.3 0.3 0.3]);
        text(ax, C(1,k), C(2,k), C(3,k), sprintf('  cam %d', k), ...
            'FontSize', 9);
        plot3(ax, [C(1,k) H.centroid(1)], [C(2,k) H.centroid(2)], ...
                  [C(3,k) H.centroid(3)], ':', 'Color', [0.5 0.5 0.5]);
    end
end

axis(ax, 'equal'); axis(ax, 'vis3d');
xlabel(ax, sprintf('X (%s)', opts.units));
ylabel(ax, sprintf('Y (%s)', opts.units));
zlabel(ax, sprintf('Z (%s)', opts.units));
view(ax, 35, 22);
camlight(ax, 'headlight'); camlight(ax, 'left');
title(ax, sprintf(['hull %.0f %s^3   |   %s voxels at %.3f %s   |   ' ...
    'extents %.1f x %.1f x %.1f %s'], H.volumeVoxel, opts.units, ...
    addComma(H.nOccupied), H.voxelSize(1), opts.units, ...
    H.principalExtent, opts.units));
legend(ax, {'hull','voxel box','occupied bbox','centroid'}, ...
    'Location','northeastoutside');

%% -------------------------------------- fig 3: undistortion sanity check

if any(~strcmp({M.kind}, 'none'))
    figure('Name','vh - undistortion check','NumberTitle','off', ...
           'Color','w','Units','normalized','Position',[0.06 0.1 0.88 0.76]);
    tl3 = tiledlayout(2, nCams, 'Padding','compact', 'TileSpacing','compact');
    title(tl3, 'top: mask as exported (distorted)   bottom: undistorted', ...
        'FontWeight','bold');
    for k = 1:nCams
        s = min(1, opts.dispMaxDim / max(M(k).H0, M(k).W0));
        nexttile(k);
        imshow(imresize(M(k).raw, s, 'nearest'));
        title(sprintf('cam %d raw', k), 'FontSize', 9);
        nexttile(nCams + k);
        imshow(imresize(M(k).mask, s, 'nearest'));
        title(sprintf('cam %d undistorted (%s)', k, M(k).kind), 'FontSize', 9);
    end
end
end


%% ------------------------------------------------------------------ helpers

function drawBox(ax, lo, hi, colr, lw, ls)
x = [lo(1) hi(1)];  y = [lo(2) hi(2)];  z = [lo(3) hi(3)];
c = [x([1 2 2 1 1 1 2 2 1 1 2 2 2 2 1 1]).', ...
     y([1 1 2 2 1 1 1 2 2 1 1 1 2 2 2 2]).', ...
     z([1 1 1 1 1 2 2 2 2 2 2 1 1 2 2 1]).'];
plot3(ax, c(:,1), c(:,2), c(:,3), ls, 'Color', colr, 'LineWidth', lw);
end


function s = addComma(n)
s = regexprep(sprintf('%d', round(n)), '\d{1,3}(?=(\d{3})+$)', '$&,');
end
