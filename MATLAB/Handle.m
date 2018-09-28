% Handle - Encapsulate a handle to a resource to which a client may request
% deletion.
% 
% Handle constructor:
%   Handle(callback) - Invoke function when deleted.
% 
% Handle methods:
%   delete - Invokes a function previously defined by a server to release internal resources.

% 2018-05-28. Leonardo Molina.
% 2018-06-23. Last modified.
classdef Handle
    properties (Access = private)
        callback
    end
    
    methods
        function obj = Handle(callback)
            % Handle(callback)
            % Return an object which invokes the given function handle on
            % deletion.
            
            obj.callback = callback;
        end
        
        function delete(obj)
            Callbacks.invoke(obj.callback);
        end
    end
end