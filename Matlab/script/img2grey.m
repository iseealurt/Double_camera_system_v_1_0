% 图像批量转换为灰度图脚本
% 作者：MATLAB助手
% 功能：将文件夹内的所有图像转换为灰度图并保存到指定位置

clear; clc; close all;

try
    % 选择包含图像的文件夹
    fprintf('请选择包含图像的文件夹...\n');
    inputFolder = uigetdir('', '请选择包含图像的文件夹');
    
    if inputFolder == 0
        error('用户取消了文件夹选择。');
    end
    
    % 选择保存灰度图像的文件夹
    fprintf('请选择保存灰度图像的文件夹...\n');
    outputFolder = uigetdir('', '请选择保存灰度图像的文件夹');
    
    if outputFolder == 0
        error('用户取消了保存文件夹选择。');
    end
    
    % 获取文件夹中的所有图像文件
    imageExtensions = {'*.jpg', '*.jpeg', '*.png', '*.bmp', '*.tif', '*.tiff', '*.gif'};
    imageFiles = [];
    
    for i = 1:length(imageExtensions)
        files = dir(fullfile(inputFolder, imageExtensions{i}));
        imageFiles = [imageFiles; files];
    end
    
    % 检查是否找到图像文件
    if isempty(imageFiles)
        error('在选择的文件夹中未找到任何图像文件。支持格式：jpg, jpeg, png, bmp, tif, tiff, gif');
    end
    
    fprintf('找到 %d 个图像文件。开始转换...\n', length(imageFiles));
    
    % 创建进度条
    h = waitbar(0, '正在转换图像，请稍候...');
    
    % 处理每个图像文件
    for i = 1:length(imageFiles)
        try
            % 更新进度条
            waitbar(i/length(imageFiles), h, sprintf('正在处理第 %d/%d 个图像...', i, length(imageFiles)));
            
            % 读取图像
            filename = imageFiles(i).name;
            filepath = fullfile(inputFolder, filename);
            img = imread(filepath);
            
            % 转换为灰度图像
            if size(img, 3) == 3
                grayImg = rgb2gray(img);
            elseif size(img, 3) == 1
                grayImg = img; % 如果已经是灰度图，直接使用
            else
                fprintf('跳过文件 %s：不支持的图像格式\n', filename);
                continue;
            end
            
            % 生成输出文件名（保持原文件名，添加_gray后缀）
            [~, name, ext] = fileparts(filename);
            outputFilename = [name, '_gray', ext];
            outputPath = fullfile(outputFolder, outputFilename);
            
            % 保存灰度图像
            imwrite(grayImg, outputPath);
            
            fprintf('已转换并保存：%s\n', outputFilename);
            
        catch ME
            fprintf('处理文件 %s 时出错：%s\n', filename, ME.message);
            continue;
        end
    end
    
    % 关闭进度条
    close(h);
    
    fprintf('\n转换完成！共处理 %d 个文件，结果保存在：%s\n', length(imageFiles), outputFolder);
    
catch ME
    % 错误处理
    fprintf('程序执行出错：%s\n', ME.message);
    
    % 确保进度条被关闭
    if exist('h', 'var') && ishandle(h)
        close(h);
    end
end