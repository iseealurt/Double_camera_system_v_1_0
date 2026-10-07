clc;
clear;
close all;

%% 参数
IMG_WIDTH  = 640;
IMG_HEIGHT = 480;
BYTES_PER_PIXEL = 3;
EXPECTED_SIZE = IMG_WIDTH * IMG_HEIGHT * BYTES_PER_PIXEL;

%% 1. 选择输入 dat 文件
[fileName, filePath] = uigetfile('*.dat', '请选择 census dat 文件');
if isequal(fileName, 0)
    disp('未选择文件，程序结束。');
    return;
end

inFile = fullfile(filePath, fileName);

%% 2. 选择输出文件夹
outFolder = uigetdir('', '请选择输出文件夹');
if isequal(outFolder, 0)
    disp('未选择输出文件夹，程序结束。');
    return;
end

%% 3. 读取 dat 文件
fid = fopen(inFile, 'rb');
if fid == -1
    error('无法打开输入文件。');
end

rawData = fread(fid, inf, 'uint8=>uint8');
fclose(fid);

%% 4. 文件格式检查
if numel(rawData) ~= EXPECTED_SIZE
    error('dat 文件格式错误：文件大小不是 640×480×3 字节。');
end

%% 5. 按每像素3字节重组
rawData = reshape(rawData, 3, []).';   % 每行对应一个像素的3字节

% 按高字节在前的方式拼成24bit
census24 = bitshift(uint32(rawData(:,1)), 16) + ...
           bitshift(uint32(rawData(:,2)), 8)  + ...
           uint32(rawData(:,3));

% 还原成 480x640 图像
censusImg = reshape(census24, IMG_WIDTH, IMG_HEIGHT).';
% 注意这里转置是因为原 dat 是按光栅顺序写出的

%% 6. 可视化方式1：直接取低8位
vis_low8 = uint8(bitand(censusImg, uint32(255)));

%% 7. 可视化方式2：直接取中8位
vis_mid8 = uint8(bitand(bitshift(censusImg, -8), uint32(255)));

%% 8. 可视化方式3：直接取高8位
vis_high8 = uint8(bitand(bitshift(censusImg, -16), uint32(255)));

%% 9. 可视化方式4：24bit统计“1”的个数（更推荐）
bitCountImg = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');

for b = 1:24
    bitCountImg = bitCountImg + uint8(bitget(censusImg, b));
end

% 拉伸到 0~255 便于显示
vis_popcount = uint8(double(bitCountImg) / 24 * 255);

%% 10. 可视化方式5：是否为0的掩膜图
vis_zero_mask = uint8(censusImg == 0) * 255;

%% 11. 显示结果
figure('Name', 'Census Visualization', 'NumberTitle', 'off');

subplot(2,3,1);
imshow(vis_low8);
title('Low 8 bits');

subplot(2,3,2);
imshow(vis_mid8);
title('Middle 8 bits');

subplot(2,3,3);
imshow(vis_high8);
title('High 8 bits');

subplot(2,3,4);
imshow(vis_popcount);
title('Popcount Visualization');

subplot(2,3,5);
imshow(vis_zero_mask);
title('Zero Mask');

subplot(2,3,6);
histogram(bitCountImg(:), 0:24);
title('Popcount Histogram');
xlabel('Number of 1 bits');
ylabel('Pixel Count');

%% 12. 保存图片
[~, baseName, ~] = fileparts(fileName);

imwrite(vis_low8,      fullfile(outFolder, [baseName, '_low8.png']));
imwrite(vis_mid8,      fullfile(outFolder, [baseName, '_mid8.png']));
imwrite(vis_high8,     fullfile(outFolder, [baseName, '_high8.png']));
imwrite(vis_popcount,  fullfile(outFolder, [baseName, '_popcount.png']));
imwrite(vis_zero_mask, fullfile(outFolder, [baseName, '_zero_mask.png']));

disp('Census 可视化完成。');
disp(['结果已保存到: ', outFolder]);