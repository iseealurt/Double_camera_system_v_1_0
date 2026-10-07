%% 独立 Hamming 距离比对与可视化脚本
% 功能：单独比较 MATLAB costVol 与 RTL hamming_dist，保存可视化图片
% 增强的偏移扫描范围（d_shift 扩大到 ±48，含 d_flip）
% 用法：
%   1. 运行此脚本
%   2. 选择 MATLAB 输出文件夹（含 sgm_mat_task_6.dat）
%   3. 选择 RTL 输出文件夹（含 tb_sgm_new_task_6.dat）
%   4. 选择输出文件夹

clc;
clear;
close all;

%% ===================== 参数 =====================
IMG_WIDTH       = 640;
IMG_HEIGHT      = 480;
MAX_DISP        = 48;
BYTES_PER_PIXEL = 48;
HEADER_SIZE     = 5;

%% ===================== 选择文件夹 =====================
matFolder = uigetdir('', '请选择 MATLAB 输出文件夹（含 sgm_mat_task_6.dat）');
if isequal(matFolder, 0)
    disp('未选择 MATLAB 文件夹，程序结束。');
    return;
end

rtlFolder = uigetdir('', '请选择 RTL 输出文件夹（含 tb_sgm_new_task_6.dat）');
if isequal(rtlFolder, 0)
    disp('未选择 RTL 文件夹，程序结束。');
    return;
end

outFolder = uigetdir('', '请选择输出文件夹（保存图片）');
if isequal(outFolder, 0)
    disp('未选择输出文件夹，程序结束。');
    return;
end

