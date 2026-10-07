clc;
clear;
close all;

%% =========================
% 参数设置
%% =========================
IMG_WIDTH   = 640;
IMG_HEIGHT  = 480;
MAX_DISP    = 40;      % 视差范围 0~39
CENSUS_BITS = 48;      % 7x7 Census 去中心 = 48bit
BYTES_PER_PIXEL = 6;   % 每像素6字节

% SGM参数
P1 = 10;
P2 = 120;

% 唯一性约束
USE_UNIQUENESS = true;
UNI_ABS_TH = 10;       % 第一小与第二小的绝对差阈值

% 左右一致性检查
USE_LR_CHECK = true;
LR_TH = 1;             % 左右一致性阈值

% 后处理
USE_MEDIAN_FILTER = true;
MEDIAN_SIZE = [5 5];

USE_SPECKLE_REMOVE = true;
SPECKLE_SIZE = 80;     % 小连通域面积阈值
SPECKLE_DIFF = 2;      % 连通时允许的视差差值

%% =========================
% 1. 选择左右目 dat 文件
%% =========================
[leftFile, leftPath] = uigetfile('*.dat', '请选择左目 census dat 文件');
if isequal(leftFile, 0)
    disp('未选择左目文件，程序结束。');
    return;
end

[rightFile, rightPath] = uigetfile('*.dat', '请选择右目 census dat 文件');
if isequal(rightFile, 0)
    disp('未选择右目文件，程序结束。');
    return;
end

leftDatPath  = fullfile(leftPath, leftFile);
rightDatPath = fullfile(rightPath, rightFile);

%% =========================
% 2. 选择输出文件夹
%% =========================
outFolder = uigetdir('', '请选择输出文件夹');
if isequal(outFolder, 0)
    disp('未选择输出文件夹，程序结束。');
    return;
end

%% =========================
% 3. 读取并检查 dat 格式
%% =========================
expectedSize = IMG_WIDTH * IMG_HEIGHT * BYTES_PER_PIXEL;

fid = fopen(leftDatPath, 'rb');
if fid == -1
    error('无法打开左目 dat 文件。');
end
leftRaw = fread(fid, inf, 'uint8=>uint8');
fclose(fid);

fid = fopen(rightDatPath, 'rb');
if fid == -1
    error('无法打开右目 dat 文件。');
end
rightRaw = fread(fid, inf, 'uint8=>uint8');
fclose(fid);

if numel(leftRaw) ~= expectedSize
    error('左目 dat 文件格式不正确：文件大小不是 640x480x6 字节。');
end
if numel(rightRaw) ~= expectedSize
    error('右目 dat 文件格式不正确：文件大小不是 640x480x6 字节。');
end

%% =========================
% 4. 重组为48bit Census
%% =========================
fprintf('重组 48bit census...\n');

leftRaw  = reshape(leftRaw,  BYTES_PER_PIXEL, []).';
rightRaw = reshape(rightRaw, BYTES_PER_PIXEL, []).';

leftCensus = ...
    bitshift(uint64(leftRaw(:,1)), 40) + ...
    bitshift(uint64(leftRaw(:,2)), 32) + ...
    bitshift(uint64(leftRaw(:,3)), 24) + ...
    bitshift(uint64(leftRaw(:,4)), 16) + ...
    bitshift(uint64(leftRaw(:,5)),  8) + ...
    uint64(leftRaw(:,6));

rightCensus = ...
    bitshift(uint64(rightRaw(:,1)), 40) + ...
    bitshift(uint64(rightRaw(:,2)), 32) + ...
    bitshift(uint64(rightRaw(:,3)), 24) + ...
    bitshift(uint64(rightRaw(:,4)), 16) + ...
    bitshift(uint64(rightRaw(:,5)),  8) + ...
    uint64(rightRaw(:,6));

leftCensus  = reshape(leftCensus,  IMG_WIDTH, IMG_HEIGHT).';
rightCensus = reshape(rightCensus, IMG_WIDTH, IMG_HEIGHT).';


