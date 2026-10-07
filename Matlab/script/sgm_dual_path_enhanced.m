%% 4方向DP空洞填充（方案C升级版）
% 对应 plan.md 1.3 实现方法C
% WTA输出视差图 → 置信度检测 → 空洞标记
% 4方向传播: 左→右 + 上→下 + 左上→右下 + 右上→左下
% 合并策略: 4方向中值
% 纯前馈，1 px/cycle，无反馈环

clc;
clear;
close all;

%% ===================== 算法参数 =====================
IMG_WIDTH       = 640;
IMG_HEIGHT      = 480;
MAX_DISP        = 48;
CENSUS_BITS     = 24;
BYTES_PER_PIXEL = 3;

% 置信度阈值（与 sgm_new.v CONFIDENCE_THRE 一致）
CONFIDENCE_THRE = 3;

% DP传播参数
P1_THRESH       = 3;    % 传播容忍度，越大填洞越激进，越小边缘保持越好
MERGE_THRESH    = 3;    % 4方向中值合并时的分群判据
USE_MEDIAN      = true; % true=4方向中值, false=4方向取min(前景优先)

% 无效代价（边界填充用）
INVALID_COST = CENSUS_BITS;  % 24

%% ===================== 1. 选择输入文件 =====================
[leftFile, leftPath] = uigetfile('*.dat', '请选择左目 24bit Census dat 文件');
if isequal(leftFile, 0)
    disp('未选择左目文件，程序结束。');
    return;
end

[rightFile, rightPath] = uigetfile('*.dat', '请选择右目 24bit Census dat 文件');
if isequal(rightFile, 0)
    disp('未选择右目文件，程序结束。');
    return;
end

leftDatPath  = fullfile(leftPath, leftFile);
rightDatPath = fullfile(rightPath, rightFile);

outFolder = uigetdir('', '请选择输出文件夹');
if isequal(outFolder, 0)
    disp('未选择输出文件夹，程序结束。');
    return;
end

%% ===================== 2. 读取 ASCII 十六进制 Census dat 文件 =====================
expectedNumValues = IMG_WIDTH * IMG_HEIGHT * BYTES_PER_PIXEL + 5;

leftStr = fileread(leftDatPath);
leftTokens = strsplit(strtrim(leftStr));
if numel(leftTokens) ~= expectedNumValues
    error('左目 dat 文件数值个数错误！期望 %d 个，实际 %d 个', expectedNumValues, numel(leftTokens));
