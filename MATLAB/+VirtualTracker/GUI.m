% VirtualTracker.GUI(cameraId) - GUI for the VirtualTracker class.
% UI components to interact with the VirtualTracker task.
% 
% Example 1 - a unique zone for all trials:
%   region = [0, 0, 0.1];
%   callback = @(data)fprintf('Inside: %i\n', data.State);
%   zone = {1, region, callback};
%   obj = VirtualTracker.GUI();
%   obj.zones = zone;
% 
% Example 2 - one zone for odd trials, another zone for even trials:
%   zones = {1, [-0.1, -0.1, +0.1], @(data)fprintf('zone 1: %i\n', data.State), ...
%            2, [+0.1, +0.1, +0.1], @(data)fprintf('zone 2: %i\n', data.State)};
%   obj = VirtualTracker.GUI();
%   obj.zones = zones;
% 
% Example 3 - two zones, one zone, another zone, repeat:
%   zones = {1, [-0.1, -0.1, +0.1], @(data)fprintf('zone 1.1: %i\n', data.State), ...
%            1, [+0.1, +0.1, +0.1], @(data)fprintf('zone 1.2: %i\n', data.State), ...
%            8, [+0.1, +0.1, +0.1], @(data)fprintf('zone 8: %i\n', data.State)  , ...
%            9, [+0.0, +0.0, +0.0], @(data)fprintf('zone 9: %i\n', data.State)};
%   obj = VirtualTracker.GUI();
%   obj.zones = zones;