%% =========================
% 6. 计算左目视差图（左图参考）
%% =========================
fprintf('计算左目视差图...\n');
dispLeft = compute_disparity_4path(rightCensus, leftCensus, ...
    IMG_WIDTH, IMG_HEIGHT, MAX_DISP, CENSUS_BITS, P1, P2, ...
    USE_UNIQUENESS, UNI_ABS_TH);

dispRight_fromLeft = zeros(size(dispLeft), 'uint8');

for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        d = double(dispLeft(y,x));

        xr = x - d;

        if xr >= 1 && xr <= IMG_WIDTH
            dispRight_fromLeft(y, xr) = d;
        end
    end
end
dispRight_fromLeft = medfilt2(dispRight_fromLeft, [5 5]);
%% =========================
% 7. 左右一致性检查
%% =========================
if USE_LR_CHECK
    fprintf('执行左右一致性检查...\n');
    dispRightChecked = left_right_check_right_view(dispRight_fromLeft, dispLeft, LR_TH);
else
    dispRightChecked = dispRight_fromLeft;
end

%% =========================
% 8. 中值滤波
%% =========================
if USE_MEDIAN_FILTER
    fprintf('执行中值滤波...\n');
    dispRightMed = medfilt2(dispRightChecked, MEDIAN_SIZE);
else
    dispRightMed = dispRightChecked;
end

%% =========================
% 9. Speckle 去除
%% =========================
if USE_SPECKLE_REMOVE
    fprintf('执行 speckle 去除...\n');
    dispRightFinal = remove_speckles(dispRightMed, SPECKLE_SIZE, SPECKLE_DIFF);
else
    dispRightFinal = dispRightMed;
end

%% =========================
% 10. 保存结果
%% =========================
[~, leftBase, ~]  = fileparts(leftFile);
[~, rightBase, ~] = fileparts(rightFile);

rawPath     = fullfile(outFolder, sprintf('01_disp_right_raw_%s__%s.png', leftBase, rightBase));
checkPath   = fullfile(outFolder, sprintf('02_disp_right_lrcheck_%s__%s.png', leftBase, rightBase));
medianPath  = fullfile(outFolder, sprintf('03_disp_right_median_%s__%s.png', leftBase, rightBase));
finalPath   = fullfile(outFolder, sprintf('04_disp_right_final_%s__%s.png', leftBase, rightBase));
leftPathOut = fullfile(outFolder, sprintf('05_disp_left_raw_%s__%s.png', leftBase, rightBase));

rawVis    = uint8(double(dispRight_fromLeft)        * 255 / (MAX_DISP - 1));
checkVis  = uint8(double(dispRightChecked) * 255 / (MAX_DISP - 1));
medianVis = uint8(double(dispRightMed)     * 255 / (MAX_DISP - 1));
finalVis  = uint8(double(dispRightFinal)   * 255 / (MAX_DISP - 1));
leftVis   = uint8(double(dispLeft)         * 255 / (MAX_DISP - 1));

imwrite(rawVis, rawPath);
imwrite(checkVis, checkPath);
imwrite(medianVis, medianPath);
imwrite(finalVis, finalPath);
imwrite(leftVis, leftPathOut);

fprintf('\n处理完成。\n');
fprintf('右目原始视差图      : %s\n', rawPath);
fprintf('右目一致性检查后    : %s\n', checkPath);
fprintf('右目中值滤波后      : %s\n', medianPath);
fprintf('右目最终演示结果    : %s\n', finalPath);
fprintf('左目原始视差图      : %s\n', leftPathOut);

figure('Name', 'SGM 4-Path Demo Final', 'NumberTitle', 'off');
subplot(2,3,1); imshow(rawVis);    title('Right Raw');
subplot(2,3,2); imshow(checkVis);  title('Right LR Check');
subplot(2,3,3); imshow(medianVis); title('Right Median');
subplot(2,3,4); imshow(finalVis);  title('Right Final');
subplot(2,3,5); imshow(leftVis);   title('Left Raw');

