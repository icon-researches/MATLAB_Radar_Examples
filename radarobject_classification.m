c = 3e8;
fc = 850e6;
[cylrcs,az,el] = rcscylinder(1,1,10,c,fc);
helperTargetRCSPatternPlot(az,el,cylrcs);

cyltgt = phased.BackscatterRadarTarget('PropagationSpeed',c,...
    'OperatingFrequency',fc,'AzimuthAngles',az,'ElevationAngles',el,'RCSPattern',cylrcs);

rng default;
N = 100;
az = 2*randn(1,N);                  
el = 2*randn(1,N);
cylrtn = cyltgt(ones(1,N),[az;el]);  


plot(mag2db(abs(cylrtn)));
xlabel('Time Index')
ylabel('Target Return (dB)');
title('Target Return for Cylinder');

load('RCSClassificationReturnsTraining');
load('RCSClassificationReturnsTest');

subplot(2,2,1)
plot(cylinderAspectAngle(1,:))
ylim([-90 90])
grid on
title('Cylinder Aspect Angle vs. Time'); xlabel('Time Index'); ylabel('Aspect Angle (degrees)');
subplot(2,2,3)
plot(RCSReturns.Cylinder_1); ylim([-50 50]);
grid on
title('Cylinder Return'); xlabel('Time Index'); ylabel('Target Return (dB)');
subplot(2,2,2)
plot(coneAspectAngle(1,:)); ylim([-90 90]); grid on;
title('Cone Aspect Angle vs. Time'); xlabel('Time Index'); ylabel('Aspect Angle (degrees)');
subplot(2,2,4);
plot(RCSReturns.Cone_1); ylim([-50 50]); grid on;
title('Cone Return'); xlabel('Time Index'); ylabel('Target Return (dB)');

sn = waveletScattering('SignalLength',701,'InvarianceScale',701,'QualityFactors',[4 2]);
sTrain = sn.featureMatrix(RCSReturns{:,:},'transform','log');
sTest = sn.featureMatrix(RCSReturnsTest{:,:},'transform','log');

TrainFeatures = squeeze(mean(sTrain,2))';
TestFeatures = squeeze(mean(sTest,2))';

TrainLabels = repelem(categorical({'Cylinder','Cone'}),[50 50])';
TestLabels = repelem(categorical({'Cylinder','Cone'}),[25 25])';

template = templateSVM('KernelFunction', 'polynomial', ...
    'PolynomialOrder', 2, ...
    'KernelScale', 'auto', ...
    'BoxConstraint', 1, ...
    'Standardize', true);
classificationSVM = fitcecoc(...
    TrainFeatures, ...
    TrainLabels, ...
    'Learners', template, ...
    'Coding', 'onevsone', ...
    'ClassNames', categorical({'Cylinder','Cone'}));
partitionedModel = crossval(classificationSVM, 'KFold', 5);
[validationPredictions, validationScores] = kfoldPredict(partitionedModel);
validationAccuracy = (1 - kfoldLoss(partitionedModel, 'LossFun', 'ClassifError'))*100;

predLabels = predict(classificationSVM,TestFeatures);
accuracy = sum(predLabels == TestLabels )/numel(TestLabels)*100;

figure('Units','normalized','Position',[0.2 0.2 0.5 0.5]);
ccDCNN = confusionchart(TestLabels,predLabels);
ccDCNN.Title = 'Confusion Chart';
ccDCNN.ColumnSummary = 'column-normalized';
ccDCNN.RowSummary = 'row-normalized';

snet = squeezenet;
snet.Layers(1)
snet.Layers(68)

rng default;
idxCylinder = randperm(50,2);
idxCone = randperm(50,2)+50;

cwt(RCSReturns{:,idxCylinder(1)},'VoicesPerOctave',8)
cwt(RCSReturns{:,idxCone(2)},'VoicesPerOctave',8);

parentDir = tempdir;
helpergenWaveletTFImg(parentDir,RCSReturns,RCSReturnsTest)

trainingData= imageDatastore(fullfile(parentDir,'Training'), 'IncludeSubfolders', true,...
    'LabelSource', 'foldernames');
testData = imageDatastore(fullfile(parentDir,'Test'),'IncludeSubfolders',true,...
    'LabelSource','foldernames');

lgraphSqueeze = layerGraph(snet);
convLayer = lgraphSqueeze.Layers(64);
numClasses = numel(categories(trainingData.Labels));
newLearnableLayer = convolution2dLayer(1,numClasses, ...
        'Name','binaryconv', ...
        'WeightLearnRateFactor',10, ...
        'BiasLearnRateFactor',10);
lgraphSqueeze = replaceLayer(lgraphSqueeze,convLayer.Name,newLearnableLayer);
classLayer = lgraphSqueeze.Layers(end);
newClassLayer = classificationLayer('Name','binary');
lgraphSqueeze = replaceLayer(lgraphSqueeze,classLayer.Name,newClassLayer);

ilr = 1e-4;
mxEpochs = 15;
mbSize =10;
opts = trainingOptions('sgdm', 'InitialLearnRate', ilr, ...
    'MaxEpochs',mxEpochs , 'MiniBatchSize',mbSize, ...
    'Plots', 'training-progress','ExecutionEnvironment','gpu');

CWTnet = trainNetwork(trainingData,lgraphSqueeze,opts);

predictedLabels = classify(CWTnet,testData,'ExecutionEnvironment','gpu');
accuracy = sum(predictedLabels == testData.Labels)/50*100;

figure('Units','normalized','Position',[0.2 0.2 0.5 0.5]);
ccDCNN = confusionchart(testData.Labels,predictedLabels);
ccDCNN.Title = 'Confusion Chart';
ccDCNN.ColumnSummary = 'column-normalized';
ccDCNN.RowSummary = 'row-normalized';

LSTMlayers = [ ...
    sequenceInputLayer(1)
    bilstmLayer(100,'OutputMode','last')
    fullyConnectedLayer(2)
    softmaxLayer
    classificationLayer
    ];
options = trainingOptions('adam', ...
    'MaxEpochs',30, ...
    'MiniBatchSize', 150, ...
    'InitialLearnRate', 0.01, ...
    'GradientThreshold', 1, ...
    'plots','training-progress', ...
    'Verbose',false,'ExecutionEnvironment','gpu');
trainLabels = repelem(categorical({'cylinder','cone'}),[50 50]);
trainLabels = trainLabels(:);
trainData = num2cell(table2array(RCSReturns)',2);
testData = num2cell(table2array(RCSReturnsTest)',2);
testLabels = repelem(categorical({'cylinder','cone'}),[25 25]);
testLabels = testLabels(:);
RNNnet = trainNetwork(trainData,trainLabels,LSTMlayers,options);

predictedLabels = classify(RNNnet,testData,'ExecutionEnvironment','gpu');
accuracy = sum(predictedLabels == testLabels)/50*100;