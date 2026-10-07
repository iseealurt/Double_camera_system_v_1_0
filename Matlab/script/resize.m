clc;
clear;

%% 1. 选择源文件夹
srcFolder = uigetdir('', '请选择源文件夹');
if srcFolder == 0
    disp('未选择源文件夹，程序结束');
    return;
end

%% 2. 选择输出文件夹
dstFolder = uigetdir('', '请选择输出文件夹');
if dstFolder == 0
    disp('未选择输出文件夹，程序结束');
    return;
end

%% 3. 获取图片文件（支持常见格式）
imgTypes = {'*.jpg','*.jpeg','*.png','*.bmp','*.tif'};
imgFiles = [];

for i = 1:length(imgTypes)
    imgFiles = [imgFiles; dir(fullfile(srcFolder, imgTypes{i}))];
end

if isempty(imgFiles)
    error('源文件夹中没有图片文件');
end

%% 4. 选择缩放模式
fprintf('请选择缩放模式：\n');
fprintf('  1 - 保持宽高比（填充黑边）\n');
fprintf('  2 - 直接拉伸至640x480\n');
fprintf('  3 - 保持宽高比（裁剪多余部分）\n');
modeChoice = input('请输入选项 (1/2/3，默认1): ', 's');
if isempty(modeChoice)
    modeChoice = '1';
end

switch modeChoice
    case '2'
        resizeMode = 'stretch';
    case '3'
        resizeMode = 'crop';
    otherwise
        resizeMode = 'letterbox';
end

%% 5. 选择插值方法
fprintf('\n请选择插值方法：\n');
fprintf('  1 - 双三次插值（亚像素插值，推荐，缩放质量最高）\n');
fprintf('  2 - 双线性插值\n');
fprintf('  3 - 最近邻插值\n');
interpChoice = input('请输入选项 (1/2/3，默认1): ', 's');
if isempty(interpChoice)
    interpChoice = '1';
end

switch interpChoice
    case '2'
        interpMethod = 'bilinear';
    case '3'
        interpMethod = 'nearest';
    otherwise
        interpMethod = 'bicubic';
end

fprintf('\n缩放模式: %s\n', resizeMode);
fprintf('插值方法: %s\n', interpMethod);

%% 6. 执行缩放任务
TARGET_WIDTH  = 640;
TARGET_HEIGHT = 480;

totalCount = 0;
for i = 1:length(imgFiles)
    imgPath = fullfile(srcFolder, imgFiles(i).name);
    img = imread(imgPath);
    [h, w, c] = size(img);
    if c > 3
        img = img(:, :, 1:3);
        c = 3;
    end

    totalCount = totalCount + 1;
    fprintf('\n[%d/%d] 处理: %s  (%dx%d) -> 640x480\n', ...
        totalCount, length(imgFiles), imgFiles(i).name, w, h);

    switch resizeMode
        case 'letterbox'
            scale = min(TARGET_WIDTH / w, TARGET_HEIGHT / h);
            newW = round(w * scale);
            newH = round(h * scale);
            newW = max(1, newW);
            newH = max(1, newH);

            resizedImg = subpixel_resize(img, [newH, newW], interpMethod);

            finalImg = zeros(TARGET_HEIGHT, TARGET_WIDTH, c, 'uint8');
            yOff = floor((TARGET_HEIGHT - newH) / 2);
            xOff = floor((TARGET_WIDTH  - newW) / 2);
            finalImg(yOff+1:yOff+newH, xOff+1:xOff+newW, :) = resizedImg;

        case 'stretch'
            finalImg = subpixel_resize(img, [TARGET_HEIGHT, TARGET_WIDTH], interpMethod);

        case 'crop'
            scale = max(TARGET_WIDTH / w, TARGET_HEIGHT / h);
            newW = round(w * scale);
            newH = round(h * scale);
            newW = max(1, newW);
            newH = max(1, newH);

            resizedImg = subpixel_resize(img, [newH, newW], interpMethod);

            yOff = floor((newH - TARGET_HEIGHT) / 2);
            xOff = floor((newW - TARGET_WIDTH)  / 2);
            finalImg = resizedImg(yOff+1:yOff+TARGET_HEIGHT, xOff+1:xOff+TARGET_WIDTH, :);
    end

    outPath = fullfile(dstFolder, imgFiles(i).name);
    imwrite(finalImg, outPath);
    fprintf('  -> 已保存: %s\n', outPath);
