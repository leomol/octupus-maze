% Tracker - Scan targets in an image.
% 
% Tracker methods:
%   track - Scan targets in an image. Identity of targets is preserved over
%   time.
% 
% Tracker properties:
%   area       - Target size relative to the screen area (0..1).
%   blobs      - Identity of isolated blobs.
%   hue        - Target hue.
%   population - Proportion of pixels to test.
%   quantity   - Number of targets to track.
%   roi        - Region of interest.
%   shrink     - Number of layers to peel off each test blob.
%   weights    - Match score assigned to each pixel.
% 
% Tracker Event list:
%   Area(area)
%   Hue(hue)
%   Population(population)
%   Position(position)
%   Quantity(quantity)
%   Roi(roi)
%   Shrink(shrink)
%   Weights(weights)
% 
% All of the above are reported after a change in the property with the same
% name.
% 
% See also Event, Tracker.GUI.

% 2016-11-23. Leonardo Molina.
% 2018-09-13. Last modified.
classdef Tracker < Event
    properties (Dependent = true)
        % area - Target size. 0 <= size <= 1; ignore: -1; homogeneous: -2.
        area
        
        % blobs - Identity of isolated blobs.
        blobs
        
        % hue - Target hue. 0 <= hue <= 1; dark: -1, bright: -2.
        hue
        
        % population - Proportion of pixels to test. 0 <= population <= 1
        population
        
        % position - Current position.
        position
        
        % quantity - Number of targets. Center of mass: 0; Multiple: 1, 2, ...
        quantity
        
        % resize - Resize image prior to computing anything.
        resize
        
        % roi - ROI mask.
        roi
        
        % shrink - How many pixel layers to remove from each test blob.
        shrink
        
        % weights - Current score weights assigned to each pixel.
        weights
    end
    
    properties (Access = private)
        mArea = 0
        mBlobs
        mHue = 0
        mResize = []
        mRoi = []
        mPopulation = 0.02
        mPosition = zeros(2, 1)
        mQuantity = 1
        mShrink = 1
        mWeights
        
        cx = zeros(1, 0)
        cy = zeros(1, 0)
        rectangularMask = []
        mask
        
        index1
        index2
        dataSize
    end
    
    methods
        function set.area(obj, area)
            if numel(area) == 1 && isfloat(area) && ...
                ( ...
                    (area >= 0 && area <= 1) || ...
                    area == -1 || ...
                    area == -2 ...
                )
                obj.mArea = area;
                obj.invoke('Area', area);
            else
                error('Value provided for area is invalid.');
            end
        end
        
        function area = get.area(obj)
            area = obj.mArea;
        end
        
        function blobs = get.blobs(obj)
            blobs = obj.mBlobs;
        end
        
        function set.hue(obj, hue)
            if numel(hue) == 1 && isfloat(hue) && ...
                ( ...
                    (hue >= 0 && hue <= 1) || ...
                    hue == -1 || ...
                    hue == -2 ...
                )
                obj.mHue = hue;
                obj.invoke('Hue', hue);
            else
                error('Value provided for hue is invalid.');
            end
        end
        
        function hue = get.hue(obj)
            hue = obj.mHue;
        end
        
        function set.population(obj, population)
            if numel(population) == 1 && population >= 0 && population <= 1
                obj.mPopulation = population;
                obj.invoke('Population', population);
            else
                error('Value provided for population is invalid.');
            end
        end
        
        function population = get.population(obj)
            population = obj.mPopulation;
        end
        
        function position = get.position(obj)
            position = obj.mPosition;
        end
        
        function set.quantity(obj, quantity)
            if numel(quantity) == 1 && isfloat(quantity) && round(quantity) == quantity && quantity >= 0
                obj.mQuantity = quantity;
                obj.invoke('Quantity', quantity);
            else
                error('Value provided for quantity is invalid.');
            end
        end
        
        function quantity = get.quantity(obj)
            quantity = obj.mQuantity;
        end
        
        function set.resize(obj, s)
            if isempty(s) || (numel(s) == 1 && s > 0)
                obj.mResize = s;
            else
                error('Value provided for resize is invalid.');
            end
        end
        
        function s = get.resize(obj)
            s = obj.mResize;
        end
        
        function set.roi(obj, region)
            obj.mRoi = region;
            obj.invoke('Roi', region);
        end
        
        function roi = get.roi(obj)
            roi = obj.mRoi;
        end
        
        function set.shrink(obj, shrink)
            if numel(shrink) == 1 && isfloat(shrink) && round(shrink) == shrink && shrink >= 0
                obj.mShrink = shrink;
                obj.invoke('Shrink', shrink);
            else
                error('Value provided for shrink is invalid.');
            end
        end
        
        function shrink = get.shrink(obj)
            shrink = obj.mShrink;
        end
        
        function weights = get.weights(obj)
            weights = obj.mWeights;
        end
        
        function position = track(obj, image)
            % position = Tracker.track(image)
            % Find a number of targets satisfying settings area, hue, quantity, etc.
            % image is a n x m x 3 matrix of uint8 type.
            % position is a 2 by n matrix with target coordinates.
            % Coordinates are relative to the lower-left corner of the image.
            
            
            % Image must be 3D.
            if size(image, 3) == 1
                image = repmat(image, 1, 1, 3);
            end
            originalSize = [size(image, 1), size(image, 2)];
            
            % Resize for performance.
            if isempty(obj.mResize)
                workSize = originalSize;
            else
                image = imresize(image, [obj.mResize, NaN], 'method', 'nearest');
                workSize = [size(image, 1), size(image, 2)];
            end
            obj.mBlobs = zeros(workSize, 'uint8');
            
            nPixels = prod(workSize);
            % Create working masks.
            if isempty(obj.mRoi)
                obj.mask = true(workSize(2), workSize(1));
                obj.rectangularMask = {1:workSize(1), 1:workSize(2)};
            else
                [ux, uy] = Tools.region(obj.mRoi, 360);
                [obj.mask, i, j] = Tools.mask(ux, uy, workSize(2), workSize(1));
                obj.rectangularMask = {min(i):max(i), min(j):max(j)};
            end
            
            % Initialize cluster position.
            nc = max(obj.mQuantity, 1);
            d = nc - numel(obj.cx);
            if d > 0
                obj.cx(1, end + 1:end + d) = zeros(1, d);
                obj.cy(1, end + 1:end + d) = zeros(1, d);
            elseif d < 0
                obj.cx = obj.cx(1:nc);
                obj.cy = obj.cy(1:nc);
            end
            
            hsv = rgb2hsv(image);
            v = hsv(:, :, 3);
            % Rank pixels.
            switch obj.mHue
                case -2
                    % Brightest.
                    obj.mWeights = v;
                case -1
                    % Darkest.
                    obj.mWeights = 1 - v;
                otherwise
                    % Nearest to target hue and highest saturation/value.
                    h = hsv(:, :, 1);
                    s = hsv(:, :, 2);
                    obj.mWeights = (1 - abs(circDiff(2 * pi * h, 2 * pi * obj.mHue) / pi) + s + v) / 3;
            end
            obj.mWeights(:) = uint8(255 * obj.mWeights);
            
            % Keep above a percentile.
            targets = false(workSize);
            mx = prctile(obj.mWeights(obj.mask), 100 - min(10, 100 * obj.mPopulation));
            targets(obj.mask) = obj.mWeights(obj.mask) >= mx * (1 - obj.mPopulation);
            
            % Shrink borders. Needs optimization !!.
            if obj.mShrink > 0
                ii = 2:workSize(1) - 1;
                jj = 2:workSize(2) - 1;
                for i = 1:obj.mShrink
                    nn = targets(ii + 0, jj + 0) + ...
                         targets(ii - 1, jj - 1) + targets(ii + 0, jj - 1) + targets(ii + 1, jj - 1) + ...
                         targets(ii + 1, jj + 0) + targets(ii + 1, jj + 1) + targets(ii + 0, jj + 1) + ...
                         targets(ii - 1, jj + 1) + targets(ii - 1, jj + 0);
                    targets(:) = false;
                    targets(ii, jj) = nn == 9;
                end
            end
            
            if any(any(targets))
                % Average weight by blob.
                if obj.mQuantity > 0
                    [obj.mBlobs(obj.rectangularMask{:}), ids, counts] = obj.label(targets(obj.rectangularMask{:}), 0, true);
                    obj.mBlobs(~obj.mask) = 0;
                else
                    obj.mBlobs(obj.mask) = targets(obj.mask);
                    ids = 1;
                    counts = sum(obj.mBlobs(:));
                end
                
                nb = numel(ids);
                if nb > 0
                    score = zeros(nb, 1);
                    for b = 1:nb
                        m = obj.mBlobs == b;
                        score(b) = mean(obj.mWeights(m));
                    end
                    
                    if obj.mArea == -2
                        % Choose homogeneous targets.
                        % Check size of top 2 * nc blobs.
                        [~, sc] = sort(score, 'descend');
                        % Adjust score. Most similar blobs within largest 10.
                        targetCount = median(counts(sc(1:min(10, nb))));
                        score = score ./ abs(targetCount - counts);
                    elseif obj.mArea >= 0 && obj.mArea <= 1
                        % Choose by area.
                        score = score ./ abs(obj.mArea * nPixels - counts);
                    else
                        % Choose any.
                    end
                    [~, sc] = sort(score, 'descend');
                    sc = sc(1:min(nc, nb));
                    
                    nc2 = numel(sc);
                    cx2 = zeros(1, nc2);
                    cy2 = zeros(1, nc2);
                    for k = 1:nc2
                        [i, j] = find(obj.mBlobs == sc(k));
                        % Recover scale.
                        i = i * originalSize(1) / workSize(1);
                        j = j * originalSize(2) / workSize(2);
                        % Center of individual blobs.
                        cx2(k) = mean(j);
                        cy2(k) = mean(i);
                    end
                    
                    % Maintain order.
                    dr = Tools.distance(cx2, cy2, obj.cx, obj.cy);
                    p = perms([0:nc - (nc - nc2) - 1, Inf(1, nc - nc2)]);
                    b = bsxfun(@plus, p, 1:nc2:nc * nc2)';
                    b = reshape(b(b < Inf), nc2, size(b, 2));
                    [~, m] = min(sum(dr(b)));
                    p = p(m, :) + 1;
                    obj.cx(p < Inf) = cx2(p(p < Inf));
                    obj.cy(p < Inf) = cy2(p(p < Inf));
                end
            end
            if numel(obj.resize) == 1
                obj.mBlobs = imresize(obj.mBlobs, originalSize, 'method', 'nearest');
                obj.mWeights = imresize(obj.mWeights, originalSize, 'method', 'nearest');
            end
            
            position = [obj.cx; obj.cy];
            obj.mPosition = position;
            obj.invoke('Position', position);
        end
    end
    
    methods (Access = private)
        function [blobs, ids, counts] = label(obj, data, backgroundId, clean)
            [ni, nj] = size(data);
            n = ni * nj;
            blobs = zeros(n, 1);
            blobs(:) = 1:n;
            blobs = reshape(blobs, ni, nj);
            
            if ~isequal(obj.dataSize, [ni, nj]) || isempty(obj.index1)
                k = 4;
                cc = [n - ni, n - nj, n - ni - nj + 1, n - ni - nj + 1];
                cs = cumsum(cc);
                obj.dataSize = [ni, nj];
                % Horizontal neighbors.
                f = find(n < [256 65536 4294967296 17179869184 Inf], 1);
                types = {'uint8', 'uint16', 'uint32', 'uint64'};
                mtype = types{f};
                obj.index1 = zeros(cs(k), 1, mtype);
                obj.index1(        1:cs(1)) = blobs(:, 1:end - 1);
                obj.index1(cs(1) + 1:cs(2)) = blobs(1:end - 1, :);
                obj.index2 = zeros(cs(k), 1, mtype);
                obj.index2(        1:cs(1)) = blobs(:, 2:end);
                obj.index2(cs(1) + 1:cs(2)) = blobs(2:end, :);
                % Vertical neighbors.
                if k == 4
                    obj.index1(cs(2) + 1:cs(3)) = blobs(1:end - 1, 1:end - 1);
                    obj.index1(cs(3) + 1:cs(4)) = blobs(2:end, 1:end - 1);
                    obj.index2(cs(2) + 1:cs(3)) = blobs(2:end, 2:end);
                    obj.index2(cs(3) + 1:cs(4)) = blobs(1:end - 1, 2:end);
                end
            end
            counts = ones(ni, nj);
            
            for k = 1:numel(obj.index1)
                k1 = obj.index1(k);
                k2 = obj.index2(k);
                if data(k1) ~= backgroundId && data(k2) ~= backgroundId
                    while blobs(k1) ~= k1
                        blobs(k1) = blobs(blobs(k1));
                        k1 = blobs(k1);
                    end
                    while blobs(k2) ~= k2
                        blobs(k2) = blobs(blobs(k2));
                        k2 = blobs(k2);
                    end
                    if k1 ~= k2
                        if data(k1) == data(k2)
                            n1 = counts(k1);
                            n2 = counts(k2);
                            if n1 < n2
                                blobs(k1) = k2;
                                counts(k2) = n1 + n2;
                            else
                                blobs(k2) = k1;
                                counts(k1) = n1 + n2;
                            end
                        end
                    end
                end
            end
            
            % Optimize.
            m = data > 0;
            if nargin == 1 || clean
                [uid, ~, blobs(m)] = unique(blobs(m), 'stable');
                ids = 1:numel(uid);
            else
                uid = unique(blobs(m), 'stable');
                ids = uid;
            end
            counts = counts(uid);
            blobs(~m) = 0;
        end
    end
end

function d = circDiff(a, b)
    d = mod(a - b + pi, 2 * pi) - pi;
end