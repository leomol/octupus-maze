% VirtualTracker - Controller for 2D tasks relaying on video tracking.
% Track target(s) with an overhead camera and invoke callbacks when they
% enter virtual zones on a trial basis.
% 
% VirtualTracker methods:
%   VirtualTracker  - Create a VirtualTracker  object.
%   delete          - Close GUIs and delete object from memory.
%   save            - Write to disk data acquired during current setup.
%   setup           - Configure trial.
%
% VirtualTracker events:
%   Position(position) - Position of targets changed.
%   Roi(roi)           - Region of interest changed.
% 
%   where position is a  struct with fields X and Y with coordinates of
%   tracked pointers; and roi is the region of interest.
%   
% Data is saved to disk as a CSV file with 6 columns:
%   time, x-coordinate, y-coordinate, pointer id, zone id, trial number.
%   Trial number increases after methods save and setup are called (if data
%   any data was acquired during the last setup call).
%   
%   For example:
%     time,   x,   y, zone, pointer, trial,
%     0.10, 0.3, 0.3,    0,       1,     1,
%     0.20, 0.4, 0.4,    0,       1,     1,
%     0.30, 0.5, 0.5,    1,       1,     1,
%     0.40, 0.6, 0.6,    1,       1,     1,
% 
% Notes:
%   You must have webcam support in order to use this class. You can use the
%   Add-Ons explorer to install it, or download it directly from the link below:
%   https://www.mathworks.com/matlabcentral/fileexchange/45182-matlab-support-package-for-usb-webcams
% 
%   Please note that these classes are in early stages and are provided "as is"
%   and "with all faults". You should test throughly for proper execution and
%   proper data output before running any behavioral experiments.
% 
%   Tested on MATLAB 2018a.
% 
% See also Events, VirtualTracker.GUI, VirtualTracker.example, CircularMaze, LinearMaze, TwoChoice.

