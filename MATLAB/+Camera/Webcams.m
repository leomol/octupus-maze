% Webcams.
% Webcam events:
%   Resolution - Resolution changed (asynchronous).
% 
% See also Camera.

% 2016-11-30. Leonardo Molina.
% 2018-08-20. Last modified.
classdef Webcams < Event % pretent-CameraInterface
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
    
    properties (SetAccess = private)
        camera                % Webcam object.
        controller            % Controller of the webcam object.
    end
    
    properties (Access = private)
        mFrame
        mResolutionIndex = -1 
        mResolutionList
        mResolutionNames
        mExposureAvailable
        mExposure
        mExposureRange
    end
    
    methods
        function obj = Webcams(id)
            % Webcams(<camera_id>)
            
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
                        % Try loading using webcam.
                        warning('OFF', 'MATLAB:class:DestructorError');
                        obj.camera = webcam(id);
                        obj.controller = obj.camera.getCameraController();
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
                    try
                        obj.camera.ExposureMode = 'manual';
                        obj.mExposureAvailable = true;
                    catch
                        obj.mExposureAvailable = false;
                    end
                    if obj.mExposureAvailable
                        try
                            obj.camera.Exposure = Inf;
                        catch e
                            exposureNumbers = regexp(e.message, '[-+]?\d+', 'match');
                        end
                        obj.mExposureRange = str2double(exposureNumbers(end-1:end));
                        obj.exposure = 0.9 * sum(obj.exposureRange);
                    else
                        obj.mExposure = Inf;
                        obj.mExposureRange = [Inf Inf];
                    end

                    % Populate resolution list.
                    res = obj.camera.AvailableResolutions;
                    mres = strsplit(strjoin(res, 'x'), 'x');
                    mres = reshape(str2double(mres), 2, numel(mres) / 2)';
                    mres = fliplr(mres);
                    [mres, o] = sortrows(mres);
                    obj.mResolutionNames = res(o);
                    obj.mResolutionList = mres';
                    % Choose minimum resolution.
                    obj.resolutionIndex = 1;
                    % Start frame for getFrame(false).
                    resolution = obj.resolutionList(:, obj.resolutionIndex);
                    obj.mFrame = zeros(resolution(2), resolution(1), 3, 'uint8');
                end
            else
                error('Could not connect to any webcams.');
            end
        end
        
        function delete(obj)
            Objects.delete(obj.camera);
        end
        
        function frame = getFrame(obj, block)
            if nargin < 2
                block = false;
            end
            if block
                obj.mFrame = obj.controller.getCurrentFrame();
            else
                if obj.hasFrame
                    obj.mFrame = obj.controller.getCurrentPreviewFrame();
                end
            end
            frame = obj.mFrame;
            
            dim = [size(frame, 1); size(frame, 2)];
            if ~isequal(dim, obj.resolution)
                obj.invoke('Resolution', obj.resolution);
            end
        end
        
        function hasFrame = get.hasFrame(obj)
            hasFrame = obj.controller.getHasNewPreviewData();
        end
        
        function set.resolutionIndex(obj, r)
            if r ~= obj.mResolutionIndex && r > 0 && r <= size(obj.resolutionList, 2)
                % Exposure must be set to the minimum to avoid buggy MATLAB to hang.
                exposureWas = obj.exposure;
                obj.exposure = obj.exposureRange(1);
                obj.mResolutionIndex = r;
                obj.camera.Resolution = obj.mResolutionNames{r};
                obj.exposure = exposureWas;
                obj.invoke('Resolution', obj.resolution);
            end
        end
        
        function r = get.resolutionIndex(obj)
            r = obj.mResolutionIndex;
        end
        
        function r = get.resolutionList(obj)
            r = obj.mResolutionList;
        end
        
        function set.exposure(obj, exposure)
            obj.mExposure = min(max(exposure, obj.exposureRange(1)), obj.exposureRange(2));
            if obj.mExposureAvailable
                % Toggling the exposure mode helps buggy MATLAB recognize changes to exposure.
                % Also, allow camera refresh settings.
                obj.camera.ExposureMode = 'auto';
                Scheduler.Delay({@Objects.assign, obj.camera, 'ExposureMode', 'manual'}, 0.050);
                Scheduler.Delay({@Objects.assign, obj.camera, 'Exposure', obj.mExposure}, 0.100);
            end
        end
        
        function exposure = get.exposure(obj)
            exposure = obj.mExposure;
        end
        
        function range = get.exposureRange(obj)
            range = obj.mExposureRange;
        end
    end
    
    methods (Access = private)
        function resolution = resolution(obj)
            resolution = obj.resolutionList(:, obj.resolutionIndex);
        end
    end
end