clear;
close all;
clc;

base_freq = 10;
base_amp = 3;

carry_freq = 100;
carry_amp = 1;
fs = 1024;

n = [1:fs];

pm_signal = carry_amp * cos(2 * pi * carry_freq * n / fs + ...
    base_amp * cos(2 * pi * base_freq * n / fs));

figure;
subplot(2, 1, 1);
plot(pm_signal);
subplot(2, 1, 2);
plot(20* log10(abs(fft(pm_signal)) ./ fs));