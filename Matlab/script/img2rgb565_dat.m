clear;clc;close all;

script_dir = fileparts(mfilename('fullpath'));
cd(script_dir);

BUFFER_INTERVAL = 16;
MEM_ADDRESS_WIDTH = 20;
MEM_UNIT_WIDTH = 32;

origin_path = '../test img/origin/venus/';
resize_path = '../test img/resize/venus/';

if ~exist(resize_path, 'dir')
    mkdir(resize_path);
end

disp('==============================');
disp('开始处理图像...');
disp('==============================');

%% ====================== 1. 处理左目图像 ======================
disp(' ');
disp('[Step 1] 处理左目图像 im2');
im0 = imread([origin_path, 'im2.ppm']);
disp(['  原始尺寸: ', num2str(size(im0,2)), ' x ', num2str(size(im0,1))]);

im0_resize = imresize(im0, [480, 640]);
disp(['  Resize到: 640 x 480']);

[im0_rgb565, im0_rgb888] = rgb2rgb565(im0_resize);
disp('  RGB565转换完成');

%% ====================== 2. 处理右目图像 ======================
disp(' ');
disp('[Step 2] 处理右目图像 im6');
im1 = imread([origin_path, 'im6.ppm']);
disp(['  原始尺寸: ', num2str(size(im1,2)), ' x ', num2str(size(im1,1))]);

im1_resize = imresize(im1, [480, 640]);
disp(['  Resize到: 640 x 480']);

[im1_rgb565, im1_rgb888] = rgb2rgb565(im1_resize);
disp('  RGB565转换完成');

%% ====================== 3. 写入DAT文件 ======================
disp(' ');
disp('[Step 3] 写入DAT文件');
datFilePath = [resize_path, 'test_img.dat'];

total_mem_words = 2 ^ MEM_ADDRESS_WIDTH;
written_words = 0;

left_img_words = 480 * 320;
right_img_words = 480 * 320;
padding_words = BUFFER_INTERVAL * 32 / 8 / 4;

fid = fopen(datFilePath, 'w');

write_img_to_dat(fid, im0_rgb565);
written_words = written_words + left_img_words;
disp(['  左目图像写入完成, 已写入 ', num2str(written_words), ' 字']);

disp(['  填充 ', num2str(padding_words * 4), ' 字节 (', num2str(padding_words), ' 字) 缓冲区对齐...']);
for i = 1:padding_words
    fprintf(fid, '00000000 ');
    written_words = written_words + 1;
end

write_img_to_dat(fid, im1_rgb565);
written_words = written_words + right_img_words;
disp(['  右目图像写入完成, 已写入 ', num2str(written_words), ' 字']);

final_padding_words = total_mem_words - written_words;
if final_padding_words > 0
    disp(['  MEM容量填充: 补充 ', num2str(final_padding_words), ' 字 (', num2str(final_padding_words * 4), ' 字节)...']);
    for i = 1:final_padding_words
        fprintf(fid, '00000000 ');
    end
end

fclose(fid);

disp(' ');
disp('==============================');
disp('处理完成!');
disp(['文件位置: ', datFilePath]);
disp(['左目像素数: 640 x 480 = ', num2str(640*480)]);
disp(['右目像素数: 640 x 480 = ', num2str(640*480)]);
disp(['缓冲区对齐填充: ', num2str(padding_words), ' 字 (', num2str(padding_words * 4), ' 字节)']);
disp(['MEM总容量: 2^', num2str(MEM_ADDRESS_WIDTH), ' = ', num2str(total_mem_words), ' 字']);
disp(['文件总大小: ', num2str(total_mem_words * 4), ' 字节']);
disp('==============================');

%% ====================== 4. 回读验证 ======================
disp(' ');
disp(' ');
disp('==============================');
disp('开始回读验证...');
disp('==============================');

rd_left_rgb888 = read_dat_to_rgb888(datFilePath, 0, 480, 640);
rd_right_rgb888 = read_dat_to_rgb888(datFilePath, left_img_words + padding_words, 480, 640);

disp(' ');
disp('----------- 左目图像 回读对比 -----------');
[psnrL, maeL, maxErrL, mismatchL, totalL] = compare_images(im0_rgb888, rd_left_rgb888, 'left');

