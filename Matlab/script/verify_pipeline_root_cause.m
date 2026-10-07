%% SGM 流水线根因验证脚本 — Pipeline Model vs RTL vs Ideal Model
%  功能：三路对比，验证 Lr_prev 流水线反馈延迟是否 FPGA 与 MATLAB 差异的根因
%
%  核心逻辑：
%    如果流水线延迟是根因，则以下结论应成立：
%      ✅ Stage 4 (hamming_dist):  三路全部一致（流水线尚未介入）
%      ✅ Stage 10 (Lr0_curr):     Pipeline ≈ RTL，Ideal ≠ RTL
%      ✅ Stage 11 (combined_lr):  Pipeline ≈ RTL，Ideal ≠ RTL
%      ✅ Stage 17 (disparity):    Pipeline ≈ RTL，Ideal ≠ RTL
%
%  数据来源：
%    1. RTL ModelSim 仿真输出：tb_sgm_new_task_5~8.dat
%    2. Pipeline 模型输出：    sgm_mat_task_5~8.dat (来自 sgm_pipeline_model.m)
%    3. Ideal 模型输出：        sgm_mat_task_5~8.dat (来自 sgm_dual_path_enhanced.m)

clc;
clear;
close all;

%% ===================== 参数 =====================
IMG_WIDTH       = 640;
IMG_HEIGHT      = 480;
MAX_DISP        = 48;
TOTAL_PIXELS    = IMG_HEIGHT * IMG_WIDTH * MAX_DISP;

% testbench 捕获时序偏移量（根因）
%   Task 7 (Lr0_curr):  dly[10] 捕获 vs dly[16] 数据 → 6 像素偏移
%   Task 8 (combined_lr): dly[11] 捕获 vs dly[17] 数据 → 6 像素偏移
%   Task 6 (hamming_dist): dly[4] 捕获 vs dly[4] 数据  → 0 偏移 ✓
%   Task 5 (disparity):    dly[23] 捕获 vs dly[23] 数据 → 0 偏移 ✓
TB_CAPTURE_OFFSET = 6;

% 偏移校正后的有效宽度（RTL 前 OFFSET 个位置为无效复位值 4095）
VALID_WIDTH = IMG_WIDTH - TB_CAPTURE_OFFSET;  % 634
TOTAL_PIXELS_OFFSET = IMG_HEIGHT * VALID_WIDTH * MAX_DISP;

%% ===================== 选择三个数据源文件夹 =====================
rtlFolder = uigetdir('', '【1/3】请选择 RTL 输出文件夹（含 tb_sgm_new_task_5~8.dat）');
if isequal(rtlFolder, 0), disp('未选择 RTL 文件夹，程序结束。'); return; end

pipeFolder = uigetdir('', '【2/3】请选择 Pipeline 模型输出文件夹（含 sgm_mat_task_5~8.dat）');
if isequal(pipeFolder, 0), disp('未选择 Pipeline 文件夹，程序结束。'); return; end

idealFolder = uigetdir('', '【3/3】请选择 Ideal 模型输出文件夹（含 sgm_mat_task_5~8.dat）');
if isequal(idealFolder, 0), disp('未选择 Ideal 文件夹，程序结束。'); return; end

outFolder = uigetdir('', '请选择报告输出文件夹');
if isequal(outFolder, 0), disp('未选择输出文件夹，程序结束。'); return; end

fprintf('\n========================================\n');
fprintf('  数据源:\n');
fprintf('    RTL:      %s\n', rtlFolder);
fprintf('    Pipeline: %s\n', pipeFolder);
fprintf('    Ideal:    %s\n', idealFolder);
fprintf('========================================\n');

%% ===================== 数据加载 =====================
fprintf('\n===== 加载 Stage 4: hamming_dist (uint8) =====\n');
rtlHam4   = load_stage_data(rtlFolder,   'tb_sgm_new', 6, 'uint8=>uint8',  MAX_DISP, IMG_WIDTH, IMG_HEIGHT);
pipeHam4  = load_stage_data(pipeFolder,  'sgm_mat',    6, 'uint8=>uint8',  MAX_DISP, IMG_WIDTH, IMG_HEIGHT);
idealHam4 = load_stage_data(idealFolder, 'sgm_mat',    6, 'uint8=>uint8',  MAX_DISP, IMG_WIDTH, IMG_HEIGHT);

