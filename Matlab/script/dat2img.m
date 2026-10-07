clear;clc;close all;

disp('==============================');
disp('DAT文件图像还原工具');
disp('==============================');
disp(' ');

[file_name, path_name] = uigetfile('*.dat', '选择DAT文件');

if isequal(file_name, 0)
    disp('用户取消选择');
    return;
end

full_path = fullfile(path_name, file_name);
disp(['选中文件: ', full_path]);
disp(' ');

%% ====================== 读取文件头 ======================
disp('[Step 1] 解析文件头');
fid = fopen(full_path, 'r');

data = fscanf(fid, '%2X ', Inf);
fclose(fid);

disp(['  fscanf 读取字节数: ', num2str(length(data))]);
if length(data) == 65535
    disp('  [WARNING] 读取到65535字节 = 2^16-1，疑似fscanf溢出!');
    disp('  正在尝试用textscan重新读取...');
    fid = fopen(full_path, 'r');
    data = textscan(fid, '%2X', Inf);
    data = data{1};
    fclose(fid);
    disp(['  textscan 读取字节数: ', num2str(length(data))]);
end

if length(data) < 5
    error(['文件太短! 仅读取到 ', num2str(length(data)), ' 字节，至少需要5字节文件头']);
end

img_width = bitor(bitshift(double(data(1)), 8), double(data(2)));
img_height = bitor(bitshift(double(data(3)), 8), double(data(4)));
data_type = double(data(5));

disp(['  图像宽度: ', num2str(img_width), ' (0x', dec2hex(img_width,4), ')']);
disp(['  图像高度: ', num2str(img_height), ' (0x', dec2hex(img_height,4), ')']);

type_str = {'Unknown', 'Gray', 'Census', 'Disparity8', 'Disparity16'};
disp(['  数据类型: ', type_str{data_type + 1}, ' (Type ', num2str(data_type), ')']);

%% ====================== 读取数据 ======================
disp(' ');
disp('[Step 2] 读取像素数据');

pixel_data = double(data(6:end));
disp(['  文件总字节数: ', num2str(length(pixel_data))]);

%% ====================== 根据类型还原图像 ======================
disp(' ');
disp('[Step 3] 还原图像');

