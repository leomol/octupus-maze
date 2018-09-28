% Image - Object holder for an image and line graphics.
% The image is centered at (0, 0) and its axis limits are always [-0.5, +0.5]
% on it's shortest dimension, while the larger dimension's limits are scaled
% accordingly to maintain the aspect ratio.
%
% Image methods:
%   delete - Close figure.
%   line   - Create line graphic in the image axes.
% 
% Image properties:
%   image  - Set/get image pixels.
%   mouse  - Get mouse state as a structure.
%   window - Figure handle.
% 
% Image Event list:
%   MouseClick(mouseState) - Mouse click-state changed.
%   MouseMove(mouseState)  - Mouse position changed.
%   Close                  - Figure closed.
%
% For example:
%   % 1) Create an Image object.
%   obj = Image('test');
%   % 2) Define an image.
%   obj.image = randi(255, [100, 150, 3], 'uint8');
%   % 2) Draw a black line with the given data.
%   h = obj.line('XData', [-0.5, 0.5], 'YData', [-0.5, 0.5], 'Color', [0 0 0], 'LineWidth', 3);
%   % 3) Replace data to turn line into a red circle.
%   r = linspace(0, 2 * pi, 360);
%   h.data = 0.5 * [sin(r); cos(r)];
%   set(h.handle, 'Color', [1 0 0]);
%   % 4) Delete object.
%   delete(h);
% 
% Also see UI, Event.

% 2018-05-30. Leonardo Molina.
% 2018-09-07. Last modified.
classdef Image < Event
    properties (Dependent)
        % image - Set/get image in the figure.
        image
        
        % mouse - Get mouse state.
        mouse
        
        % window - Get object's figure.
        window
    end
    
    properties (Hidden)
        % imageAxes - Image axes handle for plots.
        imageAxes
        
        % imageHandle - Image handle for rendering images.
        imageHandle
        
        % ui - Reference to the UI object forwarding mouse events.
        ui
    end
    
    methods
        function obj = Image(name)
            % obj = Image(name)
            % Create a figure window as a holder for image and line plots.
            
            obj.ui = UI(name);
            obj.imageAxes = axes('Visible', 'off');
            axis(obj.imageAxes, 'tight', 'equal', 'xy');
            hold(obj.imageAxes, 'all');
            obj.ui.register('KeyPress', {@obj.invoke, 'KeyPress'});
            obj.ui.register('MouseClick', @(~)obj.onMouseClick);
            obj.ui.register('MouseMove', @(~)obj.onMouseMove);
            obj.ui.register('Close', @()obj.invoke('Close'));
            
            obj.imageHandle = imagesc(zeros(120, 120, 3, 'uint8')); % !!
            obj.image = obj.image;
        end
        
        function delete(obj)
            % Image.delete()
            % Delete graphic components.
            
            delete(obj.ui);
            obj.invoke('Delete');
        end
        
        function window = get.window(obj)
            window = obj.ui.window;
        end
        
        function line = line(obj, varargin)
            % line = line(obj, <pair-wise line properties>)
            % Plots a line on top of the image with pair-wise properties as
            % defined for MATLAB's primitive Line object.
            
            line = Line(obj.imageAxes);
            style = varargin;
            line.handle.set(style{:});
        end
        
        function set.image(obj, image)
            dim = size(image);
            obj.imageHandle.CData = image;
            k = 0.5;
            if dim(1) < dim(2)
                d = k * dim(2) / dim(1);
                set(obj.imageHandle, 'XData', [-d, +d], 'YData', [-k, +k]);
            else
                d = k * dim(1) / dim(2);
                set(obj.imageHandle, 'XData', [-k, +k], 'YData', [-d, +d]);
            end
        end
        
        function image = get.image(obj)
            image = obj.imageHandle.CData;
        end
        
        function data = get.mouse(obj)
            [x, y] = UI.mousePosition(obj.imageAxes);
            data = obj.ui.mouse;
            data.Position = [x, y];
        end
    end
    
    methods (Access = private)
        function onMouseClick(obj)
            % Image.onMouseClick()
            % Mouse clicked on the figure.
            
            obj.invoke('MouseClick', obj.mouse);
        end
        
        function onMouseMove(obj)
            % Image.onMouseMove()
            % Mouse moved over the figure.
            
            obj.invoke('MouseMove', obj.mouse);
        end
    end
end