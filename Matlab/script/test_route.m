%% ============================================================
%  WTA disparity post-processing verification
%
%  Input:
%      .dat file, format: "02 80 01 e0 03 型" (dat2img 格式)
%      header: [width_H, width_L, height_H, height_L, data_type]
%      data_type = 3 → disparity (int8: MSB=valid, lower7=disparity)
%
%  Pipeline:
%      raw WTA disparity (.dat)
%        -> disparity range check
%        -> 3x3 valid-aware median   (去除孤立噪点)
%        -> horizontal box fill      (前景优先填充空洞)
%        -> 4-direction recursive fill  (方向传播填充剩余空洞)
%        -> 5x5 Gaussian smoothing   (平滑量化噪声)
%
%  Author: for FPGA WTA disparity post-process verification
%% ============================================================

clear; clc; close all;

%% ---------------- User parameters ----------------

[file_name, path_name] = uigetfile('*.dat', '选择 WTA 视差 .dat 文件');

if isequal(file_name, 0)
    disp('用户取消选择，使用默认文件');
    default_path = '..\..\Bench\tb_sgm_new_task_5_disparity_gray.png';
    warning('No .dat selected, falling back to PNG demo mode.');
    fallback_to_png = true;
else
    full_path = fullfile(path_name, file_name);
    disp(['选中文件: ', full_path]);
    fallback_to_png = false;
end

IMG_W = 640;
IMG_H = 480;

MAX_DISP = 47;

DISP_MIN = 1;
DISP_MAX = MAX_DISP;

% valid-aware median 参数
MED_WIN = 3;
MIN_VALID_FOR_MED = 5;      % 3x3窗口中至少5个有效点才输出有效median

% 横向盒滤波参数
HBOX_HALF_LEN = 5;          % 半窗长，总窗口 = 2*HALF_LEN + 1 = 11
MIN_VALID_HBOX = 2;         % 水平窗口内至少 N 个有效点才进行填充
HBOX_FILL_MODE = 'max';     % 前景优先

% 递归方向填充参数
RECURSIVE_DIRS = {'L->R', 'T->B', 'LT->RB', 'RT->LB'};  % 按顺序执行

% 5x5 高斯核
GAUSS_SIGMA = 1.0;

%% ---------------- Read input ----------------

if fallback_to_png
    img = imread(default_path);
    if size(img, 3) == 3
        img = rgb2gray(img);
    end
    img = double(img);
    [H, W] = size(img);
    if H ~= IMG_H || W ~= IMG_W
        warning('Input image size is %dx%d, expected %dx%d.', W, H, IMG_W, IMG_H);
    end
    disp_raw = round(img / 255 * MAX_DISP);
    disp_raw = max(0, min(MAX_DISP, disp_raw));
    valid0 = (disp_raw >= DISP_MIN) & (disp_raw <= DISP_MAX);
else
    [disp_raw, valid0] = read_disparity_dat(full_path, IMG_W, IMG_H, MAX_DISP, DISP_MIN, DISP_MAX);
end

hole_count0 = sum(~valid0(:));
total_pix   = IMG_W * IMG_H;
fprintf('Raw: holes = %d / %d (%.1f%%)\n', hole_count0, total_pix, 100*hole_count0/total_pix);

%% ---------------- Stage 1: 3x3 valid-aware median (pre-filter) ----------------

fprintf('Stage 1: 3x3 valid-aware median (min_valid=%d) ...\n', MIN_VALID_FOR_MED);

[disp_median, valid_median] = valid_aware_median( ...
    disp_raw, valid0, MED_WIN, MIN_VALID_FOR_MED);

hole_count1 = sum(~valid_median(:));
fprintf('  After median: holes = %d / %d (%.1f%%)\n', hole_count1, total_pix, 100*hole_count1/total_pix);

%% ---------------- Stage 2: Horizontal box filter hole filling ----------------

fprintf('Stage 2: Horizontal box fill (mode=%s, half_len=%d, min_valid=%d) ...\n', ...
    HBOX_FILL_MODE, HBOX_HALF_LEN, MIN_VALID_HBOX);

