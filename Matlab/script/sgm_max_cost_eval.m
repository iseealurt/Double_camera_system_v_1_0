%% sgm_max_cost_eval.m
% SGM 单条匹配路径内最大匹配代价值评估
% 评估4条路径: L→R, T→B, LT→RB, RT→LB
% 分辨率: 480P, 视差范围: 96 pixel
% 用于确定FPGA硬件实现中的代价位宽
clear; clc; close all;

%% ====================== 参数配置 ======================
IMG_WIDTH  = 640;
IMG_HEIGHT = 480;
MAX_DISP   = 96;
P1 = 3;
P2 = 24;
INVALID_COST = 24;
CENSUS_BITS = 24;

fprintf('========================================\n');
fprintf('SGM 单路径最大匹配代价值评估\n');
fprintf('========================================\n');
fprintf('图像分辨率: %d x %d\n', IMG_WIDTH, IMG_HEIGHT);
fprintf('最大视差:   %d pixel\n', MAX_DISP);
fprintf('P1 = %d, P2 = %d\n', P1, P2);
fprintf('========================================\n\n');

%% ====================== 选择左右目Census文件 ======================
[leftFile, path1] = uigetfile('*.dat', '选择 左目 Census .dat 文件');
if isequal(leftFile, 0), disp('用户取消'); return; end

[rightFile, path2] = uigetfile('*.dat', '选择 右目 Census .dat 文件');
if isequal(rightFile, 0), disp('用户取消'); return; end

leftPath  = fullfile(path1, leftFile);
rightPath = fullfile(path2, rightFile);

fprintf('[1] 读取Census文件...\n');
fprintf('    左目: %s\n', leftPath);
fprintf('    右目: %s\n', rightPath);

%% ====================== 读取DAT文件(含5字节文件头) ======================
rawLeft  = read_dat_file(leftPath);
rawRight = read_dat_file(rightPath);

% 解析文件头
img_width  = bitshift(uint16(rawLeft(1)), 8) + uint16(rawLeft(2));
img_height = bitshift(uint16(rawLeft(3)), 8) + uint16(rawLeft(4));
data_type  = rawLeft(5);

fprintf('    文件头解析: 宽度=%d, 高度=%d, 类型=%d\n', ...
    img_width, img_height, data_type);

% 校验尺寸
pixel_count = img_width * img_height;
expected_raw_len = 5 + pixel_count * 3;

if length(rawLeft) ~= expected_raw_len || length(rawRight) ~= expected_raw_len
    warning('文件尺寸异常: 左=%d, 右=%d, 期望=%d', ...
        length(rawLeft), length(rawRight), expected_raw_len);
end

if img_width ~= IMG_WIDTH || img_height ~= IMG_HEIGHT
    warning('图像尺寸与预期不匹配(预期 %dx%d, 实际 %dx%d)', ...
        IMG_WIDTH, IMG_HEIGHT, img_width, img_height);
end

%% ====================== 解析Census数据 ======================
fprintf('[2] 解析Census数据...\n');

censusLeft  = parse_census_data(rawLeft,  img_height, img_width);
censusRight = parse_census_data(rawRight, img_height, img_width);

fprintf('    Census数据解析完成: %d x %d x %d bit\n', ...
    img_height, img_width, CENSUS_BITS);

%% ====================== 检查GPU可用性 ======================
useGPU = false;
try
    if gpuDeviceCount > 0
        gpuInfo = gpuDevice();
        fprintf('[3] GPU可用: %s (显存: %.1f GB)\n', ...
            gpuInfo.Name, gpuInfo.TotalMemory / 1e9);
        useGPU = true;
    end
catch
    fprintf('[3] GPU不可用，使用CPU计算\n');
end

if useGPU
    censusLeft  = gpuArray(censusLeft);
    censusRight = gpuArray(censusRight);
end

%% ====================== 4条路径聚合 ======================
fprintf('\n[4] 开始4条路径聚合评估...\n\n');

path_results = struct();
path_names = {'L→R (Left to Right)', ...
              'T→B (Top to Bottom)', ...
              'LT→RB (Diag ↘)', ...
              'RT→LB (Anti-Diag ↙)'};

% 使用单精度避免溢出
use_gpu = useGPU;

