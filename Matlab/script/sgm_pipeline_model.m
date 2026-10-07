%% SGM 流水线延迟模型 — 精确模拟 RTL sgm_new.v 的 12 级流水线反馈延迟
%  与 sgm_dual_path_enhanced.m 的区别：
%     - Lr_prev 不再逐像素立即更新，而是通过 12 级 shift register 模拟流水线延迟
%     - Min tree 读取 Lr_prev_queue[1]  ← 像素 N-12 的 Lr_curr
%     - R0~R3   读取 Lr_prev_queue[7]  ← 像素 N-6  的 Lr_curr
%     - 输出与 verify_sgm_pipeline.m 兼容的二进制比对文件
%
%  参考 RTL: sgm_new.v 中 Lr0_min_compare_tree / lr0_curr2prev 模块
%  流水线深度: 12 级 (dly[6]~dly[17])

clc;
clear;
close all;

%% ===================== 算法参数（与 sgm_new.v 一致） =====================
IMG_WIDTH       = 640;
IMG_HEIGHT      = 480;
MAX_DISP        = 48;
CENSUS_BITS     = 24;
BYTES_PER_PIXEL = 3;

P1 = 15;
P2 = 100;
SGM_LR_WIDTH    = 12;
K_LR_MAX        = 2^SGM_LR_WIDTH - 1;
INVALID_COST    = CENSUS_BITS;

PIPELINE_DELAY  = 12;   % Lr_prev 反馈路径总延迟 (dly[6]→dly[17] = 12 级)
MIN_TREE_IDX    = 1;     % min tree 在 Lr_prev 队列中的位置 (dly[6]: pixel N-12)
R_IDX           = 7;     % R0~R3 在 Lr_prev 队列中的位置  (dly[12]: pixel N-6)

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

outFolder = uigetdir('', '请选择输出文件夹（流水线模型结果）');
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

%% ===================== 4. Hamming 代价体（同 sgm_dual_path_enhanced.m） =====================
fprintf('===== Hamming 距离计算 (Stage 0-4) =====\n');
costVol = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_DISP, 'uint8');
popLUT = uint8(sum(dec2bin(0:255) == '1', 2));

hwb = waitbar(0, 'Hamming 代价体...');
for d_val = 0:MAX_DISP-1
    if d_val == 0
        xr = 1:IMG_WIDTH;
        xl = 1:IMG_WIDTH;
    else
        xr = (d_val+1):IMG_WIDTH;
        xl = 1:(IMG_WIDTH-d_val);
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
fprintf('Stage 4 完成: costVol = HxWx%d (uint8)\n', MAX_DISP);

%% ===================== 5. Lr0 左→右聚合（带 12 级流水线延迟） =====================
%   RTL 流水线映射：
%     dly[6]  : min tree 读取 Lr_prev_queue[1]  ← 像素 N-12 的 Lr_curr
%     dly[11] : min tree 输出 Lr_min
%     dly[12] : R0~R3 读取 Lr_prev_queue[7]    ← 像素 N-6 的 Lr_curr
%               + 读取 Lr0_min (与 Lr0_min_en 同步)
%     dly[13] : min4 第 1 级
%     dly[14] : min4 第 2 级 → min4 输出
%     dly[15] : Lr_curr_temp = min4 + cost
%     dly[16] : Lr_curr 锁存
%     dly[17] : Lr_curr → Lr_prev (写入队列尾部)
fprintf('===== Lr0 左→右聚合（流水线延迟模型） =====\n');
fprintf('  PIPELINE_DELAY = %d\n', PIPELINE_DELAY);
fprintf('  Min tree reads Lr_prev_queue[%d] (pixel N-%d)\n', MIN_TREE_IDX, PIPELINE_DELAY);
fprintf('  R0~R3    reads Lr_prev_queue[%d] (pixel N-%d)\n', R_IDX, PIPELINE_DELAY - R_IDX + 1);

Lr_LR_pipeline = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_DISP, 'uint16');

