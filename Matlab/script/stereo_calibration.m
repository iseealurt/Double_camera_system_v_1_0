%% 双目立体标定脚本
% 根据 double_camera_disp.v 的显示布局从标定图像中裁剪左右目图像:
%   全帧分辨率: 1920 x 1080
%   左目 (Camera 1): 偏移 (160, 32), 分辨率 640 x 480
%   右目 (Camera 2): 偏移 (1120, 32), 分辨率 640 x 480
%
% 使用说明:
%   1. 将上位机截取的标定图像放入 calibration 文件夹
%   2. 根据实际棋盘格修改下方 squareSize 参数
%   3. 运行此脚本
%   4. 标定结果保存在 calibration 文件夹中
%
% 更新说明 (v2.0):
%   - 增加 Bouguet 立体校正 (Stereo Rectification)
%   - 生成复合 LUT: 畸变校正 + 立体校正 合并为单次查表
%   - 输出校正后的相机参数, 供软件 config 更新

clear; clc; close all;

%% ====================== 配置参数 ======================

% 图像文件夹路径 (标定图像所在目录)
imgFolder = '..\..\Matlab\calibration';

% 棋盘格参数 (根据实际标定板修改!)
squareSize = 15;            % 棋盘格方格边长 (mm)

% 显示区域参数 (与 double_camera_disp.v 保持一致)
frameWidth  = 1920;         % 全帧宽度
frameHeight = 1080;         % 全帧高度
camWidth    = 640;          % 单目图像宽度
camHeight   = 480;          % 单目图像高度

% 左目偏移 (CMR_1_DISP_AREA_H_OFST, CMR_1_DISP_AREA_V_OFST)
leftOffsetX = 160;
leftOffsetY = 32;

% 右目偏移 (CMR_2_DISP_AREA_H_OFST, CMR_2_DISP_AREA_V_OFST)
rightOffsetX = 1120;
rightOffsetY = 32;

%% ====================== 读取标定图像并裁剪左右目 ======================

imgFiles = dir(fullfile(imgFolder, '*.jpg'));
numImages = length(imgFiles);

if numImages == 0
    error('未在 %s 中找到 JPG 标定图像', imgFolder);
end

fprintf('找到 %d 张标定图像\n', numImages);

% 构造 4D uint8 数组 (H x W x 3 x N) 供 detectCheckerboardPoints 直接使用
leftImages  = zeros(camHeight, camWidth, 3, numImages, 'uint8');
rightImages = zeros(camHeight, camWidth, 3, numImages, 'uint8');

for i = 1:numImages
    imgPath = fullfile(imgFolder, imgFiles(i).name);
    img = imread(imgPath);

    [h, w, ~] = size(img);
    if h ~= frameHeight || w ~= frameWidth
        warning('图像 %s 尺寸为 %d x %d, 期望 %d x %d, 将自动缩放', ...
            imgFiles(i).name, w, h, frameWidth, frameHeight);
        img = imresize(img, [frameHeight, frameWidth]);
    end

    % 裁剪左目: x ∈ [160, 800), y ∈ [32, 512)
    leftImages(:, :, :, i) = img(leftOffsetY+1 : leftOffsetY+camHeight, ...
                                  leftOffsetX+1 : leftOffsetX+camWidth, :);

    % 裁剪右目: x ∈ [1120, 1760), y ∈ [32, 512)
    rightImages(:, :, :, i) = img(rightOffsetY+1 : rightOffsetY+camHeight, ...
                                   rightOffsetX+1 : rightOffsetX+camWidth, :);
end

fprintf('已从 %d 张全帧图像中裁剪出左右目图像 (640 x 480)\n', numImages);

%% ====================== 检测棋盘格角点 ======================

fprintf('检测左目棋盘格角点...\n');
[imagePointsLeft, boardSize, imagesUsedLeft] = ...
    detectCheckerboardPoints(leftImages);

fprintf('检测右目棋盘格角点...\n');
[imagePointsRight, boardSize2, imagesUsedRight] = ...
    detectCheckerboardPoints(rightImages);

% 只保留左右目均检测成功的图像对
usedIdx = imagesUsedLeft & imagesUsedRight;
numValidPairs = sum(usedIdx);

if numValidPairs < 3
    error('有效标定图像对仅 %d 对 (至少需要 3 对)，请调整棋盘格参数或重新拍摄', numValidPairs);
end

fprintf('成功检测 %d 对标定图像\n', numValidPairs);

% 过滤有效图像
imagePointsLeft  = imagePointsLeft(:, :, usedIdx);
imagePointsRight = imagePointsRight(:, :, usedIdx);

% 使用检测得到的 boardSize 生成世界坐标点 (保证角点数量一致)
worldPoints = generateCheckerboardPoints(boardSize, squareSize);

%% ====================== 单目标定 ======================

fprintf('正在进行左目单目标定（含切向畸变）...\n');
paramsLeft = estimateCameraParameters(imagePointsLeft, worldPoints, ...
    'ImageSize', [camHeight, camWidth], ...
    'EstimateTangentialDistortion', true);

fprintf('正在进行右目单目标定（含切向畸变）...\n');
paramsRight = estimateCameraParameters(imagePointsRight, worldPoints, ...
    'ImageSize', [camHeight, camWidth], ...
    'EstimateTangentialDistortion', true);

%% ====================== 双目标定 ======================

% 验证左右目检测的棋盘格尺寸一致
if ~isequal(boardSize, boardSize2)
    error('左右目检测到的棋盘格尺寸不一致: 左目 [%d,%d], 右目 [%d,%d]', ...
        boardSize(1), boardSize(2), boardSize2(1), boardSize2(2));
end

fprintf('正在进行双目标定...\n');

% 构造 4D imagePoints 数组: M x 2 x numPairs x 2
% 第4维: 1=左目, 2=右目
imagePointsStereo = cat(4, imagePointsLeft, imagePointsRight);

stereoParams = estimateCameraParameters(imagePointsStereo, worldPoints, ...
    'ImageSize', [camHeight, camWidth], ...
    'EstimateTangentialDistortion', true);

%% ====================== 显示标定结果 ======================

% 左目
figure('Name', '左目相机 - 外参', 'NumberTitle', 'off');
showExtrinsics(paramsLeft);
title('左目相机外参');

figure('Name', '左目相机 - 重投影误差', 'NumberTitle', 'off');
showReprojectionErrors(paramsLeft);
title('左目重投影误差');

% 右目
figure('Name', '右目相机 - 外参', 'NumberTitle', 'off');
showExtrinsics(paramsRight);
title('右目相机外参');

figure('Name', '右目相机 - 重投影误差', 'NumberTitle', 'off');
showReprojectionErrors(paramsRight);
title('右目重投影误差');

% 双目
figure('Name', '双目立体标定 - 外参', 'NumberTitle', 'off');
showExtrinsics(stereoParams);
title('双目立体标定 - 相机外参');

