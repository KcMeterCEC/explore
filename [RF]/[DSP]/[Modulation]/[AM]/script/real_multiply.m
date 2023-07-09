clear;
clc;
close all;

% 采样率及信号频率
fs = 10240;
f1 = 100;
f2 = 300;
n = [1:fs];

% 产生信号
signal_f1 = cos(2*pi*f1*n/fs);
signal_f2 = cos(2*pi*f2*n/fs);

% 相乘
signal_multiply = signal_f1 .* signal_f2;

% 绘制
figure;
subplot(3, 1, 1);
plot(signal_f1);title("100Hz");
subplot(3, 1, 2);
plot(signal_f2);title("300Hz");
subplot(3, 1, 3);
plot(abs(fft(signal_multiply))./fs);title("fft");