for p = 1:4
    fprintf('───── 路径 %d/4: %s ─────\n', p, path_names{p});
    
    switch p
        case 1  % L→R
            [max_cost, max_info] = path_LR(censusLeft, censusRight, ...
                IMG_HEIGHT, IMG_WIDTH, MAX_DISP, P1, P2, INVALID_COST, use_gpu);
        case 2  % T→B
            [max_cost, max_info] = path_TB(censusLeft, censusRight, ...
                IMG_HEIGHT, IMG_WIDTH, MAX_DISP, P1, P2, INVALID_COST, use_gpu);
        case 3  % LT→RB
            [max_cost, max_info] = path_LTRB(censusLeft, censusRight, ...
                IMG_HEIGHT, IMG_WIDTH, MAX_DISP, P1, P2, INVALID_COST, use_gpu);
        case 4  % RT→LB
            [max_cost, max_info] = path_RTLB(censusLeft, censusRight, ...
                IMG_HEIGHT, IMG_WIDTH, MAX_DISP, P1, P2, INVALID_COST, use_gpu);
    end
    
    % 收集结果
    path_results(p).name     = path_names{p};
    path_results(p).max_cost = max_cost;
    path_results(p).max_info = max_info;
    
    fprintf('    → 最大聚合代价值: %d\n', max_cost);
    fprintf('    → 出现位置: (行=%d, 列=%d, 视差=%d)\n', ...
        max_info.y, max_info.x, max_info.d-1);
    fprintf('    → 该位置原始匹配代价: %d\n\n', max_info.raw_cost);
end

%% ====================== 结果汇总 ======================
fprintf('========================================\n');
fprintf('          结果汇总\n');
fprintf('========================================\n');
fprintf('  %-25s | %s\n', '路径', '最大聚合代价');
fprintf('  %s-|-%s\n', repmat('-',1,25), repmat('-',1,15));
for p = 1:4
    fprintf('  %-25s |  %d\n', path_results(p).name, path_results(p).max_cost);
end
fprintf('========================================\n');

% 计算理论最大值
theoretical_max = INVALID_COST + (IMG_WIDTH + IMG_HEIGHT) * (P2 + INVALID_COST);
fprintf('\n[参考] 理论极限值(最恶劣情况): ~%d\n', theoretical_max);
fprintf('      实际最大: %d  (占理论值的 %.1f%%)\n', ...
    max([path_results.max_cost]), ...
    max([path_results.max_cost]) / theoretical_max * 100);

% 建议的位宽
worst_max = max([path_results.max_cost]);
needed_bits = ceil(log2(worst_max + 1));
fprintf('\n[位宽建议] Lr聚合代价所需位宽: %d bit (最大值 %d, 2^%d = %d)\n', ...
    needed_bits, worst_max, needed_bits, 2^needed_bits);

%% ====================== 可视化输出 ======================
fprintf('\n[5] 生成可视化...\n');

figure('Name', 'SGM单路径最大匹配代价值评估', 'Position', [50, 50, 1400, 900]);

