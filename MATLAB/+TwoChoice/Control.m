% TwoChoice.Control - GUI to open/close doors and trigger rewards.
% See also TwoChoice, TwoChoice.Choices, TwoChoice.Modes, TwoChoice.Paths, TwoChoice.PinOut, TwoChoice.Sources.

% 2017-12-13. Leonardo Molina.
% 2018-09-24. Last modified.
function Control(bridge)
    if ~Objects.isValid(bridge)
        error('Expected a valid bridge object as the first parameter.');
    end
    bridge.start();
    
    dx = 150;
    dy = 30;
    figure('Name', 'Servo Control', 'MenuBar', 'none', 'NumberTitle', 'off');
    servos = Bridge.ServoMotor(bridge);
    doorNames = {'DoorS', 'DoorN', 'DoorW', 'DoorE', 'DoorL', 'DoorR', 'DoorSL', 'DoorSR', 'DoorNL', 'DoorNR', 'DoorWB', 'DoorWT', 'DoorEB', 'DoorET'};
    nDoors = numel(doorNames);
    for i = 1:nDoors
        name = doorNames{i};
        y = dy * (nDoors - i);
        uicontrol('Position', [0 * dx, y, dx, dy], 'Style', 'Text', 'String', name);
        uicontrol('Position', [1 * dx, y, dx, dy], 'Style', 'PushButton', 'String', 'Open', 'Callback', {@setServo, servos, name, 'opened'});
        uicontrol('Position', [2 * dx, y, dx, dy], 'Style', 'PushButton', 'String', 'Closed', 'Callback', {@setServo, servos, name, 'closed'});
    end

    dx = 150;
    dy = 30;
    figure('Name', 'Valve Control', 'MenuBar', 'none', 'NumberTitle', 'off');
    feederNames = {'FeederS', 'FeederN', 'FeederW', 'FeederE', 'FeederSW', 'FeederSE', 'FeederNW', 'FeederNE'};
    nFeeders = numel(feederNames);
    for i = 1:nFeeders
        name = feederNames{i};
        y = dy * (nFeeders - i);
        uicontrol('Position', [0 * dx, y, dx, dy], 'Style', 'Text', 'String', sprintf('%s (%.4fs)', name, TwoChoice.PinOut.(name).valveDuration));
        uicontrol('Position', [1 * dx, y, dx, dy], 'Style', 'PushButton', 'String', 'Click', 'Callback', {@setPulse, bridge, name});
    end
end
    
function setServo(~, ~, servos, name, state)
    duration = 1.000;
    channel = TwoChoice.PinOut.(name).channel;
    angle = TwoChoice.PinOut.(name).(state);
    servos.set(channel, angle, duration);
end
    
function setPulse(~, ~, bridge, name)
    pin = TwoChoice.PinOut.(name).valvePin;
    duration = TwoChoice.PinOut.(name).valveDuration;
    bridge.setPulse(pin, 0, min(max(round(1e6 * duration), 1), Bridge.durationRange(2)), 0, 1);
end