hwb = waitbar(0, 'Lr0 流水线聚合...');
for y = 1:IMG_HEIGHT
    % 初始化 12 级延迟队列（全部为 K_LR_MAX，对应 RTL 复位值）
    Lr_prev_queue = repmat(uint16(K_LR_MAX), PIPELINE_DELAY, MAX_DISP);
    Lr0_min_en = false;

    for x = 1:IMG_WIDTH
        cost_d = uint16(squeeze(costVol(y, x, :))');

        %==========================================================
        % [dly[6]]  Min tree 读取 Lr_prev_queue[MIN_TREE_IDX]
        %==========================================================
        Lr_prev_for_min = Lr_prev_queue(MIN_TREE_IDX, :);
        % [dly[11]] Lr_min = min(Lr_prev_for_min)  (6 级比较树结果)
        Lr_min_min = min(Lr_prev_for_min);

        %==========================================================
        % [dly[12]] R0~R3 读取 Lr_prev_queue[R_IDX] 和 Lr0_min
        %==========================================================
        Lr_prev_for_R = Lr_prev_queue(R_IDX, :);
        if Lr0_min_en
            Lr_min_R = Lr_min_min;
        else
            Lr_min_R = 0;
        end

        % 计算 R0~R3
        R0 = uint16(zeros(1, MAX_DISP));
        R1 = uint16(zeros(1, MAX_DISP));
        R2 = uint16(zeros(1, MAX_DISP));

        for d_idx = 1:MAX_DISP
            d = d_idx - 1;
            if ~Lr0_min_en
                R0(d_idx) = K_LR_MAX;
                R1(d_idx) = K_LR_MAX;
                R2(d_idx) = K_LR_MAX;
            else
                val0 = Lr_prev_for_R(d_idx);
                if val0 >= Lr_min_R
                    R0(d_idx) = val0 - Lr_min_R;
                else
                    R0(d_idx) = 0;
                end

                if d == 0
                    R1(d_idx) = K_LR_MAX;
                else
                    val1 = uint16(P1) + Lr_prev_for_R(d_idx-1);
                    if val1 >= Lr_min_R
                        R1(d_idx) = val1 - Lr_min_R;
                    else
                        R1(d_idx) = 0;
                    end
                end

                if d == MAX_DISP - 1
                    R2(d_idx) = K_LR_MAX;
                else
                    val2 = uint16(P1) + Lr_prev_for_R(d_idx+1);
                    if val2 >= Lr_min_R
                        R2(d_idx) = val2 - Lr_min_R;
                    else
                        R2(d_idx) = 0;
                    end
                end
            end
        end
        R3 = uint16(P2);

        % [dly[12] 结束时] Lr0_min_en 在第一个像素的 dly[11]→dly[12] 上升沿置 1
        % 对应 RTL: per_cmr2_href_dly[12] && !per_cmr2_href_dly[13] 时置 1
        %          即第 1 个像素结束后置 1，第 2 个像素开始 Lr0_min_en = true
        if x == 1
            Lr0_min_en = true;
        end

        %==========================================================
        % [dly[13]] min4 第 1 级
        %==========================================================
        min4_t0 = min(R0, R1);
        min4_t1 = min(R2, repmat(R3, 1, MAX_DISP));

        %==========================================================
        % [dly[14]] min4 第 2 级 → min4 输出
        %==========================================================
        min4 = min(min4_t0, min4_t1);

        %==========================================================
        % [dly[15]] Lr_curr_temp = min4 + cost
        %==========================================================
        Lr_curr_temp = min4 + cost_d;

        %==========================================================
        % [dly[16]] Lr_curr 锁存（12-bit 截断）
        %==========================================================
        Lr_curr = uint16(bitand(uint32(Lr_curr_temp), uint32(K_LR_MAX)));
        Lr_LR_pipeline(y, x, :) = Lr_curr;

        %==========================================================
        % [dly[17]] Lr_curr → Lr_prev 队列移位更新
        %   队列行为：移除最旧元素，新 Lr_curr 推入队尾
        %   RTL: Lr0_prev[d_cnt] <= Lr0_curr[d_cnt]  (per_cmr2_href_dly[17])
        %==========================================================
        Lr_prev_queue = [Lr_prev_queue(2:end, :); Lr_curr];
    end
    waitbar(y/IMG_HEIGHT, hwb, sprintf('Lr0_pipe row %d/%d', y, IMG_HEIGHT));
end
close(hwb);
fprintf('流水线 Lr0 聚合完成: Lr_LR_pipeline = HxWx%d\n', MAX_DISP);

%% ===================== 6. Lr2 上→下聚合（带流水线延迟，同 Lr0 结构） =====================
fprintf('===== Lr2 上→下聚合（流水线延迟模型） =====\n');

Lr_UD_pipeline = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_DISP, 'uint16');