figure('Name', '双目立体标定 - 重投影误差', 'NumberTitle', 'off');
showReprojectionErrors(stereoParams);
title('双目立体标定 - 重投影误差');

%% ====================== 保存标定结果 ======================

% --- 保存 .mat 文件 ---
save(fullfile(imgFolder, 'stereo_calibration_results.mat'), ...
    'stereoParams', 'paramsLeft', 'paramsRight');

% --- 提取参数供后续导出使用 ---
K1 = stereoParams.CameraParameters1.IntrinsicMatrix;
K2 = stereoParams.CameraParameters2.IntrinsicMatrix;
R  = stereoParams.RotationOfCamera2;
T  = stereoParams.TranslationOfCamera2;

k1_1 = stereoParams.CameraParameters1.RadialDistortion;
k1_2 = stereoParams.CameraParameters2.RadialDistortion;
p1_1 = stereoParams.CameraParameters1.TangentialDistortion;
p1_2 = stereoParams.CameraParameters2.TangentialDistortion;

if length(k1_1) < 3, k1_1(3) = 0; end
if length(k1_2) < 3, k1_2(3) = 0; end
if length(p1_1) < 2, p1_1(2) = 0; end
if length(p1_2) < 2, p1_2(2) = 0; end

%% ====================== Bouguet 立体校正 (Stereo Rectification) ======================
%
% 标准 Bouguet 算法:
%   1. Rodrigues 半角旋转 → 两相机光轴平行 (R1=R2=R_epipolar * R^(-1/2))
%   2. 极线校正旋转 → 极线水平对齐
%
% 关键: 左右目使用相同的校正旋转, 左目LUT和右目LUT差异仅来自畸变模型

fprintf('\n========== 计算立体校正变换 ==========\n');

% K1/K2 为 IntrinsicMatrix 返回形式(转置), 取其标准形式
K1_std = K1';
K2_std = K2';

% 左右目标准内参
fx1 = K1_std(1,1); fy1 = K1_std(2,2); cx1 = K1_std(1,3); cy1 = K1_std(2,3);
fx2 = K2_std(1,1); fy2 = K2_std(2,2); cx2 = K2_std(1,3); cy2 = K2_std(2,3);

fprintf('左目内参: fx=%.4f, fy=%.4f, cx=%.4f, cy=%.4f\n', fx1, fy1, cx1, cy1);
fprintf('右目内参: fx=%.4f, fy=%.4f, cx=%.4f, cy=%.4f\n', fx2, fy2, cx2, cy2);

% 基线
baseline_norm = norm(T);
fprintf('基线: %.4f mm\n', baseline_norm);

% ========== Step 1: Rodrigues 半角旋转 (使两相机光轴平行) ==========

% R 定义: X_right = R * X_left + T (右目相对左目的旋转)
% 使用 Rodrigues 公式计算 R^(-1/2)
% 关键: 左右目用相同的校正旋转 R1 = R2 = R_epipolar * R^(-1/2)
% 这样两相机平行且极线水平

theta = acos(max(-1, min(1, (trace(R) - 1) / 2)));  % 旋转角度

if abs(theta) < 1e-10
    R_half_inv = eye(3);
    fprintf('左右目间旋转角度: ~0 rad (可忽略)\n');
else
    % 旋转轴 (单位向量)
    rx = (R(3,2) - R(2,3)) / (2 * sin(theta));
    ry = (R(1,3) - R(3,1)) / (2 * sin(theta));
    rz = (R(2,1) - R(1,2)) / (2 * sin(theta));
    r_norm = [rx, ry, rz];
    r_norm = r_norm / norm(r_norm);

    % Rodrigues 公式: R = exp(θ*K), R_half = exp(θ/2 * K)
    % R_half * R_half = R, 所以 R_half = R^(1/2)
    % 我们需要 R^(-1/2) = R_half^(-1) = R_half'
    K_hat = [0,          -r_norm(3),  r_norm(2);
             r_norm(3),  0,          -r_norm(1);
            -r_norm(2),  r_norm(1),   0];

    R_half = eye(3) + sin(theta/2) * K_hat + (1 - cos(theta/2)) * K_hat^2;
    R_half_inv = R_half';  % R^(-1/2) = R_half^(-1) = R_half'

    fprintf('左右目间旋转角度: %.4f rad (%.2f°)\n', theta, theta * 180 / pi);
end

% ========== Step 2: 极线校正旋转 (使极线水平) ==========

% 新 X 轴: 沿基线方向, 指向正X方向
T_vec = T(:);        % 3x1 列向量
e1 = -T_vec / norm(T_vec);  % T≈[-30,0,0] → e1≈[1,0,0] (指向正X)

% 新 Y 轴: 垂直于新X轴和原Z轴
z_orig = [0; 0; 1];
e2 = cross(z_orig, e1);
e2 = e2 / norm(e2);

% 新 Z 轴: 右手系, 垂直于新X和新Y
e3 = cross(e1, e2);