end

fprintf('\n全部完成！共处理 %d 张图片。\n', totalCount);


%% ======================================================================
%  亚像素插值缩放函数
%  基于三次卷积（Catmull-Rom）核实现，支持亚像素精度的坐标映射
% ======================================================================
function outImg = subpixel_resize(img, targetSize, method)
    [h, w, c] = size(img);
    tH = targetSize(1);
    tW = targetSize(2);

    sY = h / tH;
    sX = w / tW;

    [gridX, gridY] = meshgrid(0:tW-1, 0:tH-1);
    srcX = (gridX + 0.5) * sX - 0.5;
    srcY = (gridY + 0.5) * sY - 0.5;

    srcX = max(0, min(w - 1 - eps, srcX));
    srcY = max(0, min(h - 1 - eps, srcY));

    imgD = double(img);
    outD = zeros(tH, tW, c);

    for ch = 1:c
        switch method
            case 'bicubic'
                outD(:, :, ch) = bicubic_interp(imgD(:, :, ch), srcX, srcY);
            case 'bilinear'
                outD(:, :, ch) = bilinear_interp(imgD(:, :, ch), srcX, srcY);
            case 'nearest'
                outD(:, :, ch) = nearest_interp(imgD(:, :, ch), srcX, srcY);
        end
    end

    outImg = uint8(max(0, min(255, round(outD))));
end


%% ----------------------------------------------------------------------
%  双三次插值（亚像素插值，Catmull-Rom 核，a = -0.5）
%  使用 4x4 邻域像素进行三次卷积，实现亚像素位置的高精度插值
% ----------------------------------------------------------------------
function out = bicubic_interp(ch, srcX, srcY)
    [h, w] = size(ch);
    xI = floor(srcX);
    yI = floor(srcY);
    xF = srcX - xI;
    yF = srcY - yI;

    xI = xI - 1;
    yI = yI - 1;

    out = zeros(size(srcX));

    for m = 0:3
        for n = 0:3
            xi = xI + n;
            yi = yI + m;
            xi = max(0, min(w - 1, xi));
            yi = max(0, min(h - 1, yi));
            wx = cubic_kernel(n - 1 - xF);
            wy = cubic_kernel(m - 1 - yF);
            idx = xi * h + yi + 1;
            out = out + wx .* wy .* ch(idx);
        end
    end
end

function w = cubic_kernel(t)
    t = abs(t);
    a = -0.5;
    w = zeros(size(t));
    m1 = t <= 1;
    w(m1) = ((a + 2) * t(m1).^3) - ((a + 3) * t(m1).^2) + 1;
    m2 = (t > 1) & (t <= 2);
    w(m2) = a * t(m2).^3 - 5*a * t(m2).^2 + 8*a * t(m2) - 4*a;
end


%% ----------------------------------------------------------------------
%  双线性插值
% ----------------------------------------------------------------------
function out = bilinear_interp(ch, srcX, srcY)
    [h, w] = size(ch);
    xI = floor(srcX);
    yI = floor(srcY);
    xF = srcX - xI;
    yF = srcY - yI;

    x0 = max(0, min(w - 1, xI));
    x1 = max(0, min(w - 1, xI + 1));
    y0 = max(0, min(h - 1, yI));
    y1 = max(0, min(h - 1, yI + 1));

    i00 = x0 * h + y0 + 1;
    i10 = x1 * h + y0 + 1;
    i01 = x0 * h + y1 + 1;
    i11 = x1 * h + y1 + 1;

    c00 = ch(i00); c10 = ch(i10);
    c01 = ch(i01); c11 = ch(i11);

    out = (1 - yF) .* ((1 - xF) .* c00 + xF .* c10) ...
          +    yF  .* ((1 - xF) .* c01 + xF .* c11);
end


%% ----------------------------------------------------------------------
%  最近邻插值
% ----------------------------------------------------------------------
function out = nearest_interp(ch, srcX, srcY)
    [h, w] = size(ch);
    xi = max(0, min(w - 1, round(srcX)));
    yi = max(0, min(h - 1, round(srcY)));
    idx = xi * h + yi + 1;
    out = ch(idx);
end