end
leftVals = uint8(hex2dec(leftTokens.'));

leftW = uint16(leftVals(1)) * 256 + uint16(leftVals(2));
leftH = uint16(leftVals(3)) * 256 + uint16(leftVals(4));
leftDT = leftVals(5);
if leftW ~= IMG_WIDTH || leftH ~= IMG_HEIGHT
    error('左目文件头尺寸不匹配：期望 %dx%d，实际 %dx%d', IMG_WIDTH, IMG_HEIGHT, leftW, leftH);
end
if leftDT ~= 2, error('左目文件类型错误：期望 2，实际 %d', leftDT); end
leftVals = leftVals(6:end);

rightStr = fileread(rightDatPath);
rightTokens = strsplit(strtrim(rightStr));
if numel(rightTokens) ~= expectedNumValues
    error('右目 dat 文件数值个数错误！期望 %d 个，实际 %d 个', expectedNumValues, numel(rightTokens));
end
rightVals = uint8(hex2dec(rightTokens.'));

rightW = uint16(rightVals(1)) * 256 + uint16(rightVals(2));
rightH = uint16(rightVals(3)) * 256 + uint16(rightVals(4));
rightDT = rightVals(5);
if rightW ~= IMG_WIDTH || rightH ~= IMG_HEIGHT
    error('右目文件头尺寸不匹配：期望 %dx%d，实际 %dx%d', IMG_WIDTH, IMG_HEIGHT, rightW, rightH);
end
if rightDT ~= 2, error('右目文件类型错误：期望 2，实际 %d', rightDT); end
rightVals = rightVals(6:end);

%% ===================== 3. 重组为 24bit Census 图像 =====================
leftVals  = reshape(leftVals,  BYTES_PER_PIXEL, []).';
rightVals = reshape(rightVals, BYTES_PER_PIXEL, []).';

leftCensus = uint32(leftVals(:,1)) + ...
             bitshift(uint32(leftVals(:,2)), 8) + ...
             bitshift(uint32(leftVals(:,3)), 16);
rightCensus = uint32(rightVals(:,1)) + ...
              bitshift(uint32(rightVals(:,2)), 8) + ...
              bitshift(uint32(rightVals(:,3)), 16);

leftCensus  = reshape(leftCensus,  IMG_WIDTH, IMG_HEIGHT).';
rightCensus = reshape(rightCensus, IMG_WIDTH, IMG_HEIGHT).';
fprintf('Census 数据加载完成：%dx%d, 24bit\n', IMG_WIDTH, IMG_HEIGHT);

%% ===================== 4. Hamming 代价体 + WTA 无聚合视差图 =====================
% 直接计算 hamming distance，不做任何 SGM 代价聚合
% 同时记录最小代价和次小代价，用于置信度计算
fprintf('===== Hamming 代价体计算 + WTA =====\n');

costVol      = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_DISP, 'uint8');
disparityMap = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');
confidenceMap = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');
validMap     = false(IMG_HEIGHT, IMG_WIDTH);

popLUT = uint8(sum(dec2bin(0:255) == '1', 2));

hwb = waitbar(0, 'Hamming 代价体...');
for d_val = 0:MAX_DISP-1
    if d_val == 0
        xr = 1:IMG_WIDTH;
        xl = 1:IMG_WIDTH;
    else
        xr = 1:(IMG_WIDTH-d_val);
        xl = (d_val+1):IMG_WIDTH;
    end
    plane = uint8(ones(IMG_HEIGHT, IMG_WIDTH) * INVALID_COST);
    if ~isempty(xr)
        xorVal = bitxor(rightCensus(:, xr), leftCensus(:, xl));
        b0 = bitand(xorVal, uint32(255));
        b1 = bitand(bitshift(xorVal, -8), uint32(255));
        b2 = bitand(bitshift(xorVal, -16), uint32(255));
        ham = popLUT(double(b0)+1) + popLUT(double(b1)+1) + popLUT(double(b2)+1);
        plane(:, xr) = ham;
    end
    costVol(:, :, d_val+1) = plane;
    waitbar((d_val+1)/MAX_DISP, hwb, sprintf('d=%d/%d', d_val, MAX_DISP-1));
end
close(hwb);

fprintf('WTA + 置信度计算...\n');
for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        costs = squeeze(costVol(y, x, :));
        [sortedCosts, sortIdx] = sort(costs);
        best_d = sortIdx(1) - 1;
        best_cost = sortedCosts(1);
        second_best_cost = sortedCosts(2);

        disparityMap(y, x) = uint8(best_d);
        confidence = second_best_cost - best_cost;
        confidenceMap(y, x) = uint8(confidence);
        validMap(y, x) = (confidence >= CONFIDENCE_THRE) && (best_d > 0);
    end
end

holeCount = sum(~validMap(:));
totalPix  = IMG_WIDTH * IMG_HEIGHT;
fprintf('WTA 完成: 空洞 %d / %d (%.1f%%)\n', holeCount, totalPix, 100*holeCount/totalPix);

%% ===================== 5. 左→右 DP 传播 (L→R) =====================
% 对应 FPGA: 单 8bit 寄存器 Lr_reg, 每行复位
% 前驱: (y, x-1), 同行左侧
fprintf('===== 左→右 DP 传播 (P1_THRESH=%d) =====\n', P1_THRESH);

disp_LR  = disparityMap;
valid_LR = validMap;

for y = 1:IMG_HEIGHT
    Lr_reg = uint8(0);
    for x = 1:IMG_WIDTH
        if valid_LR(y, x)
            Lr_reg = disp_LR(y, x);
        else
            disp_LR(y, x) = Lr_reg;
            valid_LR(y, x) = true;
        end
    end
end

holeAfterLR = sum(~valid_LR(:));
fprintf('  左→右完成: 空洞 %d → %d (填了 %d)\n', holeCount, holeAfterLR, holeCount - holeAfterLR);

%% ===================== 6. 上→下 DP 传播 (T→B) =====================
% 对应 FPGA: 640×8bit RAM (1行缓冲)
% 前驱: (y-1, x), 上一行同列
fprintf('===== 上→下 DP 传播 (P1_THRESH=%d) =====\n', P1_THRESH);

disp_TB  = disparityMap;
valid_TB = validMap;
Tb_buf   = zeros(1, IMG_WIDTH, 'uint8');

for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        Tb_val = Tb_buf(x);
        if valid_TB(y, x)
            Tb_buf(x) = disp_TB(y, x);
        else
            disp_TB(y, x) = Tb_val;
            valid_TB(y, x) = true;
        end
    end
end

holeAfterTB = sum(~valid_TB(:));
fprintf('  上→下完成: 空洞 %d → %d (填了 %d)\n', holeCount, holeAfterTB, holeCount - holeAfterTB);

%% ===================== 6b. 左上→右下 DP 传播 (TL→BR) =====================
% 对应 FPGA: 640×8bit RAM (2行ping-pong缓冲)
% 前驱: (y-1, x-1), 上一行左侧
% 行首(x=1)时无左上前驱 → 传播值=0
fprintf('===== 左上→右下 DP 传播 (P1_THRESH=%d) =====\n', P1_THRESH);

disp_TLBR  = disparityMap;
valid_TLBR = validMap;
Tlbr_buf   = zeros(1, IMG_WIDTH, 'uint8');   % 上一行结果（读）
Tlbr_curr  = zeros(1, IMG_WIDTH, 'uint8');    % 本行结果（写）

for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        if x == 1
            tlbr_pred = uint8(0);
        else
            tlbr_pred = Tlbr_buf(x - 1);
        end

        if valid_TLBR(y, x)
            if abs(int32(disp_TLBR(y, x)) - int32(tlbr_pred)) <= P1_THRESH
                Tlbr_curr(x) = disp_TLBR(y, x);
            else
                Tlbr_curr(x) = disp_TLBR(y, x);
            end
        else
            disp_TLBR(y, x) = tlbr_pred;
            Tlbr_curr(x) = tlbr_pred;
            valid_TLBR(y, x) = true;
        end
    end
    % 行末交换: 本行 → 上一行
    Tlbr_buf = Tlbr_curr;
    Tlbr_curr = zeros(1, IMG_WIDTH, 'uint8');
end

holeAfterTLBR = sum(~valid_TLBR(:));
fprintf('  左上→右下完成: 空洞 %d → %d (填了 %d)\n', holeCount, holeAfterTLBR, holeCount - holeAfterTLBR);

%% ===================== 6c. 右上→左下 DP 传播 (TR→BL) =====================
% 对应 FPGA: 640×8bit RAM (2行ping-pong缓冲)
% 前驱: (y-1, x+1), 上一行右侧
% 行尾(x=IMG_WIDTH)时无右上前驱 → 传播值=0
fprintf('===== 右上→左下 DP 传播 (P1_THRESH=%d) =====\n', P1_THRESH);

disp_TRBL  = disparityMap;
valid_TRBL = validMap;
Trbl_buf   = zeros(1, IMG_WIDTH, 'uint8');   % 上一行结果（读）
Trbl_curr  = zeros(1, IMG_WIDTH, 'uint8');    % 本行结果（写）

for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        if x == IMG_WIDTH
            trbl_pred = uint8(0);
        else
            trbl_pred = Trbl_buf(x + 1);
        end

        if valid_TRBL(y, x)
            if abs(int32(disp_TRBL(y, x)) - int32(trbl_pred)) <= P1_THRESH
                Trbl_curr(x) = disp_TRBL(y, x);
            else
                Trbl_curr(x) = disp_TRBL(y, x);
            end
        else
            disp_TRBL(y, x) = trbl_pred;
            Trbl_curr(x) = trbl_pred;
            valid_TRBL(y, x) = true;
        end
    end
    Trbl_buf = Trbl_curr;
    Trbl_curr = zeros(1, IMG_WIDTH, 'uint8');
end

holeAfterTRBL = sum(~valid_TRBL(:));
fprintf('  右上→左下完成: 空洞 %d → %d (填了 %d)\n', holeCount, holeAfterTRBL, holeCount - holeAfterTRBL);

%% ===================== 7. 4方向合并 =====================
% 合并策略:
%   USE_MEDIAN=true : 4个方向值排序, 取中值(索引2)
%   USE_MEDIAN=false: 4个方向取min (前景优先)
%
%   FPGA等价: 4输入中值 = 4级 2:1比较器 → 1级选择
fprintf('===== 4方向合并 (median=%d, MERGE_THRESH=%d) =====\n', USE_MEDIAN, MERGE_THRESH);

disp_merged = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');
valid_merged = false(IMG_HEIGHT, IMG_WIDTH);

for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        if validMap(y, x)
            disp_merged(y, x) = disparityMap(y, x);
            valid_merged(y, x) = true;
        else
            vals = [disp_LR(y, x), disp_TB(y, x), ...
                    disp_TLBR(y, x), disp_TRBL(y, x)];

            if USE_MEDIAN
                sv = sort(vals);
                % 4元素中值: 看聚集程度
                if max(vals) - min(vals) <= MERGE_THRESH
                    % 4方向高度一致 → 取中值(平均值)
                    disp_merged(y, x) = uint8((uint16(sv(2)) + uint16(sv(3)) + 1) / 2);
                else
                    % 有分歧 → 取第二小(保守)
                    disp_merged(y, x) = sv(2);
                end
            else
                disp_merged(y, x) = min(vals);
            end
            valid_merged(y, x) = true;
        end
    end
end

fprintf('  合并完成: 全部填充, 空洞率 0%%\n');

%% ===================== 7b. 方向一致度统计 =====================
% 统计4个方向在空洞位置的分歧程度
disagreement = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');
for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        if ~validMap(y, x)
            vals = [disp_LR(y, x), disp_TB(y, x), ...
                    disp_TLBR(y, x), disp_TRBL(y, x)];
            disagreement(y, x) = max(vals) - min(vals);
        end
    end
end
fprintf('  空洞处4方向最大分歧: avg=%.1f, max=%d\n', ...
    mean(double(disagreement(disagreement > 0))), max(disagreement(:)));

%% ===================== 8. 可视化 =====================
oriGray     = uint8(255 * mat2gray(disparityMap, [0, MAX_DISP-1]));
lrGray      = uint8(255 * mat2gray(disp_LR,      [0, MAX_DISP-1]));
tbGray      = uint8(255 * mat2gray(disp_TB,      [0, MAX_DISP-1]));
tlbrGray    = uint8(255 * mat2gray(disp_TLBR,    [0, MAX_DISP-1]));
trblGray    = uint8(255 * mat2gray(disp_TRBL,    [0, MAX_DISP-1]));
mgGray      = uint8(255 * mat2gray(disp_merged,  [0, MAX_DISP-1]));

% 空洞标记图（空洞区域标红）
holeMark = repmat(oriGray, [1, 1, 3]);
redMask = repmat(~validMap, [1, 1, 3]);
holeMark(redMask) = 255;
holeMark(:, :, 2) = min(holeMark(:, :, 2), uint8(~validMap) * 255);
holeMark(:, :, 3) = min(holeMark(:, :, 3), uint8(~validMap) * 255);

figure('Name', '方案C升级: 4方向DP空洞填充', 'Color', 'w', 'Position', [50, 50, 1600, 900]);

subplot(3,4,1); imshow(oriGray);
title(sprintf('原始WTA (空洞 %d%%)', round(100*holeCount/totalPix)));

subplot(3,4,2); imshow(holeMark);
title('空洞标记 (红色)');

subplot(3,4,3); imshow(lrGray);
title(sprintf('左→右 (P1=%d)', P1_THRESH));

subplot(3,4,4); imshow(tbGray);
title('上→下');

subplot(3,4,5); imshow(tlbrGray);
title('左上→右下');

subplot(3,4,6); imshow(trblGray);
title('右上→左下');

subplot(3,4,7); imshow(mgGray);
title(sprintf('4方向合并 (%s)', 'median'));

% 差分图：DP填充 vs 原始WTA
diffMap = uint8(abs(int32(disp_merged) - int32(disparityMap)) * 5);
diffMap(diffMap > 255) = 255;
subplot(3,4,8); imshow(diffMap);
title('填充差异 (亮=变化大)');

% 置信度分布直方图
subplot(3,4,9);
histogram(double(confidenceMap(validMap)), 0:2:MAX_DISP);
xlabel('置信度'); ylabel('像素数');
title('有效像素置信度分布');
grid on;

% 空洞位置统计（按行）
subplot(3,4,10);
holePerRow = sum(~validMap, 2);
plot(1:IMG_HEIGHT, holePerRow);
xlabel('行号'); ylabel('空洞数');
title('空洞行分布');
grid on;

% 4方向分歧度分布
subplot(3,4,11);
histogram(double(disagreement(disagreement > 0)), 0:MAX_DISP);
xlabel('max-min 分歧'); ylabel('像素数');
title(sprintf('4方向分歧度 (avg=%.1f)', mean(double(disagreement(disagreement > 0)))));
grid on;

% 单独方向 vs 合并的 PSNR/空洞率
subplot(3,4,12);
dir_names = {'L→R','T→B','TL→BR','TR→BL','4dir'};
dir_holes = [holeAfterLR, holeAfterTB, holeAfterTLBR, holeAfterTRBL, 0];
bar(categorical(dir_names), dir_holes);
ylabel('剩余空洞数');
title('各方向空洞填充效果');
grid on;

%% ===================== 9. 参数扫描对比（P1_THRESH） =====================
fprintf('===== P1_THRESH 参数扫描 =====\n');

p1_values = [1, 2, 3, 4, 6];

% 对每个 P1 值跑完整的 4 方向流程，统计空洞填充情况
scan_results = zeros(length(p1_values), 5);  % [P1, L→R, T→B, TL→BR, TR→BL]

for pi = 1:length(p1_values)
    p1 = p1_values(pi);

    % L→R
    disp_p1 = disparityMap;
    valid_p1 = validMap;
    for y = 1:IMG_HEIGHT
        Lr = uint8(0);
        for x = 1:IMG_WIDTH
            if valid_p1(y, x), Lr = disp_p1(y, x);
            else, disp_p1(y, x) = Lr; valid_p1(y, x) = true; end
        end
    end
    hole1 = sum(~valid_p1(:));

    % T→B
    disp_p1 = disparityMap;
    valid_p1 = validMap;
    buf = zeros(1, IMG_WIDTH, 'uint8');
    for y = 1:IMG_HEIGHT
        for x = 1:IMG_WIDTH
            v = buf(x);
            if valid_p1(y, x), buf(x) = disp_p1(y, x);
            else, disp_p1(y, x) = v; valid_p1(y, x) = true; end
        end
    end
    hole2 = sum(~valid_p1(:));

    % TL→BR
    disp_p1 = disparityMap;
    valid_p1 = validMap;
    buf_prev = zeros(1, IMG_WIDTH, 'uint8');
    buf_curr = zeros(1, IMG_WIDTH, 'uint8');
    for y = 1:IMG_HEIGHT
        for x = 1:IMG_WIDTH
            pred = buf_prev(max(x-1, 1));
            if valid_p1(y, x), buf_curr(x) = disp_p1(y, x);
            else, disp_p1(y, x) = pred; valid_p1(y, x) = true; buf_curr(x) = pred; end
        end
        buf_prev = buf_curr;
        buf_curr = zeros(1, IMG_WIDTH, 'uint8');
    end
    hole3 = sum(~valid_p1(:));

    % TR→BL
    disp_p1 = disparityMap;
    valid_p1 = validMap;
    buf_prev = zeros(1, IMG_WIDTH, 'uint8');
    buf_curr = zeros(1, IMG_WIDTH, 'uint8');
    for y = 1:IMG_HEIGHT
        for x = 1:IMG_WIDTH
            pred = buf_prev(min(x+1, IMG_WIDTH));
            if valid_p1(y, x), buf_curr(x) = disp_p1(y, x);
            else, disp_p1(y, x) = pred; valid_p1(y, x) = true; buf_curr(x) = pred; end
        end
        buf_prev = buf_curr;
        buf_curr = zeros(1, IMG_WIDTH, 'uint8');
    end
    hole4 = sum(~valid_p1(:));

    scan_results(pi, :) = [p1, hole1, hole2, hole3, hole4];
    fprintf('  P1=%d: L→R=%d  T→B=%d  TL→BR=%d  TR→BL=%d\n', ...
        p1, hole1, hole2, hole3, hole4);
end

% 可视化参数扫描结果
figure('Name', 'P1_THRESH 参数扫描 - 4方向对比', 'Color', 'w', 'Position', [200, 200, 1200, 500]);

subplot(1,2,1);
plot(scan_results(:,1), scan_results(:,2), 'o-', 'LineWidth', 2); hold on;
plot(scan_results(:,1), scan_results(:,3), 's-', 'LineWidth', 2);
plot(scan_results(:,1), scan_results(:,4), 'd-', 'LineWidth', 2);
plot(scan_results(:,1), scan_results(:,5), '^-', 'LineWidth', 2);
xlabel('P1\_THRESH'); ylabel('剩余空洞数');
title('各P1下各方向填充能力');
legend('L→R','T→B','TL→BR','TR→BL', 'Location', 'best');
grid on;

subplot(1,2,2);
imshow(uint8(255 * mat2gray(disp_merged, [0, MAX_DISP-1])));
title(sprintf('最终结果 P1=%d (4方向中值)', P1_THRESH));

%% ===================== 10. 保存 =====================
[~, leftBase, ~] = fileparts(leftFile);
[~, rightBase, ~] = fileparts(rightFile);

prefix = sprintf('dpfill4d_P1_%d_MT_%d', P1_THRESH, MERGE_THRESH);

oriPath   = fullfile(outFolder, [prefix '_01_original_WTA.png']);
holePath  = fullfile(outFolder, [prefix '_02_hole_mark.png']);
lrPath    = fullfile(outFolder, [prefix '_03_left_right.png']);
tbPath    = fullfile(outFolder, [prefix '_04_top_bottom.png']);
tlbrPath  = fullfile(outFolder, [prefix '_05_topleft_botright.png']);
trblPath  = fullfile(outFolder, [prefix '_06_topright_botleft.png']);
mgPath    = fullfile(outFolder, [prefix '_07_merged_4dir.png']);
diffPath  = fullfile(outFolder, [prefix '_08_diff_from_original.png']);

imwrite(oriGray,  oriPath);
imwrite(holeMark, holePath);
imwrite(lrGray,   lrPath);
imwrite(tbGray,   tbPath);
imwrite(tlbrGray, tlbrPath);
imwrite(trblGray, trblPath);
imwrite(mgGray,   mgPath);
imwrite(diffMap,  diffPath);

% 保存参数扫描
for pi = 1:length(p1_values)
    p1 = p1_values(pi);

    % L→R only
    disp_p1 = disparityMap;
    valid_p1 = validMap;
    for y = 1:IMG_HEIGHT
        Lr = uint8(0);
        for x = 1:IMG_WIDTH
            if valid_p1(y, x), Lr = disp_p1(y, x);
            else, disp_p1(y, x) = Lr; valid_p1(y, x) = true; end
        end
    end
    imwrite(uint8(255 * mat2gray(disp_p1, [0, MAX_DISP-1])), ...
        fullfile(outFolder, sprintf('dpfill_P1_%d_onlyLR.png', p1)));

    % merged with this P1 (4 directions + median)
    disp_m = disparityMap;
    valid_m = validMap;

    % L→R
    for y = 1:IMG_HEIGHT
        Lr = uint8(0);
        for x = 1:IMG_WIDTH
            if valid_m(y, x), Lr = disp_m(y, x);
            else, disp_m(y, x) = Lr; valid_m(y, x) = true; end
        end
    end
    lr_pass = disp_m;

    % T→B
    disp_m = disparityMap;
    valid_m = validMap;
    buf = zeros(1, IMG_WIDTH, 'uint8');
    for y = 1:IMG_HEIGHT
        for x = 1:IMG_WIDTH
            v = buf(x);
            if valid_m(y, x), buf(x) = disp_m(y, x);
            else, disp_m(y, x) = v; valid_m(y, x) = true; end
        end
    end
    tb_pass = disp_m;

    % TL→BR
    disp_m = disparityMap;
    valid_m = validMap;
    bp = zeros(1, IMG_WIDTH, 'uint8'); bc = zeros(1, IMG_WIDTH, 'uint8');
    for y = 1:IMG_HEIGHT
        for x = 1:IMG_WIDTH
            pred = bp(max(x-1,1));
            if valid_m(y, x), bc(x) = disp_m(y, x);
            else, disp_m(y, x) = pred; valid_m(y, x) = true; bc(x) = pred; end
        end
        bp = bc; bc = zeros(1, IMG_WIDTH, 'uint8');
    end
    tlbr_pass = disp_m;

    % TR→BL
    disp_m = disparityMap;
    valid_m = validMap;
    bp = zeros(1, IMG_WIDTH, 'uint8'); bc = zeros(1, IMG_WIDTH, 'uint8');
    for y = 1:IMG_HEIGHT
        for x = 1:IMG_WIDTH
            pred = bp(min(x+1,IMG_WIDTH));
            if valid_m(y, x), bc(x) = disp_m(y, x);
            else, disp_m(y, x) = pred; valid_m(y, x) = true; bc(x) = pred; end
        end
        bp = bc; bc = zeros(1, IMG_WIDTH, 'uint8');
    end
    trbl_pass = disp_m;

    % merge
    for y = 1:IMG_HEIGHT
        for x = 1:IMG_WIDTH
            vals = sort([lr_pass(y,x), tb_pass(y,x), tlbr_pass(y,x), trbl_pass(y,x)]);
            disp_m(y,x) = vals(2);
        end
    end

    imwrite(uint8(255 * mat2gray(disp_m, [0, MAX_DISP-1])), ...
        fullfile(outFolder, sprintf('dpfill_P1_%d_merged4d.png', p1)));
end

fprintf('可视化结果已保存到: %s\n', outFolder);

%% ===================== 11. 保存 MATLAB 工作区 =====================
fprintf('===== 保存工作区 =====\n');
matPath = fullfile(outFolder, 'sgm_dual_path_results.mat');
save(matPath, ...
    'disparityMap', 'confidenceMap', 'validMap', ...
    'disp_LR', 'valid_LR', 'disp_TB', 'valid_TB', ...
    'disp_TLBR', 'valid_TLBR', 'disp_TRBL', 'valid_TRBL', ...
    'disp_merged', 'valid_merged', 'disagreement', ...
    'P1_THRESH', 'MERGE_THRESH', 'USE_MEDIAN', 'CONFIDENCE_THRE', ...
    'holeCount', 'holeAfterLR', 'holeAfterTB', 'holeAfterTLBR', 'holeAfterTRBL', ...
    'costVol', 'MAX_DISP', 'IMG_WIDTH', 'IMG_HEIGHT', ...
    '-v7.3');
fprintf('  保存到: %s\n', matPath);

%% ===================== 12. 打印总结 =====================
fprintf('\n==============================================\n');
fprintf('  方案C升级: 4方向DP空洞填充 - 处理完成\n');
fprintf('==============================================\n');
fprintf('  参数:\n');
fprintf('    CONFIDENCE_THRE = %d\n', CONFIDENCE_THRE);
fprintf('    P1_THRESH       = %d\n', P1_THRESH);
fprintf('    MERGE_THRESH    = %d\n', MERGE_THRESH);
fprintf('    USE_MEDIAN      = %d (4方向中值)\n', USE_MEDIAN);
fprintf('\n  空洞统计:\n');
fprintf('    原始 WTA:       %5d / %d (%.1f%%)\n', holeCount, totalPix, 100*holeCount/totalPix);
fprintf('    左→右 (L→R):    %5d (填了 %d)\n', holeAfterLR, holeCount - holeAfterLR);
fprintf('    上→下 (T→B):    %5d (填了 %d)\n', holeAfterTB, holeCount - holeAfterTB);
fprintf('    左上→右下(TL→BR):%5d (填了 %d)\n', holeAfterTLBR, holeCount - holeAfterTLBR);
fprintf('    右上→左下(TR→BL):%5d (填了 %d)\n', holeAfterTRBL, holeCount - holeAfterTRBL);
fprintf('    4方向合并:      %5d (全部填充)\n', sum(~valid_merged(:)));
fprintf('\n  空洞处4方向分歧度: avg=%.1f, max=%d\n', ...
    mean(double(disagreement(disagreement > 0))), max(disagreement(:)));
fprintf('\n  FPGA等价资源:\n');
fprintf('    左→右:     1个 8bit 寄存器\n');
fprintf('    上→下:     640×8bit 单口RAM (~5kb)\n');
fprintf('    左上→右下:  640×8bit ×2 (ping-pong, ~10kb)\n');
fprintf('    右上→左下:  640×8bit ×2 (ping-pong, ~10kb)\n');
fprintf('    4方向合并:  4→1 排序网络, ~3级 LUT\n');
fprintf('    总吞吐量:   1 px/cycle, 无反馈环\n');
fprintf('==============================================\n');
