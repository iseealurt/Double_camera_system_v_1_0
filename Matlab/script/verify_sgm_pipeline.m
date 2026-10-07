%% SGM Pipeline 逐级比对脚本
% 功能：加载 MATLAB 参考文件和 RTL 仿真输出文件，逐级逐像素比对
%    Stage 4:  costVol (MATLAB) vs hamming_dist (RTL)
%    Stage 10: Lr_LR   (MATLAB) vs Lr0_curr  (RTL)
%    Stage 11: Lr_LR   (MATLAB) vs combined_lr (RTL, 当前单路径)
% 用法：
%   1. 先运行 sgm_dual_path_enhanced.m 生成 sgm_mat_task_6/7/8.dat
%   2. 再运行 ModelSim 仿真得到 tb_sgm_new_task_6/7/8.dat
%   3. 运行本脚本，分别选择 MATLAB 和 RTL 文件夹

clc;
clear;
close all;

%% ===================== 参数 =====================
IMG_WIDTH       = 640;
IMG_HEIGHT      = 480;
MAX_DISP        = 48;
BYTES_PER_PIXEL_HAMMING = 48;   % 48 × uint8
BYTES_PER_PIXEL_LR      = 96;   % 48 × uint16 LE (96 bytes)
HEADER_SIZE     = 5;            % 5字节文件头

%% ===================== 选择文件夹 =====================
matFolder = uigetdir('', '请选择 MATLAB 输出文件夹（含 sgm_mat_task_6/7/8.dat）');
if isequal(matFolder, 0)
    disp('未选择 MATLAB 文件夹，程序结束。');
    return;
end

rtlFolder = uigetdir('', '请选择 RTL 输出文件夹（含 tb_sgm_new_task_6/7/8.dat）');
if isequal(rtlFolder, 0)
    disp('未选择 RTL 文件夹，程序结束。');
    return;
end

outFolder = uigetdir('', '请选择比对报告输出文件夹');
if isequal(outFolder, 0)
    disp('未选择输出文件夹，程序结束。');
    return;
end

%% ===================== Stage 4: 汉明距离比对 =====================
fprintf('\n========================================\n');
fprintf('Stage 4: 汉明距离比对 (costVol vs hamming_dist)\n');
fprintf('========================================\n');

% ----- 加载 MATLAB 参考 -----
fid = fopen(fullfile(matFolder, 'sgm_mat_task_6.dat'), 'rb');
if fid == -1
    error('找不到 MATLAB 文件: sgm_mat_task_6.dat');