fprintf('\n===== 加载 Stage 10: Lr0_curr (uint16) =====\n');
rtlLr0    = load_stage_data(rtlFolder,   'tb_sgm_new', 7, 'uint16=>uint16', MAX_DISP, IMG_WIDTH, IMG_HEIGHT);
pipeLr0   = load_stage_data(pipeFolder,  'sgm_mat',    7, 'uint16=>uint16', MAX_DISP, IMG_WIDTH, IMG_HEIGHT);
idealLr0  = load_stage_data(idealFolder, 'sgm_mat',    7, 'uint16=>uint16', MAX_DISP, IMG_WIDTH, IMG_HEIGHT);

fprintf('\n===== 加载 Stage 11: combined_lr (uint16) =====\n');
rtlComb   = load_stage_data(rtlFolder,   'tb_sgm_new', 8, 'uint16=>uint16', MAX_DISP, IMG_WIDTH, IMG_HEIGHT);
pipeComb  = load_stage_data(pipeFolder,  'sgm_mat',    8, 'uint16=>uint16', MAX_DISP, IMG_WIDTH, IMG_HEIGHT);
idealComb = load_stage_data(idealFolder, 'sgm_mat',    8, 'uint16=>uint16', MAX_DISP, IMG_WIDTH, IMG_HEIGHT);

fprintf('\n===== 加载 Stage 17: disparity (uint8) =====\n');
rtlDisp   = load_stage_data(rtlFolder,   'tb_sgm_new', 5, 'uint8=>uint8',  1, IMG_WIDTH, IMG_HEIGHT);
pipeDisp  = load_stage_data(pipeFolder,  'sgm_mat',    5, 'uint8=>uint8',  1, IMG_WIDTH, IMG_HEIGHT);
idealDisp = load_stage_data(idealFolder, 'sgm_mat',    5, 'uint8=>uint8',  1, IMG_WIDTH, IMG_HEIGHT);

%% ===================== Stage 4: hamming_dist 比对 =====================
fprintf('\n========== Stage 4: hamming_dist ==========\n');
fprintf('  [预期] 三路完全一致（流水线尚未介入，差异=0）\n');

d4_rtl_pipe  = abs(int16(rtlHam4)  - int16(pipeHam4));
d4_rtl_ideal = abs(int16(rtlHam4)  - int16(idealHam4));

r4_rtl_pipe  = 100 * (1 - sum(d4_rtl_pipe(:)  > 0) / TOTAL_PIXELS);
r4_rtl_ideal = 100 * (1 - sum(d4_rtl_ideal(:) > 0) / TOTAL_PIXELS);

fprintf('  RTL vs Pipeline:  匹配率 = %6.2f%%,  最大差异 = %d\n', r4_rtl_pipe,  max(d4_rtl_pipe(:)));
fprintf('  RTL vs Ideal:     匹配率 = %6.2f%%,  最大差异 = %d\n', r4_rtl_ideal, max(d4_rtl_ideal(:)));

%% ===================== Stage 10: Lr0_curr 比对 =====================
fprintf('\n========== Stage 10: Lr0_curr ==========\n');
fprintf('  [注意] testbench 在 dly[10] 捕获 → Lr0_curr 在 dly[16] 更新\n');
fprintf('         造成 RTL 输出前 %d 个位置为无效复位值 4095\n', TB_CAPTURE_OFFSET);
fprintf('         比对范围: RTL(%d:%d) vs Pipeline(1:%d)\n', ...
    TB_CAPTURE_OFFSET+1, IMG_WIDTH, VALID_WIDTH);
fprintf('  [预期] Pipeline ≈ RTL,  Ideal ≠ RTL\n');

% 偏移校正：RTL 前 6 个位置含复位值，跳过；Pipeline/Ideal 截断尾部
rtlLr0_valid  = rtlLr0(:,  TB_CAPTURE_OFFSET+1:end, :);
pipeLr0_valid = pipeLr0(:, 1:VALID_WIDTH,            :);
idealLr0_valid = idealLr0(:, 1:VALID_WIDTH,          :);

