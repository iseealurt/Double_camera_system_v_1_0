5%% verify_fpga_sgm.m
% 双目立体匹配 FPGA vs MATLAB 算法验证脚本
%
% 功能：
%   1. 读取 FPGA 输出视差图 (tb_sgm_new_task_5.dat)
%   2. 读取 Census 序列 (im0_gray.png.dat, im1_gray.png.dat)
%   3. 计算 SGM 8 路径聚合视差图
%   4. 计算 SGM 4 路径 (Lr0~Lr35) 聚合视差图
%   5. 三幅视差图对比，输出误差报告
%
% 参数与 FPGA (sgm_new_2.v) 严格一致

clc;
clear;
close all;

%% ==================== 1. FPGA 参数 (与 sgm_new_2.v 一致) ====================
IMG_WIDTH       = 640;
IMG_HEIGHT      = 480;
MAX_DISP        = 48;
CENSUS_BITS     = 24;
BYTES_PER_PIXEL = 3;
SGM_P1          = 3;
SGM_P2          = 24;
SGM_LR_WIDTH    = 12;
K_LR_MAX        = 2^SGM_LR_WIDTH - 1;
INVALID_COST    = CENSUS_BITS;
DISPARITY_WIDTH = 8;

%% ==================== 2. 输入文件路径 ====================
fpga_disparity_file = ['..\..\Bench\' ...
                       'tb_sgm_new_task_5.dat'];
left_census_file    = ['..\..\Bench\tb_sgm_new_task_3.dat'];
right_census_file   = ['..\..\Bench\tb_sgm_new_task_4.dat'];

out_dir = ['..\..\Matlab\' ...
           'test img\disparity\verify_fpga'];
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

%% ==================== 3. 读取 FPGA 视差图 ====================
fprintf('========== [Step 1/6] Reading FPGA disparity... ==========\n');

disp_fpga = read_disparity_hex(fpga_disparity_file, IMG_WIDTH, IMG_HEIGHT);
fprintf('  FPGA disparity: %dx%d, range [%.1f, %.1f]\n', ...
    size(disp_fpga,2), size(disp_fpga,1), ...
    min(disp_fpga(disp_fpga >= 0)), max(disp_fpga(disp_fpga >= 0)));

%% ==================== 4. 读取 Census 序列 ====================
fprintf('========== [Step 2/6] Reading census data... ==========\n');

[leftCensus,  lw, lh, lt] = read_census_hex(left_census_file);
[rightCensus, rw, rh, rt] = read_census_hex(right_census_file);

assert(lw == IMG_WIDTH && lh == IMG_HEIGHT, 'Left census size mismatch');
assert(rw == IMG_WIDTH && rh == IMG_HEIGHT, 'Right census size mismatch');
assert(lt == 2 && rt == 2, 'Census file type unexpected');

fprintf('  Left  census: %dx%d, type=%d\n', lw, lh, lt);
fprintf('  Right census: %dx%d, type=%d\n', rw, rh, rt);

%% ==================== 5. Hamming 代价体 ====================
fprintf('========== [Step 3/6] Computing Hamming cost volume... ==========\n');

costVol = compute_cost_volume(leftCensus, rightCensus, ...
    IMG_WIDTH, IMG_HEIGHT, MAX_DISP, INVALID_COST);
fprintf('  Cost volume: %dx%dx%d (uint8)\n', size(costVol,1), size(costVol,2), size(costVol,3));

%% ==================== 6. SGM 8 路径代价聚合 ====================
fprintf('========== [Step 4/6] SGM 8-path aggregation (P1=%d, P2=%d)... ==========\n', ...
    SGM_P1, SGM_P2);

costAgg8 = sgm_8path_aggregation(costVol, IMG_WIDTH, IMG_HEIGHT, MAX_DISP, ...
    SGM_P1, SGM_P2, K_LR_MAX);
[~, idx8] = min(costAgg8, [], 3);
disp_8path = uint8(idx8 - 1);
fprintf('  8-path disparity: range [%d, %d]\n', min(disp_8path(:)), max(disp_8path(:)));

%% ==================== 7. 选择对比路径 (单路径 / 4路径) ====================
fprintf('\n========== [Step 5/6] Select comparison path... ==========\n');
fprintf('  [1] Lr0  only  (L->R)\n');
fprintf('  [2] Lr1  only  (TL->BR)\n');
fprintf('  [3] Lr2  only  (T->B)\n');
fprintf('  [4] Lr3  only  (TR->BL)\n');
fprintf('  [5] ALL 4 paths (Lr0+Lr1+Lr2+Lr3)\n');
path_sel = input('  Enter choice [1-5]: ');

