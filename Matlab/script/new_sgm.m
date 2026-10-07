%% sgm_new_lr0_replay.m
% 根据 Verilog: sgm_new，只还原 lr0 方向计算过程
% cmr1 = 左摄像头 census 输入
% cmr2 = 右摄像头 census 输入
%
% 文件格式：
% ASCII 十六进制字节，空格分隔
% header 5字节：
%   02 80 01 E0 02
% 表示：
%   width  = 0x0280 = 640
%   height = 0x01E0 = 480
%   type   = 0x02
% 后续每3字节为一个24bit census，高8位在前

clear;
clc;

%% ===================== 参数区：对应 Verilog parameter =====================
IMG_WIDTH        = 640;
IMG_HEIGHT       = 480;
MAX_MATCH_DEPTH  = 48;
CENSUS_WIDTH     = 24;
DISPARITY_WIDTH  = 8;     %#ok<NASGU>
SGM_P1           = 3;
SGM_P2           = 24;
SGM_LR_WIDTH     = 12;    %#ok<NASGU>
SGM_INVALID_COST = 24;

% 输入文件
left_census_file  = "..\..\Matlab\test img\census_dat\5\im0_gray.png.dat";
right_census_file = "..\..\Matlab\test img\census_dat\5\im1_gray.png.dat";

% 输出文件
out_disparity_png = 'right_disparity_lr0.png';
out_disparity_mat = 'right_disparity_lr0.mat';

%% ===================== 读取 census 文件 =====================
[left_census, left_w, left_h, left_type] = read_census_hex_file(left_census_file);
[right_census, right_w, right_h, right_type] = read_census_hex_file(right_census_file);

fprintf('[INFO] left : %d x %d, type = 0x%02X\n', left_w, left_h, left_type);
fprintf('[INFO] right: %d x %d, type = 0x%02X\n', right_w, right_h, right_type);

if left_w ~= right_w || left_h ~= right_h
    error('左右 census 图像尺寸不一致。');
end

if left_w ~= IMG_WIDTH || left_h ~= IMG_HEIGHT
    warning('文件头尺寸与脚本参数不一致，使用文件头尺寸覆盖 IMG_WIDTH / IMG_HEIGHT。');
    IMG_WIDTH  = left_w;
    IMG_HEIGHT = left_h;
end

if left_type ~= 2 || right_type ~= 2
    warning('文件 type 不是 0x02，请确认是否仍然是每3字节一个24bit census。');
end

%% ===================== 输出缓存 =====================
disparity_lr0 = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');

% 可选：保存每个像素每个视差的 lr0 代价，调试用
% 数据量：480 * 640 * 48，double 大约 118 MB
% 如果不需要可以关掉
SAVE_LR0_VOLUME = false;
if SAVE_LR0_VOLUME
    lr0_volume = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_MATCH_DEPTH, 'uint16');
else
    lr0_volume = [];
end

%% ===================== 主循环：逐行模拟 lr0 方向 =====================
% Verilog 中 lr0 方向本质递推：
%
% Lr0(x,d) = C(x,d) + min(
%               Lr0(x-1,d),
%               Lr0(x-1,d-1) + P1,
%               Lr0(x-1,d+1) + P1,
%               min_k Lr0(x-1,k) + P2
%           ) - min_k Lr0(x-1,k)
%
% 但你的 Verilog 已经把 min_k Lr0(x-1,k) 预先减进 R0/R1/R2，
% R3 直接使用 P2：
%
% R0 = Lr0_prev[d]   - Lr0_min
% R1 = Lr0_prev[d-1] + P1 - Lr0_min
% R2 = Lr0_prev[d+1] + P1 - Lr0_min
% R3 = P2
%
% min4 = min(R0,R1,R2,R3)
% Lr0_curr[d] = C(x,d) + min4
%
% 第一列 Lr0_min_en = 0，所以 Lr0_curr[d] = C(x,d)

fprintf('[INFO] Start lr0 replay...\n');