d10_rtl_pipe  = abs(int32(rtlLr0_valid)  - int32(pipeLr0_valid));
d10_rtl_ideal = abs(int32(rtlLr0_valid)  - int32(idealLr0_valid));

r10_rtl_pipe  = 100 * (1 - sum(d10_rtl_pipe(:)  > 0) / TOTAL_PIXELS_OFFSET);
r10_rtl_ideal = 100 * (1 - sum(d10_rtl_ideal(:) > 0) / TOTAL_PIXELS_OFFSET);

% 检查 RTL 前 6 个位置是否确实为 4095（确认偏移假说）
rtl_head_garbage = rtlLr0(:, 1:TB_CAPTURE_OFFSET, :);
garbage_is_4095 = all(rtl_head_garbage(:) == 4095);
if garbage_is_4095
    fprintf('  ✅ 确认: RTL 前 %d 个位置全部 = 4095 (复位值)\n', TB_CAPTURE_OFFSET);
else
    bad_count = sum(rtl_head_garbage(:) ~= 4095);
    fprintf('  ⚠  注意: RTL 前 %d 个位置中有 %d 个 ≠ 4095\n', TB_CAPTURE_OFFSET, bad_count);
end

fprintf('  RTL vs Pipeline:  匹配率 = %6.2f%%,  最大差异 = %d,  平均差异 = %.4f\n', ...
    r10_rtl_pipe,  max(d10_rtl_pipe(:)),  mean(d10_rtl_pipe(:)));
fprintf('  RTL vs Ideal:     匹配率 = %6.2f%%,  最大差异 = %d,  平均差异 = %.4f\n', ...
    r10_rtl_ideal, max(d10_rtl_ideal(:)), mean(d10_rtl_ideal(:)));

%% ===================== Stage 11: combined_lr 比对 =====================
fprintf('\n========== Stage 11: combined_lr ==========\n');
fprintf('  [注意] 当前 RTL combined_lr = Lr0_curr (单路径)\n');
fprintf('  [注意] testbench 在 dly[11] 捕获 → combined_lr 在 dly[17] 更新\n');
fprintf('         同样存在 %d 像素偏移，同上偏移校正\n', TB_CAPTURE_OFFSET);
fprintf('  [预期] Pipeline ≈ RTL,  Ideal ≠ RTL\n');

% 偏移校正（同 Stage 10）
rtlComb_valid  = rtlComb(:,  TB_CAPTURE_OFFSET+1:end, :);
pipeComb_valid = pipeComb(:, 1:VALID_WIDTH,            :);
idealComb_valid = idealComb(:, 1:VALID_WIDTH,          :);

d11_rtl_pipe  = abs(int32(rtlComb_valid)  - int32(pipeComb_valid));
d11_rtl_ideal = abs(int32(rtlComb_valid)  - int32(idealComb_valid));

r11_rtl_pipe  = 100 * (1 - sum(d11_rtl_pipe(:)  > 0) / TOTAL_PIXELS_OFFSET);
r11_rtl_ideal = 100 * (1 - sum(d11_rtl_ideal(:) > 0) / TOTAL_PIXELS_OFFSET);

fprintf('  RTL vs Pipeline:  匹配率 = %6.2f%%,  最大差异 = %d,  平均差异 = %.4f\n', ...
    r11_rtl_pipe,  max(d11_rtl_pipe(:)),  mean(d11_rtl_pipe(:)));
fprintf('  RTL vs Ideal:     匹配率 = %6.2f%%,  最大差异 = %d,  平均差异 = %.4f\n', ...
    r11_rtl_ideal, max(d11_rtl_ideal(:)), mean(d11_rtl_ideal(:)));

%% ===================== Stage 17: Disparity 比对 =====================
fprintf('\n========== Stage 17: Disparity ==========\n');
fprintf('  [预期] Pipeline ≈ RTL,  Ideal ≠ RTL\n');

[r17_pipe_exact,  r17_pipe_w1,  r17_pipe_max]  = calc_disp_stat(rtlDisp, pipeDisp);
[r17_ideal_exact, r17_ideal_w1, r17_ideal_max] = calc_disp_stat(rtlDisp, idealDisp);

fprintf('  RTL vs Pipeline:  精确匹配 = %5.2f%%,  ±1容差 = %5.2f%%,  最大偏移 = %d\n', ...
    r17_pipe_exact, r17_pipe_w1, r17_pipe_max);
