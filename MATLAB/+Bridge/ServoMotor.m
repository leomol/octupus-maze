% 2017-06-18. Leonardo Molina.
% 2018-09-21. Last modified.
classdef ServoMotor < Event
    properties (Access = private)
        pwm
        minTic
        deltaTic
        maxAngle
        scheduler
        
        count
        map = struct('fall', repmat({NaN}, 1, 64), 'handle', repmat({NaN}, 1, 64), 'running', repmat({false}, 1, 64));
        
        queue = struct('channel', {}, 'angle', {}, 'duration', {});
    end
    
    methods
        function obj = ServoMotor(bridge, basePulse, minPulse, maxPulse, maxAngle)
            % Bridge.ServoMotor(bridge, basePulse, minPulse, maxPulse, maxAngle)
            % Setup a PWM driver connected to an Arduino via bridge. basePulse, minPulse,
            % maxPulse, and maxAngle are used to scale input angles with the set method.
            
            if nargin < 2
                basePulse = 14225;
            end
            if nargin < 3
                minPulse = 326;
            end
            if nargin < 4
                maxPulse = 2116;
            end
            if nargin < 5
                maxAngle = 180;
            end
            
            MHz = 1 / (basePulse + minPulse + maxPulse);
            
            obj.minTic = minPulse * MHz * 4096;
            obj.deltaTic = maxPulse * MHz * 4096 - obj.minTic;
            obj.maxAngle = maxAngle;
            
            obj.scheduler = Scheduler();
            obj.pwm = Bridge.PWM(bridge, round(1e6 * MHz));
            
            obj.count = 0;
        end
        
        function delete(obj)
            % ServoMotor.delete()
            % Stop scheduler controlling processes.
            
            delete(obj.scheduler);
        end
        
        function angle = angle(obj, channel)
            % Bridge.ServoMotor.angle(channel)
            % Get the angle of a servo.
            
            index = channel + 1;
            angle = obj.map(index).angle;
        end
        
        function set(obj, channel, angle, duration)
            % ServoMotor.set(channel, angle, duration)
            % Set a angle for a channel inmediately for the given duration
            % then release the channel.
            
            % Remove channel action from a schedule.
            k = [obj.queue.channel] == channel;
            obj.queue(k) = [];
            
            index = channel + 1;
            if obj.map(index).running
                % If channel is currently running, cancel a scheduled stop.
                % Number of running channels remain unchanged.
                delete(obj.map(index).handle);
            else
                obj.count = obj.count + 1;
            end
            
            % Send instruction to board.
            fall = round(angle / obj.maxAngle * obj.deltaTic + obj.minTic);
            if ~obj.map(index).running || fall ~= obj.map(index).fall
                obj.map(index).fall = fall;
                obj.pwm.set(channel, fall);
            end
            obj.map(index).running = true;
            
            % Schedule a stop.
            obj.map(index).handle = obj.scheduler.delay({obj, 'stop', channel}, duration);
        end
        
        function schedule(obj, channel, angle, duration)
            % Bridge.ServoMotor.schedule(channel, angle, duration)
            % When the queue is free, set the angle for a channel for the
            % given duration then release the channel.
            
            % Add to back of the queue.
            n = numel(obj.queue) + 1;
            obj.queue(n).channel = channel;
            obj.queue(n).angle = angle;
            obj.queue(n).duration = duration;
            
            if obj.count == 0 && n == 1
                % If nothing is currently running and this is the only element in the queue.
                obj.pop();
            end
        end
        
        function stop(obj, channel)
            % Bridge.ServoMotor.stop(channel)
            
            % Stopping a channel enables other instructions in the queue.
            n = numel(obj.queue);
            index = channel + 1;
            idle = false;
            if obj.map(index).running
                obj.map(index).running = false;
                obj.pwm.set(channel, 0);
                obj.count = obj.count - 1;
                if n == 0
                    idle = true;
                end
            end
            if obj.count == 0 && n > 0
                % If nothing is currently running and the queue is not empty.
                obj.pop();
            end
            if idle
                obj.invoke('Idle');
            end
        end
        
        function pop(obj)
            % Pop next element in the queue.
            channel = obj.queue(1).channel;
            angle = obj.queue(1).angle;
            duration = obj.queue(1).duration;
            obj.queue(1) = [];
            obj.set(channel, angle, duration);
        end
    end
end