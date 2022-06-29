function allocationType = helperAdaptiveTrackingSim(scenario, thp, rax, tracker, resetJobQ, managerPreferences)
% Initialize variables
radar = scenario.Platforms{end}.Sensors{1};
updateRate = radar.UpdateRate;
resourceAllocation = nan(1,updateRate);
h = histogram(rax,resourceAllocation,'BinMethod','integers');
xlabel(h.Parent,'TrackID')
ylabel(h.Parent,'Num beams');
numSteps = updateRate * 185;
allocationType = nan(1,numSteps);
currentStep = 1;
restart(scenario);
reset(tracker);
% Return to a reset state of jobq
jobq = resetJobQ;

% Plotters and axes
plp = thp.Plotters(1);
dtp = thp.Plotters(3);
cvp = thp.Plotters(4);
trp = thp.Plotters(5);

% For repeatable results, set the random seed and revert it when done
s = rng(2020);
oc = onCleanup(@() rng(s));

% Main loop
tracks = {};

while advance(scenario)
    time = scenario.SimulationTime;
    
    % Update ground truth display
    poses = platformPoses(scenario);
    plotPlatform(plp, reshape([poses.Position],3,[])');
    
    % Point the radar based on the scheduler current job
    [currentJob,jobq] = getCurrentRadarTask(jobq,time);
    currentStep = currentStep + 1;
    if currentStep > updateRate
        resourceAllocation(1:end-1) = resourceAllocation(2:updateRate);
    end
    if strcmpi(currentJob.JobType,'Search')
        detectableTracks = zeros(0,1,'uint32');
        resourceAllocation(min([currentStep,updateRate])) = 0;
        allocationType(currentStep) = 1;
        cvp.Color = [0 0 1]; 
    else
        detectableTracks = currentJob.TrackID;
        resourceAllocation(min([currentStep,updateRate])) = currentJob.TrackID;
        cvp.Color = [1 0 1];
        if strcmpi(currentJob.JobType,'Confirm')
            allocationType(currentStep) = 2;
        else
            allocationType(currentStep) = 3;
        end
    end
    ra = resourceAllocation(~isnan(resourceAllocation));
    h.Data = ra;
    h.Parent.YLim = [0 updateRate];
    h.Parent.XTick = 0:max(ra);
    radar.LookAngle = currentJob.BeamDirection;
    plotCoverage(cvp, coverageConfig(scenario));
    
    % Collect detections and plot them
    detections = detect(scenario);
    if isempty(detections)
        meas = zeros(0,3);
    else
        dets = [detections{:}];
        meassph = reshape([dets.Measurement],3,[])';
        [x,y,z] = sph2cart(deg2rad(meassph(1)),deg2rad(meassph(2)),meassph(3));
        meas = (detections{1}.MeasurementParameters.Orientation*[x;y;z]+detections{1}.MeasurementParameters.OriginPosition)';
    end
    plotDetection(dtp, meas);
    
    % Track and plot tracks
    if isLocked(tracker) || ~isempty(detections)
        [confirmedTracks,tentativeTracks,~,analysisInformation] = tracker(detections, time, detectableTracks);
        pos = getTrackPositions(confirmedTracks,jobq.PositionSelector);
        plotTrack(trp,pos,string([confirmedTracks.TrackID]));
        
        tracks.confirmedTracks = confirmedTracks;
        tracks.tentativeTracks = tentativeTracks;
        tracks.analysisInformation = analysisInformation;
        tracks.PositionSelector = jobq.PositionSelector;
    end
    

    % Manage resources for next jobs
    jobq = manageResource(detections,jobq,tracker,tracks,currentJob,time,managerPreferences);
end