[disp_filled, valid_filled] = horizontal_box_fill( ...
    disp_median, valid_median, HBOX_HALF_LEN, MIN_VALID_HBOX, HBOX_FILL_MODE);

hole_count2 = sum(~valid_filled(:));
fprintf('  After fill: holes = %d / %d (%.1f%%)\n', hole_count2, total_pix, 100*hole_count2/total_pix);

%% ---------------- Stage 3: 4-direction recursive fill ----------------

fprintf('Stage 3: 4-direction recursive fill ...\n');

[disp_recursive, valid_recursive] = recursive_directional_fill( ...
    disp_filled, valid_filled, RECURSIVE_DIRS);

hole_count3 = sum(~valid_recursive(:));
fprintf('  After recursive: holes = %d / %d (%.1f%%)\n', hole_count3, total_pix, 100*hole_count3/total_pix);

%% ---------------- Stage 4: 5x5 Gaussian smoothing ----------------

fprintf('Stage 4: 5x5 Gaussian smoothing (sigma=%.1f) ...\n', GAUSS_SIGMA);

disp_smooth = gaussian_5x5(disp_recursive, valid_recursive, GAUSS_SIGMA);

%% ---------------- Visualization ----------------

figure('Name', 'WTA Disparity Post Processing', 'Position', [100 100 1600 1100]);

% Row 1: 中间结果视差图
subplot(4,3,1);
imagesc(disp_raw, [0 MAX_DISP]);
axis image off;
colormap(gca, gray);
colorbar;
title(sprintf('Raw (holes=%d)', hole_count0));

subplot(4,3,2);
imagesc(disp_median, [0 MAX_DISP]);
axis image off;
colormap(gca, gray);
colorbar;
title(sprintf('After median (holes=%d)', hole_count1));

subplot(4,3,3);
imagesc(disp_filled, [0 MAX_DISP]);
axis image off;
colormap(gca, gray);
colorbar;
title(sprintf('After hbox fill (holes=%d)', hole_count2));

% Row 2: 更多中间结果
subplot(4,3,4);
imagesc(disp_recursive, [0 MAX_DISP]);
axis image off;
colormap(gca, gray);
colorbar;
title(sprintf('After recursive (holes=%d)', hole_count3));

subplot(4,3,5);
imagesc(disp_smooth, [0 MAX_DISP]);
axis image off;
colormap(gca, gray);
colorbar;
title('After 5x5 Gaussian');

subplot(4,3,6);
diff_map = abs(disp_smooth - disp_raw);
imagesc(diff_map, [0 10]);
axis image off;
colorbar;
title('|Final - Raw| (0~10)');

% Row 3: 有效掩膜
subplot(4,3,7);
imshow(valid0);
title(sprintf('Valid raw (%d)', hole_count0));

subplot(4,3,8);
imshow(valid_median);
title(sprintf('Valid after median (%d)', hole_count1));

subplot(4,3,9);
imshow(valid_filled);
title(sprintf('Valid after hbox (%d)', hole_count2));

% Row 4: 掩膜 + 空洞趋势图
subplot(4,3,10);
imshow(valid_recursive);
title(sprintf('Valid after recursive (%d)', hole_count3));

subplot(4,3,11:12);
holes = [hole_count0, hole_count1, hole_count2, hole_count3];
labels = {'Raw','Median','HBox','Recur'};
bar(holes, 'FaceColor', [0.3 0.6 0.9]);
set(gca, 'XTickLabel', labels);
ylabel('Hole count');
grid on;
for i = 1:4
    text(i, holes(i)+1000, sprintf('%d\n(%.1f%%)', holes(i), 100*holes(i)/total_pix), ...
        'HorizontalAlignment', 'center', 'FontSize', 9);
end
title('Hole reduction progression');

sgtitle(sprintf('Pipeline: Median%d x%d + HBOX%d-%s + 4-dir Recur + Gauss5x5', ...
    MED_WIN, MED_WIN, 2*HBOX_HALF_LEN+1, HBOX_FILL_MODE));