% 2016-09-02. Leonardo Molina.
% 2018-09-24. Last modified.
classdef VirtualTracker < Event
    properties (Dependent)
        % play - Start/stop video acquisition.
        play
        
        % position - Position for all pointers: x1, y1, x2, y2, ...
        position
        
        % roi - Delimit the tracking area by a region.
        % region is a polygon [x1, y1, x2, y2, ...] with normalized values,
        % referenced to the center of the image.
        roi
    end
    
    properties (SetAccess = private)
        % camera - Camera handle.
        camera
        
        % trial - Curren trial number.
        trial = 1
        
        % tracker - Tracker handle.
        tracker
    end
    
    properties (SetAccess = private, Hidden)
        % output - Output filename where data will be saved.
        output
    end
    
    properties (Access = private)
        callbacks = {}                  % Callback for each region.
        data = zeros(5, 0)              % Data for this trial: time, x, y, pointer, zone. 
        interpolate = false             % Interpolate between two positions (expect side effects).
        regions = {}                    % Region for each each callback.
        saved = false                   % Whether current trial has been saved.
        session                         % Session name.
        states = false(0, 0)            % State (in/out) for all pointers and zones.
        startTime                       % Startup time.
        targetHandles = {}              % Handle to target manager.
        target                          % Target handle.
        
        mPlay = false                   % Playing state.
        mPosition = zeros(2, 1)
        mRoi                            % Region of interest for tracking.
    end
    
    methods
        function obj = VirtualTracker(cameraId)
            % VirtualTracker(cameraId)
            % Create a VirtualTracker object with the given camera id.
            
            if nargin > 0
                if nargin < 2
                    cameraId = 1;
                end
                obj.initialize(Tracker(), Camera(cameraId));
                obj.register('Close', @obj.delete);
            else
                % Allow a default constructor so that children may inherit 
                % without side effects since MATLAB forcibly calls it when
                % constructing a subclass.
            end
        end
        
        function delete(obj)
            % VirtualTracker.delete()
            % Save last trial and release resources.
            
            delete(obj.tracker);
            delete(obj.camera);
        end
        
        function setup(obj, varargin)
            % VirtualTracker.setup(region1, callback1, region2, callback2, ...)
            % Configure zones as pairs of regions and callbacks.
            % Regions are x- and y- coordinates referenced to the center and
            % normalized to the smallest between the height and width of the
            % image.
            % Callbacks are function handles that take at lease one argument,
            % a structure with the coordinates and the state of a collision.
            
            % Trials end when data is saved and another setup occurs.
            if obj.saved
                obj.saved = false;
                obj.trial = obj.trial + 1;
            end
            
            obj.regions = varargin(1:2:end);
            obj.callbacks = varargin(2:2:end);
            
            n1s = size(obj.states, 1);
            n2s = numel(obj.regions);
            d = n2s - n1s;
            if d > 0
                obj.states(n1s + 1:n1s + d, :) = false;
            else
                obj.states(n2s + 1:n1s, :) = false;
            end
            
            obj.data = zeros(5, 0);
            Objects.delete(obj.targetHandles{:});
            for r = 1:numel(obj.regions)
                [xs, ys] = Tools.region(obj.regions{r}, 360);
                obj.targetHandles{r} = obj.target.add(xs, ys, 1 / max(obj.camera.resolution), obj.callbacks{r});
            end
        end
        
        function save(obj)
            % VirtualTracker.save()
            % Save new data to disk. The output file is appended with new data.
            
            nTrialData = size(obj.data, 2);
            if nTrialData >= 1
                if nTrialData == 1
                    if isempty(obj.output)
                        % Create log file.
                        className = mfilename('class');
                        root = getenv('USERPROFILE');
                        folder = fullfile(root, 'Documents', className);
                        if exist(folder, 'dir') ~= 7
                            mkdir(folder);
                        end
                        obj.output = fullfile(folder, sprintf('%s.csv', obj.session));
                    end
                    % Save file header.
                    fid = fopen(obj.output, 'a');
                    fprintf(fid, 'time, x, y, pointer, zone, trial\n');
                    fclose(fid);
                end
                
                % Prepare data for saving: time, x, y, pointer, zone, trial.
                body = [obj.data; repmat(obj.trial, 1, nTrialData)];
                % Save and release files.
                fid = fopen(obj.output, 'a');
                fprintf(fid, '%.4f, %.4f, %.4f, %i, %i, %i\n', body);
                fclose(fid);
                obj.saved = true;
                obj.data = zeros(5, 0);
            end
        end
        
        function play = get.play(obj)
            play = obj.camera.play;
        end
        
        function set.play(obj, play)
            obj.camera.play = play;
        end
        
        function position = get.position(obj)
            position = obj.mPosition;
        end
        
        function roi = get.roi(obj)
            roi = obj.mRoi;
        end
        
        function set.roi(obj, region)
            obj.mRoi = region;
            obj.tracker.roi = region;
        end
    end
    
    methods (Access = protected)
        function initialize(obj, tracker, camera, output)
            % VirtualTracker.initialize(tracker, camera, <output>)
            % Initialize the object with the given tracker and camera.
            % Children of this class may replace the default Tracker and Camera
            % objects with other interfaces of this type (e.g. Tracker.GUI and
            % Camera.GUI).
            % Optionally, choose the output filename.
            
            obj.tracker = tracker;
            obj.camera = camera;
            obj.target = Target();
            obj.tracker.register('Roi', @obj.tmp);
            
            % Read position at every frame.
            obj.camera.register('Frame', @obj.onFrame);
            
            if nargin < 4
                obj.output = [];
            else
                obj.output = output;
            end
            obj.session = sprintf('VT%s', datestr(now, 'yyyymmddHHMMSS'));
            
            obj.startTime = tic;
        end
        
        function tmp(obj, roi)
            obj.invoke('Roi', roi);
        end
    end
    
    methods (Access = private)
        function onFrame(obj, frame)
            % VirtualTracker.onFrame(frame)
            % Camera's callback when a new frame is acquired.
            % Track position for this frame and test for collisions.
            
            % Track position.
            pointers = obj.tracker.track(frame);
            % Change from pixels to normalized units.
            [xs, ys] = Tools.normalize(pointers(1:2:end), pointers(2:2:end), obj.camera.resolution(2), obj.camera.resolution(1));
            obj.step(xs, ys);
        end
    end
    
    methods (Access = protected)
        function step(obj, xs, ys)
            
            x1s = obj.position(1:2:end);
            y1s = obj.position(2:2:end);
            n1s = numel(x1s);
            x2s = xs(:)';
            y2s = ys(:)';
            n2s = numel(x2s);
            obj.mPosition = [x2s; y2s];
            % Resize position vectors to accomodate all pointers.
            d = n2s - n1s;
            if d > 0
                x1s(n1s + 1:n1s + d) = x2s(n1s + 1:n2s);
                y1s(n1s + 1:n1s + d) = y2s(n1s + 1:n2s);
                obj.states(:, n1s + 1:n1s + d) = false;
            else
                obj.states(:, n2s + 1:n1s) = false;
            end

            handles = obj.targetHandles;
            time = toc(obj.startTime);
            for p = 1:n2s
                % For each pointer.
                if obj.interpolate
                    states2 = obj.target.test([x1s(p), x2s(p)], [y1s(p), y2s(p)], [false, false]);
                else
                    states2 = obj.target.test(x2s(p), y2s(p), [false, false]);
                end
                nRegions = numel(states2);
                for r = 1:nRegions
                    % For each region.
                    state2 = states2(r);
                    if state2
                        % Currently inside a zone.
                        zone = r;
                        if ~obj.states(r, p)
                            % Previously outside a zone.
                            obj.states(r, p) = true;
                            Callbacks.invoke(obj.callbacks{r}, struct('X', x2s(p), 'Y', y2s(p), 'State', true, 'Handle', handles{r}));
                        end
                    else
                        % Currently outsize a zone.
                        zone = 0;
                        if obj.states(r, p)
                            % Previously inside a zone.
                            obj.states(r, p) = false;
                            Callbacks.invoke(obj.callbacks{r}, struct('X', x2s(p), 'Y', y2s(p), 'State', false, 'Handle', handles{r}));
                        end
                    end
                    % Append trial data.
                    obj.data(:, end + 1) = [time; x2s(p); y2s(p); p; zone];
                end
            end
            % Notify clients of a change in position.
            obj.mPosition = [x2s; y2s];
            obj.invoke('Position', struct('X', x2s, 'Y', y2s));
        end
    end
end