disp(' ');
disp('----------- 右目图像 回读对比 -----------');
[psnrR, maeR, maxErrR, mismatchR, totalR] = compare_images(im1_rgb888, rd_right_rgb888, 'right');

disp(' ');
disp('==============================');
disp('回读验证汇总');
disp('==============================');
fprintf('  左目 PSNR: %.2f dB,  MAE: %.2f,  最大误差: %d,  失配像素: %d / %d (%.4f%%)\n', ...
    psnrL, maeL, maxErrL, mismatchL, totalL, mismatchL/totalL*100);
fprintf('  右目 PSNR: %.2f dB,  MAE: %.2f,  最大误差: %d,  失配像素: %d / %d (%.4f%%)\n', ...
    psnrR, maeR, maxErrR, mismatchR, totalR, mismatchR/totalR*100);

if mismatchL == 0 && mismatchR == 0
    disp(' ');
    disp('  ✅ 完全一致！DAT文件回读与原始图像数据完全匹配。');
else
    disp(' ');
    disp('  ⚠️ 存在差异，请检查上述失配像素分布。');
end
disp('==============================');

%% ====================== 5. 可视化对比 ======================
disp(' ');
disp('[Step 5] 显示原始图像与回读图像对比...');

% 差图像：放大差异便于肉眼观察 (差值 * 10 + 128)
diff_left  = abs(double(rd_left_rgb888)  - double(im0_rgb888));
diff_right = abs(double(rd_right_rgb888) - double(im1_rgb888));
diff_left_vis  = uint8(min(255, diff_left  * 10 + 128));
diff_right_vis = uint8(min(255, diff_right * 10 + 128));

figure('Name', '左目图像 - 原始 vs 回读对比', 'NumberTitle', 'off', 'Position', [50, 100, 1600, 500]);
subplot(1,3,1);
imshow(im0_rgb888);
title('原始图像 (RGB888)');
subplot(1,3,2);
imshow(rd_left_rgb888);
title('DAT回读图像 (RGB888)');
subplot(1,3,3);
imshow(diff_left_vis);
title('差值 (×10+128)');

figure('Name', '右目图像 - 原始 vs 回读对比', 'NumberTitle', 'off', 'Position', [50, 620, 1600, 500]);
subplot(1,3,1);
imshow(im1_rgb888);
title('原始图像 (RGB888)');
subplot(1,3,2);
imshow(rd_right_rgb888);
title('DAT回读图像 (RGB888)');
subplot(1,3,3);
imshow(diff_right_vis);
title('差值 (×10+128)');

disp('  可视化对比窗口已打开，请查看 Figure 窗口。');


%% ======================================================================
%  将RGB888图像转换为RGB565，同时返回量化后的RGB888用于回读对比
% ======================================================================
function [rgb565_img, rgb888_quant] = rgb2rgb565(rgb_img)
    [H, W, ~] = size(rgb_img);
    rgb565_img = zeros(H, W, 'uint16');
    rgb888_quant = zeros(H, W, 3, 'uint8');

    for row = 1:H
        for col = 1:W
            r5 = bitand(bitshift(uint16(rgb_img(row,col,1)), -3), 31);
            g6 = bitand(bitshift(uint16(rgb_img(row,col,2)), -2), 63);
            b5 = bitand(bitshift(uint16(rgb_img(row,col,3)), -3), 31);
            rgb565_img(row,col) = bitor(bitor(bitshift(r5, 11), bitshift(g6, 5)), b5);

            rgb888_quant(row, col, 1) = uint8(bitshift(r5, 3));
            rgb888_quant(row, col, 2) = uint8(bitshift(g6, 2));
            rgb888_quant(row, col, 3) = uint8(bitshift(b5, 3));
        end
    end
end


%% ======================================================================
%  将RGB565图像写入DAT文件（按32位字写入，每字2像素）
% ======================================================================
function write_img_to_dat(fid, rgb565_img)
    [H, W] = size(rgb565_img);
    for row = 1:H
        for col = 1:2:W
            pix0 = uint32(rgb565_img(row, col));
            if col + 1 <= W
                pix1 = uint32(rgb565_img(row, col + 1));
            else
                pix1 = uint32(0);
            end
            mem_word = bitor(bitshift(pix1, 16), pix0);
            fprintf(fid, '%08X ', mem_word);
        end
    end
