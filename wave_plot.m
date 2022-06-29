file_name = '(sine+square)_1kHz_100_amplitude_18dB_20000.txt';
wave_datset = importdata(file_name);
sampling_frequenc = 1000;
signal_length = 100;
tiledlayout(2,1)

%time domain
nexttile
signals = abs(wave_datset(10010, 1:100));
plot(signals)
title('time domain')

%frequency domain
nexttile
normalized_siganls = normalize(signals, 'range');
normalized_siganls = normalized_siganls - mean(normalized_siganls);
signals_fft = fft(normalized_siganls);
p2 = abs(signals_fft / signal_length);
p1 = p2(1:signal_length / 2 + 1);
p1(2:end - 1) = 2 * p1(2:end - 1);
frequency = sampling_frequenc * (0:(signal_length / 2)) / signal_length;
plot(frequency, p1)
title('frequency domain')