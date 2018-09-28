% Target - Invoke functions when a test position lands within previously
% defined regions.
% 
% Target methods:
%   add  - Invoke a generic method when a pointer enters a region.
%   test - Test whether the position is inside any registered region.
% 
%   Example:
%     obj = Target();
%     zone1 = [0.50, 1.00, 1.00, 0.50
%              0.50, 0.50, 1.00, 1.00];
%     zone2 = [0.25, 0.75, 0.75, 0.25
%              0.25, 0.25, 0.75, 0.75];
%     h1 = obj.add(zone1(1:2:end), zone1(2:2:end), 0.01, {@(message, data)fprintf(message, data.X, data.Y), '>> Hit zone 1 at (%.2f, %.2f)\n'});
%     h2 = obj.add(zone2(1:2:end), zone2(2:2:end), 0.01, {@(message, data)fprintf(message, data.Y, data.Y), '>> Hit zone 2 at (%.2f, %.2f)\n'});
% 
%     disp('Aim to nothing:');
%     obj.test(0.00, 0.00);
% 
%     disp('Aim to zone 1 only:');
%     obj.test(1.00, 1.00);
% 
%     disp('Aim to zone 2 only:');
%     obj.test(0.25, 0.25);
% 
%     disp('Aim to both zones:');
%     obj.test(0.50, 0.50);
% 
%     disp('Delete zone 1 and repeat:');
%     delete(h1);
%     obj.test(0.50, 0.50);

% 2018-05-28. Leonardo Molina.
% 2018-06-15. Last modified.
classdef Target < handle
    properties (Access = private)
        % zones - Structure with zone definitions.
        zones = struct('id', {}, 'callback', {}, 'handle', {}, 'x', {}, 'y', {}, 'significance', {}, 'mask', {});
        
        % uid - Handle id for region triggers.
        uid = 0
    end
    
    methods
        function handle = add(obj, xs, ys, significance, callback)
            % handle = Target.add(xs, ys, significance, callback)
            % Invoke a generic method when a pointer enters a region.
            % Round region to the nearest multiple of significance.
            
            if nargin == 3
                callback = @Callbacks.void;
            end
            
            n = numel(obj.zones) + 1;
            id = obj.uid + 1;
            obj.uid = id;
            obj.zones(n).id = id;
            obj.zones(n).callback = callback;
            obj.zones(n).x = xs;
            obj.zones(n).y = ys;
            obj.zones(n).significance = significance;
            obj.zones(n).mask = Target.mask(xs, ys, significance);
            obj.zones(n).handle = Handle({@obj.remove, id});
            handle = obj.zones(n).handle;
        end
        
        function states = test(obj, x, y, invoke)
            % callback = Target.test(x, y, <invoke>)
            % Test whether position falls inside previously registered regions.
            % Return a cell array of callbacks: The row index of the callback
            % corresponds to the region index. A cell element will only contain
            % the corresponding callback if there was a hit. Such callback may
            % also be invoked internally if invoke == true.
            % 
            % callback = Target.test([x1 x2], [y1 y2], <invoke>)
            % Same as above, except data is interpolated between the two
            % points.
            
            if nargin < 4
                invoke = [true, false];
            end
            
            nZones = numel(obj.zones);
            states = false(nZones, 1);
            if numel(x) == 1
                x = [x x];
                y = [y y];
            end
            for z = 1:nZones
                zone = obj.zones(z);
                % Get position index for the test mask.
                ox = x - min(zone.x);
                oy = y - min(zone.y);
                ilims = floor(oy / zone.significance) + 1;
                jlims = floor(ox / zone.significance) + 1;
                ni = abs(diff(ilims));
                nj = abs(diff(jlims));
                n = max([ni, nj, 1]) - 1;
                if n == 0
                    ii = ilims(1);
                    jj = jlims(1);
                else
                    ii = floor(oy(1) / zone.significance + (0:n) * (diff(oy) / zone.significance / n)) + 1;
                    jj = floor(ox(1) / zone.significance + (0:n) * (diff(ox) / zone.significance / n)) + 1;
                end
                k = arrayfun(@(k) ii(k) >= 1 && jj(k) >= 1 && ii(k) <= size(zone.mask, 1) && jj(k) <= size(zone.mask, 2) && zone.mask(ii(k), jj(k)), 1:numel(ii));
                % If index is within bounds and is a match, callback.
                states(z) = any(k);
                if states(z)
                    if invoke(1)
                        Callbacks.invoke(zone.callback, struct('X', x(end), 'Y', y(end), 'State', true, 'Handle', obj.zones(z).handle));
                    end
                else
                    if invoke(2)
                        Callbacks.invoke(zone.callback, struct('X', x(end), 'Y', y(end), 'State', false, 'Handle', obj.zones(z).handle));
                    end
                end
            end
        end
    end
    
    methods (Access = private)
        function remove(obj, ids)
            % Target.remove(id)
            % Stop capturing a region according to their id.
            
            uids = [obj.zones.id];
            obj.zones(ismember(uids, ids)) = [];
        end
    end
    
    methods (Static)
        function m = mask(x, y, significance)
            % mask = Target.mask(x, y, significance)
            % Generate a binary mask from region. Resize mask according to
            % the nearest multiple of significance.
            
            % Offset to zero.
            x = x - min(x);
            y = y - min(y);
            % Scale to significance.
            x = x / significance;
            y = y / significance;
            % Turn into one-based indexing.
            x = floor(x) + 1;
            y = floor(y) + 1;
            % Mask size.
            resolution = [max(y), max(x)];
            % All points in the mask.
            [ys, xs] = find(true(resolution));
            % Build mask.
            [a, b] = inpolygon(xs, ys, x, y);
            m = false(resolution);
            m(a | b) = true;
        end
    end
end