% 2018-05-30. Leonardo Molina.
% 2018-09-12. Last modified.
classdef GUI < VirtualTracker
    properties (Dependent)
        % zone - Index of current target zone.
        zone
        
        % renderMode - Render modes: normal | weigths.
        renderMode
        
        % zones - List of zones to track.
        zones
    end
    
    properties
        % trail - Length of trail left by a pointer.
        trail = 20
    end
    
    properties (SetAccess = private, Hidden)
        % window - Figure handle with GUI.
        window
    end
    
    properties (Access = private)
        % Buttons.
        discardButton
        nextButton
        renderModeButton
        
        % Lines.
        blobLines
        pathLines = {}
        pointerLines = {}
        roiLine
        targetLines = {}
        
        % Other.
        caret = 1
        roiChanging = false
        roiBuffer = []
        mode = 0
        mRenderMode = 'weights'
        mZone = 0
        mZones = {}
        panelOffset = 0
        playback
    end
    
    methods
        function obj = GUI(cameraId)
            % VirtualTracker.GUI(<cameraId>)
            
            if nargin < 1
                cameraId = 1;
            end
            
            % Create window figure and UI components.
            obj.window = figure('MenuBar', 'none', 'NumberTitle', 'off', 'Name', 'VirtualTracker Maze - Control', 'DeleteFcn', @(~, ~)obj.onClose);
            width = obj.window.Position(3);
            
            % Add VirtualTracker controls.
            nRows = 3;
            height = 20;
            panel = uipanel('Title', 'VirtualTracker');
            panel.Units = 'Pixels';
            panel.Position = [1, 1, width, nRows * height];
            obj.discardButton    = uicontrol('Parent', panel, 'Style', 'PushButton', 'Position', [0.20 * width, 1 * height, 0.40 * width, height], 'Units', 'Normalized', 'String', 'Discard trial', 'Callback', @(~, ~)obj.onDiscardButton);
            obj.nextButton       = uicontrol('Parent', panel, 'Style', 'PushButton', 'Position', [0.60 * width, 1 * height, 0.40 * width, height], 'Units', 'Normalized', 'String', 'Next trial', 'Callback', @(~, ~)obj.onNextButton);
            obj.renderModeButton = uicontrol('Parent', panel, 'Style', 'PushButton', 'Position', [0.20 * width, 0 * height, 0.40 * width, height], 'Units', 'Normalized', 'String', 'Display: Normal', 'Callback', @(~, ~)obj.onRenderModeButton);
            obj.pushPanel(panel);
            
            % Add Tracker controls.
            [tracker, panel] = Tracker.GUI(width);
            obj.pushPanel(panel);
            
            % Add Camera controls.
            [camera, panel] = Camera.GUI(cameraId, width);
            obj.pushPanel(panel);
            
            % Add playback figure.
            obj.playback = Image('VirtualTracker Maze - Playback');
            obj.playback.register('Close', {obj, 'delete'});
            obj.playback.register('KeyPress', @obj.onKeyPress);
            obj.playback.register('MouseClick', @obj.onMouseClick);
            obj.playback.window.OuterPosition = [obj.window.OuterPosition(1), obj.window.OuterPosition(2) - obj.playback.window.OuterPosition(4), obj.playback.window.OuterPosition([3, 4])];
            
            % Add lines.
            obj.roiLine = obj.playback.line('LineStyle', '--', 'Marker', 'none', 'Color', [1, 1, 1]);
            obj.blobLines = obj.playback.line('LineStyle', 'none', 'Marker', '+', 'MarkerSize', 1, 'LineWidth', 1, 'Color', [0, 0, 1]);
            
            % Listen to property changes.
            obj.register('Position', @obj.onPosition);
            obj.register('Roi', @obj.onRoi);
            
            % Initialize superclass.
            obj.initialize(tracker, camera);
            
            camera.register('Frame', @(~)obj.onFrame);
        end
        
        function pushPanel(obj, panel)
            % VirtualTracker.GUI.pushPanel()
            
            panel.Parent = obj.window;
            panel.Position = [1, obj.panelOffset, obj.window.Position(3), panel.Position(4)];
            obj.panelOffset = sum(panel.Position([2, 4]));
            
            % Adjust figure size.
            obj.window.Position = [obj.window.Position([1, 2]), obj.window.Position(3), obj.panelOffset];
        end
        
        function delete(obj)
            % VirtualTracker.GUI.delete()
            % Close window figure and release resources.
            
            delete(obj.playback);
            delete(obj.window);
            delete@VirtualTracker(obj);
        end
        
        function set.renderMode(obj, renderMode)
            switch renderMode
                case 'weights'
                    obj.playback.imageHandle.CDataMapping = 'scaled';
                    obj.renderModeButton.String = 'Display: Normal';
                    obj.mRenderMode = renderMode;
                case 'normal'
                    obj.playback.imageHandle.CDataMapping = 'direct';
                    obj.renderModeButton.String = 'Display: Weights';
                    obj.mRenderMode = renderMode;
                otherwise
                    error('Value provided for renderMode is invalid.');
            end
        end
        
        function renderMode = get.renderMode(obj)
            renderMode = obj.mRenderMode;
        end
        
        function zones = get.zones(obj)
            zones = obj.mZones;
        end
        
        function set.zones(obj, zones)
            % One-based index for all zone ids.
            % 1 3 5 9 7 --> 1 2 3 5 4.
            [~, ~, ids] = unique(cat(2, zones{1:3:end}));
            ids = num2cell(ids);
            [zones{1:3:end}] = deal(ids{:});
            obj.mZones = zones;
            
            obj.zone = 1;
        end
        
        function zone = get.zone(obj)
            zone = obj.mZone;
        end
        
        function set.zone(obj, zone)
            % Cycle around available ids.
            ids = cat(2, obj.zones{1:3:end});
            uids = unique(ids);
            obj.clearLines();
            if numel(uids) > 0
                zone = mod(zone - 1, numel(uids)) + 1;
                obj.mZone = zone;

                matches = find(ids == zone);
                regions = obj.zones(3 * (matches - 1) + 2);
                callbacks = obj.zones(3 * (matches - 1) + 3);
                
                for r = 1:numel(regions)
                    [xs, ys] = Tools.region(regions{r}, 360);
                    obj.targetLines{r} = obj.playback.line('LineStyle', '--', 'Color', [0, 1, 0], 'XData', xs, 'YData', ys);
                end

                zs = [regions; callbacks];
                obj.setup(zs{:});
            end
        end
    end
    
    methods (Access = private)
        function onClose(obj)
            % VirtualTracker.GUI.onClose()
            % Report that the figure window is closing.
            
            obj.invoke('Close');
            delete(obj);
        end
        
        function onDiscardButton(obj)
            % VirtualTracker.GUI.onDiscardButton()
            % Reload zone without saving.
            
            obj.clearLines();
            obj.zone = obj.zone;
        end
        
        function onFrame(obj)
            % VirtualTracker.GUI.onFrame()
            % New image reported by camera.
            
            switch obj.renderMode
                case 'normal'
                    obj.playback.image = obj.camera.frame;
                case 'weights'
                    obj.playback.image = obj.tracker.weights;
            end
            drawnow();
        end
        
        function onRenderModeButton(obj)
            % VirtualTracker.GUI.onRenderModeButton()
            % Rotate between different rendering modes (normal and weights).
            
            switch obj.renderMode
                case 'normal'
                    obj.renderMode = 'weights';
                otherwise
                    obj.renderMode = 'normal';
            end
        end
        
        function onNextButton(obj)
            % VirtualTracker.GUI.onNextButton()
            % Save current trial and load next zone.
            
            obj.save();
            obj.zone = obj.zone + 1;
        end
        
        function clearLines(obj)
            % VirtualTracker.GUI.clearLines()
            % Remove graphics from axis.
            
            Objects.delete(obj.pointerLines{:});
            Objects.delete(obj.pathLines{:});
            Objects.delete(obj.targetLines{:});
            obj.pointerLines = {};
            obj.pathLines = {};
            obj.targetLines = {};
        end
        
        function onKeyPress(obj, data)
            if data.Character == 'r'
                obj.roiChanging = data.Down;
                if obj.roiChanging
                    obj.roi = [];
                    obj.roiBuffer = [];
                end
            end
        end
        
        function onMouseClick(obj, data)
            if obj.roiChanging
                obj.roiBuffer = [obj.roiBuffer, data.Position];
                if numel(obj.roiBuffer) > 4
                    obj.roi = obj.roiBuffer;
                end
            elseif data.Left && data.Down
                %obj.onPosition(struct('X', data.Position(1), 'Y', data.Position(2)));
                obj.step(data.Position(1), data.Position(2));
            end
        end
        
        function onPosition(obj, data)
            % VirtualTracker.GUI.onPosition()
            % Tracker reports a change in position. Update graphics.
            
            nLines = numel(obj.pointerLines);
            nPoints = numel(data.X);
            for p = nLines + 1:nPoints
                obj.pointerLines{p} = obj.playback.line('LineStyle', 'none', 'Marker', 'o', 'MarkerSize', 10); %, 'LineWidth', 3);
                obj.pathLines{p} = obj.playback.line('LineStyle', '-', 'Marker', 'none', 'Color', obj.pointerLines{p}.handle.Color); %, 'LineWidth', 1);
            end
            for p = 1:nPoints
                current = [data.X(p); data.Y(p)];
                obj.pathLines{p}.data = [obj.pathLines{p}.data; current];
                obj.pathLines{p}.data = obj.pathLines{p}.data(end + 1 - min(2 * obj.trail, numel(obj.pathLines{p}.data)):end);
                obj.pathLines{p}.data = obj.pathLines{p}.data(end + 1 - min(2 * obj.trail, numel(obj.pathLines{p}.data)):end);
                obj.pointerLines{p}.data = current;
            end
            [ys, xs] = find(obj.tracker.blobs);
            [xs, ys] = Tools.normalize(xs, ys, obj.camera.resolution(2), obj.camera.resolution(1));
            obj.blobLines.data = [xs, ys]';
        end
        
        function onRoi(obj, roi)
            % VirtualTracker.GUI.onRoi(roi)
            % Tracker reports a change in the region of interest.
            % Update graphics.
            
            [x, y] = Tools.region(roi);
            if isempty(x)
                obj.roiLine.data = [];
            else
                obj.roiLine.data = [x, x(1); y, y(1)];
            end
        end
    end
end