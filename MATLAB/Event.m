% Event - Event handler.
% Event methods:
%   register - Invoke a generic method with the given event.
% 
% Event notification mechanism which accepts any delegate, as opposed to MATLAB's 
% event mechanism which expects listeners with one type of argument, i.e. a child
% of event.EventData.
% 
% Clients register to events with obj.register(eventName, @callback)
% where obj is an instance of the object in question, and callback is a 
% recipient function/method that receives the expected parameters defined
% in the documentation for a given eventName.
% 
% See also Callbacks.invoke.

% 2018-03-08. Leonardo Molina.
% 2018-07-05. Last modified.
classdef Event < handle
    properties (Access = private)
        map = cell(3, 0)
    end
    
    properties (Access = protected)
        uid = 0
    end
    
    methods
        function obj = Event(varargin)
        end
        
        function [handle, id] = register(obj, name, callback)
            % Event.register(name, callback)
            % Register to an event with the given name and invoke the given
            % function handle when is triggered.
            % The returned handle of the event may be deleted to stop 
            % receiving notifications for which it was registered.
            
            if ischar(name) && ~isempty(name)
                n = size(obj.map, 2);
                obj.uid = obj.uid + 1;
                id = obj.uid;
                obj.map(:, n + 1) = {id; name; callback};
                handle = Event.Object(obj, id);
            else
                error('Invalid Event name');
            end
        end
    end
    
    methods (Hidden)
        function unregister(obj, ids)
            % Event.unregister(ids)
            % Remove previously registered callbacks.
            
            uids = [obj.map{1, :}];
            k = ismember(uids, ids);
            obj.map(:, k) = [];
        end
    end
    
    methods (Access = protected)
        function invoke(obj, name, varargin)
            % Event.invoke(name, parameter1, parameter2, ...)
            % Invoke callbacks with parameters registered with a given name.
            
            names = obj.map(2, :);
            k = ismember(names, name);
            callbacks = obj.map(3, k);
            for c = 1:numel(callbacks)
                Callbacks.invoke(callbacks{c}, varargin{:});
            end
        end
    end
end