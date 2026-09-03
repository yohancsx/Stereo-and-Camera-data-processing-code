function H = buildMesh(count, g, minCams, opts)
%VH.BUILDMESH Turn an occupancy count volume into a surface and measurements.
%
%   H = vh.buildMesh(count, g, minCams, opts)
%
%   count    nx-by-ny-by-nz from vh.carve
%   g        .x .y .z grid vectors (mm)
%   minCams  a voxel is occupied when count >= minCams
%   opts     .smooth       smooth the volume before isosurfacing (cosmetic)
%            .reduceFaces  0 to keep all faces, else a fraction for reducepatch
%
%   H  .occ .faces .vertices .volumeVoxel .volumeMesh .centroid
%      .principalAxes .principalExtent .bbox .voxelSize .nOccupied
%
%   Volume is reported from the VOXEL COUNT, not the mesh, so that turning
%   smoothing on or off does not change the number. The mesh volume is
%   computed separately as a cross-check; large disagreement means the
%   surface is open (the hull ran into the edge of the box).
%
%   Units are whatever the wand length was in - mm here, so volumes are mm^3.

arguments
    count
    g struct
    minCams (1,1) double
    opts.smooth (1,1) logical = true
    opts.reduceFaces (1,1) double = 0
end

occ = count >= minCams;
H.occ = occ;
H.nOccupied = nnz(occ);

dx = mean(diff(g.x));  dy = mean(diff(g.y));  dz = mean(diff(g.z));
H.voxelSize = [dx dy dz];
H.volumeVoxel = H.nOccupied * abs(dx*dy*dz);

if H.nOccupied == 0
    warning('vh:buildMesh:empty', ...
        ['No voxel was seen by %d cameras. Either the box misses the ' ...
         'object, the camera pairing is wrong, or one mask is bad. Try ' ...
         'minCams = %d.'], minCams, max(1, minCams-1));
    [H.faces, H.vertices] = deal([]);
    [H.volumeMesh, H.centroid] = deal(NaN);
    H.principalAxes = nan(3); H.principalExtent = nan(1,3); H.bbox = nan(2,3);
    return
end

% ---- centroid, principal axes, bounding box -----------------------------
[ix, iy, iz] = ind2sub(size(occ), find(occ));
Pts = [g.x(ix).', g.y(iy).', g.z(iz).'];
H.centroid = mean(Pts, 1);
H.bbox = [min(Pts,[],1); max(Pts,[],1)];

Cv = cov(Pts);
[V, D] = eig(Cv);
[~, ord] = sort(diag(D), 'descend');
H.principalAxes = V(:, ord);                      % columns, longest first
proj = (Pts - H.centroid) * H.principalAxes;
H.principalExtent = max(proj,[],1) - min(proj,[],1);

% ---- surface ------------------------------------------------------------
% Pad with a zero shell so a hull touching the box edge still closes.
V3 = double(count);
if opts.smooth, V3 = smooth3(V3, 'box', 3); end
V3 = padarray(V3, [1 1 1], 0, 'both');
gxp = [g.x(1)-dx, g.x(:).', g.x(end)+dx];
gyp = [g.y(1)-dy, g.y(:).', g.y(end)+dy];
gzp = [g.z(1)-dz, g.z(:).', g.z(end)+dz];

% isosurface expects meshgrid ordering; the volume is ndgrid ordered.
fv = isosurface(gxp, gyp, gzp, permute(V3, [2 1 3]), minCams - 0.5);

if opts.reduceFaces > 0 && opts.reduceFaces < 1 && ~isempty(fv.faces)
    fv = reducepatch(fv, opts.reduceFaces);
end
H.faces = fv.faces;
H.vertices = fv.vertices;

% ---- mesh volume, as a cross-check on closure ---------------------------
H.volumeMesh = meshVolume(fv);
if isfinite(H.volumeMesh) && H.volumeVoxel > 0
    r = H.volumeMesh / H.volumeVoxel;
    if r < 0.5 || r > 1.6
        warning('vh:buildMesh:openSurface', ...
            ['Mesh volume is %.2fx the voxel volume. The surface is ' ...
             'probably open - the hull is running into the edge of the ' ...
             'voxel box. Increase boxPadFactor.'], r);
    end
end
end


function V = meshVolume(fv)
%MESHVOLUME Signed volume by the divergence theorem over the triangles.
V = NaN;
if isempty(fv.faces), return, end
v1 = fv.vertices(fv.faces(:,1), :);
v2 = fv.vertices(fv.faces(:,2), :);
v3 = fv.vertices(fv.faces(:,3), :);
V = abs(sum(dot(v1, cross(v2, v3, 2), 2)) / 6);
end
