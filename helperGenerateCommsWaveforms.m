function [data, truth] = helperGenerateCommsWaveforms()

numFramesPerModType = 3000;
sps = 8;                % Samples per symbol
spf = 1024;             % Samples per frame
fs = 200e3;             % Sampling rate

%% Channel impairments

%AWGN
SNR = 30;

%CombinedChannel
channel = helperModClassTestChannel(...
  'SampleRate', fs, ...
  'SNR', SNR, ...
  'PathDelays', [0 1.8 3.4] / fs, ...
  'AveragePathGains', [0 -2 -10], ...
  'KFactor', 4, ...
  'MaximumDopplerShift', 4, ...
  'MaximumClockOffset', 5, ...
  'CenterFrequency', 900e6);

modulationTypes = categorical(["GFSK", "CPFSK", "B-FM", ...
    "DSB-AM", "SSB-AM"]);

numModulationTypes = length(modulationTypes);
transDelay = 50;
idx = 1;
for modType = 1:numModulationTypes
  dataSrc = getSource(modulationTypes(modType), sps, 2*spf, fs);
  modulator = getModulator(modulationTypes(modType), sps, fs);
  if contains(char(modulationTypes(modType)), {'B-FM','DSB-AM','SSB-AM'})
    % Analog modulation types use 100 MHz center frequency
    channel.CenterFrequency = 100e6;
  else
    % Digital modulation types use 900 MHz center frequency
    channel.CenterFrequency = 900e6;
  end
  
  for p=1:numFramesPerModType
    % Generate random data
    x = dataSrc();
    
    % Modulate
    y = modulator(x);
    
    % Pass through independent channels
    rxSamples = channel(y);
    
    % Remove transients from the beginning, trim to size, and normalize
    data{idx} = helperModClassFrameGenerator(rxSamples, spf, spf, transDelay, sps);
    truth(idx) = modulationTypes(modType);
    idx = idx + 1;
  end
end
end

%% Helper functions

function modulator = getModulator(modType, sps, fs)
%getModulator Modulation function selector
%   MOD = getModulator(TYPE,SPS,FS) returns a modulator function handle,
%   MOD, based on the TYPE. SPS is samples per symbol and FS is sampling
%   rate.

switch modType
    case "BPSK"
        modulator = @(x)bpskModulator(x,sps);
    case "QPSK"
        modulator = @(x)qpskModulator(x,sps);
    case "GFSK"
        modulator = @(x)gfskModulator(x,sps);
    case "CPFSK"
        modulator = @(x)cpfskModulator(x,sps);
    case "PAM4"
        modulator = @(x)pam4Modulator(x,sps);
    case "B-FM"
        modulator = @(x)bfmModulator(x, fs);
    case "DSB-AM"
        modulator = @(x)dsbamModulator(x, fs);
    case "SSB-AM"
        modulator = @(x)ssbamModulator(x, fs);
end
end

function src = getSource(modType, sps, spf, fs)
%getSource Source selector for modulation types
%    SRC=getSource(TYPE,SPS,SPF,FS) returns the data source
%    for modulation type, TYPE, with samples per symbol, SPS,
%    samples per frame, SPF, and sampling frequency, FS.

switch modType
    case {"BPSK","GFSK","CPFSK"}
        M = 2;
        src = @()randi([0 M-1],spf/sps,1);
    case {"QPSK","PAM4"}
        M = 4;
        src = @()randi([0 M-1],spf/sps,1);
    case {"B-FM","DSB-AM","SSB-AM"}
        src = @()getAudio(spf,fs);
end
end

function x = getAudio(spf,fs)
%getAudio Audio source for analog modulation types
%    A = getAudio(SPF,FS) returns an audio source, A, with
%    samples per frame, SPF, and sample rate, FS.

persistent audioSrc audioRC

if isempty(audioSrc)
    audioSrc = dsp.AudioFileReader('audio_mix_441.wav',...
        'SamplesPerFrame',spf,'PlayCount',inf);
    audioRC = dsp.SampleRateConverter('Bandwidth',30e3,...
        'InputSampleRate',audioSrc.SampleRate,...
        'OutputSampleRate',fs);
    [~,decimFactor] = getRateChangeFactors(audioRC);
    audioSrc.SamplesPerFrame = ceil(spf / fs * audioSrc.SampleRate / decimFactor) * decimFactor;
end

x = audioRC(audioSrc());
x = x(1:spf,1);
end

%% Modulators

function y = bpskModulator(x,sps)
%bpskModulator BPSK modulator with pulse shaping
%   Y=bpskModulator(X,SPS) BPSK modulates input, X, and returns a root-raised
%   cosine pulse shaped signal, Y. X must be a column vector of values in
%   the set of [0 1]. Root-raised cosine filter has a roll-off factor of
%   0.35 and spans four symbols. The output signal, Y, has unit power.

