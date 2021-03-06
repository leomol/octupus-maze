% Bridge
% Communication bridge between MATLAB and an Arduino running a matching firmware.
% Data exchanged with such device are hardcoded to speed up transmission.
% Methods to listen the state of IO pins or devices connected to them, or to
% modify their state are listed below.
% 
% Bridge methods:
%   delete       - Stop connection and release the serial port resource.
%   getBinary    - Listen to binary changes produced by variations in voltage.
%   getContact   - Listen to binary changes produced by variations in capacitance.
%   getCount     - Get the number of times a pin was a in a given state.
%   getLevel     - Listen to 8-bit changes produced by variations in voltage.
%   getRotation  - Listen to updates from a rotary encoder.
%   getThreshold - Listen to binary changes produced by variations in voltage around a threshold.
%   getValue     - Get the current value accumulated for a pin.
%   setAddress   - Change the 8-bit value of the given 8-bit CPU address.
%   setBinary    - Change the binary state of an output pin.
%   setChirp     - Set a square wave with variable frequency.
%   setPulse     - Set a square wave with fixed frequency.
%   setTone      - Play a tone with a given frequency and duration.
%   stopGet      - Stop listening to changes from an input pin.
%   stopSet      - Stop the output routine on an output pin.
% 
% Units of time parameters such as pulse duration and debounce durations
% are expected in microseconds, as an integer value in the range Bridge.durationRange.
% 
% Pin numbers for an Arduino Mega 2560:
%   Digital pins (D02 to D49) correspond to pins 02 to 49.
%   Analog pins (A00 to A15) correspond to pins 50 to 65.
% 
% Examples:
%     Make pin 13 blink - MATLAB handles timing:
%       for i = 1:10
%          if mod(i, 2) == 0
%              bridge.setBinary(13, 0);
%          else
%              bridge.setBinary(13, 1);
%          end
%          pause(0.5);
%       end
% 
%     Make pin 13 blink - Arduino handles timing:
%       bridge.setPulse(13, 0, 500000, 500000, 10);
% 
%     Listen for incoming data:
%       bridge.register('DataReceived', @fcn)
%       function fcn(data)
%           fprintf('Pin: %i. State: %i. Count: %i.\n', data.Pin, data.State, data.Count);
%       end
% 
%     Get current count for pin 21:
%       pin = 21;
%       fprintf('Pin: %i. Count: %i.\n', pin, bridge.getCount(pin));
% 
%     Change state of a 8-bit port (e.g. DDRB/PORTB) by direct port manipulation:
%      DDRB is at address HEX=0x24 or DEC=36
%     PORTB is at address HEX=0x25 or DEC=37
%      DDRB = 255 (B11111111) makes all pins outputs.
%     PORTB =   0 (B00000000) turns all pins low.
%     PORTB = 255 (B11111111) turns all pins high.
%     See Atmel 2560 datasheet register summary for details.
%       % Make all pins outputs.
%       bridge.setAddress(36, 255);
%       % Toggle state of port B from 00000000 to 11111111
%       for state = repmat([0 255], 1, 10)
%         bridge.setAddress(37, state);
%         pause(0.5);
%       end
% 
%     Rotate a servo motor connected to pin 54:
%       bridge.setPulse(54, 0, 10000, 550, 0)
%       pause(2);
%       bridge.setPulse(54, 0, 10000, 2150, 0)
% 
%     Rotate at a given speed; for example from 0 to 180 in 2 seconds and back:
%       obj.setChirp(54, 10000, 10000, 550, 2150, 2000000)
%       pause(2);
%       obj.setChirp(54, 10000, 10000, 2150, 550, 2000000)
% 
%     Or, using the Servo object:
%       servo = Servo(bridge, 54, 10000, 550, 2150, 90);
%       servo.angle = 0;
%       pause(2);
%       servo.angle = 180;
%       pause(2);
%       servo.angle = 0;

