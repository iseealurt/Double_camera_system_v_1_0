clear; clc; close all;

[filename, pathname] = uigetfile(...
    {'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff', ...
     '图像文件 (*.jpg, *.jpeg, *.png, *.bmp, *.tif, *.tiff)'}, ...
    '请选择一张图片');

if filename == 0
    error('用户取消了图片选择。');
end

img_path = fullfile(pathname, filename);
img_original = imread(img_path);

if size(img_original, 3) == 3
    img_gray = rgb2gray(img_original);
else
    img_gray = img_original;
end

img_double = im2double(img_gray);

sigma = 1;
gauss_kernel = fspecial('gaussian', [5, 5], sigma);

img_filtered = imfilter(img_double, gauss_kernel, 'replicate');

figure('Name', '5x5 高斯滤波结果', 'NumberTitle', 'off');

subplot(2, 3, 1);
imagesc(img_double);
colormap(gray); axis image off;
title('原图 (灰度)');

subplot(2, 3, 2);
imagesc(img_filtered);
colormap(gray); axis image off;
title('5x5 高斯滤波后');

subplot(2, 3, 3);
imagesc(img_double - img_filtered);
colormap(gray); axis image off;
title('差图 (原图 - 滤波)');

mid_row = round(size(img_double, 1) / 2);
subplot(2, 3, 4);
plot(1:size(img_double, 2), img_double(mid_row, :), 'b-', ...
     1:size(img_double, 2), img_filtered(mid_row, :), 'r-', 'LineWidth', 1);
xlabel('列'); ylabel('灰度值');
title('中间行灰度剖面对比');
legend({'原图', '滤波后'}, 'Location', 'best');
grid on;

subplot(2, 3, 5);
mid_col = round(size(img_double, 2) / 2);
plot(img_double(:, mid_col), 'b-', ...
     img_filtered(:, mid_col), 'r-', 'LineWidth', 1);
xlabel('行'); ylabel('灰度值');
title('中间列灰度剖面对比');
legend({'原图', '滤波后'}, 'Location', 'best');
grid on;

subplot(2, 3, 6);
surf(img_filtered(1:4:end, 1:4:end), 'EdgeColor', 'none', 'FaceAlpha', 0.8);
colormap(jet); axis tight;
title('滤波后图像表面图');
xlabel('列'); ylabel('行'); zlabel('灰度值');

disp('=== 5x5 高斯滤波完成 ===');
disp(['高斯核标准差 sigma = ', num2str(sigma)]);
disp(['高斯核:']);
disp(gauss_kernel);
