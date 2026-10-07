%% fpga_sgm_census_repro.m
% 基于论文思路的 MATLAB 复现：
% 1) 输入左右目 census 序列 dat 文件（每 3 字节 = 1 像素 = 24-bit Census）
% 2) 计算 0~dmax-1 的 Hamming 初始代价
% 3) WTA 得到初始视差图
% 4) 用论文中的三点公式做亚像素插值，输出优化后视差图
%
% 论文依据：
% - Census 为 5x5 窗口生成 24bit 序列，并用 Hamming 距离作为初始代价
% - 视差优化使用 d0-1, d0, d0+1 的三点亚像素插值公式
%
% 说明：
% - 本脚本假设 dat 文件里只存 Census 结果，不再重新做 Census
% - dat 文件按行优先存储，3 字节表示 1 个像素
% - 采用左图为参考图，右图按 x-d 匹配
%
% 作者：ChatGPT

% ===================== 环境初始化 =====================
clear;      % 清空工作区所有变量，避免旧数据干扰
clc;        % 清空命令行窗口，便于查看新输出
close all;  % 关闭所有已打开的图像窗口

%% ===================== 1) 选择输入文件 =====================
% 弹出文件选择对话框，获取左目 Census 数据文件的路径和文件名
[leftName, leftPath] = uigetfile({'*.dat','DAT files (*.dat)'}, '选择左目 Census 序列文件');
% 检查用户是否点击了取消按钮
if isequal(leftName, 0)
    error('未选择左目文件，程序结束。');  % 抛出错误并终止执行
end
% 将路径和文件名拼接成完整的绝对路径
leftFile = fullfile(leftPath, leftName);

% 弹出文件选择对话框，获取右目 Census 数据文件
[rightName, rightPath] = uigetfile({'*.dat','DAT files (*.dat)'}, '选择右目 Census 序列文件');
if isequal(rightName, 0)
    error('未选择右目文件，程序结束。');
end
rightFile = fullfile(rightPath, rightName);

% 弹出目录选择对话框，选择结果输出文件夹
outDir = uigetdir(pwd, '选择输出文件夹');  % pwd 表示当前工作目录
if isequal(outDir, 0)
    error('未选择输出文件夹，程序结束。');
end

%% ===================== 2) 输入算法参数 =====================
prompt = { ...
    '图像宽度 Width:', ...
    '图像高度 Height:', ...
    '最大视差 dmax:', ...
    '无效代价 invalidCost（建议 24）:', ...
    'SGM P1 惩罚（视差变化1，建议15）:', ...
    'SGM P2 惩罚（视差跳变，建议120）:', ...
    '是否显示计算进度（1/0）:' ...
    };
dlgTitle = 'SGM 算法参数';
dims = [1 50];
defAns = {'640','480','80','24','15','120','1'};
answ = inputdlg(prompt, dlgTitle, dims, defAns);

if isempty(answ)
    error('未输入参数，程序结束。');
end

W = str2double(answ{1});
H = str2double(answ{2});
dmax = str2double(answ{3});
invalidCost = str2double(answ{4});
P1 = str2double(answ{5});
P2 = str2double(answ{6});
showProgress = logical(str2double(answ{7}));

% 参数合法性校验：检查是否为有效数值
assert(~isnan(W) && ~isnan(H) && ~isnan(dmax), '参数输入无效。');
% 参数范围校验：必须为正整数
assert(W > 0 && H > 0 && dmax > 0, 'Width/Height/dmax 必须为正数。');

% 在命令行输出确认参数设置
fprintf('参数：W=%d, H=%d, dmax=%d\n', W, H, dmax);

%% ===================== 3) 读取 dat 并解析为 uint32 Census 图 =====================
% 调用自定义函数读取左右目 Census 二进制数据
% 返回 H×W 的 uint32 矩阵，每个元素存储 24bit Census 特征
leftCensus  = read24bitDat(leftFile, W, H);
rightCensus = read24bitDat(rightFile, W, H);

%% ===================== 4) 计算初始代价体 C(y, x, d) =====================
% 代价体定义：C(y, x, d) = Hamming( left(y,x), right(y,x-d) )
% 物理意义：左图(y,x)像素与右图同一行、x-d 列像素的相似度
% 若 x-d < 1（视差过大超出图像边界），则代价置为 invalidCost
% 24bit Census -> Hamming 距离范围 0~24（0表示完全匹配，24表示完全不匹配）