fprintf('  RTL vs Ideal:     精确匹配 = %5.2f%%,  ±1容差 = %5.2f%%,  最大偏移 = %d\n', ...
    r17_ideal_exact, r17_ideal_w1, r17_ideal_max);

%% ===================== 结论判定 =====================
fprintf('\n========================================\n');
fprintf('  根因分析结论\n');
fprintf('========================================\n');

stage4_ok    = (r4_rtl_pipe == 100) && (r4_rtl_ideal == 100);
stage10_pipe_ok  = (r10_rtl_pipe > 99);
stage10_ideal_ng = (r10_rtl_ideal < 99);

if stage4_ok
    fprintf('  ✅ Stage 4:  三路全部一致 → Hamming 距离计算正确\n');
else
    fprintf('  ⚠  Stage 4:  存在差异 → 需排查 Census/Hamming 部分\n');
end

if stage10_pipe_ok
    fprintf('  ✅ Stage 10: Pipeline ≈ RTL  → 流水线模型正确描述了 RTL 行为\n');
else
    fprintf('  ⚠  Stage 10: Pipeline ≠ RTL  → 流水线模型有偏差，需调整\n');
end

if stage10_ideal_ng
    fprintf('  ✅ Stage 10: Ideal ≠ RTL     → 理想模型缺少流水线延迟，确认为差异根因\n');
else
    fprintf('  ⚠  Stage 10: Ideal ≈ RTL     → 延迟不是根因，需另寻原因\n');
end

if stage10_pipe_ok && stage10_ideal_ng
    fprintf('\n  ★★★★★ 结论验证通过 ★★★★★\n');
    fprintf('  Lr_prev 流水线反馈延迟 (差异 #1) 确认为 FPGA 与 MATLAB 差异的根因。\n');
    fprintf('  建议: 参考项目内时序方案，实施流水线重排或相位补偿。\n');
else
    fprintf('\n  ⚠ 结论不明确，需进一步分析数据。\n');
end

%% ===================== 可视化 =====================
fprintf('\n===== 生成可视化报告 =====\n');

% ---- 图1: 三路匹配率一览 ----
fig1 = figure('Name', 'SGM 根因分析 — 三路匹配率', 'Color', 'w', 'Position', [50, 50, 1000, 600]);

stages_label = {'Stage4\nhamm\_dist', 'Stage10\nLr0\_curr', 'Stage11\ncombined\_lr', 'Stage17\ndisparity\n(±1容差)'};
rtl_vs_pipe  = [r4_rtl_pipe,  r10_rtl_pipe,  r11_rtl_pipe,  r17_pipe_w1];
rtl_vs_ideal = [r4_rtl_ideal, r10_rtl_ideal, r11_rtl_ideal, r17_ideal_w1];

subplot(2,2,1);
bar_data = [rtl_vs_pipe; rtl_vs_ideal]';
bh = bar(bar_data, 0.7);
bh(1).FaceColor = [0.2 0.6 0.2]; bh(2).FaceColor = [0.8 0.3 0.3];
set(gca, 'XTickLabel', stages_label, 'XTick', 1:4);
ylabel('匹配率 (%)'); ylim([80 100.5]); grid on;
legend('RTL vs Pipeline', 'RTL vs Ideal', 'Location', 'southeast');
title('三路逐级匹配率对比');
for i = 1:4
    text(i-0.15, bar_data(i,1)+0.5, sprintf('%.1f%%', bar_data(i,1)), ...
        'FontSize', 9, 'Color', [0 0.4 0]);
    text(i+0.15, bar_data(i,2)+0.5, sprintf('%.1f%%', bar_data(i,2)), ...
        'FontSize', 9, 'Color', [0.6 0 0]);
end