switch data_type
    case 1
        disp('  还原灰度图像...');
        expected_bytes = img_width * img_height;
        disp(['  文件头声明尺寸: ', num2str(img_width), 'x', num2str(img_height), ' = ', num2str(expected_bytes), ' 字节']);
        disp(['  实际像素数据字节数: ', num2str(length(pixel_data))]);
        
        usable_rows = floor(length(pixel_data) / img_width);
        disp(['  可还原完整行数: ', num2str(usable_rows), ' (每行列数: ', num2str(img_width), ')']);
        
        if usable_rows < img_height
            warning(['行数不足! 期望: ', num2str(img_height), ' 行, 实际: ', num2str(usable_rows), ' 行']);
            actual_rows = usable_rows;
        else
            actual_rows = img_height;
        end
        
        actual_bytes = actual_rows * img_width;
        img_gray = reshape(pixel_data(1:actual_bytes), img_width, actual_rows)';
        img_gray = uint8(img_gray);
        
        figure('Name', '还原的灰度图像');
        imshow(img_gray, []);
        colormap gray;
        title(['灰度图像 - ', num2str(img_width), 'x', num2str(img_height)]);
        
        out_file = fullfile(path_name, [file_name(1:end-4), '_gray.png']);
        imwrite(img_gray, out_file);
        disp(['  保存到: ', out_file]);
        
    case 2
        disp('  还原Census特征可视化...');
        expected_bytes = img_width * img_height * 3;
        if length(pixel_data) < expected_bytes
            warning(['数据不足! 期望: ', num2str(expected_bytes), ...
                ' 实际: ', num2str(length(pixel_data))]);
        end
        
        census_3d = zeros(img_height, img_width, 3, 'uint8');
        idx = 1;
        for row = 1:img_height
            for col = 1:img_width
                if idx + 2 <= length(pixel_data)
                    census_3d(row, col, 1) = pixel_data(idx);
                    census_3d(row, col, 2) = pixel_data(idx + 1);
                    census_3d(row, col, 3) = pixel_data(idx + 2);
                    idx = idx + 3;
                end
            end
        end
        
        figure('Name', 'Census特征可视化(三通道分别显示');
        subplot(1,3,1); imshow(squeeze(census_3d(:,:,1)), []);
        title('Census高8位');
        subplot(1,3,2); imshow(squeeze(census_3d(:,:,2)), []);
        title('Census中8位');
        subplot(1,3,3); imshow(squeeze(census_3d(:,:,3)), []);
        title('Census低8位');
        sgtitle(['Census特征 - ', num2str(img_width), 'x', num2str(img_height)]);
        
        out_file = fullfile(path_name, [file_name(1:end-4), '_census_vis.png']);
        imwrite(census_3d, out_file);
        disp(['  保存到: ', out_file]);
        
    case 3
        disp('  还原视差图像 (sgm_new_2.v 亚像素格式) ...');
        disp('    byte[7] = valid (0有效 / 1空洞)');
        disp('    byte[6:0] = integer_disp * 2 + subpixel_offset (-1/0/+1)');
        disp('    实际视差 = byte[6:0] / 2.0  (0.5 像素亚像素精度)');
        expected_bytes = img_width * img_height;
        disp(['  文件头声明尺寸: ', num2str(img_width), 'x', num2str(img_height), ' = ', num2str(expected_bytes), ' 字节']);
        disp(['  实际像素数据字节数: ', num2str(length(pixel_data))]);
        
        usable_rows = floor(length(pixel_data) / img_width);
        disp(['  可还原完整行数: ', num2str(usable_rows), ' (每行列数: ', num2str(img_width), ')']);
        
        if usable_rows < img_height
            warning(['行数不足! 期望: ', num2str(img_height), ' 行, 实际: ', num2str(usable_rows), ' 行']);
            actual_rows = usable_rows;
        else
            actual_rows = img_height;
        end
        
        actual_bytes = actual_rows * img_width;
        img_disp_raw = reshape(pixel_data(1:actual_bytes), img_width, actual_rows)';
        
        % 解析亚像素格式: MSB=valid, lower 7 bits = int_disp*2 + subpixel_offset
        valid_mask = ~logical(bitget(uint8(img_disp_raw), 8));  % bit8=0 → valid
        raw_7bit = double(bitand(uint8(img_disp_raw), uint8(127)));
        img_disp = raw_7bit / 2.0;                                % 0.5 像素亚像素精度
        img_disp(~valid_mask) = -1;                               % 空洞标记为 -1
        
        hole_count = sum(~valid_mask(:));
        total_pix  = img_width * actual_rows;
        disp(['  MSB解析完成: 空洞 ', num2str(hole_count), ' / ', num2str(total_pix), ...
            ' (', num2str(100*hole_count/total_pix, '%.1f'), '%)']);
        
        MAX_DISP = 48;
        % 可视化: 有效视差映射到 0~255, 空洞置黑
        img_disp_norm = zeros(size(img_disp));
        valid_pix = img_disp >= 0;
        img_disp_norm(valid_pix) = img_disp(valid_pix) * (255.0 / MAX_DISP);
        img_disp_gray = uint8(img_disp_norm);
        
        % 空洞标记图: 空洞位置标红
        hole_mark = repmat(img_disp_gray, [1, 1, 3]);
        red_mask = repmat(~valid_mask, [1, 1, 3]);
        hole_mark(red_mask) = 255;       % R通道=255
        hole_mark(:, :, 2) = min(hole_mark(:, :, 2), uint8(valid_mask) * 255);
        hole_mark(:, :, 3) = min(hole_mark(:, :, 3), uint8(valid_mask) * 255);
        
        % 伪彩色映射: jet(256) + 首行黑色用于空洞
        cmap = [0 0 0; jet(256)];
        disp_idx = uint8(img_disp_norm) + 1;
        disp_idx(~valid_mask) = 0;
        disp_rgb = ind2rgb(disp_idx, cmap);
        
        figure('Name', '还原的视差图像 (sgm_new_2.v 亚像素格式)');
        subplot(1,3,1);
        imshow(img_disp_gray, []);
        colormap(gca, gray);
        colorbar;
        title(sprintf('灰度图 (空洞=%d, %.1f%%)', hole_count, 100*hole_count/total_pix));
        
        subplot(1,3,2);
        imshow(hole_mark);
        title('空洞标记 (红色=MSB=1)');
        
        subplot(1,3,3);
        imshow(disp_rgb);
        colorbar;
        colormap(gca, jet(256));
        caxis([0 MAX_DISP]);
        title(sprintf('伪彩色 (jet, 空洞=黑色)'));
        
        out_gray  = fullfile(path_name, [file_name(1:end-4), '_disparity_gray.png']);
        out_mark  = fullfile(path_name, [file_name(1:end-4), '_hole_mark.png']);
        out_color = fullfile(path_name, [file_name(1:end-4), '_disparity_color.png']);
        imwrite(img_disp_gray, out_gray);
        imwrite(hole_mark, out_mark);
        imwrite(disp_rgb, out_color);
        disp(['  保存灰度图到: ', out_gray]);
        disp(['  保存空洞标记到: ', out_mark]);
        disp(['  保存伪彩色图到: ', out_color]);
        
    case 4
        disp('  还原16位视差图像 (sgm_new_3.v 亚像素格式) ...');
        disp('    每像素2字节: byte[15]=空洞标志(0有效/1空洞)');
        disp('    byte[14:0] = best_disparity*2 + subpixel_bias(-1/0/+1)');
        disp('    实际视差 = byte[14:0] / 2.0');
        expected_pixels = img_width * img_height;
        expected_bytes = expected_pixels * 2;
        disp(['  文件头声明尺寸: ', num2str(img_width), 'x', num2str(img_height), ...
            ' = ', num2str(expected_pixels), ' 像素, ', num2str(expected_bytes), ' 字节']);
        disp(['  实际像素数据字节数: ', num2str(length(pixel_data))]);
        
        usable_pairs = floor(length(pixel_data) / 2);
        usable_rows = floor(usable_pairs / img_width);
        disp(['  可还原完整行数: ', num2str(usable_rows), ' (每行列数: ', num2str(img_width), ')']);
        
        if usable_rows < img_height
            warning(['行数不足! 期望: ', num2str(img_height), ' 行, 实际: ', num2str(usable_rows), ' 行']);
            actual_rows = usable_rows;
        else
            actual_rows = img_height;
        end
        
        actual_pixels = actual_rows * img_width;
        actual_bytes = actual_pixels * 2;
        
        img_disp_raw = zeros(actual_rows, img_width);
        for row = 1:actual_rows
            for col = 1:img_width
                idx = ((row-1) * img_width + (col-1)) * 2 + 1;
                high_byte = pixel_data(idx);
                low_byte = pixel_data(idx + 1);
                img_disp_raw(row, col) = high_byte * 256 + low_byte;
            end
        end
        
        valid_mask = bitget(uint16(img_disp_raw), 16) == 0;
        raw_15bit = double(bitand(uint16(img_disp_raw), uint16(32767)));
        img_disp = raw_15bit / 2.0;
        img_disp(~valid_mask) = -1;
        
        hole_count = sum(~valid_mask(:));
        total_pix = img_width * actual_rows;
        disp(['  解析完成: 空洞 ', num2str(hole_count), ' / ', num2str(total_pix), ...
            ' (', num2str(100*hole_count/total_pix, '%.1f'), '%)']);
        
        MAX_DISP = 95;
        
        img_disp_norm = zeros(size(img_disp));
        valid_pix = img_disp >= 0;
        img_disp_norm(valid_pix) = img_disp(valid_pix) * (255.0 / MAX_DISP);
        img_disp_gray = uint8(img_disp_norm);
        
        hole_mark = repmat(img_disp_gray, [1, 1, 3]);
        for c = 1:3
            chan = hole_mark(:, :, c);
            chan(~valid_mask) = 255;
            hole_mark(:, :, c) = chan;
        end
        hole_mark(:, :, 2) = min(hole_mark(:, :, 2), uint8(valid_mask) * 255);
        hole_mark(:, :, 3) = min(hole_mark(:, :, 3), uint8(valid_mask) * 255);
        
        % 伪彩色映射: jet(256) + 首行黑色用于空洞
        cmap = [0 0 0; jet(256)];
        disp_idx = uint8(img_disp_norm) + 1;
        disp_idx(~valid_mask) = 0;
        disp_rgb = ind2rgb(disp_idx, cmap);
        
        figure('Name', '还原的16位视差图像 (sgm_new_3.v)');
        subplot(1,3,1);
        imshow(img_disp_gray, []);
        colormap(gca, gray);
        colorbar;
        title(sprintf('灰度图 (空洞=%d, %.1f%%)', hole_count, 100*hole_count/total_pix));
        
        subplot(1,3,2);
        imshow(hole_mark);
        title('空洞标记 (红色=bit15=1)');
        
        subplot(1,3,3);
        imshow(disp_rgb);
        colorbar;
        colormap(gca, jet(256));
        caxis([0 MAX_DISP]);
        title(sprintf('伪彩色 (jet, 空洞=黑色)'));
        
        out_gray  = fullfile(path_name, [file_name(1:end-4), '_disparity16_gray.png']);
        out_mark  = fullfile(path_name, [file_name(1:end-4), '_hole16_mark.png']);
        out_color = fullfile(path_name, [file_name(1:end-4), '_disparity16_color.png']);
        imwrite(img_disp_gray, out_gray);
        imwrite(hole_mark, out_mark);
        imwrite(disp_rgb, out_color);
        disp(['  保存灰度图到: ', out_gray]);
        disp(['  保存空洞标记到: ', out_mark]);
        disp(['  保存伪彩色图到: ', out_color]);
        
    otherwise
        error(['不支持的数据类型: ', num2str(data_type)]);
end

disp(' ');
disp('==============================');
disp('还原完成!');
disp('==============================');