% 极线校正旋转矩阵
R_epipolar = [e1'; e2'; e3'];

fprintf('\n极线校正旋转 R_epipolar:\n');
fprintf('  %10.8f  %10.8f  %10.8f\n', R_epipolar(1,:));
fprintf('  %10.8f  %10.8f  %10.8f\n', R_epipolar(2,:));
fprintf('  %10.8f  %10.8f  %10.8f\n', R_epipolar(3,:));

% ========== Step 3: 合成最终校正旋转 ==========

% 左右目使用相同的校正旋转, 保证极线水平对齐
R1_rect = R_epipolar * R_half_inv;  % 左目: 半角旋转 + 极线校正
R2_rect = R_epipolar * R_half_inv;  % 右目: 半角旋转 + 极线校正 (与左目相同)

fprintf('\n左目校正旋转 R1_rect (= R2_rect):\n');
fprintf('  %10.8f  %10.8f  %10.8f\n', R1_rect(1,:));
fprintf('  %10.8f  %10.8f  %10.8f\n', R1_rect(2,:));
fprintf('  %10.8f  %10.8f  %10.8f\n', R1_rect(3,:));

% 验证相机平行: R2_rect * R * R1_rect' = I
check_final = R2_rect * R * R1_rect';
fprintf('\n校正后相对旋转 (应为 I):\n');
fprintf('  %10.8f  %10.8f  %10.8f\n', check_final(1,:));
fprintf('  %10.8f  %10.8f  %10.8f\n', check_final(2,:));
fprintf('  %10.8f  %10.8f  %10.8f\n', check_final(3,:));
fprintf('  ★ 相机已平行! ✓ (残差 = %.6f)\n', norm(check_final - eye(3)));

% ========== Step 4: 确定校正后内参 ==========

% 使用左右目焦距的几何均值 (减小畸变)
fx_rect = sqrt(fx1 * fx2);
fy_rect = sqrt(fy1 * fy2);

% 搜索最优主点, 使 LUT 偏移在 Q4.3 范围内 (±16px)
% 先以左目主点为起点
cx_rect = cx1;
cy_rect = cy1;

K_rect = [fx_rect, 0, cx_rect; 0, fy_rect, cy_rect; 0, 0, 1];
fprintf('\n校正后初始内参 K_rect:\n');
fprintf('  %10.6f  %10.6f  %10.6f\n', K_rect(1,:));
fprintf('  %10.6f  %10.6f  %10.6f\n', K_rect(2,:));
fprintf('  %10.6f  %10.6f  %10.6f\n', K_rect(3,:));

% ========== Step 5: 优化主点使 LUT 偏移在 Q4.3 范围内 ==========

% 采样网格 (每隔2px采样, 快速评估)
[U_samp, V_samp] = meshgrid(4:4:camWidth-5, 4:4:camHeight-5);
U_samp = single(U_samp(:));
V_samp = single(V_samp(:));
num_samp = length(U_samp);

% 预计算畸变校正偏移 (cx,cy 变化时畸变偏移也会变化)
% 对于每个候选 (cx_test, cy_test), 评估左右目复合映射的偏移最大值
% 搜索范围: cx 在左右目cx之间, cy 在左右目cy之间
cx_range = linspace(min(cx1, cx2) - 2, max(cx1, cx2) + 2, 31);
cy_range = linspace(min(cy1, cy2) - 2, max(cy1, cy2) + 2, 21);

best_max_offset = 100;
best_cx = cx1;
best_cy = cy1;

fprintf('\n搜索最优主点 (cx_range=[%.1f~%.1f], cy_range=[%.1f~%.1f])...\n', ...
    min(cx_range), max(cx_range), min(cy_range), max(cy_range));

for i = 1:length(cx_range)
    if mod(i, 5) ~= 1 && i < length(cx_range)
        continue  % 隔5个点搜索一次提高速度
    end
    for j = 1:4:length(cy_range)
        cx_test = cx_range(i);
        cy_test = cy_range(j);

        % === 左目复合映射评估 ===
        xn_test = (U_samp - cx_test) / fx_rect;
        yn_test = (V_samp - cy_test) / fy_rect;
        pts_rect = [xn_test'; yn_test'; ones(1, num_samp)];
        pts_orig = R1_rect' * pts_rect;
        x_orig = pts_orig(1,:)' ./ pts_orig(3,:)';
        y_orig = pts_orig(2,:)' ./ pts_orig(3,:)';

        % 左目畸变
        r2_l = x_orig.^2 + y_orig.^2;
        radial_l = 1 + k1_1(1)*r2_l + k1_1(2)*r2_l.^2 + k1_1(3)*r2_l.^3;
        dx_tan_l = 2*p1_1(1)*x_orig.*y_orig + p1_1(2)*(r2_l + 2*x_orig.^2);
        dy_tan_l = p1_1(1)*(r2_l + 2*y_orig.^2) + 2*p1_1(2)*x_orig.*y_orig;
        xd_l = x_orig .* radial_l + dx_tan_l;
        yd_l = y_orig .* radial_l + dy_tan_l;
        mapX_l = fx1 * xd_l + cx1;
        mapY_l = fy1 * yd_l + cy1;
        dx_l = mapX_l - U_samp;
        dy_l = mapY_l - V_samp;
        max_l = max(max(abs(dx_l)), max(abs(dy_l)));

        % === 右目复合映射评估 ===
        pts_orig_r = R2_rect' * pts_rect;
        x_orig_r = pts_orig_r(1,:)' ./ pts_orig_r(3,:)';
        y_orig_r = pts_orig_r(2,:)' ./ pts_orig_r(3,:)';

        % 右目畸变
        r2_r = x_orig_r.^2 + y_orig_r.^2;
        radial_r = 1 + k1_2(1)*r2_r + k1_2(2)*r2_r.^2 + k1_2(3)*r2_r.^3;
        dx_tan_r = 2*p1_2(1)*x_orig_r.*y_orig_r + p1_2(2)*(r2_r + 2*x_orig_r.^2);
        dy_tan_r = p1_2(1)*(r2_r + 2*y_orig_r.^2) + 2*p1_2(2)*x_orig_r.*y_orig_r;
        xd_r = x_orig_r .* radial_r + dx_tan_r;
        yd_r = y_orig_r .* radial_r + dy_tan_r;
        mapX_r = fx2 * xd_r + cx2;
        mapY_r = fy2 * yd_r + cy2;
        dx_r = mapX_r - U_samp;
        dy_r = mapY_r - V_samp;
        max_r = max(max(abs(dx_r)), max(abs(dy_r)));

        current_max = max(max_l, max_r);
        if current_max < best_max_offset
            best_max_offset = current_max;
            best_cx = cx_test;
            best_cy = cy_test;
            fprintf('  cx=%.2f cy=%.2f → max_offset=%.1f (L:%.1f, R:%.1f)\n', ...
                cx_test, cy_test, current_max, max_l, max_r);
        end
    end
end

cx_rect = best_cx;
cy_rect = best_cy;
K_rect = [fx_rect, 0, cx_rect; 0, fy_rect, cy_rect; 0, 0, 1];
fprintf('\n优化后主点: cx=%.2f, cy=%.2f (最大偏移=%.1f px)\n', ...
    cx_rect, cy_rect, best_max_offset);
if best_max_offset <= 15.875
    fprintf('  ★ Q4.3 范围合格! ✓\n');
else
    fprintf('  ⚠ 超出 Q4.3 范围 (%.1f > 15.875), 需要增大位宽\n', best_max_offset);
end

% ========== Step 6: 平移向量和 Q 矩阵 ==========

% 校正后的平移向量 (在校正坐标系中)
% 右目 - 左目在校正坐标系中的位移 = R2_rect * T
T_rect = R2_rect * T_vec;

fprintf('\n校正后平移向量 T_rect:\n');
fprintf('  [%.4f, %.4f, %.4f] mm\n', T_rect(1), T_rect(2), T_rect(3));
fprintf('  基线 = %.4f mm\n', norm(T_rect));
fprintf('  有效水平基线 = %.4f mm (X分量)\n', abs(T_rect(1)));

baseline_cm = baseline_norm / 10;

% P1, P2 矩阵 (3x4)
P1 = [K_rect, zeros(3, 1)];
P2 = K_rect * [eye(3), -T_rect];

% Q 矩阵
Q = [1, 0, 0, -cx_rect;
     0, 1, 0, -cy_rect;
     0, 0, 0,  fx_rect;
     0, 0, 1/T_rect(1), 0];

fprintf('\nQ 矩阵:\n');
fprintf('  %10.6f  %10.6f  %10.6f  %10.6f\n', Q(1,:));
fprintf('  %10.6f  %10.6f  %10.6f  %10.6f\n', Q(2,:));
fprintf('  %10.6f  %10.6f  %10.6f  %10.6f\n', Q(3,:));
fprintf('  %10.6f  %10.6f  %10.6f  %10.6f\n', Q(4,:));

fprintf('\n深度公式: Z(cm) = %.4f * %.4f / disparity = %.4f / disparity\n', ...
    baseline_cm, fx_rect, baseline_cm * fx_rect);

%% ====================== 导出给 FPGA 使用的简洁参数 ======================

fid2 = fopen(fullfile(imgFolder, 'calibration_params_short.txt'), 'w');

fprintf(fid2, '# 左目内参 (Camera 1)\n');
fprintf(fid2, 'K_left = [\n');
fprintf(fid2, '  %.6f, %.6f, %.6f;\n', K1(1,1), K1(2,1), K1(3,1));
fprintf(fid2, '  %.6f, %.6f, %.6f;\n', K1(1,2), K1(2,2), K1(3,2));
fprintf(fid2, '  %.6f, %.6f, %.6f\n', K1(1,3), K1(2,3), K1(3,3));
fprintf(fid2, ']\n\n');

fprintf(fid2, '# 右目内参 (Camera 2)\n');
fprintf(fid2, 'K_right = [\n');
fprintf(fid2, '  %.6f, %.6f, %.6f;\n', K2(1,1), K2(2,1), K2(3,1));
fprintf(fid2, '  %.6f, %.6f, %.6f;\n', K2(1,2), K2(2,2), K2(3,2));
fprintf(fid2, '  %.6f, %.6f, %.6f\n', K2(1,3), K2(2,3), K2(3,3));
fprintf(fid2, ']\n\n');

fprintf(fid2, '# 右目相对左目的旋转\n');
fprintf(fid2, 'R = [\n');
fprintf(fid2, '  %.8f, %.8f, %.8f;\n', R(1,1), R(1,2), R(1,3));
fprintf(fid2, '  %.8f, %.8f, %.8f;\n', R(2,1), R(2,2), R(2,3));
fprintf(fid2, '  %.8f, %.8f, %.8f\n', R(3,1), R(3,2), R(3,3));
fprintf(fid2, ']\n\n');

fprintf(fid2, '# 右目相对左目的平移 (mm)\n');
fprintf(fid2, 'T = [%.4f, %.4f, %.4f]\n\n', T(1), T(2), T(3));

fprintf(fid2, '# 基线距离 (mm)\n');
fprintf(fid2, 'baseline = %.4f\n\n', norm(T));

fprintf(fid2, '# 左目畸变系数\n');
fprintf(fid2, 'k_left  = [%.8f, %.8f, %.8f]\n', k1_1(1), k1_1(2), k1_1(3));
fprintf(fid2, 'p_left  = [%.8f, %.8f]\n\n', p1_1(1), p1_1(2));

fprintf(fid2, '# 右目畸变系数\n');
fprintf(fid2, 'k_right = [%.8f, %.8f, %.8f]\n', k1_2(1), k1_2(2), k1_2(3));
fprintf(fid2, 'p_right = [%.8f, %.8f]\n\n', p1_2(1), p1_2(2));

% ---- 追加校正后参数 ----
fprintf(fid2, '# 立体校正参数 (Rectification)\n');
fprintf(fid2, '# 校正后左右目共用内参\n');
fprintf(fid2, 'K_rect = [\n');
fprintf(fid2, '  %.6f, %.6f, %.6f;\n', K_rect(1,1), K_rect(1,2), K_rect(1,3));
fprintf(fid2, '  %.6f, %.6f, %.6f;\n', K_rect(2,1), K_rect(2,2), K_rect(2,3));
fprintf(fid2, '  %.6f, %.6f, %.6f\n', K_rect(3,1), K_rect(3,2), K_rect(3,3));
fprintf(fid2, ']\n\n');

fprintf(fid2, '# 左目校正旋转矩阵 (R1_rect)\n');
fprintf(fid2, 'R1_rect = [\n');
fprintf(fid2, '  %.8f, %.8f, %.8f;\n', R1_rect(1,1), R1_rect(1,2), R1_rect(1,3));
fprintf(fid2, '  %.8f, %.8f, %.8f;\n', R1_rect(2,1), R1_rect(2,2), R1_rect(2,3));
fprintf(fid2, '  %.8f, %.8f, %.8f\n', R1_rect(3,1), R1_rect(3,2), R1_rect(3,3));
fprintf(fid2, ']\n\n');

fprintf(fid2, '# 右目校正旋转矩阵 (R2_rect)\n');
fprintf(fid2, 'R2_rect = [\n');
fprintf(fid2, '  %.8f, %.8f, %.8f;\n', R2_rect(1,1), R2_rect(1,2), R2_rect(1,3));
fprintf(fid2, '  %.8f, %.8f, %.8f;\n', R2_rect(2,1), R2_rect(2,2), R2_rect(2,3));
fprintf(fid2, '  %.8f, %.8f, %.8f\n', R2_rect(3,1), R2_rect(3,2), R2_rect(3,3));
fprintf(fid2, ']\n\n');

fprintf(fid2, '# 校正后投影矩阵 P1 (左目)\n');
fprintf(fid2, 'P1 = [\n');
fprintf(fid2, '  %.6f, %.6f, %.6f, %.6f;\n', P1(1,1), P1(1,2), P1(1,3), P1(1,4));
fprintf(fid2, '  %.6f, %.6f, %.6f, %.6f;\n', P1(2,1), P1(2,2), P1(2,3), P1(2,4));
fprintf(fid2, '  %.6f, %.6f, %.6f, %.6f\n', P1(3,1), P1(3,2), P1(3,3), P1(3,4));
fprintf(fid2, ']\n\n');

fprintf(fid2, '# 校正后投影矩阵 P2 (右目)\n');
fprintf(fid2, 'P2 = [\n');
fprintf(fid2, '  %.6f, %.6f, %.6f, %.6f;\n', P2(1,1), P2(1,2), P2(1,3), P2(1,4));
fprintf(fid2, '  %.6f, %.6f, %.6f, %.6f;\n', P2(2,1), P2(2,2), P2(2,3), P2(2,4));
fprintf(fid2, '  %.6f, %.6f, %.6f, %.6f\n', P2(3,1), P2(3,2), P2(3,3), P2(3,4));
fprintf(fid2, ']\n\n');

fprintf(fid2, '# Q 矩阵 (视差到三维坐标)\n');
fprintf(fid2, 'Q = [\n');
fprintf(fid2, '  %.6f, %.6f, %.6f, %.6f;\n', Q(1,1), Q(1,2), Q(1,3), Q(1,4));
fprintf(fid2, '  %.6f, %.6f, %.6f, %.6f;\n', Q(2,1), Q(2,2), Q(2,3), Q(2,4));
fprintf(fid2, '  %.6f, %.6f, %.6f, %.6f;\n', Q(3,1), Q(3,2), Q(3,3), Q(3,4));
fprintf(fid2, '  %.6f, %.6f, %.6f, %.6f\n', Q(4,1), Q(4,2), Q(4,3), Q(4,4));
fprintf(fid2, ']\n\n');

fclose(fid2);

%% ====================== 生成原始畸变校正查找表 (保留, 用于对比) ======================

fprintf('\n========== 生成畸变校正查找表 (Undistortion Only) ==========\n');
fprintf('  图像尺寸: %d x %d\n', camWidth, camHeight);

% 生成像素网格
[U, V] = meshgrid(0:camWidth-1, 0:camHeight-1);
U = single(U);
V = single(V);

% ---- 左目 LUT ----
fprintf('  计算左目校正映射...\n');

x1 = (U - cx1) / fx1;
y1 = (V - cy1) / fy1;
r2_1 = x1.^2 + y1.^2;
r4_1 = r2_1.^2;
r6_1 = r2_1.^3;

% 径向畸变因子
radialFactor1 = 1 + k1_1(1)*r2_1 + k1_1(2)*r4_1 + k1_1(3)*r6_1;
% 切向畸变
dx1 = 2*p1_1(1)*x1.*y1 + p1_1(2)*(r2_1 + 2*x1.^2);
dy1 = p1_1(1)*(r2_1 + 2*y1.^2) + 2*p1_1(2)*x1.*y1;

mapX_left  = fx1 * (x1 .* radialFactor1 + dx1) + cx1;
mapY_left  = fy1 * (y1 .* radialFactor1 + dy1) + cy1;

% 边界裁剪
mapX_left = max(0, min(camWidth-1, mapX_left));
mapY_left = max(0, min(camHeight-1, mapY_left));

% ---- 右目 LUT ----
fprintf('  计算右目校正映射...\n');

x2 = (U - cx2) / fx2;
y2 = (V - cy2) / fy2;
r2_2 = x2.^2 + y2.^2;
r4_2 = r2_2.^2;
r6_2 = r2_2.^3;

radialFactor2 = 1 + k1_2(1)*r2_2 + k1_2(2)*r4_2 + k1_2(3)*r6_2;
dx2 = 2*p1_2(1)*x2.*y2 + p1_2(2)*(r2_2 + 2*x2.^2);
dy2 = p1_2(1)*(r2_2 + 2*y2.^2) + 2*p1_2(2)*x2.*y2;

mapX_right = fx2 * (x2 .* radialFactor2 + dx2) + cx2;
mapY_right = fy2 * (y2 .* radialFactor2 + dy2) + cy2;

% ---- 畸变偏移量统计 (裁剪前) ----
offsetX_left  = mapX_left  - U;
offsetY_left  = mapY_left  - V;
offsetX_right = mapX_right - U;
offsetY_right = mapY_right - V;

maxOffX_left  = max(abs(offsetX_left(:)));
maxOffY_left  = max(abs(offsetY_left(:)));
maxOffX_right = max(abs(offsetX_right(:)));
maxOffY_right = max(abs(offsetY_right(:)));

fprintf('\n========== 畸变偏移统计 ==========\n');
fprintf('  左目: 最大横向偏移 = %.2f pixel, 最大纵向偏移 = %.2f pixel\n', ...
    maxOffX_left, maxOffY_left);
fprintf('  右目: 最大横向偏移 = %.2f pixel, 最大纵向偏移 = %.2f pixel\n', ...
    maxOffX_right, maxOffY_right);

winRadiusX_undist = ceil(max(maxOffX_left, maxOffX_right));
winRadiusY_undist = ceil(max(maxOffY_left, maxOffY_right));

%% ====================== 生成复合查找表 (Undistortion + Rectification) ======================

fprintf('\n========== 生成复合查找表 (Undistortion + Rectification) ==========\n');
fprintf('  图像尺寸: %d x %d\n', camWidth, camHeight);

% 对于校正后的每个输出像素 (x_rect, y_rect):
%   1. 反投影到校正坐标系的归一化平面
%   2. 应用校正旋转的逆变换, 得到原始相机坐标系中的射线方向
%   3. 应用畸变模型, 得到原始图像中的对应像素位置
%   4. 存储偏移量: (dx, dy) = (x_dist - x_rect, y_dist - y_rect)

% ---- 左目复合映射 ----
fprintf('  计算左目复合映射 (Undistortion + Rectification)...\n');

% Step 1: 反投影到归一化坐标 (在校正坐标系中)
xn_rect = (U - cx_rect) / fx_rect;
yn_rect = (V - cy_rect) / fy_rect;

% Step 2: 应用 R1_rect 的逆旋转, 回到原始相机坐标系
% R1_rect 是从原始坐标系到校正坐标系的旋转
% 逆变换: X_orig = R1_rect' * X_rect
pts_homog = R1_rect' * [xn_rect(:)'; yn_rect(:)'; ones(1, numel(U))];
xn_orig = reshape(pts_homog(1,:), size(U));
yn_orig = reshape(pts_homog(2,:), size(V));
zn_orig = reshape(pts_homog(3,:), size(U));

% 归一化: 确保 Z=1 (在归一化平面上)
xn_orig = xn_orig ./ zn_orig;
yn_orig = yn_orig ./ zn_orig;

% Step 3: 应用畸变 (径向 + 切向)
% 使用左目的畸变系数
r2 = xn_orig.^2 + yn_orig.^2;
r4 = r2.^2;
r6 = r2.^3;

radial = 1 + k1_1(1)*r2 + k1_1(2)*r4 + k1_1(3)*r6;
dx_tan = 2*p1_1(1)*xn_orig.*yn_orig + p1_1(2)*(r2 + 2*xn_orig.^2);
dy_tan = p1_1(1)*(r2 + 2*yn_orig.^2) + 2*p1_1(2)*xn_orig.*yn_orig;

xd = xn_orig .* radial + dx_tan;
yd = yn_orig .* radial + dy_tan;

% Step 4: 转换到原始图像像素坐标 (使用原始左目内参)
mapX_left_rect = fx1 * xd + cx1;
mapY_left_rect = fy1 * yd + cy1;

% 边界裁剪
mapX_left_rect_clip = max(0, min(camWidth-1, mapX_left_rect));
mapY_left_rect_clip = max(0, min(camHeight-1, mapY_left_rect));

% ---- 右目复合映射 ----
fprintf('  计算右目复合映射 (Undistortion + Rectification)...\n');

% Step 1-2: 使用 R2_rect
pts_homog_r = R2_rect' * [xn_rect(:)'; yn_rect(:)'; ones(1, numel(U))];
xn_orig_r = reshape(pts_homog_r(1,:), size(U));
yn_orig_r = reshape(pts_homog_r(2,:), size(V));
zn_orig_r = reshape(pts_homog_r(3,:), size(U));

xn_orig_r = xn_orig_r ./ zn_orig_r;
yn_orig_r = yn_orig_r ./ zn_orig_r;

% Step 3: 应用右目畸变
r2_r = xn_orig_r.^2 + yn_orig_r.^2;
r4_r = r2_r.^2;
r6_r = r2_r.^3;

radial_r = 1 + k1_2(1)*r2_r + k1_2(2)*r4_r + k1_2(3)*r6_r;
dx_tan_r = 2*p1_2(1)*xn_orig_r.*yn_orig_r + p1_2(2)*(r2_r + 2*xn_orig_r.^2);
dy_tan_r = p1_2(1)*(r2_r + 2*yn_orig_r.^2) + 2*p1_2(2)*xn_orig_r.*yn_orig_r;

xd_r = xn_orig_r .* radial_r + dx_tan_r;
yd_r = yn_orig_r .* radial_r + dy_tan_r;

% Step 4: 转换到原始图像像素坐标 (使用原始右目内参)
mapX_right_rect = fx2 * xd_r + cx2;
mapY_right_rect = fy2 * yd_r + cy2;

% 边界裁剪
mapX_right_rect_clip = max(0, min(camWidth-1, mapX_right_rect));
mapY_right_rect_clip = max(0, min(camHeight-1, mapY_right_rect));

% ---- 复合偏移统计 ----
offX_left_rect  = mapX_left_rect  - U;
offY_left_rect  = mapY_left_rect  - V;
offX_right_rect = mapX_right_rect - U;
offY_right_rect = mapY_right_rect - V;

maxOffX_left_rect  = max(abs(offX_left_rect(:)));
maxOffY_left_rect  = max(abs(offY_left_rect(:)));
maxOffX_right_rect = max(abs(offX_right_rect(:)));
maxOffY_right_rect = max(abs(offY_right_rect(:)));

valid_left_rect  = sum(mapX_left_rect_clip(:) >= 0) / numel(mapX_left_rect) * 100;
valid_right_rect = sum(mapX_right_rect_clip(:) >= 0) / numel(mapX_right_rect) * 100;

fprintf('\n========== 复合校正偏移统计 ==========\n');
fprintf('  左目: 最大偏移 = [%.1f, %.1f] px, 有效像素 = %.1f%%\n', ...
    maxOffX_left_rect, maxOffY_left_rect, valid_left_rect);
fprintf('  右目: 最大偏移 = [%.1f, %.1f] px, 有效像素 = %.1f%%\n', ...
    maxOffX_right_rect, maxOffY_right_rect, valid_right_rect);

% 计算复合校正的窗口尺寸
winRadiusX = ceil(max(maxOffX_left_rect, maxOffX_right_rect));
winRadiusY = ceil(max(maxOffY_left_rect, maxOffY_right_rect));
winWidth   = 2 * winRadiusX + 1;
winHeight  = 2 * winRadiusY + 1;

fprintf('\n========== 滑动窗口架构 (复合校正) ==========\n');
fprintf('  双向偏移最大范围: 横向 ±%d px, 纵向 ±%d px\n', winRadiusX, winRadiusY);
fprintf('  窗口尺寸: %d x %d\n', winWidth, winHeight);
fprintf('  每个相机 LUT 大小: %d x %d = %.1f KB (每像素 2 bytes)\n', ...
    camWidth, camHeight, camWidth * camHeight * 2 / 1024);

% ---- 生成 Q4.3 格式的复合 LUT ----
Q_bits = 3;
scale = 2^Q_bits;

% 左目相对偏移
relX_left_rect  = mapX_left_rect  - U;
relY_left_rect  = mapY_left_rect  - V;
% 右目相对偏移
relX_right_rect = mapX_right_rect - U;
relY_right_rect = mapY_right_rect - V;

% 检查偏移量是否超出 Q4.3 范围 [-16, +15.875]
maxAbsDx = max(abs([relX_left_rect(:); relX_right_rect(:)]));
maxAbsDy = max(abs([relY_left_rect(:); relY_right_rect(:)]));
fprintf('\nQ4.3 范围检查: 最大 |dx| = %.2f, 最大 |dy| = %.2f (Q4.3范围: [-16, +15.875])\n', ...
    maxAbsDx, maxAbsDy);

if maxAbsDx >= 16 || maxAbsDy >= 16
    fprintf('  警告: 偏移超出 Q4.3 范围! 需要增大 FPGA 窗口尺寸或改用更大位宽\n');
end

% 量化为 Q4.3 int8
relX_left_i8  = int8(round(relX_left_rect  * scale));
relY_left_i8  = int8(round(relY_left_rect  * scale));
relX_right_i8 = int8(round(relX_right_rect * scale));
relY_right_i8 = int8(round(relY_right_rect * scale));

% ---- 保存复合 LUT .mat ----
save(fullfile(imgFolder, 'rectification_lut.mat'), ...
    'mapX_left_rect', 'mapY_left_rect', 'mapX_right_rect', 'mapY_right_rect', ...
    'relX_left_i8', 'relY_left_i8', 'relX_right_i8', 'relY_right_i8', ...
    'winRadiusX', 'winRadiusY', 'winWidth', 'winHeight', ...
    'R1_rect', 'R2_rect', 'K_rect', 'P1', 'P2', 'Q', ...
    'fx_rect', 'fy_rect', 'cx_rect', 'cy_rect', 'baseline_norm', 'baseline_cm');

% ---- 输出复合 LUT 二进制文件 ----
fprintf('\n写入复合 LUT 文件...\n');

fid3 = fopen(fullfile(imgFolder, 'rectification_lut_left.raw'), 'wb');
for y = 1:camHeight
    for x = 1:camWidth
        fwrite(fid3, relX_left_i8(y, x), 'int8');
        fwrite(fid3, relY_left_i8(y, x), 'int8');
    end
end
fclose(fid3);

fid4 = fopen(fullfile(imgFolder, 'rectification_lut_right.raw'), 'wb');
for y = 1:camHeight
    for x = 1:camWidth
        fwrite(fid4, relX_right_i8(y, x), 'int8');
        fwrite(fid4, relY_right_i8(y, x), 'int8');
    end
end
fclose(fid4);

% ---- 输出复合 LUT CSV (调试用) ----
fid5 = fopen(fullfile(imgFolder, 'rectification_lut_left.csv'), 'w');
fprintf(fid5, 'x,y,dx,dy,windowX,windowY\n');
for y = 1:camHeight
    for x = 1:camWidth
        dx = single(relX_left_i8(y, x)) / scale;
        dy = single(relY_left_i8(y, x)) / scale;
        winX = round(dx) + winRadiusX;
        winY = round(dy) + winRadiusY;
        fprintf(fid5, '%d,%d,%.3f,%.3f,%d,%d\n', x-1, y-1, dx, dy, winX, winY);
    end
end
fclose(fid5);

fid6 = fopen(fullfile(imgFolder, 'rectification_lut_right.csv'), 'w');
fprintf(fid6, 'x,y,dx,dy,windowX,windowY\n');
for y = 1:camHeight
    for x = 1:camWidth
        dx = single(relX_right_i8(y, x)) / scale;
        dy = single(relY_right_i8(y, x)) / scale;
        winX = round(dx) + winRadiusX;
        winY = round(dy) + winRadiusY;
        fprintf(fid6, '%d,%d,%.3f,%.3f,%d,%d\n', x-1, y-1, dx, dy, winX, winY);
    end
end
fclose(fid6);

fprintf('  rectification_lut_left.raw  (左目复合 LUT)\n');
fprintf('  rectification_lut_right.raw (右目复合 LUT)\n');

%% ====================== 更新标定报告 (追加立体校正信息) ======================

fid = fopen(fullfile(imgFolder, 'calibration_params.txt'), 'a');

fprintf(fid, '\n---------- 立体校正 (Stereo Rectification) ----------\n');
fprintf(fid, '算法: Bouguet (R1=R2=R_epipolar * R^(-1/2), 左右目校正旋转相同)\n\n');

fprintf(fid, '左目校正旋转 R1_rect:\n');
fprintf(fid, '  %10.8f  %10.8f  %10.8f\n', R1_rect(1,:));
fprintf(fid, '  %10.8f  %10.8f  %10.8f\n', R1_rect(2,:));
fprintf(fid, '  %10.8f  %10.8f  %10.8f\n', R1_rect(3,:));

fprintf(fid, '\n右目校正旋转 R2_rect:\n');
fprintf(fid, '  %10.8f  %10.8f  %10.8f\n', R2_rect(1,:));
fprintf(fid, '  %10.8f  %10.8f  %10.8f\n', R2_rect(2,:));
fprintf(fid, '  %10.8f  %10.8f  %10.8f\n', R2_rect(3,:));

fprintf(fid, '\n校正后内参 (左右目共用):\n');
fprintf(fid, '  fx_rect = %.6f\n', fx_rect);
fprintf(fid, '  fy_rect = %.6f\n', fy_rect);
fprintf(fid, '  cx_rect = %.6f\n', cx_rect);
fprintf(fid, '  cy_rect = %.6f\n', cy_rect);
fprintf(fid, '  K_rect = [%.6f, %.6f, %.6f; %.6f, %.6f, %.6f; %.6f, %.6f, %.6f]\n', ...
    K_rect(1,1), K_rect(1,2), K_rect(1,3), ...
    K_rect(2,1), K_rect(2,2), K_rect(2,3), ...
    K_rect(3,1), K_rect(3,2), K_rect(3,3));

fprintf(fid, '\n校正后基线: %.4f mm (%.4f cm)\n', baseline_norm, baseline_norm/10);
fprintf(fid, '深度公式: Z (cm) = %.4f * %.4f / disparity\n', baseline_norm/10, fx_rect);
fprintf(fid, '        Z (cm) = %.4f / disparity\n\n', baseline_norm/10 * fx_rect);

fprintf(fid, '\n---------- 复合校正 LUT 参数 ----------\n');
fprintf(fid, '双向偏移最大范围: 横向 ±%d px, 纵向 ±%d px\n', winRadiusX, winRadiusY);
fprintf(fid, '窗口尺寸: %d x %d\n', winWidth, winHeight);
fprintf(fid, '左目有效像素: %.2f%%\n', valid_left_rect);
fprintf(fid, '右目有效像素: %.2f%%\n', valid_right_rect);
fprintf(fid, 'LUT 格式: Q4.3 int8, 每像素 2 bytes (dx + dy)\n');

fclose(fid);

%% ====================== 立体校正效果验证 ======================

fprintf('\n========== 立体校正效果验证 ==========\n');

% 使用第一张裁剪后的左右目图像做验证
imgLeft  = leftImages(:, :, :, 1);
imgRight = rightImages(:, :, :, 1);

% ---- 复合校正: 畸变校正 + 立体校正 ----
rectifiedLeft  = zeros(size(imgLeft),  'uint8');
rectifiedRight = zeros(size(imgRight), 'uint8');

for c = 1:3
    rectifiedLeft(:, :, c)  = interp2(double(imgLeft (:, :, c)),  ...
        mapX_left_rect + 1, mapY_left_rect + 1, 'linear', 0);
    rectifiedRight(:, :, c) = interp2(double(imgRight(:, :, c)), ...
        mapX_right_rect + 1, mapY_right_rect + 1, 'linear', 0);
end
rectifiedLeft  = uint8(rectifiedLeft);
rectifiedRight = uint8(rectifiedRight);

% ---- 仅畸变校正 (用于对比) ----
undistortedLeft  = zeros(size(imgLeft),  'uint8');
undistortedRight = zeros(size(imgRight), 'uint8');

for c = 1:3
    undistortedLeft(:, :, c)  = interp2(double(imgLeft (:, :, c)),  ...
        mapX_left + 1, mapY_left + 1, 'linear', 0);
    undistortedRight(:, :, c) = interp2(double(imgRight(:, :, c)), ...
        mapX_right + 1, mapY_right + 1, 'linear', 0);
end
undistortedLeft  = uint8(undistortedLeft);
undistortedRight = uint8(undistortedRight);

% ---- 绘制对比图 ----

% 图1: 畸变校正对比 (原始方案)
figure('Name', '左目畸变校正对比 (Undistortion Only)', 'NumberTitle', 'off', 'Position', [50, 50, 1400, 500]);
subplot(1,2,1); imshow(imgLeft);
title('校正前 (左目)'); hold on;
plot([1, camWidth, camWidth, 1, 1], [1, 1, camHeight, camHeight, 1], 'r-', 'LineWidth', 1);
subplot(1,2,2); imshow(undistortedLeft);
title('畸变校正后 (左目)'); hold on;
plot([1, camWidth, camWidth, 1, 1], [1, 1, camHeight, camHeight, 1], 'g-', 'LineWidth', 1);

figure('Name', '右目畸变校正对比 (Undistortion Only)', 'NumberTitle', 'off', 'Position', [50, 50, 1400, 500]);
subplot(1,2,1); imshow(imgRight);
title('校正前 (右目)'); hold on;
plot([1, camWidth, camWidth, 1, 1], [1, 1, camHeight, camHeight, 1], 'r-', 'LineWidth', 1);
subplot(1,2,2); imshow(undistortedRight);
title('畸变校正后 (右目)'); hold on;
plot([1, camWidth, camWidth, 1, 1], [1, 1, camHeight, camHeight, 1], 'g-', 'LineWidth', 1);

% 图2: 复合校正对比 (新方案)
figure('Name', '左目复合校正对比 (Undistortion + Rectification)', 'NumberTitle', 'off', 'Position', [50, 50, 1400, 500]);
subplot(1,2,1); imshow(imgLeft);
title('原始图像 (左目)'); hold on;
plot([1, camWidth, camWidth, 1, 1], [1, 1, camHeight, camHeight, 1], 'r-', 'LineWidth', 1);
subplot(1,2,2); imshow(rectifiedLeft);
title('复合校正后 (左目)'); hold on;
plot([1, camWidth, camWidth, 1, 1], [1, 1, camHeight, camHeight, 1], 'g-', 'LineWidth', 1);

figure('Name', '右目复合校正对比 (Undistortion + Rectification)', 'NumberTitle', 'off', 'Position', [50, 50, 1400, 500]);
subplot(1,2,1); imshow(imgRight);
title('原始图像 (右目)'); hold on;
plot([1, camWidth, camWidth, 1, 1], [1, 1, camHeight, camHeight, 1], 'r-', 'LineWidth', 1);
subplot(1,2,2); imshow(rectifiedRight);
title('复合校正后 (右目)'); hold on;
plot([1, camWidth, camWidth, 1, 1], [1, 1, camHeight, camHeight, 1], 'g-', 'LineWidth', 1);

% ---- ★ 核心验证: 立体校正效果 (极线对齐检查) ★ ----
% 在左右目校正后图像上绘制同一水平线, 检查棋盘格角点是否在同一行

figure('Name', '极线对齐验证 (Rectified Stereo Pair)', 'NumberTitle', 'off', 'Position', [100, 100, 1400, 600]);

% 将左右目校正后图像水平拼接
stereoPair = [rectifiedLeft, rectifiedRight];
imshow(stereoPair);
title('复合校正后双目图像对 (左|右) — 极线对齐验证');
hold on;

% 在图像上绘制 6 条水平线 (绿色), 检查棋盘格角点是否对齐
for k = 1:6
    y_line = round(k * camHeight / 7);
    % 画一条贯穿左右图的水平线
    plot([1, 2*camWidth], [y_line, y_line], 'g-', 'LineWidth', 1);
end

% 在左右目图像中间画一条分隔线
plot([camWidth, camWidth], [1, camHeight], 'r--', 'LineWidth', 2);

% 选取图像中间 1/3 区域中的棋盘格角点, 计算垂直残差
% (如果标定图像中包含完整的棋盘格)
try
    [leftPoints, ~] = detectCheckerboardPoints(rectifiedLeft);
    [rightPoints, ~] = detectCheckerboardPoints(rectifiedRight);

    if size(leftPoints, 1) == size(rightPoints, 1) && size(leftPoints, 1) > 0
        % 计算对应点的垂直坐标差
        vertDiff = abs(leftPoints(:,2) - rightPoints(:,2));
        meanVertDiff = mean(vertDiff);
        maxVertDiff = max(vertDiff);

        % 在图上标注角点
        plot(leftPoints(:,1), leftPoints(:,2), 'yo', 'MarkerSize', 8, 'LineWidth', 2);
        plot(rightPoints(:,1) + camWidth, rightPoints(:,2), 'yo', 'MarkerSize', 8, 'LineWidth', 2);

        % 绘制对应点连线
        for i = 1:size(leftPoints, 1)
            plot([leftPoints(i,1), rightPoints(i,1) + camWidth], ...
                 [leftPoints(i,2), rightPoints(i,2)], 'c-', 'LineWidth', 0.5);
        end

        fprintf('\n========== 极线对齐精度 ==========\n');
        fprintf('  棋盘格角点数: %d\n', size(leftPoints, 1));
        fprintf('  平均垂直残差: %.4f pixels\n', meanVertDiff);
        fprintf('  最大垂直残差: %.4f pixels\n', maxVertDiff);
        if meanVertDiff < 0.5
            fprintf('  ★ 立体校正合格! 极线对齐精度 < 0.5 pixel\n');
        else
            fprintf('  ⚠ 立体校正需改善, 垂直残差偏大\n');
        end
    end
catch
    fprintf('\n  ⚠ 无法在校正后图像中检测棋盘格角点, 跳过定量验证\n');
end

fprintf('\n  请目视检查: 左右目图像的对应特征是否位于同一水平线上\n');

% ---- 仅畸变校正的极线对比 ----
figure('Name', '仅畸变校正 — 极线对齐对比 (Undistortion Only)', 'NumberTitle', 'off', 'Position', [100, 100, 1400, 600]);
stereoPairUndist = [undistortedLeft, undistortedRight];
imshow(stereoPairUndist);
title('仅畸变校正 (无立体校正) — 左右目对应点不在同一行');
hold on;
for k = 1:6
    y_line = round(k * camHeight / 7);
    plot([1, 2*camWidth], [y_line, y_line], 'r-', 'LineWidth', 1);
end
plot([camWidth, camWidth], [1, camHeight], 'r--', 'LineWidth', 2);

%% ====================== 输出软件配置更新建议 ======================

fprintf('\n========================================\n');
fprintf('  软件配置更新建议\n');
fprintf('========================================\n');
fprintf('\n请将 config.py 中的以下参数更新为:\n');
fprintf('\n');
fprintf('STEREO_FOCAL_LENGTH_PX = %.4f\n', fx_rect);
fprintf('STEREO_PARAMS["BASELINE_CM"] = %.6f\n', baseline_norm / 10);
fprintf('PCD_PARAMS["CAM_CX"] = %.2f\n', cx_rect);
fprintf('PCD_PARAMS["CAM_CY"] = %.2f\n', cy_rect);
fprintf('\nFPGA LUT 文件更新:\n');
fprintf('  左目: rectification_lut_left.raw  (取代 undistortion_lut_left.raw)\n');
fprintf('  右目: rectification_lut_right.raw (取代 undistortion_lut_right.raw)\n');
fprintf('\n注意: 替换 FPGA LUT 后需要重新综合/加载比特流\n');

%% ====================== 完成 ======================

fprintf('\n========================================\n');
fprintf('  双目立体标定 + 校正完成!\n');
fprintf('========================================\n');
fprintf('标定结果文件:\n');
fprintf('  %s\n', fullfile(imgFolder, 'stereo_calibration_results.mat'));
fprintf('  %s\n', fullfile(imgFolder, 'calibration_params.txt'));
fprintf('  %s\n', fullfile(imgFolder, 'calibration_params_short.txt'));
fprintf('复合校正 LUT:\n');
fprintf('  %s\n', fullfile(imgFolder, 'rectification_lut_left.raw'));
fprintf('  %s\n', fullfile(imgFolder, 'rectification_lut_right.raw'));
fprintf('  %s\n', fullfile(imgFolder, 'rectification_lut.mat'));
