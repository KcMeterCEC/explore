clear all;
clc;
close all;

kf = 2;
Am = 4e3*pi;
base_freq = 1e3;
carry_freq = 10e3;
fs = 10e4;

n = [1:fs];

fm_signal = cos(2*pi*carry_freq*n/fs + ...
    kf * Am * sin(2 * pi * base_freq * n / fs) / (2 * pi * base_freq));

figure;
subplot(2, 1, 1);
plot(fm_signal);
subplot(2, 1, 2);
plot(20 * log10(abs(fft(fm_signal))./fs));