function stereoReport(pairsOut, camC, vol, cfg)
%VH.STEREOREPORT Figures for the stereo reconstruction.
%
%   fig 1  rectified pair with horizontal rules - corresponding features
%          must sit on the same rule if the epipolar geometry is right
%   fig 2  red/cyan anaglyph of the rectified pair
%   fig 3  disparity maps per dense method
%   fig 4  the 3-D point cloud, coloured by pair          (own window)
%   fig 5  the 3-D point cloud, coloured by image texture (own window)
%   fig 6  epipolar row-error histogram from unconstrained feature matches

nP = numel(pairsOut);
if nP == 0, return, end
cols = [0.85 0.33 0.10; 0.00 0.45 0.74; 0.47 0.67 0.19; 0.49 0.18 0.56];

%% ---- fig 1: rectified pairs with row rules -----------------------------
figure('Name','stereo 1 - rectified pairs','NumberTitle','off','Color','w', ...
       'Units','normalized','Position',[0.04 0.08 0.92 0.8]);
tl = tiledlayout(nP, 2, 'Padding','compact','TileSpacing','compact');
title(tl, ['Rectified pairs. A true correspondence must lie on the same ' ...
    'horizontal rule in both panels.'], 'FontWeight','bold');
for q = 1:nP
    S = pairsOut(q).rect;
    for s = 1:2
        nexttile;
        if s == 1, I = S.Irgb1; else, I = S.Irgb2; end
        imshow(I); hold on
        yl = round(linspace(1, size(I,1), 12));
        for y = yl(2:end-1)
            plot([1 size(I,2)], [y y], '-', 'Color', [1 1 0 0.35], 'LineWidth', 0.6);
        end
        title(sprintf('pair %d  (DLT %d)  view %d', q, ...
            pairsOut(q).idx(s), s), 'FontSize', 10);
    end
end

%% ---- fig 2: anaglyphs ---------------------------------------------------
figure('Name','stereo 2 - anaglyph','NumberTitle','off','Color','w', ...
       'Units','normalized','Position',[0.06 0.1 0.88 0.78]);
tl2 = tiledlayout(1, nP, 'Padding','compact','TileSpacing','compact');
title(tl2, ['Red/cyan overlay of the rectified pair. Vertical offset means ' ...
    'the epipolar geometry is off.'], 'FontWeight','bold');
for q = 1:nP
    S = pairsOut(q).rect;
    A = cat(3, im2uint8(S.I1), im2uint8(S.I2), im2uint8(S.I2));
    nexttile; imshow(A);
    title(sprintf('pair %d   search range [%d %d] px', q, S.dispRange), ...
        'FontSize', 10);
end

%% ---- fig 3: disparity maps ---------------------------------------------
haveD = false;
for q = 1:nP
    for mi = 1:numel(pairsOut(q).matches)
        if ~isempty(pairsOut(q).matches(mi).disparity), haveD = true; end
    end
end
if haveD
    figure('Name','stereo 3 - disparity','NumberTitle','off','Color','w', ...
           'Units','normalized','Position',[0.05 0.08 0.9 0.82]);
    nM = 0;
    for q = 1:nP
        nM = max(nM, sum(arrayfun(@(r) ~isempty(r.disparity), pairsOut(q).matches)));
    end
    tl3 = tiledlayout(nP, max(nM,1), 'Padding','compact','TileSpacing','compact');
    title(tl3, 'Disparity (px, rectified). Grey = no match found.', ...
        'FontWeight','bold');
    for q = 1:nP
        S = pairsOut(q).rect;
        for mi = 1:numel(pairsOut(q).matches)
            R = pairsOut(q).matches(mi);
            if isempty(R.disparity), continue, end
            nexttile;
            D = double(R.disparity);  D(~S.K1) = NaN;
            h = imagesc(D, 'AlphaData', ~isnan(D));
            set(h.Parent, 'Color', [0.85 0.85 0.85]);
            axis image off; colormap(gca, turbo); colorbar
            frac = nnz(isfinite(D) & S.K1) / max(nnz(S.K1),1);
            title(sprintf('pair %d - %s   %.0f%% of the animal matched', ...
                q, R.name, 100*frac), 'FontSize', 10);
        end
    end
end

%% ---- figs 4 and 5: the point clouds, one window each --------------------
% Separate windows rather than tiles: each cloud needs the whole window to
% be readable, and you want to rotate them independently.
f4 = figure('Name','stereo 4 - reconstruction, coloured by pair', ...
    'NumberTitle','off','Color','w','Units','normalized', ...
    'Position',[0.06 0.08 0.52 0.80]);
ax1 = axes(f4);  hold(ax1,'on'); grid(ax1,'on'); set(ax1,'Box','on');

f5 = figure('Name','stereo 5 - reconstruction, coloured by image', ...
    'NumberTitle','off','Color','w','Units','normalized', ...
    'Position',[0.42 0.08 0.52 0.80]);
ax2 = axes(f5);  hold(ax2,'on'); grid(ax2,'on'); set(ax2,'Box','on');