end


%% ======================================================================
%  从DAT文件回读图像数据，转换为RGB888
%  startWord : 起始字偏移（0-based）
%  H, W     : 图像高度、宽度（像素）
% ======================================================================
function rgb888_img = read_dat_to_rgb888(datFilePath, startWord, H, W)
    fid = fopen(datFilePath, 'r');
    if fid == -1
        error('无法打开文件: %s', datFilePath);
    end

    allData = textscan(fid, '%s');
    fclose(fid);

    hexWords = allData{1};
    totalWords = length(hexWords);

    rgb888_img = zeros(H, W, 3, 'uint8');

    wordsPerRow = W / 2;
    expectedWords = H * wordsPerRow;

    if startWord + expectedWords > totalWords
        error('文件字数不足: 需要从第 %d 字开始读取 %d 字，但文件仅有 %d 字', ...
            startWord, expectedWords, totalWords);
    end

    for row = 1:H
        for sub = 1:wordsPerRow
            wordIdx = startWord + (row - 1) * wordsPerRow + sub;
            wordVal = uint32(hex2dec(hexWords{wordIdx}));

            pix0_565 = bitand(wordVal, uint32(65535));
            pix1_565 = bitshift(wordVal, -16);

            col0 = (sub - 1) * 2 + 1;
            col1 = col0 + 1;

            r5 = bitand(bitshift(pix0_565, -11), uint32(31));
            g6 = bitand(bitshift(pix0_565, -5),  uint32(63));
            b5 = bitand(pix0_565, uint32(31));
            rgb888_img(row, col0, 1) = uint8(bitshift(r5, 3));
            rgb888_img(row, col0, 2) = uint8(bitshift(g6, 2));
            rgb888_img(row, col0, 3) = uint8(bitshift(b5, 3));

            if col1 <= W
                r5 = bitand(bitshift(pix1_565, -11), uint32(31));
                g6 = bitand(bitshift(pix1_565, -5),  uint32(63));
                b5 = bitand(pix1_565, uint32(31));
                rgb888_img(row, col1, 1) = uint8(bitshift(r5, 3));
                rgb888_img(row, col1, 2) = uint8(bitshift(g6, 2));
                rgb888_img(row, col1, 3) = uint8(bitshift(b5, 3));
            end
        end
    end
end


%% ======================================================================
%  对比两幅RGB888图像，输出PSNR/MAE/最大误差/失配像素数
% ======================================================================
function [psnr, mae, maxErr, mismatchCnt, totalPixels] = compare_images(im_ref, im_test, nameStr)
    diff_img = double(im_test) - double(im_ref);
    sqErr = diff_img .^ 2;
    absErr = abs(diff_img);

    mse = mean(sqErr(:));
    if mse < 1e-10
        psnr = Inf;
    else
        psnr = 10 * log10(255^2 / mse);
    end

    mae = mean(absErr(:));
    maxErr = max(absErr(:));

    errPerPixel = sum(absErr, 3);
    mismatchCnt = sum(errPerPixel(:) > 0);
    totalPixels = size(im_ref, 1) * size(im_ref, 2);

    fprintf('  %s: MSE=%.4f, PSNR=%.2f dB, MAE=%.4f, 最大误差=%d\n', ...
        nameStr, mse, psnr, mae, maxErr);
    fprintf('  失配像素: %d / %d (%.4f%%)\n', mismatchCnt, totalPixels, mismatchCnt/totalPixels*100);

    if mismatchCnt > 0
        [rows, cols] = find(sum(absErr, 3) > 0);
        fprintf('  失配像素位置（前20个）: ');
        for k = 1:min(20, length(rows))
            fprintf('(%d,%d)[R%+d,G%+d,B%+d] ', rows(k), cols(k), ...
                int16(diff_img(rows(k), cols(k), 1)), ...
                int16(diff_img(rows(k), cols(k), 2)), ...
                int16(diff_img(rows(k), cols(k), 3)));
        end
        fprintf('\n');
    end
end
