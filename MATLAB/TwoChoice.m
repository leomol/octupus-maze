% TwoChoice - Controller for a behavioral task dependent on video tracking.
% 
% Track subject with a webcam, open/close gates and trigger rewards/tones to
% guide behavior while logging and syncing with an external data acquisition
% system (e.g. electrophysiology) in a choice task.
% 
% Task:
%   Refer to the octupus maze diagram. Subject starts at the N or S arms of
%   the maze and takes a reward. According to a contingency table, chooses 
%   to or is forced to take a left or a right turn, for a reward. Then either
%   starts a new trial at the starting point or chooses to go to the opposite
%   side of the maze.
% 
% TwoChoice methods:
%   delete                   - Close figure and release resources.
%   log                      - Create a log entry using the same syntax as sprintf.
%   note                     - Print on screen and log using the same syntax as sprintf.
%   print                    - Print on screen using the same syntax as sprintf.
%   reward                   - Send a pulse to an Arduino Pin for the given duration (seconds).
%   setByte                  - Write an 8-bit number in the port F of Arduino.
%   tone                     - Play a tone with the given frequency (Hz) and duration (seconds) in a designated pin in Arduino.
%   trial                    - Trigger a new trial.
%   
% TwoChoice properties:
%   contingencies            - Probabilities for left/right paths and rewards.
%   contingenciesRepetitions - Number of trials with the same feeder probability.
%   errorTone                - Frequency and duration of an error tone.
%   freePathProbability      - Probability of issuing a free choice.
%   halfMazeRepetitions      - Number of trials in either south or north halves of the maze.
%   rewardAmount             - Reward volume in 3rds of a feeder cup.
%   sideFeederDelayRange     - Delay before a reward is issued.
%   successTone              - Frequency and duration of a success tone.
% 
% Please note that these classes are in early stages and are provided "as is"
% and "with all faults". You should test throughly for proper execution and
% proper data output before running any behavioral experiments.
% 
% Tested on MATLAB 2018a.
% 
% See also TwoChoice, CircularMaze, LinearMaze, VirtualTracker.GUI.