%% ---------------- Save outputs ----------------

out_dir = fileparts(which(mfilename));
if isempty(out_dir)
    out_dir = pwd;
end

out_raw       = fullfile(out_dir, 'disparity_raw.png');
out_median    = fullfile(out_dir, 'disparity_median.png');
out_fill      = fullfile(out_dir, 'disparity_filled.png');
out_recursive = fullfile(out_dir, 'disparity_recursive.png');
out_smoothed  = fullfile(out_dir, 'disparity_smoothed.png');

imwrite(uint8(round(disp_raw       / MAX_DISP * 255)),  out_raw);
imwrite(uint8(round(disp_median    / MAX_DISP * 255)),  out_median);
imwrite(uint8(round(disp_filled    / MAX_DISP * 255)),  out_fill);
imwrite(uint8(round(disp_recursive / MAX_DISP * 255)),  out_recursive);
imwrite(uint8(round(disp_smooth    / MAX_DISP * 255)),  out_smoothed);

fprintf('\nSaved:\n');
fprintf('  %s\n', out_raw);
fprintf('  %s\n', out_median);
fprintf('  %s\n', out_fill);
fprintf('  %s\n', out_recursive);
fprintf('  %s\n', out_smoothed);
fprintf('Done.\n');

%% ============================================================
%  Local functions
%% ============================================================

function [disp_data, valid_mask] = read_disparity_dat(filepath, img_w, img_h, max_disp, disp_min, disp_max)
    fid = fopen(filepath, 'r');
    if fid == -1
        error('Cannot open file: %s', filepath);
    end

    raw = fscanf(fid, '%2X', Inf);
    fclose(fid);

    if length(raw) == 65535
        fid = fopen(filepath, 'r');
        raw = textscan(fid, '%2X', Inf);
        raw = raw{1};
        fclose(fid);
    end

    if length(raw) < 5
        error('File too short: only %d bytes (need >= 5 for header).', length(raw));
    end

    hdr_w  = bitshift(raw(1), 8) + raw(2);
    hdr_h  = bitshift(raw(3), 8) + raw(4);
    hdr_ty = raw(5);
    fprintf('  DAT header: %dx%d, type=%d\n', hdr_w, hdr_h, hdr_ty);

    if hdr_ty ~= 3
        error('Expected disparity type(3), got type=%d.', hdr_ty);
    end

    pixel_raw = double(raw(6:end));

    usable_rows = floor(length(pixel_raw) / img_w);
    if usable_rows < img_h
        warning('Only %d rows available (expected %d).', usable_rows, img_h);
        actual_rows = usable_rows;
    else
        actual_rows = img_h;
    end

    actual_bytes = actual_rows * img_w;
    disp_data_mat = reshape(pixel_raw(1:actual_bytes), img_w, actual_rows)';

    valid_mask = ~logical(bitget(uint8(disp_data_mat), 8));
    disp_data  = bitand(uint8(disp_data_mat), uint8(127));
    disp_data  = double(disp_data);

    disp_data = max(0, min(max_disp, disp_data));

    range_valid = (disp_data >= disp_min) & (disp_data <= disp_max);
    valid_mask  = valid_mask & range_valid;

    disp_data(~valid_mask) = 0;
end