path_names = {'Lr0 (L->R)', 'Lr1 (TL->BR)', 'Lr2 (T->B)', 'Lr3 (TR->BL)', 'ALL 4 paths'};
path_types = [1, 5, 3, 6];
sel_name  = path_names{path_sel};

fprintf('\n========== Computing MATLAB: %s ... ==========\n', sel_name);

if path_sel <= 4
    % 单路径: 仅聚合一条路径, WTA 生成视差
    pid = path_types(path_sel);
    costAgg4 = sgm_path_aggregate(costVol, pid, IMG_WIDTH, IMG_HEIGHT, ...
        MAX_DISP, SGM_P1, SGM_P2, K_LR_MAX);
    [~, idx4] = min(costAgg4, [], 3);
    disp_4path = uint8(idx4 - 1);
    fprintf('  %s disparity: range [%d, %d]\n', sel_name, ...
        min(disp_4path(:)), max(disp_4path(:)));
else
    % 全 4 路径: 原逻辑
    costAgg4 = sgm_4path_aggregation(costVol, IMG_WIDTH, IMG_HEIGHT, MAX_DISP, ...
        SGM_P1, SGM_P2, K_LR_MAX);
    [~, idx4] = min(costAgg4, [], 3);
    disp_4path = uint8(idx4 - 1);
    fprintf('  4-path disparity: range [%d, %d]\n', ...
        min(disp_4path(:)), max(disp_4path(:)));
end

%% ==================== 8. 误差对比与报告 ====================
fprintf('========== [Step 6/6] Error comparison... ==========\n');

[err84, errF8, errF4, report, ...
 avgErr84_no, avgErr84_all, bad1_84_no, bad1_84_all, ...
 avgErrF8_no, avgErrF8_all, bad1_F8_no, bad1_F8_all, ...
 avgErrF4_no, avgErrF4_all, bad1_F4_no, bad1_F4_all] = ...
    compare_disparity_maps(disp_fpga, disp_8path, disp_4path, ...
                           IMG_WIDTH, IMG_HEIGHT, MAX_DISP, ...
                           SGM_P1, SGM_P2, sel_name, path_sel);

%% ==================== 8.5 Ground Truth 对比 ====================
fprintf('========== [Step 6.5/6] Comparing with Ground Truth... ==========\n');

gt_file = ['..\..\Matlab\' ...
           'test img\origin\venus\disp2.pgm'];
gt_raw = imread(gt_file);
if ndims(gt_raw) == 3
    gt_disp = double(rgb2gray(gt_raw));
else
    gt_disp = double(gt_raw);
end
[gtH, gtW] = size(gt_disp);
fprintf('  GT disparity: %dx%d, range [%d, %d]\n', ...
    gtW, gtH, min(gt_disp(:)), max(gt_disp(:)));

if gtW ~= IMG_WIDTH || gtH ~= IMG_HEIGHT
    scale_x = IMG_WIDTH / gtW;
    fprintf('  Resizing GT from %dx%d to %dx%d (nearest-neighbor), scaling disparity by %.3f...\n', ...
        gtW, gtH, IMG_WIDTH, IMG_HEIGHT, scale_x);
    gt_disp = imresize(gt_disp, [IMG_HEIGHT, IMG_WIDTH], 'nearest');
    gt_disp = gt_disp * scale_x;
end

% 对 GT 使用与 compare_disparity_maps 相同的 ROI 裁剪
BDR = 32;
switch path_sel
    case 1
        ym = 1; yM = IMG_HEIGHT; xm = BDR+1; xM = IMG_WIDTH;
    case 2
        ym = BDR+1; yM = IMG_HEIGHT; xm = 1; xM = IMG_WIDTH - BDR;
    case 3
        ym = BDR+1; yM = IMG_HEIGHT; xm = 1; xM = IMG_WIDTH;
    case 4
        ym = BDR+1; yM = IMG_HEIGHT; xm = BDR+1; xM = IMG_WIDTH;
    otherwise
        ym = 1; yM = IMG_HEIGHT; xm = 1; xM = IMG_WIDTH;
end

df_roi = double(disp_fpga(ym:yM, xm:xM));
d8_roi = double(disp_8path(ym:yM, xm:xM));
d4_roi = double(disp_4path(ym:yM, xm:xM));
gt_roi = gt_disp(ym:yM, xm:xM);

df_roi = df_roi(:); d8_roi = d8_roi(:); d4_roi = d4_roi(:); gt_roi = gt_roi(:);

% FPGA vs GT
absFG  = abs(df_roi - gt_roi);
noFG   = (gt_roi > 0);
noFG_n = sum(noFG);
allFG_n = numel(absFG);
avgErrFG_no  = mean(absFG(noFG));
avgErrFG_all = mean(absFG);
bad1_FG_no   = sum(absFG(noFG) > 1.0) / noFG_n * 100;
bad1_FG_all  = sum(absFG > 1.0) / allFG_n * 100;
n_bad1_FG_no  = sum(absFG(noFG) > 1.0);
n_bad1_FG_all = sum(absFG > 1.0);

