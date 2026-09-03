function uv = imageToDLT(colrow, imgH, yOrigin)
%VH.IMAGETODLT Convert MATLAB image indices to DLT (u,v) coordinates.
%
%   uv = vh.imageToDLT([col row], imgH, yOrigin)
%
%   The exact inverse of the flip applied in vh.project, so a point sent
%   through both comes back unchanged. Keeping the two in matching files is
%   the whole point - a flip applied in one place and not the other is the
%   classic way to get a plausible but wrong reconstruction.

u = colrow(:,1);
switch lower(yOrigin)
    case 'bottom', v = imgH + 1 - colrow(:,2);
    case 'top',    v = colrow(:,2);
    otherwise
        error('vh:imageToDLT:yOrigin', ...
            'yOrigin must be ''bottom'' or ''top'', got ''%s''.', yOrigin);
end
uv = [u v];
end
