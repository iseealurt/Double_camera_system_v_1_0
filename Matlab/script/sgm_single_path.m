clc;
clear;

IMG_WIDTH  = 640;
IMG_HEIGHT = 480;
MAX_DISP   = 40;
P1 = 2;
P2 = 8;

%% 1. 选择左右dat文件
[leftFile, path1] = uigetfile('*.dat', '选择左目census');
if isequal(leftFile,0), return; end

[rightFile, path2] = uigetfile('*.dat', '选择右目census');
if isequal(rightFile,0), return; end

leftPath  = fullfile(path1, leftFile);
rightPath = fullfile(path2, rightFile);

%% 2. 选择输出文件夹
outFolder = uigetdir('', '选择输出文件夹');
if outFolder == 0, return; end

%% 3. 读取dat文件
fid = fopen(leftPath, 'rb');
leftData = fread(fid, 'uint8');
fclose(fid);

fid = fopen(rightPath, 'rb');
rightData = fread(fid, 'uint8');
fclose(fid);

% 校验大小
expectedSize = IMG_WIDTH * IMG_HEIGHT * 3;
if length(leftData) ~= expectedSize || length(rightData) ~= expectedSize
    error('dat文件格式错误（尺寸不匹配）');
end

%% 4. 转换为24bit census
leftData  = reshape(leftData, 3, [])';
rightData = reshape(rightData, 3, [])';

leftCensus  = uint32(leftData(:,1))*65536 + uint32(leftData(:,2))*256 + uint32(leftData(:,3));
rightCensus = uint32(rightData(:,1))*65536 + uint32(rightData(:,2))*256 + uint32(rightData(:,3));

leftCensus  = reshape(leftCensus,  IMG_WIDTH, IMG_HEIGHT)';
rightCensus = reshape(rightCensus, IMG_WIDTH, IMG_HEIGHT)';

%% 5. 输出视差图
dispMap = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');

%% 6. SGM主循环（逐行）
for y = 1:IMG_HEIGHT
    
    Lr_prev = zeros(1, MAX_DISP);
    
    for x = 1:IMG_WIDTH
        
        % ===== 1. 计算匹配代价 =====
        cost = zeros(1, MAX_DISP);
        
        for d = 0:MAX_DISP-1
            if x-d >= 1
                xorv = bitxor(leftCensus(y,x-d), rightCensus(y,x));
                cost(d+1) = sum(bitget(xorv,1:24)); % Hamming
            else
                cost(d+1) = 24; % 最大代价
            end
        end
        
        % ===== 2. SGM聚合 =====
        Lr_curr = zeros(1, MAX_DISP);
        min_prev = min(Lr_prev);
        
        for d = 1:MAX_DISP
            
            l1 = Lr_prev(d);
            
            if d > 1
                l2 = Lr_prev(d-1) + P1;
            else
                l2 = inf;
            end
            
            if d < MAX_DISP
                l3 = Lr_prev(d+1) + P1;
            else
                l3 = inf;
            end
            
            l4 = min_prev + P2;
            
            Lr_curr(d) = cost(d) + min([l1,l2,l3,l4]) - min_prev;
        end
        
        % ===== 3. WTA =====
        [~, best_d] = min(Lr_curr);
        dispMap(y,x) = best_d - 1;
        
        % 更新
        Lr_prev = Lr_curr;
    end
end

%% 7. 保存结果
outPath = fullfile(outFolder, 'disparity.png');
imwrite(uint8(dispMap * (255/MAX_DISP)), outPath);

disp('处理完成！');