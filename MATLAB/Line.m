% Line - Wrapper to MATLAB's Line object.
% Line object where XData and YData can be defined in one property 'data'.
% 
% Line properties:
%   data - Set/get internal object's X and Y data interleaved.
% 
% Line methods:
%   delete - delete graphics object.

% 2018-05-30. Leonardo Molina.
% 2018-06-23. Last modified.
classdef Line < handle
    properties (Dependent)
        data
    end
    
    properties (SetAccess = private)
        handle
    end
    
    properties (Access = private)
        mData
    end
    
    methods
        function obj = Line(axes, varargin)
            % Line(axes)
            % Create a Line object on the given axes.
            
            obj.handle = plot(axes, NaN(2, 1));
            style = varargin;
            if ~isempty(style)
                set(obj.handle, style{:});
            end
        end
        
        function delete(obj)
            % Line.delete().
            % Delete graphics object.
            
            delete(obj.handle);
        end
        
        function data = get.data(obj)
            data = obj.mData;
        end
        
        function set.data(obj, data)
            if isempty(data)
                obj.mData = [];
                set(obj.handle, 'XData', [], 'YData', []);
            elseif isnumeric(data) && mod(numel(data), 2) == 0
                obj.mData = data(:);
                set(obj.handle, 'XData', obj.data(1:2:end), 'YData', obj.data(2:2:end));
            else
                error('Invalid data.');
            end
        end
    end
end