% 预分配 3 维代价体内存：H 行 × W 列 × dmax 个视差级别
% 使用 uint8 节省内存（Hamming 距离 0~24 < 256）
costVol = zeros(H, W, dmax, 'uint8');

% 预计算 8bit 数的 1 的个数查找表（popcount / 汉明重量）
% 查表法比实时计算 bitcount 快 5~10 倍
% dec2bin(0:255) 生成 256×8 的二进制字符矩阵
% sum(=='1', 2) 对每行求和得到每个字节的 1 的个数
popLUT = uint8(sum(dec2bin(0:255) == '1', 2));

% 如果需要显示进度，创建等待条窗口
if showProgress
    hwb = waitbar(0, '正在计算 Hamming 初始代价体...');
end

% 遍历每个视差级别 d（0-based）
for d = 0:dmax-1
    % 根据当前视差 d，计算左右图的有效列范围
    if d == 0
        % 视差为 0 时，左右图所有列都参与计算
        xrL = 1:W;      % 左图有效列：全部 1~W
        xrR = 1:W;      % 右图有效列：全部 1~W
    else
        % 视差 d>0 时，左图从 d+1 列开始，右图到 W-d 列结束
        % 保证 x-d >= 1，避免数组越界
        xrL = (d+1):W;    % 左图有效列：d+1 ~ W
        xrR = 1:(W-d);    % 右图有效列：1 ~ W-d
    end

    % 初始化当前视差平面：先全部置为无效代价
    plane = uint8(ones(H, W) * invalidCost);

    % 如果有效列范围非空（d <= W-1），计算汉明距离
    if ~isempty(xrL)
        % Census 特征逐位异或：相同为 0，不同为 1
        % 异或结果中 1 的个数就是汉明距离
        xorVal = bitxor(leftCensus(:, xrL), rightCensus(:, xrR));

        % 24-bit popcount 拆分为 3 个 8-bit 字节分别查表再相加
        % bitand 提取对应字节，+1 是因为 MATLAB 数组索引从 1 开始
        b0 = bitand(xorVal, uint32(255));               % 提取低 8 位（字节 0）
        b1 = bitand(bitshift(xorVal, -8), uint32(255));  % 右移 8 位，提取字节 1
        b2 = bitand(bitshift(xorVal, -16), uint32(255)); % 右移 16 位，提取字节 2

        % 查表得到每个字节的 1 的个数，相加得到 24bit 的汉明距离
        ham = popLUT(double(b0)+1) + popLUT(double(b1)+1) + popLUT(double(b2)+1);
        % 将有效区域的汉明距离写入当前视差平面
        plane(:, xrL) = ham;
    end

    % 将当前视差平面存入代价体对应位置
    % 注意：MATLAB 数组索引从 1 开始，所以 d+1 对应视差 d
    costVol(:, :, d+1) = plane;

    % 更新进度条显示
    if showProgress
        waitbar((d+1)/dmax, hwb, sprintf('正在计算代价体... d = %d / %d', d, dmax-1));
    end
end

% 关闭进度条窗口
if showProgress
    close(hwb);
end

%% ===================== 4.5) SGM 4 路径代价聚合（核心补充） =====================
% -------------------------- 算法背景说明 --------------------------
% Hirschmüller 论文核心公式：沿每个路径 r 进行递推：
%   Lr(p,d) = C(p,d) 
%           + min(Lr(p-r,d), Lr(p-r,d-1)+P1, Lr(p-r,d+1)+P1, min_k Lr(p-r,k)+P2)
%           - min_k Lr(p-r,k)
% 物理意义：
%   - P1：视差变化 1 个像素的惩罚（鼓励平滑视差）
%   - P2：视差变化 >=2 个像素的惩罚（允许不连续，但加大惩罚）
%   - 最后减 min_k Lr(p-r,k)：防止数值溢出，不影响 WTA 结果
%
% FPGA 实现注意事项：
%   - 每个方向可独立并行计算，是 SGM 加速的关键
%   - 递推只依赖前一个像素的结果，适合流水线
%   - 4 路径是资源和效果的折中（8 路径更好但资源翻倍）

% ========== SGM 代价聚合开始 ==========
% FPGA 关键设计提示：
%   - P1/P2 已从参数对话框传入，可根据场景调节
%   - P1/P2 比值决定平滑程度：
%     P1/P2 越大，对视差不连续的惩罚越强，边缘越模糊
%     P2/P1 ≈ 8:1 是 Hirschmüller 论文推荐比例