%% =========================
% 局部函数
%% =========================

function dispMap = compute_disparity_4path(matchImg, refImg, ...
    IMG_WIDTH, IMG_HEIGHT, MAX_DISP, CENSUS_BITS, P1, P2, ...
    USE_UNIQUENESS, UNI_ABS_TH)

    costVol = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_DISP, 'single');

    fprintf('  构建 cost volume...\n');
    for y = 1:IMG_HEIGHT
        if mod(y,20)==0 || y==1 || y==IMG_HEIGHT
            fprintf('    cost row %d / %d\n', y, IMG_HEIGHT);
        end
        for x = 1:IMG_WIDTH
            rc = refImg(y, x);
            for d = 0:MAX_DISP-1
                xm = x - d;
                if xm >= 1
                    xorVal = bitxor(matchImg(y, xm), rc);
                    costVol(y, x, d+1) = single(popcount48(xorVal));
                else
                    costVol(y, x, d+1) = single(CENSUS_BITS);
                end
            end
        end
    end

    L1 = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_DISP, 'single');
    L2 = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_DISP, 'single');
    L3 = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_DISP, 'single');
    L4 = zeros(IMG_HEIGHT, IMG_WIDTH, MAX_DISP, 'single');

    % 左 -> 右
    fprintf('  聚合方向 1/4: Left -> Right\n');
    for y = 1:IMG_HEIGHT
        prev = zeros(1, MAX_DISP, 'single');
        for x = 1:IMG_WIDTH
            C = reshape(costVol(y,x,:), 1, []);
            curr = zeros(1, MAX_DISP, 'single');
            if x == 1
                curr = C;
            else
                minPrev = min(prev);
                for d = 1:MAX_DISP
                    a = prev(d);
                    if d > 1
                        b = prev(d-1) + P1;
                    else
                        b = inf;
                    end
                    if d < MAX_DISP
                        c = prev(d+1) + P1;
                    else
                        c = inf;
                    end
                    e = minPrev + P2;
                    curr(d) = C(d) + min([a,b,c,e]) - minPrev;
                end
            end
            L1(y,x,:) = curr;
            prev = curr;
        end
    end

    % 右 -> 左
    fprintf('  聚合方向 2/4: Right -> Left\n');
    for y = 1:IMG_HEIGHT
        prev = zeros(1, MAX_DISP, 'single');
        for x = IMG_WIDTH:-1:1
            C = reshape(costVol(y,x,:), 1, []);
            curr = zeros(1, MAX_DISP, 'single');
            if x == IMG_WIDTH
                curr = C;
            else
                minPrev = min(prev);
                for d = 1:MAX_DISP
                    a = prev(d);
                    if d > 1
                        b = prev(d-1) + P1;
                    else
                        b = inf;
                    end
                    if d < MAX_DISP
                        c = prev(d+1) + P1;
                    else
                        c = inf;
                    end
                    e = minPrev + P2;
                    curr(d) = C(d) + min([a,b,c,e]) - minPrev;
                end
            end
            L2(y,x,:) = curr;
            prev = curr;
        end
    end

    % 上 -> 下
    fprintf('  聚合方向 3/4: Top -> Bottom\n');
    for x = 1:IMG_WIDTH
        prev = zeros(1, MAX_DISP, 'single');
        for y = 1:IMG_HEIGHT
            C = reshape(costVol(y,x,:), 1, []);
            curr = zeros(1, MAX_DISP, 'single');
            if y == 1
                curr = C;
            else
                minPrev = min(prev);
                for d = 1:MAX_DISP
                    a = prev(d);
                    if d > 1
                        b = prev(d-1) + P1;
                    else
                        b = inf;
                    end
                    if d < MAX_DISP
                        c = prev(d+1) + P1;
                    else
                        c = inf;
                    end
                    e = minPrev + P2;
                    curr(d) = C(d) + min([a,b,c,e]) - minPrev;
                end
            end
            L3(y,x,:) = curr;
            prev = curr;
        end
    end

    % 下 -> 上
    fprintf('  聚合方向 4/4: Bottom -> Top\n');
    for x = 1:IMG_WIDTH
        prev = zeros(1, MAX_DISP, 'single');
        for y = IMG_HEIGHT:-1:1
            C = reshape(costVol(y,x,:), 1, []);
            curr = zeros(1, MAX_DISP, 'single');
            if y == IMG_HEIGHT
                curr = C;
            else
                minPrev = min(prev);
                for d = 1:MAX_DISP
                    a = prev(d);
                    if d > 1
                        b = prev(d-1) + P1;
                    else
                        b = inf;
                    end
                    if d < MAX_DISP
                        c = prev(d+1) + P1;
                    else
                        c = inf;
                    end
                    e = minPrev + P2;
                    curr(d) = C(d) + min([a,b,c,e]) - minPrev;
                end
            end
            L4(y,x,:) = curr;
            prev = curr;
        end
    end

    fprintf('  WTA 生成视差图...\n');
    dispMap = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');

    for y = 1:IMG_HEIGHT
        if mod(y,20)==0 || y==1 || y==IMG_HEIGHT
            fprintf('    WTA row %d / %d\n', y, IMG_HEIGHT);
        end
        for x = 1:IMG_WIDTH
            S = reshape(L1(y,x,:) + L2(y,x,:) + L3(y,x,:) + L4(y,x,:), 1, []);

            if USE_UNIQUENESS
                [min1, idx1] = min(S);
                S2 = S;
                S2(idx1) = inf;
                min2 = min(S2);

                if (min2 - min1) < UNI_ABS_TH
                    dispMap(y,x) = uint8(0);
                else
                    dispMap(y,x) = uint8(idx1 - 1);
                end
            else
                [~, idx] = min(S);
                dispMap(y,x) = uint8(idx - 1);
            end
        end
    end
