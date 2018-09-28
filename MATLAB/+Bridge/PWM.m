% Bridge.PWM(bridge)
% Bridge.PWM methods:
%   set - Change the pulse deliver to a servo-motor.

% 2018-01-13. Leonardo Molina.
% 2018-09-20. Last modified.
classdef PWM < handle
    properties (Access = private)
        bridge
    end
    
    methods
        function obj = PWM(bridge, frequency)
            % Bridge.PWM(bridge, frequency)
            % Create a Power Modulated Driver interface, to change the processing
            % frequency and the power (translated to a rotation angle) passed to a
            % servo-motor connected to one of 16 channels of a PWM driver.
            obj.bridge = bridge;
            obj.bridge.enqueue(Compression.compress([255, 3, frequency], [8, 8, 16]));
        end
        
        function set(obj, channel, width)
            % Bridge.PWM.set(channel, width)
            % Set the width of the high state of the PWM pulse at a given
            % servo-motor channel.
            obj.bridge.enqueue(Compression.compress([255, 4, channel, width], [8, 8, 4, 12]));
        end
    end
end