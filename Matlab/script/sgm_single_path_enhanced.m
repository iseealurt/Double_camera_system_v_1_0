clc;
clear;

IMG_WIDTH  = 640;
IMG_HEIGHT = 480;
MAX_DISP   = 40;

P1 = 4;
P2 = 16;

%% === 读取数据（和你原来一样） ===
[leftFile, path1] = uigetfile('*.dat', '选择左目census');
if isequal(leftFile,0), return; end

[rightFile, path2] = uigetfile('*.dat', '选择右目census');
if isequal(rightFile,0), return; end

leftPath  = fullfile(path1, leftFile);
rightPath = fullfile(path2, rightFile);

outFolder = uigetdir('', '选择输出文件夹');
if outFolder == 0, return; end

fid = fopen(leftPath, 'rb');
leftData = fread(fid, 'uint8'); fclose(fid);

fid = fopen(rightPath, 'rb');
rightData = fread(fid, 'uint8'); fclose(fid);

expectedSize = IMG_WIDTH * IMG_HEIGHT * 3;
if length(leftData) ~= expectedSize
    error('尺寸错误');
end

%% === 转换为 census ===
leftData  = reshape(leftData, 3, [])';
rightData = reshape(rightData, 3, [])';

leftCensus  = uint32(leftData(:,1))*65536 + uint32(leftData(:,2))*256 + uint32(leftData(:,3));
rightCensus = uint32(rightData(:,1))*65536 + uint32(rightData(:,2))*256 + uint32(rightData(:,3));

leftCensus  = reshape(leftCensus,  IMG_WIDTH, IMG_HEIGHT)';
rightCensus = reshape(rightCensus, IMG_WIDTH, IMG_HEIGHT)';

%% === 输出 ===
dispMap = zeros(IMG_HEIGHT, IMG_WIDTH, 'uint8');

%% =====================================================
%% 主循环（逐行）
%% =====================================================
for y = 1:IMG_HEIGHT
    
    %% ========= 路径1：左 → 右 =========
    Lr_lr = zeros(IMG_WIDTH, MAX_DISP);
    Lr_prev = zeros(1, MAX_DISP);
    
    for x = 1:IMG_WIDTH
        
        % cost
        cost = zeros(1, MAX_DISP);
        for d = 0:MAX_DISP-1
            if x-d >= 1
                xorv = bitxor(leftCensus(y,x-d), rightCensus(y,x));
                cost(d+1) = sum(bitget(xorv,1:24));
            else
                cost(d+1) = 24;
            end
        end
        
        % SGM
        Lr_curr = zeros(1, MAX_DISP);
        min_prev = min(Lr_prev);
        
        for d = 1:MAX_DISP
            
            l1 = Lr_prev(d);
            l2 = (d>1)* (Lr_prev(max(d-1,1)) + P1) + (d==1)*inf;
            l3 = (d<MAX_DISP)* (Lr_prev(min(d+1,MAX_DISP)) + P1) + (d==MAX_DISP)*inf;
            l4 = min_prev + P2;
            
            Lr_curr(d) = cost(d) + min([l1,l2,l3,l4]) - min_prev;
        end
        
        Lr_lr(x,:) = Lr_curr;
        Lr_prev = Lr_curr;
    end
    
    %% ========= 路径2：右 → 左 =========
    Lr_rl = zeros(IMG_WIDTH, MAX_DISP);
    Lr_prev = zeros(1, MAX_DISP);
    
    for x = IMG_WIDTH:-1:1
        
        % cost
        cost = zeros(1, MAX_DISP);
        for d = 0:MAX_DISP-1
            if x-d >= 1
                xorv = bitxor(leftCensus(y,x-d), rightCensus(y,x));
                cost(d+1) = sum(bitget(xorv,1:24));
            else
                cost(d+1) = 24;
            end
        end
        
        % SGM
        Lr_curr = zeros(1, MAX_DISP);
        min_prev = min(Lr_prev);
        
        for d = 1:MAX_DISP
            
            l1 = Lr_prev(d);
            l2 = (d>1)* (Lr_prev(max(d-1,1)) + P1) + (d==1)*inf;
            l3 = (d<MAX_DISP)* (Lr_prev(min(d+1,MAX_DISP)) + P1) + (d==MAX_DISP)*inf;
            l4 = min_prev + P2;
            
            Lr_curr(d) = cost(d) + min([l1,l2,l3,l4]) - min_prev;
        end
        
        Lr_rl(x,:) = Lr_curr;
        Lr_prev = Lr_curr;
    end
    
    %% ========= 融合 + WTA =========
    for x = 1:IMG_WIDTH
        
        S = Lr_lr(x,:) + Lr_rl(x,:);
        [~, best_d] = min(S);
        
        dispMap(y,x) = best_d - 1;
    end
end

%% 保存
outPath = fullfile(outFolder, 'disparity_dual_path.png');
imwrite(uint8(dispMap * (255/MAX_DISP)), outPath);

disp('双路径SGM完成！');