hwb = waitbar(0, 'Lr2 流水线聚合...');
for x = 1:IMG_WIDTH
    Lr_prev_queue = repmat(uint16(K_LR_MAX), PIPELINE_DELAY, MAX_DISP);

    for y = 1:IMG_HEIGHT
        cost_d = uint16(squeeze(costVol(y, x, :))');

        Lr_prev_for_min = Lr_prev_queue(MIN_TREE_IDX, :);
        Lr_min = min(Lr_prev_for_min);

        Lr_prev_for_R = Lr_prev_queue(R_IDX, :);

        R0 = uint16(zeros(1, MAX_DISP));
        R1 = uint16(zeros(1, MAX_DISP));
        R2 = uint16(zeros(1, MAX_DISP));

        for d_idx = 1:MAX_DISP
            d = d_idx - 1;
            val0 = Lr_prev_for_R(d_idx);
            if val0 >= Lr_min
                R0(d_idx) = val0 - Lr_min;
            else
                R0(d_idx) = 0;
            end

            if d == 0
                R1(d_idx) = K_LR_MAX;
            else
                val1 = uint16(P1) + Lr_prev_for_R(d_idx-1);
                if val1 >= Lr_min
                    R1(d_idx) = val1 - Lr_min;
                else
                    R1(d_idx) = 0;
                end
            end

            if d == MAX_DISP - 1
                R2(d_idx) = K_LR_MAX;
            else
                val2 = uint16(P1) + Lr_prev_for_R(d_idx+1);
                if val2 >= Lr_min
                    R2(d_idx) = val2 - Lr_min;
                else
                    R2(d_idx) = 0;
                end
            end
        end
        R3 = uint16(P2);

        min4 = min(min(min(R0, R1), min(R2, repmat(R3, 1, MAX_DISP))));
        Lr_curr_temp = min4 + cost_d;
        Lr_curr = uint16(bitand(uint32(Lr_curr_temp), uint32(K_LR_MAX)));
        Lr_UD_pipeline(y, x, :) = Lr_curr;

        Lr_prev_queue = [Lr_prev_queue(2:end, :); Lr_curr];
    end
    waitbar(x/IMG_WIDTH, hwb, sprintf('Lr2_pipe col %d/%d', x, IMG_WIDTH));
end
close(hwb);
fprintf('流水线 Lr2 聚合完成\n');

%% ===================== 7. 理想无延迟模型（供对比参考） =====================
fprintf('===== 理想无延迟模型（对比参考） =====\n');

Lr_LR_ideal = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_DISP, 'uint16');

