function example
    % Example file using the VirtualTracker class.
    % - Define an operation to scale and shift targets.
    % - Define targets and apply scale and shift operation.
    % - Define tone callbacks.
    % - Combine targets and tones to define zones on a trial basis.
    % - Create VirtualTracker object with custom settings.

    % Define an operation to scale and shift targets in case the camera is
    % moved.
    scale = 0.30;
    xOffset = 0;
    yOffset = 0;
    transform = @(m) [scale * m(1) + xOffset, scale * m(2) + yOffset, m(3:end)];

    % Define targets. Coordinates are relative to the center of the image.
    % ( 0.0, 0.0) is the middle of the image.
    % (-0.5,-0.5) and (+0.5,0.5) confine a square.
    radius = 0.05;
    targets.NE = transform([+0.50, +0.50, radius]);
    targets.NW = transform([-0.50, +0.50, radius]);
    targets.SW = transform([-0.50, -0.50, radius]);
    targets.SE = transform([+0.50, -0.50, radius]);
    targets.CC = transform([+0.00, +0.00, radius]);
    targets.CC = transform([+0.00, +0.00, radius]);
    targets.CC = transform([+0.00, +0.00, radius]);
    targets.CC = transform([+0.00, +0.00, radius]);

    % Define tone callbacks with frequency (Hz) and duration (seconds).
    callbacks.tone1 = @(data)callback(data.State, 1000, 0.500);
    callbacks.tone2 = @(data)callback(data.State, 1500, 0.500);
    callbacks.tone3 = @(data)callback(data.State, 2000, 0.500);
    callbacks.tone4 = @(data)callback(data.State, 2500, 0.500);

    % Define pairs of region/tone for each trial.
    zones = ...
    {   ... Single target region per trial:
        00, targets.CC, callbacks.tone1, ...
        01, targets.NE, callbacks.tone1, ...
        02, targets.NW, callbacks.tone2, ...
        03, targets.SW, callbacks.tone3, ...
        04, targets.SE, callbacks.tone4, ...
        ... Multiple target regions on a single trial:
        10, targets.NE, callbacks.tone1, ...
        10, targets.NW, callbacks.tone2, ...
        10, targets.SW, callbacks.tone3, ...
        10, targets.SE, callbacks.tone4  ...
    };

    % Create task with defined zones, using the given settings.
    cameraId = 1;
    obj = VirtualTracker.GUI(cameraId);
    obj.zones = zones;
    % Define a region of interest in an octagonal shape.
    u = 1 / (sqrt(2) + 2);
    v = 0.5 * sqrt(2) * u;
    x = [-v - u, -v, v, v + u, v + u, v, -v, -v - u];
    y = [-v, -v - u, -v - u, -v, v, v + u, v + u, v];
    obj.roi = [x; y];
    
    % Adjust tracker settings.
    obj.tracker.hue = -2;
    obj.tracker.population = 0.05;
    obj.tracker.area = 0.08;
    obj.tracker.quantity = 1;
    
    % Mirror camera in both axes.
    obj.camera.mirror = [true, true];
    obj.camera.exposure = -5;
    
    function callback(state, frequency, duration)
        if state
            Tools.tone(frequency, duration);
        end
    end
end