% 8-path vs GT
abs8G  = abs(d8_roi - gt_roi);
no8G   = (gt_roi > 0);
no8G_n = sum(no8G);
all8G_n = numel(abs8G);
avgErr8G_no  = mean(abs8G(no8G));
avgErr8G_all = mean(abs8G);
bad1_8G_no   = sum(abs8G(no8G) > 1.0) / no8G_n * 100;
bad1_8G_all  = sum(abs8G > 1.0) / all8G_n * 100;
n_bad1_8G_no  = sum(abs8G(no8G) > 1.0);
n_bad1_8G_all = sum(abs8G > 1.0);

% Selected vs GT
absSG  = abs(d4_roi - gt_roi);
noSG   = (gt_roi > 0);
noSG_n = sum(noSG);
allSG_n = numel(absSG);
avgErrSG_no  = mean(absSG(noSG));
avgErrSG_all = mean(absSG);
bad1_SG_no   = sum(absSG(noSG) > 1.0) / noSG_n * 100;
bad1_SG_all  = sum(absSG > 1.0) / allSG_n * 100;
n_bad1_SG_no  = sum(absSG(noSG) > 1.0);
n_bad1_SG_all = sum(absSG > 1.0);

gt_report = sprintf([ ...
    'Comparison:  FPGA vs Ground Truth\n', ...
    '  nonocc - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n', ...
    '  all    - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n\n', ...
    'Comparison:  8-path vs Ground Truth\n', ...
    '  nonocc - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n', ...
    '  all    - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n\n', ...
    'Comparison:  %s vs Ground Truth\n', ...
    '  nonocc - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n', ...
    '  all    - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n\n', ...
    '===============================================================\n'], ...
    avgErrFG_no, bad1_FG_no, n_bad1_FG_no, noFG_n, ...
    avgErrFG_all, bad1_FG_all, n_bad1_FG_all, allFG_n, ...
    avgErr8G_no, bad1_8G_no, n_bad1_8G_no, no8G_n, ...
    avgErr8G_all, bad1_8G_all, n_bad1_8G_all, all8G_n, ...
    sel_name, ...
    avgErrSG_no, bad1_SG_no, n_bad1_SG_no, noSG_n, ...
    avgErrSG_all, bad1_SG_all, n_bad1_SG_all, allSG_n);

report = [report, gt_report];

fprintf('%s\n', gt_report);

%% ==================== 9. 可视化与输出 ====================
fprintf('\n%s\n', report);

vis_fpga   = uint8(double(disp_fpga)  * 255 / (MAX_DISP - 1));
vis_8path  = uint8(double(disp_8path) * 255 / (MAX_DISP - 1));
vis_sel    = uint8(double(disp_4path) * 255 / (MAX_DISP - 1));
vis_gt     = uint8(double(gt_disp) * 255 / (max(gt_disp(:)) + eps));
err_fpga_vs_8 = uint8(abs(double(disp_fpga) - double(disp_8path)) * 255 / MAX_DISP);
err_fpga_vs_S = uint8(abs(double(disp_fpga) - double(disp_4path)) * 255 / MAX_DISP);
err_fpga_vs_G = uint8(abs(double(disp_fpga) - gt_disp) * 255 / MAX_DISP);
err_sel_vs_G  = uint8(abs(double(disp_4path) - gt_disp) * 255 / MAX_DISP);

figure('Name', 'FPGA SGM Verification', 'Color', 'w', 'Position', [100 100 1600 1100]);

subplot(3,4,1);  imshow(vis_fpga);    title('FPGA Output (sgm\_new\_2)');
subplot(3,4,2);  imshow(vis_8path);   title('SGM 8-path (MATLAB)');
subplot(3,4,3);  imshow(vis_sel);     title(sprintf('SGM %s (MATLAB)', sel_name));
subplot(3,4,4);  imshow(vis_gt);      title('Ground Truth');

subplot(3,4,5);  imshow(err_fpga_vs_8); title(sprintf('|FPGA - 8path| nonocc: %.2f%%', errF8));
subplot(3,4,6);  imshow(err_fpga_vs_S); title(sprintf('|FPGA - %s| nonocc: %.2f%%', sel_name, errF4));
subplot(3,4,7);  imshow(err_fpga_vs_G); title(sprintf('|FPGA - GT| nonocc: %.2f%%', bad1_FG_no));
subplot(3,4,8);  imshow(err_sel_vs_G);  title(sprintf('|%s - GT| nonocc: %.2f%%', sel_name, bad1_SG_no));