% 将初始代价体转换为 single 类型，避免聚合过程中数值溢出
% uint8 范围 0~255，4 路径聚合后范围 0~1024
costVolSingle = single(costVol);

% 初始化聚合后代价体：S = L1 + L2 + L3 + L4（4 路径累加）
costVolAgg = zeros(H, W, dmax, 'single');

if showProgress
    hwb = waitbar(0, '正在进行 SGM 4 路径代价聚合...');
end

% ===================== 路径 1/4：左 → 右 扫描 =====================
% 递推方向：x 从 1 到 W，每列只依赖左边前一列的结果
L = zeros(H, W, dmax, 'single');
L(:, 1, :) = costVolSingle(:, 1, :);  % 第一列直接等于初始代价

for x = 2:W
    % 前一列 (x-1) 在所有视差下的代价最小值
    minPrev = min(L(:, x-1, :), [], 3);  % H×1 向量
    
    for d = 1:dmax
        % ========== 公式 4 项取最小值 ==========
        % term1 = L(p-r, d)         : 视差不变
        term1 = L(:, x-1, d);
        
        % term2 = L(p-r, d-1) + P1  : 视差减 1
        if d > 1
            term2 = L(:, x-1, d-1) + P1;
        else
            term2 = inf(H, 1, 'single');  % d=1 时 d-1=0 越界
        end
        
        % term3 = L(p-r, d+1) + P1  : 视差加 1
        if d < dmax
            term3 = L(:, x-1, d+1) + P1;
        else
            term3 = inf(H, 1, 'single');  % d=dmax 时 d+1 越界
        end
        
        % term4 = min_k L(p-r, k) + P2  : 视差任意跳变
        term4 = minPrev + P2;
        
        % 四项取最小，减去前一列最小值（数值归一化，防止溢出）
        minTerm = min( min(term1, term2), min(term3, term4) );
        L(:, x, d) = costVolSingle(:, x, d) + minTerm - minPrev;
    end
end
costVolAgg = costVolAgg + L;  % 累加到聚合代价体

if showProgress
    waitbar(0.25, hwb, 'SGM 聚合进度：左→右 完成 (1/4)');
end

% ===================== 路径 2/4：右 → 左 扫描 =====================
% 递推方向：x 从 W 到 1，每列只依赖右边后一列的结果
L = zeros(H, W, dmax, 'single');
L(:, W, :) = costVolSingle(:, W, :);  % 最后一列直接等于初始代价

for x = W-1:-1:1
    % 后一列 (x+1) 在所有视差下的代价最小值
    minPrev = min(L(:, x+1, :), [], 3);
    
    for d = 1:dmax
        term1 = L(:, x+1, d);                      % 视差不变
        
        if d > 1
            term2 = L(:, x+1, d-1) + P1;           % 视差减 1
        else
            term2 = inf(H, 1, 'single');
        end
        
        if d < dmax
            term3 = L(:, x+1, d+1) + P1;           % 视差加 1
        else
            term3 = inf(H, 1, 'single');
        end
        
        term4 = minPrev + P2;                       % 视差跳变
        
        minTerm = min( min(term1, term2), min(term3, term4) );
        L(:, x, d) = costVolSingle(:, x, d) + minTerm - minPrev;
    end
end
costVolAgg = costVolAgg + L;

if showProgress
    waitbar(0.5, hwb, 'SGM 聚合进度：右→左 完成 (2/4)');
end

% ===================== 路径 3/4：上 → 下 扫描 =====================
% 递推方向：y 从 1 到 H，每行只依赖上方前一行的结果
L = zeros(H, W, dmax, 'single');
L(1, :, :) = costVolSingle(1, :, :);  % 第一行直接等于初始代价

for y = 2:H
    % 上一行 (y-1) 在所有视差下的代价最小值
    minPrev = min(L(y-1, :, :), [], 3);
    
    for d = 1:dmax
        term1 = L(y-1, :, d);                      % 视差不变
        
        if d > 1
            term2 = L(y-1, :, d-1) + P1;           % 视差减 1
        else
            term2 = inf(1, W, 'single');
        end
        
        if d < dmax
            term3 = L(y-1, :, d+1) + P1;           % 视差加 1
        else
            term3 = inf(1, W, 'single');
        end
        
        term4 = minPrev + P2;                       % 视差跳变
        
        minTerm = min( min(term1, term2), min(term3, term4) );
        L(y, :, d) = costVolSingle(y, :, d) + minTerm - minPrev;
    end
