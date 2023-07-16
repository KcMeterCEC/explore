close all;
clear;
clc;

fs=10240;
f1=100;
f2=1e3;
fft_size = 8192;

t=0:1/fs:(fs-1)/fs;

% 产生基带信号
base_cos = 2 * cos(2*pi*f1*t);
% 产生载波信号
carry_cos = cos(2*pi*f2*t);
% 调制后的信号
s_modulate = (0.5 + base_cos).* carry_cos;

s_fft = fft(s_modulate(1:fft_size));
s_fft_abs = abs(s_fft) ./ fft_size;

figure;
subplot(4,1,1);
plot(base_cos);title("base band");
subplot(4,1,2);
plot(carry_cos);title("carrier");
subplot(4,1,3);
plot(s_modulate);title("modulate");
subplot(4,1,4);
plot(s_fft_abs);title("fft");
