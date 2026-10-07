clc;
clear;

IMG_WIDTH  = 640;
IMG_HEIGHT = 480;
MAX_DISP   = 40;

P1 = 10;
P2 = 60;

UNI_TH = 5;   % 唯一性阈值
LR_TH  = 1;   % 左右一致性阈值

%% === 读取数据 ===
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

%% === 转换 census ===
leftData  = reshape(leftData, 3, [])';
rightData = reshape(rightData, 3, [])';

leftCensus  = uint32(leftData(:,1))*65536 + uint32(leftData(:,2))*256 + uint32(leftData(:,3));
rightCensus = uint32(rightData(:,1))*65536 + uint32(rightData(:,2))*256 + uint32(rightData(:,3));

leftCensus  = reshape(leftCensus,  IMG_WIDTH, IMG_HEIGHT)';
rightCensus = reshape(rightCensus, IMG_WIDTH, IMG_HEIGHT)';

%% === 计算左右视差 ===
dispL = zeros(IMG_HEIGHT, IMG_WIDTH);
dispR = zeros(IMG_HEIGHT, IMG_WIDTH);

for dir = 1:2
    
    if dir == 1
        ref = rightCensus;  tgt = leftCensus;
        dispMap = dispL;
    else
        ref = leftCensus;   tgt = rightCensus;
        dispMap = dispR;
    end
    
    for y = 1:IMG_HEIGHT
        
        Lr_lr = zeros(IMG_WIDTH, MAX_DISP);
        Lr_rl = zeros(IMG_WIDTH, MAX_DISP);
        
        %% → 路径
        Lr_prev = zeros(1, MAX_DISP);
        for x = 1:IMG_WIDTH
            
            cost = zeros(1, MAX_DISP);
            for d = 0:MAX_DISP-1
                if x-d >= 1
                    xorv = bitxor(tgt(y,x-d), ref(y,x));
                    cost(d+1) = sum(bitget(xorv,1:24));
                else
                    cost(d+1) = 24;
                end
            end
            
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
        
        %% ← 路径
        Lr_prev = zeros(1, MAX_DISP);
        for x = IMG_WIDTH:-1:1
            
            cost = zeros(1, MAX_DISP);
            for d = 0:MAX_DISP-1
                if x-d >= 1
                    xorv = bitxor(tgt(y,x-d), ref(y,x));
                    cost(d+1) = sum(bitget(xorv,1:24));
                else
                    cost(d+1) = 24;
                end
            end
            
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
        
        %% WTA + 唯一性
        for x = 1:IMG_WIDTH
            
            S = Lr_lr(x,:) + Lr_rl(x,:);
            
            [min1, idx1] = min(S);
            S(idx1) = inf;
            min2 = min(S);
            
            if (min2 - min1) < UNI_TH
                dispMap(y,x) = -1; % 无效
            else
                dispMap(y,x) = idx1 - 1;
            end
        end
    end
    
    if dir == 1
        dispL = dispMap;
    else
        dispR = dispMap;
    end
end

%% === 左右一致性检测 ===
finalDisp = zeros(IMG_HEIGHT, IMG_WIDTH);

for y = 1:IMG_HEIGHT
    for x = 1:IMG_WIDTH
        
        d = dispL(y,x);
        
        if d <= 0 || x-d < 1
            continue;
        end
        
        d2 = dispR(y, x-d);
        
        if abs(d - d2) <= LR_TH
            finalDisp(y,x) = d;
        else
            finalDisp(y,x) = 0;
        end
    end
end

%% === 中值滤波 ===
finalDisp = medfilt2(finalDisp, [3 3]);

%% === 保存 ===
outPath = fullfile(outFolder, 'disp_final.png');
imwrite(uint8(finalDisp * (255/MAX_DISP)), outPath);

disp('雪花噪声优化完成！');