end

function out = left_right_check_right_view(dispRight, dispLeft, th)
    [h, w] = size(dispRight);
    out = zeros(h, w, 'uint8');

    for y = 1:h
        for x = 1:w
            d = double(dispRight(y,x));
            xl = x - d;

            if d <= 0 || xl < 1 || xl > w
                out(y,x) = 0;
                continue;
            end

            dl = double(dispLeft(y, xl));
            if abs(d - dl) <= th
                out(y,x) = dispRight(y,x);
            else
                out(y,x) = 0;
            end
        end
    end
end

function out = remove_speckles(in, maxSpeckleSize, diffThreshold)
    [h, w] = size(in);
    out = in;
    visited = false(h, w);

    dirs = [-1 0; 1 0; 0 -1; 0 1];

    for y = 1:h
        for x = 1:w
            if visited(y,x) || out(y,x) == 0
                continue;
            end

            seedVal = double(out(y,x));

            queue = zeros(h*w, 2);
            head = 1;
            tail = 1;
            queue(tail,:) = [y, x];
            visited(y,x) = true;

            pixels = zeros(h*w, 2);
            count = 0;

            while head <= tail
                cy = queue(head,1);
                cx = queue(head,2);
                head = head + 1;

                count = count + 1;
                pixels(count,:) = [cy, cx];

                for k = 1:4
                    ny = cy + dirs(k,1);
                    nx = cx + dirs(k,2);

                    if ny < 1 || ny > h || nx < 1 || nx > w
                        continue;
                    end
                    if visited(ny,nx)
                        continue;
                    end
                    if out(ny,nx) == 0
                        continue;
                    end

                    if abs(double(out(ny,nx)) - seedVal) <= diffThreshold
                        tail = tail + 1;
                        queue(tail,:) = [ny, nx];
                        visited(ny,nx) = true;
                    end
                end
            end

            if count < maxSpeckleSize
                for k = 1:count
                    out(pixels(k,1), pixels(k,2)) = 0;
                end
            end
        end
    end
end

function n = popcount48(v)
    n = 0;
    for b = 1:48
        n = n + bitget(v, b);
    end
end