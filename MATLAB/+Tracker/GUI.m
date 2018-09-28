% Tracker.GUI(width)
% Tracker object with UI components.
% 
% Tracker.GUI methods;
%   delete - Delete panel with graphic components.

% 2018-05-30. Leonardo Molina.
% 2018-06-24. Last modified.
classdef GUI < Tracker
    properties (Access = private)
        areaEnabled = true
        hueEnabled = true
        populationEnabled = true
        quantityEnabled = true
        shrinkEnabled = true
        
        areaPopup
        areaSlider
        areaText
        
        huePopup
        hueSlider
        hueText
        
        populationSlider
        populationText
        
        quantitySlider
        quantityText
        
        shrinkSlider
        shrinkText
    end
    
    properties (SetAccess = private, Hidden)
        panel
    end
    
    methods
        function [obj, panel] = GUI(width)
            % [obj, panel] = GUI(width)
            % Create a Tracker object and return a panel with UI components
            % to interact with it.
            
            if nargin < 1
                width = 560;
            end
            
            obj.register('Area', @(~)obj.redraw('area'));
            obj.register('Hue', @(~)obj.redraw('hue'));
            obj.register('Population', @(~)obj.redraw('population'));
            obj.register('Quantity', @(~)obj.redraw('quantity'));
            obj.register('Shrink', @(~)obj.redraw('shrink'));
            
            % Add GUI controls.
            nRows = 6;
            height = 20;
            
            panel = uipanel('Title', 'Tracker');
            panel.Units = 'Pixels';
            panel.Position = [1, 1, width, nRows * height];
            obj.panel = panel;
            
            % Size of targets.
            p = 0;
            obj.areaText         = uicontrol('Parent', panel, 'Style', 'Text',      'Position', [0.00 * width, p * height, 0.29 * width, height], 'Units', 'Normalized', 'String', 'Target area', 'HorizontalAlignment', 'right');
            obj.areaPopup        = uicontrol('Parent', panel, 'Style', 'PopUpMenu', 'Position', [0.30 * width, p * height, 0.35 * width, height], 'Units', 'Normalized', 'String', {'Ignore', 'Homogeneous', 'Area'}, 'CallBack', @(~, ~)obj.onAreaPopup());
            obj.areaSlider       = uicontrol('Parent', panel, 'Style', 'Slider',    'Position', [0.65 * width, p * height, 0.35 * width, height], 'Units', 'Normalized', 'Min', 0, 'Max', 1, 'Value', 0.025, 'SliderStep', [1 1]./(1000 - 0), 'Enable', 'off', 'CallBack', @(~, ~)obj.onAreaSlider());
            
            % Number of targets.
            p = 1;
            obj.quantityText     = uicontrol('Parent', panel, 'Style', 'Text',      'Position', [0.00 * width, p * height, 0.29 * width, height], 'Units', 'Normalized', 'String', 'Target number', 'HorizontalAlignment', 'right');
            obj.quantitySlider   = uicontrol('Parent', panel, 'Style', 'Slider',    'Position', [0.30 * width, p * height, 0.70 * width, height], 'Units', 'Normalized', 'Min', 0, 'Max', 6, 'Value', 0, 'SliderStep', [1 1]./(6 - 0), 'CallBack', @(~, ~)obj.onQuantitySlider);
            
            % Blob shrink.
            p = 2;
            obj.shrinkText       = uicontrol('Parent', panel, 'Style', 'Text',      'Position', [0.00 * width, p * height, 0.29 * width, height], 'Units', 'Normalized', 'String', 'Blob shrink', 'HorizontalAlignment', 'right');
            obj.shrinkSlider     = uicontrol('Parent', panel, 'Style', 'Slider',    'Position', [0.30 * width, p * height, 0.70 * width, height], 'Units', 'Normalized', 'Min', 0, 'Max', 10, 'Value', 0, 'SliderStep', [1 1]./(10 - 0), 'CallBack', @(~, ~)obj.onShrinkSlider);
            
            % Population size.
            p = 3;
            obj.populationText   = uicontrol('Parent', panel, 'Style', 'Text',      'Position', [0.00 * width, p * height, 0.29 * width, height], 'Units', 'Normalized', 'String', 'Population size', 'HorizontalAlignment', 'right');
            obj.populationSlider = uicontrol('Parent', panel, 'Style', 'Slider',    'Position', [0.30 * width, p * height, 0.75 * width, height], 'Units', 'Normalized', 'Min', 0, 'Max', 1, 'Value', 0.025, 'SliderStep', [1 1]./(1000 - 0), 'CallBack', @(~, ~)obj.onPopulationSlider);
            
            % Target hue.
            p = 4;
            obj.hueText          = uicontrol('Parent', panel, 'Style', 'Text',      'Position', [0.00 * width, p * height, 0.29 * width, height], 'Units', 'Normalized', 'String', 'Target hue', 'HorizontalAlignment', 'right');
            obj.huePopup         = uicontrol('Parent', panel, 'Style', 'PopUpMenu', 'Position', [0.30 * width, p * height, 0.35 * width, height], 'Units', 'Normalized', 'String', {'Bright', 'Dark', 'Hue'}, 'CallBack', @(~, ~)obj.onHuePopup());
            obj.hueSlider        = uicontrol('Parent', panel, 'Style', 'Slider',    'Position', [0.65 * width, p * height, 0.35 * width, height], 'Units', 'Normalized', 'Min', 0, 'Max', 1, 'Value', 0, 'SliderStep', [1 1]./(100 - 0), 'Enable', 'off', 'CallBack', @(~, ~)obj.onHueSlider);
            
            addlistener(obj.areaSlider,       'ContinuousValueChange', @(~, ~)obj.onAreaSlider);
            addlistener(obj.hueSlider,        'ContinuousValueChange', @(~, ~)obj.onHueSlider);
            addlistener(obj.populationSlider, 'ContinuousValueChange', @(~, ~)obj.onPopulationSlider);
            addlistener(obj.quantitySlider,   'ContinuousValueChange', @(~, ~)obj.onQuantitySlider);
            addlistener(obj.shrinkSlider,     'ContinuousValueChange', @(~, ~)obj.onShrinkSlider);
            
            obj.redraw('area');
            obj.redraw('hue');
            obj.redraw('population');
            obj.redraw('quantity');
            obj.redraw('shrink');
        end
        
        function delete(obj)
            % Tracker.GUI.delete()
            % Delete panel with graphic components.
            
            delete(obj.panel);
            delete@Tracker(obj);
        end
    end
    
    methods (Access = private)
        function redraw(obj, tag)
            switch tag
                case 'area'
                    value = obj.area;
                    switch value
                        case -1
                            obj.areaSlider.Enable = 'off';
                            obj.areaText.String = 'Area:';
                            obj.areaPopup.Value = find(ismember(obj.areaPopup.String, 'Ignore'));
                        case -2
                            obj.areaSlider.Enable = 'off';
                            obj.areaText.String = 'Area:';
                            obj.areaPopup.Value = find(ismember(obj.areaPopup.String, 'Homogeneous'));
                        otherwise
                            obj.areaEnabled = false;
                            obj.areaSlider.Enable = 'on';
                            obj.areaPopup.Value = find(ismember(obj.areaPopup.String, 'Area'));
                            value = min(max(value, obj.areaSlider.Min), obj.areaSlider.Max);
                            obj.areaSlider.Value = value;
                            obj.areaText.String = sprintf('Area [%.2f%%]:', 100 * value);
                            obj.areaEnabled = true;
                    end
                case 'hue'
                    value = obj.hue;
                    switch value
                        case -1
                            obj.hueSlider.Enable = 'off';
                            obj.hueText.String = 'Mode:';
                            obj.huePopup.Value = find(ismember(obj.huePopup.String, 'Dark'));
                        case -2
                            obj.hueSlider.Enable = 'off';
                            obj.hueText.String = 'Mode:';
                            obj.huePopup.Value = find(ismember(obj.huePopup.String, 'Bright'));
                        otherwise
                            obj.hueEnabled = false;
                            obj.hueSlider.Enable = 'on';
                            obj.huePopup.Value = find(ismember(obj.huePopup.String, 'Hue'));
                            value = min(max(value, obj.hueSlider.Min), obj.hueSlider.Max);
                            obj.hueSlider.Value = value;
                            obj.hueText.String = sprintf('Mode [%.2f]:', value);
                            obj.hueEnabled = true;
                    end
                case 'population'
                    obj.populationEnabled = false;
                    value = obj.population;
                    value = min(max(value, obj.populationSlider.Min), obj.populationSlider.Max);
                    obj.populationSlider.Value = value;
                    obj.populationText.String = sprintf('Population size [%0.2f%%]:', 100 * value);
                    obj.populationEnabled = true;
                case 'quantity'
                    obj.quantityEnabled = false;
                    value = obj.quantity;
                    value = min(max(value, obj.quantitySlider.Min), obj.quantitySlider.Max);
                    obj.quantitySlider.Value = value;
                    if value == 0
                        obj.quantityText.String = 'Number of targets [mean]:';
                    else
                        obj.quantityText.String = sprintf('Number of targets [%i]:', value);
                    end
                    obj.quantityEnabled = true;
                case 'shrink'
                    obj.shrinkEnabled = false;
                    value = obj.shrink;
                    value = min(max(value, obj.shrinkSlider.Min), obj.shrinkSlider.Max);
                    obj.shrinkSlider.Value = value;
                    obj.shrinkText.String = sprintf('Blob shrink [%i]:', value);
                    obj.shrinkEnabled = true;
            end
        end
        
        function onAreaPopup(obj)
            if obj.areaEnabled
                switch obj.areaPopup.String{obj.areaPopup.Value}
                    case 'Area'
                        obj.area = round(obj.areaSlider.Value);
                    case 'Homogeneous'
                        obj.area = -2;
                    case 'Ignore'
                        obj.area = -1;
                end
            end
        end
        
        function onAreaSlider(obj)
            if obj.areaEnabled
                value = obj.areaSlider.Value;
                if obj.area ~= value
                    obj.area = value;
                end
            end
        end
        
        function onQuantitySlider(obj)
            if obj.quantityEnabled
                value = round(obj.quantitySlider.Value);
                if obj.quantity ~= value
                    obj.quantity = value;
                end
            end
        end
        
        function onShrinkSlider(obj)
            if obj.shrinkEnabled
                value = round(obj.shrinkSlider.Value);
                if obj.shrink ~= value
                    obj.shrink = value;
                end
            end
        end
        
        function onPopulationSlider(obj)
            if obj.populationEnabled
                value = obj.populationSlider.Value;
                if obj.population ~= value
                    obj.population = value;
                end
            end
        end
        
        function onHuePopup(obj)
            if obj.hueEnabled
                switch obj.huePopup.String{obj.huePopup.Value}
                    case 'Bright'
                        obj.hue = -2;
                    case 'Dark'
                        obj.hue = -1;
                    case 'Hue'
                        obj.hue = obj.hueSlider.Value;
                end
            end
        end
        
        function onHueSlider(obj)
            if obj.hueEnabled
                value = obj.hueSlider.Value;
                if obj.hue ~= value
                    obj.hue = value;
                end
            end
        end
    end
end