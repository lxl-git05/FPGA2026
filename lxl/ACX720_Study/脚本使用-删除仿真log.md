先关闭 Vivado，然后打开 PowerShell，依次执行：

```
cd D:\github\FPGA2026\FPGA2026\lxl\ACX720_Study
```

先预览将要删除的内容：

```
.\clean_vivado_sim.ps1
```

确认列表无误后，真正清理：

```
.\clean_vivado_sim.ps1 -Apply
```

如果 PowerShell 提示“禁止运行脚本”，使用下面这条命令。它只对本次运行临时放行，不修改系统设置：

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\clean_vivado_sim.ps1 -Apply
```

运行完成后会显示成功删除的目录数量和释放的空间。不要双击脚本，否则窗口可能执行完立即关闭，不便查看结果。