end
costVolAgg = costVolAgg + L;

if showProgress
    waitbar(0.75, hwb, 'SGM 聚合进度：上→下 完成 (3/4)');
end

% ===================== 路径 4/4：下 → 上 扫描 =====================
% 递推方向：y 从 H 到 1，每行只依赖下方后一行的结果
L = zeros(H, W, dmax, 'single');
L(H, :, :) = costVolSingle(H, :, :);  % 最后一行直接等于初始代价

for y = H-1:-1:1
    % 下一行 (y+1) 在所有视差下的代价最小值
    minPrev = min(L(y+1, :, :), [], 3);
    
    for d = 1:dmax
        term1 = L(y+1, :, d);                      % 视差不变
        
        if d > 1
            term2 = L(y+1, :, d-1) + P1;           % 视差减 1
        else
            term2 = inf(1, W, 'single');
        end
        
        if d < dmax
            term3 = L(y+1, :, d+1) + P1;           % 视差加 1
        else
            term3 = inf(1, W, 'single');
        end
        
        term4 = minPrev + P2;                       % 视差跳变
        
        minTerm = min( min(term1, term2), min(term3, term4) );
        L(y, :, d) = costVolSingle(y, :, d) + minTerm - minPrev;
    end
end
costVolAgg = costVolAgg + L;

if showProgress
    close(hwb);
end

fprintf('SGM 代价聚合完成：4 路径，P1=%d, P2=%d\n', P1, P2);

%% ===================== 5) WTA：对比有无代价聚合的视差图 =====================
% ---------- 无代价聚合的原始视差图 ----------
[~, idxMinNoAgg] = min(costVol, [], 3);
dispNoAgg = single(idxMinNoAgg - 1);

% ---------- 经过 SGM 代价聚合的视差图 ----------
[~, idxMinAgg] = min(costVolAgg, [], 3);
dispAgg = single(idxMinAgg - 1);

%% ===================== 6) 亚像素插值：仅对聚合后视差进行 =====================
% 使用聚合后的代价体进行亚像素插值，精度更高
dispAggSub = dispAgg;

for y = 1:H
    for x = 1:W
        d0 = idxMinAgg(y, x) - 1;   % 聚合后的最优整数视差
        
        if d0 > 0 && d0 < (dmax - 1)
            % 使用聚合后的代价体进行插值
            C1 = single(costVolAgg(y, x, d0));
            C0 = single(costVolAgg(y, x, d0+1));
            C2 = single(costVolAgg(y, x, d0+2));
            
            denom = 2 * (C1 + C2 - C0);
            
            if abs(denom) > 1e-6
                dsub = single(d0) + (C1 - C2) / denom;
            else
                dsub = single(d0);
            end
            
            dsub = max(0, min(single(dmax-1), dsub));
            dispAggSub(y, x) = dsub;
        else
            dispAggSub(y, x) = single(d0);
        end
    end
end

% 中值滤波后处理
dispAggFinal = medfilt2(dispAggSub, [3 3], 'symmetric');

%% ===================== 7) 可视化：有无代价聚合的对比 =====================
imgNoAgg      = uint8(255 * mat2gray(dispNoAgg,      [0, dmax-1]));  % 原始 WTA 无聚合
imgAgg        = uint8(255 * mat2gray(dispAgg,        [0, dmax-1]));  % SGM 聚合后整数视差
imgAggSub     = uint8(255 * mat2gray(dispAggSub,     [0, dmax-1]));  % 聚合+亚像素插值
imgAggFinal   = uint8(255 * mat2gray(dispAggFinal,   [0, dmax-1]));  % 聚合+亚像素+中值滤波

% 2×2 对比显示
figure('Name','SGM 代价聚合效果对比','Color','w');
subplot(2,2,1); imshow(imgNoAgg);    
title('原始 WTA (无代价聚合) - 噪声极大');
subplot(2,2,2); imshow(imgAgg);     
title('SGM 4路径代价聚合 - 整数视差');
subplot(2,2,3); imshow(imgAggSub);  
title('SGM 聚合 + 亚像素插值');
subplot(2,2,4); imshow(imgAggFinal);
title(sprintf('SGM 聚合 + 亚像素 + 3×3中值 (P1=%d, P2=%d)', P1, P2));

