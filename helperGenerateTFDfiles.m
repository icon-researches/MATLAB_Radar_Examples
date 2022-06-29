function helperGenerateTFDfiles(parentDir,dataDir,wav,truth,Fs)
% This function is only intended to support
% ModClassificationOfRadarAndCommSignalsExample. It may change or be
% removed in a future release.
    
[~,~,~] = mkdir(fullfile(parentDir,dataDir));
modTypes = unique(truth);

for idxM = 1:length(modTypes)
    modType = modTypes(idxM);
    [~,~,~] = mkdir(fullfile(parentDir,dataDir,char(modType)));
end
    
for idxW = 1:length(truth)
   sig = wav{idxW};
   TFD = wvd(sig,Fs,'smoothedPseudo',kaiser(101,20),kaiser(101,20),'NumFrequencyPoints',500,'NumTimePoints',500);
   TFD = imresize(TFD,[227 227]);
   TFD = rescale(TFD);
   modType = truth(idxW);
   
   imwrite(TFD,fullfile(parentDir,dataDir,char(modType),sprintf('%d.png',idxW)))
    
    
end
end