subplot(2,2,2);
row_sel = min(100, IMG_HEIGHT);
% 使用偏移校正后的数据（RTL 跳过前 6 个无效位置）
pipe_row = squeeze(pipeLr0(row_sel, 1:VALID_WIDTH, 1));
ideal_row = squeeze(idealLr0(row_sel, 1:VALID_WIDTH, 1));
rtl_row  = squeeze(rtlLr0(row_sel, TB_CAPTURE_OFFSET+1:end, 1));
x_valid  = 1:VALID_WIDTH;
plot(x_valid, double(pipe_row), 'g-', 'LineWidth', 1, 'DisplayName', 'Pipeline');
hold on;
plot(x_valid, double(ideal_row), 'r--', 'LineWidth', 1, 'DisplayName', 'Ideal');
plot(x_valid, double(rtl_row),  'b.', 'MarkerSize', 3, 'DisplayName', 'RTL');
hold off;
xlabel('有效像素索引 (0~633)'); ylabel('Lr0\_curr (d=0)');
title(sprintf('Lr0 第 %d 行 d=0 三路对比 (偏移校正后)', row_sel));
legend('Location', 'best'); grid on;

subplot(2,2,3);
diffDispMap = abs(double(idealDisp) - double(rtlDisp));
imagesc(diffDispMap); colormap(gca, 'jet'); colorbar;
title(sprintf('|Ideal - RTL| disparity, max=%d', max(diffDispMap(:))));
xlabel('x (列)'); ylabel('y (行)');
axis equal tight;

subplot(2,2,4);
diffDisp_ideal_rtl = int16(idealDisp) - int16(rtlDisp);
diffDisp_pipe_rtl  = int16(pipeDisp)  - int16(rtlDisp);
edges = -10:10;
histogram(diffDisp_ideal_rtl(:), edges, 'FaceColor', [0.8 0.3 0.3], ...
    'FaceAlpha', 0.6, 'Normalization', 'probability', 'DisplayName', 'Ideal - RTL');
hold on;
histogram(diffDisp_pipe_rtl(:),  edges, 'FaceColor', [0.2 0.6 0.2], ...
    'FaceAlpha', 0.6, 'Normalization', 'probability', 'DisplayName', 'Pipeline - RTL');
hold off;
xlabel('视差偏移 (像素)'); ylabel('概率'); grid on;
legend('Location', 'best');
title('Disparity 偏移分布对比');

sgtitle('SGM 流水线延迟根因验证', 'FontSize', 14);

% ---- 图2: 行方向延迟模式分析 ----
fig2 = figure('Name', '流水线延迟模式分析', 'Color', 'w', 'Position', [100, 100, 1200, 500]);

row_analyze = min(50, IMG_HEIGHT);
% 偏移校正：Ideal/RTL vs Pipeline 仅在校正后的有效范围内比对
lr0_diff_ideal_vs_pipe = squeeze(mean(abs(int32(idealLr0(row_analyze,1:VALID_WIDTH,:)) - ...
    int32(pipeLr0(row_analyze,1:VALID_WIDTH,:))), 3));
lr0_diff_rtl_vs_pipe   = squeeze(mean(abs(int32(rtlLr0(row_analyze,TB_CAPTURE_OFFSET+1:end,:)) - ...
    int32(pipeLr0(row_analyze,1:VALID_WIDTH,:))), 3));

subplot(1,3,1);
plot(1:VALID_WIDTH, lr0_diff_ideal_vs_pipe, 'r-', 'LineWidth', 1); hold on;
plot(1:VALID_WIDTH, lr0_diff_rtl_vs_pipe,   'g-', 'LineWidth', 1); hold off;
xlabel('有效像素索引 (偏移校正后)'); ylabel('平均 Lr0 差异'); grid on;
title(sprintf('第 %d 行 Lr0 差异沿行分布', row_analyze));
legend('Ideal vs Pipeline', 'RTL vs Pipeline', 'Location', 'northeast');
xline(12, '--k', '预热期', 'LabelOrientation', 'horizontal');

subplot(1,3,2);
x_range = 1:min(50, VALID_WIDTH);
plot(x_range, lr0_diff_ideal_vs_pipe(x_range), 'r-o', 'MarkerSize', 4); hold on;
plot(x_range, lr0_diff_rtl_vs_pipe(x_range),   'g-s', 'MarkerSize', 4); hold off;
xlabel('有效像素索引 (偏移校正后)'); ylabel('平均 Lr0 差异'); grid on;
title('前 50 列放大（预热期可见）');
legend('Ideal vs Pipeline', 'RTL vs Pipeline', 'Location', 'northeast');
xline(12, '--k', '预热结束', 'LabelOrientation', 'horizontal');

