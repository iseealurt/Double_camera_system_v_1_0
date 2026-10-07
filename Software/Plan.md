# 配套上位机软件开发计划 
## 开发语言：Python
## 源码存放位置：Software/Source_Code，如果文件夹不存在，则自行创建
## 1. 功能需求
### 输入：
#### 1. 从GUI里选择要接入的摄像头，将原始图像显示在GUI里。
#### 2. 根据FPGA内部设置的偏移量，从1080P画面里截取对应的两个摄像头各自的480P图像。
        localparam CMR_1_DISP_AREA_H_OFST = 12'd160;
        localparam CMR_1_DISP_AREA_V_OFST = 12'd32;
        localparam CMR_2_DISP_AREA_H_OFST = 12'd1120;
        localparam CMR_2_DISP_AREA_V_OFST = 12'd32;
#### 根据以上偏移量设置，可知以(160,32)和(1120,32)为起始点，分别截取左右目摄像头输出的480P图像，
#### 3. 点击“连接”按钮后，将左右目摄像头输出的480P图像显示在GUI里。

