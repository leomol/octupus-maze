% SetShift - Controller for a behavioral task dependent on video tracking.
% 
% Track subject with a webcam, open/close gates and trigger rewards/tones to
% guide behavior while logging and syncing with an external data acquisition
% system (e.g. electrophysiology) in a choice task.
% 
% Task:
%   Refer to the octupus maze diagram. Subject starts at the N or S arms of
%   the maze and takes a reward. According to a contingency table, chooses 
%   to or is forced to take a left or a right turn, to then choose a feeder
%   on the south or north halves of the maze. Then starts a new trial at the
%   starting point or chooses to go to the opposite side of the maze.
% 
% SetShift methods:
%   delete                   - Close figure and release resources.
%   log                      - Create a log entry using the same syntax as sprintf.
%   note                     - Print on screen and log using the same syntax as sprintf.
%   print                    - Print on screen using the same syntax as sprintf.
%   reward                   - Send a pulse to an Arduino Pin for the given duration (seconds).
%   setByte                  - Write an 8-bit number in the port F of Arduino.
%   tone                     - Play a tone with the given frequency (Hz) and duration (seconds) in a designated pin in Arduino.
%   trial                    - Trigger a new trial.
%   
% SetShift properties:
%   contingencies            - Probabilities for left/right paths and rewards.
%   contingenciesRepetitions - Number of trials with the same feeder probability.
%   errorTone                - Frequency and duration of an error tone.
%   freePathProbability      - Probability of issuing a free choice.
%   rewardAmount             - Reward volume in 3rds of a feeder cup.
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
classdef SetShift < handle
    properties (Access = public)
        % folder - Where to store the log file.
        folder = 'Documents/SetShift'
        
        % errorTone - Frequency and duration for an error tone.
        errorTone = [1750, 2]
        
        % successTone - Frequency and duration for a success tone.
        successTone = [2250, 0.25]
        
        % freePathProbability - Probability of issuing a free choice.
        % The complement is a forced choice.
        freePathProbability = 0.5
        
        % contingencies - Probabilities for West/East paths and rewards.
        % A new column is read every 'contingenciesRepetitions' trials.
        % 1st value:
        %   Probability of forced West path (when a forced choice is active).
        %   The complement is the probability of going East.
        % 2nd value:
        %   The probability of rewarding a South feeder (SW|SE).
        % 3rd value:
        %   The probability of rewarding a North feeder (NW|NE).
        contingencies = [0.5, 0.5
                         0.7, 0.0
                         0.0, 0.7]
                     
        % contingenciesRepetitions - Number of trials with the same feeder probability.
        contingenciesRepetitions = 4
        
        % rewardAmount - Reward volume in 3rds of a feeder cup.
        rewardAmount = 1
        
        % servoDuration - Disengage a servo motor after a given duration.
        servoDuration = 1.000
    end
    
    properties (GetAccess = public, SetAccess = private)
        % fid - Log file identifier.
        fid
        
        % filename - Name of the log file.
        filename
        
        % startTime - Reference to time at start.
        startTime
        
        % trialNumber - Trial id.
        trialNumber = 0
    end
    
    properties (Access = private)
        % className - Name of this class.
        className
        
        % states - Miscellaneous states for behavioral control.
        %   half: Which half south or north is currently active.
        %   feederS.available: Whether the South feeder is enabled.
        %   feederN.available: Whether the South feeder is enabled.
        states
    end
    
    properties (Constant)
        % programVersion - Version of this class.
        programVersion = '20180927'
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
        function obj = SetShift(comID, cameraID)
            % SetShift(comID, cameraID)
            % Controller for a SetShift task. Gets the position of a target
            % using a webcam with cameraID (1 to n cameras connected) and an
            % Arduino with comID to read inputs from feeder ports and trigger
            % rewards and open/close doors in a maze.
            
            % Name of this class.
            obj.className = mfilename('class');
            
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
                'rewardAmount', ...
                'successTone', ...
                'errorTone', ...
                'freePathProbability', 'contingencies', 'contingenciesRepetitions' ...
                };
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
            obj.states.feederSW.available = false;
            obj.states.feederSE.available = false;
            obj.states.feederNW.available = false;
            obj.states.feederNE.available = false;
            obj.states.mode = TwoChoice.Modes.FreeChoice;
            obj.states.choice = TwoChoice.Choices.X;
            obj.states.half = TwoChoice.Choices.X;
            obj.states.ready = false;
            
            % Show version and session name on screen.
            obj.print('Version %s %s', obj.className, TwoChoice.programVersion);
            obj.print('Session "%s"', session);
            
            % Setup Arduino.
            obj.bridge = Bridge(comID);
            
            % Behavior is enabled after a successful connection.
            obj.bridge.register('ConnectionChanged', @obj.onBridgeConnection);
            
            % Listen to feeder pokes.
            obj.bridge.register(TwoChoice.PinOut.FeederS.pokePin, {@obj.onPoke, TwoChoice.Sources.FeederS});
            obj.bridge.register(TwoChoice.PinOut.FeederN.pokePin, {@obj.onPoke, TwoChoice.Sources.FeederN});
            obj.bridge.register(TwoChoice.PinOut.FeederSW.pokePin, {@obj.onPoke, TwoChoice.Sources.FeederSW});
            obj.bridge.register(TwoChoice.PinOut.FeederSE.pokePin, {@obj.onPoke, TwoChoice.Sources.FeederSE});
            obj.bridge.register(TwoChoice.PinOut.FeederNW.pokePin, {@obj.onPoke, TwoChoice.Sources.FeederNW});
            obj.bridge.register(TwoChoice.PinOut.FeederNE.pokePin, {@obj.onPoke, TwoChoice.Sources.FeederNE});
            
            % Control servo motors using generic settings and angles.
            obj.servoMotor = Bridge.ServoMotor(obj.bridge);
            
            % Start video tracker.
            obj.virtualTracker = VirtualTracker.GUI(cameraID);
            
            % Listen to every position change.
            obj.virtualTracker.register('Position', @obj.onPosition);
            
            % Release resources when window is closed.
            obj.virtualTracker.register('Close', @obj.onClose);
            
            % Start Arduino.
            obj.bridge.start();
            
            % Close all doors.
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorS.channel,  TwoChoice.PinOut.DoorS.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorN.channel,  TwoChoice.PinOut.DoorN.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorW.channel,  TwoChoice.PinOut.DoorW.closed, obj.servoDuration);
            obj.servoMotor.schedule(TwoChoice.PinOut.DoorE.channel,  TwoChoice.PinOut.DoorE.closed, obj.servoDuration);
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
            % SetShift.delete()
            % Close figure and release resources.
            
            obj.onClose();
        end
        
        function log(obj, format, varargin)
            % SetShift.log(format, arg1, arg2, ...)
            % Create a log entry using the same syntax as sprintf.
            
            fprintf(obj.fid, '%.2f,%s\n', toc(obj.startTime), sprintf(format, varargin{:}));
        end
        
        function note(obj, format, varargin)
            % SetShift.note(format, arg1, arg2, ...)
            % Print on screen and log using the same syntax as sprintf.
            
            obj.log(['note,' format], varargin{:});
            obj.print(format, varargin{:});
        end
        
        function print(obj, format, varargin)
            % SetShift.print(format, arg1, arg2, ...)
            % Print on screen using the same syntax as sprintf.
            
            fprintf(['[%.1f] ' format '\n'], toc(obj.startTime), varargin{:});
        end
        
        function reward(obj, pin, duration)
            % SetShift.reward(pin, duration)
            % Send a pulse to an Arduino Pin for the given duration (seconds).
            
            % Valve switches on with a LOW pulse.
            obj.bridge.setPulse(pin, 0, round(1e6 * duration), 0, 1);
            obj.log('reward,%i,%.2f', pin, duration);
        end
        
        function setByte(obj, value)
            % SetShift.setByte(value)
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
            % SetShift.tone(frequency, duration)
            % Play a tone with the given frequency (Hz) and duration (seconds) in a designated pin in Arduino.
            
            obj.bridge.setTone(TwoChoice.PinOut.Speaker, round(frequency), round(1e6 * duration));
            obj.log('tone,%.2f,%.2f', frequency, duration);
        end
        
        function trial(obj)
            % SetShift.trial()
            % Trigger a new trial.
            
            % Increase trial number.
            obj.trialNumber = obj.trialNumber + 1;
            
            % Output trial number to pins A8 to A15 of the Arduino (wrap around 8 bits).
            obj.setByte(mod(obj.trialNumber - 1, 255) + 1);
            
            % Close doors behind.
            
            % Force West or East paths, or else allow free choice.
            if rand() <= obj.freePathProbability
                % Open West and East doors.
                obj.print('Trial #%i: Free choice.', obj.trialNumber);
                obj.log('trial,%i,free-choice', obj.trialNumber);
                obj.states.mode = TwoChoice.Modes.FreeChoice;
                
                obj.servoMotor.set(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.opened, obj.servoDuration);
                obj.servoMotor.set(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.opened, obj.servoDuration);
                obj.servoMotor.set(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.opened, obj.servoDuration);
                obj.servoMotor.set(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.opened, obj.servoDuration);
                obj.servoMotor.set(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.opened, obj.servoDuration);
                obj.servoMotor.set(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.opened, obj.servoDuration);
            else
                % Active column in the contingencies table.
                nColumns = size(obj.contingencies, 2);
                column = mod(ceil(obj.trialNumber .* 1 / obj.contingenciesRepetitions) - 1, nColumns) + 1;
                westPathProbability = obj.contingencies(1, column);
                if rand() <= westPathProbability
                    % Open West door.
                    obj.print('Trial #%i: Forced west.', obj.trialNumber);
                    obj.log('trial,%i,forced-west', obj.trialNumber);
                    obj.states.mode = TwoChoice.Modes.ForcedWest;
                    obj.servoMotor.set(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.opened, obj.servoDuration);
                    obj.servoMotor.set(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.opened, obj.servoDuration);
                    obj.servoMotor.set(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.opened, obj.servoDuration);
                else
                    % Open East door.
                    obj.print('Trial #%i: Forced East.', obj.trialNumber);
                    obj.log('trial,%i,forced-East', obj.trialNumber);
                    obj.states.mode = TwoChoice.Modes.ForcedEast;
                    obj.servoMotor.set(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.opened, obj.servoDuration);
                    obj.servoMotor.set(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.opened, obj.servoDuration);
                    obj.servoMotor.set(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.opened, obj.servoDuration);
                end
            end
            
            % Reset current choice.
            obj.states.choice = TwoChoice.Choices.X;
        end
    end
    
    methods (Access = private)
        function onBridgeConnection(obj, connected)
            % SetShift.onBridgeConnection(connected)
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
                names = {'FeederS', 'FeederN', 'FeederSW', 'FeederSE', 'FeederNW', 'FeederNE'};
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
            % SetShift.onBridgeData(data)
            % Parse data received from Arduino.
            
            % Ignore pin state during setup.
            if data.State && data.Count > 0
                % Always log licks.
                switch data.Pin
                    case TwoChoice.PinOut.FeederS.lickPin
                        obj.log('lick,FeederS');
                    case TwoChoice.PinOut.FeederN.lickPin
                        obj.log('lick,FeederN');
                    case TwoChoice.PinOut.FeederSW.lickPin
                        obj.log('lick,FeederSW');
                    case TwoChoice.PinOut.FeederSE.lickPin
                        obj.log('lick,FeederSE');
                    case TwoChoice.PinOut.FeederNW.lickPin
                        obj.log('lick,FeederNW');
                    case TwoChoice.PinOut.FeederNE.lickPin
                        obj.log('lick,FeederNE');
                end
            end
        end
        
        function onClose(obj)
            % SetShift.onClose(tracker)
            % Video tracker window closed. Release all resources.
            
            Objects.delete(obj.bridge);
            Objects.delete(obj.virtualTracker);
            if isvalid(obj) && isnumeric(obj.fid)
                fclose(obj.fid);
            end
            
            obj.print('Terminated.');
        end
        
        function onPoke(obj, source, data)
            % SetShift.onPoke(source, data)
            % source: one of 6 reward feeders (S, N, SW, SE, NW, NE)
            % data: the logical state of the pin associated to the feeder
            % device.
            % West or East feeders need to be poked timely; North or South
            % feeders do not.
            % Poking South feeder re-enables North feeder and vice-versa.
            
            if data.Count > 0 && data.State
                % Ignore pin state during setup.
                switch source
                    case TwoChoice.Sources.FeederS
                        % Re-enable entries in other feeders.
                        obj.states.feederN.available = true;
                        obj.states.feederSW.available = true;
                        obj.states.feederSE.available = true;
                        obj.states.feederNW.available = true;
                        obj.states.feederNE.available = true;
                        if obj.states.feederS.available
                            obj.states.feederS.available = false;
                            % Poking north or south feeders trigger a reward and produce a new trial.
                            % Always reward at the start feeder.
                            obj.tone(obj.successTone(1), obj.successTone(2));
                            obj.reward(TwoChoice.PinOut.FeederS.valvePin, obj.rewardAmount * TwoChoice.PinOut.FeederS.valveDuration);
                            % Close doors behind.
                            switch obj.states.choice
                                case TwoChoice.Choices.SW
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.closed, obj.servoDuration);
                                case TwoChoice.Choices.SE
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.closed, obj.servoDuration);
                                case TwoChoice.Choices.NW
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.closed, obj.servoDuration);
                                case TwoChoice.Choices.NE
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.closed, obj.servoDuration);
                            end
                            obj.print('South feeder: Rewarded.');
                            obj.log('feeder,FeederS,reward');
                            
                            issueTrial = true;
                        else
                            issueTrial = false;
                        end
                        % Close doors behind.
                        if obj.states.half ~= TwoChoice.Choices.S
                            obj.states.half = TwoChoice.Choices.S;
                            % Open South door. Close North door.
                            obj.servoMotor.set(TwoChoice.PinOut.DoorS.channel, TwoChoice.PinOut.DoorS.opened, obj.servoDuration);
                            obj.servoMotor.set(TwoChoice.PinOut.DoorN.channel, TwoChoice.PinOut.DoorN.closed, obj.servoDuration);
                        end
                        if issueTrial
                            obj.trial();
                        end
                    case TwoChoice.Sources.FeederN
                        % Re-enable entries in other feeders.
                        obj.states.feederS.available = true;
                        obj.states.feederSW.available = true;
                        obj.states.feederSE.available = true;
                        obj.states.feederNW.available = true;
                        obj.states.feederNE.available = true;
                        if obj.states.feederN.available
                            obj.states.feederN.available = false;
                            % Poking north or south feeders trigger a reward and produce a new trial.
                            % Always reward at the start feeder.
                            obj.tone(obj.successTone(1), obj.successTone(2));
                            obj.reward(TwoChoice.PinOut.FeederN.valvePin, obj.rewardAmount * TwoChoice.PinOut.FeederN.valveDuration);
                            % Close doors behind.
                            switch obj.states.choice
                                case TwoChoice.Choices.SW
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.closed, obj.servoDuration);
                                case TwoChoice.Choices.SE
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.closed, obj.servoDuration);
                                case TwoChoice.Choices.NW
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.closed, obj.servoDuration);
                                case TwoChoice.Choices.NE
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.closed, obj.servoDuration);
                                    obj.servoMotor.set(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.closed, obj.servoDuration);
                            end
                            obj.print('North feeder: Rewarded.');
                            obj.log('feeder,FeederN,reward');
                            issueTrial = true;
                        else
                            issueTrial = false;
                        end
                        % Close doors behind.
                        if obj.states.half ~= TwoChoice.Choices.N
                            obj.states.half = TwoChoice.Choices.N;
                            % Open North door. Close South door.
                            obj.servoMotor.set(TwoChoice.PinOut.DoorN.channel, TwoChoice.PinOut.DoorN.opened, obj.servoDuration);
                            obj.servoMotor.set(TwoChoice.PinOut.DoorS.channel, TwoChoice.PinOut.DoorS.closed, obj.servoDuration);
                        end
                        if issueTrial
                            obj.trial();
                        end
                    case TwoChoice.Sources.FeederSW
                        obj.states.choice = TwoChoice.Choices.SW;
                        if obj.states.feederSW.available
                            % Re-enable entries in other feeders.
                            obj.states.feederS.available = true;
                            obj.states.feederN.available = true;
                            obj.states.feederSW.available = false;
                            obj.states.feederSE.available = true;
                            obj.states.feederNW.available = true;
                            obj.states.feederNE.available = true;
                            % Rotate column in the contingencies table after a number of trials.
                            nColumns = size(obj.contingencies, 2);
                            column = mod(ceil(obj.trialNumber .* 1 / obj.contingenciesRepetitions) - 1, nColumns) + 1;
                            % Chance of getting a reward.
                            southRewardProbability = obj.contingencies(2, column);
                            % Get reward according to chance.
                            rnd = rand();
                            if rnd <= southRewardProbability
                                obj.reward(TwoChoice.PinOut.FeederSW.valvePin, obj.rewardAmount * TwoChoice.PinOut.FeederSW.valveDuration);
                                obj.tone(obj.successTone(1), obj.successTone(2));
                                obj.print('South West feeder: Rewarded.');
                                obj.log('feeder,FeederSW,rewarded');
                            else
                                obj.tone(obj.errorTone(1), obj.errorTone(2));
                                obj.print('South West feeder: Disabled (%.2f > %.2f).', rnd, southRewardProbability);
                                obj.log('feeder,FeederSW,disabled');
                            end
                            % Close opposed doors.
                            obj.servoMotor.set(TwoChoice.PinOut.DoorWT.channel, TwoChoice.PinOut.DoorWT.closed, obj.servoDuration);
                            obj.servoMotor.set(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.closed, obj.servoDuration);
                        end
                    case TwoChoice.Sources.FeederSE
                        obj.states.choice = TwoChoice.Choices.SE;
                        if obj.states.feederSE.available
                            % Re-enable entries in other feeders.
                            obj.states.feederS.available = true;
                            obj.states.feederN.available = true;
                            obj.states.feederSW.available = true;
                            obj.states.feederSE.available = false;
                            obj.states.feederNW.available = true;
                            obj.states.feederNE.available = true;
                            % Rotate column in the contingencies table after a number of trials.
                            nColumns = size(obj.contingencies, 2);
                            column = mod(ceil(obj.trialNumber .* 1 / obj.contingenciesRepetitions) - 1, nColumns) + 1;
                            % Chance of getting a reward.
                            southRewardProbability = obj.contingencies(2, column);
                            % Get reward according to chance.
                            rnd = rand();
                            if rnd <= southRewardProbability
                                obj.reward(TwoChoice.PinOut.FeederSE.valvePin, obj.rewardAmount * TwoChoice.PinOut.FeederSE.valveDuration);
                                obj.tone(obj.successTone(1), obj.successTone(2));
                                obj.print('South East feeder: Rewarded.');
                                obj.log('feeder,FeederSE,rewarded');
                            else
                                obj.tone(obj.errorTone(1), obj.errorTone(2));
                                obj.print('South East feeder: Disabled (%.2f > %.2f).', rnd, southRewardProbability);
                                obj.log('feeder,FeederSE,disabled');
                            end
                            % Close opposed doors.
                            obj.servoMotor.set(TwoChoice.PinOut.DoorET.channel, TwoChoice.PinOut.DoorET.closed, obj.servoDuration);
                            obj.servoMotor.set(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.closed, obj.servoDuration);
                        end
                    case TwoChoice.Sources.FeederNW
                        obj.states.choice = TwoChoice.Choices.NW;
                        if obj.states.feederNW.available
                            % Re-enable entries in other feeders.
                            obj.states.feederS.available = true;
                            obj.states.feederN.available = true;
                            obj.states.feederSW.available = true;
                            obj.states.feederSE.available = true;
                            obj.states.feederNW.available = false;
                            obj.states.feederNE.available = true;
                            % Rotate column in the contingencies table after a number of trials.
                            nColumns = size(obj.contingencies, 2);
                            column = mod(ceil(obj.trialNumber .* 1 / obj.contingenciesRepetitions) - 1, nColumns) + 1;
                            % Chance of getting a reward.
                            northRewardProbability = obj.contingencies(3, column);
                            % Get reward according to chance.
                            rnd = rand();
                            if rnd <= northRewardProbability
                                obj.reward(TwoChoice.PinOut.FeederNW.valvePin, obj.rewardAmount * TwoChoice.PinOut.FeederNW.valveDuration);
                                obj.tone(obj.successTone(1), obj.successTone(2));
                                obj.print('North West feeder: Rewarded.');
                                obj.log('feeder,FeederNW,rewarded');
                            else
                                obj.tone(obj.errorTone(1), obj.errorTone(2));
                                obj.print('North West feeder: Disabled (%.2f > %.2f).', rnd, northRewardProbability);
                                obj.log('feeder,FeederNW,disabled');
                            end
                            % Close opposed doors.
                            obj.servoMotor.set(TwoChoice.PinOut.DoorWB.channel, TwoChoice.PinOut.DoorWB.closed, obj.servoDuration);
                            obj.servoMotor.set(TwoChoice.PinOut.DoorR.channel, TwoChoice.PinOut.DoorR.closed, obj.servoDuration);
                        end
                    case TwoChoice.Sources.FeederNE
                        obj.states.choice = TwoChoice.Choices.NE;
                        if obj.states.feederNE.available
                            % Re-enable entries in other feeders.
                            obj.states.feederS.available = true;
                            obj.states.feederN.available = true;
                            obj.states.feederSW.available = true;
                            obj.states.feederSE.available = true;
                            obj.states.feederNW.available = true;
                            obj.states.feederNE.available = false;
                            % Rotate column in the contingencies table after a number of trials.
                            nColumns = size(obj.contingencies, 2);
                            column = mod(ceil(obj.trialNumber .* 1 / obj.contingenciesRepetitions) - 1, nColumns) + 1;
                            % Chance of getting a reward.
                            northRewardProbability = obj.contingencies(3, column);
                            % Get reward according to chance.
                            rnd = rand();
                            if rnd <= northRewardProbability
                                obj.reward(TwoChoice.PinOut.FeederNE.valvePin, obj.rewardAmount * TwoChoice.PinOut.FeederNE.valveDuration);
                                obj.tone(obj.successTone(1), obj.successTone(2));
                                obj.print('North East feeder: Rewarded.');
                                obj.log('feeder,FeederNE,rewarded');
                            else
                                obj.tone(obj.errorTone(1), obj.errorTone(2));
                                obj.print('North East feeder: Disabled (%.2f > %.2f).', rnd, northRewardProbability);
                                obj.log('feeder,FeederNE,disabled');
                            end
                            % Close opposed doors.
                            obj.servoMotor.set(TwoChoice.PinOut.DoorEB.channel, TwoChoice.PinOut.DoorEB.closed, obj.servoDuration);
                            obj.servoMotor.set(TwoChoice.PinOut.DoorL.channel, TwoChoice.PinOut.DoorL.closed, obj.servoDuration);
                        end
                end
            end
        end
        
        function onPosition(obj, position)
            % SetShift.onPosition(position)
            % Camera tracker reported a change in position.
            
            obj.log('position,%.4f,%.4f', position.X, position.Y);
        end
        
        function onReady(obj)
            if ~obj.states.ready
                obj.states.ready = true;
                obj.print('Ready.');
            end
        end
    end
end