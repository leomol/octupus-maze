% UI - Figure holder of UI graphics.
% Mouse and keyboard events are forwarded to subscribers.
% 
% Below is a summary of what MATLAB and UI (this class) reports for several
% key/click combinations:
% MATLAB only reports with certainty when a left click occurs. 
%          MATLAB: reports "normal"
%              UI: reports a left click.
%    Combinations: LeftClick | Ctrl + Shift + LeftClick
%
%          MATLAB: reports "extent"
%              UI: reports not a left click.
%    Combinations: Shift + LeftClick | Shift + RightClick
%                  ScrollClick | ScrollClick + LeftClick | ScrollClick + RightClick
%                  Shift + ScrollClick | LeftClick + RightClick.
%
%          MATLAB: reports "alt"
%              UI: reports not a left click.
%    Combinations: RightClick | Control + LeftClick | Control + RightClick
%                  Control + ScrollClick
%
%          MATLAB: reports "open"
%              UI: repeats last report (left click or not a left click).
%    Combinations: LeftDoubleClick | RightDoubleClick | ScrollDoubleClick
% 
% UI properties:
%   mouse  - Structure with last mouse state.
%   window - Figure window handle.
% 
% UI events:
%   KeyPress(struct) - A key was pressed or released.
%     Keyboard reports include a structure with fields Character, Modifiers,
%     Key, and Down (boolean encoding a key press or a key release).
%     MATLAB reports a keypress several times per second as long as it is
%     pressed. This behavior is corrected here by only sending state toggles.
%   MouseClick(struct) - A mouse button was pressed or released.
%     Mouse reports include a structure with fields Left and Down; Left is a
%     boolean encoding whether the event involed the left click button or not.
%     Down is a boolean encoding whether such button was pressed or released.
%   MouseMove - A mouse button was pressed or released.
%   MouseScroll(amount) - Mouse scroll changed by the given amount.

% 2018-05-28. Leonardo Molina.
% 2018-07-16. Last modified.
classdef UI < Event
    properties (Dependent)
        % mouse  - Structure with last mouse state.
        mouse
        
        % window - Figure window handle.
        window
    end
    
    properties (Access = private)
        % wasLeftClick - Last click was left.
        wasLeftClick = true;
        
        % combos - Last key combination used.
        combos = cell(0)
        
        % mMouse - Current mouse state.
        mMouse = struct('Left', false, 'Down', false);
        
        % mWindow - Figure window handle.
        mWindow
    end
    
    methods
        function obj = UI(name)
            % UI(<name>)
            % Create a figure window to capture mouse and keyboard events and
            % report them to subscribers.
            
            if nargin < 1
                name = 'UI';
            end
            
            obj.mWindow = figure('MenuBar', 'none', 'NumberTitle', 'off', 'Name', name, ...
                'DeleteFcn', @(~, ~)obj.onClose, ...
                'WindowButtonDownFcn', @(~, ~)obj.onMouseDown, 'WindowButtonUpFcn', @(~, ~)obj.onMouseUp, 'WindowButtonMotionFcn', @(~, ~)obj.onMouseMove, 'WindowScrollWheelFcn', @(~, e)obj.onMouseScroll(e),...
                'WindowKeyPressFcn', @(~, e)obj.onKeyDown(e), 'WindowKeyReleaseFcn', @(~, e)obj.onKeyUp(e));
        end
        
        function delete(obj)
            % UI.delete()
            % Report that window is closing.
            
            obj.invoke('Delete');
            Objects.delete(obj.window);
        end
        
        function mouse = get.mouse(obj)
            mouse = obj.mMouse;
        end
        
        function window = get.window(obj)
            window = obj.mWindow;
        end
    end
    
    methods (Access = private)
        function type = clickType(obj)
            % type = UI.clickType()
            % Get one of MATLAB's click types: normal | open | something else.
            
            type = get(obj.window, 'SelectionType');
        end
        
        function onClose(obj)
            % UI.onClose()
            % Window figure closed, object ceases to exist.
            
            Objects.delete(obj.window);
            obj.invoke('Close');
        end
        
        function onKeyDown(obj, e)
            % UI.onKeyDown(event)
            % Forward key presses, without repetition.
            
            combo = {e.Character, e.Modifier, e.Key};
            if findCell(obj.combos, combo) == 0
                obj.invoke('KeyPress', cell2struct({e.Character, e.Modifier, e.Key, true}, {'Character', 'Modifiers', 'Key', 'Down'}, 2));
                obj.combos{end + 1} = combo;
            end
        end
        
        function onKeyUp(obj, e)
            % UI.onKeyUp(event)
            % Forward key releases, without repetitions.
            
            combo = {e.Character, e.Modifier, e.Key};
            p = findCell(obj.combos, combo);
            if p > 0
                obj.combos(p) = [];
            end
            obj.invoke('KeyPress', cell2struct({e.Character, e.Modifier, e.Key, false}, {'Character', 'Modifiers', 'Key', 'Down'}, 2));
        end
        
        function onMouseDown(obj)
            % UI.onMouseDown()
            % Forward mouse clicks.
            
            switch obj.clickType()
                case 'normal'
                    obj.mMouse.Left = true;
                    obj.mMouse.Down = true;
                    obj.invoke('MouseClick', obj.mMouse);
                    obj.wasLeftClick = true;
                case 'open'
                    obj.mMouse.Left = obj.wasLeftClick;
                    obj.mMouse.Down = true;
                    obj.invoke('MouseClick', obj.mMouse);
                otherwise
                    obj.mMouse.Left = false;
                    obj.mMouse.Down = true;
                    obj.invoke('MouseClick', obj.mMouse);
                    obj.wasLeftClick = false;
            end
        end
        
        function onMouseUp(obj)
            % UI.onMouseUp()
            % Capture mouse unclick.
            
            switch obj.clickType()
                case 'normal'
                    obj.mMouse.Left = true;
                    obj.mMouse.Down = false;
                    obj.invoke('MouseClick', obj.mMouse);
                case 'open'
                    obj.mMouse.Left = obj.wasLeftClick;
                    obj.mMouse.Down = false;
                    obj.invoke('MouseClick', obj.mMouse);
                otherwise
                    obj.mMouse.Left = false;
                    obj.mMouse.Down = false;
                    obj.invoke('MouseClick', obj.mMouse);
            end
        end
        
        function onMouseMove(obj)
            % UI.onMouseMove()
            % Forward mouse move.
            
            obj.invoke('MouseMove');
        end
        
        function onMouseScroll(obj, e)
            % UI.onMouseScroll()
            % Forward mouse scroll.
            
            amount = e.VerticalScrollAmount * e.VerticalScrollCount;
            obj.invoke('MouseScroll', amount);
        end
    end
    
    methods (Static)
        function [x, y] = mousePosition(axes)
            % [x, y] = mousePosition(axes)
            % Get mouse coordinates for the given axes.
             
            point = get(axes, 'CurrentPoint');
            x = point(1);
            y = point(3);
        end
    end
end

function p = findCell(list, test)
    % findCell(list, test)
    % Find test vector in a list of vectors.
    
    p = 0;
    for c = 1:numel(list)
        if isequal(list{c}, test)
            p = c;
            break;
        end
    end
end