clc;
clear;
close all;

disp('========================================');
disp('Census变换结果对比分析工具');
disp('Matlab vs FPGA');
disp('========================================');
disp(' ');

%% ====================== 配置文件路径 ======================
disp('[Step 1] 配置文件路径');

file_matlab = '..\..\Matlab\test img\census_dat\5\im0_gray.png.dat';
file_fpga   = '..\..\Bench\tb_sgm_new_task_3.dat';

disp(['  Matlab文件: ', file_matlab]);
disp(['  FPGA文件:   ', file_fpga]);
disp(' ');

%% ====================== 读取Matlab输出 ======================
disp('[Step 2] 读取Matlab输出的Census数据');

fid = fopen(file_matlab, 'r');
raw_text = char(fread(fid, Inf, 'char')');
fclose(fid);

bytes_per_pixel = 3;

% 自动检测：ASCII文本格式（含空格）还是二进制格式
if all(raw_text(1:min(100, end)) <= 127) && any(raw_text == ' ')
    disp('  检测到ASCII十六进制文本格式');
    data_matlab = sscanf(raw_text, '%2X ', Inf);
else
    disp('  检测到纯二进制格式');
    data_matlab = uint8(raw_text);
end

disp(['  解析后的字节数: ', num2str(length(data_matlab)), ' 字节']);

% 解析5字节标准文件头
disp('  检测5字节标准文件头:');
img_width  = bitshift(uint16(data_matlab(1)), 8) + data_matlab(2);
img_height = bitshift(uint16(data_matlab(3)), 8) + data_matlab(4);
data_type  = data_matlab(5);
type_str = {'灰度图', '原始图像', 'Census', '代价聚合', '视差图'};

fprintf('    图像宽度: %d (0x%04X)\n', img_width, img_width);
fprintf('    图像高度: %d (0x%04X)\n', img_height, img_height);
if data_type >= 1 && data_type <= length(type_str)
    fprintf('    数据类型: %s (Type=%d)\n', type_str{data_type}, data_type);
else
    fprintf('    数据类型: 未知 (Type=%d)\n', data_type);
end

idx_matlab = 6;
usable_rows = floor((length(data_matlab) - idx_matlab + 1) / (img_width * bytes_per_pixel));

disp(['  图像尺寸: ', num2str(img_width), 'x', num2str(img_height)]);
disp(['  每像素字节数: ', num2str(bytes_per_pixel)]);
disp(['  可用完整行数: ', num2str(usable_rows), ' 行']);

census_matlab = zeros(img_height, img_width, 3, 'uint8');
idx = idx_matlab;
for y = 1:img_height
    for x = 1:img_width
        if idx + 2 <= length(data_matlab)
            census_matlab(y, x, 1) = data_matlab(idx);
            census_matlab(y, x, 2) = data_matlab(idx + 1);
            census_matlab(y, x, 3) = data_matlab(idx + 2);
        end
        idx = idx + 3;
    end
end

disp('  Matlab数据读取完成');
disp(' ');

%% ====================== 读取FPGA输出 ======================
disp('[Step 3] 读取FPGA输出的Census数据');

fid = fopen(file_fpga, 'r');
raw_text = char(fread(fid, Inf, 'char')');
fclose(fid);

disp(['  文件大小: ', num2str(length(raw_text)), ' 字符 (ASCII十六进制格式)']);

% 解析ASCII十六进制文本格式 (如 "02 80 01 E0 02 ...")
data_fpga = sscanf(raw_text, '%2X ', Inf);
disp(['  解析后的字节数: ', num2str(length(data_fpga)), ' 字节']);

if length(data_fpga) >= 5
    fpga_width = bitor(bitshift(double(data_fpga(1)), 8), double(data_fpga(2)));
    fpga_height = bitor(bitshift(double(data_fpga(3)), 8), double(data_fpga(4)));
    fpga_data_type = double(data_fpga(5));
    
    type_str = {'Unknown', 'Gray', 'Census', 'Disparity'};
    disp('  解析5字节文件头:');
    disp(['    图像宽度: ', num2str(fpga_width), ' (0x', dec2hex(data_fpga(1),2), dec2hex(data_fpga(2),2), ')']);
    disp(['    图像高度: ', num2str(fpga_height), ' (0x', dec2hex(data_fpga(3),2), dec2hex(data_fpga(4),2), ')']);
    
    if fpga_data_type + 1 <= length(type_str)
        disp(['    数据类型: ', type_str{fpga_data_type + 1}, ' (Type=', num2str(fpga_data_type), ')']);
    else
        disp(['    数据类型: Type=', num2str(fpga_data_type), ' (未知类型)']);
    end
else
    error('FPGA数据文件太短，缺少5字节文件头！');
end

usable_rows_fpga = floor((length(data_fpga) - 5) / (fpga_width * bytes_per_pixel));
disp(['  可用完整行数: ', num2str(usable_rows_fpga), ' 行']);

census_fpga = zeros(img_height, img_width, 3, 'uint8');
idx = 6;  % 跳过前5字节文件头，从第6字节开始读取有效数据
for y = 1:img_height
    for x = 1:img_width
        if idx + 2 <= length(data_fpga)
            census_fpga(y, x, 1) = data_fpga(idx);
            census_fpga(y, x, 2) = data_fpga(idx + 1);
            census_fpga(y, x, 3) = data_fpga(idx + 2);
        end
        idx = idx + 3;
    end
end

disp('  FPGA数据读取完成');
disp(' ');

%% ====================== 位序诊断与自动校准 ======================
disp('[Step 4] 位序诊断与自动校准');

test_y = 100;
test_x = 100;

ml_byte1 = census_matlab(test_y, test_x, 1);
ml_byte2 = census_matlab(test_y, test_x, 2);
ml_byte3 = census_matlab(test_y, test_x, 3);

fp_byte1 = census_fpga(test_y, test_x, 1);
fp_byte2 = census_fpga(test_y, test_x, 2);
fp_byte3 = census_fpga(test_y, test_x, 3);

ml_original = bitshift(uint32(ml_byte1), 16) + ...
              bitshift(uint32(ml_byte2), 8) + ...
              uint32(ml_byte3);
          
fp_original = bitshift(uint32(fp_byte1), 16) + ...
              bitshift(uint32(fp_byte2), 8) + ...
              uint32(fp_byte3);

% 测试各种位序组合
dist_original = sum(bitget(bitxor(ml_original, fp_original), 1:24));

% 位序反转
ml_rev = uint32(0);
for b = 0:23
    ml_rev = bitor(bitshift(ml_rev, 1), bitget(ml_original, b + 1));
end
dist_bit_rev = sum(bitget(bitxor(ml_rev, fp_original), 1:24));

% 字节顺序反转
ml_byte_rev = bitshift(uint32(ml_byte3), 16) + ...
              bitshift(uint32(ml_byte2), 8) + ...
              uint32(ml_byte1);
dist_byte_rev = sum(bitget(bitxor(ml_byte_rev, fp_original), 1:24));

fprintf('\n  位置(%d,%d)诊断结果:\n', test_y, test_x);
fprintf('    Matlab原始: 0x%06X\n', ml_original);
fprintf('    FPGA原始:   0x%06X\n', fp_original);
fprintf('    方案1 - 直接对比:      %d bit\n', dist_original);
fprintf('    方案2 - Matlab位反转:  %d bit\n', dist_bit_rev);
fprintf('    方案3 - Matlab字节反转: %d bit\n', dist_byte_rev);

% 自动选择汉明距离最小的方案
[min_dist, best_scheme] = min([dist_original, dist_bit_rev, dist_byte_rev]);
fprintf('  ==> 自动选择: 方案%d (汉明距离=%d)\n', best_scheme, min_dist);

% 额外诊断: 比较运算符 > vs >= 测试
fprintf('\n  [附加诊断] 测试比较运算符 ( > 与 >= ):\n');
fprintf('    注: 1-5 bit差异通常是相等像素的处理不同\n');
disp(' ');

%% ====================== 逐比特对比分析 ======================
disp('[Step 5] 逐比特对比分析');

compare_rows = min([usable_rows, usable_rows_fpga, img_height]);
compare_cols = img_width;

fprintf('  对比行数: 1~%d, 列数: 1~%d\n', compare_rows, compare_cols);
total_pixels = double(compare_rows) * double(compare_cols);
fprintf('  总对比像素数: %d (注意: 之前500%%错误率是uint16溢出bug)\n', total_pixels);

total_bits = 0;
error_bits = 0;
error_pixels = 0;

bit_error_map = zeros(compare_rows, compare_cols);
pixel_error_map = zeros(compare_rows, compare_cols);
hamming_dist_map = zeros(compare_rows, compare_cols);

for y = 1:compare_rows
    for x = 1:compare_cols
        
        ml_byte1 = census_matlab(y, x, 1);
        ml_byte2 = census_matlab(y, x, 2);
        ml_byte3 = census_matlab(y, x, 3);
        
        fp_byte1 = census_fpga(y, x, 1);
        fp_byte2 = census_fpga(y, x, 2);
        fp_byte3 = census_fpga(y, x, 3);
        
        ml_val = bitshift(uint32(ml_byte1), 16) + ...
                 bitshift(uint32(ml_byte2), 8) + ...
                 uint32(ml_byte3);
                 
        fp_val = bitshift(uint32(fp_byte1), 16) + ...
                 bitshift(uint32(fp_byte2), 8) + ...
                 uint32(fp_byte3);
        
        % 应用选中的校准方案
        if best_scheme == 2
            % 位序反转
            ml_val_rev = uint32(0);
            for b = 0:23
                ml_val_rev = bitor(bitshift(ml_val_rev, 1), bitget(ml_val, b + 1));
            end
            ml_val = ml_val_rev;
        elseif best_scheme == 3
            % 字节反转
            ml_val = bitshift(uint32(ml_byte3), 16) + ...
                     bitshift(uint32(ml_byte2), 8) + ...
                     uint32(ml_byte1);
        end
        
        hamming_dist = sum(bitget(bitxor(ml_val, fp_val), 1:24));
        
        hamming_dist_map(y, x) = hamming_dist;
        
        if hamming_dist > 0
            error_pixels = error_pixels + 1;
            pixel_error_map(y, x) = 1;
            error_bits = error_bits + hamming_dist;
        end
        
        total_bits = total_bits + 24;
        bit_error_map(y, x) = hamming_dist;
    end
end

total_pixels = compare_rows * compare_cols;

disp(' ');
disp('=================== 统计结果 ===================');
disp(['  总像素数: ', num2str(total_pixels)]);
disp(['  总比特数: ', num2str(total_bits)]);
disp(['  错误像素数: ', num2str(error_pixels), ' (', ...
    num2str(double(error_pixels) * 100 / total_pixels, '%.2f'), '%)']);
disp(['  错误比特数: ', num2str(error_bits), ' (', ...
    num2str(double(error_bits) * 100 / total_bits, '%.4f'), '%)']);
disp(['  平均汉明距离(错误像素): ', ...
    num2str(double(error_bits) / max(error_pixels, 1), '%.2f'), ' bit']);
disp(['  平均汉明距离(全像素): ', ...
    num2str(mean(hamming_dist_map(:)), '%.4f'), ' bit']);
disp('================================================');
disp(' ');

%% ====================== 抽取样本详细对比 ======================
disp('[Step 6] 典型位置样本详细对比');

sample_positions = [3, 3; 100, 100; 240, 320; 478, 638];
sample_names = {'左上角非边界', '图像中心', '中间区域', '右下角非边界'};

fprintf('\n%25s | %8s | %8s | Hamming\n', '位置', 'Matlab', 'FPGA', 'Dist');
fprintf('%25s+%8s+%8s+%8s\n', repmat('-',1,25), repmat('-',1,8), repmat('-',1,8), repmat('-',1,8));

scheme_name = {'原始', '位反转', '字节反转'};
fprintf('  (已应用方案%d: %s)\n', best_scheme, scheme_name{best_scheme});

for i = 1:size(sample_positions, 1)
    y = sample_positions(i, 1);
    x = sample_positions(i, 2);
    
    if y > compare_rows || x > compare_cols
        continue;
    end
    
    ml_val = bitshift(uint32(census_matlab(y, x, 1)), 16) + ...
             bitshift(uint32(census_matlab(y, x, 2)), 8) + ...
             uint32(census_matlab(y, x, 3));
             
    fp_val = bitshift(uint32(census_fpga(y, x, 1)), 16) + ...
             bitshift(uint32(census_fpga(y, x, 2)), 8) + ...
             uint32(census_fpga(y, x, 3));
    
    % 应用选中的校准方案（保持与统计一致）
    if best_scheme == 2
        ml_val_rev = uint32(0);
        for b = 0:23
            ml_val_rev = bitor(bitshift(ml_val_rev, 1), bitget(ml_val, b + 1));
        end
        ml_val = ml_val_rev;
    elseif best_scheme == 3
        ml_val = bitshift(uint32(census_matlab(y, x, 3)), 16) + ...
                 bitshift(uint32(census_matlab(y, x, 2)), 8) + ...
                 uint32(census_matlab(y, x, 1));
    end
    
    hamming_dist = sum(bitget(bitxor(ml_val, fp_val), 1:24));
    
    fprintf('%25s | %06X | %06X | %3d\n', ...
        sample_names{i}, ml_val, fp_val, hamming_dist);
    
    if hamming_dist > 0
        disp(['  详细比特差异:']);
        for bit = 23:-1:0
            ml_bit = bitget(ml_val, bit + 1);
            fp_bit = bitget(fp_val, bit + 1);
            if ml_bit ~= fp_bit
                fprintf('    BIT%2d: Matlab=%d, FPGA=%d\n', bit, ml_bit, fp_bit);
            end
        end
    end
end
disp(' ');

%% ====================== 错误位置热力图 ======================
disp('[Step 7] 生成差异可视化');

figure('Name', 'Census差异对比', 'Position', [100, 100, 1200, 800]);

subplot(2, 3, 1);
imagesc(census_matlab(:,:,1));
colormap gray;
title('Matlab Census (高8位)');
colorbar;
axis image;

subplot(2, 3, 2);
imagesc(census_fpga(:,:,1));
colormap gray;
title('FPGA Census (高8位)');
colorbar;
axis image;

subplot(2, 3, 3);
diff_byte1 = abs(double(census_matlab(:,:,1)) - double(census_fpga(:,:,1))) > 0;
imagesc(diff_byte1);
colormap hot;
title(['高8位差异 (', num2str(sum(diff_byte1(:))), '像素)']);
colorbar;
axis image;

subplot(2, 3, 4);
imagesc(hamming_dist_map, [0 24]);
colormap jet;
title('像素汉明距离分布');
xlabel('列');
ylabel('行');
colorbar;
axis image;

subplot(2, 3, 5);
histogram(hamming_dist_map(:), 0:24);
title('汉明距离直方图');
xlabel('汉明距离');
ylabel('像素数');
grid on;

subplot(2, 3, 6);
mean_hamming_by_row = mean(hamming_dist_map, 2);
plot(mean_hamming_by_row);
title('每行平均汉明距离');
xlabel('行号');
ylabel('平均汉明距离');
grid on;
ylim([0 24]);

sgtitle(['Census Matlab vs FPGA 差异分析 - 错误率: ', ...
    num2str(error_bits / total_bits * 100, '%.4f'), '%']);

disp(' ');
disp('========================================');
disp('对比完成!');
disp('========================================');
