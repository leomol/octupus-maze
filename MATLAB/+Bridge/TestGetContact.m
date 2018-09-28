% 2016-12-05. Leonardo Molina.
% 2018-09-25. Last modified.
classdef TestGetContact < handle
    properties
        bridge
        handles
        listeners
        pins = [10 11 42 43];
    end
    
    methods
        function obj = TestGetContact(com)
            obj.bridge = Bridge(com);
            obj.bridge.verbose = true;
            obj.handles(4) = figure('Name', mfilename('class'), 'MenuBar', 'none', 'NumberTitle', 'off', 'CloseRequestFcn', @(~, ~)obj.delete);
            obj.handles(3) = axes('Units', 'Normalized', 'Position', [0, 0, 1, 1], 'Visible', 'off');
            obj.handles(2) = rectangle('Position', [0.5, 0.0, 0.5, 1.0], 'FaceColor', [1 1 1]);
            obj.handles(1) = rectangle('Position', [0.0, 0.0, 0.5, 1.0], 'FaceColor', [1 1 1]);
            
            nSamples = 25;
            snr = 25;
            debounce = 100;
            obj.bridge.getContact(obj.pins(1:2), nSamples, snr, debounce, debounce);
            obj.bridge.getContact(obj.pins(3:4), nSamples, snr, debounce, debounce);
            obj.bridge.register('DataReceived', @obj.onDataReceived);
        end
        
        function delete(obj)
            delete(obj.handles);
            delete(obj.bridge);
        end
        
        function onDataReceived(obj, data)
            if isvalid(obj)
                if data.State
                    color = [0, 0, 1];
                else
                    color = [1, 1, 1];
                end
                if data.Pin == obj.pins(1)
                     set(obj.handles(1), 'FaceColor', color);
                elseif data.Pin == obj.pins(3)
                     set(obj.handles(2), 'FaceColor', color);
                end
            end
        end
    end
end