% 2016-12-05. Leonardo Molina.
% 2018-09-19. Last modified.
classdef Bridge < Event
    properties (Constant)
        % nPins - Maximum number of pins.
        nPins = 2 ^ 8 / 2 - 1;
        
        % maxU8 - Maximum 8 bit value.
        maxU8 = 2 ^ 8 - 1;
        
        % maxU24 - Maximum 24 bit value.
        maxU24 = 2 ^ 24 - 1;
        
        % pinRange - I/O pin range.
        pinRange = [0, Bridge.nPins - 1];
        
        % addressRange - Arduino CPU address range.
        addressRange = [0, Bridge.maxU8];
        
        % durationRange - Duration range (us).
        durationRange = [0, Bridge.maxU24];
        
        % factorRange - Report scale factor.
        factorRange = [1, Bridge.maxU8];
    end
    
    properties (Constant, Access = private)
        % baudrate - Baudrate of the Arduino.
        baudrate = 115200
        
        % timeout - Time intervals for r/w operations.
        timeout = 1e-3
        
        % handshake - Handshake to be exchanged between the two parties.
        handshake = sprintf('%s', Bridge.maxU8, Bridge.maxU8, Bridge.maxU8);
    end
    
    properties (SetAccess = private)
        % portName - Serial port name.
        portName
    end
    
    properties (Access = private)
        device     % 
        repeat     % 
        retry      % 
        queueMatch % 
        setup      % State received after setup.
        states     % 1-bit state.
        counts     % Full counts.
        factor     % Individual report scale factor.
        connected  % 
        outputs    % Cue for output data.
        inputs     % Cue for input data.
        className  % 
        
        mverbose   % 
        enabled    % 
        
        % callbackMap - Structure with pin to callback definitions.
        callbackMap = struct('id', {}, 'callback', {}, 'pin', {});
    end
    
    properties (Dependent)
        % verbose - print debugging information.
        verbose
    end
    
    methods
        function obj = Bridge(portName)
            % Bridge(portName)
            % Create a bridge object attached to the given serial port.
            
            % Remember classname and portname.
            className = mfilename('class');
            portName = upper(portName);
            
            obj.className = className;
            obj.portName = portName;
            
            % When using the same communication port of another class instance,
            % return such instance reseting everything to defaults except
            % subscriptions to events.
            globalName = [obj.className obj.portName];
            globalObject = Global.get(globalName, []);
            if Objects.isValid(globalObject)
                % Recover object handle.
                obj = globalObject;
                obj.stop();
                obj.deleteDevice();
            end
            Global.set(globalName, obj);
            
            % Open port.
            obj.device = serial(portName, 'BaudRate', obj.baudrate);
            obj.device.Timeout = obj.timeout;
            fopen(obj.device);
            
            obj.initialize();
            
            % Disable expected timeout warnings when reading serial data.
            % Asynchronous operations cannot be used due to the nature of
            % the communication protocol and this is not permitted in
            % MATLAB anyways.
            warning('OFF', 'MATLAB:serial:fread:unsuccessfulRead');
            warning('OFF', 'MATLAB:serial:fgetl:unsuccessfulRead');
            warning('OFF', 'MATLAB:serial:fgets:unsuccessfulRead');
        end
        
        function delete(obj)
            % Bridge.delete()
            % Stop connection and release the serial port resource.
            
            obj.stop();
            obj.deleteDevice();
        end
        
        function handle = register(obj, var, callback)
            % Bridge.register(eventName, callback)
            % Invoke a generic method with the given event.
            % 
            % Bridge.register(pin, callback)
            % Invoke a generic method when a pointer enters a region.
            
            if isnumeric(var)
                pin = var;
                n = numel(obj.callbackMap) + 1;
                obj.uid = obj.uid + 1;
                id = obj.uid;
                obj.callbackMap(n).id = id;
                obj.callbackMap(n).callback = callback;
                obj.callbackMap(n).pin = pin;
                handle = Event.Object(obj, id);
            else
                eventName = var;
                handle = register@Event(obj, eventName, callback);
            end
        end
        
        function unregister(obj, ids)
            % Bridge.unregister(id)
            % Stop capturing a pin.
            
            uids = [obj.callbackMap.id];
            obj.zones(ismember(uids, ids)) = [];
        end
        
        function start(obj)
            % Threads.
            obj.stop();
            obj.repeat = Scheduler.Repeat(@obj.loop, obj.timeout);
        end
        
        function stop(obj)
            % Threads.
            Objects.delete(obj.repeat);
        end
        
        function getBinary(obj, pin, debounceRising, debounceFalling, factor)
            % Bridge.getBinary(pin, debounceRising, debounceFalling, factor)
            % Enable a report for a given pin, data is filtered so that
            % changes occurring faster than the debounceRising or
            % debounceFalling are canceled. Also, to save bandwidth, only a
            % proportion of the data is reported.
            
            obj.factor(pin + 1) = factor;
            obj.reset(pin);
            obj.enqueue(Compression.compress([255 255 pin debounceRising debounceFalling factor], [8 8 8 24 24 8]));
        end
        
        function getContact(obj, pins, samples, snr, debounceRising, debounceFalling)
            % Bridge.getContact(pins, samples, snr, debounceRising, debounceFalling)
            % Trigger a touch event when the first pin in pins changes
            % capacitance due to, for example, contact with a finger. The
            % detection occurs by sending pulses from one pin and measuring
            % the delay in the second pin. Higher number of samples yield more
            % accurate measurements at the expense of longer integration times;
            % higher snr filters out noise at the expense of removing weaker signals; 
            % while the debounce parameters filter out flickering.
            
            obj.reset(pins);
            obj.factor(pins(1) + 1) = 1;
            obj.enqueue(Compression.compress([255 254 pins(1) pins(2) samples snr debounceRising debounceFalling], [8 8 8 8 8 8 24 24]));
        end
        
        function count = getCount(obj, pin, state)
            % Bridge.getCount(pin, state)
            % Get the number of times a pin was in the given binary state.
            
            if nargin == 2
                state = 0;
            end
            count = obj.counts(pin + 1, state + 1);
        end
        
        function getLevel(obj, pin, debounceRising, debounceFalling)
            % Bridge.getLevel(pin, debounceRising, debounceFalling)
            % Listen to changes in the value of an analogous pin.
            % The debounce parameters filter out flickering.
            
            obj.reset(pin);
            obj.factor(pin + 1) = 1;
            obj.enqueue(Compression.compress([255 253 pin debounceRising debounceFalling], [8 8 8 24 24]));
        end
        
        function getRotation(obj, pins, factor)
            % Bridge.getRotation(pins, factor)
            % Get the rotation state of a rotary encoder configured at the
            % given pins. A factor limits the reports to multiples of the
            % given number so as to reduce the bandwidth.
            
            obj.reset(pins);
            obj.factor(pins(1) + 1) = factor;
            obj.enqueue(Compression.compress([255 252 pins(1) pins(2) factor], [8 8 8 8 8]));
        end
        
        function getThreshold(obj, pin, threshold, debounceRising, debounceFalling)
            % Bridge.getThreshold(pin, threshold, debounceRising, debounceFalling)
            % Listen to changes in the value of an analogous pin.
            % The debounce parameters filter out flickering.
            
            obj.reset(pin);
            obj.factor(pin + 1) = 1;
            obj.enqueue(Compression.compress([255 251 pin threshold debounceRising debounceFalling], [8 8 8 8 24 24]));
        end
        
        function value = getValue(obj, pin)
            % Bridge.getValue(pin)
            % Reads the current value associated to a pin.
            % Cases:
            %   -Listener to a rotary encoder: this value is the resulting
            %    rotation (one direction minus the other).
            %   -Listener to a binary state: this value changes according
            %    to the initial state when configured and the current state
            %    so that LOW states add -1 and HIGH states add +1.
            %   -Listener to an analog state: this value reflects the
            %    analog value.
            %   -Listener to a contact state: this value reflects the touch
            %    state, 0 if untouched, 1 if touched.
            
            value = obj.counts(pin + 1, 2) - obj.counts(pin + 1, 1);
        end
        
        function setAddress(obj, address, value)
            % Bridge.setAddress(address, value)
            % Change the 8-bit value of the given 8-bit CPU address.
            
            obj.enqueue(254, address, value);
        end
        
        function setBinary(obj, pin, state)
            % Bridge.setBinary(pin, state)
            % Change the binary state of a GPIO.
            
            obj.enqueue(Bridge.encodeState(pin, state));
        end
        
        function setChirp(obj, pin, lowStart, lowEnd, highStart, highEnd, duration)
            % Bridge.setChirp(pin, lowStart, lowEnd, highStart, highEnd, duration)
            % Start a square wave at one frequency and finish at another in
            % a given duration.
            
            obj.enqueue(Compression.compress([255 2 pin lowStart lowEnd highStart highEnd duration], [8 8 8 24 24 24 24 24]));
        end
        
        function setPulse(obj, pin, stateStart, durationLow, durationHigh, repetitions)
            % Bridge.setPulse(pin, stateStart, durationLow, durationHigh, repetitions)
            % Start a square wave pulse starting with the given state for a
            % number of repetitions and with the given durations for the up
            % and down states.
            
            obj.enqueue(Compression.compress([255 1 pin stateStart durationLow durationHigh repetitions], [8 8 7 1 24 24 24]));
        end
        
        function setTone(obj, pin, frequency, duration)
            % Bridge.setTone(pin, frequency, duration)
            % Play a tone with a given frequency and duration.
            
            obj.enqueue(Compression.compress([255 5 pin frequency duration], [8 8 8 16 24]));
        end
        
        function stopGet(obj, pin)
            % Bridge.stopGet(pin)
            % Stop listening to changes from an input pin.
            
            obj.enqueue(Compression.compress([255 0 pin 1], [8 8 7 1]));
        end
        
        function stopSet(obj, pin)
            % Bridge.stopSet(pin)
            % Stop the output routine on an output pin.
            
            obj.enqueue(Compression.compress([255 0 pin 0], [8 8 7 1]));
        end
        
        function set.verbose(obj, verbose)
            if numel(verbose) == 1 && islogical(verbose)
                obj.mverbose = verbose;
            else
                error('verbose can only be true or false.');
            end
        end
        
        function verbose = get.verbose(obj)
            verbose = obj.mverbose;
        end
    end
    
    methods (Hidden)
        function enqueue(obj, varargin)
            % Bridge.enqueue(data)
            % Enqueue bytes into the output buffer.
            
            data = cat(2, varargin{:});
            data = max(0, min(Bridge.maxU8, data));
            data = cast(data, 'double');
            obj.outputs = [obj.outputs; data(:)];
        end
    end
    
    methods (Access = private)
        function deleteDevice(obj)
            if isa(obj.device, 'serial') && isvalid(obj.device)
                fclose(obj.device);
                delete(obj.device);
            end
        end
        
        function initialize(obj)
            obj.retry = true;
            obj.setup = false(Bridge.nPins, 1);
            obj.states = NaN(Bridge.nPins, 1);
            obj.counts = zeros(Bridge.nPins, 2);
            obj.factor = zeros(Bridge.nPins, 1);
            obj.connected = false;
            obj.outputs = zeros(1, 0);
            obj.inputs = zeros(1, 0);
            obj.mverbose = false;
            obj.enabled = false;
            
            % Initialize handshake tester.
            obj.queueMatch = QueueMatch(obj.handshake);
        end
            
        function reset(obj, pins)
            % Bridge.reset(pins)
            % Clear known data for the provided pins, including state count.
            
            for i = 1:numel(pins)
                id = pins(i) + 1;
                obj.setup(id) = true;
                obj.states(id) = NaN;
                obj.counts(id, :) = 0;
            end
        end
        
        function completed = write(obj, varargin)
            % Bridge.write(bytes)
            % Write bytes to the serial port. Return the number of bytes
            % that could not be written due to unexpected reasons, such as
            % port in a bad state.
            
            data = cat(1, varargin{:});
            if numel(data) > 0
                data = max(0, min(Bridge.maxU8, data));
                data = cast(data, 'double');
                % Limit transmission speed.
                ndata = numel(data);
                blockSize = 64;
                starts = 1:blockSize:ndata;
                nstarts = numel(starts);
                for s = 1:nstarts
                    start = starts(s);
                    finish = min(starts(s) + blockSize, ndata);
                    range = start:finish;
                    try
                        fwrite(obj.device, data(range), 'uint8');
                        completed = finish;
                    catch
                        obj.connected = false;
                        obj.reportConnection(false);
                        if obj.retry
                            obj.retry = false;
                            obj.reopen();
                        end
                        completed = start - 1;
                        break;
                    end
                    if s < nstarts
                        pause(1e-6);
                    end
                end
            else
                completed = 0;
            end
        end
        
        function reopen(obj)
            % Bridge.reopen()
            % Close and open the serial port.
            
            try
                fclose(obj.device);
                fopen(obj.device);
                obj.retry = true;
            catch
                obj.scheduler.delay(@obj.reopen, 1);
            end
        end
        
        function loop(obj)
            % Bridge.loop()
            % Read and write to serial port. This method is meant to be
            % called by a timer. Note that MATLAB's timer is limited to 1ms
            % intervals.
            % Read a few bytes at a time.
            nb = min(obj.device.BytesAvailable, 128);
            if nb > 0
                obj.inputs = [obj.inputs; fread(obj.device, nb, 'uint8')];
            end
            % Read only a few elements at the time so that write operations
            % are not delayed by large input arrays.
            n = min(numel(obj.inputs), 64);
            for i = 1:n
                input = obj.inputs(i);
                completed = obj.queueMatch.push(input);
                handshook = completed == numel(obj.handshake);
                if handshook
                    if obj.connected
                        obj.connected = false;
                        obj.reportConnection(false);
                    end
                    obj.connected = true;
                    fwrite(obj.device, 'r', 'uint8');
                    obj.reportConnection(true);
                elseif obj.connected && completed == 0
                    [pin, state] = Bridge.decodeState(input);
                    if pin >= Bridge.pinRange(1) && pin <= Bridge.pinRange(2)
                        if obj.setup(pin + 1)
                            obj.setup(pin + 1) = false;
                        else
                            obj.counts(pin + 1, state + 1) = obj.counts(pin + 1, state + 1) + obj.factor(pin + 1);
                        end
                        value = obj.getValue(pin);
                        if obj.verbose
                            fprintf('[%s] Pin:%i State:%i Value:%i Count:%i\n', obj.className, pin, state, value, obj.counts(pin + 1, state + 1));
                        end
                        data = struct('Pin', pin, 'State', state, 'Value', value, 'Count', obj.counts(pin + 1, state + 1));
                        obj.invoke('DataReceived', data);
                        targets = find([obj.callbackMap.pin] == pin);
                        for t = 1:numel(targets)
                            target = targets(t);
                            Callbacks.invoke(obj.callbackMap(target).callback, data);
                        end
                        obj.states(pin + 1) = state;
                    end
                end
            end
            obj.inputs(1:n) = [];
            
            % Write everything available.
            if obj.connected && numel(obj.outputs) > 0
                completed = obj.write(obj.outputs);
                obj.outputs(1:completed) = [];
            end
        end
    
        function reportConnection(obj, connected)
            % Bridge.reportConnection(connected)
            % Notify listeners that the connection changed.
            
            if connected
                obj.invoke('ConnectionChanged', true);
                if obj.verbose
                    fprintf('[%s] Status:%s\n', obj.className, 'connected');
                end
            else
                obj.invoke('ConnectionChanged', false);
                if obj.verbose
                    fprintf('[%s] Status:%s\n', obj.className, 'disconnected');
                end
            end
        end
    end
	
    methods (Static)
        function code = encodeState(pin, state)
            % Bridge.encodeState(pin, state)
            % Encode into a byte a pin number and a binary state.
            
            if state
                code = pin + Bridge.pinRange(2) + 1;
            else
                code = pin;
            end
        end
        
        function [pin, state] = decodeState(code)
            % Bridge.decodeState(code)
            % Decode the given value into a pin and a binary state.
            
            if code <= Bridge.pinRange(2)
                pin = code;
                state = false;
            else
                pin = code - Bridge.pinRange(2) - 1;
                state = true;
            end
        end
    end
end