hwb = waitbar(0, '理想 Lr0...');
for y = 1:IMG_HEIGHT
    Lr_prev = repmat(uint16(K_LR_MAX), 1, MAX_DISP);
    for x = 1:IMG_WIDTH
        cost_d = uint16(squeeze(costVol(y, x, :))');
        Lr_min = min(Lr_prev);

        R0 = uint16(zeros(1, MAX_DISP));
        R1 = uint16(zeros(1, MAX_DISP));
        R2 = uint16(zeros(1, MAX_DISP));

        for d_idx = 1:MAX_DISP
            d = d_idx - 1;
            if x == 1
                R0(d_idx) = K_LR_MAX;
                R1(d_idx) = K_LR_MAX;
                R2(d_idx) = K_LR_MAX;
            else
                val0 = Lr_prev(d_idx);
                if val0 >= Lr_min
                    R0(d_idx) = val0 - Lr_min;
                else
                    R0(d_idx) = 0;
                end
                if d == 0
                    R1(d_idx) = K_LR_MAX;
                else
                    val1 = uint16(P1) + Lr_prev(d_idx-1);
                    if val1 >= Lr_min
                        R1(d_idx) = val1 - Lr_min;
                    else
                        R1(d_idx) = 0;
                    end
                end
                if d == MAX_DISP - 1
                    R2(d_idx) = K_LR_MAX;
                else
                    val2 = uint16(P1) + Lr_prev(d_idx+1);
                    if val2 >= Lr_min
                        R2(d_idx) = val2 - Lr_min;
                    else
                        R2(d_idx) = 0;
                    end
                end
            end
        end
        R3 = uint16(P2);
        min4 = min(min(min(R0, R1), min(R2, repmat(R3, 1, MAX_DISP))));
        Lr_curr_temp = min4 + cost_d;
        Lr_curr = uint16(bitand(uint32(Lr_curr_temp), uint32(K_LR_MAX)));
        Lr_LR_ideal(y, x, :) = Lr_curr;
        Lr_prev = Lr_curr;
    end
    waitbar(y/IMG_HEIGHT, hwb, sprintf('理想Lr0 row %d/%d', y, IMG_HEIGHT));
end
close(hwb);

%% ===================== 8. 代价合并与 WTA =====================
fprintf('===== 代价合并与 WTA =====\n');

% 流水线模型：单路径（仅 Lr0，匹配当前 RTL 输出）
combined_pipeline_single = Lr_LR_pipeline;

% 流水线模型：双路径（Lr0 + Lr2）
combined_pipeline_dual = uint16(min(Lr_LR_pipeline + Lr_UD_pipeline, K_LR_MAX));

% 理想模型：单路径
combined_ideal_single = Lr_LR_ideal;

% WTA
disp_pipeline_single = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');
disp_pipeline_dual   = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');
disp_ideal_single    = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');
disp_noagg           = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');

for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        [~, min_idx] = min(squeeze(costVol(y, x, :)));
        disp_noagg(y, x) = uint8(min_idx - 1);

        [~, min_idx] = min(squeeze(combined_pipeline_single(y, x, :)));
        disp_pipeline_single(y, x) = uint8(min_idx - 1);

        [~, min_idx] = min(squeeze(combined_pipeline_dual(y, x, :)));
        disp_pipeline_dual(y, x) = uint8(min_idx - 1);

        [~, min_idx] = min(squeeze(combined_ideal_single(y, x, :)));
        disp_ideal_single(y, x) = uint8(min_idx - 1);
    end
end

%% ===================== 9. 定量分析：流水线模型 vs 理想模型 =====================
fprintf('\n========== 定量差异分析 ==========\n');

diff_Lr0 = abs(int32(Lr_LR_ideal) - int32(Lr_LR_pipeline));
fprintf('Lr0 (单路径) 差异统计:\n');
fprintf('  最大差异: %d\n', max(diff_Lr0, [], 'all'));
fprintf('  平均差异: %.4f\n', mean(diff_Lr0, 'all'));
fprintf('  RMS差异:  %.4f\n', sqrt(mean(diff_Lr0(:).^2)));

diff_disp = int16(disp_ideal_single) - int16(disp_pipeline_single);
fprintf('\nDisparity (单路径) 差异统计:\n');
fprintf('  最大视差偏移: %d\n', max(abs(diff_disp), [], 'all'));
fprintf('  平均视差偏移: %.4f\n', mean(abs(diff_disp), 'all'));
fprintf('  差异 > 1 的像素占比: %.2f%%\n', sum(abs(diff_disp(:)) > 1) / numel(diff_disp) * 100);
fprintf('  完全一致的像素占比: %.2f%%\n', sum(diff_disp(:) == 0) / numel(diff_disp) * 100);
fprintf('  差异 > 8 的像素占比: %.2f%%\n', sum(abs(diff_disp(:)) > 8) / numel(diff_disp) * 100);

%% ===================== 10. 可视化 =====================
fprintf('\n===== 生成可视化报告 =====\n');

noAgg  = uint8(255 * mat2gray(disp_noagg,           [0, MAX_DISP-1]));
ideal  = uint8(255 * mat2gray(disp_ideal_single,    [0, MAX_DISP-1]));
pipe   = uint8(255 * mat2gray(disp_pipeline_single, [0, MAX_DISP-1]));
pipeD  = uint8(255 * mat2gray(disp_pipeline_dual,   [0, MAX_DISP-1]));

figure('Name','SGM 流水线延迟模型 vs 理想模型','Color','w','Position',[50,50,1400,700]);

subplot(2,4,1); imshow(noAgg);  title('无聚合 WTA (costVol)');
subplot(2,4,2); imshow(ideal);  title('理想模型 (无延迟)');
subplot(2,4,3); imshow(pipe);   title(sprintf('流水线模型 (延迟=%d)', PIPELINE_DELAY));
subplot(2,4,4); imshow(pipeD);  title('流水线+双路径');

% 差异图
diffMap = abs(double(disp_ideal_single) - double(disp_pipeline_single));
subplot(2,4,5); imshow(diffMap, []); colormap(subplot(2,4,5), 'jet');
title('视差差异图 |ideal - pipeline|'); colorbar;

% 差异直方图
subplot(2,4,6); histogram(diff_disp(:), -10:10, 'Normalization', 'probability');
title('视差偏移直方图'); xlabel('偏移 (pixels)'); ylabel('概率');
grid on;

% Lr0 差异热图（取第 1 行示例）
subplot(2,4,7);
lr0_row_diff = squeeze(mean(diff_Lr0(100, :, :), 3));
plot(lr0_row_diff); title('Lr0 平均差异 — 第 100 行');
xlabel('x (列)'); ylabel('平均 Lr 差异'); grid on;

% 首行差异分布
subplot(2,4,8);
firstRowDiff = squeeze(mean(diff_Lr0(1, :, :), 3));
plot(firstRowDiff); title('Lr0 平均差异 — 第 1 行（含预热期）');
xlabel('x (列)'); ylabel('平均 Lr 差异'); grid on;

%% ===================== 11. 导出二进制数据（与 verify_sgm_pipeline.m 兼容） =====================
fprintf('\n===== 导出 FPGA 逐级比对数据 =====\n');

% [A] Stage 4: hamming_dist (uint8)
fname = fullfile(outFolder, 'sgm_mat_task_6.dat');
fid = fopen(fname, 'wb');
fwrite(fid, [bitshift(uint16(IMG_WIDTH),-8), bitand(uint16(IMG_WIDTH),255), ...
             bitshift(uint16(IMG_HEIGHT),-8), bitand(uint16(IMG_HEIGHT),255), ...
             uint8(4)], 'uint8');
for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        fwrite(fid, reshape(costVol(y, x, :), 1, []), 'uint8');
    end
end
fclose(fid);
fprintf('  [Stage 4]  sgm_mat_task_6.dat  (hamming_dist, uint8)\n');

% [B] Stage 10: Lr0_curr (pipeline model, uint16 LE)
fname = fullfile(outFolder, 'sgm_mat_task_7.dat');
fid = fopen(fname, 'wb');
fwrite(fid, [bitshift(uint16(IMG_WIDTH),-8), bitand(uint16(IMG_WIDTH),255), ...
             bitshift(uint16(IMG_HEIGHT),-8), bitand(uint16(IMG_HEIGHT),255), ...
             uint8(16)], 'uint8');
for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        fwrite(fid, reshape(Lr_LR_pipeline(y, x, :), 1, []), 'uint16');
    end
end
fclose(fid);
fprintf('  [Stage 10] sgm_mat_task_7.dat  (Lr0_curr, 流水线模型, uint16 LE)\n');

% [C] Stage 11: combined_lr (pipeline model, 单路径=仅Lr0, uint16 LE)
fname = fullfile(outFolder, 'sgm_mat_task_8.dat');
fid = fopen(fname, 'wb');
fwrite(fid, [bitshift(uint16(IMG_WIDTH),-8), bitand(uint16(IMG_WIDTH),255), ...
             bitshift(uint16(IMG_HEIGHT),-8), bitand(uint16(IMG_HEIGHT),255), ...
             uint8(17)], 'uint8');
for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        fwrite(fid, reshape(combined_pipeline_single(y, x, :), 1, []), 'uint16');
    end
end
fclose(fid);
fprintf('  [Stage 11] sgm_mat_task_8.dat  (combined_lr, 流水线模型, 单路径, uint16 LE)\n');

% [D] Stage 17: disparity (pipeline model, uint8)
fname = fullfile(outFolder, 'sgm_mat_task_5.dat');
fid = fopen(fname, 'wb');
fwrite(fid, [bitshift(uint16(IMG_WIDTH),-8), bitand(uint16(IMG_WIDTH),255), ...
             bitshift(uint16(IMG_HEIGHT),-8), bitand(uint16(IMG_HEIGHT),255), ...
             uint8(5)], 'uint8');
for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        fwrite(fid, disp_pipeline_single(y, x), 'uint8');
    end
end
fclose(fid);
fprintf('  [Stage 17] sgm_mat_task_5.dat  (disparity, 流水线模型, uint8)\n');

%% ===================== 12. 保存工作区 =====================
fprintf('\n===== 保存工作区 =====\n');
matPath = fullfile(outFolder, 'sgm_pipeline_results.mat');
save(matPath, ...
    'costVol', ...
    'Lr_LR_pipeline', 'Lr_UD_pipeline', ...
    'Lr_LR_ideal', ...
    'combined_pipeline_single', 'combined_pipeline_dual', 'combined_ideal_single', ...
    'disp_noagg', 'disp_ideal_single', 'disp_pipeline_single', 'disp_pipeline_dual', ...
    'diff_Lr0', 'diff_disp', ...
    'P1', 'P2', 'MAX_DISP', 'SGM_LR_WIDTH', 'K_LR_MAX', 'PIPELINE_DELAY', ...
    '-v7.3');
fprintf('  保存到: %s\n', matPath);

%% ===================== 13. 输出总结 =====================
fprintf('\n========================================\n');
fprintf('  SGM 流水线延迟模型 - 处理完成\n');
fprintf('========================================\n');
fprintf('  流水线参数:\n');
fprintf('    PIPELINE_DELAY = %d\n', PIPELINE_DELAY);
fprintf('    Min tree 使用 Lr_prev_queue[%d] (pixel N-%d)\n', MIN_TREE_IDX, PIPELINE_DELAY);
fprintf('    R0~R3   使用 Lr_prev_queue[%d] (pixel N-%d)\n', R_IDX, PIPELINE_DELAY - R_IDX + 1);
fprintf('\n  差异统计 (流水线 vs 理想):\n');
fprintf('    Lr0 最大差异:   %d\n', max(diff_Lr0, [], 'all'));
fprintf('    Lr0 平均差异:   %.4f\n', mean(diff_Lr0, 'all'));
fprintf('    视差完全一致率: %.2f%%\n', sum(diff_disp(:) == 0) / numel(diff_disp) * 100);
fprintf('    视差 >1px 偏差: %.2f%%\n', sum(abs(diff_disp(:)) > 1) / numel(diff_disp) * 100);
fprintf('\n  输出文件:\n');
fprintf('    [比对用] sgm_mat_task_5~8.dat (与 verify_sgm_pipeline.m 兼容)\n');
fprintf('    [分析用] sgm_pipeline_results.mat\n');
fprintf('========================================\n');
