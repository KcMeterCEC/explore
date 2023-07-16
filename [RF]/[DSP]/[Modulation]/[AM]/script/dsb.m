close all;
clear;
clc;

fs=1024;
f1=10;
f2=100;

t=0:1/fs:(fs-1)/fs;

% 产生基带信号
base_cos = cos(2*pi*f1*t);
% 产生载波信号
carry_cos = cos(2*pi*f2*t);
% 调制后的信号
s_modulate = (base_cos).* carry_cos;
% 解调后的信号
s_demodulate = s_modulate.* carry_cos;

s_fft = fft(s_modulate);
s_fft_abs = abs(s_fft) ./ fs;

s_fft_demodu = fft(s_demodulate);
s_fft_demodu_abs = abs(s_fft_demodu)./fs;

figure;
subplot(5,1,1);
plot(base_cos);title("base band");
subplot(5,1,2);
plot(carry_cos);title("carrier");
subplot(5,1,3);
plot(s_modulate);title("modulate");
subplot(5,1,4);
plot(s_fft_abs);title("fft");
subplot(5,1,5);
plot(s_fft_demodu_abs);title("fft demodu");
