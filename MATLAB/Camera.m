% Camera - Wrapper to a video resource.
% 
% Webcam events:
%   Resolution      - The resolution changed.
% 
% Camera methods:
%   count           - Return the number of recognized video resources.
%   delete          - Release video resource and delete this object.
%   getFrame        - Return current frame.
%
% Camera properties:
%   frame           - Last captured frame.
%   mirror          - Mirror horizontal and vertical axes.
%   play            - Play/pause acquiring frames.
%   resolutionIndex - Set/get the video resolution.
%   resolutionList  - List available resolutions.
%   exposure        - Set/get exposure.
%   exposureRange   - Get exposure range.

% 2016-11-30. Leonardo Molina.
% 2018-09-14. Last modified.
classdef Camera < Event % pretend-CameraInterface
    properties (Dependent)
        % exposure - Set/get the camera exposure. If not available, exposure = Inf.
        exposure
        
        % exposureRange - Get the camera exposure range. If not available, exposureRange = [Inf Inf].
        exposureRange
        
        % frame - Last captured frame.
        frame
        
        % mirror - Mirror horizontally and vertically: [true|false true|false]
        mirror
        
        % play - Play/pause acquiring frames.
        play
        
        % resolution - Set/get the video resolution.
        resolution
        
        % resolutionIndex - Set/get the video resolution index corresponding to the resolutionList.
        resolutionIndex
        
        % resolutionList - Get the list of available resolutions.
        resolutionList
    end
    
    properties (Access = private)
        % Internal camera object.
        camera
        
        mFrame = []
        mMirror = [false, false]
        
        mPlay = false
        playHandle
        
        scheduler
    end
    
    methods
        function obj = Camera(varargin)
            % Wrap either a webcam or videoinput class, whichever is able
            % to access a video resource.
            
            % Camera factory. Support for a specific resource cannot be
            % determined before hand in MATLAB, hence try opening it with
            % one of two controllers then check for errors.
            errors = [];
            try
                obj.camera = Camera.Webcams(varargin{:});
            catch e1
                errors = [errors, e1];
                try
                    obj.camera = Camera.VideoInputs(varargin{:});
                catch e2
                    errors = [errors, e2];
                end
            end
            success = numel(errors) < 2;
            
            if success
                % Forward camera's resolution change event.
                obj.camera.register('Resolution', @(resolution)obj.invoke('Resolution', resolution));
            else
                % Rethrow both errors.
                Scheduler.Delay({@rethrow, errors(1)}, 1e-3);
                Scheduler.Delay({@rethrow, errors(2)}, 2e-3);
                error('Could not connect to the camera.');
            end
            
            obj.scheduler = Scheduler();
        end
        
        function delete(obj)
            % Camera.delete()
            % Release video resource and delete this object.
            
            delete(obj.scheduler);
            delete(obj.camera);
            obj.invoke('Delete');
        end
        
        function frame = get.frame(obj)
            frame = obj.mFrame;
            if obj.mirror(1)
                frame = frame(end:-1:1, :, :);
            end
            if obj.mirror(2)
                frame = frame(:, end:-1:1, :);
            end
        end
        
        function set.play(obj, play)
            if play && ~obj.play
                obj.playHandle = obj.scheduler.repeat(@obj.loop, 2e-3);
                obj.mPlay = true;
            elseif obj.play && ~play
                Objects.delete(obj.playHandle);
                obj.mPlay = false;
            end
        end
        
        function play = get.play(obj)
            play = obj.mPlay;
        end
        
        function frame = getFrame(obj, varargin)
            % frame = Camera.getFrame(<block>)
            % Return current frame.
            % If block is true (default is false), the call blocks
            % execution until a new frame is available. If block is false, 
            % a new frame is returned if available, otherwise the last one
            % is returned.
            
            available = obj.camera.hasFrame;
            obj.mFrame = obj.camera.getFrame(varargin{:});
            frame = obj.frame;
            if available
                obj.invoke('Frame', frame);
            end
        end
        
        function set.mirror(obj, mirror)
            if numel(mirror) == 2 && islogical(mirror)
                obj.mMirror = mirror;
            else
                error('Value provided for mirror is invalid.');
            end
            obj.invoke('Mirror');
        end
        
        function mirror = get.mirror(obj)
            mirror = obj.mMirror;
        end
        
        function set.resolution(obj, resolution)
            resolution = resolution(:);
            index = find(all(obj.resolutionList == resolution, 1), 1);
            if isempty(index)
                error('Invalid resolution');
            else
                obj.resolutionIndex = index;
            end
        end
        
        function resolution = get.resolution(obj)
            resolution = obj.resolutionList(:, obj.resolutionIndex);
        end
        
        function set.resolutionIndex(obj, index)
            obj.camera.resolutionIndex = index;
        end
        
        function index = get.resolutionIndex(obj)
            index = obj.camera.resolutionIndex;
        end
        
        function list = get.resolutionList(obj)
            list = obj.camera.resolutionList;
        end
        
        function set.exposure(obj, exposure)
            obj.camera.exposure = exposure;
            obj.invoke('Exposure');
        end
        
        function exposure = get.exposure(obj)
            exposure = obj.camera.exposure;
        end
        
        function range = get.exposureRange(obj)
            range = obj.camera.exposureRange;
        end
    end
    
    methods (Access = private)
        function loop(obj)
            if obj.play && obj.camera.hasFrame
                obj.mFrame = obj.camera.getFrame();
                obj.invoke('Frame', obj.frame);
            end
        end
    end
    
    methods (Static)
        function n = count()
            % Camera.count()
            % Return the number of recognized video resources.
            
            list = webcamlist();
            n = numel(list);
        end
    end
end