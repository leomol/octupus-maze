% VideoInputs.
% 
% VideoInput properties:
% 
% See also Camera.

% 2017-12-14. Leonardo Molina.
% 2018-09-07. Last modified.
classdef VideoInputs < Event % pretend-CameraInterface
    properties (Dependent)
        % hasFrame - Whether a new frame is available.
        hasFrame
        
        % exposure - Set/get the exposure.
        exposure
        
        % exposureRange - Exposure range.
        exposureRange
        
        % resolutionIndex - Index of selected resolution.
        resolutionIndex
        
        % resolutionList - List of available resolutions.
        resolutionList
    end
    
    properties (Access = private)
        camera
        scheduler
        frame = zeros(3, 3, 3, 'uint8');
        mHasFrame = false;
        mResolutionIndex = 1
    end

    methods
        function obj = VideoInputs(id)
            % VideoInputs(<camera_id>)
            
            success = false;
            className = mfilename('class');
            cameraNames = webcamlist();
            if nargin == 0
                id = 1;
            end
            nCameras = numel(cameraNames);
            if nCameras > 0 && id >= 0 && id <= nCameras
                cameraName = cameraNames{id};
                if Global.contains(className)
                    globalList = Global.get(className);
                    k = find(ismember(globalList(1, :), cameraName), 1);
                    if isempty(k)
                        k = size(globalList, 2) + 1;
                        redo = true;
                    elseif ~Objects.isValid(globalList{2, k})
                        redo = true;
                    else
                        redo = false;
                    end
                else
                    globalList = cell(2, 0);
                    k = 1;
                    redo = true;
                end
                if redo
                    try
                        % Try loading using Image Acquisition Toolbox.
                        obj.camera = videoinput('winvideo', id);
                        obj.camera.TriggerRepeat = Inf;
                        start(obj.camera);
                        globalList(:, k) = {cameraName; obj};
                        % Remember object handle.
                        Global.set(className, globalList);
                        success = true;
                    catch
                    end
                else
                    % Recover object handle.
                    obj = globalList{2, k};
                    success = true;
                end
            end
            
            if success
                if redo
                    % Read and clear videoinput's buffer in the background.
                    obj.scheduler = Scheduler();
                    obj.scheduler.repeat(@obj.capture, 1e-2);
                end
            else
                error('Could not connect to any videoinputs.');
            end
        end
        
        function delete(obj)
            delete(obj.scheduler);
            flushdata(obj.camera);
            stop(obj.camera);
            delete(obj.camera);
        end
        
        function frame = getFrame(obj, block)
            if nargin == 2 && block
                while Objects.isValid(obj) && ~obj.mHasFrame
                    pause(1e-3);
                end
            end
            if Objects.isValid(obj)
                frame = obj.frame;
                obj.mHasFrame = false;
            else
                frame = [];
            end
        end
        
        function hasFrame = get.hasFrame(obj)
            hasFrame = obj.mHasFrame;
        end
        
        function r = get.resolutionIndex(obj)
            r = obj.mResolutionIndex;
        end
        
        function set.resolutionIndex(~, ~)
        end
        
        function list = get.resolutionList(obj)
            list = fliplr(obj.camera.VideoResolution)';
            list = list(:);
        end
        
        function set.exposure(~, ~)
        end
        
        function exposure = get.exposure(~)
            exposure = Inf;
        end
        
        function range = get.exposureRange(~)
            range = [Inf, Inf];
        end
    end
    
    methods (Access = private)
        function capture(obj)
            % VideoInputs.capture()
            % Read all frames from videoinput, keep last.
            
            if Objects.isValid(obj.camera) && obj.camera.FramesAvailable > 0
                data = getdata(obj.camera, 1);
                flushdata(obj.camera);
                obj.frame = data(:, :, end);
                obj.mHasFrame = true;
            end
        end
    end
end