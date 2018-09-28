% Camera.GUI(id, width)
% Camera object with UI components.
%
% Camera.GUI methods:
%   delete - Release camera and delete panel with graphic components.

% 2018-05-30. Leonardo Molina.
% 2018-08-22. Last modified.
classdef GUI < Camera
    properties (Access = private)
        exposureIdle = true
        exposureSlider
        exposureText
        exposureStep = 0.10
        fpsVector = NaN(1, 20)
        mirrorVButton
        mirrorHButton
        mirrorText
        playButton
        resolutionIdle = true
        resolutionPopup
        resolutionText
        startTime
    end
    
    properties (SetAccess = private)
        panel
    end
    
    methods
        function [obj, panel] = GUI(cameraId, width)
            % [obj, panel] = Camera.GUI(cameraId, width)
            % Create a Camera object and return a panel with UI components
            % to interact with it.
            
            if nargin < 1
                cameraId = 1;
            end
            if nargin < 2
                width = 560;
            end
            obj = obj@Camera(cameraId);
            
            obj.register('Mirror', @(~)obj.redraw('mirror'));
            obj.register('Exposure', @(~)obj.redraw('exposure'));
            obj.register('Resolution', @(~)obj.redraw('resolution'));
            
            % Add GUI controls.
            nRows = 5;
            height = 20;
            
            if numel(findobj('type', 'figure')) == 0
                control = figure('MenuBar', 'none', 'NumberTitle', 'off', 'Name', 'Camera - GUI', 'DeleteFcn', @(~, ~)obj.delete);
                control.Position = [control.Position([1, 2]), width, nRows * height];
            end
            
            panel = uipanel('Title', 'Camera');
            panel.Units = 'Pixels';
            panel.Position = [1, 1, width, nRows * height];
            obj.panel = panel;
            
            % Play.
            p = 0;
            obj.playButton      = uicontrol('Parent', panel, 'Style', 'PushButton',  'Position', [0.20 * width, p * height, 0.40 * width, height], 'Units', 'Normalized', 'String', 'Play', 'Callback', @(handle, ~)obj.onPlayButton(handle));
            % Mirror.
            p = 1;
            obj.mirrorText      = uicontrol('Parent', panel, 'Style', 'Text',        'Position', [0.00 * width, p * height, 0.19 * width, height], 'Units', 'Normalized', 'String', 'Image mirror:', 'HorizontalAlignment', 'right');
            obj.mirrorVButton   = uicontrol('Parent', panel, 'Style', 'PushButton',  'Position', [0.20 * width, p * height, 0.40 * width, height], 'Units', 'Normalized', 'CallBack', @(~, ~)obj.onMirrorVButton());
            obj.mirrorHButton   = uicontrol('Parent', panel, 'Style', 'PushButton',  'Position', [0.60 * width, p * height, 0.40 * width, height], 'Units', 'Normalized', 'CallBack', @(~, ~)obj.onMirrorHButton());
            % Exposure.
            p = 2;
            obj.exposureText    = uicontrol('Parent', panel, 'Style', 'Text',        'Position', [0.00 * width, p * height, 0.19 * width, height], 'Units', 'Normalized', 'String', 'Exposure', 'HorizontalAlignment', 'right');
            obj.exposureSlider  = uicontrol('Parent', panel, 'Style', 'Slider',      'Position', [0.20 * width, p * height, 0.80 * width, height], 'Units', 'Normalized');
            % Resolution.
            p = 3;
            obj.resolutionText  = uicontrol('Parent', panel, 'Style', 'Text',        'Position', [0.00 * width, p * height, 0.19 * width, height], 'Units', 'Normalized', 'String', 'Resolution', 'HorizontalAlignment', 'right');
            obj.resolutionPopup = uicontrol('Parent', panel, 'Style', 'Popup',       'Position', [0.20 * width, p * height, 0.80 * width, height], 'Units', 'Normalized', 'String', Tools.compose('%ix%i', num2cell(obj.resolutionList)), 'CallBack', @(~, ~)obj.onResolutionList());
            
            mn = round(obj.exposureRange(1) / obj.exposureStep) * obj.exposureStep;
            mx = round(obj.exposureRange(2) / obj.exposureStep) * obj.exposureStep;
            iSteps = (mx - mn)/obj.exposureStep;
            set(obj.exposureSlider, 'Min', mn, 'Max', mx, 'Value', mean(obj.exposureRange), 'SliderStep', [1 1] ./ iSteps, 'Callback', @(~, ~)obj.onExposureSlider());
            addlistener(obj.exposureSlider, 'ContinuousValueChange', @(~, ~)obj.onExposureSlider());
            
            obj.startTime = tic;
            obj.register('Frame', @(frame)obj.onFrame());
            
            obj.redraw('mirror');
            obj.redraw('exposure');
            obj.redraw('resolution');
        end
        
        function delete(obj)
            % Camera.GUI.delete()
            % Release camera resource and remove GUI components.
            
            delete(obj.panel);
            delete@Camera(obj);
        end
    end
    
    methods (Access = private)
        function redraw(obj, tag)
            switch tag
                case 'mirror'
                    switch obj.mirror(1)
                        case true
                            obj.mirrorVButton.String = 'Vertical: Mirror';
                        case false
                            obj.mirrorVButton.String = 'Vertical: Normal';
                    end
                    switch obj.mirror(2)
                        case true
                            obj.mirrorHButton.String = 'Horizontal: Mirror';
                        case false
                            obj.mirrorHButton.String = 'Horizontal: Normal';
                    end
                case 'exposure'
                    if obj.exposureIdle
                        obj.exposureSlider.Value = min(max(obj.exposure, obj.exposureSlider.Min), obj.exposureSlider.Max);
                    end
                    obj.exposureText.String = sprintf('Exposure [%.5f]:', obj.exposure);
                case 'resolution'
                    if obj.resolutionIdle
                        obj.resolutionPopup.Value = obj.resolutionIndex;
                    end
                    obj.resolutionText.String = sprintf('Resolution [%i]', obj.resolutionIndex);
            end
        end
        
        function onExposureSlider(obj)
            value = round(obj.exposureSlider.Value / obj.exposureStep) * obj.exposureStep;
            obj.exposureIdle = false;
            obj.exposure = value;
            obj.exposureIdle = true;
        end
        
        function onFrame(obj)
            vector = obj.fpsVector(~isnan(obj.fpsVector));
            if numel(vector) >= 2
                obj.playButton.String = sprintf('Pause [%i fps]', round(1 / mean(diff(vector))));
            end
            obj.fpsVector = circshift(obj.fpsVector, -1);
            obj.fpsVector(end) = toc(obj.startTime);
        end
        
        function onMirrorVButton(obj)
            obj.mirror = [~obj.mirror(1), obj.mirror(2)];
        end
        
        function onMirrorHButton(obj)
            obj.mirror = [obj.mirror(1), ~obj.mirror(2)];
        end
        
        function onPlayButton(obj, handle)
            if obj.play
                obj.play = false;
                handle.String = 'Play';
            else
                obj.play = true;
                handle.String = 'Pause';
            end
        end
        
        function onResolutionList(obj)
            value = obj.resolutionPopup.Value;
            obj.resolutionIdle = false;
            obj.resolutionIndex = value;
            obj.resolutionIdle = true;
        end
    end
end