subplot(3,4,9);
histogram(abs(double(disp_fpga(:)) - double(disp_8path(:))), 0:1:MAX_DISP-1, ...
    'FaceColor', [0.2 0.6 0.8]);
xlabel('disparity error [pixel]'); ylabel('pixel count');
title('FPGA vs 8-path error');

subplot(3,4,10);
histogram(abs(double(disp_fpga(:)) - double(disp_4path(:))), 0:1:MAX_DISP-1, ...
    'FaceColor', [0.8 0.4 0.2]);
xlabel('disparity error [pixel]'); ylabel('pixel count');
title(sprintf('FPGA vs %s error', sel_name));

subplot(3,4,11);
histogram(absFG, 0:1:MAX_DISP-1, 'FaceColor', [0.2 0.8 0.2]);
xlabel('disparity error [pixel]'); ylabel('pixel count');
title('FPGA vs GT error');

subplot(3,4,12);
text(0.05, 0.95, report, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', 'FontSize', 8, 'BackgroundColor', [0.95 0.95 0.95]);
title('Error Report');
axis off;

saveas(gcf, fullfile(out_dir, 'verification_report.png'));
fprintf('  Report figure saved.\n');

imwrite(vis_fpga,      fullfile(out_dir, '01_fpga_disparity.png'));
imwrite(vis_8path,     fullfile(out_dir, '02_matlab_8path.png'));
imwrite(vis_sel,       fullfile(out_dir, '03_matlab_selected.png'));
imwrite(vis_gt,        fullfile(out_dir, '04_ground_truth.png'));
imwrite(err_fpga_vs_8, fullfile(out_dir, '05_error_fpga_vs_8path.png'));
imwrite(err_fpga_vs_S, fullfile(out_dir, '06_error_fpga_vs_selected.png'));
imwrite(err_fpga_vs_G, fullfile(out_dir, '07_error_fpga_vs_gt.png'));
imwrite(err_sel_vs_G,  fullfile(out_dir, '08_error_selected_vs_gt.png'));

save(fullfile(out_dir, 'verification_data.mat'), ...
    'disp_fpga', 'disp_8path', 'disp_4path', 'gt_disp', ...
    'costVol', 'costAgg8', 'costAgg4', ...
    'IMG_WIDTH', 'IMG_HEIGHT', 'MAX_DISP', ...
    'SGM_P1', 'SGM_P2', 'sel_name', ...
    'errF8', 'errF4', 'err84', ...
    'avgErr84_no', 'avgErr84_all', 'bad1_84_no', 'bad1_84_all', ...
    'avgErrF8_no', 'avgErrF8_all', 'bad1_F8_no', 'bad1_F8_all', ...
    'avgErrF4_no', 'avgErrF4_all', 'bad1_F4_no', 'bad1_F4_all', ...
    'avgErrFG_no', 'avgErrFG_all', 'bad1_FG_no', 'bad1_FG_all', ...
    'avgErr8G_no', 'avgErr8G_all', 'bad1_8G_no', 'bad1_8G_all', ...
    'avgErrSG_no', 'avgErrSG_all', 'bad1_SG_no', 'bad1_SG_all', '-v7.3');

fprintf('  All results saved to: %s\n', out_dir);
fprintf('========== Verification done! ==========\n');

%% ========================================================================
%%                           Local Functions
%% ========================================================================

function disp_img = read_disparity_hex(filename, W, H)
    % 读取 ASCII 十六进制 disparity dat 文件 (亚像素格式)
    % 格式: 5-byte header (W_MSB, W_LSB, H_MSB, H_LSB, TYPE=0x03)
    %        + 1 byte/pixel, 行优先
    % 字节编码 (sgm_new_2.v 亚像素插值):
    %   byte[7]    = valid (0=有效, 1=低置信度/空洞)
    %   byte[6:0]  = integer_disp * 2 + subpixel_offset  (-1/0/+1)
    %   实际视差 = byte[6:0] / 2.0  (0.5 像素亚像素精度)
    txt = fileread(filename);
    raw = sscanf(txt, '%x');
    assert(numel(raw) >= 5, 'Disparity file too short');
    bytes = uint8(raw(:));
    w = double(bytes(1)) * 256 + double(bytes(2));
    h = double(bytes(3)) * 256 + double(bytes(4));
    dtype = double(bytes(5));
    fprintf('  Disparity header: %dx%d, type=%d\n', w, h, dtype);
    assert(w == W && h == H, 'Disparity image size mismatch');
    payload = bytes(6:end);
    expected = W * H;
    if numel(payload) < expected
        warning('Disparity payload short: got %d, expected %d', numel(payload), expected);
        payload(end+1:expected) = 0;
    end
    payload = payload(1:expected);
    payload_mat = reshape(payload, W, H).';

    % 亚像素解码: byte[7]=valid, byte[6:0]=integer_disp*2+subpixel_offset
    valid_mask = ~bitget(payload_mat, 8);
    raw_7bit = double(bitand(uint8(payload_mat), uint8(127)));
    disp_img = raw_7bit / 2.0;
    disp_img(~valid_mask) = -1;

    valid_pixels = disp_img(disp_img >= 0);
    if isempty(valid_pixels)
        fprintf('  Decoded subpixel disparity: NO valid pixels\n');
    else
        fprintf('  Decoded subpixel disparity: range [%.1f, %.1f], %.1f%% valid\n', ...
            min(valid_pixels(:)), max(valid_pixels(:)), ...
            sum(valid_mask(:)) / numel(disp_img) * 100);
    end
end

function [census_img, width, height, data_type] = read_census_hex(filename)
    % 读取 ASCII 十六进制 census dat 文件
    % 格式: 5-byte header + 3 bytes/pixel (24-bit census), 行优先
    txt = fileread(filename);
    raw = sscanf(txt, '%x');
    assert(numel(raw) >= 5, 'Census file too short');
    bytes = uint32(raw(:));
    assert(all(bytes <= 255), 'Census file byte value > FF');
    width     = double(bytes(1) * 256 + bytes(2));
    height    = double(bytes(3) * 256 + bytes(4));
    data_type = double(bytes(5));
    payload = bytes(6:end);
    expected = width * height * 3;
    if numel(payload) < expected
        error('Payload short: got %d, expected %d', numel(payload), expected);
    elseif numel(payload) > expected
        payload = payload(1:expected);
    end
    payload3 = reshape(payload, 3, []).';
    census_vec = bitshift(payload3(:,1), 16) + ...
                 bitshift(payload3(:,2),  8) + ...
                 payload3(:,3);
    census_img = reshape(census_vec, width, height).';
    census_img = uint32(census_img);
end

function costVol = compute_cost_volume(leftCensus, rightCensus, ...
    W, H, MAX_DISP, INVALID_COST)
    % 计算左视差 Hamming 代价体
    % leftCensus   : H x W, uint32, 参考左图
    % rightCensus  : H x W, uint32, 匹配右图
    % costVol      : H x W x MAX_DISP, uint8
    popLUT = uint8(sum(dec2bin(0:255) == '1', 2));
    costVol = uint8(ones(H, W, MAX_DISP) * INVALID_COST);
    for d = 0:MAX_DISP-1
        if d == 0
            xl = 1:W;
            xr = 1:W;
        else
            xl = (d+1):W;
            xr = 1:(W-d);
        end
        if ~isempty(xl)
            xorVal = bitxor(leftCensus(:, xl), rightCensus(:, xr));
            b0 = bitand(xorVal, uint32(255));
            b1 = bitand(bitshift(xorVal, -8), uint32(255));
            b2 = bitand(bitshift(xorVal, -16), uint32(255));
            ham = popLUT(double(b0)+1) + popLUT(double(b1)+1) + popLUT(double(b2)+1);
            costVol(:, xl, d+1) = ham;
        end
    end
end

%% ========================================================================
%%                   SGM 单路径递推 (矢量化为逐路径聚合)
%% ========================================================================
function L = sgm_path_aggregate(costVol, path_type, W, H, MAX_DISP, P1, P2, K_MAX)
    % 沿指定方向进行 SGM 递推代价聚合
    %
    % path_type: 1=L->R  2=R->L  3=T->B  4=B->T
    %            5=TL->BR  6=TR->BL  7=BL->TR  8=BR->TL
    L = zeros(H, W, MAX_DISP, 'uint16');

    switch path_type
        case 1  % L->R
            for y = 1:H
                L_prev = uint16(K_MAX * ones(1, MAX_DISP));
                for x = 1:W
                    L(y, x, :) = sgm_cell_step(costVol(y, x, :), L_prev, ...
                        (x > 1), P1, P2, K_MAX);
                    L_prev = uint16(squeeze(L(y, x, :))');
                end
            end

        case 2  % R->L
            for y = 1:H
                L_prev = uint16(K_MAX * ones(1, MAX_DISP));
                for x = W:-1:1
                    L(y, x, :) = sgm_cell_step(costVol(y, x, :), L_prev, ...
                        (x < W), P1, P2, K_MAX);
                    L_prev = uint16(squeeze(L(y, x, :))');
                end
            end

        case 3  % T->B
            for x = 1:W
                L_prev = uint16(K_MAX * ones(1, MAX_DISP));
                for y = 1:H
                    L(y, x, :) = sgm_cell_step(costVol(y, x, :), L_prev, ...
                        (y > 1), P1, P2, K_MAX);
                    L_prev = uint16(squeeze(L(y, x, :))');
                end
            end

        case 4  % B->T
            for x = 1:W
                L_prev = uint16(K_MAX * ones(1, MAX_DISP));
                for y = H:-1:1
                    L(y, x, :) = sgm_cell_step(costVol(y, x, :), L_prev, ...
                        (y < H), P1, P2, K_MAX);
                    L_prev = uint16(squeeze(L(y, x, :))');
                end
            end

        case 5  % TL->BR (沿 y-x = const 线扫描)
            for diag_offset = -(H-1):(W-1)
                [ys, xs] = tl_br_line(diag_offset, W, H);
                if isempty(ys), continue; end
                L_prev = uint16(K_MAX * ones(1, MAX_DISP));
                first = true;
                for k = 1:numel(ys)
                    y = ys(k); x = xs(k);
                    L(y, x, :) = sgm_cell_step(costVol(y, x, :), L_prev, ...
                        ~first, P1, P2, K_MAX);
                    L_prev = uint16(squeeze(L(y, x, :))');
                    first = false;
                end
            end

        case 6  % TR->BL (沿 y+x = const 线扫描)
            for sum_xy = 2:(H+W)
                [ys, xs] = tr_bl_line(sum_xy, W, H);
                if isempty(ys), continue; end
                L_prev = uint16(K_MAX * ones(1, MAX_DISP));
                first = true;
                for k = 1:numel(ys)
                    y = ys(k); x = xs(k);
                    L(y, x, :) = sgm_cell_step(costVol(y, x, :), L_prev, ...
                        ~first, P1, P2, K_MAX);
                    L_prev = uint16(squeeze(L(y, x, :))');
                    first = false;
                end
            end

        case 7  % BL->TR (沿 y+x = const, 从 BL 往 TR)
            for sum_xy = 2:(H+W)
                [ys, xs] = bl_tr_line(sum_xy, W, H);
                if isempty(ys), continue; end
                L_prev = uint16(K_MAX * ones(1, MAX_DISP));
                first = true;
                for k = 1:numel(ys)
                    y = ys(k); x = xs(k);
                    L(y, x, :) = sgm_cell_step(costVol(y, x, :), L_prev, ...
                        ~first, P1, P2, K_MAX);
                    L_prev = uint16(squeeze(L(y, x, :))');
                    first = false;
                end
            end

        case 8  % BR->TL (沿 y-x = const, 从 BR 往 TL)
            for diag_offset = -(H-1):(W-1)
                [ys, xs] = br_tl_line(diag_offset, W, H);
                if isempty(ys), continue; end
                L_prev = uint16(K_MAX * ones(1, MAX_DISP));
                first = true;
                for k = 1:numel(ys)
                    y = ys(k); x = xs(k);
                    L(y, x, :) = sgm_cell_step(costVol(y, x, :), L_prev, ...
                        ~first, P1, P2, K_MAX);
                    L_prev = uint16(squeeze(L(y, x, :))');
                    first = false;
                end
            end
    end
end

%% ========================================================================
%%               SGM 单步递推 (单个像素) — 与 FPGA 公式完全对齐
%% ========================================================================
function L_curr = sgm_cell_step(cost_d, L_prev, has_prev, P1, P2, K_MAX)
    % cost_d  : 1 x MAX_DISP, uint8
    % L_prev  : 1 x MAX_DISP, uint16
    % has_prev: 是否有前一像素（行首 = false）
    % L_curr  : 1 x MAX_DISP, uint16
    MAX_DISP = numel(L_prev);
    L_curr = zeros(1, MAX_DISP, 'uint16');

    if ~has_prev
        L_curr = uint16(cost_d);
        return;
    end

    L_min = min(L_prev);
    for d_idx = 1:MAX_DISP
        d = d_idx - 1;

        % R0 = L_prev[d] - L_min
        r0 = sat_sub_uint16(L_prev(d_idx), L_min);

        % R1 = L_prev[d-1] + P1 - L_min  (d=0 时 = K_MAX)
        if d == 0
            r1 = K_MAX;
        else
            r1 = sat_sub_uint16(uint16(min(double(L_prev(d_idx-1)) + double(P1), ...
                double(K_MAX))), L_min);
        end

        % R2 = L_prev[d+1] + P1 - L_min  (d=MAX_DISP-1 时 = K_MAX)
        if d == MAX_DISP - 1
            r2 = K_MAX;
        else
            r2 = sat_sub_uint16(uint16(min(double(L_prev(d_idx+1)) + double(P1), ...
                double(K_MAX))), L_min);
        end

        % R3 = P2
        r3 = uint16(P2);

        rmin = min([r0, r1, r2, r3]);
        L_curr(d_idx) = uint16(min(double(cost_d(d_idx)) + double(rmin), double(K_MAX)));
    end
end

function v = sat_sub_uint16(a, b)
    % 饱和减法: a - b, 下界 0
    if a >= b
        v = uint16(a - b);
    else
        v = uint16(0);
    end
end

%% ========================================================================
%%              8 路径 / 4 路径 聚合封装
%% ========================================================================
function costAgg = sgm_8path_aggregation(costVol, W, H, MAX_DISP, P1, P2, K_MAX)
    costAgg = zeros(H, W, MAX_DISP, 'uint32');
    paths = [1, 2, 3, 4, 5, 6, 7, 8];
    path_names = {'L->R','R->L','T->B','B->T','TL->BR','TR->BL','BL->TR','BR->TL'};
    for pi = 1:8
        fprintf('  Path %d/8: %s ...\n', pi, path_names{pi});
        L = sgm_path_aggregate(costVol, paths(pi), W, H, MAX_DISP, P1, P2, K_MAX);
        costAgg = costAgg + uint32(L);
    end
end

function costAgg = sgm_4path_aggregation(costVol, W, H, MAX_DISP, P1, P2, K_MAX)
    costAgg = zeros(H, W, MAX_DISP, 'uint32');
    paths = [1, 5, 3, 6];
    path_names = {'Lr0 L->R','Lr1 TL->BR','Lr2 T->B','Lr3 TR->BL'};
    for pi = 1:4
        fprintf('  Path %d/4: %s ...\n', pi, path_names{pi});
        L = sgm_path_aggregate(costVol, paths(pi), W, H, MAX_DISP, P1, P2, K_MAX);
        costAgg = costAgg + uint32(L);
    end
end

%% ========================================================================
%%                   对角线扫描线生成 (TL->BR, TR->BL 等)
%% ========================================================================
function [ys, xs] = tl_br_line(diag_offset, W, H)
    % TL->BR: 沿 y - x = diag_offset 的像素，按 y 从小到大
    ys = []; xs = [];
    for y = 1:H
        x = y - diag_offset;
        if x >= 1 && x <= W
            ys(end+1) = y;
            xs(end+1) = x;
        end
    end
end

function [ys, xs] = br_tl_line(diag_offset, W, H)
    % BR->TL: 沿 y - x = diag_offset 的像素，按 y 从大到小
    [ys, xs] = tl_br_line(diag_offset, W, H);
    ys = fliplr(ys);
    xs = fliplr(xs);
end

function [ys, xs] = tr_bl_line(sum_xy, W, H)
    % TR->BL: 沿 y + x = sum_xy 的像素，按 y 从小到大
    ys = []; xs = [];
    for y = 1:H
        x = sum_xy - y;
        if x >= 1 && x <= W
            ys(end+1) = y;
            xs(end+1) = x;
        end
    end
end

function [ys, xs] = bl_tr_line(sum_xy, W, H)
    % BL->TR: 沿 y + x = sum_xy 的像素，按 y 从大到小
    [ys, xs] = tr_bl_line(sum_xy, W, H);
    ys = fliplr(ys);
    xs = fliplr(xs);
end

%% ========================================================================
%%                   三图误差对比与报告 (Middlebury 标准: nonocc / all)
%% ========================================================================
function [err84, errF8, errF4, report, ...
    avgErr84_no, avgErr84_all, bad1_84_no, bad1_84_all, ...
    avgErrF8_no, avgErrF8_all, bad1_F8_no, bad1_F8_all, ...
    avgErrF4_no, avgErrF4_all, bad1_F4_no, bad1_F4_all] = ...
    compare_disparity_maps(disp_fpga, disp_8path, disp_4path, ...
                           W, H, MAX_DISP, P1, P2, sel_name, path_sel)
    % 按 Middlebury 标准计算绝对视差误差指标
    %   nonocc : 参考视差有效 (>0) 的非遮挡区域
    %   all    : ROI 内全部像素
    %   指标   : AvgErr = mean(|d_est - d_ref|) [pixel]
    %           Bad 1.0 = % of pixels with |d_est - d_ref| > 1.0 px
    BDR = 32;

    switch path_sel
        case 1   % Lr0 L->R: 左边不可靠
            ym = 1; yM = H;  xm = BDR+1; xM = W;
        case 2   % Lr1 TL->BR: 上边+右边+右上角不可靠
            ym = BDR+1; yM = H;  xm = 1; xM = W - BDR;
        case 3   % Lr2 T->B: 上边不可靠
            ym = BDR+1; yM = H;  xm = 1; xM = W;
        case 4   % Lr3 TR->BL: 上边+左边不可靠
            ym = BDR+1; yM = H;  xm = BDR+1; xM = W;
        otherwise  % 4-path / 8-path: 全图
            ym = 1; yM = H;  xm = 1; xM = W;
    end

    d8  = double(disp_8path(ym:yM, xm:xM));
    d4  = double(disp_4path(ym:yM, xm:xM));
    df  = double(disp_fpga(ym:yM, xm:xM));

    d8 = d8(:); d4 = d4(:); df = df(:);

    excluded = W * H - numel(d4);

    % === 8-path vs selected: 绝对视差误差 ===
    abs84    = abs(d8 - d4);
    no84     = (d4 > 0);
    n_no84   = sum(no84);
    n_all84  = numel(abs84);
    avgErr84_no  = mean(abs84(no84));
    avgErr84_all = mean(abs84);
    bad1_84_no   = sum(abs84(no84) > 1.0) / n_no84 * 100;
    bad1_84_all  = sum(abs84 > 1.0) / n_all84 * 100;
    n_bad1_84_no = sum(abs84(no84) > 1.0);
    n_bad1_84_all = sum(abs84 > 1.0);
    err84 = bad1_84_no;

    % === FPGA vs 8-path (MATLAB reference): 绝对视差误差 ===
    absF8    = abs(df - d8);
    noF8     = (d8 > 0);
    n_noF8   = sum(noF8);
    n_allF8  = numel(absF8);
    avgErrF8_no  = mean(absF8(noF8));
    avgErrF8_all = mean(absF8);
    bad1_F8_no   = sum(absF8(noF8) > 1.0) / n_noF8 * 100;
    bad1_F8_all  = sum(absF8 > 1.0) / n_allF8 * 100;
    n_bad1_F8_no = sum(absF8(noF8) > 1.0);
    n_bad1_F8_all = sum(absF8 > 1.0);
    errF8 = bad1_F8_no;

    % === FPGA vs selected: 绝对视差误差 ===
    absF4    = abs(df - d4);
    noF4     = (d4 > 0);
    n_noF4   = sum(noF4);
    n_allF4  = numel(absF4);
    avgErrF4_no  = mean(absF4(noF4));
    avgErrF4_all = mean(absF4);
    bad1_F4_no   = sum(absF4(noF4) > 1.0) / n_noF4 * 100;
    bad1_F4_all  = sum(absF4 > 1.0) / n_allF4 * 100;
    n_bad1_F4_no = sum(absF4(noF4) > 1.0);
    n_bad1_F4_all = sum(absF4 > 1.0);
    errF4 = bad1_F4_no;

    report = sprintf([ ...
        '================ SGM FPGA VERIFICATION REPORT ================\n', ...
        'Parameters:  %dx%d, dmax=%d, P1=%d, P2=%d\n', ...
        'Error type:  absolute disparity error [pixel] (Middlebury)\n', ...
        'MATLAB path: %s\n', ...
        'Excluded pixels (border crop): %d\n\n', ...
        'Comparison:  8-path vs selected (%s)\n', ...
        '  nonocc - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n', ...
        '  all    - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n\n', ...
        'Comparison:  FPGA vs 8-path (MATLAB reference)\n', ...
        '  nonocc - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n', ...
        '  all    - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n\n', ...
        'Comparison:  FPGA vs selected (%s)\n', ...
        '  nonocc - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n', ...
        '  all    - AvgErr: %.4f px    Bad 1.0: %.2f%% (%d/%d)\n\n', ...
        '===============================================================\n', ...
        'NOTE: FPGA sgm_new_2 implements 4-direction: \n', ...
        '      Lr0(L->R), Lr1(TL->BR via BRAM), Lr2(T->B via BRAM), Lr3(TR->BL via BRAM).\n', ...
        '      P1=%d, P2=%d match tb_sgm_new.v.\n', ...
        '      Differences may come from pipeline alignment / mask logic.\n', ...
        '===============================================================\n'], ...
        W, H, MAX_DISP, P1, P2, sel_name, excluded, ...
        sel_name, ...
        avgErr84_no, bad1_84_no, n_bad1_84_no, n_no84, ...
        avgErr84_all, bad1_84_all, n_bad1_84_all, n_all84, ...
        avgErrF8_no, bad1_F8_no, n_bad1_F8_no, n_noF8, ...
        avgErrF8_all, bad1_F8_all, n_bad1_F8_all, n_allF8, ...
        sel_name, ...
        avgErrF4_no, bad1_F4_no, n_bad1_F4_no, n_noF4, ...
        avgErrF4_all, bad1_F4_all, n_bad1_F4_all, n_allF4, ...
        P1, P2);
end
