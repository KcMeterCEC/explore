clear;
clc;

[audio_data, fs] = audioread("./audio.wav");

data_left = audio_data(:,1) .+ 1;
data_right = audio_data(:,2) .+ 1;
out_fs = 220500;

resample_left = resample(data_left(500000:700000), out_fs, fs);
resample_right = resample(data_right(500000:700000), out_fs, fs);

data_iq = complex(resample_left, resample_right);
audiowrite("./audio_out.wav", data_iq, out_fs);