for row = 1:IMG_HEIGHT

    % ---------------- stage-like 状态寄存器 ----------------
    % 对应一行开始时，Lr0_prev 尚无有效前一列
    Lr0_prev = zeros(1, MAX_MATCH_DEPTH);
    Lr0_curr = zeros(1, MAX_MATCH_DEPTH);
    Lr0_min  = 0;
    Lr0_min_en = false;

    for col = 1:IMG_WIDTH

        % Verilog 中列计数 cmr2_col_cnt 从0开始
        col0 = col - 1;

        %% ==================================================
        % stage 0 ~ stage 4:
        % 右图 right[x] 到来时，匹配窗口 xor_window[i] = left[x-i]
        % d = i 直接对应
        %% ==================================================
        hamming_dist = zeros(1, MAX_MATCH_DEPTH);

        right_code = right_census(row, col);

        for d = 0:MAX_MATCH_DEPTH-1

            if col0 >= d
                left_col = col - d;

                left_code = left_census(row, left_col);

                xor_code = bitxor(left_code, right_code);
                hamming_dist(d+1) = popcount24(xor_code);
            else
                % 对应 hamming_dist_valid_mask_pre[i] = cmr2_col_cnt >= i
                hamming_dist(d+1) = SGM_INVALID_COST;
            end
        end

        %% ==================================================
        % stage 5 ~ stage 9:
        % lr0 方向代价聚合
        %
        % 这里没有显式模拟 FIFO IP 的读写时钟，
        % 因为对 lr0 数学结果而言，FIFO 只是把 cost 与 min4 流水线对齐。
        % 本脚本在同一个像素位置使用同一个 C(x,d) 和对应 min4，
        % 等效于 Verilog 流水线稳定后的结果。
        %% ==================================================
        if ~Lr0_min_en
            % 第一列，Verilog 中 Lr0_min_en_dly 无效：
            % Lr0_curr[d] <= lr0_cost_fifo_dout[d]
            Lr0_curr = hamming_dist;
        else
            min4 = zeros(1, MAX_MATCH_DEPTH);

            for d = 0:MAX_MATCH_DEPTH-1

                % R0
                r0 = max(Lr0_prev(d+1) - Lr0_min, 0);

                % R1
                if d == 0
                    r1 = inf;
                else
                    r1 = max(SGM_P1 + Lr0_prev(d) - Lr0_min, 0);
                end

                % R2
                if d == MAX_MATCH_DEPTH-1
                    r2 = inf;
                else
                    r2 = max(SGM_P1 + Lr0_prev(d+2) - Lr0_min, 0);
                end

                % R3
                r3 = SGM_P2;

                min4(d+1) = min([r0, r1, r2, r3]);

                Lr0_curr(d+1) = hamming_dist(d+1) + min4(d+1);
            end
        end

        % 模拟 12bit 代价寄存器的安全范围
        % 正常参数下不会溢出；这里保留检查，便于发现异常。
        if any(Lr0_curr > 2^SGM_LR_WIDTH - 1)
            warning('row=%d, col=%d 出现 Lr0_curr 超过 %d bit 范围。', ...
                row, col, SGM_LR_WIDTH);
        end

        %% ==================================================
        % stage 10 ~ stage 15:
        % Lr0_min 比较树
        %% ==================================================
        Lr0_min_next = min(Lr0_curr);

        %% ==================================================
        % stage 10:
        % combined_lr = Lr0_curr
        %
        % 你的 Verilog 当前写法：
        %   combined_lr <= Lr0_curr;
        %   // combined_lr <= Lr0_curr + Lr2_curr;
        %% ==================================================
        combined_lr = Lr0_curr;

        %% ==================================================
        % stage 11 ~ stage 16:
        % WTA 比较树，取最小代价对应的视差
        %
        % Verilog 中比较使用 <=，相等时选择较小 d。
        % MATLAB min 默认也是返回第一个最小值，即较小 d。
        %% ==================================================
        [~, best_idx] = min(combined_lr);
        best_d = best_idx - 1;

        disparity_lr0(row, col) = uint8(best_d);

        if SAVE_LR0_VOLUME
            lr0_volume(row, col, :) = uint16(Lr0_curr);
        end

        %% ==================================================
        % 当前列结果成为下一列 prev
        %% ==================================================
        Lr0_prev = Lr0_curr;
        Lr0_min  = Lr0_min_next;
        Lr0_min_en = true;
    end

    if mod(row, 20) == 0 || row == IMG_HEIGHT
        fprintf('[INFO] row %d / %d done\n', row, IMG_HEIGHT);
    end
