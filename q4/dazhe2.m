%数据提取和整理
data={
'蟹味菇 (1)',3;
'蟹味菇 (盒)',3;
'杏鲍菇 (袋)',3;
'黑牛肝菌',2;
'红尖椒',2;
'黄花菜',2;
'金针菇 (袋)(3)',2;
'净藕 (2)',2;
'双孢菇 (份)',2;
'随州泡泡青',2;
'猪肚菇 (盒)',2;
'白玉菇 (盒)',1;
'灯笼椒 (份)',1;
'黑皮鸡枞菌',1;
'黑皮鸡枞菌 (盒)',1;
'七彩椒 (份)',1;
'圆茄子 (2)',1;
'长线茄',1;
'紫贝菜',1;
'紫螺丝椒',1
};
%分离品类和数量
categories=data (:,1);
values=cell2mat (data (:,2));
%创建条形图
figure ('Position',[100,100,1400,700])
bar (values)
set (gca,'XTick',1:length (categories),'XTickLabel',categories)
xtickangle (45)
ylabel ('数量')
title ('蔬菜品类数量统计')
%添加数值标签
text (1:length (values),values,num2str (values),...
'HorizontalAlignment','center',...
'VerticalAlignment','bottom',...
'FontSize',8)
%调整布局
set (gcf,'Color','w')
set (gca,'FontSize',9)
grid on
%设置 Y 轴格式，避免科学计数法
ytickformat ('%.0f')
%设置 Y 轴范围，使数据更清晰可见
ylim ([0 max(values)+1])