% 保存 PNG 图像文件
imwrite(imgNoAgg,    fullfile(outDir, '01_no_aggregation_raw.png'));
imwrite(imgAgg,      fullfile(outDir, '02_sgm_4path_integer.png'));
imwrite(imgAggSub,   fullfile(outDir, '03_sgm_subpixel.png'));
imwrite(imgAggFinal, fullfile(outDir, '04_sgm_final_medfilt.png'));

% 保存 MATLAB 工作空间变量
save(fullfile(outDir, 'disparity_results.mat'), ...
    'dispNoAgg', 'dispAgg', 'dispAggSub', 'dispAggFinal', ...
    'costVol', 'costVolAgg', 'P1', 'P2', ...
    'W', 'H', 'dmax', 'invalidCost', ...
    'leftFile', 'rightFile', '-v7.3');

% ========== 保存运行参数说明文本文件 ==========
txtFile = fullfile(outDir, 'run_info.txt');
fid = fopen(txtFile, 'w');
fprintf(fid, '=== SGM 立体匹配算法运行参数 ===\n\n');
fprintf(fid, 'Left census file : %s\n', leftFile);
fprintf(fid, 'Right census file: %s\n', rightFile);
fprintf(fid, 'Width            : %d\n', W);
fprintf(fid, 'Height           : %d\n', H);
fprintf(fid, 'dmax             : %d\n', dmax);
fprintf(fid, 'invalidCost      : %d\n', invalidCost);
fprintf(fid, 'SGM P1 penalty   : %d\n', P1);
fprintf(fid, 'SGM P2 penalty   : %d\n', P2);
fprintf(fid, 'Aggregation paths: 4 (L->R, R->L, U->D, D->U)\n');
fprintf(fid, '\n=== 输出文件说明 ===\n');
fprintf(fid, '01_no_aggregation_raw.png    : 无代价聚合的原始 WTA 噪声图\n');
fprintf(fid, '02_sgm_4path_integer.png     : 4路径聚合后的整数视差图\n');
fprintf(fid, '03_sgm_subpixel.png          : 聚合+亚像素插值\n');
fprintf(fid, '04_sgm_final_medfilt.png     : 聚合+亚像素+3x3中值滤波(最终输出)\n');
fprintf(fid, 'disparity_results.mat        : MATLAB 原始数据\n');
fclose(fid);

% 命令行输出完成提示
fprintf('\n处理完成，结果已保存到：\n%s\n', outDir);

%% ===================== 本脚本用到的本地函数 =====================
% 读取 24bit Census 二进制 dat 文件
% 输入：filename - dat 文件路径，W/H - 图像宽高
% 输出：censusImg - H×W 的 uint32 矩阵，每个元素包含 24bit Census 特征
function censusImg = read24bitDat(filename, W, H)
    % 以二进制只读模式打开文件
    fid = fopen(filename, 'rb');
    if fid < 0
        error('无法打开文件：%s', filename);
    end

    % 一次性读取全部字节数据，数据类型 uint8
    raw = fread(fid, inf, 'uint8=>uint8');
    % 关闭文件句柄
    fclose(fid);

    % 校验文件大小是否符合预期
    expectedBytes = W * H * 3;  % 每个像素 3 字节存储
    if numel(raw) ~= expectedBytes
        error(['文件大小不匹配：%s\n' ...
               '期望字节数 = W*H*3 = %d，实际 = %d。\n' ...
               '请检查 Width/Height 或 dat 文件格式。'], ...
               filename, expectedBytes, numel(raw));
    end

    % 数据维度重整：
    % raw 是 3WH×1 的列向量 → 重整为 3×WH 矩阵 → 转置为 WH×3
    % 每行的 3 个元素对应一个像素的 3 个字节
    raw = reshape(raw, 3, []).';  % 结果维度：(W*H) × 3

    % 按 Little-Endian 字节序组装成 uint32：
    % raw(:,1) = 低字节，raw(:,2) = 中字节，raw(:,3) = 高字节
    val = uint32(raw(:,1)) + ...
          bitshift(uint32(raw(:,2)), 8) + ...
          bitshift(uint32(raw(:,3)), 16);

    % 重整为 H×W 的图像矩阵
    % 注意：MATLAB 按列存储，所以先 reshape 为 W×H 再转置，保证行优先
    censusImg = reshape(val, [W, H]).';
end