end

fprintf('[INFO] lr0 replay finished.\n');

%% ===================== 保存结果 =====================
% 视差值范围 0 ~ 47，直接保存会比较暗；
% 这里保存一个拉伸到 0~255 的 png 便于查看，同时 mat 里保存原始视差。
disparity_show = uint8(double(disparity_lr0) * 255 / max(1, MAX_MATCH_DEPTH-1));
imwrite(disparity_show, out_disparity_png);

if SAVE_LR0_VOLUME
    save(out_disparity_mat, ...
        'disparity_lr0', 'lr0_volume', ...
        'IMG_WIDTH', 'IMG_HEIGHT', 'MAX_MATCH_DEPTH', ...
        'SGM_P1', 'SGM_P2', 'SGM_INVALID_COST', ...
        '-v7.3');
else
    save(out_disparity_mat, ...
        'disparity_lr0', ...
        'IMG_WIDTH', 'IMG_HEIGHT', 'MAX_MATCH_DEPTH', ...
        'SGM_P1', 'SGM_P2', 'SGM_INVALID_COST');
end

fprintf('[INFO] disparity png saved: %s\n', out_disparity_png);
fprintf('[INFO] disparity mat saved: %s\n', out_disparity_mat);

%% ========================================================================
% local functions
%% ========================================================================

function [census_img, width, height, data_type] = read_census_hex_file(filename)
    % 读取 ASCII 十六进制字节文件
    %
    % 示例：
    %   02 80 01 E0 02 xx xx xx ...
    %
    % 每3个字节拼成一个 uint32：
    %   byte0 = 高8位
    %   byte1 = 中8位
    %   byte2 = 低8位

    if ~isfile(filename)
        error('找不到文件: %s', filename);
    end

    txt = fileread(filename);

    % sscanf('%x') 会按十六进制读取空格/换行分隔的 token
    raw = sscanf(txt, '%x');

    if numel(raw) < 5
        error('文件长度不足5字节，无法读取 header。');
    end

    bytes = uint32(raw(:));

    if any(bytes > 255)
        error('文件中存在超过 FF 的字节，请确认是否是按字节空格分隔的十六进制格式。');
    end

    width     = double(bytes(1) * 256 + bytes(2));
    height    = double(bytes(3) * 256 + bytes(4));
    data_type = double(bytes(5));

    payload = bytes(6:end);

    expected_bytes = width * height * 3;

    if numel(payload) < expected_bytes
        error('payload 字节不足：期望 %d，实际 %d。', expected_bytes, numel(payload));
    elseif numel(payload) > expected_bytes
        warning('payload 字节多于期望值：期望 %d，实际 %d。多余字节将被忽略。', ...
            expected_bytes, numel(payload));
        payload = payload(1:expected_bytes);
    end

    payload3 = reshape(payload, 3, []).';

    census_vec = ...
        bitshift(payload3(:,1), 16) + ...
        bitshift(payload3(:,2),  8) + ...
        payload3(:,3);

    % 文件默认按行优先排列：
    % row0: col0 col1 col2 ...
    census_img = reshape(census_vec, width, height).';
    census_img = uint32(census_img);
end

function cnt = popcount24(x)
    % 计算 24bit 数中 1 的个数
    % x 可以是 uint32 标量

    x = uint32(x);

    b0 = bitand(x, uint32(255));
    b1 = bitand(bitshift(x, -8),  uint32(255));
    b2 = bitand(bitshift(x, -16), uint32(255));

    cnt = popcount8(b0) + popcount8(b1) + popcount8(b2);
end

function cnt = popcount8(x)
    % 计算 8bit popcount
    % 用 bitget，避免依赖额外 toolbox

    x = uint32(x);
    cnt = 0;

    for k = 1:8
        cnt = cnt + double(bitget(x, k));
    end
end