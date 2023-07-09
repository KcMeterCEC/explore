close all;
clear;
clc;

fs=1024;
f1=10;
f2=100;

t=0:1/fs:(fs-1)/fs;

% 产生基带信号
base = cos(2*pi*f1*t) + sin(2*pi*f1*t) * 1i;
% 产生载波信号
carry = cos(2*pi*f2*t) + sin(2*pi*f2*t) * 1i;
% 调制后的信号
s_modulate = (1 + base).* carry;

s_fft = fft(s_modulate);
s_fft_abs = abs(s_fft) ./ fs;

figure;
subplot(2,1,1);
plot(real(base));title("base band real");
subplot(2,1,2);
plot(imag(base));title("base band imag");

figure;
subplot(2,1,1);
plot(real(carry));title("carrier real");
subplot(2,1,2);
plot(imag(carry));title("carrier imag");

figure;
subplot(2,1,1);
plot(real(s_modulate));title("modulate real");
subplot(2,1,2);
plot(imag(s_modulate));title("modulate imag");

figure;plot(s_fft_abs);title("fft");