end
[matW, matH, matDT] = parse_5byte_header(fid);
fprintf('MATLAB: %dx%d, TYPE=0x%02X\n', matW, matH, matDT);
matHam = fread(fid, [MAX_DISP, IMG_WIDTH * IMG_HEIGHT], 'uint8=>uint8');
fclose(fid);
matHam = reshape(matHam', IMG_HEIGHT, IMG_WIDTH, MAX_DISP);

% ----- 加载 RTL 输出 -----
fid = fopen(fullfile(rtlFolder, 'tb_sgm_new_task_6.dat'), 'rb');
if fid == -1
    error('找不到 RTL 文件: tb_sgm_new_task_6.dat');
end
[rtlW, rtlH, rtlDT] = parse_5byte_header(fid);
fprintf('RTL:    %dx%d, TYPE=0x%02X\n', rtlW, rtlH, rtlDT);
rtlHam = fread(fid, [MAX_DISP, IMG_WIDTH * IMG_HEIGHT], 'uint8=>uint8');
fclose(fid);
rtlHam = reshape(rtlHam', IMG_HEIGHT, IMG_WIDTH, MAX_DISP);

% ===== 诊断：二维扫描 x×d 偏移检测 (FIFO 时序相位) =====
fprintf('\n  ----- (x,d) 联合偏移扫描 -----\n');
bestShiftX = 0;
bestShiftD = 0;
bestMatch = 0;
bestFlip = 0;
fprintf('  扫描中... (x ±60, d ±10) ');
for flipD = 0:1
    for shiftX = -60:60
        for shiftD = -10:10
            % 应用 d 反向
            if flipD == 1
                m = matHam(:, :, end:-1:1);
            else
                m = matHam;
            end
            % 应用 x/d 偏移
            xR = max(1, 1-shiftX):min(640, 640-shiftX);
            xM = xR + shiftX;
            dR = max(1, 1-shiftD):min(48, 48-shiftD);
            dM = dR + shiftD;
            
            mRegion = m(:, xM, dM);
            rRegion = rtlHam(:, xR, dR);
            matchRate = sum(mRegion == rRegion, 'all') / numel(mRegion) * 100;
            
            if matchRate > bestMatch
                bestMatch = matchRate;
                bestShiftX = shiftX;
                bestShiftD = shiftD;
                bestFlip = flipD;
            end
        end
    end
end
fprintf('完成\n');
fprintf('  最佳对齐: x_shift=%d, d_shift=%d, d_flip=%d, 匹配率 = %.2f%%\n', ...
    bestShiftX, bestShiftD, bestFlip, bestMatch);
if bestMatch > 80
    fprintf('  ✅ 找到 (x,d) 联合偏移！\n');
else
    fprintf('  ⚠  偏移/反向仍无法对齐，根因在像素对本身\n');
    fprintf('  建议：直接在最大误差点 y=112, x=2, d=1 打印两边的 Census 值\n');
end
fprintf('  --------------------\n\n');

% ----- 逐像素比对 -----
diffHam = abs(int16(matHam) - int16(rtlHam));
maxDiffHam = max(diffHam, [], 'all');
meanDiffHam = mean(diffHam, 'all');
mismatchPixelsHam = sum(diffHam > 0, 'all');
totalPixels = IMG_HEIGHT * IMG_WIDTH * MAX_DISP;

fprintf('  最大差异: %d\n', maxDiffHam);
fprintf('  平均差异: %.4f\n', meanDiffHam);
fprintf('  像素失配率: %.2f%% (%d / %d)\n', ...
    mismatchPixelsHam / totalPixels * 100, mismatchPixelsHam, totalPixels);

if maxDiffHam == 0
    fprintf('  ✅ Stage 4: MATLAB costVol == RTL hamming_dist (完全一致!)\n');
else
    fprintf('  ❌ Stage 4: 存在差异！\n');
    % 找出差异最大的位置
    [maxErrY, maxErrX, maxErrD] = ind2sub(size(diffHam), find(diffHam == maxDiffHam, 1));
    fprintf('     最大误差位置: y=%d, x=%d, d=%d (MATLAB=%d, RTL=%d)\n', ...
        maxErrY, maxErrX, maxErrD, matHam(maxErrY, maxErrX, maxErrD), rtlHam(maxErrY, maxErrX, maxErrD));
end

%% ===================== Stage 10: Lr0 聚合比对 =====================
fprintf('\n========================================\n');
fprintf('Stage 10: Lr0聚合比对 (Lr_LR vs Lr0_curr)\n');
fprintf('========================================\n');

% ----- 加载 MATLAB 参考 -----
fid = fopen(fullfile(matFolder, 'sgm_mat_task_7.dat'), 'rb');
if fid == -1
    error('找不到 MATLAB 文件: sgm_mat_task_7.dat');
end
[matW, matH, matDT] = parse_5byte_header(fid);
fprintf('MATLAB: %dx%d, TYPE=0x%02X\n', matW, matH, matDT);
matLr0 = fread(fid, [MAX_DISP, IMG_WIDTH * IMG_HEIGHT], 'uint16=>uint16');
fclose(fid);
matLr0 = reshape(matLr0', IMG_HEIGHT, IMG_WIDTH, MAX_DISP);

% ----- 加载 RTL 输出 -----
fid = fopen(fullfile(rtlFolder, 'tb_sgm_new_task_7.dat'), 'rb');
if fid == -1
    error('找不到 RTL 文件: tb_sgm_new_task_7.dat');
end
[rtlW, rtlH, rtlDT] = parse_5byte_header(fid);
fprintf('RTL:    %dx%d, TYPE=0x%02X\n', rtlW, rtlH, rtlDT);
rtlLr0 = fread(fid, [MAX_DISP, IMG_WIDTH * IMG_HEIGHT], 'uint16=>uint16');
fclose(fid);
rtlLr0 = reshape(rtlLr0', IMG_HEIGHT, IMG_WIDTH, MAX_DISP);

% ----- 逐像素比对 -----
% 检查 RTL 是否出现过饱和（12bit 截断）
if any(rtlLr0(:) > 4095) || any(matLr0(:) > 4095)
    fprintf('  ⚠  注意：检测到 >12bit 值，注意截断行为\n');
end

diffLr0 = abs(int32(matLr0) - int32(rtlLr0));
maxDiffLr0 = max(diffLr0, [], 'all');
meanDiffLr0 = mean(diffLr0, 'all');
mismatchPixelsLr0 = sum(diffLr0 > 0, 'all');

fprintf('  最大差异: %d\n', maxDiffLr0);
fprintf('  平均差异: %.4f\n', meanDiffLr0);
fprintf('  像素失配率: %.2f%% (%d / %d)\n', ...
    mismatchPixelsLr0 / totalPixels * 100, mismatchPixelsLr0, totalPixels);

if maxDiffLr0 == 0
    fprintf('  ✅ Stage 10: MATLAB Lr_LR == RTL Lr0_curr (完全一致!)\n');
else
    fprintf('  ❌ Stage 10: 存在差异！\n');
    [maxErrY, maxErrX, maxErrD] = ind2sub(size(diffLr0), find(diffLr0 == maxDiffLr0, 1));
    fprintf('     最大误差位置: y=%d, x=%d, d=%d (MATLAB=%d, RTL=%d)\n', ...
        maxErrY, maxErrX, maxErrD, matLr0(maxErrY, maxErrX, maxErrD), rtlLr0(maxErrY, maxErrX, maxErrD));
end

%% ===================== Stage 11: 合并代价比对 =====================
fprintf('\n========================================\n');
fprintf('Stage 11: 合并代价比对 (Lr_LR vs combined_lr)\n');
fprintf('========================================\n');
fprintf('  [注意] 当前 RTL combined_lr = Lr0_curr (单路径，Lr2已注释)\n');

% ----- 加载 MATLAB 参考 -----
fid = fopen(fullfile(matFolder, 'sgm_mat_task_8.dat'), 'rb');
if fid == -1
    error('找不到 MATLAB 文件: sgm_mat_task_8.dat');
end
[matW, matH, matDT] = parse_5byte_header(fid);
fprintf('MATLAB: %dx%d, TYPE=0x%02X\n', matW, matH, matDT);
matComb = fread(fid, [MAX_DISP, IMG_WIDTH * IMG_HEIGHT], 'uint16=>uint16');
fclose(fid);
matComb = reshape(matComb', IMG_HEIGHT, IMG_WIDTH, MAX_DISP);

% ----- 加载 RTL 输出 -----
fid = fopen(fullfile(rtlFolder, 'tb_sgm_new_task_8.dat'), 'rb');
if fid == -1
    error('找不到 RTL 文件: tb_sgm_new_task_8.dat');
end
[rtlW, rtlH, rtlDT] = parse_5byte_header(fid);
fprintf('RTL:    %dx%d, TYPE=0x%02X\n', rtlW, rtlH, rtlDT);
rtlComb = fread(fid, [MAX_DISP, IMG_WIDTH * IMG_HEIGHT], 'uint16=>uint16');
fclose(fid);
rtlComb = reshape(rtlComb', IMG_HEIGHT, IMG_WIDTH, MAX_DISP);

% ----- 逐像素比对 -----
diffComb = abs(int32(matComb) - int32(rtlComb));
maxDiffComb = max(diffComb, [], 'all');
meanDiffComb = mean(diffComb, 'all');
mismatchPixelsComb = sum(diffComb > 0, 'all');

fprintf('  最大差异: %d\n', maxDiffComb);
fprintf('  平均差异: %.4f\n', meanDiffComb);
fprintf('  像素失配率: %.2f%% (%d / %d)\n', ...
    mismatchPixelsComb / totalPixels * 100, mismatchPixelsComb, totalPixels);

if maxDiffComb == 0
    fprintf('  ✅ Stage 11: MATLAB Lr_LR == RTL combined_lr (完全一致!)\n');
else
    fprintf('  ❌ Stage 11: 存在差异！\n');
    [maxErrY, maxErrX, maxErrD] = ind2sub(size(diffComb), find(diffComb == maxDiffComb, 1));
    fprintf('     最大误差位置: y=%d, x=%d, d=%d (MATLAB=%d, RTL=%d)\n', ...
        maxErrY, maxErrX, maxErrD, matComb(maxErrY, maxErrX, maxErrD), rtlComb(maxErrY, maxErrX, maxErrD));
end

%% ===================== 生成可视化报告 =====================
fprintf('\n========================================\n');
fprintf('生成比对报告...\n');
fprintf('========================================\n');

% Stage 4: 差异图（每视差级别的平均差异）
diffMapHam = squeeze(mean(diffHam, 3));
diffMapLr0 = squeeze(mean(diffLr0, 3));
diffMapComb = squeeze(mean(diffComb, 3));

figure('Name', 'SGM Pipeline 逐级比对报告', 'Color', 'w', 'Position', [100, 100, 1200, 800]);

subplot(3, 4, 1);
imshow(matHam(:, :, 1), []); title('MATLAB Stage4: d=0');
subplot(3, 4, 2);
imshow(rtlHam(:, :, 1), []); title('RTL Stage4: d=0');
subplot(3, 4, 3);
imshow(diffMapHam, []); title(sprintf('Stage4 差异均值, max=%.1f', max(diffMapHam, [], 'all')));
colorbar;
subplot(3, 4, 4);
histogram(diffHam(:), 0:maxDiffHam+1); title(sprintf('Stage4 差异分布'));
xlabel('差异值'); ylabel('像素数');

subplot(3, 4, 5);
imshow(matLr0(:, :, 1), []); title('MATLAB Stage10: d=0');
subplot(3, 4, 6);
imshow(rtlLr0(:, :, 1), []); title('RTL Stage10: d=0');
subplot(3, 4, 7);
imshow(diffMapLr0, []); title(sprintf('Stage10 差异均值, max=%.1f', max(diffMapLr0, [], 'all')));
colorbar;
subplot(3, 4, 8);
histogram(diffLr0(:), 0:min(maxDiffLr0+1, 50)); title(sprintf('Stage10 差异分布'));
xlabel('差异值'); ylabel('像素数');

subplot(3, 4, 9);
imshow(matComb(:, :, 1), []); title('MATLAB Stage11: d=0');
subplot(3, 4, 10);
imshow(rtlComb(:, :, 1), []); title('RTL Stage11: d=0');
subplot(3, 4, 11);
imshow(diffMapComb, []); title(sprintf('Stage11 差异均值, max=%.1f', max(diffMapComb, [], 'all')));
colorbar;
subplot(3, 4, 12);
histogram(diffComb(:), 0:min(maxDiffComb+1, 50)); title(sprintf('Stage11 差异分布'));
xlabel('差异值'); ylabel('像素数');

sgtitle('SGM Pipeline FPGA vs MATLAB 逐级比对');

% 保存报告
reportPath = fullfile(outFolder, 'sgm_pipeline_verification_report.png');
saveas(gcf, reportPath);
fprintf('比对报告已保存至: %s\n', reportPath);

%% ===================== 输出汇总 =====================
fprintf('\n========================================\n');
fprintf('            SGM PIPELINE VERIFICATION SUMMARY\n');
fprintf('========================================\n');
fprintf('  Stage  |  Variable     |  MaxDiff  |  MeanDiff  |  MatchRate\n');
fprintf('---------------------------------------------------------------\n');

matchRateHam = (1 - mismatchPixelsHam / totalPixels) * 100;
matchRateLr0 = (1 - mismatchPixelsLr0 / totalPixels) * 100;
matchRateComb = (1 - mismatchPixelsComb / totalPixels) * 100;

fprintf('  Stage4 |  hamming_dist  |  %6d  |  %8.4f  |  %6.2f%%\n', maxDiffHam, meanDiffHam, matchRateHam);
fprintf('  Stage10|  Lr0_curr      |  %6d  |  %8.4f  |  %6.2f%%\n', maxDiffLr0, meanDiffLr0, matchRateLr0);
fprintf('  Stage11|  combined_lr   |  %6d  |  %8.4f  |  %6.2f%%\n', maxDiffComb, meanDiffComb, matchRateComb);
fprintf('---------------------------------------------------------------\n');

if maxDiffHam == 0 && maxDiffLr0 == 0 && maxDiffComb == 0
    fprintf('\n  🎉 全部三级比对完全一致! RTL 与 MATLAB 行为完全匹配！\n');
else
    fprintf('\n  ⚠  存在差异，请检查上述误差位置处的 RTL 与 MATLAB 行为。\n');
    if maxDiffLr0 > 0
        fprintf('     - 常见原因：MATLAB 浮点精度 vs RTL 定点截断\n');
    end
    if maxDiffComb > 0
        fprintf('     - combined_lr 差异若与 Lr0_curr 一致，则来自 Lr0 传播\n');
    end
end

fprintf('\n比对完成！\n');

%% ===================== 局部函数 =====================
function [w, h, dtype] = parse_5byte_header(fid)
    hdr = fread(fid, 5, 'uint8=>uint8');
    if length(hdr) < 5
        error('文件头不足5字节！');
    end
    w     = uint16(hdr(1)) * 256 + uint16(hdr(2));
    h     = uint16(hdr(3)) * 256 + uint16(hdr(4));
    dtype = hdr(5);
end
