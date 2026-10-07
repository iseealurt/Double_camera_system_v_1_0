clc;
clear;

%% 参数
IMG_WIDTH  = 640;
IMG_HEIGHT = 480;

%% 1. 选择源文件夹
srcFolder = uigetdir('', '请选择源文件夹');
if isequal(srcFolder, 0)
    disp('未选择源文件夹，程序结束。');
    return;
end

%% 2. 选择输出文件夹
dstFolder = uigetdir('', '请选择输出文件夹');
if isequal(dstFolder, 0)
    disp('未选择输出文件夹，程序结束。');
    return;
end

%% 3. 搜索图片
imgTypes = {'*.jpg','*.jpeg','*.png','*.bmp','*.tif','*.tiff'};
imgFiles = [];
for k = 1:numel(imgTypes)
    imgFiles = [imgFiles; dir(fullfile(srcFolder, imgTypes{k}))]; %#ok<AGROW>
end

if isempty(imgFiles)
    error('源文件夹中没有图片文件。');
end

%% 4. 检查是否存在合法图片：640x480灰度
validFlag = false;
for k = 1:numel(imgFiles)
    imgPath = fullfile(srcFolder, imgFiles(k).name);
    img = imread(imgPath);

    if ndims(img) ~= 2
        continue;
    end

    [h, w] = size(img);
    if h == IMG_HEIGHT && w == IMG_WIDTH
        validFlag = true;
        break;
    end
end

if ~validFlag
    error('源文件夹内没有640x480灰度图片，任务终止。');
end

%% 5. 构造7x7窗口偏移，去掉中心点，共48个
offsets = zeros(48, 2);
idx = 1;
for dy = -3:3
    for dx = -3:3
        if ~(dy == 0 && dx == 0)
            offsets(idx, :) = [dy, dx];
            idx = idx + 1;
        end
    end
end

%% 6. 逐图处理
for k = 1:numel(imgFiles)
    imgPath = fullfile(srcFolder, imgFiles(k).name);
    img = imread(imgPath);

    % 非灰度跳过
    if ndims(img) ~= 2
        continue;
    end

    [h, w] = size(img);
    if h ~= IMG_HEIGHT || w ~= IMG_WIDTH
        continue;
    end

    img = double(img);

    % 每像素 48bit -> 6字节
    censusBytes = zeros(IMG_HEIGHT, IMG_WIDTH, 6, 'uint8');

    for y = 1:IMG_HEIGHT
        for x = 1:IMG_WIDTH

            % 边缘3像素直接置0
            if y <= 3 || y >= IMG_HEIGHT-2 || x <= 3 || x >= IMG_WIDTH-2
                censusVal = uint64(0);
            else
                centerVal = img(y, x);
                censusVal = uint64(0);

                for t = 1:48
                    ny = y + offsets(t, 1);
                    nx = x + offsets(t, 2);

                    censusVal = bitshift(censusVal, 1);

                    if img(ny, nx) > centerVal
                        censusVal = bitor(censusVal, uint64(1));
                    end
                end
            end

            % 拆成6字节，高字节在前
            censusBytes(y, x, 1) = uint8(bitand(bitshift(censusVal, -40), uint64(255)));
            censusBytes(y, x, 2) = uint8(bitand(bitshift(censusVal, -32), uint64(255)));
            censusBytes(y, x, 3) = uint8(bitand(bitshift(censusVal, -24), uint64(255)));
            censusBytes(y, x, 4) = uint8(bitand(bitshift(censusVal, -16), uint64(255)));
            censusBytes(y, x, 5) = uint8(bitand(bitshift(censusVal, -8 ), uint64(255)));
            censusBytes(y, x, 6) = uint8(bitand(censusVal, uint64(255)));
        end
    end

    % 输出文件名：原文件名.dat
    outName = [imgFiles(k).name, '.dat'];
    outPath = fullfile(dstFolder, outName);

    fid = fopen(outPath, 'wb');
    if fid == -1
        error('无法创建输出文件：%s', outPath);
    end

    % 写入5字节标准文件头（与FPGA输出格式一致）
    DATA_TYPE_CENSUS = 2;
    fwrite(fid, uint8(bitshift(IMG_WIDTH, -8)), 'uint8');   % 宽度高8位
    fwrite(fid, uint8(bitand(IMG_WIDTH, 255)), 'uint8');    % 宽度低8位
    fwrite(fid, uint8(bitshift(IMG_HEIGHT, -8)), 'uint8');  % 高度高8位
    fwrite(fid, uint8(bitand(IMG_HEIGHT, 255)), 'uint8');   % 高度低8位
    fwrite(fid, uint8(DATA_TYPE_CENSUS), 'uint8');          % 数据类型

    % 按VESA光栅顺序写出
    for y = 1:IMG_HEIGHT
        for x = 1:IMG_WIDTH
            fwrite(fid, squeeze(censusBytes(y, x, :)), 'uint8');
        end
    end

    fclose(fid);
    fprintf('已生成: %s\n', outPath);
end

disp('7x7 Census 变换完成。');