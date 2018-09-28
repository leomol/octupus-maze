% Pin-out map for the TwoChoice maze (aka Octupus maze).
% S: South
% N: North
% W: West
% E: East
% L: Left
% R: Right
% B: Bottom
% T: Top
% 
% See also TwoChoice, TwoChoice.Choices, TwoChoice.Modes, TwoChoice.Paths, TwoChoice.Sources.

% 2018-05-21. Leonardo Molina.
% 2018-09-24. Last modified.
classdef PinOut
    properties (Constant)
        % Speaker pin number in the Arduino.
        Speaker = 13;
        
        %    pin: Door id to Servo Driver pin number.
        % opened: Door angle when opened.
        % closed: Door angle when closed.
        DoorS  = struct('channel', 09, 'opened', 070, 'closed', 150);
        DoorN  = struct('channel', 14, 'opened', 075, 'closed', 135);
        DoorW  = struct('channel', 12, 'opened', 090, 'closed', 140);
        DoorE  = struct('channel', 10, 'opened', 070, 'closed', 130);
        DoorL  = struct('channel', 13, 'opened', 135, 'closed', 185);
        DoorR  = struct('channel', 11, 'opened', 110, 'closed', 055);
        DoorSL = struct('channel', 08, 'opened', 120, 'closed', 065);
        DoorSR = struct('channel', 01, 'opened', 080, 'closed', 140);
        DoorNL = struct('channel', 05, 'opened', 100, 'closed', 165);
        DoorNR = struct('channel', 04, 'opened', 105, 'closed', 055);
        DoorEB = struct('channel', 02, 'opened', 070, 'closed', 140);
        DoorET = struct('channel', 03, 'opened', 110, 'closed', 055);
        DoorWB = struct('channel', 07, 'opened', 105, 'closed', 055);
        DoorWT = struct('channel', 06, 'opened', 065, 'closed', 125);
        
        % valveDuration: Click duration of each valve calibrated to a 3rd of a cup.
        %      valvePin: Pinch valve id to Arduino pin number.
        %       pokePin: Well sensor id to Arduino pin number.
        %       lickPin: Lick sensor id to Arduino pin number.
        FeederS  = struct('valveDuration', 0.150, 'valvePin', 42, 'pokePin', 30, 'lickPin', 31);
        FeederN  = struct('valveDuration', 0.150, 'valvePin', 45, 'pokePin', 36, 'lickPin', 37);
        FeederW  = struct('valveDuration', 0.160, 'valvePin', 44, 'pokePin', 34, 'lickPin', 35);
        FeederE  = struct('valveDuration', 0.150, 'valvePin', 43, 'pokePin', 32, 'lickPin', 33);
        FeederSW = struct('valveDuration', 0.150, 'valvePin', 41, 'pokePin', 28, 'lickPin', 29);
        FeederSE = struct('valveDuration', 0.150, 'valvePin', 38, 'pokePin', 22, 'lickPin', 23);
        FeederNW = struct('valveDuration', 0.150, 'valvePin', 40, 'pokePin', 26, 'lickPin', 27);
        FeederNE = struct('valveDuration', 0.150, 'valvePin', 39, 'pokePin', 24, 'lickPin', 25);
    end
end