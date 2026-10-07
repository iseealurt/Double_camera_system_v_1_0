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

%% 3. 获取图片文件
imgTypes = {'*.jpg','*.jpeg','*.png','*.bmp','*.tif'};
imgFiles = [];

for i = 1:length(imgTypes)
    imgFiles = [imgFiles; dir(fullfile(srcFolder, imgTypes{i}))];
end

if isempty(imgFiles)
    error('源文件夹中没有图片文件');
end

%% 4. 检查是否存在符合条件的图片（640x480灰度）
validFlag = false;

for i = 1:length(imgFiles)
    imgPath = fullfile(srcFolder, imgFiles(i).name);
    img = imread(imgPath);

    % 判断灰度图
    if ndims(img) ~= 2
        continue;
    end

    [h, w] = size(img);

    if h == 480 && w == 640
        validFlag = true;
        break;
    end
end

if ~validFlag
    error('没有找到640x480的灰度图片，任务终止');
end

%% 5. 处理图片
for i = 1:length(imgFiles)
    imgPath = fullfile(srcFolder, imgFiles(i).name);
    img = imread(imgPath);

    % 跳过非灰度或非640x480
    if ndims(img) ~= 2
        continue;
    end

    [h, w] = size(img);
    if ~(h == 480 && w == 640)
        continue;
    end

    img = double(img);

    % 每个像素对应3字节（24bit）
    censusData = zeros(h, w, 3, 'uint8');

    %% 7. Census变换（与FPGA Verilog代码1:1精确对应）
    % FPGA位序: {p11,p12,p13,p14,p15, p21,p22,p23,p24,p25, p31,p32,p34,p35, p41,p42,p43,p44,p45, p51,p52,p53,p54,p55}
    % p11 = MSB (bit23), p55 = LSB (bit0)
    
    disp('  使用与FPGA 1:1精确对应的位序 (邻域 > 中心 → 1)');
    
    for y = 1:h
        for x = 1:w

            % 边界处理（2像素边缘）
            if y <= 2 || y >= h-1 || x <= 2 || x >= w-1
                censusVal = uint32(0);
            else
                center = img(y, x);
                
                % 5x5邻域像素命名 (p[行][列], 左上为p11, p33=center跳过)
                p11 = img(y-2, x-2);  p12 = img(y-2, x-1);  p13 = img(y-2, x);    p14 = img(y-2, x+1);  p15 = img(y-2, x+2);
                p21 = img(y-1, x-2);  p22 = img(y-1, x-1);  p23 = img(y-1, x);    p24 = img(y-1, x+1);  p25 = img(y-1, x+2);
                p31 = img(y,   x-2);  p32 = img(y,   x-1);  p34 = img(y,   x+1);  p35 = img(y,   x+2);
                p41 = img(y+1, x-2);  p42 = img(y+1, x-1);  p43 = img(y+1, x);    p44 = img(y+1, x+1);  p45 = img(y+1, x+2);
                p51 = img(y+2, x-2);  p52 = img(y+2, x-1);  p53 = img(y+2, x);    p54 = img(y+2, x+1);  p55 = img(y+2, x+2);
                
                % ==============================================
                % 1:1 精确对应 FPGA 源码 census_5x5.v 第160行
                % ==============================================
                % 【已修正】根据matrix_5x5.v FIFO级联顺序验证:
                % FPGA matrix_p1行 = 最上面一行 = Matlab p1行 (y-2)
                % FPGA matrix_p2行 = 上面第二行 = Matlab p2行 (y-1)
                % FPGA matrix_p4行 = 下面第二行 = Matlab p4行 (y+1)
                % FPGA matrix_p5行 = 最下面一行 = Matlab p5行 (y+2)
                % 每行内部: pX1=左, pX5=右, 顺序不变
                % 比较运算符: > (与FPGA完全一致)
                censusVal = ...
                    bitshift(uint32(p11 > center), 23) + ...  % FPGA:p11 = Matlab:p11 (y-2,x-2)
                    bitshift(uint32(p12 > center), 22) + ...  % FPGA:p12 = Matlab:p12 (y-2,x-1)
                    bitshift(uint32(p13 > center), 21) + ...  % FPGA:p13 = Matlab:p13 (y-2,x)
                    bitshift(uint32(p14 > center), 20) + ...  % FPGA:p14 = Matlab:p14 (y-2,x+1)
                    bitshift(uint32(p15 > center), 19) + ...  % FPGA:p15 = Matlab:p15 (y-2,x+2)
                    bitshift(uint32(p21 > center), 18) + ...  % FPGA:p21 = Matlab:p21 (y-1,x-2)
                    bitshift(uint32(p22 > center), 17) + ...  % FPGA:p22 = Matlab:p22 (y-1,x-1)
                    bitshift(uint32(p23 > center), 16) + ...  % FPGA:p23 = Matlab:p23 (y-1,x)
                    bitshift(uint32(p24 > center), 15) + ...  % FPGA:p24 = Matlab:p24 (y-1,x+1)
                    bitshift(uint32(p25 > center), 14) + ...  % FPGA:p25 = Matlab:p25 (y-1,x+2)
                    bitshift(uint32(p31 > center), 13) + ...  % FPGA:p31 = Matlab:p31 (y,x-2)
                    bitshift(uint32(p32 > center), 12) + ...  % FPGA:p32 = Matlab:p32 (y,x-1)
                    bitshift(uint32(p34 > center), 11) + ...  % FPGA:p34 = Matlab:p34 (y,x+1)
                    bitshift(uint32(p35 > center), 10) + ...  % FPGA:p35 = Matlab:p35 (y,x+2)
                    bitshift(uint32(p41 > center),  9) + ...  % FPGA:p41 = Matlab:p41 (y+1,x-2)
                    bitshift(uint32(p42 > center),  8) + ...  % FPGA:p42 = Matlab:p42 (y+1,x-1)
                    bitshift(uint32(p43 > center),  7) + ...  % FPGA:p43 = Matlab:p43 (y+1,x)
                    bitshift(uint32(p44 > center),  6) + ...  % FPGA:p44 = Matlab:p44 (y+1,x+1)
                    bitshift(uint32(p45 > center),  5) + ...  % FPGA:p45 = Matlab:p45 (y+1,x+2)
                    bitshift(uint32(p51 > center),  4) + ...  % FPGA:p51 = Matlab:p51 (y+2,x-2)
                    bitshift(uint32(p52 > center),  3) + ...  % FPGA:p52 = Matlab:p52 (y+2,x-1)
                    bitshift(uint32(p53 > center),  2) + ...  % FPGA:p53 = Matlab:p53 (y+2,x)
                    bitshift(uint32(p54 > center),  1) + ...  % FPGA:p54 = Matlab:p54 (y+2,x+1)
                    uint32(p55 > center);                     % FPGA:p55 = Matlab:p55 (y+2,x+2)
            end

            % 拆成3字节（高字节在前，与FPGA一致）
            censusData(y, x, 1) = bitand(bitshift(censusVal, -16), 255);
            censusData(y, x, 2) = bitand(bitshift(censusVal, -8), 255);
            censusData(y, x, 3) = bitand(censusVal, 255);
        end
    end

    %% 8. 写入.dat文件（ASCII十六进制空格分隔，与FPGA输出格式100%一致）
    outName = [imgFiles(i).name, '.dat'];
    outPath = fullfile(dstFolder, outName);

    fid = fopen(outPath, 'w');
    if fid == -1
        error('无法创建输出文件');
    end

    disp('  输出格式: ASCII十六进制 空格分隔（与FPGA完全一致）');

    % 写入5字节标准文件头
    DATA_TYPE_CENSUS = 2;
    header = [bitshift(w, -8), bitand(w, 255), ...
              bitshift(h, -8), bitand(h, 255), ...
              DATA_TYPE_CENSUS];
    
    for b = 1:length(header)
        fprintf(fid, '%02X ', header(b));
    end

    % 按行展开，每像素3字节
    for y = 1:h
        for x = 1:w
            fprintf(fid, '%02X ', censusData(y,x,1));
            fprintf(fid, '%02X ', censusData(y,x,2));
            fprintf(fid, '%02X ', censusData(y,x,3));
        end
    end

    fclose(fid);
end

disp('任务完成！');