% 1. 最大代价柱状图
subplot(2, 3, 1);
max_vals = [path_results.max_cost];
bar(max_vals, 'FaceColor', [0.3, 0.6, 0.9], 'EdgeColor', 'k', 'LineWidth', 1.5);
set(gca, 'XTickLabel', {'L→R', 'T→B', 'LT→RB', 'RT→LB'});
ylabel('最大聚合代价值');
title('各路径最大聚合代价');
grid on;
for i = 1:4
    text(i, max_vals(i), num2str(max_vals(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontWeight', 'bold');
end

% 2. 实际/理论 对比
subplot(2, 3, 2);
theoretical_per_path = zeros(1, 4);
H = IMG_HEIGHT; W = IMG_WIDTH;
% 每条路径的理论最大值 = max_hamming + P2 * max_path_length
% 路径长度: L→R = W, T→B = H, LT→RB = W+H-2, RT→LB = W+H-2
path_lengths = [W, H, W+H-2, W+H-2];
theoretical = INVALID_COST + (path_lengths - 1) * (P2 + INVALID_COST);
ratio = max_vals ./ theoretical * 100;
bar(ratio, 'FaceColor', [0.9, 0.5, 0.3], 'EdgeColor', 'k', 'LineWidth', 1.5);
set(gca, 'XTickLabel', {'L→R', 'T→B', 'LT→RB', 'RT→LB'});
ylabel('占理论最大值比例 (%)');
title('实际/理论对比');
grid on;
ylim([0, 100]);
for i = 1:4
    text(i, ratio(i), sprintf('%.1f%%', ratio(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontWeight', 'bold');
end

% 3. 位宽需求示意
subplot(2, 3, 3);
bits_needed = ceil(log2(max_vals + 1));
bar(bits_needed, 'FaceColor', [0.2, 0.7, 0.4], 'EdgeColor', 'k', 'LineWidth', 1.5);
set(gca, 'XTickLabel', {'L→R', 'T→B', 'LT→RB', 'RT→LB'});
ylabel('所需位宽 (bit)');
title('各路径所需Lr位宽');
grid on;
for i = 1:4
    text(i, bits_needed(i), sprintf('%d bit\n(max=%d)', bits_needed(i), max_vals(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontWeight', 'bold');
end

% 4. 各路径代价分布热力图
subplot(2, 3, 4:6);
plot_data = zeros(4, max(bits_needed) + 2);
for p = 1:4
    plot_data(p, 1:bits_needed(p)+2) = [max_vals(p), 2^(bits_needed(p)-1), 2^(bits_needed(p))];
end
% 改用表格形式显示
col_names = {};
for p = 1:4
    col_names{p} = sprintf('%s\nmax=%d', strrep(path_names{p}, ' ', ''), max_vals(p));
end
% 创建一个表格
T = table((1:4)', max_vals', bits_needed', max_vals'./theoretical'*100, ...
    'VariableNames', {'路径', '最大代价', '所需位宽', '理论占比'});
T.路径 = {'L→R'; 'T→B'; 'LT→RB'; 'RT→LB'};
uitable('Data', table2cell(T), 'ColumnName', T.Properties.VariableNames, ...
    'Position', [120, 60, 560, 120], 'FontSize', 12, ...
    'ColumnWidth', {80, 80, 80, 80});

text(0.1, 0.85, sprintf('结论: Lr聚合代价最大值为 %d\n建议位宽: %d bit (0~%d)', ...
    worst_max, needed_bits, 2^needed_bits-1), ...
    'Units', 'normalized', 'FontSize', 14, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.9, 0.9, 0.9], 'EdgeColor', 'k', ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
text(0.1, 0.55, sprintf(['评估参数:\n  分辨率: %dx%d\n  视差范围: %d\n  P1=%d, P2=%d\n' ...
    '  无效代价=%d\n  路径长度: %s'], ...
    IMG_WIDTH, IMG_HEIGHT, MAX_DISP, P1, P2, INVALID_COST, ...
    mat2str(path_lengths)), ...
    'Units', 'normalized', 'FontSize', 11, ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
axis off;

sgtitle(sprintf('SGM单路径最大匹配代价值评估  (P1=%d, P2=%d, 无效代价=%d)', P1, P2, INVALID_COST), ...
    'FontSize', 16, 'FontWeight', 'bold');

%% ====================== 保存结果 ======================
% 询问保存路径
savePath = fullfile(pwd, 'sgm_max_cost_result.mat');
[saveFile, saveDir] = uiputfile('*.mat', '保存评估结果', savePath);
if saveFile ~= 0
    save(fullfile(saveDir, saveFile), 'path_results', 'IMG_WIDTH', 'IMG_HEIGHT', ...
        'MAX_DISP', 'P1', 'P2', 'INVALID_COST', 'worst_max', 'needed_bits');
    fprintf('\n结果已保存至: %s\n', fullfile(saveDir, saveFile));
end

% 保存图片
[imgFile, imgDir] = uiputfile('*.png', '保存热力图', fullfile(pwd, 'sgm_max_cost_heatmap.png'));
if imgFile ~= 0
    saveas(gcf, fullfile(imgDir, imgFile));
    fprintf('热力图已保存至: %s\n', fullfile(imgDir, imgFile));
end

fprintf('\n===== 评估完成 =====\n');

%% ====================== 辅助函数 ======================

function raw = read_dat_file(filepath)
    fid = fopen(filepath, 'rb');
    if fid == -1
        error('无法打开文件: %s', filepath);
    end
    raw = fread(fid, Inf, 'uint8');
    fclose(fid);
end

function censusImg = parse_census_data(raw, img_height, img_width)
    % 跳过5字节文件头
    pixel_data = raw(6:end);
    % 每像素3字节
    pixel_data = reshape(pixel_data, 3, [])';
    % 拼接为24bit uint32 (Big Endian: byte1=高8位, byte3=低8位)
    census24 = bitshift(uint32(pixel_data(:,1)), 16) + ...
               bitshift(uint32(pixel_data(:,2)), 8) + ...
               uint32(pixel_data(:,3));
    % 按光栅顺序reshape为图像矩阵
    censusImg = reshape(census24, img_width, img_height)';
end

function cost = compute_cost_line(leftCensus, rightCensus, ...
        y, x, MAX_DISP, INVALID_COST, use_gpu)
    % 计算像素(y,x)在所有视差下的匹配代价
    if use_gpu
        cost = gpuArray.zeros(1, MAX_DISP, 'uint8');
    else
        cost = zeros(1, MAX_DISP, 'uint8');
    end
    
    left_row = leftCensus(y, :);
    right_val = rightCensus(y, x);
    
    for d = 0:MAX_DISP-1
        if x - d >= 1
            xorv = bitxor(left_row(x - d), right_val);
            cost(d+1) = uint8(sum(bitget(xorv, 1:24)));
        else
            cost(d+1) = INVALID_COST;
        end
    end
end

function [max_cost, max_info] = path_LR(leftCensus, rightCensus, ...
        H, W, D, P1, P2, INVALID_COST, use_gpu)
    % L→R 路径聚合 (Left to Right)
    max_cost = 0;
    max_info = struct('y', 0, 'x', 0, 'd', 0, 'raw_cost', 0);
    
    if use_gpu
        cls = 'gpuArray';
    else
        cls = 'double';
    end
    
    for y = 1:H
        Lr_prev = zeros(1, D, cls);
        
        for x = 1:W
            % 计算匹配代价
            cost = compute_cost_line(leftCensus, rightCensus, y, x, D, INVALID_COST, use_gpu);
            
            % SGM聚合
            Lr_curr = zeros(1, D, cls);
            min_prev = min(Lr_prev);
            
            if min_prev == inf
                min_prev = 0;
            end
            
            for d = 1:D
                l1 = Lr_prev(d);
                l2 = inf;
                l3 = inf;
                if d > 1, l2 = Lr_prev(d-1) + P1; end
                if d < D, l3 = Lr_prev(d+1) + P1; end
                l4 = min_prev + P2;
                
                Lr_curr(d) = double(cost(d)) + min([l1, l2, l3, l4]) - min_prev;
            end
            
            % 追踪最大值
            [cur_max, cur_d] = max(Lr_curr);
            if cur_max > max_cost
                max_cost = cur_max;
                max_info.y = y;
                max_info.x = x;
                max_info.d = cur_d;
                max_info.raw_cost = double(cost(cur_d));
            end
            
            Lr_prev = Lr_curr;
        end
    end
    
    if use_gpu
        max_cost = gather(max_cost);
    end
end

function [max_cost, max_info] = path_TB(leftCensus, rightCensus, ...
        H, W, D, P1, P2, INVALID_COST, use_gpu)
    % T→B 路径聚合 (Top to Bottom)
    max_cost = 0;
    max_info = struct('y', 0, 'x', 0, 'd', 0, 'raw_cost', 0);
    
    if use_gpu
        cls = 'gpuArray';
    else
        cls = 'double';
    end
    
    for x = 1:W
        Lr_prev = zeros(1, D, cls);
        
        for y = 1:H
            cost = compute_cost_line(leftCensus, rightCensus, y, x, D, INVALID_COST, use_gpu);
            
            Lr_curr = zeros(1, D, cls);
            min_prev = min(Lr_prev);
            
            if min_prev == inf
                min_prev = 0;
            end
            
            for d = 1:D
                l1 = Lr_prev(d);
                l2 = inf;
                l3 = inf;
                if d > 1, l2 = Lr_prev(d-1) + P1; end
                if d < D, l3 = Lr_prev(d+1) + P1; end
                l4 = min_prev + P2;
                
                Lr_curr(d) = double(cost(d)) + min([l1, l2, l3, l4]) - min_prev;
            end
            
            [cur_max, cur_d] = max(Lr_curr);
            if cur_max > max_cost
                max_cost = cur_max;
                max_info.y = y;
                max_info.x = x;
                max_info.d = cur_d;
                max_info.raw_cost = double(cost(cur_d));
            end
            
            Lr_prev = Lr_curr;
        end
    end
    
    if use_gpu
        max_cost = gather(max_cost);
    end
end

function [max_cost, max_info] = path_LTRB(leftCensus, rightCensus, ...
        H, W, D, P1, P2, INVALID_COST, use_gpu)
    % LT→RB 路径聚合 (Top-Left to Bottom-Right, 对角线 ↘)
    % 沿 x+y=const 的对角线扫描，从左到右
    % 链ID = x - y (沿↘方向恒定), 范围 -(H-1)~(W-1), 偏移 H → 1~(W+H-1)
    % 前驱像素 (x-1, y-1) 在同一条链上, 在2条对角线之前被处理
    max_cost = 0;
    max_info = struct('y', 0, 'x', 0, 'd', 0, 'raw_cost', 0);
    
    if use_gpu
        Lr_buf = gpuArray.zeros(W+H-1, D);
        cls = 'gpuArray';
    else
        Lr_buf = zeros(W+H-1, D);
        cls = 'double';
    end
    
    for s = 2:W+H
        x_start = max(1, s - H);
        x_end   = min(W, s - 1);
        
        for x = x_start:x_end
            y = s - x;
            chain_id = x - y + H;
            
            cost = compute_cost_line(leftCensus, rightCensus, y, x, D, INVALID_COST, use_gpu);
            
            Lr_prev = Lr_buf(chain_id, :);
            min_prev = min(Lr_prev);
            
            Lr_curr = zeros(1, D, cls);
            for d = 1:D
                l1 = Lr_prev(d);
                l2 = inf;
                l3 = inf;
                if d > 1, l2 = Lr_prev(d-1) + P1; end
                if d < D, l3 = Lr_prev(d+1) + P1; end
                l4 = min_prev + P2;
                
                Lr_curr(d) = double(cost(d)) + min([l1, l2, l3, l4]) - min_prev;
            end
            
            Lr_buf(chain_id, :) = Lr_curr;
            
            [cur_max, cur_d] = max(Lr_curr);
            if cur_max > max_cost
                max_cost = cur_max;
                max_info.y = y;
                max_info.x = x;
                max_info.d = cur_d;
                max_info.raw_cost = double(cost(cur_d));
            end
        end
    end
    
    if use_gpu
        max_cost = gather(max_cost);
    end
end

function [max_cost, max_info] = path_RTLB(leftCensus, rightCensus, ...
        H, W, D, P1, P2, INVALID_COST, use_gpu)
    % RT→LB 路径聚合 (Top-Right to Bottom-Left, 对角线 ↙)
    % 沿 x+y=const 的对角线扫描，从右到左
    % 链ID = x + y (沿↙方向恒定), 范围 2~(W+H), 偏移 -1 → 1~(W+H-1)
    % 同一对角线上所有像素共享同一链ID, 从右到左遍历形成链式传播
    % 前驱像素 (x+1, y-1) 在同一对角线内, 已被右→左的前一步处理
    max_cost = 0;
    max_info = struct('y', 0, 'x', 0, 'd', 0, 'raw_cost', 0);
    
    if use_gpu
        Lr_buf = gpuArray.zeros(W+H-1, D);
        cls = 'gpuArray';
    else
        Lr_buf = zeros(W+H-1, D);
        cls = 'double';
    end
    
    for s = 2:W+H
        x_start = max(1, s - H);
        x_end   = min(W, s - 1);
        chain_id = s - 1;
        
        for x = x_end:-1:x_start
            y = s - x;
            
            cost = compute_cost_line(leftCensus, rightCensus, y, x, D, INVALID_COST, use_gpu);
            
            Lr_prev = Lr_buf(chain_id, :);
            min_prev = min(Lr_prev);
            
            Lr_curr = zeros(1, D, cls);
            for d = 1:D
                l1 = Lr_prev(d);
                l2 = inf;
                l3 = inf;
                if d > 1, l2 = Lr_prev(d-1) + P1; end
                if d < D, l3 = Lr_prev(d+1) + P1; end
                l4 = min_prev + P2;
                
                Lr_curr(d) = double(cost(d)) + min([l1, l2, l3, l4]) - min_prev;
            end
            
            Lr_buf(chain_id, :) = Lr_curr;
            
            [cur_max, cur_d] = max(Lr_curr);
            if cur_max > max_cost
                max_cost = cur_max;
                max_info.y = y;
                max_info.x = x;
                max_info.d = cur_d;
                max_info.raw_cost = double(cost(cur_d));
            end
        end
    end
    
    if use_gpu
        max_cost = gather(max_cost);
    end
end