% 2017-12-13. Leonardo Molina.
% 2018-09-27. Last modified.
classdef TwoChoice < handle
    properties (Access = public)
        % folder - Where to store the log file.
        folder = 'Documents/TwoChoice'
        
        % errorIntertrialDuration - Intertrial duration during an error.
        errorIntertrialDuration = 5
        
        % errorTone - Frequency and duration for an error tone.
        errorTone = [1750, 2]
        
        % successTone - Frequency and duration for a success tone.
        successTone = [2250, 0.25]
        
        % freePathProbability - Probability of issuing a free choice.
        % The complement is a forced choice.
        freePathProbability = 0.5
        
        % contingencies - Probabilities for left/right paths and rewards.
        % A new column is read every 'contingenciesRepetitions' trials.
        % 1st value:
        %   Probability of forced left path (when a forced choice is active).
        %   The complement is the probability of going right.
        % 2nd value:
        %   The probability of rewarding the left feeder.
        % 3rd value:
        %   The probability of rewarding the right feeder.
        contingencies = [0.7, 0.3
                         0.7, 0.3
                         0.3, 0.7]
                     
        % contingenciesRepetitions - Number of trials with the same feeder probability.
        contingenciesRepetitions = 4
        
        % halfMazeRepetitions - Number of trials in South or North halves of the maze.
        halfMazeRepetitions = 8
        
        % rewardAmount - Reward volume in 3rds of a feeder cup.
        rewardAmount = 1
        
        % servoDuration - Disengage a servo motor after a given duration.
        servoDuration = 1.000
        
        % sideFeederDelayRange - Enforce a delay before a reward is issued, 
        % with a duration randomly sampled from the given range.
        sideFeederDelayRange = [0, 0.5]
    end
    
    properties (GetAccess = public, SetAccess = private)
        % fid - Log file identifier.
        fid
        
        % filename - Name of the log file.
        filename
        
        % stage - Behavioral stage.
        stage
        
        % startTime - Reference to time at start.
        startTime
        
        % trialNumber - Trial id.
        trialNumber = 0
    end
    
    properties (Access = private)
        % scheduler - Scheduler object for non-blocking pauses.
        scheduler
        
        % className - Name of this class.
        className
        
        % states - Miscellaneous states for behavioral control.
        %   switchingHalves - Flag informing about switching south-north.
        %   southHalf: Which half south or north is currently active.
        %   feederS.available: Whether the South feeder is enabled.
        %   feederN.available: Whether the South feeder is enabled.
        states
        
        % timedFeederW/timedFeederE - Handle to timing object for claiming rewards.
        timedFeederW
        timedFeederE
    end
    
    properties (Constant)
        % programVersion - Version of this class.
        programVersion = '20180924'
    end
    
    properties (Hidden)
        % virtualTracker - Tracker GUI object.
        virtualTracker
        
        % bridge - Bridge object connecting with the Arduino.
        bridge
        
        % servoMotor - Interface to control servo motors.
        servoMotor
    end
    
    methods
        function obj = TwoChoice(comID, cameraID)
            % TwoChoice(comID, cameraID)
            % Controller for a two-choice task. Gets the position of a target
            % using a webcam with cameraID (1 to n cameras connected) and an
            % Arduino with comID to read inputs from feeder ports and trigger
            % rewards and open/close doors in a maze.
            
            % Name of this class.
            obj.className = mfilename('class');
            
            % Task scheduler.
            obj.scheduler = Scheduler();
            
            % Log file.
            root = getenv('USERPROFILE');
            target = fullfile(root, obj.folder);
            if exist(target, 'dir') ~= 7
                mkdir(target);
            end
            session = sprintf('VM%s', datestr(now, 'yyyymmddHHMMSS'));
            obj.filename = fullfile(target, sprintf('%s.csv', session));
            obj.fid = fopen(obj.filename, 'a');
            obj.startTime = tic;
            
            % Log program version, filename and session id.
            obj.log('version,%s,%s', obj.className, TwoChoice.programVersion);
            obj.log('filename,%s', obj.filename);
            obj.log('session,%s', session);
            
            % Log settings to disk.
            parameters = {
                'rewardAmount', 'sideFeederDelayRange', ...
                'successTone', ...
                'errorIntertrialDuration', 'errorTone', ...
                'freePathProbability', 'contingencies', 'contingenciesRepetitions', ...
                'halfMazeRepetitions'};
            for f = 1:numel(parameters)
                fieldname = parameters{f};
                value = obj.(fieldname);
                if ischar(value)
                else
                    if isequal(value, round(value))
                        value = strtrim(sprintf('%i ', value));
                    else
                        value = strtrim(sprintf('%.4f ', value));
                    end
                end
                obj.log('setting,%s,%s', fieldname, value);
            end
            
            % Initial control states.
            obj.states.feederS.available = true;
            obj.states.feederN.available = true;
            obj.states.southHalf = true;
            obj.states.switchingHalves = false;
            obj.states.mode = TwoChoice.Modes.FreeChoice;
            obj.states.choice = TwoChoice.Choices.X;
            obj.states.ready = false;
            
            % Show version and session name on screen.
            obj.print('Version %s %s', obj.className, TwoChoice.programVersion);
            obj.print('Session "%s"', session);
            
            % Time West and East feeder pokes.
            % Default configuration for a timed feeder.
            inside = false;
            enterDelay = 0;
            enterTimeout = Inf;
            holdDelay = 0;
            exitDelay = 0;
            exitTimeout = Inf;
            obj.timedFeederW = Delay(inside, enterDelay, enterTimeout, holdDelay, exitDelay, exitTimeout, {@obj.onTimedPoke, TwoChoice.Sources.FeederW});
            obj.timedFeederE = Delay(inside, enterDelay, enterTimeout, holdDelay, exitDelay, exitTimeout, {@obj.onTimedPoke, TwoChoice.Sources.FeederE});
            
            % Setup Arduino.
            obj.bridge = Bridge(comID);
            
            % Behavior is enabled after a successful connection.
            obj.bridge.register('ConnectionChanged', @obj.onBridgeConnection);
            
            % Listen to feeder pokes.
            obj.bridge.register(TwoChoice.PinOut.FeederS.pokePin, {@obj.onPoke, TwoChoice.Sources.FeederS});
            obj.bridge.register(TwoChoice.PinOut.FeederN.pokePin, {@obj.onPoke, TwoChoice.Sources.FeederN});
            obj.bridge.register(TwoChoice.PinOut.FeederW.pokePin, {@obj.onPoke, TwoChoice.Sources.FeederW});
            obj.bridge.register(TwoChoice.PinOut.FeederE.pokePin, {@obj.onPoke, TwoChoice.Sources.FeederE});
            
            % Control servo motors using generic settings and angles.
            obj.servoMotor = Bridge.ServoMotor(obj.bridge);
            
            % Video tracker zones are used to close doors behind the subject.
            circle = @(x, y) [-0.125 + x, y, x + 0.125, y];
            x = +0.05;
            y = -0.09;
            zoneC  = circle( 0.0000 + x,  0.0000 + y);
            zoneNE = circle(+0.4250 + x, -0.2575 + y);
            zoneSW = circle(-0.4250 + x, +0.2575 + y);
            zoneNW = circle(+0.4250 + x, +0.2575 + y);
            zoneSE = circle(-0.4250 + x, -0.2575 + y);
            
            zones = ...
            { ...
                00, zoneC,  {@obj.onZone,  TwoChoice.Sources.ZoneC}, ...
                00, zoneNE, {@obj.onZone, TwoChoice.Sources.ZoneNE}, ...
                00, zoneSW, {@obj.onZone, TwoChoice.Sources.ZoneSW}, ...
                00, zoneNW, {@obj.onZone, TwoChoice.Sources.ZoneNW}, ...
                00, zoneSE, {@obj.onZone, TwoChoice.Sources.ZoneSE}  ...
            };
            % Start video tracker.
            obj.virtualTracker = VirtualTracker.GUI(cameraID);
            % Hide figures until all settings have been applied.
            figures = findobj('type', 'figure');
            set(figures, 'Visible', 'off');
            % Show a heatmap; peaks indicate closest match.
            obj.virtualTracker.renderMode = 'weights';
            % Perform computations in a resized version of the image.
            obj.virtualTracker.tracker.resize = 75;
            % Total pixel population.
            obj.virtualTracker.tracker.population = 0.005;
            % Size of target blob.
            obj.virtualTracker.tracker.area = 0.20;
            % Process only a region of the image.
            obj.virtualTracker.tracker.roi = [-0.65 + x, -0.48 + y, +0.65 + x, -0.48 + y, +0.65 + x, +0.48 + y, -0.65 + x, +0.48 + y];
            % Target is bright.
            obj.virtualTracker.tracker.hue = -2;
            % Invoke functions when a target enters/exits a zone.
            obj.virtualTracker.zones = zones;
            % Mirror image left to right, but not top to bottom.
            obj.virtualTracker.camera.mirror = [true, false];
            % Show figure again.
            set(figures, 'Visible', 'on');
            
            % Listen to every position change.
            obj.virtualTracker.register('Position', @obj.onPosition);
            
            % Release resources when window is closed.
            obj.virtualTracker.register('Close', @obj.onClose);
            
            % Start Arduino.
            obj.bridge.start();
            
            % Close all doors except West and East which guard reward feeders.
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorS.channel,  TwoChoice.PinOut.DoorS.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorN.channel,  TwoChoice.PinOut.DoorN.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorW.channel,  TwoChoice.PinOut.DoorW.opened, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorE.channel,  TwoChoice.PinOut.DoorE.opened, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorL.channel,  TwoChoice.PinOut.DoorL.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorR.channel,  TwoChoice.PinOut.DoorR.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorSL.channel, TwoChoice.PinOut.DoorSL.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorSR.channel, TwoChoice.PinOut.DoorSR.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorNL.channel, TwoChoice.PinOut.DoorNL.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorNR.channel, TwoChoice.PinOut.DoorNR.closed, obj.servoDuration);
            
            obj.servoMotor.register('Idle', @obj.onReady);
        end
        
        function delete(obj)
            % TwoChoice.delete()
            % Close figure and release resources.
            
            obj.onClose();
        end
        
        function log(obj, format, varargin)
            % TwoChoice.log(format, arg1, arg2, ...)
            % Create a log entry using the same syntax as sprintf.
            
            fprintf(obj.fid, '%.2f,%s\n', toc(obj.startTime), sprintf(format, varargin{:}));
        end
        
        function note(obj, format, varargin)
            % TwoChoice.note(format, arg1, arg2, ...)
            % Print on screen and log using the same syntax as sprintf.
            
            obj.log(['note,' format], varargin{:});
            obj.print(format, varargin{:});
        end
        
        function print(obj, format, varargin)
            % TwoChoice.print(format, arg1, arg2, ...)
            % Print on screen using the same syntax as sprintf.
            
            fprintf(['[%.1f] ' format '\n'], toc(obj.startTime), varargin{:});
        end
        
        function reward(obj, pin, duration)
            % TwoChoice.reward(pin, duration)
            % Send a pulse to an Arduino Pin for the given duration (seconds).
            
            % Valve switches on with a LOW pulse.
            obj.bridge.setPulse(pin, 0, round(1e6 * duration), 0, 1);
            obj.log('reward,%i,%.2f', pin, duration);
        end
        
        function setByte(obj, value)
            % TwoChoice.setByte(value)
            % Write an 8-bit number in the port F of Arduino.
            % Port F consists of pins 54 to 61 (A0 to A7) of the Arduino Mega.
            % This port can be fed to a data acquisition system such as the Digital Lynx
            % to synchronize trial number with electrophysiological measurements.
            
            if value >= 0 && value <= 255
                % PORTF is at address HEX=0x31, DEC=49.
                obj.bridge.setAddress(49, value);
            else
                error('"PORTK" expects an 8-bit value (0 to 255).');
            end
        end
        
        function tone(obj, frequency, duration)
            % TwoChoice.tone(frequency, duration)
            % Play a tone with the given frequency (Hz) and duration (seconds) in a designated pin in Arduino.
            
            obj.bridge.setTone(TwoChoice.PinOut.Speaker, round(frequency), round(1e6 * duration));
            obj.log('tone,%.2f,%.2f', frequency, duration);
        end
        
        function trial(obj)
            % TwoChoice.trial()
            % Trigger a new trial.
            
            % Increase trial number.
            obj.trialNumber = obj.trialNumber + 1;
            
            % Enable switching sides (North/South) after a given number of trials.
            obj.states.switchingHalves = mod(obj.trialNumber, obj.halfMazeRepetitions) == 0;
            
            % Output trial number to pins A8 to A15 of the Arduino (wrap around 8 bits).
            obj.setByte(mod(obj.trialNumber - 1, 255) + 1);
            
            % Default configuration for a timed feeder.
            % See Delay and Delay.Stages.
            inside = false;
            enterDelay = 0;
            enterTimeout = Inf;
            exitDelay = 0;
            exitTimeout = Inf;
            if obj.states.switchingHalves
                % If switching halves in this trial, disable hold errors.
                holdDelay = 0;
            else
                % Otherwise, choose a minimum wait time randomly.
                holdDelay = rand() * diff(obj.sideFeederDelayRange) + obj.sideFeederDelayRange(1);
            end
            obj.print('Required to poke feeder for %.2fs.', holdDelay);
            
            % Force left or right paths, or else allow free choice.
            if obj.states.switchingHalves || rand() <= obj.freePathProbability
                % Open left and right doors. Enable both feeders.
                obj.print('Trial #%i: Free choice.', obj.trialNumber);
                obj.log('trial,%i,free-choice', obj.trialNumber);
                obj.states.mode = TwoChoice.Modes.FreeChoice;
                Objects.delete(obj.timedFeederW);
                obj.timedFeederW = Delay(inside, enterDelay, enterTimeout, holdDelay, exitDelay, exitTimeout, {@obj.onTimedPoke, TwoChoice.Sources.FeederW});
                Objects.delete(obj.timedFeederE);
                obj.timedFeederE = Delay(inside, enterDelay, enterTimeout, holdDelay, exitDelay, exitTimeout, {@obj.onTimedPoke, TwoChoice.Sources.FeederE});
                obj.servoMotor.set(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.opened, obj.servoDuration);
                obj.servoMotor.set(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.opened, obj.servoDuration);
            else
                % Active column in the contingencies table.
                nColumns = size(obj.contingencies, 2);
                column = mod(ceil(obj.trialNumber .* 1 / obj.contingenciesRepetitions) - 1, nColumns) + 1;
                leftPathProbability = obj.contingencies(1, column);
                if rand() <= leftPathProbability
                    % Open left door. Only enable left feeder.
                    obj.print('Trial #%i: Forced left.', obj.trialNumber);
                    obj.log('trial,%i,forced-left', obj.trialNumber);
                    obj.states.mode = TwoChoice.Modes.ForcedLeft;
                    if obj.states.southHalf
                        Objects.delete(obj.timedFeederW);
                        obj.timedFeederW = Delay(inside, enterDelay, enterTimeout, holdDelay, exitDelay, exitTimeout, {@obj.onTimedPoke, TwoChoice.Sources.FeederW});
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.closed, obj.servoDuration);
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.opened, obj.servoDuration);
                    else
                        Objects.delete(obj.timedFeederE);
                        obj.timedFeederE = Delay(inside, enterDelay, enterTimeout, holdDelay, exitDelay, exitTimeout, {@obj.onTimedPoke, TwoChoice.Sources.FeederE});
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.closed, obj.servoDuration);
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.opened, obj.servoDuration);
                    end
                else
                    % Open right door. Only enable right feeder.
                    obj.print('Trial #%i: Forced right.', obj.trialNumber);
                    obj.log('trial,%i,forced-right', obj.trialNumber);
                    obj.states.mode = TwoChoice.Modes.ForcedRight;
                    if obj.states.southHalf
                        Objects.delete(obj.timedFeederE);
                        obj.timedFeederE = Delay(inside, enterDelay, enterTimeout, holdDelay, exitDelay, exitTimeout, {@obj.onTimedPoke, TwoChoice.Sources.FeederE});
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.closed, obj.servoDuration);
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.opened, obj.servoDuration);
                    else
                        Objects.delete(obj.timedFeederW);
                        obj.timedFeederW = Delay(inside, enterDelay, enterTimeout, holdDelay, exitDelay, exitTimeout, {@obj.onTimedPoke, TwoChoice.Sources.FeederW});
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.closed, obj.servoDuration);
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.opened, obj.servoDuration);
                    end
                end
            end
            
            % Open door ahead. Next stage: Reach center zone.
            if obj.states.southHalf
                obj.servoMotor.schedule(TwoChoice.PinOut.DoorS.channel, TwoChoice.PinOut.DoorS.opened, obj.servoDuration);
            else
                obj.servoMotor.schedule(TwoChoice.PinOut.DoorN.channel, TwoChoice.PinOut.DoorN.opened, obj.servoDuration);
            end
            
            % Reset current choice.
            obj.states.choice = TwoChoice.Choices.X;
        end
    end
    
    methods (Access = private)
        function activatePath(obj, choice)
            % TwoChoice.activatePath(TwoChoice.Paths)
            % Open doors to access outer paths in the maze.
            
            switch choice
                case TwoChoice.Paths.SW
                    obj.servoMotor.schedule(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.opened, obj.servoDuration);
                    obj.servoMotor.schedule(TwoChoice.PinOut.DoorSL.channel, TwoChoice.PinOut.DoorSL.opened, obj.servoDuration);
                case TwoChoice.Paths.NW
                    obj.servoMotor.schedule(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.opened, obj.servoDuration);
                    obj.servoMotor.schedule(TwoChoice.PinOut.DoorNL.channel, TwoChoice.PinOut.DoorNL.opened, obj.servoDuration);
                case TwoChoice.Paths.SE
                    obj.servoMotor.schedule(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.opened, obj.servoDuration);
                    obj.servoMotor.schedule(TwoChoice.PinOut.DoorSR.channel, TwoChoice.PinOut.DoorSR.opened, obj.servoDuration);
                case TwoChoice.Paths.NE
                    obj.servoMotor.schedule(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.opened, obj.servoDuration);
                    obj.servoMotor.schedule(TwoChoice.PinOut.DoorNR.channel, TwoChoice.PinOut.DoorNR.opened, obj.servoDuration);
            end
        end
        
        function onBridgeConnection(obj, connected)
            % TwoChoice.onBridgeConnection(connected)
            % Setup Arduino when connected.
            
            if connected
                obj.print('Arduino: Connected.');
                obj.log('arduino,connection,true');
                
                % Trial number will be written in a dedicated port in the Arduino.
                % Prepare PORTF (Pins A0 to A7) for direct manipulation.
                % DDRF is at address HEX=0x30, DEC=48.
                % Set pins to outputs with HEX=0xFF, DEC=255.
                obj.bridge.setAddress(48, 255);
                
                % Setup poke and lick sensors.
                obj.bridge.register('DataReceived', @obj.onBridgeData);
                names = {'FeederS', 'FeederN', 'FeederW', 'FeederE', 'FeederSW', 'FeederNE', 'FeederSE', 'FeederNW'};
                for f = 1:numel(names)
                    name = names{f};
                    feeder = TwoChoice.PinOut.(name);
                    obj.bridge.getBinary(feeder.pokePin, 0, 0, 1);
                    obj.bridge.getBinary(feeder.lickPin, 0, 0, 1);
                end
            else
                obj.print('Arduino: Disconnected.');
                obj.log('arduino,connection,false');
            end
        end
        
        function onBridgeData(obj, data)
            % TwoChoice.onBridgeData(data)
            % Parse data received from Arduino.
            
            % Ignore pin state during setup.
            if data.State && data.Count > 0
                % Always log licks.
                switch data.Pin
                    case TwoChoice.PinOut.FeederW.lickPin
                        obj.log('lick,FeederW');
                    case TwoChoice.PinOut.FeederE.lickPin
                        obj.log('lick,FeederE');
                    case TwoChoice.PinOut.FeederS.lickPin
                        obj.log('lick,FeederS');
                    case TwoChoice.PinOut.FeederN.lickPin
                        obj.log('lick,FeederN');
                end
            end
        end
        
        function onClose(obj)
            % TwoChoice.onClose(tracker)
            % Video tracker window closed. Release all resources.
            
            Objects.delete(obj.scheduler);
            Objects.delete(obj.bridge);
            Objects.delete(obj.virtualTracker);
            if isvalid(obj) && isnumeric(obj.fid)
                fclose(obj.fid);
            end
            
            obj.print('Terminated.');
        end
        
        function onPoke(obj, source, data)
            % TwoChoice.onPoke()
            % West or East feeders need to be poked timely; North or South
            % feeders do not.
            % Poking South feeder re-enables North feeder and vice-versa.
            
            if data.Count > 0
                % Ignore pin state during setup.
                switch source
                    case TwoChoice.Sources.FeederS
                        obj.states.feederN.available = true;
                        if data.State && obj.states.feederS.available
                            obj.states.feederS.available = false;
                            % Poking north or south feeders trigger a reward and produce a new trial.
                            % Always reward at the start feeder.
                            obj.tone(obj.successTone(1), obj.successTone(2));
                            obj.reward(TwoChoice.PinOut.FeederS.valvePin, obj.rewardAmount * TwoChoice.PinOut.FeederS.valveDuration);
                            % Close doors behind.
                            if obj.states.choice == TwoChoice.Choices.W
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorSL.channel, TwoChoice.PinOut.DoorSL.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.closed, obj.servoDuration);
                            elseif obj.states.choice == TwoChoice.Choices.E
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorSR.channel, TwoChoice.PinOut.DoorSR.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.closed, obj.servoDuration);
                            else
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorSL.channel, TwoChoice.PinOut.DoorSL.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorSR.channel, TwoChoice.PinOut.DoorSR.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.closed, obj.servoDuration);
                            end
                            obj.print('South feeder: Rewarded.');
                            obj.log('feeder,FeederS,reward');
                            
                            issueTrial = true;
                        else
                            issueTrial = false;
                        end
                        % Close doors behind.
                        if ~obj.states.southHalf || obj.states.switchingHalves
                            if obj.states.choice == TwoChoice.Choices.W
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorNL.channel, TwoChoice.PinOut.DoorNL.closed, obj.servoDuration);
                            else
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorNR.channel, TwoChoice.PinOut.DoorNR.closed, obj.servoDuration);
                            end
                            obj.servoMotor.schedule(TwoChoice.PinOut.DoorN.channel, TwoChoice.PinOut.DoorN.closed, obj.servoDuration);
                        end
                        obj.states.southHalf = true;
                        if issueTrial
                            obj.trial();
                        end
                    case TwoChoice.Sources.FeederN
                        obj.states.feederS.available = true;
                        if data.State && obj.states.feederN.available
                            obj.states.feederN.available = false;
                            % Poking north or south feeders trigger a reward and produce a new trial.
                            % Always reward at the start feeder.
                            obj.tone(obj.successTone(1), obj.successTone(2));
                            obj.reward(TwoChoice.PinOut.FeederN.valvePin, obj.rewardAmount * TwoChoice.PinOut.FeederN.valveDuration);
                            % Close doors behind.
                            if obj.states.choice == TwoChoice.Choices.W
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorNL.channel, TwoChoice.PinOut.DoorNL.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.closed, obj.servoDuration);
                            elseif obj.states.choice == TwoChoice.Choices.E
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorNR.channel, TwoChoice.PinOut.DoorNR.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.closed, obj.servoDuration);
                            else
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorNL.channel, TwoChoice.PinOut.DoorNL.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorNR.channel, TwoChoice.PinOut.DoorNR.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.closed, obj.servoDuration);
                            end
                            obj.print('North feeder: Rewarded.');
                            obj.log('feeder,FeederN,reward');
                            issueTrial = true;
                        else
                            issueTrial = false;
                        end
                        % Close doors behind.
                        if obj.states.southHalf || obj.states.switchingHalves
                            if obj.states.choice == TwoChoice.Choices.W
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorSL.channel, TwoChoice.PinOut.DoorSL.closed, obj.servoDuration);
                            else
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.closed, obj.servoDuration);
                                obj.servoMotor.schedule(TwoChoice.PinOut.DoorSR.channel, TwoChoice.PinOut.DoorSR.closed, obj.servoDuration);
                            end
                            obj.servoMotor.schedule(TwoChoice.PinOut.DoorS.channel, TwoChoice.PinOut.DoorS.closed, obj.servoDuration);
                        end
                        obj.states.southHalf = false;
                        if issueTrial
                            obj.trial();
                        end
                    case TwoChoice.Sources.FeederW
                        % Re-enable entries in North and South feeders.
                        obj.states.feederS.available = true;
                        obj.states.feederN.available = true;
                        % Check timing in West feeder.
                        obj.timedFeederW.step();
                    case TwoChoice.Sources.FeederE
                        % Re-enable entries in North and South feeders.
                        obj.states.feederS.available = true;
                        obj.states.feederN.available = true;
                        % Check timing in East feeder.
                        obj.timedFeederE.step();
                end
            end
        end
        
        function onPosition(obj, position)
            % TwoChoice.onPosition(position)
            % Camera tracker reported a change in position.
            
            obj.log('position,%.4f,%.4f', position.X, position.Y);
        end
        
        function onTimedPoke(obj, source, outcome)
            % TwoChoice.onTimedPoke()
            % Feeder state changed and is being tested for time accuracy.
            
            % Verbose log of interaction with feeder.
            % See Delay and Delay.Stages for more information.
            obj.log('feeder,%s,%s', source, outcome);
            
            switch source
                case TwoChoice.Sources.FeederW
                    switch outcome
                        case Delay.Stages.Entry
                            % Close doors behind as soon as a choice is made.
                            obj.states.choice = TwoChoice.Choices.W;
                            obj.servoMotor.schedule(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.closed, obj.servoDuration);
                            if obj.states.southHalf
                                obj.servoMotor.set(TwoChoice.PinOut.DoorS.channel, TwoChoice.PinOut.DoorS.closed, obj.servoDuration);
                            else
                                obj.servoMotor.set(TwoChoice.PinOut.DoorN.channel, TwoChoice.PinOut.DoorN.closed, obj.servoDuration);
                            end
                        case {Delay.Stages.EarlyEntry, Delay.Stages.EarlyExit, Delay.Stages.NoEntry}
                            % Timing not respected.
                            obj.tone(obj.errorTone(1), obj.errorTone(2));
                            % Open doors after a timeout.
                            if obj.states.southHalf
                                obj.scheduler.delay({@obj.activatePath, TwoChoice.Paths.SW}, obj.errorIntertrialDuration);
                            else
                                obj.scheduler.delay({@obj.activatePath, TwoChoice.Paths.NW}, obj.errorIntertrialDuration);
                            end
                            % Re-enable entries in North and South feeders.
                            obj.states.feederS.available = true;
                            obj.states.feederN.available = true;
                            obj.print('West feeder: Missed.');
                            obj.log('feeder,FeederW,missed');
                        case Delay.Stages.Reached
                            % Timing was respected. A reward may trigger.
                            % Rotate column in the contingencies table after a number of trials.
                            nColumns = size(obj.contingencies, 2);
                            column = mod(ceil(obj.trialNumber .* 1 / obj.contingenciesRepetitions) - 1, nColumns) + 1;
                            % Chance of getting a reward.
                            leftRewardProbability = obj.contingencies(2, column);
                            % Get reward according to chance, except if switching maze halves.
                            rnd = rand();
                            if obj.states.switchingHalves || rnd <= leftRewardProbability
                                obj.reward(TwoChoice.PinOut.FeederW.valvePin, obj.rewardAmount * TwoChoice.PinOut.FeederW.valveDuration);
                                obj.tone(obj.successTone(1), obj.successTone(2));
                                obj.print('West feeder: Rewarded.');
                                obj.log('feeder,FeederW,rewarded');
                            else
                                obj.tone(obj.errorTone(1), obj.errorTone(2));
                                obj.print('West feeder: Disabled (%.2f > %.2f).', rnd, leftRewardProbability);
                                obj.log('feeder,FeederW,disabled');
                            end
                            % Open doors inmediately.
                            if obj.states.southHalf
                                obj.activatePath(TwoChoice.Paths.SW);
                            else
                                obj.activatePath(TwoChoice.Paths.NW);
                            end
                            if obj.states.switchingHalves
                                % When switching halves, open doors in the opposite half of the maze.
                                if obj.states.southHalf
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.opened, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorNL.channel, TwoChoice.PinOut.DoorNL.opened, obj.servoDuration);
                                else
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.opened, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorSL.channel, TwoChoice.PinOut.DoorSL.opened, obj.servoDuration);
                                end
                                obj.print('Trial #%i: Choose half.', obj.trialNumber);
                                obj.log('trial,%i,choose-half');
                            end
                    end
                case TwoChoice.Sources.FeederE
                    switch outcome
                        case Delay.Stages.Entry
                            % Close doors behind as soon as a choice is made.
                            obj.states.choice = TwoChoice.Choices.E;
                            obj.servoMotor.schedule(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.closed, obj.servoDuration);
                            if obj.states.southHalf
                                obj.servoMotor.set(TwoChoice.PinOut.DoorS.channel, TwoChoice.PinOut.DoorS.closed, obj.servoDuration);
                            else
                                obj.servoMotor.set(TwoChoice.PinOut.DoorN.channel, TwoChoice.PinOut.DoorN.closed, obj.servoDuration);
                            end
                        case {Delay.Stages.EarlyEntry, Delay.Stages.EarlyExit, Delay.Stages.NoEntry}
                            % Timing not respected.
                            obj.tone(obj.errorTone(1), obj.errorTone(2));
                            % Open doors after a timeout.
                            if obj.states.southHalf
                                obj.scheduler.delay({@obj.activatePath, TwoChoice.Paths.SE}, obj.errorIntertrialDuration);
                            else
                                obj.scheduler.delay({@obj.activatePath, TwoChoice.Paths.NE}, obj.errorIntertrialDuration);
                            end
                            % Re-enable entries in North and South feeders.
                            obj.states.feederS.available = true;
                            obj.states.feederN.available = true;
                            obj.print('East feeder: Missed.');
                            obj.log('feeder,FeederE,missed');
                        case Delay.Stages.Reached
                            % Timing was respected. A reward may trigger.
                            % Rotate column in the contingencies table after a number of trials.
                            nColumns = size(obj.contingencies, 2);
                            column = mod(ceil(obj.trialNumber .* 1 / obj.contingenciesRepetitions) - 1, nColumns) + 1;
                            % Chance of getting a reward.
                            rightRewardProbability = obj.contingencies(3, column);
                            % Get reward according to chance, except if switching maze halves.
                            rnd = rand();
                            if obj.states.switchingHalves || rnd < rightRewardProbability
                                obj.reward(TwoChoice.PinOut.FeederE.valvePin, obj.rewardAmount * TwoChoice.PinOut.FeederE.valveDuration);
                                obj.tone(obj.successTone(1), obj.successTone(2));
                                obj.print('East feeder: Rewarded.');
                                obj.log('feeder,FeederE,rewarded');
                            else
                                obj.tone(obj.errorTone(1), obj.errorTone(2));
                                obj.print('East feeder: Disabled (%.2f > %.2f).', rnd, rightRewardProbability);
                                obj.log('feeder,FeederE,disabled');
                            end
                            % Open doors inmediately.
                            if obj.states.southHalf
                                obj.activatePath(TwoChoice.Paths.SE);
                            else
                                obj.activatePath(TwoChoice.Paths.NE);
                            end
                            if obj.states.switchingHalves
                                % When switching halves, open doors in the opposite half of the maze.
                                if obj.states.southHalf
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.opened, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorNR.channel, TwoChoice.PinOut.DoorNR.opened, obj.servoDuration);
                                else
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.opened, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorSR.channel, TwoChoice.PinOut.DoorSR.opened, obj.servoDuration);
                                end
                                obj.print('Trial #%i: Choose half.', obj.trialNumber);
                                obj.log('trial,%i,choose-half');
                            end
                    end
            end
        end
        
        function onZone(obj, source, data)
            % TwoChoice.onZone(zone, state)
            % Zone triggers are used exclusively to close doors behind path.
            
            obj.log('zone,%s,%s', source, data.State);
            if data.State
                switch source
                    case TwoChoice.Sources.ZoneC
                        if obj.states.southHalf
                            obj.servoMotor.schedule(TwoChoice.PinOut.DoorS.channel, TwoChoice.PinOut.DoorS.closed, obj.servoDuration);
                        else
                            obj.servoMotor.schedule(TwoChoice.PinOut.DoorN.channel, TwoChoice.PinOut.DoorN.closed, obj.servoDuration);
                        end
                        obj.print('Zone: Center.');
                    case TwoChoice.Sources.ZoneSW
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.closed, obj.servoDuration);
                        obj.print('Zone: South West.');
                    case TwoChoice.Sources.ZoneNE
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.closed, obj.servoDuration);
                        obj.print('Zone: North East.');
                    case TwoChoice.Sources.ZoneSE
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.closed, obj.servoDuration);
                        obj.print('Zone: South East.');
                    case TwoChoice.Sources.ZoneNW
                        obj.servoMotor.schedule(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.closed, obj.servoDuration);
                        obj.print('Zone: North West.');
                end
            end
        end
        
        function onReady(obj)
            if ~obj.states.ready
                obj.states.ready = true;
                obj.print('Ready.');
            end
        end
    end
end