persistent filterCoeffs
if isempty(filterCoeffs)
  filterCoeffs = rcosdesign(0.35, 4, sps);
end
% Modulate
syms = pskmod(x,2);
% Pulse shape
y = filter(filterCoeffs, 1, upsample(syms,sps));
end

function y = qpskModulator(x,sps)
%qpskModulator QPSK modulator with pulse shaping
%   Y=qpskModulator(X,SPS) QPSK modulates input, X, and returns a root-raised
%   cosine pulse shaped signal, Y. X must be a column vector of values in
%   the set of [0 3]. Root-raised cosine filter has a roll-off factor of
%   0.35 and spans four symbols. The output signal, Y, has unit power.

persistent filterCoeffs
if isempty(filterCoeffs)
  filterCoeffs = rcosdesign(0.35, 4, sps);
end
% Modulate
syms = pskmod(x,4,pi/4);
% Pulse shape
y = filter(filterCoeffs, 1, upsample(syms,sps));
end

function y = pam4Modulator(x,sps)
%pam4Modulator PAM4 modulator with pulse shaping
%   Y=qam16Modulator(X,SPS) PAM4 modulates input, X, and returns a root-raised
%   cosine pulse shaped signal, Y. X must be a column vector of values in
%   the set of [0 3]. Root-raised cosine filter has a roll-off factor of
%   0.35 and spans four symbols. The output signal, Y, has unit power.

persistent filterCoeffs amp
if isempty(filterCoeffs)
  filterCoeffs = rcosdesign(0.35, 4, sps);
  amp = 1 / sqrt(mean(abs(pammod(0:3, 4)).^2));
end
% Modulate
syms = amp * pammod(x,4);
% Pulse shape
y = filter(filterCoeffs, 1, upsample(syms,sps));
end

function y = gfskModulator(x,sps)
%gfskModulator GFSK modulator
%   Y=gfskModulator(X,SPS) GFSK modulates input, X, and returns signal, Y. 
%   X must be a column vector of values in the set of [0 1]. BT product is
%   0.35 and modulation index is 1. The output signal, Y, has unit power.

persistent mod meanM
if isempty(mod)
  M = 2;
  mod = comm.CPMModulator(...
    'ModulationOrder', M, ...
    'FrequencyPulse', 'Gaussian', ...
    'BandwidthTimeProduct', 0.35, ...
    'ModulationIndex', 1, ...
    'SamplesPerSymbol', sps);
  meanM = mean(0:M-1);
end
% Modulate
y = mod(2*(x-meanM));
end

function y = cpfskModulator(x,sps)
%cpfskModulator CPFSK modulator
%   Y=cpfskModulator(X,SPS) CPFSK modulates input, X, and returns signal, Y. 
%   X must be a column vector of values in the set of [0 1]. Modulation 
%   index is 0.5. The output signal, Y, has unit power.

persistent mod meanM
if isempty(mod)
  M = 2;
  mod = comm.CPFSKModulator(...
    'ModulationOrder', M, ...
    'ModulationIndex', 0.5, ...
    'SamplesPerSymbol', sps);
  meanM = mean(0:M-1);
end
% Modulate
y = mod(2*(x-meanM));
end

function y = bfmModulator(x,fs)
%bfmModulator Broadcast FM modulator
%   Y=bfmModulator(X,FS) broadcast FM modulates input, X, and returns 
%   signal, Y, at a sample rate of FS. X must be a column vector of 
%   audio samples at sample rate of FS. Frequency deviation is 75 kHz 
%   and pre-emphasis filter time constant is 75 microseconds. 

persistent mod
if isempty(mod)
  mod = comm.FMBroadcastModulator(...
    'AudioSampleRate', fs, ...
    'SampleRate', fs);
end
y = mod(x);
end

function y = dsbamModulator(x,fs)
%dsbamModulator Double sideband AM modulator
%   Y=dsbamModulator(X,FS) double sideband AM modulates input, X, and 
%   returns signal, Y, at a sample rate of FS. X must be a column vector of 
%   audio samples at sample rate of FS. IF frequency is 50 kHz. 

y = ammod(x,50e3,fs);
end

function y = ssbamModulator(x,fs)
%ssbamModulator Single sideband AM modulator
%   Y=ssbamModulator(X,FS) single sideband AM modulates input, X, and 
%   returns signal, Y, at a sample rate of FS. X must be a column vector of 
%   audio samples at sample rate of FS. IF frequency is 50 kHz. 

y = ssbmod(x,50e3,fs);
end
