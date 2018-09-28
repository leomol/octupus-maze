% Delay.Stages.
% Enumeration for different events evoked during the execution of a Delay.
% See also Delay.

% 2018-03-11. Leonardo Molina.
% 2018-03-12. Last modified.
classdef Stages
    enumeration
        Waiting      % Must clear entry for opening.
        Opening      % Wait for cue to enter.
        EarlyEntry   % Entered before the cue.
        EntryAllowed % Entering is now available.
        PromptEntry  % Entered timely after the cue.
        NoEntry      % Took too long to enter.
        EarlyExit    % Exited before the trigger.
        Reached      % Goal accomplished.
        RushedExit   % Exited before the cue.
        ExitAllowed  % Exiting is now available.
        PromptExit   % Exited timely after the cue.
        NoExit       % Took too long to exit.
        
        Entry        % Entered at any stage, including EarlyEntry and PromptEntry.
        Exit         % Exited at any stage, including EarlyExit and PromptExit.
        Error        % EarlyEntry, NoEntry, EarlyExit, and NoExit
    end
end