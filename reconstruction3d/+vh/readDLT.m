function [P, L, C] = readDLT(csvPath)
%VH.READDLT Read DLT-11 coefficients into 3-by-4 projection matrices.
%
%   [P, L, C] = vh.readDLT(csvPath)
%
%   csvPath   CSV of DLT coefficients, 11 rows by nCams columns (the
%             easyWand / DLTdv layout). A 12th row equal to 1 is tolerated,
%             as is the transposed layout (with a warning).
%
%   P         3-by-4-by-nCams projection matrices
%   L         11-by-nCams raw coefficients
%   C         3-by-nCams camera centres in world units
%
%   The DLT-11 model is
%       u = (L1*X + L2*Y + L3*Z + L4) / (L9*X + L10*Y + L11*Z + 1)
%       v = (L5*X + L6*Y + L7*Z + L8) / (L9*X + L10*Y + L11*Z + 1)
%   so the matrix must be filled ROW-major:
%       P = [L1 L2 L3 L4; L5 L6 L7 L8; L9 L10 L11 1]
%
%   Note: reshape([L;1],[3 4]) fills COLUMN-major and silently produces the
%   transposed matrix. That is the bug this function exists to avoid.

arguments
    csvPath (1,:) char
end

assert(isfile(csvPath), 'vh:readDLT:noFile', 'DLT file not found: %s', csvPath);

M = readmatrix(csvPath);
assert(~isempty(M), 'vh:readDLT:empty', 'No numeric data in %s', csvPath);

% Drop rows/columns that are entirely NaN (headers, index columns, trailing
% commas from a spreadsheet export).
M = M(~all(isnan(M), 2), :);
M = M(:, ~all(isnan(M), 1));

[nr, nc] = size(M);

if nr == 12 && all(abs(M(12,:) - 1) < 1e-6)
    M = M(1:11, :);  nr = 11;
elseif nc == 12 && all(abs(M(:,12) - 1) < 1e-6)
    M = M(:, 1:11);  nc = 11;
end

if nr == 11
    L = M;
elseif nc == 11
    warning('vh:readDLT:transposed', ...
        ['%s is %d-by-11; expected 11-by-nCams. Transposing - check the ' ...
         'camera order carefully.'], csvPath, nr);
    L = M.';
else
    error('vh:readDLT:badShape', ...
        ['%s is %d-by-%d. Expected 11 rows (coefficients) by nCams ' ...
         'columns.'], csvPath, nr, nc);
end

nCams = size(L, 2);
assert(nCams >= 2, 'vh:readDLT:tooFewCams', ...
    'Only %d camera(s) of coefficients found.', nCams);
assert(~any(isnan(L(:))), 'vh:readDLT:nan', ...
    'DLT coefficients contain NaN. Check %s for stray text or blanks.', csvPath);

P = zeros(3, 4, nCams);
C = zeros(3, nCams);
for i = 1:nCams
    l = L(:, i);
    P(:,:,i) = [l(1)  l(2)  l(3)  l(4)
                l(5)  l(6)  l(7)  l(8)
                l(9)  l(10) l(11) 1   ];

    if norm(l(9:11)) < eps
        warning('vh:readDLT:degenerate', ...
            'Camera %d has L9..L11 all zero - the coefficients look wrong.', i);
    end

    % The camera centre satisfies P*[C;1] = 0.
    A = P(:,1:3,i);
    if rcond(A) < 1e-12
        warning('vh:readDLT:singular', ...
            'Camera %d projection matrix is near-singular.', i);
        C(:,i) = NaN;
    else
        C(:,i) = -A \ P(:,4,i);
    end
end

fprintf('vh.readDLT: %d camera(s) from %s\n', nCams, csvPath);
end