leg = {};
anyPts = false;
for q = 1:nP
    [~, best] = max(arrayfun(@(c) c.n, pairsOut(q).clouds));
    C = pairsOut(q).clouds(best);
    if C.n == 0, continue, end
    anyPts = true;
    scatter3(ax1, C.XYZ(:,1), C.XYZ(:,2), C.XYZ(:,3), 3, cols(q,:), 'filled');
    leg{end+1} = sprintf('pair %d (%s, n=%d)', q, ...
        pairsOut(q).matches(best).name, C.n);          %#ok<AGROW>
    if ~isempty(C.rgb)
        scatter3(ax2, C.XYZ(:,1), C.XYZ(:,2), C.XYZ(:,3), 3, ...
            double(C.rgb)/255, 'filled');
    else
        scatter3(ax2, C.XYZ(:,1), C.XYZ(:,2), C.XYZ(:,3), 3, cols(q,:), 'filled');
    end
end

% Frame on the animal, not on the cameras: they sit ~11 units away and would
% squash the cloud to a dot. Viewing directions are drawn as short stubs.
lo = vol.centre - vol.half;  hi = vol.centre + vol.half;
for q = 1:nP
    [~, best] = max(arrayfun(@(c) c.n, pairsOut(q).clouds));
    C = pairsOut(q).clouds(best);
    if C.n == 0, continue, end
    lo = min(lo, min(C.XYZ,[],1));  hi = max(hi, max(C.XYZ,[],1));
end
padv = 0.12 * max(hi - lo);
lo = lo - padv;  hi = hi + padv;

for ax = [ax1 ax2]
    drawBox(ax, vol.centre - vol.half, vol.centre + vol.half);
    for k = 1:size(camC,2)
        v = camC(:,k).' - vol.centre;  v = v / norm(v);
        s = 0.45 * max(hi - lo);
        plot3(ax, vol.centre(1)+[0 v(1)]*s, vol.centre(2)+[0 v(2)]*s, ...
                  vol.centre(3)+[0 v(3)]*s, '-', 'Color', [0.55 0.55 0.55]);
        text(ax, vol.centre(1)+v(1)*s, vol.centre(2)+v(2)*s, ...
                 vol.centre(3)+v(3)*s, sprintf(' cam %d',k), 'FontSize', 8, ...
                 'Color', [0.35 0.35 0.35]);
    end
    axis(ax,'equal'); axis(ax,'vis3d'); view(ax, 40, 20);
    xlim(ax,[lo(1) hi(1)]); ylim(ax,[lo(2) hi(2)]); zlim(ax,[lo(3) hi(3)]);
    xlabel(ax, sprintf('X (%s)', cfg.units));
    ylabel(ax, sprintf('Y (%s)', cfg.units));
    zlabel(ax, sprintf('Z (%s)', cfg.units));
end
if ~isempty(leg)
    legend(ax1, leg, 'Location','northeast', 'Interpreter','none');
end
title(ax1, 'Stereo reconstruction - coloured by pair', 'FontWeight','bold');
title(ax2, 'Stereo reconstruction - coloured by image', 'FontWeight','bold');
if ~anyPts
    title(ax1, 'NO POINTS SURVIVED', 'FontWeight','bold','Color','r');
    title(ax2, 'NO POINTS SURVIVED', 'FontWeight','bold','Color','r');
end

%% ---- fig 6: epipolar error ---------------------------------------------
haveE = false;
for q = 1:nP
    for mi = 1:numel(pairsOut(q).matches)
        if isfield(pairsOut(q).matches(mi),'rowErrAll') && ...
                ~isempty(pairsOut(q).matches(mi).rowErrAll), haveE = true; end
    end
end
if haveE
    figure('Name','stereo 6 - epipolar agreement','NumberTitle','off', ...
           'Color','w','Position',[120 90 900 420]);
    hold on; grid on
    lg = {};
    for q = 1:nP
        for mi = 1:numel(pairsOut(q).matches)
            R = pairsOut(q).matches(mi);
            if ~isfield(R,'rowErrAll') || isempty(R.rowErrAll), continue, end
            histogram(R.rowErrAll, 0:2:80, 'FaceColor', cols(q,:), ...
                'EdgeColor','none','FaceAlpha',0.65);
            lg{end+1} = sprintf('pair %d (n=%d, median %.1f px)', q, ...
                numel(R.rowErrAll), median(R.rowErrAll));   %#ok<AGROW>
        end
    end
    xline(3, 'k--', 'LineWidth', 1.4);
    xlabel('|y_1 - y_2| after rectification (px)');
    ylabel('feature matches');
    title(['Vertical disagreement of unconstrained feature matches. ' ...
        'Perfect calibration would pile up at 0.']);
    if ~isempty(lg), legend([lg {'epipolar tolerance'}], 'Location','northeast'); end
end
end


function drawBox(ax, lo, hi)
x = [lo(1) hi(1)];  y = [lo(2) hi(2)];  z = [lo(3) hi(3)];
c = [x([1 2 2 1 1 1 2 2 1 1 2 2 2 2 1 1]).', ...
     y([1 1 2 2 1 1 1 2 2 1 1 1 2 2 2 2]).', ...
     z([1 1 1 1 1 2 2 2 2 2 2 1 1 2 2 1]).'];
plot3(ax, c(:,1), c(:,2), c(:,3), '-', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8);
end



