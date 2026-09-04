function v = probeChannel(rgbIn, name)
%PROBECHANNEL Evaluate a named colour-separation channel.
%
%   V = PROBECHANNEL(IMG, NAME) where IMG is an H-by-W-by-3 image returns an
%   H-by-W double matrix.
%
%   V = PROBECHANNEL(PX, NAME) where PX is an N-by-3 list of RGB triplets
%   returns an N-by-1 double vector.
%
%   Input may be uint8/uint16/double. Everything is evaluated in double
%   0-255 units so thresholds measured on one image type transfer to another.
%
%   Supported NAME values:
%       'RmG'    R - G          red-dominant targets (e.g. an orange marker)
%       'BmG'    B - G          blue-dominant targets (blue ball)
%       'RmB'    R - B
%       'GmR'    G - R          green-dominant targets (background water)
%       'rgRed'  255*(R-G)/(R+G+B)   illumination-normalised redness
%       'rgBlue' 255*(B-G)/(R+G+B)   illumination-normalised blueness
%       'Lab_a'  CIELAB a*      green(-) to red(+)
%       'Lab_b'  CIELAB b*      blue(-) to yellow(+)
%       'Lab_L'  CIELAB L*      lightness
%       'gray'   rec.601 luma
%
%   This function is deliberately kept separate from colourProbe.m so
%   that the batch segmentation code can call it with the channel name saved
%   in the probe .mat file and reproduce the exact same numbers.
%
%   See also COLOURPROBE.

arguments
    rgbIn
    name (1,:) char
end

isImage = (ndims(rgbIn) == 3);

% Work as an N-by-3 double list in 0-255 units.
if isImage
    [h, w, c] = size(rgbIn);
    assert(c == 3, 'probeChannel:notRGB', 'Image input must be H-by-W-by-3.');
    px = reshape(rgbIn, [], 3);
else
    assert(ismatrix(rgbIn) && size(rgbIn,2) == 3, 'probeChannel:notList', ...
        'List input must be N-by-3.');
    px = rgbIn;
end

% Scale factor bringing the input into 0-255 double units.
if isinteger(px)
    if isa(px, 'uint8')
        sc = 1;                                     % already 0-255
    else
        sc = 255 / double(intmax(class(px)));
    end
elseif max(px(:)) <= 1
    sc = 255;                                       % floats live in [0 1]
else
    sc = 1;
end

% Convert column by column rather than casting the whole array. At 16 MP a
% full double copy of px is ~380 MB on its own, so this matters.
R = double(px(:,1)) * sc;
G = double(px(:,2)) * sc;
B = double(px(:,3)) * sc;

switch name
    case 'RmG',    v = R - G;
    case 'BmG',    v = B - G;
    case 'RmB',    v = R - B;
    case 'GmR',    v = G - R;

    case 'rgRed'
        s = R + G + B;  s(s < 1) = 1;
        v = 255 * (R - G) ./ s;
    case 'rgBlue'
        s = R + G + B;  s(s < 1) = 1;
        v = 255 * (B - G) ./ s;

    case {'Lab_L','Lab_a','Lab_b'}
        switch name
            case 'Lab_L', col = 1;
            case 'Lab_a', col = 2;
            case 'Lab_b', col = 3;
        end
        % Chunked: a full 16 MP frame would otherwise need several GB of
        % temporaries inside rgb2lab.
        n     = numel(R);
        chunk = 2e6;
        v     = zeros(n, 1);
        for i0 = 1:chunk:n
            k   = i0:min(n, i0 + chunk - 1);
            % rgb2lab accepts an N-by-3 colormap-style list in [0 1].
            lab = rgb2lab([R(k) G(k) B(k)] / 255);
            v(k) = lab(:, col);
        end

    case 'gray'
        v = 0.2989*R + 0.5870*G + 0.1140*B;

    otherwise
        error('probeChannel:unknownChannel', ...
              'Unknown channel "%s". See "help probeChannel".', name);
end

if isImage
    v = reshape(v, h, w);
end
end

