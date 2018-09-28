% CameraInterface - Pretend camera interface.
% Dependent properties or events cannot be defined in a MATLAB interface.
% Therefore, interfacing and abstraction cannot be actually implemented.

% 2018-02-15. Leonardo Molina.
% 2018-06-20. Last modified.
classdef CameraInterface < Event
    events
        Resolution
    end
    
    properties (Dependent, Access = public)
        exposure
        exposureRange
        resolutionIndex
    end
    
    properties (Dependent, GetAccess = public, SetAccess = private)
        hasFrame
        resolutionList
    end
    
    methods (Abstract)
        getFrame(obj, block)
    end
end