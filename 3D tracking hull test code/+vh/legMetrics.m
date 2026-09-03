function [T, frame] = legMetrics(legs, opts)
%VH.LEGMETRICS Leg geometry expressed in a body-fixed frame.
%
%   [T, frame] = vh.legMetrics(legs)
%
%   legs   struct array from crabLegAnnotator: .name .XYZ (nPts-by-3)
%          The leg named 'body' defines the long axis.
%
%   T      table, one row per leg:
%            nPts        landmarks triangulated
%            length      polyline length, base to tip (world units)
%            span        straight-line base-to-tip distance
%            straight    span/length, 1 = straight leg, <1 = bent
%            elevation   angle out of the body's transverse plane, +ve
%                        toward the head end of the body axis (deg)
%            azimuth     angle around the body axis (deg)
%            angleToAxis angle between the leg vector and the body axis
%            baseAlong   base position along the body axis from its origin
%            baseRadial  base distance from the body axis
%
%   frame  .origin .e1 .e2 .e3 .valid .note
%
%   THE BODY FRAME
%   e1 is the body axis, from the first digitised body point to the last.
%   That alone fixes elevation and angleToAxis but leaves azimuth free to
%   spin about the axis, so e2 is pinned to the radial direction of the
%   FIRST digitised leg's base: azimuth is then measured round from that
%   leg, which is well defined and anatomically readable. frame.refLeg
%   names it.
%
%   Angles are frame-relative and therefore unaffected by the world scale,
%   which matters here because the DLT's units are wand-lengths rather than
%   mm. Lengths carry whatever unit the calibration was solved in.

arguments
    legs struct
    opts.bodyName (1,:) char = 'body'
end

frame = struct('origin', [NaN NaN NaN], 'e1', [], 'e2', [], 'e3', [], ...
               'valid', false, 'note', '', 'refLeg', '');

names = {legs.name};
bi = find(strcmpi(names, opts.bodyName), 1);

% ---- body axis ----------------------------------------------------------
if isempty(bi)
    frame.note = sprintf('no leg named "%s"', opts.bodyName);
else
    B = legs(bi).XYZ;
    B = B(all(isfinite(B),2), :);
    if size(B,1) < 2
        frame.note = 'the body needs at least 2 triangulated landmarks';
    else
        frame.origin = B(1,:);
        e1 = B(end,:) - B(1,:);
        if norm(e1) < eps
            frame.note = 'body landmarks are coincident';
        else
            frame.e1 = e1 / norm(e1);
            frame.valid = true;
        end
    end
end

% ---- transverse reference from the leg bases ----------------------------
legIdx = setdiff(1:numel(legs), bi);
bases = nan(numel(legIdx), 3);
for i = 1:numel(legIdx)
    X = legs(legIdx(i)).XYZ;
    g = find(all(isfinite(X),2), 1, 'first');
    if ~isempty(g), bases(i,:) = X(g,:); end
end
haveBase = find(all(isfinite(bases),2));

if frame.valid
    % Azimuth needs a zero direction perpendicular to the body axis. The
    % radial direction of the FIRST digitised leg's base is the natural
    % choice: always well defined, and anatomically interpretable as
    % "azimuth is measured round from this leg".
    %
    % Note a plane fitted to the leg bases would NOT work here: on a crab
    % those bases sit around the carapace rim, so their plane normal is
    % essentially the body axis itself and orthogonalising it against e1
    % leaves nothing.
    e2 = [];
    if ~isempty(haveBase)
        refI = haveBase(1);
        r = bases(refI,:) - frame.origin;
        r = r - dot(r, frame.e1)*frame.e1;
        if norm(r) > 1e-9
            e2 = r / norm(r);
            frame.refLeg = legs(legIdx(refI)).name;
            frame.note = sprintf('azimuth 0 = radial direction of "%s"', ...
                frame.refLeg);
        end
    end
    if isempty(e2)
        frame.note = 'azimuth is arbitrary (no leg base off the body axis)';
        a = [1 0 0];
        if abs(dot(a, frame.e1)) > 0.9, a = [0 1 0]; end
        e2 = a - dot(a, frame.e1)*frame.e1;
        e2 = e2 / norm(e2);
    end
    frame.e2 = e2;
    frame.e3 = cross(frame.e1, e2);
end

% ---- per-leg numbers ----------------------------------------------------
n = numel(legIdx);
nm = cell(n,1);
[nPts, len, span, straight, elev, azim, ang, bAlong, bRad] = deal(nan(n,1));

for i = 1:n
    k = legIdx(i);
    nm{i} = legs(k).name;
    X = legs(k).XYZ;
    X = X(all(isfinite(X),2), :);
    nPts(i) = size(X,1);
    if nPts(i) < 2, continue, end

    d = diff(X, 1, 1);
    len(i)  = sum(vecnorm(d, 2, 2));
    v = X(end,:) - X(1,:);
    span(i) = norm(v);
    if len(i) > 0, straight(i) = span(i) / len(i); end

    if ~frame.valid || span(i) < eps, continue, end

    vf = [dot(v, frame.e1), dot(v, frame.e2), dot(v, frame.e3)];
    elev(i) = asind(max(-1, min(1, vf(1)/span(i))));
    azim(i) = atan2d(vf(3), vf(2));
    ang(i)  = acosd(max(-1, min(1, vf(1)/span(i))));

    b = X(1,:) - frame.origin;
    bAlong(i) = dot(b, frame.e1);
    bRad(i)   = norm(b - bAlong(i)*frame.e1);
end

T = table(nm, nPts, len, span, straight, elev, azim, ang, bAlong, bRad, ...
    'VariableNames', {'leg','nPts','length','span','straight', ...
                      'elevation','azimuth','angleToAxis','baseAlong','baseRadial'});
end

