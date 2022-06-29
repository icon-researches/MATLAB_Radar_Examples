function jobq = manageResource(detections,jobq,tracker,tracks,current_job,current_time,managerPreferences)

trackq           = jobq.TrackQueue;
num_trackq_items = jobq.NumTrackJobs;
if ~isempty(detections)
    detection = detections{1};
else
    detection = [];
end

% Execute current job
switch current_job.JobType
    case 'Search'
        % For search job, if there is a detection, establish tentative
        % track and schedule a confirmation job
        if ~isempty(detection)           
            % A search task can still find a track we already have. Define
            % a confirmation task only if it's a tentative track. There
            % could be more than one if there are false alarms. Create
            % confirm jobs for tentative tracks created at this update.

            numTentative = numel(tracks.tentativeTracks);
            for i = 1:numTentative
                if tracks.tentativeTracks(i).Age == 1 && tracks.tentativeTracks(i).IsCoasted == 0
                    trackid = tracks.tentativeTracks(i).TrackID;
                    job = revisitTrackJob(tracker, trackid, current_time, managerPreferences, 'Confirm', tracks.PositionSelector);
                    num_trackq_items = num_trackq_items+1;
                    trackq(num_trackq_items) = job;
                end
            end
        end

    case 'Confirm'
        % For a confirm job, if the track ID is within the tentative
        % tracks, it means that we need to run another confirmation job
        % regardless of having a detection. If the track ID is within the
        % confirmed tracks, it means that we must have gotten a detection,
        % and the track passed the confirmation logic test. In this case we
        % need to schedule a track revisit job.
        trackid = current_job.TrackID;
        tentativeTrackIDs = [tracks.tentativeTracks.TrackID];        
        confirmedTrackIDs = [tracks.confirmedTracks.TrackID];
        if any(trackid == tentativeTrackIDs)
            job = revisitTrackJob(tracker, trackid, current_time, managerPreferences, 'Confirm', tracks.PositionSelector);
            num_trackq_items = num_trackq_items+1;
            trackq(num_trackq_items) = job;                
        elseif any(trackid == confirmedTrackIDs)
            job = revisitTrackJob(tracker, trackid, current_time, managerPreferences, 'TrackNonManeuvering', tracks.PositionSelector);
            num_trackq_items = num_trackq_items+1;
            trackq(num_trackq_items) = job;                
        end

    otherwise % Covers both types of track jobs
        % For track job, if the track hasn't been dropped, update the track
        % and schedule a track job corresponding to the revisit time
        % regardless of having a detection. In the case when there is no
        % detection, we could also predict and schedule a track job sooner
        % so the target is not lost. This would require defining another
        % job type to control the revisit rate for this case.
        
        trackid = current_job.TrackID;
        confirmedTrackIDs = [tracks.confirmedTracks.TrackID];
        if any(trackid == confirmedTrackIDs)           
            jobType = 'TrackNonManeuvering';
            mdlProbs = getTrackFilterProperties(tracker, trackid, 'ModelProbabilities');
            if mdlProbs{1}(2) > 0.6
                jobType = 'TrackManeuvering';
            end

            job = revisitTrackJob(tracker, trackid, current_time, managerPreferences, jobType, tracks.PositionSelector);
            num_trackq_items = num_trackq_items+1;
            trackq(num_trackq_items) = job;
        end
end
    
jobq.TrackQueue   = trackq;
jobq.NumTrackJobs = num_trackq_items;
end

function job = revisitTrackJob(tracker, trackID, currentTime, managerPreferences, jobType, positionSelector)
    types = [managerPreferences.Type];
    inTypes = strcmpi(jobType,types);
    revisitTime = 1/managerPreferences(inTypes).RevisitRate + currentTime;
    predictedTrack = predictTracksToTime(tracker,trackID,revisitTime);

    xpred = getTrackPositions(predictedTrack,positionSelector); 
    
    [phipred,thetapred,rpred] = cart2sph(xpred(1),xpred(2),xpred(3));
    job = struct('JobType',jobType,'Priority',managerPreferences(inTypes).Priority,...
        'BeamDirection',rad2deg([phipred thetapred]),'WaveformIndex',1,'Time',revisitTime,...
        'Range',rpred,'TrackID',trackID);
    
end