subplot(1,3,3);
residual = d10_rtl_pipe(:);
residual = residual(residual > 0);
if isempty(residual)
    text(0.3, 0.5, '残差 = 0\nPipeline 模型完全匹配 RTL', 'FontSize', 14, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
    xlim([0 1]); ylim([0 1]); axis off;
else
    histogram(residual, 0:max(3, max(residual))); grid on;
    xlabel('Lr0 残差 (RTL - Pipeline)'); ylabel('像素数');
    title(sprintf('非零残差分布 (共 %d 个)', length(residual)));
end

sgtitle('流水线延迟模式深入分析', 'FontSize', 14);

%% ===================== 保存报告 =====================
reportImg1 = fullfile(outFolder, 'root_cause_matching_rate.png');
reportImg2 = fullfile(outFolder, 'root_cause_delay_pattern.png');
saveas(fig1, reportImg1);
saveas(fig2, reportImg2);
fprintf('  报告已保存:\n');
fprintf('    %s\n', reportImg1);
fprintf('    %s\n', reportImg2);

%% ===================== 汇总输出 =====================
fprintf('\n========================================\n');
fprintf('            SGM 根因验证汇总\n');
fprintf('========================================\n');
fprintf('  ※ Stage10/11 已进行 %d 像素偏移校正\n', TB_CAPTURE_OFFSET);
fprintf('  ※ 有效比对宽度 = %d (跳过 RTL 前 %d 个无效位置)\n', VALID_WIDTH, TB_CAPTURE_OFFSET);
fprintf('  -------------------------------------------------\n');
fprintf('  比对项目           | RTL vs Pipeline | RTL vs Ideal\n');
fprintf('  -------------------+-----------------+--------------\n');
fprintf('  Stage4  hamm_dist  |     %5.2f%%      |    %5.2f%%\n',   r4_rtl_pipe,  r4_rtl_ideal);
fprintf('  Stage10 Lr0_curr   |     %5.2f%%      |    %5.2f%%\n',   r10_rtl_pipe, r10_rtl_ideal);
fprintf('  Stage11 combined_lr|     %5.2f%%      |    %5.2f%%\n',   r11_rtl_pipe, r11_rtl_ideal);
fprintf('  Stage17 disparity  |     %5.2f%%      |    %5.2f%%  (±1容差)\n', r17_pipe_w1, r17_ideal_w1);
fprintf('  -------------------+-----------------+--------------\n');

if stage10_pipe_ok && stage10_ideal_ng
    fprintf('\n  ★★★ 结论: Lr_prev 流水线反馈延迟确认为根因 ★★★\n');
elseif stage10_pipe_ok
    fprintf('\n  ⚠  Ideal 也与 RTL 匹配，可能是其他原因\n');
elseif stage10_ideal_ng
    fprintf('\n  ⚠  Pipeline 模型需要进一步调整\n');
else
    fprintf('\n  ⚠  全部不匹配，需从头排查\n');
end

fprintf('\n验证完成！\n');

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

function data = load_stage_data(folder, prefix, taskId, dataType, dataDim, imgW, imgH)
    fname = fullfile(folder, sprintf('%s_task_%d.dat', prefix, taskId));
    fid = fopen(fname, 'rb');
    if fid == -1
        error('找不到文件: %s', fname);
    end
    hdr = fread(fid, 5, 'uint8=>uint8');
    if length(hdr) < 5
        error('文件头不足5字节: %s', fname);
    end
    w = uint16(hdr(1)) * 256 + uint16(hdr(2));
    h = uint16(hdr(3)) * 256 + uint16(hdr(4));
    dtype = hdr(5);
    fprintf('    加载: %s → %dx%d, TYPE=0x%02X\n', fname, w, h, dtype);
    raw = fread(fid, [dataDim, imgW * imgH], dataType);
    fclose(fid);
    data = reshape(raw', imgH, imgW, dataDim);
end

function [exact, within1, maxDiff] = calc_disp_stat(ref, cmp)
    d = int16(ref) - int16(cmp);
    totalPix = numel(d);
    exact    = 100 * (1 - sum(abs(d(:)) > 0) / totalPix);
    within1  = 100 * (1 - sum(abs(d(:)) > 1) / totalPix);
    maxDiff  = max(abs(d(:)));
end