%% ===================== 加载数据 =====================
% MATLAB
fid = fopen(fullfile(matFolder, 'sgm_mat_task_6.dat'), 'rb');
if fid == -1, error('找不到 MATLAB 文件: sgm_mat_task_6.dat'); end
hdr = fread(fid, 5, 'uint8=>uint8');
matW = uint16(hdr(1))*256 + uint16(hdr(2));
matH = uint16(hdr(3))*256 + uint16(hdr(4));
matDT = hdr(5);
fprintf('MATLAB: %dx%d, TYPE=0x%02X\n', matW, matH, matDT);
matHam = fread(fid, [MAX_DISP, IMG_WIDTH * IMG_HEIGHT], 'uint8=>uint8');
fclose(fid);
matHam = permute(reshape(matHam', IMG_HEIGHT, IMG_WIDTH, MAX_DISP), [1 2 3]);

% RTL
fid = fopen(fullfile(rtlFolder, 'tb_sgm_new_task_6.dat'), 'rb');
if fid == -1, error('找不到 RTL 文件: tb_sgm_new_task_6.dat'); end
hdr = fread(fid, 5, 'uint8=>uint8');
rtlW = uint16(hdr(1))*256 + uint16(hdr(2));
rtlH = uint16(hdr(3))*256 + uint16(hdr(4));
rtlDT = hdr(5);
fprintf('RTL:    %dx%d, TYPE=0x%02X\n', rtlW, rtlH, rtlDT);
rtlHam = fread(fid, [MAX_DISP, IMG_WIDTH * IMG_HEIGHT], 'uint8=>uint8');
fclose(fid);
rtlHam = permute(reshape(rtlHam', IMG_HEIGHT, IMG_WIDTH, MAX_DISP), [1 2 3]);

%% ===================== 增强偏移扫描：d_shift ±48, 含 d_flip =====================
fprintf('\n========================================\n');
fprintf('增强偏移扫描 (d_shift = -48~+48, 含 d_flip)\n');
fprintf('========================================\n');

bestShiftX  = 0;   bestShiftD  = 0;   bestFlip = 0;
bestShiftX2 = 0;   bestShiftD2 = 0;   bestFlip2 = 0;
bestMatch   = 0;   bestMatch2  = 0;

% 第一轮：快速粗扫
fprintf('  第一轮粗扫 (x ±5, d ±48)...\n');
for flipD = 0:1
    for shiftX = -5:5
        for shiftD = -48:48
            if flipD == 1
                m = matHam(:, :, end:-1:1);
            else
                m = matHam;
            end
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
fprintf('  粗扫最佳: x_shift=%d, d_shift=%d, d_flip=%d, 匹配率 = %.2f%%\n', ...
    bestShiftX, bestShiftD, bestFlip, bestMatch);

% 第二轮：在最优 d_shift 附近细扫 x (±60)
fprintf('  第二轮细扫 (x ±60, d 固定)...\n');
bestMatch2 = bestMatch;
bestShiftX2 = bestShiftX;
bestShiftD2 = bestShiftD;
bestFlip2 = bestFlip;
for flipD = 0:1
    for shiftX = -60:60
        if flipD == 1
            m = matHam(:, :, end:-1:1);
        else
            m = matHam;
        end
        xR = max(1, 1-shiftX):min(640, 640-shiftX);
        xM = xR + shiftX;
        dR = max(1, 1-bestShiftD):min(48, 48-bestShiftD);
        dM = dR + bestShiftD;

        mRegion = m(:, xM, dM);
        rRegion = rtlHam(:, xR, dR);
        matchRate = sum(mRegion == rRegion, 'all') / numel(mRegion) * 100;

        if matchRate > bestMatch2
            bestMatch2 = matchRate;
            bestShiftX2 = shiftX;
            bestShiftD2 = bestShiftD;
            bestFlip2 = flipD;
        end
    end
end
fprintf('  细扫最佳: x_shift=%d, d_shift=%d, d_flip=%d, 匹配率 = %.2f%%\n', ...
    bestShiftX2, bestShiftD2, bestFlip2, bestMatch2);

% 如果最佳匹配很低，再扫一下极限 d_shift (±47) 的细粒度 x
if bestMatch2 < 50
    fprintf('  ⚠ 匹配率 < 50%%，尝试更多 d_shift 组合...\n');
    for flipD = 0:1
        for shiftD = [-48, -47, -1, 0, 1, 47, 48]
            if flipD == 1
                m = matHam(:, :, end:-1:1);
            else
                m = matHam;
            end
            xR = max(1, 1-bestShiftX2):min(640, 640-bestShiftX2);
            xM = xR + bestShiftX2;
            dR = max(1, 1-shiftD):min(48, 48-shiftD);
            dM = dR + shiftD;

            mRegion = m(:, xM, dM);
            rRegion = rtlHam(:, xR, dR);
            matchRate = sum(mRegion == rRegion, 'all') / numel(mRegion) * 100;

            if matchRate > bestMatch2
                bestMatch2 = matchRate;
                bestShiftD2 = shiftD;
                bestFlip2 = flipD;
                fprintf('  -> 新最佳: x_shift=%d, d_shift=%d, d_flip=%d, 匹配率 = %.2f%%\n', ...
                    bestShiftX2, bestShiftD2, bestFlip2, bestMatch2);
            end
        end
    end
end

fprintf('\n  最终最佳对齐: x_shift=%d, d_shift=%d, d_flip=%d, 匹配率 = %.2f%%\n', ...
    bestShiftX2, bestShiftD2, bestFlip2, bestMatch2);

%% ===================== 逐像素比对 (无偏移) =====================
fprintf('\n========================================\n');
fprintf('逐像素比对 (无偏移)\n');
fprintf('========================================\n');

diffHam    = abs(int16(matHam) - int16(rtlHam));
maxDiffHam = max(diffHam, [], 'all');
meanDiffHam = mean(diffHam, 'all');
mismatchPixels = sum(diffHam > 0, 'all');
totalPixels    = IMG_HEIGHT * IMG_WIDTH * MAX_DISP;
matchRateRaw   = (1 - mismatchPixels / totalPixels) * 100;

fprintf('  最大差异  : %d\n', maxDiffHam);
fprintf('  平均差异  : %.4f\n', meanDiffHam);
fprintf('  匹配率    : %.2f%%\n', matchRateRaw);
fprintf('  失配像素数: %d / %d\n', mismatchPixels, totalPixels);

%% ===================== 诊断：逐 disparity 层分析 =====================
fprintf('\n========================================\n');
fprintf('逐 disparity 层匹配率分析\n');
fprintf('========================================\n');
fprintf('   d  |  MatchRate  |  MaxDiff  |  MeanDiff\n');
fprintf('  ----+------------+-----------+-----------\n');
dMatchRates = zeros(1, MAX_DISP);
for d_idx = 1:MAX_DISP
    sliceDiff = diffHam(:, :, d_idx);
    dMaxDiff  = max(sliceDiff, [], 'all');
    dMeanDiff = mean(sliceDiff, 'all');
    dMismatch = sum(sliceDiff > 0, 'all');
    dTotal    = IMG_HEIGHT * IMG_WIDTH;
    dMatchRates(d_idx) = (1 - dMismatch / dTotal) * 100;
    fprintf('  %2d  |  %6.2f%%   |  %7d  |  %8.4f\n', d_idx-1, dMatchRates(d_idx), dMaxDiff, dMeanDiff);
end

%% ===================== 诊断：最大误差像素位置详查 =====================
fprintf('\n========================================\n');
fprintf('最大误差像素位置详查\n');
fprintf('========================================\n');

% 找出全局最大误差的几个位置
diffFlat = diffHam(:);
[sortedDiffs, sortedIdx] = sort(diffFlat, 'descend');
nTopErrors = min(10, length(sortedDiffs));
for k = 1:nTopErrors
    if sortedDiffs(k) == 0, break; end
    [yy, xx, dd] = ind2sub(size(diffHam), sortedIdx(k));
    fprintf('  #%d: y=%d, x=%d, d=%d, |MAT=%d, RTL=%d|, diff=%d\n', ...
        k, yy, xx, dd-1, matHam(yy, xx, dd), rtlHam(yy, xx, dd), sortedDiffs(k));
end

%% ===================== 诊断：按y行的匹配率分布 =====================
fprintf('\n========================================\n');
fprintf('按行匹配率分析 (前10行 + 异常行)\n');
fprintf('========================================\n');
yMatchRates = zeros(1, IMG_HEIGHT);
for y = 1:IMG_HEIGHT
    sliceY = diffHam(y, :, :);
    yMismatch = sum(sliceY > 0, 'all');
    yMatchRates(y) = (1 - yMismatch / (IMG_WIDTH * MAX_DISP)) * 100;
end
fprintf('  前10行: ');
for y = 1:10
    fprintf('y=%-3d:%.1f%%  ', y, yMatchRates(y));
end
fprintf('\n  最低匹配率行: y=%-4d (%.2f%%), y=%-4d (%.2f%%), y=%-4d (%.2f%%)\n', ...
    find(yMatchRates == min(yMatchRates), 1), min(yMatchRates), ...
    find(yMatchRates == min(yMatchRates(yMatchRates > min(yMatchRates))), 1), ...
    min(yMatchRates(yMatchRates > min(yMatchRates))));

%% ===================== 可视化输出 =====================
fprintf('\n========================================\n');
fprintf('生成可视化报告...\n');
fprintf('========================================\n');

% ---- 图1：全景比对 ----
figure('Name', 'Hamming 距离独立比对', 'Color', 'w', 'Position', [50, 50, 1400, 900]);

% (A) MATLAB d=0
subplot(3,4,1);
imshow(matHam(:, :, 1), [0 24]); 
title('MATLAB costVol: d=0', 'FontSize', 12);
colormap(gca, jet);

% (B) RTL d=0
subplot(3,4,2);
imshow(rtlHam(:, :, 1), [0 24]);
title('RTL hamming\_dist: d=0', 'FontSize', 12);
colormap(gca, jet);

% (C) 差异图 d=0
subplot(3,4,3);
imshow(diffHam(:, :, 1), [0 max(1, max(diffHam(:, :, 1), [], 'all'))]);
title(sprintf('差异 d=0 (max=%d)', max(diffHam(:, :, 1), [], 'all')), 'FontSize', 12);
colorbar; colormap(gca, hot);

% (D) 差异直方图
subplot(3,4,4);
histogram(diffHam(:), 0:maxDiffHam+1, 'EdgeColor', 'none', 'FaceColor', [0.8 0.2 0.2]);
title(sprintf('差异分布 (匹配率=%.1f%%)', matchRateRaw), 'FontSize', 12);
xlabel('差异值'); ylabel('像素数');
xlim([0 25]);
text(0.5, 0.95, sprintf('maxDiff=%d, meanDiff=%.2f', maxDiffHam, meanDiffHam), ...
    'Units', 'normalized', 'FontSize', 10);

% (E) MATLAB d=24
subplot(3,4,5);
imshow(matHam(:, :, 25), [0 24]);
title('MATLAB costVol: d=24', 'FontSize', 12);
colormap(gca, jet);

% (F) RTL d=24
subplot(3,4,6);
imshow(rtlHam(:, :, 25), [0 24]);
title('RTL hamming\_dist: d=24', 'FontSize', 12);
colormap(gca, jet);

% (G) 差异图 d=24
subplot(3,4,7);
imshow(diffHam(:, :, 25), [0 max(1, max(diffHam(:, :, 25), [], 'all'))]);
title(sprintf('差异 d=24 (max=%d)', max(diffHam(:, :, 25), [], 'all')), 'FontSize', 12);
colorbar; colormap(gca, hot);

% (H) 所有 d 层的平均差异图
subplot(3,4,8);
meanDiffMap = squeeze(mean(diffHam, 3));
imshow(meanDiffMap, [0 max(1, max(meanDiffMap, [], 'all'))]);
title(sprintf('平均差异 (all d), max=%.1f', max(meanDiffMap, [], 'all')), 'FontSize', 12);
colorbar; colormap(gca, hot);

% (I) 每 disparity 层的匹配率曲线
subplot(3,4,9);
bar(0:MAX_DISP-1, dMatchRates, 'FaceColor', [0.3 0.6 0.9]);
title('每 disparity 层匹配率', 'FontSize', 12);
xlabel('disparity d'); ylabel('匹配率 %');
ylim([0 100]);
grid on;

% (J) 每行匹配率曲线
subplot(3,4,10);
plot(1:IMG_HEIGHT, yMatchRates, 'b-', 'LineWidth', 1);
title('每行匹配率', 'FontSize', 12);
xlabel('行号 y'); ylabel('匹配率 %');
ylim([0 100]);
grid on;

% (K) MATLAB 最优 d (argmin) = WTA 结果
subplot(3,4,11);
[~, matMinD] = min(matHam, [], 3);
imagesc(matMinD); axis image; colorbar;
title('MATLAB WTA (argmin)', 'FontSize', 12);
colormap(gca, jet);

% (L) RTL 最优 d (argmin)
subplot(3,4,12);
[~, rtlMinD] = min(rtlHam, [], 3);
imagesc(rtlMinD); axis image; colorbar;
title('RTL WTA (argmin)', 'FontSize', 12);
colormap(gca, jet);

sgtitle(sprintf('Hamming 距离独立比对 | 匹配率=%.2f%% | 偏移扫描最佳: x=%d, d=%d, flip=%d | 匹配率=%.2f%%', ...
    matchRateRaw, bestShiftX2, bestShiftD2, bestFlip2, bestMatch2), 'FontSize', 14);

% 保存图1
saveas(gcf, fullfile(outFolder, 'hamming_comparison_overview.png'));
fprintf('  已保存: hamming_comparison_overview.png\n');

% ---- 图2：偏移扫描结果与热力图 ----
figure('Name', '偏移扫描与错误热力图', 'Color', 'w', 'Position', [100, 100, 1200, 700]);

% (A) 应用最佳对齐后的差异
subplot(2,3,1);
if bestFlip2 == 1
    mAligned = matHam(:, :, end:-1:1);
else
    mAligned = matHam;
end
xRng = max(1, 1-bestShiftX2):min(640, 640-bestShiftX2);
dRng = max(1, 1-bestShiftD2):min(48, 48-bestShiftD2);
mAlignedCrop = mAligned(:, xRng + bestShiftX2, dRng + bestShiftD2);
rtlCrop      = rtlHam(:, xRng, dRng);
diffAligned  = abs(int16(mAlignedCrop) - int16(rtlCrop));
meanDiffAligned = squeeze(mean(diffAligned, 3));
imshow(meanDiffAligned, [0 max(1, max(meanDiffAligned, [], 'all'))]);
title(sprintf('最佳对齐后平均差异 (x=%d,d=%d,flip=%d,匹配=%.1f%%)', ...
    bestShiftX2, bestShiftD2, bestFlip2, bestMatch2), 'FontSize', 11);
colorbar; colormap(gca, hot);

% (B) 对齐后差异分布直方图
subplot(2,3,2);
histogram(diffAligned(:), 0:max(diffAligned(:))+1, 'EdgeColor', 'none');
title(sprintf('对齐后差异分布 (mean=%.2f)', mean(diffAligned, 'all')), 'FontSize', 11);
xlabel('差异值'); ylabel('像素数');

% (C) 几个典型行的 d-slice 错误图
subplot(2,3,3);
errorLineY = [1, 60, 120, 240, 360, 480];
hold on;
colors = lines(length(errorLineY));
for k = 1:length(errorLineY)
    yy = errorLineY(k);
    if yy <= IMG_HEIGHT
        dErr = squeeze(mean(diffHam(yy, :, :), 2));
        plot(0:MAX_DISP-1, dErr, '-', 'Color', colors(k,:), 'LineWidth', 1.5, ...
            'DisplayName', sprintf('y=%d', yy));
    end
end
hold off;
title('典型行 - 每个 disparity 的平均差异', 'FontSize', 11);
xlabel('disparity d'); ylabel('平均差异');
legend('Location', 'best');
grid on;

% (D-F) 3 个关键 disparity 层的 RTL vs MATLAB 散点对比
dChkList = [0, 23, 47];
for k = 1:3
    dPick = dChkList(k);
    subplot(2, 3, 3+k);
    dIdx = dPick + 1;
    yMid = 240;
    xVals = 1:min(100, IMG_WIDTH);
    plot(xVals, squeeze(matHam(yMid, xVals, dIdx)), 'b-', 'LineWidth', 1.5); hold on;
    plot(xVals, squeeze(rtlHam(yMid, xVals, dIdx)), 'r--', 'LineWidth', 1.5); hold off;
    title(sprintf('y=240, d=%d: 行剖面', dPick), 'FontSize', 11);
    xlabel('列 x'); ylabel('Hamming');
    legend('MATLAB', 'RTL', 'Location', 'best');
    grid on;
end

sgtitle('Hamming 距离诊断详情', 'FontSize', 14);
saveas(gcf, fullfile(outFolder, 'hamming_diagnosis_detail.png'));
fprintf('  已保存: hamming_diagnosis_detail.png\n');

%% ===================== 打印最终结论 =====================
fprintf('\n========================================\n');
fprintf('            诊断结论\n');
fprintf('========================================\n');

fprintf('  (1) 无偏匹配率           : %.2f%%\n', matchRateRaw);
fprintf('  (2) 最佳偏移对齐匹配率   : %.2f%% (x=%d, d=%d, flip=%d)\n', ...
    bestMatch2, bestShiftX2, bestShiftD2, bestFlip2);
fprintf('  (3) 最大差异             : %d\n', maxDiffHam);
fprintf('  (4) 平均差异             : %.4f\n', meanDiffHam);

if matchRateRaw > 98
    fprintf('\n  ✅ Hamming 距离匹配良好，RTL 与 MATLAB 计算一致！\n');
elseif bestMatch2 > 90
    fprintf('\n  ⚠ 存在系统性偏移 (x=%d, d=%d, flip=%d)。\n', bestShiftX2, bestShiftD2, bestFlip2);
    fprintf('     检查：xor_window 移位方向、预读数量、FIFO 延迟对齐。\n');
else
    fprintf('\n  ❌ 大面积不匹配，无法用简单偏移对齐。\n');
    fprintf('     可能原因：\n');
    fprintf('     - xor_window 移位方向导致 d-index 翻转/偏移\n');
    fprintf('     - 预读像素数与 disparity 索引的对应关系错误\n');
    fprintf('     - FIFO 读延迟与 cmr2_census 延迟的对齐时序有问题\n');
    fprintf('     - Census 数据的位顺序 (大端/小端) 不一致\n');
    
    if bestMatch2 < 20
        fprintf('\n  🔴 匹配率 < 20%%，很可能是移位方向或 d-index 错位。\n');
        fprintf('     请检查：hamming_dist[i] 实际计算的 disparity 是 i 还是 (47-i)；\n');
        fprintf('     或验证 xor_window 移位方向：新左图像素从 [0] 进入还是从 [47] 进入。\n');
    end
end

fprintf('\n  可视化文件已保存至: %s\n', outFolder);
fprintf('\n比对完成！\n');
