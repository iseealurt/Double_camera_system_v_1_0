import os
import tkinter as tk
from tkinter import filedialog, messagebox

def process_files():
    """
    核心逻辑函数：
    1. 打开文件夹选择框
    2. 递归搜索 .v 文件
    3. 打开保存文件对话框
    4. 按指定格式写入 txt
    """
    
    # --- 1. 选择要处理的文件夹 ---
    source_folder = filedialog.askdirectory(title="第一步：请选择要搜索的文件夹")
    
    if not source_folder:
        # 用户取消了选择
        return

    # --- 2. 搜索文件夹及子文件夹内所有 .v 文件 ---
    v_file_paths = []
    
    # os.walk 会递归遍历目录树
    for root, dirs, files in os.walk(source_folder):
        for file in files:
            # 检查后缀名是否为 .v (忽略大小写)
            if file.lower().endswith('.v'):
                # 获取绝对路径
                full_path = os.path.join(root, file)
                # 你的示例中路径分隔符是 "/" (E:/FPGA...), Windows默认是 "\", 这里统一替换为 "/"
                full_path = full_path.replace('\\', '/')
                v_file_paths.append(full_path)

    if not v_file_paths:
        messagebox.showinfo("提示", "在该文件夹及其子文件夹中未找到任何 .v 文件。")
        return

    # --- 3. 用户选择输出 txt 的位置 ---
    output_file = filedialog.asksaveasfilename(
        title="第二步：请选择保存结果的位置",
        defaultextension=".txt",
        filetypes=[("Text Files", "*.txt"), ("All Files", "*.*")]
    )

    if not output_file:
        return

    # --- 4. 写入文件，处理格式 ---
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            total_files = len(v_file_paths)
            
            for index, path in enumerate(v_file_paths):
                # 基础格式: "路径"
                line = f'"{path}"'
                
                # 如果不是最后一个文件，后面加上反斜杠 \
                if index < total_files - 1:
                    line += '\\'
                
                # 写入并换行
                f.write(line + '\n')
        
        messagebox.showinfo("成功", f"处理完成！\n\n共找到 {total_files} 个文件。\n列表已保存至:\n{output_file}")

    except Exception as e:
        messagebox.showerror("错误", f"写入文件时发生错误:\n{e}")

def create_gui():
    """创建主窗口 GUI"""
    root = tk.Tk()
    root.title("Verilog文件路径生成器")
    root.geometry("400x200")
    
    # 简单的布局
    label_desc = tk.Label(root, text="功能：搜索文件夹下所有.v文件并生成路径列表", pady=20)
    label_desc.pack()

    btn_start = tk.Button(root, text="开始处理", command=process_files, font=("Arial", 12), bg="#dddddd", padx=20, pady=10)
    btn_start.pack()

    label_tip = tk.Label(root, text="点击上方按钮开始选择文件夹", fg="gray", pady=20)
    label_tip.pack()

    root.mainloop()

if __name__ == "__main__":
    create_gui()
