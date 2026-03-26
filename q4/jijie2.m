%数据提取和整理 
data={'芥菜',1.826;'青杭椒(1)',1.176;'菌蔬四宝(份)',1;'活体银耳',1;'猴头菇',1;'海鲜菇(袋)(1)',1;'虫草花(盒)(2)',1;'甘蓝叶',0.943;'水果辣椒(橙色)',0.415;'冰草',0.318 };
%分离品类和数值
categories=data (:,1);
values=cell2mat (data (:,2));
%创建条形图
figure ('Position',[100,100,1000,600])
bar (values)
set (gca,'XTick',1:length (categories),'XTickLabel',categories)
xtickangle (45)
ylabel (' 数值')
title (' 蔬菜品类数值统计')
%添加数值标签
text (1:length (values),values,num2str (values,'%.3f'),...
'HorizontalAlignment','center',...
'VerticalAlignment','bottom',...
'FontSize',9)
%调整布局
set (gcf,'Color','w')
set (gca,'FontSize',10)
grid on
%设置 Y 轴格式，避免科学计数法
ytickformat ('%.2f')
%调整 Y 轴范围，使数据更清晰可见
ylim ([0 max(values)*1.1])