function [out_disp, out_valid] = recursive_directional_fill(in_disp, in_valid, dirs)
    [H, W] = size(in_disp);
    out_disp  = in_disp;
    out_valid = in_valid;

    for d = 1:length(dirs)
        dir = dirs{d};
        filled = 0;

        switch dir
            case 'L->R'
                for y = 1:H
                    for x = 2:W
                        if ~out_valid(y, x) && out_valid(y, x-1)
                            out_disp(y, x)  = out_disp(y, x-1);
                            out_valid(y, x) = true;
                            filled = filled + 1;
                        end
                    end
                end

            case 'T->B'
                for y = 2:H
                    for x = 1:W
                        if ~out_valid(y, x) && out_valid(y-1, x)
                            out_disp(y, x)  = out_disp(y-1, x);
                            out_valid(y, x) = true;
                            filled = filled + 1;
                        end
                    end
                end

            case 'LT->RB'
                for s = 2:(H+W-1)
                    for y = max(1, s-W+1):min(H, s)
                        x = s - y + 1;
                        if x < 1 || x > W, continue; end
                        if ~out_valid(y, x) && y > 1 && x > 1 && out_valid(y-1, x-1)
                            out_disp(y, x)  = out_disp(y-1, x-1);
                            out_valid(y, x) = true;
                            filled = filled + 1;
                        end
                    end
                end

            case 'RT->LB'
                for s = 2:(H+W-1)
                    for y = max(1, s-W+1):min(H, s)
                        x = W - (s - y);
                        if x < 1 || x > W, continue; end
                        if ~out_valid(y, x) && y > 1 && x < W && out_valid(y-1, x+1)
                            out_disp(y, x)  = out_disp(y-1, x+1);
                            out_valid(y, x) = true;
                            filled = filled + 1;
                        end
                    end
                end
        end

        fprintf('    dir %s: filled %d holes\n', dir, filled);
    end
end

function [out_disp, out_valid] = valid_aware_median(in_disp, in_valid, win_size, min_valid)
    half = floor(win_size / 2);
    [H, W] = size(in_disp);

    out_disp = zeros(H, W);
    out_valid = false(H, W);

    pad_disp  = padarray(in_disp,  [half half], 'replicate', 'both');
    pad_valid = padarray(in_valid, [half half], false, 'both');

    for y = 1:H
        for x = 1:W
            crop_disp  = pad_disp(y:y+win_size-1, x:x+win_size-1);
            crop_valid = pad_valid(y:y+win_size-1, x:x+win_size-1);

            vals = crop_disp(crop_valid);
            cnt  = numel(vals);

            if cnt >= min_valid
                out_disp(y, x)  = round(median(vals));
                out_valid(y, x) = true;
            else
                out_disp(y, x)  = in_disp(y, x);
                out_valid(y, x) = false;
            end
        end
    end
end

function [out_disp, out_valid] = horizontal_box_fill(in_disp, in_valid, half_len, min_valid, fill_mode)
    [H, W] = size(in_disp);
    out_disp  = in_disp;
    out_valid = in_valid;

    for y = 1:H
        for x = 1:W
            if in_valid(y, x)
                continue;
            end

            xL = max(1, x - half_len);
            xR = min(W, x + half_len);

            win_valid = in_valid(y, xL:xR);
            win_disp  = in_disp(y, xL:xR);

            vals = win_disp(win_valid);
            cnt  = numel(vals);

            if cnt >= min_valid
                switch fill_mode
                    case 'max'
                        out_disp(y, x) = max(vals);
                        out_valid(y, x) = true;
                    case 'mean'
                        out_disp(y, x) = round(mean(vals));
                        out_valid(y, x) = true;
                    otherwise
                        out_disp(y, x) = round(mean(vals));
                        out_valid(y, x) = true;
                end
            end
        end
    end
end

function out_disp = gaussian_5x5(in_disp, in_valid, sigma)
    kernel = fspecial('gaussian', [5 5], sigma);

    [H, W] = size(in_disp);

    pad_disp  = padarray(in_disp,  [2 2], 'replicate', 'both');
    pad_valid = padarray(double(in_valid), [2 2], 0, 'both');

    out_disp = zeros(H, W);

    for y = 1:H
        for x = 1:W
            crop_disp  = pad_disp(y:y+4, x:x+4);
            crop_valid = pad_valid(y:y+4, x:x+4);

            weighted_sum = sum(sum(crop_disp .* kernel .* crop_valid));
            weight_total = sum(sum(kernel .* crop_valid));

            if weight_total > 0.5
                out_disp(y, x) = round(weighted_sum / weight_total);
            else
                out_disp(y, x) = in_disp(y, x);
            end
        end
    end
end
